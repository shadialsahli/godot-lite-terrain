@tool
extends Node3D

const Data = preload("terrain_data.gd")
const Foliage = preload("foliage.gd")
const Generator = preload("generator.gd")
const CHUNK := 32
@export var data: Resource
@export var textures: Array[Texture2D] = []:
	set(value):
		textures = value
		if is_inside_tree():
			update_material()
@export_group("النباتات والعشب | Foliage / Grass")
@export_enum("Off / معطل", "Texture X / خامة X", "PackedScene / مشهد") var foliage_mode: int = 0:
	set(value):
		foliage_mode = value
		queue_foliage_refresh()
@export var foliage_texture: Texture2D:
	set(value):
		foliage_texture = value
		queue_foliage_refresh()
@export var foliage_scene: PackedScene:
	set(value):
		foliage_scene = value
		queue_foliage_refresh()
@export_range(0.0, 1.0, 0.01) var foliage_density: float = 0.08:
	set(value):
		foliage_density = value
		queue_foliage_refresh()
@export_range(0, 5000, 1) var foliage_count: int = 0:
	set(value):
		foliage_count = clampi(value, 0, Foliage.LIMIT)
		if is_node_ready():
			distribute_foliage()
		queue_foliage_refresh()
@export_range(-2.0, 2.0, 0.01, "suffix:m") var foliage_ground_offset: float = -0.02:
	set(value):
		foliage_ground_offset = value
		queue_foliage_refresh()
@export_range(4.0, 512.0, 1.0, "suffix:m") var foliage_lod_distance: float = 48.0:
	set(value):
		foliage_lod_distance = value
		queue_foliage_refresh()
@export var foliage_align_slope := true:
	set(value):
		foliage_align_slope = value
		queue_foliage_refresh()
@export_range(1.0, 12.0, 0.5, "suffix:m") var foliage_spacing: float = 3.0
@export var foliage_seed: int = 1337:
	set(value):
		foliage_seed = value
		if is_node_ready(): distribute_foliage()
		queue_foliage_refresh()
@export_range(0.5, 64.0) var tile_size: float = 4.0:
	set(value):
		tile_size = value
		if material:
			material.set_shader_parameter("tile_size", tile_size)
@export_group("Collision / التصادم")
## Full Map collides everywhere. Around Player updates a smaller patch at runtime.
## كامل الخريطة أو رقعة تصادم تتبع اللاعب أثناء تشغيل اللعبة.
@export_enum("Disabled / معطل", "Full Map / كامل الخريطة", "Around Player / حول اللاعب") var collision_mode: int = 1:
	set(value):
		collision_mode = value
		queue_collision_refresh()
@export_node_path("Node3D") var collision_player: NodePath:
	set(value):
		collision_player = value
		queue_collision_refresh()
@export_range(4, 64, 1, "suffix:m") var collision_radius: int = 16:
	set(value):
		collision_radius = value
		queue_collision_refresh()
@export_flags_3d_physics var terrain_collision_layer: int = 1:
	set(value):
		terrain_collision_layer = value
		queue_collision_refresh()
# Load older scenes without exposing a second conflicting Inspector switch.
@export_storage var collision_enabled: bool = true
var collision_origin := Vector2i(-10000, -10000)
var collision_size := Vector2i.ZERO
var collision_refresh_queued := false
var material: ShaderMaterial
var chunks: Dictionary = {}
var weight_texture: ImageTexture
var defaults: Array[Texture2D] = []
var pending_chunks: Dictionary = {}
var pending_weights := false
var pending_foliage := false
var foliage_refresh_queued := false
var grass_cache: Texture2D

func _ready() -> void:
	process_physics_priority = -100
	if not collision_enabled:
		collision_mode = 0
		collision_enabled = true
	if data == null:
		data = Data.new()
	data.initialize()
	update_material()
	if data.foliage.is_empty() and foliage_count > 0: distribute_foliage()
	rebuild()
	rebuild_foliage()

func queue_collision_refresh() -> void:
	if is_node_ready() and not collision_refresh_queued:
		collision_refresh_queued = true
		call_deferred("rebuild_collision")

func _physics_process(_delta: float) -> void:
	if collision_mode == 2 and not Engine.is_editor_hint():
		var bounds := collision_bounds()
		if bounds.position != collision_origin or bounds.size != collision_size:
			rebuild_collision()

func collision_bounds() -> Rect2i:
	var cells: int = data.resolution - 1
	var player := get_node_or_null(collision_player) as Node3D if not collision_player.is_empty() else null
	# A missing/freed player safely falls back to the whole map.
	if collision_mode != 2 or Engine.is_editor_hint() or not is_instance_valid(player):
		return Rect2i(0, 0, cells, cells)
	var p := to_local(player.global_position)
	var diameter := mini(cells, collision_radius * 2 + 8)
	var x := clampi(int(floor(p.x / 4.0)) * 4 - collision_radius - 4, 0, cells - diameter)
	var z := clampi(int(floor(p.z / 4.0)) * 4 - collision_radius - 4, 0, cells - diameter)
	return Rect2i(x, z, diameter, diameter)

func update_material() -> void:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = preload("terrain.gdshader")
	if defaults.is_empty():
		for color in [Color("557440"), Color("736d65"), Color("bd9d64"), Color("e4e9ed")]:
			var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
			var noise := FastNoiseLite.new()
			noise.frequency = 0.12
			for z in 128:
				for x in 128:
					img.set_pixel(x, z, color * (0.9 + noise.get_noise_2d(x, z) * 0.2))
			img.generate_mipmaps()
			defaults.append(ImageTexture.create_from_image(img))
	for i in 4:
		var tex: Texture2D = defaults[i]
		if i < textures.size() and textures[i] != null:
			tex = textures[i]
			# Imported textures without mipmaps still get an automatic mip chain.
			var source := tex.get_image()
			if source != null and not source.has_mipmaps():
				if source.is_compressed():
					source.decompress()
				if source.generate_mipmaps() == OK:
					tex = ImageTexture.create_from_image(source)
		material.set_shader_parameter("layer_%d" % i, tex)
	material.set_shader_parameter("tile_size", tile_size)
	if data:
		material.set_shader_parameter("terrain_size", float(data.resolution - 1))
		update_weights()

func update_weights() -> void:
	data.initialize()
	material.set_shader_parameter("terrain_size", float(data.resolution - 1))
	var img := Image.create(data.resolution, data.resolution, false, Image.FORMAT_RGBA8)
	for z in data.resolution:
		for x in data.resolution:
			img.set_pixel(x, z, data.weights[z * data.resolution + x])
	if weight_texture == null or weight_texture.get_width() != data.resolution:
		weight_texture = ImageTexture.create_from_image(img)
	else:
		weight_texture.update(img)
	material.set_shader_parameter("weight_map", weight_texture)

func height_at(x: int, z: int) -> float:
	return data.heights[clampi(z, 0, data.resolution - 1) * data.resolution + clampi(x, 0, data.resolution - 1)]

func surface_height(x: float, z: float) -> float:
	x = clampf(x, 0, data.resolution - 1)
	z = clampf(z, 0, data.resolution - 1)
	var ix := int(floor(x))
	var iz := int(floor(z))
	var fx := x - ix
	var fz := z - iz
	# Same diagonal as the collision and render triangles.
	if fx + fz <= 1.0:
		return height_at(ix, iz) + fx * (height_at(ix + 1, iz) - height_at(ix, iz)) + fz * (height_at(ix, iz + 1) - height_at(ix, iz))
	return height_at(ix + 1, iz + 1) + (1.0 - fx) * (height_at(ix, iz + 1) - height_at(ix + 1, iz + 1)) + (1.0 - fz) * (height_at(ix + 1, iz) - height_at(ix + 1, iz + 1))

func rebuild() -> void:
	pending_chunks.clear()
	if material: update_weights()
	for child in get_children():
		if child.has_meta("lite_generated"):
			remove_child(child)
			child.queue_free()
	chunks.clear()
	for z in range(0, data.resolution - 1, CHUNK):
		for x in range(0, data.resolution - 1, CHUNK):
			var mesh_node := MeshInstance3D.new()
			mesh_node.name = "Chunk_%d_%d" % [x, z]
			mesh_node.set_meta("lite_generated", true)
			mesh_node.material_override = material
			# Precise editor picking must match the full-resolution surface.
			if Engine.is_editor_hint(): mesh_node.lod_bias = 128.0
			add_child(mesh_node)
			chunks[Vector2i(x, z)] = mesh_node
			build_chunk(Vector2i(x, z))
	rebuild_collision()

func queue_foliage_refresh() -> void:
	if not is_node_ready() or foliage_refresh_queued: return
	foliage_refresh_queued = true
	call_deferred("rebuild_foliage")

func rebuild_foliage() -> void:
	foliage_refresh_queued = false
	pending_foliage = false
	if is_inside_tree(): Foliage.rebuild(self)

func default_grass() -> Texture2D:
	if grass_cache: return grass_cache
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for blade in 7:
		var base_x := 12 + blade * 6
		var top := 8 + (blade * 7) % 20
		for y in range(top, 64):
			var progress := float(y - top) / (64 - top)
			var center := base_x + int(sin(progress * 2.5 + blade) * (1 - progress) * 9)
			var width := maxi(1, int(progress * 2.5))
			for x in range(maxi(0, center - width), mini(64, center + width + 1)):
				image.set_pixel(x, y, Color(0.16 + blade * 0.012, 0.4 + blade * 0.024, 0.07, 1))
	image.generate_mipmaps()
	grass_cache = ImageTexture.create_from_image(image)
	return grass_cache

func terrain_normal_at(x: float, z: float) -> Vector3:
	var x0 := maxf(0, x - 0.25)
	var x1 := minf(data.resolution - 1, x + 0.25)
	var z0 := maxf(0, z - 0.25)
	var z1 := minf(data.resolution - 1, z + 0.25)
	var dx := (surface_height(x1, z) - surface_height(x0, z)) / maxf(0.001, x1 - x0)
	var dz := (surface_height(x, z1) - surface_height(x, z0)) / maxf(0.001, z1 - z0)
	return Vector3(-dx, 1, -dz).normalized()

func foliage_record(p: Vector2, rng: RandomNumberGenerator, automatic: bool) -> Dictionary:
	return {"point": p, "yaw": rng.randf_range(0, TAU), "size": rng.randf_range(0.8, 1.2),
		"mode": foliage_mode, "texture": foliage_texture, "scene": foliage_scene, "automatic": automatic}

func distribute_foliage() -> void:
	if data == null: return
	var keep: Array[Dictionary] = []
	for record in data.foliage:
		if not record.get("automatic", false): keep.append(record)
	data.foliage = keep
	if foliage_mode != 0 and (foliage_mode != 2 or foliage_scene != null):
		var rng := RandomNumberGenerator.new()
		rng.seed = foliage_seed
		for i in mini(foliage_count, Foliage.LIMIT - data.foliage.size()):
			var p := Vector2(rng.randf_range(0, data.resolution - 1), rng.randf_range(0, data.resolution - 1))
			data.foliage.append(foliage_record(p, rng, true))
	data.emit_changed()
	queue_foliage_refresh()

func paint_foliage(center: Vector3, radius: float, amount: int = 1, erase: bool = false, brush_shape: int = 0) -> void:
	if foliage_mode == 0 or data == null: return
	if erase:
		var keep: Array[Dictionary] = []
		for record in data.foliage:
			if brush_weight(record.point - Vector2(center.x, center.z), radius, brush_shape) <= 0: keep.append(record)
		data.foliage = keep
	else:
		if foliage_mode == 2 and foliage_scene == null: return
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var wanted := mini(clampi(amount, 1, 64), Foliage.LIMIT - data.foliage.size())
		var added := 0
		for attempt in wanted * 16:
			if added >= wanted: break
			var p := Vector2(center.x, center.z) + Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))
			if p.x < 0 or p.y < 0 or p.x > data.resolution - 1 or p.y > data.resolution - 1: continue
			if rng.randf() > brush_weight(p - Vector2(center.x, center.z), radius, brush_shape): continue
			data.foliage.append(foliage_record(p, rng, false))
			added += 1
	pending_foliage = true
	data.emit_changed()

func indices(step: int, _key: Vector2i = Vector2i(-1, -1)) -> PackedInt32Array:
	var result := PackedInt32Array()
	for z in range(0, CHUNK, step):
		for x in range(0, CHUNK, step):
			if step > 1 and (x == 0 or z == 0 or x + step == CHUNK or z + step == CHUNK):
				# Keep every perimeter vertex at all LODs: seamless, without walls.
				var ring := PackedInt32Array()
				for dx in range(0, step, 1 if z == 0 else step):
					ring.append(z * 33 + x + dx)
				for dz in range(0, step, 1 if x + step == CHUNK else step):
					ring.append((z + dz) * 33 + x + step)
				for dx in range(0, step, 1 if z + step == CHUNK else step):
					ring.append((z + step) * 33 + x + step - dx)
				for dz in range(0, step, 1 if x == 0 else step):
					ring.append((z + step - dz) * 33 + x)
				var center := (z + step / 2) * 33 + x + step / 2
				for i in range(ring.size()):
					result.append_array(PackedInt32Array([center, ring[i], ring[(i + 1) % ring.size()]]))
				continue
			var a := z * 33 + x
			var b := a + step
			var c := a + step * 33
			var d := c + step
			result.append_array(PackedInt32Array([a, b, c, b, d, c]))
	return result

func build_chunk(key: Vector2i) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for z in 33:
		for x in 33:
			var gx := key.x + x
			var gz := key.y + z
			vertices.append(Vector3(gx, height_at(gx, gz), gz))
			normals.append(Vector3(height_at(gx - 1, gz) - height_at(gx + 1, gz), 2.0, height_at(gx, gz - 1) - height_at(gx, gz + 1)).normalized())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices(1, key)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {2.0: indices(2, key), 8.0: indices(4, key), 32.0: indices(8, key)})
	chunks[key].mesh = mesh

func rebuild_collision() -> void:
	collision_refresh_queued = false
	if data == null or not is_inside_tree():
		return
	var body := get_node_or_null("TerrainCollision") as StaticBody3D
	if collision_mode == 0 or not collision_enabled:
		if body:
			remove_child(body)
			body.queue_free()
		collision_origin = Vector2i(-10000, -10000)
		return
	if body == null:
		body = StaticBody3D.new()
		body.name = "TerrainCollision"
		body.set_meta("lite_generated", true)
		body.add_child(CollisionShape3D.new())
		add_child(body)
	body.collision_layer = terrain_collision_layer
	var shape_node := body.get_child(0) as CollisionShape3D
	var bounds := collision_bounds()
	var shape := HeightMapShape3D.new()
	shape.map_width = bounds.size.x + 1
	shape.map_depth = bounds.size.y + 1
	if bounds.size.x == data.resolution - 1:
		shape.map_data = data.heights
	else:
		var heights := PackedFloat32Array()
		heights.resize(shape.map_width * shape.map_depth)
		for z in shape.map_depth:
			for x in shape.map_width:
				heights[z * shape.map_width + x] = height_at(bounds.position.x + x, bounds.position.y + z)
		shape.map_data = heights
	# Replace on the existing body before the next physics step, without a gap.
	shape_node.position = Vector3(bounds.position.x + bounds.size.x * 0.5, 0, bounds.position.y + bounds.size.y * 0.5)
	shape_node.shape = shape
	collision_origin = bounds.position
	collision_size = bounds.size

func restore(state: Dictionary) -> void:
	var resized: bool = data.resolution != int(state.get("resolution", roundi(sqrt(state.heights.size()))))
	data.restore(state)
	pending_chunks.clear()
	pending_weights = false
	update_weights()
	if resized: rebuild()
	else:
		for key in chunks: build_chunk(key)
		rebuild_collision()
	rebuild_foliage()

func apply_generated(heights: PackedFloat32Array, resolution: int) -> void:
	var old_n: int = data.resolution
	var old_weights: PackedColorArray = data.weights.duplicate()
	data.resolution = resolution
	data.heights = heights.duplicate()
	data.weights.resize(resolution * resolution)
	for z in resolution:
		for x in resolution:
			var ox := roundi(float(x) / (resolution - 1) * (old_n - 1))
			var oz := roundi(float(z) / (resolution - 1) * (old_n - 1))
			data.weights[z * resolution + x] = old_weights[oz * old_n + ox]
	# Maintain normalized locations when changing the map size.
	var factor := float(resolution - 1) / (old_n - 1)
	for record in data.foliage: record.point *= factor
	pending_chunks.clear()
	update_weights()
	rebuild()
	rebuild_foliage()
	data.emit_changed()

func generate_procedural(seed_value: int, base_height: float, height_range: float, noise_scale: float, roughness: float, octaves: int, erosion_steps: int, erosion_weight: float, target_resolution: int = 0) -> void:
	var p := {"seed": seed_value, "base": base_height, "range": height_range, "scale": noise_scale,
		"roughness": roughness, "octaves": octaves, "erosion": erosion_steps, "erosion_weight": erosion_weight,
		"resolution": target_resolution if target_resolution in [65, 129, 257] else data.resolution}
	apply_generated(Generator.generate(p), int(p.resolution))

func brush_weight(delta: Vector2, radius: float, shape: int) -> float:
	var d := delta.length() / radius
	if shape == 2:
		d = maxf(absf(delta.x), absf(delta.y)) / radius
	elif shape == 3:
		d = (absf(delta.x) + absf(delta.y)) / radius
	if d >= 1.0:
		return 0.0
	if shape == 1:
		return 1.0
	if shape == 4:
		return pow(1.0 - d, 2) * (0.5 + 0.5 * sin(delta.x * 2.1 + sin(delta.y * 1.7)))
	return (1.0 - d * d) * (1.0 - d * d)

func stamp(center: Vector3, radius: float, strength: float, shape: int, tool: int, layer: int, invert: bool, target: float, flush: bool = true) -> void:
	var n: int = data.resolution
	var previous: PackedFloat32Array = data.heights.duplicate() if tool == 2 else PackedFloat32Array()
	var dirty: Dictionary = {}
	for z in range(maxi(0, int(center.z - radius)), mini(n, int(center.z + radius) + 1)):
		for x in range(maxi(0, int(center.x - radius)), mini(n, int(center.x + radius) + 1)):
			var w := brush_weight(Vector2(x - center.x, z - center.z), radius, shape)
			if w <= 0.0:
				continue
			var i := z * n + x
			if tool >= 3:
				var goal := Color(0, 0, 0, 0)
				goal[0 if invert else layer] = 1.0
				data.weights[i] = data.weights[i].lerp(goal, clampf(w * strength * (1.0 if tool == 3 else 0.18), 0, 1))
			else:
				if tool == 0:
					data.heights[i] += w * strength * (-1.0 if invert else 1.0)
				elif tool == 1:
					data.heights[i] = lerpf(data.heights[i], target, clampf(w * strength, 0, 1))
				else:
					var total := 0.0
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							total += previous[clampi(z + dz, 0, n - 1) * n + clampi(x + dx, 0, n - 1)]
					data.heights[i] = lerpf(previous[i], total / 9.0, clampf(w * strength, 0, 1))
				for key in chunks:
					if x >= key.x - 1 and x <= key.x + CHUNK + 1 and z >= key.y - 1 and z <= key.y + CHUNK + 1:
						dirty[key] = true
	if tool >= 3:
		pending_weights = true
	else:
		for key in dirty:
			pending_chunks[key] = true
	if flush:
		flush_changes()
	data.emit_changed()

func flush_changes() -> void:
	if pending_foliage: rebuild_foliage()
	if pending_weights:
		update_weights()
		pending_weights = false
	for key in pending_chunks:
		build_chunk(key)
	pending_chunks.clear()

func raycast(origin: Vector3, direction: Vector3) -> Variant:
	var start := to_local(origin)
	var dir := global_transform.basis.inverse() * direction
	var previous_t := 0.0
	var was_above := false
	for i in 4096:
		var t := i * 0.5
		var p := start + dir * t
		if p.x < 0 or p.z < 0 or p.x > data.resolution - 1 or p.z > data.resolution - 1:
			was_above = false
			continue
		var above := p.y > surface_height(p.x, p.z)
		if was_above and not above:
			var lo := previous_t
			var hi := t
			for iteration in 12:
				var mid := (lo + hi) * 0.5
				var q := start + dir * mid
				if q.y > surface_height(q.x, q.z): lo = mid
				else: hi = mid
			return start + dir * ((lo + hi) * 0.5)
		was_above = above
		previous_t = t
	return null
