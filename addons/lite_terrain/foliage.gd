@tool
extends RefCounted

const LIMIT := 5000

static func bounds_points(node: Node, transform: Transform3D = Transform3D.IDENTITY) -> PackedVector3Array:
	var points := PackedVector3Array()
	var local := transform
	if node is Node3D: local = transform * node.transform
	if node is MeshInstance3D and node.mesh:
		var bounds: AABB = node.mesh.get_aabb()
		for i in 8: points.append(local * bounds.get_endpoint(i))
	for child in node.get_children(): points.append_array(bounds_points(child, local))
	return points

static func orientation(terrain: Node3D, record: Dictionary) -> Transform3D:
	var point: Vector2 = record.point
	var normal: Vector3 = terrain.terrain_normal_at(point.x, point.y) if terrain.foliage_align_slope else Vector3.UP
	var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, float(record.yaw))
	basis = basis.scaled(Vector3.ONE * float(record.size))
	return Transform3D(basis, Vector3(point.x, terrain.surface_height(point.x, point.y) + terrain.foliage_ground_offset, point.y))

static func card_mesh(texture: Texture2D) -> ArrayMesh:
	# Trim transparent image padding so the visible blade starts at ground level.
	var rect := Rect2(0, 0, 1, 1)
	var source := texture.get_image() if texture else null
	if source:
		if source.is_compressed(): source.decompress()
		var used := source.get_used_rect()
		if used.has_area(): rect = Rect2(Vector2(used.position) / Vector2(source.get_size()), Vector2(used.size) / Vector2(source.get_size()))
	var u0 := rect.position.x
	var v0 := rect.position.y
	var u1 := rect.end.x
	var v1 := rect.end.y
	var vertices := PackedVector3Array([Vector3(-0.5,0,0),Vector3(0.5,0,0),Vector3(0.5,1,0),Vector3(-0.5,1,0),Vector3(0,0,-0.5),Vector3(0,0,0.5),Vector3(0,1,0.5),Vector3(0,1,-0.5)])
	var normals := PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	var uv := PackedVector2Array([Vector2(u0,v1),Vector2(u1,v1),Vector2(u1,v0),Vector2(u0,v0),Vector2(u0,v1),Vector2(u1,v1),Vector2(u1,v0),Vector2(u0,v0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3,4,5,6,4,6,7])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.albedo_texture = texture
	if source and not source.has_mipmaps():
		if source.generate_mipmaps() == OK: mat.albedo_texture = ImageTexture.create_from_image(source)
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	return mesh

static func scene_ranges(node: Node, end: float) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = end
		node.visibility_range_end_margin = 2.0
	for child in node.get_children(): scene_ranges(child, end)

static func batch(parent: Node3D, mesh: Mesh, transforms: Array, origin: Vector3, begin: float, end: float) -> void:
	if transforms.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		var transform: Transform3D = transforms[i]
		transform.origin -= origin
		multi.set_instance_transform(i, transform)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.position = origin
	instance.visibility_range_begin = begin
	instance.visibility_range_end = end
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

static func rebuild(terrain: Node3D) -> void:
	var old := terrain.get_node_or_null("Foliage")
	if old:
		terrain.remove_child(old)
		old.queue_free()
	if terrain.data == null or terrain.foliage_mode == 0: return
	var root := Node3D.new()
	root.name = "Foliage"
	terrain.add_child(root)
	var groups := {}
	var meshes := {}
	for record in terrain.data.foliage:
		var p: Vector2 = record.point
		if p.x < 0 or p.y < 0 or p.x > terrain.data.resolution - 1 or p.y > terrain.data.resolution - 1: continue
		var transform := orientation(terrain, record)
		if record.mode == 2:
			var scene: PackedScene = record.get("scene")
			if scene == null: continue
			var item := scene.instantiate()
			if not item is Node3D:
				item.free()
				continue
			var wrapper := Node3D.new()
			var points := bounds_points(item)
			var bottom := 0.0
			if not points.is_empty():
				bottom = INF
				for point in points: bottom = minf(bottom, point.y)
			# Retain authored child transforms; shift along the aligned up axis.
			item.position.y -= bottom
			wrapper.transform = transform
			wrapper.add_child(item)
			scene_ranges(item, terrain.foliage_lod_distance)
			root.add_child(wrapper)
		else:
			var texture: Texture2D = record.get("texture")
			if texture == null: texture = terrain.default_grass()
			var id := texture.get_instance_id()
			var tile := Vector2i(floori(p.x / 16), floori(p.y / 16))
			var key := "%d_%d_%d" % [id, tile.x, tile.y]
			if not meshes.has(id): meshes[id] = card_mesh(texture)
			if not groups.has(key): groups[key] = {"mesh": meshes[id], "transforms": [], "origin": Vector3(tile.x * 16 + 8, 0, tile.y * 16 + 8)}
			groups[key].transforms.append(transform)
	for group in groups.values():
		var transforms: Array = group.transforms
		var far: Array = []
		for i in range(0, transforms.size(), 3): far.append(transforms[i])
		var split: float = terrain.foliage_lod_distance * 0.55
		batch(root, group.mesh, transforms, group.origin, 0, split)
		batch(root, group.mesh, far, group.origin, split, terrain.foliage_lod_distance)
