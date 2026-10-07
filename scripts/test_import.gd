extends Node3D

# A deliberately small inspection layout. No gameplay or economy simulation.
const DISPLAY_TYPES: Array[String] = [
	"manor_hall", "barracks", "archer_tower", "mill",
	"farm", "market", "mine", "cottage",
	"gate", "wall", "trap", "oathstone",
]
const NAVY := Color("182a3b")
const BRASS := Color("c7a66a")
const PARCHMENT := Color("f0e5ce")

var catalog: Array = []
var buildings := Node3D.new()
var characters: Array[Dictionary] = []
var camera := Camera3D.new()
var sun := DirectionalLight3D.new()
var environment := Environment.new()
var target := Vector3(0, 0.7, 2)
var yaw: float = 0.0
var elevation: float = 0.83
var distance: float = 29.0
var tier: int = 1
var night: bool = false
var dragging: bool = false
var status := Label.new()
var capture_path: String = ""
var closeup: bool = false


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/catalog.json"))
	if not parsed is Dictionary or not parsed.get("assets") is Array:
		push_error("Invalid art/catalog.json")
		get_tree().quit(1)
		return
	catalog = parsed["assets"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		if arg == "--closeup":
			closeup = true
			target = Vector3(0, 1.1, 10)
			distance = 18.5
			elevation = 0.30
	add_child(buildings)
	_build_ground()
	_build_lighting()
	add_child(camera)
	camera.current = true
	camera.fov = 48
	camera.far = 400
	_show_tier(1)
	_build_characters()
	_build_ui()
	get_viewport().size_changed.connect(_update_camera)
	_update_camera()
	if not capture_path.is_empty():
		_capture()


func _box(size: Vector3, position_m: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	node.position = position_m
	add_child(node)


func _build_ground() -> void:
	_box(Vector3(40, 0.18, 32), Vector3(0, -0.09, 0), Color("778574"))
	for x in range(-20, 21, 2):
		_box(Vector3(0.018, 0.005, 32), Vector3(x, 0.003, 0), Color("96a18b"))
	for z in range(-16, 17, 2):
		_box(Vector3(40, 0.005, 0.018), Vector3(0, 0.003, z), Color("96a18b"))
	for x in [-20.1, 20.1]:
		_box(Vector3(0.2, 0.25, 32.4), Vector3(x, -0.07, 0), BRASS)
	for z in [-16.1, 16.1]:
		_box(Vector3(40, 0.25, 0.2), Vector3(0, -0.07, z), BRASS)
	var body := StaticBody3D.new()
	body.name = "GroundSupport"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.18, 32)
	shape.shape = box
	body.position.y = -0.09
	body.add_child(shape)
	add_child(body)


func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	world.environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("aebfca")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dbe4eb")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(world)
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	add_child(sun)


func _entry(type_name: String, requested_tier: int) -> Dictionary:
	var fallback: Dictionary = {}
	for value: Dictionary in catalog:
		var asset: String = value["asset"]
		if asset == "%s_t%d" % [type_name, requested_tier]:
			return value
		if asset == type_name + "_t1":
			fallback = value
	return fallback


func _load_asset(entry: Dictionary) -> Node3D:
	var path: String = "res://art/%s/%s" % [entry["asset"], entry["file"]]
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Cannot load " + path)
		return null
	return packed.instantiate() as Node3D


static func mesh_triangles(root_node: Node) -> int:
	var count: int = 0
	if root_node is MeshInstance3D:
		var mesh: Mesh = root_node.mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				if mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
					var arrays: Array = mesh.surface_get_arrays(surface)
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	for child in root_node.get_children():
		count += mesh_triangles(child)
	return count


func _show_tier(requested_tier: int) -> void:
	tier = requested_tier
	for child in buildings.get_children():
		buildings.remove_child(child)
		child.queue_free()
	var triangle_count: int = 0
	var fallbacks: Array[String] = []
	for index in DISPLAY_TYPES.size():
		var type_name: String = DISPLAY_TYPES[index]
		var entry: Dictionary = _entry(type_name, tier)
		if entry.is_empty():
			push_error("No catalog entry for " + type_name)
			continue
		var asset: Node3D = _load_asset(entry)
		if asset == null:
			continue
		buildings.add_child(asset)
		asset.position = Vector3(-9 + (index % 4) * 6, 0, -6 + (index / 4) * 6)
		triangle_count += mesh_triangles(asset)
		var actual_tier: String = str(entry["asset"]).rsplit("_t", true, 1)[1]
		if actual_tier != str(tier):
			fallbacks.append(type_name.capitalize())
		var height: float = float(entry["dimensions_m"][1])
		var label: Label3D = _label(asset, "%s / T0%s" % [type_name.capitalize(), actual_tier], Vector3(0, height + 0.55, 0), 30)
		label.visible = not closeup
	status.text = "T0%d  |  %d static building triangles  |  12 / 23 types\n40 x 32 m board  /  20 x 16 tiles  /  scale 1" % [tier, triangle_count]
	if not fallbacks.is_empty():
		status.text += "\nT01 fallback: " + ", ".join(fallbacks)
	print("DISPLAY_TIER ", tier, " static_building_triangles=", triangle_count)


func _label(parent: Node3D, text: String, position_m: Vector3, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position_m
	label.font_size = font_size
	label.pixel_size = 0.015
	label.modulate = PARCHMENT
	label.outline_modulate = NAVY
	label.outline_size = 9
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var player: AnimationPlayer = _find_player(child)
		if player != null:
			return player
	return null


func _build_characters() -> void:
	var jobs: Array[String] = ["work", "attack", "attack", "gather", "work", "work", "gather", "walk"]
	for entry: Dictionary in catalog:
		if entry["kind"] != "character":
			continue
		var asset: Node3D = _load_asset(entry)
		if asset == null:
			continue
		add_child(asset)
		var index: int = characters.size()
		asset.position = Vector3(-8.75 + index * 2.5, 0, 10)
		var player: AnimationPlayer = _find_player(asset)
		var label: Label3D = _label(asset, "", Vector3(0, 2.5, 0), 25)
		characters.append({"player": player, "label": label, "name": str(entry["asset"]).trim_prefix("char_").capitalize(), "job": jobs[index % jobs.size()]})
	_set_animation(0)


func _set_animation(index: int) -> void:
	var choices: Array[String] = ["Job preview", "idle", "walk", "work", "attack", "gather", "death"]
	for character: Dictionary in characters:
		var player: AnimationPlayer = character["player"]
		var clip: String = character["job"] if index == 0 else choices[index]
		var note: String = ""
		if player == null:
			character["label"].text = character["name"] + "\nNO ANIMATION PLAYER"
			continue
		if not player.has_animation(clip):
			var requested: String = clip
			clip = "gather" if player.has_animation("gather") else "work"
			note = " (%s fallback)" % requested
		var animation: Animation = player.get_animation(clip)
		animation.loop_mode = Animation.LOOP_NONE if clip == "death" else Animation.LOOP_LINEAR
		player.play(clip)
		character["label"].text = "%s\n%s%s" % [character["name"], clip, note]


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(NAVY, 0.96)
	style.border_color = BRASS
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(5)
	return style


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var theme := Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_color", "OptionButton", PARCHMENT)
	theme.set_stylebox("panel", "PanelContainer", _panel_style())
	for control_type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus"]:
			theme.set_stylebox(state, control_type, _panel_style())
	column.theme = theme
	var top := PanelContainer.new()
	column.add_child(top)
	var header := VBoxContainer.new()
	top.add_child(header)
	var title := Label.new()
	title.text = "MANOR  /  ASSET TEST SCENE"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", BRASS)
	header.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Import and animation inspection only. NOT A FULL GAME."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(subtitle)
	var controls := HFlowContainer.new()
	header.add_child(controls)
	var animation_title := Label.new()
	animation_title.text = "Character clips  "
	controls.add_child(animation_title)
	var dropdown := OptionButton.new()
	dropdown.focus_mode = Control.FOCUS_NONE
	for text in ["Job preview", "idle", "walk", "work", "attack", "gather", "death"]:
		dropdown.add_item(text)
	dropdown.item_selected.connect(_set_animation)
	controls.add_child(dropdown)
	var toggle := Button.new()
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.text = "Day / Night"
	toggle.pressed.connect(_toggle_day)
	controls.add_child(toggle)
	var reset := Button.new()
	reset.focus_mode = Control.FOCUS_NONE
	reset.text = "Reset view"
	reset.pressed.connect(func() -> void:
		closeup = false
		_show_tier(tier)
		target = Vector3(0, 0.7, 2)
		distance = 29
		yaw = 0
		elevation = 0.83
		_update_camera())
	controls.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var bottom := PanelContainer.new()
	column.add_child(bottom)
	var footer := VBoxContainer.new()
	bottom.add_child(footer)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(status)
	var help := Label.new()
	help.text = "1-6: building tier    Q / E: orbit    Wheel: zoom    Right-drag: orbit    W / A / S / D: pan\nStatic buildings, including Lift Gate: no mechanism clips. Attack falls back to gather for civilian jobs."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 15)
	footer.add_child(help)


func _toggle_day() -> void:
	night = not night
	sun.light_energy = 0.35 if night else 0.85
	sun.light_color = Color("9ab4ed") if night else Color.WHITE
	environment.ambient_light_energy = 0.25 if night else 0.45
	environment.background_color = NAVY if night else Color("aebfca")


func _update_camera() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1)
	var fitted_distance: float = distance * maxf(1.0, 1.6 / aspect)
	camera.position = target + Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * fitted_distance
	camera.look_at(target)


func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	var orbit: float = float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	yaw += orbit * delta
	var pan := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	target += (right * pan.x + forward * pan.y) * delta * distance * 0.4
	target.x = clampf(target.x, -20, 20)
	target.z = clampf(target.z, -16, 16)
	if orbit != 0 or pan != Vector2.ZERO:
		_update_camera()


func _input(event: InputEvent) -> void:
	# Release anywhere, including over UI, to avoid a stuck orbit gesture.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_6:
			_show_tier(event.physical_keycode - KEY_0)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 5, 65)
			_update_camera()
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.006
		elevation = clampf(elevation + event.relative.y * 0.004, 0.15, 1.35)
		_update_camera()


func _capture() -> void:
	if not capture_path.is_absolute_path() or capture_path.get_extension().to_lower() != "png":
		push_error("--capture requires an absolute PNG filename")
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Viewport capture requires a rendering window; omit --headless")
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.1).timeout
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(capture_path)
	print("CAPTURE ", capture_path, " result=", result)
	get_tree().quit(0 if result == OK else 1)
