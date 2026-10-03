@tool
extends ConfirmationDialog

const Generator = preload("generator.gd")
signal applied(heights: PackedFloat32Array, resolution: int)
var language := "ar"
var values: Dictionary = {}
var captions: Array = []
var original: Dictionary
var generated := PackedFloat32Array()
var preview: SubViewport
var surface: MeshInstance3D
var sea: MeshInstance3D
var camera: Camera3D
var light: DirectionalLight3D
var debounce: Timer
var status: Label
var random_button: Button
var hint: Label
var size_menu: OptionButton
var yaw := 0.65
var pitch := 0.65
var zoom := 1.0
var center := Vector3.ZERO
var extent := 64.0
var height_limits := Vector2.ZERO
var dragging := false
var drag_offset := false
var fingers: Dictionary = {}

func setup() -> void:
	force_native = false
	min_size = Vector2i(620, 360)
	get_ok_button().custom_minimum_size.y = 44
	get_cancel_button().custom_minimum_size.y = 44
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.85
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	var heading := Label.new()
	form.add_child(heading)
	captions.append([heading, "تشكيل التضاريس", "TERRAIN GENERATOR"])
	heading.add_theme_font_size_override("font_size", 20)
	var size_label := Label.new()
	form.add_child(size_label)
	captions.append([size_label, "حجم الخريطة (متر)", "Map size (meters)"])
	size_menu = OptionButton.new()
	size_menu.custom_minimum_size.y = 38
	for label in ["64 × 64", "128 × 128", "256 × 256"]: size_menu.add_item(label)
	form.add_child(size_menu)
	size_menu.item_selected.connect(func(_i: int): request_preview())
	random_button = Button.new()
	form.add_child(random_button)
	random_button.custom_minimum_size.y = 38
	random_button.pressed.connect(func(): values.seed.value = randi_range(0, 999999))
	var specs := [
		["البذرة", "Seed", "seed", 0, 999999, 1337, 1],
		["الإزاحة الأفقية", "Offset X", "offset_x", -10000, 10000, 0, 1],
		["الإزاحة العمودية", "Offset Z", "offset_z", -10000, 10000, 0, 1],
		["الارتفاع الأساسي", "Base height", "base", -200, 200, -5, 0.1],
		["مدى الارتفاع", "Height range", "range", 0, 500, 24, 0.1],
		["المقياس", "Scale", "scale", 1, 512, 32, 0.5],
		["الخشونة", "Roughness", "roughness", 0, 1, 0.5, 0.01],
		["منحنى الارتفاع", "Curve", "curve", 0.1, 5, 1, 0.1],
		["طبقات التفاصيل", "Octaves", "octaves", 1, 8, 5, 1],
		["خطوات التعرية المبسطة", "Erosion steps (diffusion)", "erosion", 0, 12, 0, 1],
		["قوة التعرية", "Erosion weight", "erosion_weight", 0, 1, 0.35, 0.01],
		["تأثير الميل", "Erosion slope factor", "slope_factor", 0, 2, 0, 0.01],
		["اتجاه الميل الأفقي", "Slope direction X", "slope_x", -1, 1, 0, 0.01],
		["اتجاه الميل العمودي", "Slope direction Z", "slope_z", -1, 1, 0, 0.01],
		["تمدد القمم", "Dilation", "dilation", 0, 1, 0, 0.01],
		["تأثير الجزيرة", "Island weight", "island_weight", 0, 1, 0, 0.01],
		["حدة الجزيرة", "Island sharpness", "island_sharpness", 0.1, 6, 2, 0.1],
		["ارتفاع حواف الجزيرة", "Island height ratio", "island_height", -1, 1, -0.2, 0.01],
		["شكل الجزيرة", "Island shape", "island_shape", 0, 1, 0, 0.01]]
	for spec in specs:
		var row := HBoxContainer.new()
		form.add_child(row)
		var label := Label.new()
		label.custom_minimum_size.x = 115
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		label.add_theme_font_size_override("font_size", 16)
		row.add_child(label)
		captions.append([label, spec[0], spec[1]])
		var slider := HSlider.new()
		slider.min_value = spec[3]
		slider.max_value = spec[4]
		slider.step = spec[6]
		slider.value = spec[5]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(50, 38)
		row.add_child(slider)
		var number := SpinBox.new()
		number.min_value = spec[3]
		number.max_value = spec[4]
		number.step = spec[6]
		number.value = spec[5]
		number.custom_minimum_size = Vector2(100, 38)
		row.add_child(number)
		values[spec[2]] = number
		slider.value_changed.connect(func(v: float): number.value = v)
		number.value_changed.connect(func(v: float):
			slider.set_value_no_signal(v)
			request_preview())
	for spec in [["عكس اتجاه الميل", "Invert slope direction", "slope_invert", false], ["إضافة إلى الارتفاع الحالي", "Add to existing terrain", "additive", false], ["إظهار البحر (معاينة فقط)", "Show sea (preview only)", "sea", true], ["الظلال", "Shadows", "shadows", true]]:
		var check := CheckBox.new()
		check.custom_minimum_size.y = 38
		check.button_pressed = spec[3]
		form.add_child(check)
		captions.append([check, spec[0], spec[1]])
		values[spec[2]] = check
		check.toggled.connect(func(_on: bool): request_preview())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.35
	columns.add_child(right)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.max_lines_visible = 2
	hint.add_theme_font_size_override("font_size", 16)
	right.add_child(hint)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(270, 190)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(container)
	preview = SubViewport.new()
	preview.own_world_3d = true
	preview.size = Vector2i(512, 512)
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(preview)
	container.gui_input.connect(preview_input)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("343a43")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b6c3d0")
	world.environment.ambient_light_energy = 0.25
	preview.add_child(world)
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 0.85
	preview.add_child(light)
	surface = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("999fa4")
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.material_override = mat
	preview.add_child(surface)
	sea = MeshInstance3D.new()
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("3068bb")
	water.roughness = 0.6
	sea.material_override = water
	preview.add_child(sea)
	camera = Camera3D.new()
	camera.current = true
	preview.add_child(camera)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.max_lines_visible = 2
	status.add_theme_font_size_override("font_size", 16)
	right.add_child(status)
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 0.18
	add_child(debounce)
	debounce.timeout.connect(update_preview)
	preview.size_changed.connect(update_camera)
	confirmed.connect(apply_preview)
	visibility_changed.connect(func():
		preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
		if not visible: debounce.stop())
	localize(language)

func localize(lang: String) -> void:
	language = lang
	var ar := lang == "ar"
	title = "توليد تضاريس — معاينة ثلاثية الأبعاد" if ar else "Terrain generator — 3D preview"
	for item in captions: item[0].text = item[1] if ar else item[2]
	get_ok_button().text = "تطبيق على الخريطة" if ar else "Apply to terrain"
	get_cancel_button().text = "إلغاء" if ar else "Cancel"
	if random_button: random_button.text = "بذرة عشوائية" if ar else "Randomize seed"
	if hint: hint.text = "اسحب للدوران • بإصبعين أو العجلة للتقريب\nShift + سحب: إزاحة التضاريس" if ar else "Drag to orbit • pinch or wheel to zoom\nShift + drag: offset terrain"
	if not generated.is_empty(): update_status()

func parameters() -> Dictionary:
	var result := {"resolution": [65, 129, 257][size_menu.selected]}
	for key in values:
		result[key] = values[key].button_pressed if values[key] is CheckBox else values[key].value
	return result

func open_for(snapshot: Dictionary, lang: String) -> void:
	original = snapshot.duplicate(true)
	size_menu.select(maxi(0, [65, 129, 257].find(int(snapshot.resolution))))
	localize(lang)
	zoom = 1.0
	popup_centered_ratio(0.9)
	update_preview()

func request_preview() -> void:
	if debounce and visible: debounce.start()

func update_preview() -> void:
	if original.is_empty(): return
	var p := parameters()
	generated = Generator.generate(p, original)
	var n: int = p.resolution
	var step := 2 if n == 257 else 1
	var rows := (n - 1) / step + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(0, n, step):
		for x in range(0, n, step):
			vertices.append(Vector3(x, generated[z * n + x], z))
			var dx := generated[z * n + maxi(0, x - 1)] - generated[z * n + mini(n - 1, x + 1)]
			var dz := generated[maxi(0, z - 1) * n + x] - generated[mini(n - 1, z + 1) * n + x]
			normals.append(Vector3(dx, 2, dz).normalized())
	for z in rows - 1:
		for x in rows - 1:
			var i := z * rows + x
			indices.append_array(PackedInt32Array([i, i + 1, i + rows, i + 1, i + rows + 1, i + rows]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface.mesh = mesh
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (n - 1)
	sea.mesh = plane
	sea.position = Vector3((n - 1) * 0.5, 0, (n - 1) * 0.5)
	sea.visible = p.sea
	light.shadow_enabled = p.shadows
	var minimum := generated[0]
	var maximum := minimum
	for h in generated:
		minimum = minf(minimum, h)
		maximum = maxf(maximum, h)
	center = Vector3((n - 1) * 0.5, (minimum + maximum) * 0.5, (n - 1) * 0.5)
	height_limits = Vector2(minimum, maximum)
	extent = maxf(n - 1, maximum - minimum)
	update_camera()
	update_status()

func update_status() -> void:
	var n := int(parameters().resolution)
	status.text = ("%d × %d متر • الارتفاع %.1f إلى %.1f\nالتعديلات مؤقتة حتى الضغط على تطبيق." if language == "ar" else "%d × %d m • Height %.1f to %.1f\nChanges remain a preview until Apply.") % [n - 1, n - 1, height_limits.x, height_limits.y]

func update_camera() -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree(): return
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var aspect := float(preview.size.x) / maxf(1, preview.size.y)
	var half_fov := deg_to_rad(camera.fov) * 0.5
	if aspect < 1: half_fov = atan(tan(half_fov) * aspect)
	camera.position = center + offset * extent * 0.78 / sin(half_fov) * zoom
	camera.far = maxf(4000, extent * 20)
	camera.look_at(center)

func preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed
			drag_offset = event.shift_pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.35, 4)
			update_camera()
	if event is InputEventMouseMotion and dragging and fingers.is_empty():
		if drag_offset:
			values.offset_x.value += event.relative.x * 0.25
			values.offset_z.value += event.relative.y * 0.25
		else: orbit(event.relative)
	if event is InputEventScreenTouch:
		if event.pressed: fingers[event.index] = event.position
		else: fingers.erase(event.index)
	if event is InputEventScreenDrag and fingers.has(event.index):
		if fingers.size() == 1: orbit(event.relative)
		elif fingers.size() == 2:
			var other: int = fingers.keys()[0] if fingers.keys()[1] == event.index else fingers.keys()[1]
			var old_distance: float = fingers[event.index].distance_to(fingers[other])
			var new_distance: float = event.position.distance_to(fingers[other])
			if new_distance > 1:
				zoom = clampf(zoom * old_distance / new_distance, 0.35, 4)
				update_camera()
		fingers[event.index] = event.position

func orbit(delta: Vector2) -> void:
	yaw -= delta.x * 0.008
	pitch = clampf(pitch + delta.y * 0.008, 0.1, 1.5)
	update_camera()

func apply_preview() -> void:
	debounce.stop()
	update_preview()
	applied.emit(generated.duplicate(), int(parameters().resolution))
