@tool
extends EditorInspectorPlugin

var host: EditorPlugin
var owned := ["data", "textures", "tile_size", "foliage_mode", "foliage_texture", "foliage_scene", "foliage_count", "foliage_density", "foliage_ground_offset", "foliage_lod_distance", "foliage_spacing", "foliage_seed", "foliage_align_slope", "collision_mode", "collision_player", "collision_radius", "terrain_collision_layer"]

func _can_handle(object: Object) -> bool:
	return object.get_script() == preload("terrain.gd")

func _parse_property(_object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
	return name in owned

func _parse_begin(object: Object) -> void:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	add_custom_control(panel)
	section(panel, "التضاريس", "TERRAIN")
	var detail := Label.new()
	detail.text = host.words("مساحة الأرض: %d × %d متر", "Terrain area: %d × %d m") % [object.data.resolution - 1, object.data.resolution - 1] if object.data else "LiteTerrain"
	panel.add_child(detail)
	number(panel, object, "tile_size", "حجم تكرار الخامة", "Texture tile size", 0.5, 64, 0.5)
	var generate := Button.new()
	generate.text = host.words("توليد تضاريس مع معاينة…", "Generate with preview…")
	generate.custom_minimum_size.y = 40
	generate.pressed.connect(func(): host._edit(object); host.open_generator())
	panel.add_child(generate)
	section(panel, "العشب والأشجار", "FOLIAGE")
	choice(panel, object, "foliage_mode", "نوع النباتات", "Foliage mode", [["معطّل", "Off"], ["صورة عشب بشكل X", "Texture X"], ["مشهد حقيقي", "Packed scene"]])
	resource_field(panel, object, "foliage_texture", "صورة العشب (اختيارية)", "Grass texture (optional)", "Texture2D")
	resource_field(panel, object, "foliage_scene", "مشهد العشب أو الشجرة", "Grass or tree scene", "PackedScene")
	number(panel, object, "foliage_count", "عدد التوزيع العشوائي", "Random distribution count", 0, 5000, 1)
	number(panel, object, "foliage_seed", "بذرة التوزيع", "Distribution seed", 0, 999999, 1)
	number(panel, object, "foliage_ground_offset", "إزاحة عن سطح الأرض", "Ground offset", -2, 2, 0.01)
	number(panel, object, "foliage_lod_distance", "مسافة تفاصيل النباتات", "Foliage LOD distance", 4, 512, 1)
	var align := CheckBox.new()
	align.text = host.words("محاذاة النباتات مع ميل الأرض", "Align foliage to terrain slope")
	align.button_pressed = object.foliage_align_slope
	align.toggled.connect(func(v: bool): host.change_property(object, "foliage_align_slope", v))
	panel.add_child(align)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = host.words("العدد يوزع النباتات على الخريطة. فرشاة النباتات للرسم اليدوي، وعكس للمسح. الصفر يبقي النباتات اليدوية فقط.", "Count scatters across the map. Use the foliage brush to paint; Invert erases. Zero keeps manually painted plants only.")
	panel.add_child(help)
	section(panel, "التصادم", "COLLISION")
	choice(panel, object, "collision_mode", "نطاق التصادم", "Collision mode", [["معطّل", "Disabled"], ["كامل الخريطة", "Full map"], ["حول اللاعب", "Around player"]])
	caption(panel, "مسار عقدة اللاعب", "Player node path")
	var path := LineEdit.new()
	path.text = str(object.collision_player)
	path.placeholder_text = "../Player"
	path.custom_minimum_size.y = 38
	path.text_submitted.connect(func(value: String): host.change_property(object, "collision_player", NodePath(value)))
	path.focus_exited.connect(func():
		if is_instance_valid(object) and str(object.collision_player) != path.text: host.change_property(object, "collision_player", NodePath(path.text)))
	panel.add_child(path)
	number(panel, object, "collision_radius", "نصف قطر التصادم", "Collision radius", 4, 64, 1)
	number(panel, object, "terrain_collision_layer", "قناع طبقات التصادم", "Collision layer bitmask", 1, 4294967295, 1)
	var fallback := Label.new()
	fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fallback.text = host.words("إذا لم تُحدد عقدة لاعب صالحة يبقى التصادم على كامل الخريطة.", "Without a valid player node, collision covers the full map.")
	panel.add_child(fallback)

func section(panel: VBoxContainer, ar: String, en: String) -> void:
	panel.add_child(HSeparator.new())
	var label := Label.new()
	label.text = host.words(ar, en)
	label.add_theme_color_override("font_color", Color("83ddba"))
	panel.add_child(label)

func caption(panel: VBoxContainer, ar: String, en: String) -> void:
	var label := Label.new()
	label.text = host.words(ar, en)
	panel.add_child(label)

func number(panel: VBoxContainer, object: Object, property: String, ar: String, en: String, minimum: float, maximum: float, step: float) -> void:
	caption(panel, ar, en)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = object.get(property)
	spin.custom_minimum_size.y = 38
	spin.value_changed.connect(func(value: float): host.change_property(object, property, int(value) if step == 1 else value))
	panel.add_child(spin)

func choice(panel: VBoxContainer, object: Object, property: String, ar: String, en: String, items: Array) -> void:
	caption(panel, ar, en)
	var select := OptionButton.new()
	select.custom_minimum_size.y = 38
	for item in items: select.add_item(host.words(item[0], item[1]))
	select.selected = object.get(property)
	select.item_selected.connect(func(index: int): host.change_property(object, property, index))
	panel.add_child(select)

func resource_field(panel: VBoxContainer, object: Object, property: String, ar: String, en: String, type: String) -> void:
	caption(panel, ar, en)
	var picker := EditorResourcePicker.new()
	picker.base_type = type
	picker.edited_resource = object.get(property)
	picker.custom_minimum_size.y = 38
	picker.resource_changed.connect(func(resource: Resource): host.change_property(object, property, resource))
	panel.add_child(picker)
