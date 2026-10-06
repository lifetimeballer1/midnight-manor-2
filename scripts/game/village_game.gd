extends Node3D

const Sim = preload("res://scripts/game/village_sim.gd")
const UI = preload("res://scripts/game/village_ui.gd")
const Details = preload("res://scripts/game/village_details.gd")
const ManorScore = preload("res://scripts/game/manor_music.gd")
var music = ManorScore.new()
var details = Details.new()
const NAVY := Color("152334")
const GOLD := Color("d4b275")
const PAPER := Color("f2e7cc")
const TILE: float = 2.0
const MAP_ORIGIN := Vector3(-20, 0, -16)
const ROAD_LIMIT: int = 320
const EFFECT_LIMIT: int = 24
const MODEL_LIMIT: int = 160

var sim = Sim.new()
var camera := Camera3D.new()
var environment := Environment.new()
var sun := DirectionalLight3D.new()
var fill := DirectionalLight3D.new()
var building_layer := Node3D.new()
var actor_layer := Node3D.new()
var ghost_layer := Node3D.new()
var selection_marker := MeshInstance3D.new()
var rally_marker := MeshInstance3D.new()
var models: Dictionary = {}
var actors: Dictionary = {}
var building_views: Dictionary = {}
var catalog: Dictionary = {}
var hud := Label.new()
var raid_hud := Label.new()
var message := Label.new()
var inspect_text: Label
var sidebar := PanelContainer.new()
var side_content := VBoxContainer.new()
var bottom := PanelContainer.new()
var placement_box := PanelContainer.new()
var placement_label := Label.new()
var confirm_button: Button
var collect_button: Button
var upgrade_button: Button
var repair_button: Button
var move_button: Button
var hire_buttons: Dictionary = {}
var roster_count: int = -1
var welcome := PanelContainer.new()
var panel: String = ""
var selected_building: int = -1
var selected_unit: int = -1
var build_type: String = ""
var moving_id: int = -1
var paving: bool = false
var rallying: bool = false
var wall_drag_start := Vector2i(-1, -1)
var preview_tile := Vector2i(-1, -1)
var ghost_signature: String = ""
var view_revision: int = -1
var tick_accumulator: float = 0.0
var ui_accumulator: float = 0.0
var save_accumulator: float = 0.0
var started: bool = false
var paused: bool = false
var focused: bool = true
var night: bool = true
var sound: bool = true
var dragging: bool = false
var panning: bool = false
var left_pressed: bool = false
var left_dragged: bool = false
var press_point := Vector2.ZERO
var last_pointer := Vector2.ZERO
var touches: Dictionary = {}
var pinch_dist: float = 0.0
var pinch_zoom: float = 0.0
var pinch_mid := Vector2.ZERO
var pinch_has_mid: bool = false
var pinch_active: bool = false
var save_blocked: bool = false
var save_path: String = "user://village-v1.json"
const SETTINGS_PATH := "user://manor-settings.json"
var show_grid: bool = true
var battery_saver: bool = false
var shadows_on: bool = true
var grid_layer := MeshInstance3D.new()
var grid_button: Button
var power_button: Button
var shadow_button: Button
var target := Vector3(0, 0, 0)
var yaw: float = 0.66
var tilt: float = 0.75
var zoom: float = 31.0
var capture_path: String = ""
var no_save: bool = false
var sfx := AudioStreamPlayer.new()
var ui: VillageUI
var left_dock := PanelContainer.new()
var left_content := VBoxContainer.new()
var resource_stack := PanelContainer.new()
var resource_rows: Dictionary = {}
var resource_bars: Dictionary = {}
var research_buttons: Dictionary = {}
var research_sheet_buttons: Dictionary = {}
var quest_label := Label.new()
var research_label := Label.new()
var build_cards: Dictionary = {}
var build_category_order: Array[String] = []
var workers_button: Button
var nav: HBoxContainer
var nav_shop: Button
var nav_attack: Button
var path_button: Button
var research_button: Button
var toast := PanelContainer.new()
var toast_label := Label.new()
var more_sheet := PanelContainer.new()
var road_layer := Node3D.new()
var road_dirt := MeshInstance3D.new()
var road_stone := MeshInstance3D.new()
var road_revision: int = -2
var road_cells: int = 0
var ground_parts: Array[MeshInstance3D] = []
var effect_nodes: Array[Node] = []
var capture_catalog: bool = false
var capture_showcase: bool = false
var research_list := VBoxContainer.new()


func _ready() -> void:
	sim.paused = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
			no_save = true
		if arg == "--no-save":
			no_save = true
		if arg == "--day":
			night = false
		if arg == "--catalog": capture_catalog = true
		if arg == "--showcase": capture_showcase = true
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/catalog.json"))
	for entry: Dictionary in parsed["assets"]:
		catalog[entry["asset"]] = entry
	if not no_save and (FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")):
		save_blocked = not sim.load_game(save_path)
	ui = UI.new()
	ui.name = "VillageUI"
	add_child(ui)
	ui.thumbnail_ready.connect(_apply_thumbnail)
	add_child(building_layer)
	add_child(actor_layer)
	add_child(ghost_layer)
	add_child(details)
	details.setup_warnings(self)
	add_child(music)
	music.set_enabled(false)
	_ground()
	_setup_roads()
	_lighting()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.far = 250
	_load_settings()
	_camera_update()
	_setup_marker()
	_build_grid()
	_setup_audio()
	_ui()
	_rebuild_buildings()
	_update_actors(0)
	_update_roads()
	_refresh_hud()
	get_viewport().size_changed.connect(_layout_ui)
	if not get_window().size_changed.is_connected(_layout_ui):
		get_window().size_changed.connect(_layout_ui)
	_layout_ui()
	if not capture_path.is_empty():
		_enter_village()
		if capture_showcase: _showcase()
		if capture_catalog: _open_panel("build")
		_capture()


func world_position(tile: Vector2, height: float = 0) -> Vector3:
	return MAP_ORIGIN + Vector3(tile.x * TILE, height, tile.y * TILE)


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if parsed is Dictionary:
			if (parsed as Dictionary).has("show_grid"):
				show_grid = bool((parsed as Dictionary)["show_grid"])
			if (parsed as Dictionary).has("sound"):
				sound = bool((parsed as Dictionary)["sound"])
			if (parsed as Dictionary).has("battery_saver"):
				battery_saver = bool((parsed as Dictionary)["battery_saver"])
			if (parsed as Dictionary).has("shadows_on"):
				shadows_on = bool((parsed as Dictionary)["shadows_on"])
	_apply_power_settings()


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"show_grid": show_grid, "sound": sound, "battery_saver": battery_saver, "shadows_on": shadows_on}))


func _apply_power_settings() -> void:
	Engine.max_fps = 30 if battery_saver else 0
	sun.shadow_enabled = shadows_on
	if is_instance_valid(power_button):
		power_button.text = "Battery saver: On" if battery_saver else "Battery saver: Off"
	if is_instance_valid(shadow_button):
		shadow_button.text = "Shadows: On" if shadows_on else "Shadows: Off"


func _toggle_power() -> void:
	battery_saver = not battery_saver
	_save_settings()
	_apply_power_settings()
	sim.notice = "Battery saver on / 30 fps" if battery_saver else "Battery saver off / full fps"


func _toggle_shadows() -> void:
	shadows_on = not shadows_on
	_save_settings()
	_apply_power_settings()


func _build_grid() -> void:
	# 20x16 tile grid overlay, toggleable from Settings. One line mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var col := Color(0.91, 0.86, 0.75, 0.22)
	for gx in 21:
		_add_grid_line(st, Vector2(gx, 0), Vector2(gx, 16), col)
	for gz in 17:
		_add_grid_line(st, Vector2(0, gz), Vector2(20, gz), col)
	grid_layer.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	grid_layer.material_override = material
	grid_layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid_layer.visible = show_grid
	add_child(grid_layer)


func _add_grid_line(st: SurfaceTool, a: Vector2, b: Vector2, col: Color) -> void:
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(world_position(a, 0.025))
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(world_position(b, 0.025))


func _toggle_grid() -> void:
	show_grid = not show_grid
	grid_layer.visible = show_grid
	_save_settings()
	if is_instance_valid(grid_button):
		grid_button.text = "Grid: On" if show_grid else "Grid: Off"


func _box(size: Vector3, at: Vector3, color: Color, parent: Node = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	node.position = at
	if parent == null:
		parent = self
	parent.add_child(node)
	return node


func _ground() -> void:
	ground_parts.clear()
	ground_parts.append(_box(Vector3(40, 0.32, 32), Vector3(0, -0.16, 0), Color("4d6038")))
	var grass := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var value: float = 0.94 + sin(x * 0.32) * cos(y * 0.24) * 0.10 + sin((x + y) * 1.8) * 0.018
			grass.set_pixel(x, y, Color(value, value, value))
	ground_parts[0].material_override.albedo_texture = ImageTexture.create_from_image(grass)
	for x in [-20.2, 20.2]:
		ground_parts.append(_box(Vector3(0.4, 0.7, 32.8), Vector3(x, -0.35, 0), Color("243529")))
	for z in [-16.2, 16.2]:
		ground_parts.append(_box(Vector3(40, 0.7, 0.4), Vector3(0, -0.35, z), Color("243529")))
	# The fixed cross path strips are gone; worn ground is drawn from living.cells instead.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for index in 35:
		var x: float = rng.randf_range(-19, 19)
		var z: float = rng.randf_range(-15, 15)
		if absf(x) < 14 and absf(z) < 11:
			continue
		ground_parts.append(_box(Vector3(0.3, 0.12, 0.3), Vector3(x, 0.06, z), Color("65745a")))
	var patch_rng := RandomNumberGenerator.new()
	patch_rng.seed = 19
	for index in 22:
		var shade: float = patch_rng.randf_range(-0.07, 0.07)
		var disc := MeshInstance3D.new()
		var disc_mesh := CylinderMesh.new()
		disc_mesh.top_radius = 1.0
		disc_mesh.bottom_radius = 1.0
		disc_mesh.height = 0.012
		disc_mesh.radial_segments = 24
		disc.mesh = disc_mesh
		var disc_material := StandardMaterial3D.new()
		disc_material.albedo_color = Color(0.30 + shade, 0.38 + shade, 0.22 + shade * 0.6)
		disc_material.roughness = 0.95
		disc.material_override = disc_material
		disc.position = Vector3(patch_rng.randf_range(-16.5, 16.5), 0.004 + index * 0.0004, patch_rng.randf_range(-13.0, 13.0))
		disc.scale = Vector3(patch_rng.randf_range(1.2, 3.2), 1.0, patch_rng.randf_range(1.0, 2.4))
		disc.rotation.y = patch_rng.randf_range(0.0, TAU)
		add_child(disc)
		ground_parts.append(disc)
	_scenery()


func _scenery() -> void:
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	add_child(scenery)
	_box(Vector3(76, 0.5, 64), Vector3(0, -0.80, 0), Color("212d20"), scenery)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color("4a3524")
	trunk_material.roughness = 0.95
	var crowns: Array[StandardMaterial3D] = []
	for tone: String in ["2b4a2e", "264128", "35532f"]:
		var crown_material := StandardMaterial3D.new()
		crown_material.albedo_color = Color(tone)
		crown_material.roughness = 0.9
		crowns.append(crown_material)
	var trunk_mesh := BoxMesh.new()
	trunk_mesh.size = Vector3(0.28, 0.9, 0.28)
	for index in 70:
		var x: float = rng.randf_range(-33.0, 33.0)
		var z: float = rng.randf_range(-27.0, 27.0)
		if absf(x) < 23.5 and absf(z) < 19.5:
			continue
		var tree := Node3D.new()
		tree.position = Vector3(x, -0.5, z)
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.5)
		scenery.add_child(tree)
		var trunk := MeshInstance3D.new()
		trunk.mesh = trunk_mesh
		trunk.material_override = trunk_material
		trunk.position.y = 0.45
		tree.add_child(trunk)
		var crown_mesh := CylinderMesh.new()
		crown_mesh.top_radius = 0.0
		crown_mesh.bottom_radius = 0.95
		crown_mesh.height = 2.0
		crown_mesh.radial_segments = 7
		var crown := MeshInstance3D.new()
		crown.mesh = crown_mesh
		crown.material_override = crowns[index % crowns.size()]
		crown.position.y = 1.7
		tree.add_child(crown)


func _setup_roads() -> void:
	add_child(road_layer)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_texture = UI.soft_disc_texture()
	dirt.vertex_color_use_as_albedo = true
	dirt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dirt.cull_mode = BaseMaterial3D.CULL_DISABLED
	dirt.roughness = 1.0
	dirt.render_priority = 1
	road_dirt.material_override = dirt
	road_layer.add_child(road_dirt)
	var cobble := StandardMaterial3D.new()
	cobble.albedo_texture = UI.cobble_texture()
	cobble.vertex_color_use_as_albedo = true
	cobble.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cobble.cull_mode = BaseMaterial3D.CULL_DISABLED
	cobble.roughness = 0.95
	cobble.render_priority = 2
	road_stone.material_override = cobble
	road_layer.add_child(road_stone)


# Two cached meshes, rebuilt only when the living system changes a trail stage.
func _update_roads() -> void:
	if road_revision == sim.living.revision:
		return
	road_revision = sim.living.revision
	var dirt := SurfaceTool.new()
	dirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cobble := SurfaceTool.new()
	cobble.begin(Mesh.PRIMITIVE_TRIANGLES)
	road_cells = 0
	for id: Variant in sim.living.cells.keys():
		if road_cells >= ROAD_LIMIT:
			break
		road_cells += 1
		var parts: PackedStringArray = str(id).split(",")
		if parts.size() != 2:
			continue
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var centre: Vector3 = world_position(Vector2(tile) + Vector2.ONE * 0.5, 0.02)
		var cell: Dictionary = sim.living.cells[id]
		var wear: float = clampf(float(cell.get("wear", 0.0)), 0.0, 1.0)
		if bool(cell.get("stone", false)):
			_road_quad(cobble, centre + Vector3(0, 0.014, 0), Color(0.78, 0.79, 0.78, 1.0))
			continue
		var faint: float = maxf(sim.living.faint_threshold(), 0.0001)
		var strength: float = clampf(wear / faint, 0.0, 1.0)
		var alpha: float = (0.16 + 0.6 * clampf(wear * 1.15, 0.0, 1.0)) * (0.45 + 0.55 * strength)
		_road_quad(dirt, centre, Color(0.45, 0.39, 0.3, alpha))
	road_dirt.mesh = dirt.commit()
	road_stone.mesh = cobble.commit()


func _lighting() -> void:
	var world := WorldEnvironment.new()
	world.environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = shadows_on
	sun.directional_shadow_max_distance = 48
	sun.shadow_bias = 0.03
	add_child(sun)
	fill.rotation_degrees = Vector3(-14, 95, 0)
	fill.light_color = Color("8fb4e0")
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	add_child(fill)
	_apply_lighting()


func _apply_lighting() -> void:
	environment.background_color = Color("0c172b") if night else Color("a6c0cd")
	environment.ambient_light_color = Color("b6b8c4") if night else Color("edf0de")
	environment.ambient_light_energy = 0.52 if night else 0.5
	environment.fog_enabled = night
	environment.fog_light_color = Color("2a2f52") if night else Color("c9d8dc")
	environment.fog_density = 0.006 if night else 0.0
	sun.light_color = Color("ffc48a") if night else Color("fff2cf")
	sun.light_energy = 0.85 if night else 1.0
	_update_light_pool()


func _update_light_pool() -> void:
	# Aggressive opt: max 6 nearest lamps visible, rest off. gl_compatibility safe.
	var scored: Array = []
	for view: Dictionary in building_views.values():
		var lamp: OmniLight3D = view.get("lamp")
		var root: Node3D = view.get("root")
		if not is_instance_valid(lamp) or not is_instance_valid(root):
			continue
		if not night:
			lamp.visible = false
			continue
		scored.append([target.distance_squared_to(root.global_position), lamp])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	for i in scored.size():
		(scored[i][1] as OmniLight3D).visible = i < 6


func _camera_update() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = size.x / maxf(size.y, 1)
	camera.size = zoom * maxf(1, 0.95 / ratio)
	camera.position = target + Vector3(sin(yaw) * cos(tilt), sin(tilt), cos(yaw) * cos(tilt)) * 60
	camera.look_at(target)
	# Bunny-judged yaw-follow: shadows fall away from viewer, offset 35deg right.
	sun.rotation_degrees = Vector3(-48.0, rad_to_deg(yaw) - 35.0, 0.0)
	fill.rotation_degrees = Vector3(-14.0, rad_to_deg(yaw) + 95.0, 0.0)


func _road_quad(tool: SurfaceTool, centre: Vector3, colour: Color) -> void:
	var half: float = TILE * 0.5 + 0.18
	var offsets := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half),
		Vector3(-half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for index in offsets.size():
		tool.set_normal(Vector3.UP)
		tool.set_color(colour)
		tool.set_uv(uvs[index])
		tool.add_vertex(centre + offsets[index])


func _asset_exists(asset_key: String) -> bool:
	return catalog.has(asset_key) and ResourceLoader.exists("res://art/%s/%s.glb" % [asset_key, asset_key])


# No stone_quarry GLB has been exported, so the quarry reuses the mine model as a
# stone worksite. Every returned key is a real exported asset.
func model_asset(type_name: String, tier: int) -> String:
	var aliases: Dictionary = {"guard_post": "tower", "mason_yard": "sawmill"}
	var asset_type: String = str(aliases.get(type_name, type_name))
	var key: String = "%s_t%d" % [asset_type, tier]
	if _asset_exists(key):
		return key
	var base: String = "%s_t1" % asset_type
	if base != key and _asset_exists(base):
		return base
	return "mine_t1" if _asset_exists("mine_t1") else key


func thumbnail_asset(type_name: String) -> String:
	return model_asset(type_name, 1)


func _model(asset_name: String) -> Node3D:
	if not models.has(asset_name):
		if models.size() >= MODEL_LIMIT:
			models.clear()
		var path: String = "res://art/%s/%s.glb" % [asset_name, asset_name]
		models[asset_name] = load(path) if ResourceLoader.exists(path) else null
	var scene: Variant = models[asset_name]
	if not scene is PackedScene:
		return Node3D.new()
	return (scene as PackedScene).instantiate() as Node3D


func _model_factory(asset_key: String) -> Node3D:
	var holder := Node3D.new()
	var model: Node3D = _model(asset_key)
	holder.add_child(model)
	if catalog.has(asset_key):
		var dims: Array = catalog[asset_key]["dimensions_m"]
		var extent: float = maxf(float(dims[0]), float(dims[2]))
		if extent > 0.001:
			model.scale = Vector3.ONE * (2.0 / extent)
	return holder


func _apply_thumbnail(asset_key: String) -> void:
	var texture: Texture2D = ui.cache.get(asset_key)
	if texture == null:
		return
	for type_name: Variant in build_cards.keys():
		if is_instance_valid(build_cards[type_name]) and thumbnail_asset(str(type_name)) == asset_key:
			build_cards[type_name].icon = texture


func _building_asset(b: Dictionary) -> String:
	return model_asset("manor_hall" if b["type"] == "hall" else str(b["type"]), int(b["tier"]))


func _rebuild_buildings() -> void:
	details.smoke_count = 0
	for child in building_layer.get_children():
		building_layer.remove_child(child)
		child.queue_free()
	building_views.clear()
	for b: Dictionary in sim.buildings:
		var key: String = _building_asset(b)
		var root_node := Node3D.new()
		building_layer.add_child(root_node)
		root_node.position = world_position(sim.center(b))
		var model: Node3D = _model(key)
		root_node.add_child(model)
		var dims: Array = catalog[key]["dimensions_m"] if catalog.has(key) else [2.0, 2.0, 2.0]
		var factor: float = minf(1.6, (float(b["size"]) * TILE - 0.15) / maxf(float(dims[0]), float(dims[2])))
		model.scale = Vector3.ONE * factor
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 30
		label.pixel_size = 0.012
		label.outline_size = 7
		label.modulate = GOLD
		label.position.y = float(dims[1]) * factor + 0.5
		root_node.add_child(label)
		var lamp: OmniLight3D
		if b["type"] in ["hall", "cottage", "barracks", "tower", "archer_tower", "gate", "storehouse"]:
			lamp = OmniLight3D.new()
			lamp.position = Vector3(0, 1.1, float(b["size"]) * 0.65)
			lamp.light_color = Color("ffc474")
			lamp.light_energy = 1.15
			lamp.omni_range = 3.6
			lamp.visible = night
			root_node.add_child(lamp)
		building_views[int(b["id"])] = {"root": root_node, "model": model, "label": label, "lamp": lamp}
		details.attach(self, b, building_views[int(b["id"])])
	view_revision = sim.revision
	_update_marker()


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result: AnimationPlayer = _find_player(child)
		if result != null:
			return result
	return null


func _tint_enemy(node: Node, tint: Color = Color("e7998e")) -> void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var source: Material = node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				material.albedo_color = tint
				node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_tint_enemy(child, tint)



func _update_actors(delta: float) -> void:
	var present: Dictionary = {}
	for enemy_group in [false, true]:
		var group: Array = sim.enemies if enemy_group else sim.units
		for u: Dictionary in group:
			var id: int = int(u["id"])
			present[id] = true
			if not actors.has(id):
				var unit_aliases: Dictionary = {"mason": "builder", "weaponsmith": "builder", "warden": "warrior", "longbowman": "archer"}
				var unit_asset: String = str(unit_aliases.get(str(u["type"]), str(u["type"])))
				var spawned: Node3D = _model("char_warrior" if enemy_group else "char_" + unit_asset)
				actor_layer.add_child(spawned)
				if enemy_group:
					var enemy_tints: Dictionary = {
						"raider": Color("e7998e"), "skirmisher": Color("e6c77b"), "brute": Color("a85f58"),
						"marksman": Color("a99ac7"), "sapper": Color("e88152")
					}
					_tint_enemy(spawned, enemy_tints.get(str(u["type"]), Color("e7998e")))
					var enemy_scale: float = 1.25 if u["type"] == "brute" else (0.88 if u["type"] == "skirmisher" else 1.0)
					spawned.scale = Vector3.ONE * enemy_scale
				actors[id] = {"model": spawned, "player": _find_player(spawned), "clip": "", "previous": Vector3.ZERO}
			var record: Dictionary = actors[id]
			var model: Node3D = record["model"]
			var destination: Vector3 = world_position(sim.position_of(u))
			var travel: Vector3 = destination - model.position
			var requested: String = str(u.get("phase", "idle"))
			if u["hp"] <= 0:
				requested = "death"
			if requested in ["gather", "repair"]:
				requested = "work"
			var player: AnimationPlayer = record["player"]
			if player != null and not player.has_animation(requested):
				requested = "idle"
			# Aim at the job or the struck enemy; walk facing follows real travel only.
			var facing: Vector3 = Vector3.ZERO
			if requested in ["work", "attack"]:
				facing = world_position(sim.facing_target(u)) - model.position
			elif travel.length_squared() > 0.00001:
				facing = travel
			if facing.length_squared() > 0.00001:
				var wanted: float = atan2(facing.x, facing.z)
				if delta > 0 and not sim.paused:
					model.rotation.y = rotate_toward(model.rotation.y, wanted, 9.0 * delta)
				elif delta <= 0:
					model.rotation.y = wanted
			model.position = destination
			if player != null:
				if record["clip"] != requested:
					player.get_animation(requested).loop_mode = Animation.LOOP_NONE if requested == "death" else Animation.LOOP_LINEAR
					player.play(requested, 0.12)
					record["clip"] = requested
				player.speed_scale = 0.0 if sim.paused else 1.0
	for id in actors.keys():
		if not present.has(id):
			actors[id]["model"].queue_free()
			actors.erase(id)
	for b: Dictionary in sim.buildings:
		var view: Dictionary = building_views.get(int(b["id"]), {})
		if view.is_empty():
			continue
		var model: Node3D = view["model"]
		model.visible = b["hp"] > 0
		model.scale.y = model.scale.x
		var label: Label3D = view["label"]
		var label_text: String = ""
		if b["hp"] <= 0:
			label_text = "RUINS / REPAIR"
		elif b["remaining"] > 0:
			label_text = "Building / %.0fs" % ceilf(b["remaining"])
		elif b["reserve"] >= 150 or int(b["id"]) == selected_building:
			var resource: String = str(sim.building_specs[b["type"]].get("production", ""))
			label_text = ("+%d %s" % [int(b["reserve"]), resource.capitalize()]) if not resource.is_empty() and resource != "<null>" else ""
		if str(view.get("label_text", "###")) != label_text:
			label.text = label_text
			view["label_text"] = label_text
	_update_marker()


func _setup_marker() -> void:
	# Selected-only ring: shared 16-gon annulus, fill 0.28 + rim 0.85, y 0.03.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs: int = 16
	var r_fill_in: float = 0.80
	var r_rim_in: float = 0.88
	var r_out: float = 1.0
	var fill_col := Color(0.82, 0.90, 1.0, 0.28)
	var rim_col := Color(1.0, 0.84, 0.48, 0.85)
	for i in segs:
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		for quad in [[r_fill_in, r_rim_in, fill_col], [r_rim_in, r_out, rim_col]]:
			var pts := [
				Vector2(quad[0], a0), Vector2(quad[1], a0), Vector2(quad[1], a1),
				Vector2(quad[0], a0), Vector2(quad[1], a1), Vector2(quad[0], a1)]
			for v in pts:
				st.set_color(quad[2])
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(cos(v.y) * v.x, 0.03, sin(v.y) * v.x))
	selection_marker.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 1
	material.disable_receive_shadows = true
	selection_marker.material_override = material
	selection_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(selection_marker)
	selection_marker.visible = false
	rally_marker.mesh = selection_marker.mesh
	rally_marker.material_override = material.duplicate()
	rally_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rally_marker)
	rally_marker.visible = false


func tier_roof_color(family_hue: float, family_sat: float, tier: int) -> Color:
	var t: int = clampi(tier, 1, 6)
	var v: float = 0.18 + 0.114 * float(t - 1)
	return Color.from_hsv(fposmod(family_hue, 1.0), clampf(family_sat, 0.0, 1.0), clampf(v, 0.0, 1.0))


func tier_trim_color(family_hue: float, family_sat: float, tier: int) -> Color:
	if tier >= 4:
		return Color("e8b64c")
	var c: Color = tier_roof_color(family_hue, family_sat, tier)
	return Color.from_hsv(c.h, c.s, c.v * 0.55)


func _update_marker() -> void:
	var b: Dictionary = sim.get_building(selected_building)
	var u: Dictionary = sim.get_unit(selected_unit)
	selection_marker.visible = not b.is_empty() or not u.is_empty()
	if not b.is_empty():
		selection_marker.position = world_position(sim.center(b), 0.035)
		selection_marker.scale = Vector3(float(b["size"]), 1, float(b["size"]))
	elif not u.is_empty():
		selection_marker.position = world_position(sim.position_of(u), 0.035)
		selection_marker.scale = Vector3(0.5, 1, 0.5)
	rally_marker.visible = sim.rally_point.x >= 0
	if rally_marker.visible:
		rally_marker.position = world_position(sim.rally_point, 0.04)
		rally_marker.scale = Vector3(0.72, 1, 0.72)



func _button(text: String, action: Callable, parent: Node) -> Button:
	return ui.button(text, action, parent)


func _paint_primary(node: Button, accent: Color) -> void:
	node.add_theme_stylebox_override("normal", ui.style(accent.darkened(0.62), accent))
	node.add_theme_stylebox_override("hover", ui.style(accent.darkened(0.42), accent.lightened(0.15)))
	node.add_theme_stylebox_override("pressed", ui.style(accent.darkened(0.76), accent))
	node.custom_minimum_size = Vector2(0, 64.0)
	node.add_theme_font_size_override("font_size", 19)
	node.add_theme_color_override("font_color", UI.PAPER)


func _paint_ring(node: Button, accent: Color, d: float) -> void:
	# Floating hero disc: AA-safe radius (not d/2), soft lift shadow.
	var r: int = clampi(int(d * 0.5) - 10, 8, int(d * 0.5) - 1)
	node.custom_minimum_size = Vector2(d, d)
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", 19 if d >= 72.0 else 15)
	node.add_theme_color_override("font_color", UI.PAPER)
	node.add_theme_color_override("font_hover_color", UI.PAPER)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		var fill_col: Color = accent.darkened(0.62)
		if state == "hover":
			fill_col = accent.darkened(0.42)
		elif state == "pressed":
			fill_col = accent.darkened(0.76)
		box.bg_color = Color(fill_col, 0.97)
		box.border_color = accent.lightened(0.15) if state != "normal" else accent
		box.set_border_width_all(2)
		box.set_corner_radius_all(r)
		box.shadow_size = 6 if d >= 72.0 else 3
		box.shadow_color = Color(0, 0, 0, 0.35)
		box.shadow_offset = Vector2(0, 2)
		box.set_content_margin_all(4)
		node.add_theme_stylebox_override(state, box)


func _action_button(text: String, action: Callable, parent: Node) -> Button:
	var made: Button = _button(text, action, parent)
	made.custom_minimum_size = Vector2(0, 56.0)
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return made


func _build_more_sheet(root_control: Control) -> void:
	# All secondary actions live here now; selection callbacks read
	# selected_building live, so reparenting changes nothing.
	more_sheet.add_theme_stylebox_override("panel", ui.style(UI.NAVY, UI.EDGE))
	root_control.add_child(more_sheet)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	more_sheet.add_child(mv)
	ui.heading("ACTIONS", mv)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	mv.add_child(grid)
	_action_button("Pave Roads", _toggle_pave, grid)
	collect_button = _action_button("Collect", _collect_selected, grid)
	upgrade_button = _action_button("Upgrade", _upgrade_selected, grid)
	move_button = _action_button("Move", _move_selected, grid)
	repair_button = _action_button("Repair", _repair_selected, grid)
	workers_button = _action_button("People", _open_workers, grid)
	_action_button("Village Path", _open_panel.bind("quests"), grid)
	_action_button("Research", _open_panel.bind("research"), grid)
	_action_button("Defense", _open_panel.bind("defense"), grid)
	_action_button("Commands", _open_selected_commands, grid)
	_action_button("⟲ Orbit", _orbit_left, grid)
	_action_button("⟳ Orbit", _orbit_right, grid)
	_action_button("Pause / Save", _open_pause, grid)
	_action_button("Close", _toggle_more, grid)
	more_sheet.hide()



func _open_selected_commands() -> void:
	more_sheet.hide()
	if selected_building >= 0 and not sim.get_building(selected_building).is_empty():
		_open_panel("building")
		sidebar.show()
	elif selected_unit >= 0 and not sim.get_unit(selected_unit).is_empty():
		_open_panel("unit")
	else:
		_open_panel("defense")
	_layout_ui()

func _toggle_more() -> void:
	# Leaving the pause panel through More must resume the simulation.
	_close_panel()
	more_sheet.visible = not more_sheet.visible
	_layout_ui()


func _label(text: String, parent: Node, large: bool = false) -> Label:
	return ui.heading(text, parent) if large else ui.body(text, parent)


func _ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root_control := Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root_control)
	root_control.theme = ui.theme()
	for label in [hud, raid_hud, quest_label, research_label]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_control.add_child(left_dock)
	left_content.add_theme_constant_override("separation", 6)
	left_dock.add_child(left_content)
	ui.heading("MIDNIGHT MANOR II", left_content)
	hud.add_theme_font_size_override("font_size", 14)
	left_content.add_child(hud)
	quest_label.add_theme_color_override("font_color", GOLD)
	left_content.add_child(quest_label)
	path_button = ui.button("Village Path", _open_panel.bind("quests"), left_content, 28.0)
	left_content.add_child(raid_hud)
	research_button = ui.button("Research / expand", _toggle_research, left_content, 28)
	research_label.add_theme_font_size_override("font_size", 13)
	left_content.add_child(research_label)
	left_content.add_child(research_list)
	research_list.hide()
	for id: Variant in sim.living.config["research"]["nodes"]:
		var node: Dictionary = sim.living.config["research"]["nodes"][id]
		var button: Button = ui.button(str(node["name"]), _begin_research.bind(str(id)), research_list, 30.0)
		button.tooltip_text = str(node["description"])
		research_buttons[str(id)] = button
	root_control.add_child(resource_stack)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	resource_stack.add_child(stack)
	for resource: String in ["wood", "food", "gold", "lumber", "stone"]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		stack.add_child(row)
		var value := ui.body("", row, 13)
		value.add_theme_color_override("font_color", GOLD)
		resource_rows[resource] = value
		resource_bars[resource] = ui.bar(0, 1, row)
	root_control.add_child(bottom)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dock := VBoxContainer.new()
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_theme_constant_override("separation", 10)
	bottom.add_child(dock)
	var toast_center := CenterContainer.new()
	toast_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(toast_center)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_stylebox_override("panel", ui.style(UI.NAVY, UI.EDGE))
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.custom_minimum_size = Vector2(280, 0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 13)
	toast_label.add_theme_color_override("font_color", GOLD)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(toast_label)
	toast_center.add_child(toast)
	nav = HBoxContainer.new()
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_theme_constant_override("separation", 12)
	dock.add_child(nav)
	nav_attack = ui.button("Horn", _test_raid, nav)
	_paint_ring(nav_attack, UI.BLOOD, 84.0)
	var spacer_left := Control.new()
	spacer_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer_left)
	var more_btn: Button = ui.button("···", _toggle_more, nav)
	_paint_ring(more_btn, UI.SLATE, 56.0)
	more_btn.tooltip_text = "More actions"
	var spacer_right := Control.new()
	spacer_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer_right)
	nav_shop = ui.button("Build", _open_panel.bind("build"), nav)
	_paint_ring(nav_shop, UI.GOLD, 84.0)
	_build_more_sheet(root_control)
	root_control.add_child(sidebar)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(side_scroll)
	side_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side_content)
	sidebar.hide()
	root_control.add_child(placement_box)
	var placement := VBoxContainer.new()
	placement_box.add_child(placement)
	placement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement.add_child(placement_label)
	var actions := HBoxContainer.new()
	placement.add_child(actions)
	confirm_button = _button("Confirm Build", _confirm_placement, actions)
	_button("Cancel", _cancel_placement, actions)
	placement_box.hide()
	root_control.add_child(welcome)
	var intro := VBoxContainer.new()
	welcome.add_child(intro)
	ui.heading("THE MANOR STANDS", intro)
	ui.body("Build your village beneath the moon.\nGather, grow, and hold the walls.", intro)
	ui.body("Drag to pan / wheel to zoom / Q-E to orbit.\nPhone: drag to pan / pinch to zoom.\nBuild previews never spend resources until you confirm.\nClick a building to collect, upgrade, move or repair.\nSelect a fighter, then click ground to give orders.", intro)
	ui.body("Core-loop prototype / local saves / no offline progress", intro, 12)
	_button("Enter Village", _enter_village, intro)
	_button("Day / Night", _toggle_day, intro)


func _research_cost(node: Dictionary) -> String:
	return "%s + %d Insight" % [_cost_text(node["cost"]), int(node["insight"])]


func _toggle_research() -> void:
	research_list.visible = not research_list.visible
	_layout_ui()


func _window_min() -> float:
	# Physical window px drive the branches: with canvas_items/expand the
	# logical rect inflates on phones (e.g. 390x844 -> 1440x3114), so
	# logical-only tests never fire there.
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return 1280.0
	return minf(float(win.x), float(win.y))


func _is_small() -> bool:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return _window_min() < 460.0 or size.x < 420.0


func _is_narrow() -> bool:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return _window_min() < 800.0 or size.x < 760.0


func _layout_ui() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var safe: float = UI.SAFE_MARGIN
	var narrow: bool = _is_narrow()
	var small: bool = _is_small()
	left_content.get_child(0).text = "MANOR II" if small else "MIDNIGHT MANOR II"
	for label in [hud, raid_hud, quest_label, research_label]:
		label.add_theme_font_size_override("font_size", 12 if small else 14)
	# Portrait phones: collapse the left dock to title + HUD + raid so the
	# world dominates; Path/Research stay one tap away in the bottom nav.
	var compact_dock: bool = small
	path_button.visible = not compact_dock
	quest_label.visible = not compact_dock
	research_button.visible = not compact_dock
	research_label.visible = not compact_dock
	if compact_dock:
		research_list.hide()
	var bar_h: float = maxf(UI.BOTTOM_BAR_H, bottom.get_combined_minimum_size().y)
	bottom.offset_left = safe
	bottom.offset_right = -safe
	bottom.offset_top = -bar_h - safe
	bottom.offset_bottom = -safe
	# Corners are structural now (ATTACK left, SHOP right): no reorder needed.
	# Reserve both safe margins plus a real gap so portrait widths never overlap.
	var corner_gap: float = 8.0
	var corner_width: float = maxf(0.0, size.x - safe * 2.0 - corner_gap)
	var dock_width: float = corner_width * 0.52 if narrow else UI.RAIL_WIDTH + 198.0
	left_dock.size = Vector2(dock_width, 0)
	left_dock.position = Vector2(safe, safe)
	var stack_width: float = corner_width * 0.48 if narrow else 226.0
	if small:
		stack_width = minf(165.0, size.x - dock_width - safe * 3.0)
	resource_stack.size = Vector2(stack_width, 0)
	resource_stack.position = Vector2(size.x - stack_width - safe, safe)
	if small:
		# Bottom sheet like the shop ref: full-width, above the bottom bar.
		var sheet_max: float = maxf(160.0, size.y - bar_h - safe * 3.0 - 96.0)
		var sheet_h: float = clampf(size.y * 0.45, minf(160.0, sheet_max), sheet_max)
		sidebar.position = Vector2(safe, size.y - bar_h - safe - 8.0 - sheet_h)
		sidebar.size = Vector2(size.x - safe * 2.0, sheet_h)
	else:
		sidebar.position = Vector2(safe, maxf(left_dock.get_combined_minimum_size().y, resource_stack.get_combined_minimum_size().y) + 30)
		sidebar.size = Vector2(size.x - 32 if narrow else 310.0, maxf(130, size.y - sidebar.position.y - bottom.size.y - 28))
	more_sheet.position = sidebar.position
	more_sheet.size = sidebar.size
	# Compact resource pills on phones: values only, bars stay on desktop.
	for resource: String in resource_bars:
		var gauge: ProgressBar = resource_bars[resource]
		if is_instance_valid(gauge):
			gauge.visible = not small
	placement_box.position = Vector2(maxf(16, (size.x - 330) / 2), size.y - bottom.size.y - 146)
	placement_box.size.x = minf(330, size.x - 32)
	welcome.size = Vector2(minf(480, size.x - 36), 0)
	welcome.position = Vector2((size.x - welcome.size.x) / 2, maxf(110, size.y * 0.28))
	_camera_update()


func _clear_sidebar() -> void:
	hire_buttons.clear()
	build_cards.clear()
	research_sheet_buttons.clear()
	for child in side_content.get_children():
		side_content.remove_child(child)
		child.queue_free()
	_button("Close", _close_panel, side_content)


func _open_panel(which: String) -> void:
	if panel == "pause" and which != "pause": paused = false
	panel = which
	more_sheet.hide()
	sidebar.show()
	_clear_sidebar()
	match which:
		"build":
			_build_catalog()
		"people":
			roster_count = sim.units.size()
			_label("PEOPLE & WORKERS", side_content, true)
			_label("%d people / %d beds\nHire a role, then select a villager to assign work or train." % [sim.units.size(), sim.beds()], side_content)
			for role in Sim.ROLES:
				var reason: String = sim.recruit_reason(role)
				var button: Button = _button("Hire " + str(sim.troop_specs[role]["name"]) + " / " + _cost_text(sim.troop_specs[role]["recruitCost"]), _hire.bind(role), side_content)
				button.disabled = not reason.is_empty()
				button.tooltip_text = reason
				hire_buttons[role] = button
			_label("Your villagers", side_content, true)
			for u: Dictionary in sim.units:
				var post: Dictionary = sim.get_building(int(u["workplace"]))
				var suffix: String = sim.building_specs[post["type"]]["name"] if not post.is_empty() else "Jobless / select to assign"
				if sim.troop_specs[u["type"]]["role"] == "combat":
					suffix = "Defender"
				_button("%s Lv%d / %s" % [str(u["type"]).capitalize(), u["level"], suffix], _select_unit.bind(int(u["id"])), side_content)
		"quests":
			_label("VILLAGE PATH", side_content, true)
			_label("Level %d / %d XP\nEarly village quests keep their original objectives and rewards." % [sim.village_level(), sim.xp], side_content)
			for quest: Dictionary in sim.quests:
				var done: bool = str(quest["id"]) in sim.completed_quests
				_label(("COMPLETE / " if done else "") + str(quest["name"]), side_content, true)
				_label(str(quest["text"]), side_content)
		"building":
			_build_inspector()
			sidebar.hide()
		"research":
			_label("RESEARCH", side_content, true)
			_label("Insight %d / %d. Research pauses during alarms." % [int(sim.living.insight), int(sim.living.config["research"]["insight_cap"])], side_content)
			for id: Variant in sim.living.config["research"]["nodes"]:
				var node: Dictionary = sim.living.config["research"]["nodes"][id]
				var key := str(id)
				var state := "READY"
				if key in sim.living.discoveries:
					state = "DONE"
				elif sim.living.active == key:
					state = "%.0fs LEFT" % sim.living.remaining
				var reason: String = sim.living.research_reason(sim, key)
				if state == "READY" and not reason.is_empty():
					state = "LOCKED"
				var button: Button = _button("%s\n%s / %d Insight" % [str(node["name"]), state, int(node["insight"])], _begin_research.bind(key), side_content)
				button.disabled = state != "READY"
				button.tooltip_text = str(node["description"]) if reason.is_empty() else reason
				research_sheet_buttons[key] = button
		"defense":
			_label("FORTRESS COMMAND", side_content, true)
			var intel: Dictionary = sim.raid_preview()
			var pieces: Array[String] = []
			for kind in intel["composition"]:
				pieces.append("%d %s" % [int(intel["composition"][kind]), str(kind).capitalize()])
			_label("Next wave %d\nApproach: %s\nExpected: %s" % [int(intel["wave"]), ", ".join(intel["sides"]), ", ".join(pieces)], side_content)
			var rally_text: String = "Not placed"
			if sim.rally_point.x >= 0:
				rally_text = "Tile %d,%d" % [floori(sim.rally_point.x), floori(sim.rally_point.y)]
			var rally_btn: Button = _button("Place Rally Point / " + rally_text, _toggle_rally, side_content)
			rally_btn.disabled = "fortifications" not in sim.living.discoveries
			rally_btn.tooltip_text = "Research Fortifications first." if rally_btn.disabled else "Choose open ground where rally-duty defenders assemble."
			_label("DEFENDER DUTIES", side_content, true)
			for u: Dictionary in sim.units:
				if sim.troop_specs[u["type"]]["role"] != "combat":
					continue
				_label("%s #%d / %s" % [str(sim.troop_specs[u["type"]]["name"]), int(u["id"]), str(u.get("defense_priority", "patrol")).capitalize()], side_content, true)
				var duty_row := HBoxContainer.new()
				side_content.add_child(duty_row)
				for priority in Sim.DEFENSE_PRIORITIES:
					var duty: Button = _button(str(priority).capitalize(), _set_defender_priority.bind(int(u["id"]), str(priority)), duty_row)
					duty.disabled = priority == "rally" and sim.rally_point.x < 0
			if not sim.last_raid_report.is_empty():
				var report: Dictionary = sim.last_raid_report
				_label("LAST BATTLE", side_content, true)
				_label("%s / Wave %d\nEnemies defeated %d / Buildings damaged %d / Destroyed %d\nDefenders knocked out %d / Duration %.0fs\nReward: %s" % [
					"VICTORY" if bool(report.get("victory", false)) else "DEFEAT", int(report.get("wave", 0)),
					int(report.get("enemies_defeated", 0)), int(report.get("buildings_damaged", 0)), int(report.get("buildings_destroyed", 0)),
					int(report.get("defenders_knocked_out", 0)), float(report.get("duration", 0.0)), _cost_text(report.get("reward", {}))
				], side_content)
		"workers":
			_build_inspector()
		"unit":
			_unit_inspector()
		"pause":
			_pause_panel()
	_layout_ui()


func _cost_text(cost: Dictionary) -> String:
	var pieces := PackedStringArray()
	for resource in cost:
		pieces.append("%d %s" % [cost[resource], str(resource).capitalize()])
	return " + ".join(pieces) if not pieces.is_empty() else "Free"


# Categorised build cards, each showing the real exported model as a cached thumbnail.
func _build_catalog() -> void:
	_label("RAISE THE VILLAGE", side_content, true)
	_label("Choose a structure, tap a tile, then confirm.\nThumbnails are the real exported models.", side_content)
	build_cards.clear()
	build_category_order.clear()
	for category: String in UI.CATEGORIES:
		var types: Array = UI.CATEGORY_TYPES[category]
		if types.is_empty():
			if category == "Roads":
				build_category_order.append(category)
				_label("ROADS", side_content, true)
				_button("Pave established dirt / 8 Stone", _toggle_pave, side_content)
			continue
		build_category_order.append(category)
		_label(category.to_upper(), side_content, true)
		for type_name: String in types:
			if not (type_name in Sim.BUILD_TYPES) or not sim.building_specs.has(type_name):
				continue
			var spec: Dictionary = sim.building_specs[type_name]
			var owned: int = 0
			for b: Dictionary in sim.buildings:
				if str(b.get("type", "")) == type_name and float(b.get("hp", 0.0)) > 0.0:
					owned += 1
			var lock: String = ""
			var cap: int = sim.building_limit(type_name)
			if type_name == "stone_quarry" and "stoneworking" not in sim.living.discoveries:
				lock = "Research Stoneworking first."
			elif type_name in ["guard_post", "mason_yard"] and "fortifications" not in sim.living.discoveries:
				lock = "Research Fortifications first."
			elif type_name == "oathstone" and "gate_engineering" not in sim.living.discoveries:
				lock = "Research Gate Engineering first."
			elif type_name == "forge" and "watchtowers" not in sim.living.discoveries:
				lock = "Research Watchtower Doctrine first."
			elif sim.village_level() < int(spec.get("minLevel", 1)):
				lock = "Requires village level %d." % int(spec.get("minLevel", 1))
			elif owned >= cap:
				lock = "Village limit reached."
			var state: int = ui.card_state_of(not lock.is_empty(), 1.0 if owned > 0 else 0.0)
			var caption := "%s\n%s / %d owned" % [str(spec["name"]), _cost_text(sim.building_cost(type_name)), owned]
			if state == UI.CardState.LOCKED:
				caption += " / LOCKED"
			if thumbnail_asset(type_name) != "%s_t1" % type_name:
				caption += "\nreuses the %s model" % thumbnail_asset(type_name)
			var card: Button = ui.button(caption, _choose_build.bind(type_name), side_content, 52.0)
			card.icon = ui.texture(thumbnail_asset(type_name), _model_factory)
			card.expand_icon = true
			card.add_theme_constant_override("icon_max_width", 72)
			card.alignment = HORIZONTAL_ALIGNMENT_LEFT
			card.add_theme_font_size_override("font_size", 13)
			if state == UI.CardState.LOCKED:
				card.disabled = true
				card.tooltip_text = lock
				card.self_modulate = Color(1, 1, 1, 0.72)
			elif state == UI.CardState.UPGRADEABLE:
				card.add_theme_stylebox_override("normal", ui.style(UI.SLATE, UI.GOLD))
			build_cards[type_name] = card


func _begin_research(id: String) -> void:
	sim.living.research(sim, id)
	_refresh_hud()


func _open_workers() -> void:
	_open_panel("people" if sim.get_building(selected_building).is_empty() else "workers")


func _build_inspector() -> void:
	var b: Dictionary = sim.get_building(selected_building)
	if b.is_empty():
		return
	_label(str(sim.building_specs[b["type"]]["name"]), side_content, true)
	inspect_text = _label("", side_content)
	# Collect / Upgrade / Move / Repair live in the bottom action bar; the panel only explains them.
	_label("Bottom bar: Collect banks the on-site reserve.\nUpgrade / %s." % _cost_text(sim.building_cost(b["type"], int(b["tier"]) + 1)), side_content)
	_label("Move relocates the site / no relocation during raids.\nRepair spends 15 HP per Wood.", side_content)
	_label("Matching workers", side_content, true)
	for u: Dictionary in sim.units:
		if str(sim.building_specs[b["type"]].get("workplace", "")) == str(u["type"]):
			var text: String = "Release " if int(u["workplace"]) == selected_building else "Assign "
			_button(text + str(u["type"]).capitalize() + " #%d" % u["id"], _assign.bind(int(u["id"]), -1 if int(u["workplace"]) == selected_building else selected_building), side_content)
	if b["type"] in ["wall", "stonewall", "gate"]:
		_label("CONNECTED DEFENSE", side_content, true)
		_button("Upgrade connected wall section", _upgrade_connected_wall, side_content)
		_button("Repair connected wall section", _repair_connected_wall, side_content)
		if b["type"] in ["wall", "stonewall"]:
			var gate_btn: Button = _button("Insert engineered gate", _insert_gate_selected, side_content)
			gate_btn.disabled = "gate_engineering" not in sim.living.discoveries or sim.raid_active or sim.raid_warning or b["remaining"] > 0
			gate_btn.tooltip_text = "Research Gate Engineering first." if "gate_engineering" not in sim.living.discoveries else "Replace this segment with a connected gate."
	if b["type"] in ["tower", "archer_tower"]:
		_label("TOWER TARGETING / " + str(b.get("target_mode", "closest")).capitalize(), side_content, true)
		for mode in ["closest", "strongest", "weakest", "sappers", "manor"]:
			var target_btn: Button = _button(str(mode).capitalize(), _set_tower_mode.bind(str(mode)), side_content)
			target_btn.disabled = mode != "closest" and "watchtowers" not in sim.living.discoveries
	if b["type"] in ["gate", "tower", "archer_tower", "guard_post"]:
		_label("POST DEFENDERS", side_content, true)
		var duty: String = "gate" if b["type"] in ["gate", "guard_post"] else "towers"
		for u: Dictionary in sim.units:
			if sim.troop_specs[u["type"]]["role"] == "combat":
				_button("Post %s #%d here" % [str(sim.troop_specs[u["type"]]["name"]), int(u["id"])], _post_defender_here.bind(int(u["id"])), side_content)
	_refresh_inspector()



func _unit_inspector() -> void:
	var u: Dictionary = sim.get_unit(selected_unit)
	if u.is_empty():
		return
	_label("%s / Level %d" % [str(u["type"]).capitalize(), u["level"]], side_content, true)
	inspect_text = _label("", side_content)
	_label("Click open ground to move. Orders keep carried goods and assignments.", side_content)
	_button("Hold position", _hold_selected, side_content)
	_button("Resume duties", _resume_selected, side_content)
	var training_cost: Dictionary = sim.troop_specs[u["type"]]["levelCost"].duplicate()
	for resource in training_cost:
		training_cost[resource] = float(training_cost[resource]) * int(u["level"])
	_button("Train / " + _cost_text(training_cost), _train_selected, side_content).disabled = int(u["level"]) >= int(sim.troop_specs[u["type"]]["maxLevel"])
	if sim.troop_specs[u["type"]]["role"] == "combat":
		_label("Defense duty: " + str(u.get("defense_priority", "patrol")).capitalize(), side_content, true)
		for priority in Sim.DEFENSE_PRIORITIES:
			var duty_btn: Button = _button(str(priority).capitalize(), _set_defender_priority.bind(int(u["id"]), str(priority)), side_content)
			duty_btn.disabled = priority == "rally" and sim.rally_point.x < 0
	for b: Dictionary in sim.buildings:
		if str(sim.building_specs[b["type"]].get("workplace", "")) == str(u["type"]) and b["hp"] > 0 and b["remaining"] <= 0:
			_button("Assign to %s #%d" % [sim.building_specs[b["type"]]["name"], b["id"]], _assign.bind(selected_unit, int(b["id"])), side_content)
	if int(u["workplace"]) >= 0:
		_button("Release workplace", _assign.bind(selected_unit, -1), side_content)
	_refresh_inspector()



func _refresh_inspector() -> void:
	if panel == "building" and inspect_text != null:
		var shown: Dictionary = sim.get_building(selected_building)
		if not shown.is_empty():
			inspect_text.text = "Tier %d / HP %d of %d\nOn-site reserve %d / %d\nCollect whenever you need it." % [shown["tier"], shown["hp"], shown["max_hp"], shown["reserve"], sim.reserve_cap(shown)]
	elif panel == "unit" and inspect_text != null:
		var unit: Dictionary = sim.get_unit(selected_unit)
		if not unit.is_empty():
			inspect_text.text = "HP %d / %d\nDuty: %s\nCarrying: %d %s" % [unit["hp"], unit["max_hp"], unit["phase"], unit["carry"], str(unit["carry_resource"]).capitalize()]
	_refresh_actions()


# The bottom action bar always mirrors the live selection, whatever panel is open.
func _refresh_actions() -> void:
	if collect_button == null:
		return
	var b: Dictionary = sim.get_building(selected_building)
	if b.is_empty():
		collect_button.disabled = sim.buildings.is_empty()
		collect_button.tooltip_text = "Collect from every workplace"
	else:
		collect_button.disabled = float(b.get("reserve", 0.0)) < 1 or float(b.get("hp", 0.0)) <= 0 or float(b.get("remaining", 0.0)) > 0
		collect_button.tooltip_text = "Bank the on-site reserve of %s" % str(sim.building_specs[b["type"]]["name"])
	upgrade_button.disabled = b.is_empty() or not sim.upgrade_reason(selected_building).is_empty()
	upgrade_button.tooltip_text = sim.upgrade_reason(selected_building) if not b.is_empty() else "Select a building"
	repair_button.disabled = b.is_empty() or float(b["hp"]) >= float(b["max_hp"]) or float(b["remaining"]) > 0
	repair_button.tooltip_text = "Repair spends 15 HP per Wood" if not b.is_empty() else "Select a building"
	move_button.disabled = b.is_empty() or sim.raid_active or sim.raid_warning or float(b.get("remaining", 0.0)) > 0
	move_button.tooltip_text = "Relocate the site" if not b.is_empty() else "Select a building"
	if workers_button != null:
		workers_button.disabled = sim.units.is_empty()


func _close_panel() -> void:
	if panel == "pause":
		paused = false
	panel = ""
	sidebar.hide()


func _pause_panel() -> void:
	_label("QUIET HOURS", side_content, true)
	_label("Simulation is paused. Your village saves locally; closed time does not generate resources.", side_content)
	_button("Resume", _close_panel, side_content)
	_button("Save now", _save_now, side_content)
	var update_btn: Button = _button("Update Game", _update_game, side_content)
	update_btn.tooltip_text = "Save the village and reload the latest build."
	_button("Day / Night", _toggle_day, side_content)
	_button("Sound On / Off", _toggle_sound, side_content)
	grid_button = _button("Grid: On" if show_grid else "Grid: Off", _toggle_grid, side_content)
	grid_button.tooltip_text = "Show or hide the 20x16 tile grid."
	power_button = _button("Battery saver: On" if battery_saver else "Battery saver: Off", _toggle_power, side_content)
	power_button.tooltip_text = "Cap at 30 fps to save battery."
	shadow_button = _button("Shadows: On" if shadows_on else "Shadows: Off", _toggle_shadows, side_content)
	shadow_button.tooltip_text = "Toggle sun shadows (biggest phone speedup)."
	_button("Recenter camera", _recenter, side_content)
	_label("Core-loop prototype. Campaign, advanced gear/abilities and multiplayer remain future work.", side_content)


func _enter_village() -> void:
	started = true
	sim.paused = paused or not focused
	welcome.hide()
	if not save_blocked:
		sim.notice = "The Manor stands. Raise a second farm, then dig a pond."
	music.enter("night" if night else "day")
	music.set_calm(sim.paused)
	music.set_enabled(sound)
	_refresh_hud()


func _open_pause() -> void:
	paused = true
	_open_panel("pause")


func _choose_build(type_name: String) -> void:
	build_type = type_name
	moving_id = -1
	paving = false
	rallying = false
	wall_drag_start = Vector2i(-1, -1)
	selected_building = -1
	selected_unit = -1
	preview_tile = Vector2i(-1, -1)
	more_sheet.hide()
	_close_panel()
	placement_box.show()
	placement_label.text = "Place " + str(sim.building_specs[type_name]["name"]) + " / drag or tap the map"
	confirm_button.disabled = true
	confirm_button.text = "Confirm Build"


func _toggle_pave() -> void:
	if paving:
		_cancel_placement()
		return
	paving = true
	rallying = false
	wall_drag_start = Vector2i(-1, -1)
	build_type = ""
	moving_id = -1
	selected_building = -1
	selected_unit = -1
	preview_tile = Vector2i(-1, -1)
	more_sheet.hide()
	_close_panel()
	placement_box.show()
	placement_label.text = "Pave stone road / click a worn dirt trail"
	confirm_button.disabled = true
	confirm_button.text = "Confirm Pave"


func _placement_active() -> bool:
	return rallying or paving or not build_type.is_empty()


func _placement_reason() -> String:
	if preview_tile.x < 0:
		return "Click a tile on the map"
	if rallying:
		if "fortifications" not in sim.living.discoveries:
			return "Research Fortifications first."
		return "" if not sim._blocked(preview_tile, false) else "Place the rally point on open ground."
	if paving:
		return sim.living.pave_reason(sim, preview_tile)
	if moving_id < 0 and build_type in ["wall", "stonewall"] and wall_drag_start.x >= 0:
		return sim.wall_line_reason(build_type, wall_drag_start, preview_tile)
	return sim.build_reason(build_type, preview_tile.x, preview_tile.y, moving_id)


func _preview() -> void:
	if not _placement_active():
		return
	var reason: String = _placement_reason()
	confirm_button.disabled = not reason.is_empty()
	var headline: String = "Rally point" if rallying else ("Stone road" if paving else str(sim.building_specs[build_type]["name"]))
	var detail: String = "No cost" if rallying else _cost_text({"stone": int(sim.living.config["stone"]["pave_cost"])})
	if not rallying and not paving:
		if moving_id >= 0:
			detail = "Move here / no cost"
		elif build_type in ["wall", "stonewall"] and wall_drag_start.x >= 0:
			var line_tiles: Array[Vector2i] = sim.wall_line_tiles(wall_drag_start, preview_tile)
			var one: Dictionary = sim.building_cost(build_type)
			var total: Dictionary = {}
			for resource in one:
				total[resource] = float(one[resource]) * line_tiles.size()
			detail = "%d segments / %s" % [line_tiles.size(), _cost_text(total)]
		else:
			detail = _cost_text(sim.building_cost(build_type))
	placement_label.text = "%s  /  tile %d, %d\n%s" % [headline, preview_tile.x, preview_tile.y, reason if not reason.is_empty() else detail]
	var signature: String = "%s/%s/%s/%s" % ["rally" if rallying else ("pave" if paving else build_type), wall_drag_start, preview_tile, reason]
	if signature == ghost_signature:
		return
	ghost_signature = signature
	for child in ghost_layer.get_children():
		ghost_layer.remove_child(child)
		child.queue_free()
	if preview_tile.x < 0:
		return
	var tint: Color = Color("d4b275") if rallying else (Color("b9bcc0") if paving else Color("93d78a"))
	var tiles: Array = [preview_tile]
	if not rallying and not paving and moving_id < 0 and build_type in ["wall", "stonewall"] and wall_drag_start.x >= 0:
		tiles = sim.wall_line_tiles(wall_drag_start, preview_tile)
	for tile in tiles:
		var size: int = 1 if rallying or paving or build_type in ["wall", "stonewall"] else int(sim.building_specs[build_type]["size"])
		var centre := Vector2(tile) + Vector2.ONE * size * 0.5
		var ghost: MeshInstance3D = _box(Vector3(size * TILE - 0.1, 0.14, size * TILE - 0.1), world_position(centre, 0.12), tint if reason.is_empty() else Color("d26c62"), ghost_layer)
		var material: StandardMaterial3D = ghost.material_override
		material.albedo_color.a = 0.65
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _confirm_placement() -> void:
	if rallying:
		if sim.set_rally(float(preview_tile.x) + 0.5, float(preview_tile.y) + 0.5):
			_cancel_placement()
			_update_marker()
			_open_panel("defense")
		_refresh_hud()
		return
	if paving:
		# Paving stays active so a run of tiles can be laid; every tile is confirmed separately.
		if sim.living.pave(sim, preview_tile):
			_update_roads()
			_refresh_hud()
			_preview()
		return
	var success: bool = false
	if moving_id < 0 and build_type in ["wall", "stonewall"] and wall_drag_start.x >= 0:
		success = sim.build_wall_line(build_type, wall_drag_start, preview_tile)
		if success:
			wall_drag_start = Vector2i(-1, -1)
	else:
		success = sim.move_building(moving_id, preview_tile.x, preview_tile.y) if moving_id >= 0 else sim.build(build_type, preview_tile.x, preview_tile.y)
	if success:
		if build_type not in ["wall", "stonewall", "gate"] or moving_id >= 0:
			_cancel_placement()
		_rebuild_buildings()
	_preview()
	_refresh_hud()


func _cancel_placement() -> void:
	build_type = ""
	paving = false
	rallying = false
	wall_drag_start = Vector2i(-1, -1)
	moving_id = -1
	ghost_signature = ""
	confirm_button.text = "Confirm Build"
	placement_box.hide()
	for child in ghost_layer.get_children():
		child.queue_free()


func _collect_selected() -> void:
	# With nothing selected the bar collects everywhere, which keeps the compact button useful.
	if sim.get_building(selected_building).is_empty():
		sim.collect_all()
	else:
		sim.collect(selected_building)
		_open_panel("building")
	_refresh_hud()


func _upgrade_selected() -> void:
	sim.upgrade(selected_building)
	_rebuild_buildings()
	_open_panel("building")


func _repair_selected() -> void:
	sim.repair(selected_building)
	_rebuild_buildings()
	_open_panel("building")


func _move_selected() -> void:
	var b: Dictionary = sim.get_building(selected_building)
	if b.is_empty():
		return
	_choose_build(str(b["type"]))
	moving_id = int(b["id"])
	confirm_button.text = "Confirm Move"


func _select_unit(id: int) -> void:
	selected_unit = id
	selected_building = -1
	_open_panel("unit")
	_update_marker()


func _assign(unit_id: int, building_id: int) -> void:
	sim.assign(unit_id, building_id)
	_open_panel(panel)
	_refresh_hud()


func _hire(role: String) -> void:
	sim.recruit(role)
	_open_panel("people")
	_refresh_hud()


func _hold_selected() -> void:
	var u: Dictionary = sim.get_unit(selected_unit)
	if not u.is_empty():
		sim.order_unit(selected_unit, float(u["x"]), float(u["y"]), true)


func _resume_selected() -> void:
	var u: Dictionary = sim.get_unit(selected_unit)
	if not u.is_empty():
		u["order"] = []
		u["hold"] = false
		sim.notice = "Duty resumed."


func _train_selected() -> void:
	sim.train(selected_unit)
	_open_panel("unit")



func _toggle_rally() -> void:
	build_type = ""
	moving_id = -1
	paving = false
	rallying = true
	wall_drag_start = Vector2i(-1, -1)
	preview_tile = Vector2i(-1, -1)
	_close_panel()
	placement_box.show()
	placement_label.text = "Place defender rally point / tap open ground"
	confirm_button.disabled = true
	confirm_button.text = "Set Rally"


func _set_defender_priority(unit_id: int, priority: String) -> void:
	sim.set_defense_priority(unit_id, priority)
	if panel == "defense":
		_open_panel("defense")
	elif panel == "unit":
		_open_panel("unit")
	_refresh_hud()


func _post_defender_here(unit_id: int) -> void:
	sim.assign_defense_post(unit_id, selected_building)
	if panel == "building":
		_open_panel("building")
	_refresh_hud()


func _set_tower_mode(mode: String) -> void:
	sim.set_tower_targeting(selected_building, mode)
	if panel == "building":
		_open_panel("building")
	_refresh_hud()


func _upgrade_connected_wall() -> void:
	sim.upgrade_wall_line(selected_building)
	_rebuild_buildings()
	if panel == "building":
		_open_panel("building")
	_refresh_hud()


func _repair_connected_wall() -> void:
	sim.repair_wall_line(selected_building)
	_rebuild_buildings()
	if panel == "building":
		_open_panel("building")
	_refresh_hud()

func _insert_gate_selected() -> void:
	if sim.insert_gate(selected_building):
		_rebuild_buildings()
		_open_selected_commands()
	_refresh_hud()


func _test_raid() -> void:
	sim.start_raid(20.0)
	_open_panel("defense")
	_refresh_hud()


func _save_now() -> void:
	if not no_save and not save_blocked:
		if sim.save_game(save_path):
			sim.notice = "Village saved."
	_refresh_hud()


func _update_game() -> void:
	# Live update: save the village, then reload so the newest
	# deployed build boots. Web saves live in user:// (IndexedDB),
	# so progress survives the refresh. Never reload on a failed save.
	if not no_save and not save_blocked:
		if sim.save_game(save_path):
			sim.notice = "Village saved. Loading the latest build…"
		else:
			sim.notice = "Save failed. Update cancelled — your village is untouched."
			_refresh_hud()
			return
	else:
		sim.notice = "Saving is blocked. Update cancelled."
		_refresh_hud()
		return
	_refresh_hud()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
	else:
		get_tree().reload_current_scene()


func _toggle_day() -> void:
	night = not night
	music.set_mood("night" if night else "day")
	_apply_lighting()


func _toggle_sound() -> void:
	sound = not sound
	sim.notice = "Sound on" if sound else "Sound off"
	music.set_enabled(sound)
	_save_settings()


func _recenter() -> void:
	target = Vector3.ZERO
	yaw = 0.66
	tilt = 0.75
	zoom = 31
	_camera_update()


func _orbit_step(direction: float) -> void:
	yaw += direction * PI / 8.0
	_camera_update()


func _orbit_left() -> void:
	_orbit_step(-1.0)


func _orbit_right() -> void:
	_orbit_step(1.0)


func _refresh_hud() -> void:
	if build_cards.has("stone_quarry") and is_instance_valid(build_cards["stone_quarry"]):
		build_cards["stone_quarry"].disabled = "stoneworking" not in sim.living.discoveries
	if panel == "people" and roster_count != sim.units.size():
		_open_panel("people")
	for role in hire_buttons:
		var reason: String = sim.recruit_reason(role)
		hire_buttons[role].disabled = not reason.is_empty()
		hire_buttons[role].tooltip_text = reason
	for resource: String in resource_rows:
		var cap: int = int(sim.storage_cap(resource))
		var held: int = int(sim.resources.get(resource, 0))
		if _is_small():
			resource_rows[resource].text = "%s %d" % [resource.capitalize(), held]
		else:
			resource_rows[resource].text = "%s  %d / %d" % [resource.capitalize(), held, cap]
		var gauge: ProgressBar = resource_bars[resource]
		gauge.max_value = maxf(1.0, float(cap))
		gauge.value = float(held)
	hud.text = "People %d/%d    Level %d    %d XP" % [sim.units.size(), sim.beds(), sim.village_level(), sim.xp]
	var quest: Dictionary = sim.quest_current()
	quest_label.text = "Village Path complete" if quest.is_empty() else "PATH / " + str(quest["name"])
	if sim.raid_active:
		var active_counts: Dictionary = {}
		for enemy in sim.enemies:
			active_counts[enemy["type"]] = int(active_counts.get(enemy["type"], 0)) + 1
		var active_parts: Array = []
		for kind in active_counts:
			active_parts.append("%d %s" % [int(active_counts[kind]), str(kind)])
		raid_hud.text = "WAVE %d / %s / HOLD THE MANOR" % [sim.wave, ", ".join(active_parts)]
		music.set_mood("danger")
	elif sim.raid_warning:
		var intel: Dictionary = sim.raid_preview()
		var warning_parts: Array = []
		for kind in intel["composition"]:
			warning_parts.append("%d %s" % [int(intel["composition"][kind]), str(kind)])
		raid_hud.text = "HORNS %.0fs / %s / %s" % [maxf(0.0, sim.next_raid_at - sim.elapsed), ", ".join(intel["sides"]), ", ".join(warning_parts)]
		music.set_mood("tension")
	else:
		raid_hud.text = "Quiet / next horns in %.0fs" % maxf(0, sim.next_raid_at - sim.elapsed - 25)
		music.set_mood("night" if night else "day")
	music.set_calm(sim.paused)
	if _is_small():
		hud.text = "People %d/%d / Lv%d" % [sim.units.size(), sim.beds(), sim.village_level()]
		quest_label.text = "Path complete" if quest.is_empty() else str(quest["name"])
		if not sim.raid_active and not sim.raid_warning:
			raid_hud.text = "Horns in %.0fs" % maxf(0, sim.next_raid_at - sim.elapsed - 25)
	_refresh_research()
	if sim.raid_active or sim.raid_warning:
		research_label.text = "Research waits until the alarm passes."
	elif not sim.living.active.is_empty():
		research_label.text = "Working / %s  %.0fs" % [str(sim.living.config["research"]["nodes"][sim.living.active]["name"]), sim.living.remaining]
	else:
		research_label.text = "Insight %d / %d" % [int(sim.living.insight), int(sim.living.config["research"]["insight_cap"])]
	message.text = ("PAUSED / " if sim.paused else "") + sim.notice
	toast_label.text = ("PAUSED / " if sim.paused else "") + sim.notice
	_refresh_inspector()
	_layout_ui()


func _refresh_research() -> void:
	for id: Variant in research_buttons:
		var key := str(id)
		var node: Dictionary = sim.living.config["research"]["nodes"].get(key, {})
		var button: Button = research_buttons[key]
		if node.is_empty():
			button.disabled = true
			continue
		var state := "READY"
		if key in sim.living.discoveries:
			state = "DONE"
		elif sim.living.active == key:
			state = "%.0fs LEFT" % sim.living.remaining
		var reason: String = sim.living.research_reason(sim, key)
		if state == "READY" and not reason.is_empty(): state = "LOCKED"
		button.text = "%s\n%s / %d Insight" % [str(node["name"]), state, int(node["insight"])]
		button.disabled = state != "READY" or not reason.is_empty()
		button.tooltip_text = _research_cost(node) + "\n" + str(node["description"]) + ("\n" + reason if not reason.is_empty() else "")
	for id: Variant in research_sheet_buttons:
		var key := str(id)
		var button: Button = research_sheet_buttons[key]
		if not is_instance_valid(button):
			continue
		var node: Dictionary = sim.living.config["research"]["nodes"].get(key, {})
		if node.is_empty():
			continue
		var state := "READY"
		if key in sim.living.discoveries:
			state = "DONE"
		elif sim.living.active == key:
			state = "%.0fs LEFT" % sim.living.remaining
		var reason: String = sim.living.research_reason(sim, key)
		if state == "READY" and not reason.is_empty():
			state = "LOCKED"
		button.text = "%s\n%s / %d Insight" % [str(node["name"]), state, int(node["insight"])]
		button.disabled = state != "READY"
		button.tooltip_text = str(node["description"]) if reason.is_empty() else reason


func _setup_audio() -> void:
	add_child(sfx)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(6615 * 2)
	for sample in 6615:
		var seconds: float = float(sample) / 22050
		var value: int = int(sin(seconds * TAU * 880) * exp(-seconds * 16) * 7000)
		bytes.encode_s16(sample * 2, value)
	stream.data = bytes
	sfx.stream = stream
	sfx.volume_db = -13


func _consume_events() -> void:
	for index in range(effect_nodes.size() - 1, -1, -1):
		if not is_instance_valid(effect_nodes[index]):
			effect_nodes.remove_at(index)
	for event: Dictionary in sim.events:
		# Effects are decoration only; the cap keeps a busy raid from flooding the scene.
		if effect_nodes.size() >= EFFECT_LIMIT:
			break
		if event.get("kind") == "collect":
			var label := Label3D.new()
			label.text = "+%d %s" % [event["amount"], str(event["resource"]).capitalize()]
			label.modulate = GOLD
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 42
			label.pixel_size = 0.014
			label.position = world_position(Vector2(float(event["x"]), float(event["y"])), 3.5)
			add_child(label)
			effect_nodes.append(label)
			var tween: Tween = create_tween()
			tween.tween_property(label, "position:y", label.position.y + 2, 1.5)
			tween.parallel().tween_property(label, "modulate:a", 0.0, 1.5)
			tween.tween_callback(label.queue_free)
			if sound:
				sfx.play()
		elif event.get("kind") == "shot":
			var from_point: Vector3 = world_position(Vector2(float(event["from_x"]), float(event["from_y"])), 1.8)
			var to_point: Vector3 = world_position(Vector2(float(event["x"]), float(event["y"])), 1)
			var projectile: MeshInstance3D = _box(Vector3(0.09, 0.09, 0.35), from_point, GOLD)
			effect_nodes.append(projectile)
			var tween: Tween = create_tween()
			tween.tween_property(projectile, "position", to_point, 0.16)
			tween.tween_callback(projectile.queue_free)
	sim.events.clear()


func _process(delta: float) -> void:
	sim.paused = not started or paused or (not focused and capture_path.is_empty())
	if not sim.paused:
		tick_accumulator += minf(delta, 0.25)
		while tick_accumulator >= 0.05:
			sim.tick(0.05)
			tick_accumulator -= 0.05
		save_accumulator += delta
		if save_accumulator >= 5 and not no_save and not save_blocked:
			sim.save_game(save_path)
			save_accumulator = 0
	else:
		tick_accumulator = 0
	if view_revision != sim.revision:
		_rebuild_buildings()
	_update_roads()
	_update_actors(delta)
	details.update(self, delta)
	_consume_events()
	ui_accumulator += delta
	if ui_accumulator >= 0.25:
		ui_accumulator = 0
		_refresh_hud()
		_preview()
	if started and not paused:
		var orbit: float = float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
		var pan := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		var elevation: float = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))
		if orbit != 0 or pan != Vector2.ZERO or elevation != 0:
			yaw += orbit * delta
			tilt = clampf(tilt + elevation * delta * 0.4, 0.3, 1.25)
			target += Vector3(cos(yaw) * pan.x + sin(yaw) * pan.y, 0, -sin(yaw) * pan.x + cos(yaw) * pan.y) * delta * 12
			_camera_update()


func pick_ground(screen: Vector2) -> Vector2:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	if absf(direction.y) < 0.00001:
		return Vector2(-1, -1)
	var t: float = -origin.y / direction.y
	if t < 0:
		return Vector2(-1, -1)
	var point: Vector3 = origin + direction * t - MAP_ORIGIN
	return Vector2(point.x, point.z) / TILE


func _map_click(screen: Vector2) -> void:
	var point: Vector2 = pick_ground(screen)
	var tile := Vector2i(floori(point.x), floori(point.y))
	if tile.x < 0 or tile.x >= 20 or tile.y < 0 or tile.y >= 16:
		return
	if _placement_active():
		if not rallying and not paving and moving_id < 0 and build_type in ["wall", "stonewall"] and "fortifications" in sim.living.discoveries and wall_drag_start.x < 0:
			wall_drag_start = tile
		preview_tile = tile
		_preview()
		return
	# Actor screen-distance picking follows the rendered body, not floor projection.
	for u: Dictionary in sim.units:
		var p: Vector2 = camera.unproject_position(world_position(sim.position_of(u), 0.8))
		if p.distance_to(screen) < 18:
			_select_unit(int(u["id"]))
			return
	for b: Dictionary in sim.buildings:
		var bounds := Rect2(Vector2(float(b["x"]), float(b["y"])), Vector2.ONE * int(b["size"]))
		if bounds.has_point(point):
			selected_building = int(b["id"])
			selected_unit = -1
			_open_panel("building")
			return
	if selected_unit >= 0:
		sim.order_unit(selected_unit, point.x, point.y)
		sim.notice = "Marching orders sent."
	else:
		selected_building = -1
		_close_panel()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = false
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = false
		if event.button_index == MOUSE_BUTTON_LEFT and left_pressed:
			if not left_dragged and get_viewport().gui_get_hovered_control() == null:
				_map_click(event.position)
			left_pressed = false
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() >= 2:
				if get_viewport().gui_get_hovered_control() == null:
					_pinch_begin()
			elif event.index == 0 and get_viewport().gui_get_hovered_control() == null:
				left_pressed = true
				left_dragged = false
				press_point = event.position
				last_pointer = event.position
		else:
			touches.erase(event.index)
			if touches.size() >= 2:
				_pinch_begin()
			else:
				pinch_has_mid = false
				pinch_dist = 0.0
				pinch_active = false
			if touches.is_empty():
				if event.index == 0 and left_pressed and not left_dragged and get_viewport().gui_get_hovered_control() == null:
					_map_click(event.position)
				left_pressed = false
				left_dragged = false
			elif touches.size() == 1:
				_pinch_rebase_single()
		return
	if event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() >= 2 and pinch_active:
			_pinch_update()
		elif touches.size() == 1 and left_pressed:
			_drag_map(event.position)
		return


func _pinch_begin() -> void:
	var pts: Array = touches.values()
	if pts.size() < 2:
		return
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	pinch_dist = maxf(a.distance_to(b), 1.0)
	pinch_zoom = zoom
	pinch_mid = (a + b) * 0.5
	pinch_has_mid = false
	pinch_active = true
	left_pressed = false
	left_dragged = true


func _pinch_update() -> void:
	var pts: Array = touches.values()
	if pts.size() < 2 or pinch_zoom <= 0.0:
		return
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var cur_dist: float = maxf(a.distance_to(b), 1.0)
	zoom = clampf(pinch_zoom * pinch_dist / cur_dist, 12, 55)
	var mid: Vector2 = (a + b) * 0.5
	if pinch_has_mid:
		var movement: Vector2 = pick_ground(pinch_mid) - pick_ground(mid)
		target += Vector3(movement.x * TILE, 0, movement.y * TILE)
		target.x = clampf(target.x, -20, 20)
		target.z = clampf(target.z, -16, 16)
	pinch_mid = mid
	pinch_has_mid = true
	_camera_update()
	last_pointer = mid


func _pinch_rebase_single() -> void:
	for key in touches.keys():
		last_pointer = touches[key]
		press_point = touches[key]
	left_pressed = true
	left_dragged = true


func _drag_map(pointer: Vector2) -> void:
	if not left_pressed:
		return
	if _placement_active():
		var point: Vector2 = pick_ground(pointer)
		var tile := Vector2i(floori(point.x), floori(point.y))
		if not rallying and not paving and moving_id < 0 and build_type in ["wall", "stonewall"] and "fortifications" in sim.living.discoveries:
			if wall_drag_start.x < 0:
				var start_point: Vector2 = pick_ground(press_point)
				wall_drag_start = Vector2i(floori(start_point.x), floori(start_point.y))
			if pointer.distance_to(press_point) > 8.0:
				left_dragged = true
		preview_tile = tile
		_preview()
	elif pointer.distance_to(press_point) > 16.0 or left_dragged:
		left_dragged = true
		var movement: Vector2 = pick_ground(last_pointer) - pick_ground(pointer)
		target += Vector3(movement.x * TILE, 0, movement.y * TILE)
		target.x = clampf(target.x, -20, 20)
		target.z = clampf(target.z, -16, 16)
		_camera_update()
	last_pointer = pointer


func _unhandled_input(event: InputEvent) -> void:
	if not started:
		return
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_ESCAPE:
			if _placement_active():
				_cancel_placement()
			elif sidebar.visible:
				_close_panel()
			else:
				_open_pause()
		if event.physical_keycode == KEY_0:
			_recenter()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 12, 55)
			_camera_update()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			left_pressed = true
			left_dragged = false
			press_point = event.position
			last_pointer = event.position
			if _placement_active():
				_map_click(event.position)
	if event is InputEventMouseMotion:
		_drag_map(event.position)
		if dragging:
			yaw -= event.relative.x * 0.007
			tilt = clampf(tilt + event.relative.y * 0.004, 0.3, 1.25)
			_camera_update()
		if panning:
			target += Vector3(-event.relative.x, 0, -event.relative.y) * 0.025
			_camera_update()
	if event is InputEventPanGesture:
		target += Vector3(event.delta.x, 0, event.delta.y) * 0.03
		_camera_update()
	if event is InputEventMagnifyGesture:
		zoom = clampf(zoom / event.factor, 12, 55)
		_camera_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		touches.clear()
		left_pressed = false
		left_dragged = false
		pinch_active = false
		pinch_dist = 0.0
		pinch_has_mid = false
		if started and not no_save and not save_blocked:
			sim.save_game(save_path)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if started and not no_save and not save_blocked:
			sim.save_game(save_path)
		get_tree().quit()


func _capture() -> void:
	if DisplayServer.get_name() == "headless" or not capture_path.is_absolute_path():
		get_tree().quit(1)
		return
	await get_tree().create_timer(2.5 if capture_catalog else 1.4).timeout
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(capture_path)
	print("GAME_CAPTURE ", result)
	get_tree().quit(0 if result == OK else 1)


func _showcase() -> void:
	# Explicit capture-only QA fixture; never run for a player's saved village.
	if capture_path.is_empty(): return
	sim.resources["stone"] = 160
	sim.living.discoveries.assign(["stoneworking", "road_masonry"])
	for x in range(3, 14):
		sim.living.cells["%d,11" % x] = {"wear": 1.0, "last": sim.elapsed, "stone": x >= 8}
	sim.living.revision += 1
	sim.living.navigation_revision += 1
	sim.buildings.append(sim._new_building("stone_quarry", 14, 10, false))
	sim.buildings.append(sim._new_building("gate", 5, 11, false))
	sim.buildings.append(sim._new_building("wall", 5, 12, false))
	sim.buildings.append(sim._new_building("cottage", 14, 6, true))
	sim.revision += 1
	_rebuild_buildings()
	_update_roads()
	sim.notice = "QA preview / accelerated roads and research / player save untouched."
