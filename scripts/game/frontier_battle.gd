extends Node3D

signal return_requested
signal save_requested
signal pause_changed(value: bool)

const Kit = preload("res://scripts/game/village_ui.gd")
const BurstPool = preload("res://scripts/game/combat_burst_pool.gd")
var burst_pool = BurstPool.new()
const PALETTES: Array[Color] = [Color("58605e"), Color("304f46"), Color("51423e"), Color("304753"), Color("565044"), Color("5c6146"), Color("555b69")]
var sim
var model_factory: Callable
var camera := Camera3D.new()
var kit = Kit.new()
var actors: Array[Dictionary] = []
var status: Label
var save_status: Label
var back: Button
var flash := ColorRect.new()
var last_status: String = "running"
var paused: bool = false
var focused: bool = true
var accumulator: float = 0.0
var save_clock: float = 0.0


func _ready() -> void:
	position = Vector3(1000, 0, 0)
	add_child(kit)
	add_child(burst_pool)
	var index: int = sim.chronicle.region_order().find(sim.frontier.active["region"])
	var floor_mesh := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(32, 0.2, 26)
	floor_mesh.mesh = slab
	var material := StandardMaterial3D.new()
	material.albedo_color = PALETTES[index]
	material.roughness = 1.0
	floor_mesh.material_override = material
	floor_mesh.position = Vector3(14, -0.1, 11.2)
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color("d6def3")
	sun.light_energy = 0.9
	add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101927")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9da9c1")
	environment.ambient_light_energy = 0.55
	camera.environment = environment
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 150.0
	add_child(camera)
	camera.position = Vector3(34, 36, 40)
	camera.look_at(global_position + Vector3(14, 0, 11.2), Vector3.UP)
	camera.make_current()
	_frame_camera()
	get_viewport().size_changed.connect(_frame_camera)
	for slot in 8:
		var stone := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.8 + index * 0.08, 0.6 + slot % 3 * 0.4, 0.9)
		stone.mesh = mesh
		stone.material_override = material
		stone.position = Vector3(slot * 4.0, mesh.size.y * 0.5, -0.7 if slot % 2 == 0 else 23.3)
		stone.rotation.y = slot * 0.7
		add_child(stone)
	var landmark: Node3D = model_factory.call("scout_post_t1" if index % 2 == 0 else "chapel_t1")
	landmark.position = Vector3(28.7, 0, 11.2)
	add_child(landmark)
	var far_mark: Node3D = model_factory.call("chapel_t1" if index % 2 == 0 else "scout_post_t1")
	far_mark.position = Vector3(-0.7, 0, 11.2)
	add_child(far_mark)
	var spots := [Vector3(9.0, 0, 17.5), Vector3(19.5, 0, 2.8), Vector3(24.0, 0, 17.5)]
	for slot in ["wall_t1", "tower_t1", "grove_t1"]:
		var extra: Node3D = model_factory.call(slot)
		extra.position = spots[abs(hash(slot + str(index))) % spots.size()]
		extra.rotation.y = index * 0.4 + float(abs(hash(slot)) % 6) * 0.1
		add_child(extra)
	for group_name: String in ["army", "enemies"]:
		for body: Dictionary in sim.frontier.active[group_name]:
			var role: String = str(body["type"])
			var enemy: bool = group_name == "enemies"
			if enemy:
				role = {"raider": "warrior", "scout": "ranger", "archer": "archer", "breaker": "halberdier", "ram": "sapper", "bombard": "sapper"}.get(role, "warrior")
			var model: Node3D = model_factory.call("char_" + role)
			add_child(model)
			if enemy: _tint(model)
			var health := Label3D.new()
			health.position.y = 2.2
			health.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			health.font_size = 28
			health.pixel_size = 0.01
			health.modulate = Color("da978d") if enemy else Color("c0d1a7")
			model.add_child(health)
			actors.append({"body": body, "model": model, "health": health, "player": model.find_child("AnimationPlayer", true, false), "clip": ""})
	_build_ui()
	_sync()


func _tint(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("a56d68")
		material.roughness = 0.9
		node.material_override = material
	for child in node.get_children(): _tint(child)


func _frame_camera() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	camera.size = 34.0 if size.x >= size.y else 68.0


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root_control := Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.theme = kit.theme()
	layer.add_child(root_control)
	var heading := kit.manor_panel(root_control)
	heading.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	heading.offset_left = 16
	heading.offset_right = -16
	heading.offset_top = 16
	var column := VBoxContainer.new()
	heading.add_child(column)
	kit.heading(str(sim.chronicle.region_data(sim.frontier.active["region"])["name"]), column)
	status = kit.body("", column, 13)
	save_status = kit.body("Expeditions save every five active seconds.", column, 12)
	kit.body("Tap open ground to rally your force. Combat is automatic. Your home village waits safely.", column, 12)
	var commands := kit.manor_panel(root_control)
	commands.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	commands.offset_left = 16
	commands.offset_right = -16
	commands.offset_top = -140
	commands.offset_bottom = -16
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	commands.add_child(grid)
	kit.command_button("Pause / Resume", _toggle_pause, grid).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kit.command_button("Save", func(): save_requested.emit(), grid).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kit.command_button("Withdraw (no prize)", _withdraw, grid).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back = kit.gold_button("Return to Manor", func(): return_requested.emit(), grid)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Entry flash: pale arrival fade, never blocking input.
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(0.95, 0.9, 0.75, 0.55)
	root_control.add_child(flash)
	var arrival := create_tween()
	arrival.tween_property(flash, "color:a", 0.0, 0.9)


func _toggle_pause() -> void:
	paused = not paused
	pause_changed.emit(paused)


func _withdraw() -> void:
	sim.frontier.withdraw()
	_sync()


func _process(dt: float) -> void:
	burst_pool.paused = paused or not focused
	if not paused and focused:
		accumulator += minf(dt, 0.25)
		while accumulator >= 0.05:
			sim.frontier.tick(0.05)
			accumulator -= 0.05
		save_clock += minf(dt, 0.25)
		if save_clock >= 5.0:
			save_clock = 0.0
			save_requested.emit()
	else:
		accumulator = 0.0
	_sync()


func _sync() -> void:
	if sim.frontier.active.is_empty(): return
	var battle: Dictionary = sim.frontier.active
	status.text = "%s / %d defenders / %d enemies / %.0fs" % ["PAUSED" if paused or not focused else str(battle["status"]).to_upper(), sim.frontier.alive(battle["army"]), sim.frontier.alive(battle["enemies"]), battle["clock"]]
	back.disabled = battle["status"] == "running"
	if last_status == "running" and str(battle["status"]) != "running":
		_celebrate(str(battle["status"]) == "won")
	last_status = str(battle["status"])
	for actor: Dictionary in actors:
		var body: Dictionary = actor["body"]
		var model: Node3D = actor["model"]
		model.position = Vector3(float(body["x"]) * 1.4, 0, float(body["y"]) * 1.4)
		var facing := Vector2(float(body["fx"]) - float(body["x"]), float(body["fy"]) - float(body["y"]))
		if facing.length_squared() > 0.001: model.rotation.y = atan2(facing.x, facing.y)
		actor["health"].text = "%.0f / %.0f" % [body["hp"], body["max_hp"]]
		var player: AnimationPlayer = actor["player"]
		var clip: String = "death" if body["hp"] <= 0.0 else str(body["phase"])
		if player != null:
			if not player.has_animation(clip): clip = "idle"
			if player.has_animation(clip) and actor["clip"] != clip:
				player.get_animation(clip).loop_mode = Animation.LOOP_NONE if clip == "death" else Animation.LOOP_LINEAR
				player.play(clip, 0.12)
				actor["clip"] = clip
			player.speed_scale = 0.0 if paused or not focused else 1.0


func _celebrate(won: bool) -> void:
	var tint := Color("d4b275") if won else Color("8f3b34")
	flash.color = Color(tint, 0.4)
	var flare := create_tween()
	flare.tween_property(flash, "color:a", 0.0, 1.2)
	var middle := Vector3.ZERO
	var count := 0
	for body: Dictionary in sim.frontier.active["enemies"]:
		middle += Vector3(float(body["x"]) * 1.4, 0, float(body["y"]) * 1.4)
		count += 1
	if count > 0:
		middle = middle / float(count)
	else:
		middle = Vector3(14, 0, 11.2)
	for burst in 3:
		_burst(middle + Vector3(randf_range(-3.0, 3.0), 0.5 + burst * 0.5, randf_range(-3.0, 3.0)), tint)


func _burst(at: Vector3, tint: Color) -> void:
	burst_pool.spawn(at, tint, 14, 1.4)


func _unhandled_input(event: InputEvent) -> void:
	var point: Vector2
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		point = event.position
	elif event is InputEventScreenTouch and not event.pressed:
		point = event.position
	else:
		return
	var origin: Vector3 = camera.project_ray_origin(point)
	var direction: Vector3 = camera.project_ray_normal(point)
	if absf(direction.y) > 0.0001:
		var hit: Vector3 = origin + direction * (-origin.y / direction.y) - global_position
		sim.frontier.rally(Vector2(hit.x, hit.z) / 1.4)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		pause_changed.emit(true)
		save_requested.emit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
		pause_changed.emit(paused)
