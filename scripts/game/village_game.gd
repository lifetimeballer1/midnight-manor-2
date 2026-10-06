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
# Resource glyphs stay monochrome brass so the numbers stay the loudest thing.
const RESOURCE_GLYPHS: Dictionary = {"wood": "W", "food": "F", "gold": "G", "lumber": "L", "stone": "S"}

var sim = Sim.new()
var camera := Camera3D.new()
var environment := Environment.new()
var sun := DirectionalLight3D.new()
var fill := DirectionalLight3D.new()
var fireflies: CPUParticles3D
var mist: CPUParticles3D
var stars: MeshInstance3D
var building_layer := Node3D.new()
var actor_layer := Node3D.new()
var ghost_layer := Node3D.new()
var selection_marker := MeshInstance3D.new()
var models: Dictionary = {}
var tint_cache: Dictionary = {}
var player_paths: Dictionary = {}
var actors: Dictionary = {}
var building_views: Dictionary = {}
var catalog: Dictionary = {}
var hud := Label.new()
var raid_hud := Label.new()
var message := Label.new()
var inspect_text: Label
var inspect_hp: ProgressBar
var inspect_reserve: ProgressBar
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
var alarm_latched: bool = false
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
var pinch_angle: float = 0.0
var pinch_yaw: float = 0.0
var touch_mode: bool = false
var placement_anchor := Vector2i(-1, -1)
var placement_row: Array[Vector2i] = []
var actor_accumulator: float = 0.0
var detail_accumulator: float = 0.0
var lamp_accumulator: float = 0.0
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
# TEMP raid-start instrumentation (removed before commit).
var spike_active: bool = false
var spike_lines: Array[String] = []
var spike_next: float = 0.0
var spike_worst_tick: float = 0.0
var spike_worst_actors: float = 0.0
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
var more_button: Button
var collect_all_button: Button
var collect_glow: bool = false
var repair_all_button: Button
var repair_glow: bool = false
var nav_compact: bool = false
var inspect_collect: Button
var inspect_upgrade: Button
var path_button: Button
var research_button: Button
var row_upgrade_button: Button
var more_pave_button: Button
var more_chronicle_button: Button
var more_tech_button: Button
var more_frontier_button: Button
var more_board_button: Button
var more_doctrine_button: Button
var welcome_help: Label
var combat_banner := Label.new()
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
var capture_panel: String = ""
var research_list := VBoxContainer.new()
# --- Manor Chronicle surfaces -------------------------------------------------
var tech_branch: String = ""
var banner_panel := PanelContainer.new()
var banner_row := HBoxContainer.new()
var banner_label: Label
var banner_left: float = 0.0
var story_banner: Control
var title_label: Label
var crest_label: Label
var pop_label: Label
var level_bar: ProgressBar
var horn_label: Label
var objective_label: Label
var tech_node_buttons: Dictionary = {}


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
		if arg.begins_with("--ui="): capture_panel = arg.trim_prefix("--ui=")
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
		if not capture_panel.is_empty():
			_seed_capture_panel()
			_open_panel(capture_panel)
		_capture()


# Capture-only fixture so the Manor screens can be verified visually without a
# player's save. Never runs during normal play.
func _seed_capture_panel() -> void:
	sim.resources["wood"] = 4000
	sim.resources["food"] = 900
	sim.resources["gold"] = 600
	sim.xp = 1500
	sim.chronicle.act = 3
	sim.living.insight = 180
	sim.living.discoveries.assign(["stoneworking", "road_masonry", "moon_orchards"])
	sim.chronicle.grant_many(sim.chronicle.node("road_masonry").get("unlocks", []), "research:road_masonry")
	sim.chronicle.grant("watchfire", "test")
	sim.build("watchfire", 6, 2)
	for unit in [1.0, 2.0]:
		sim.tick(unit * 0.05)
	sim.raid_warning = true
	sim.raid_active = true
	sim.chronicle.queue_banner("Rue the turncloak", "The eastern road has gone quiet. Send a Wayfinder beyond the wall.")


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
	var glow_ramp := Gradient.new()
	glow_ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	glow_ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.disable_receive_shadows = true
	glow_material.vertex_color_use_as_albedo = true
	glow_material.albedo_color = Color("ffffff")
	var glow_core := Gradient.new()
	glow_core.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	glow_core.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_core
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow_texture.width = 64
	glow_texture.height = 64
	glow_material.albedo_texture = glow_texture
	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2(0.42, 0.42)
	glow_quad.material = glow_material
	fireflies = CPUParticles3D.new()
	fireflies.name = "Fireflies"
	fireflies.mesh = glow_quad
	fireflies.amount = 70
	fireflies.lifetime = 7.0
	fireflies.preprocess = 7.0
	fireflies.local_coords = false
	fireflies.position = Vector3(0, 1.6, 0)
	fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fireflies.emission_box_extents = Vector3(19, 1.4, 15)
	fireflies.direction = Vector3(0, 1, 0)
	fireflies.spread = 180.0
	fireflies.gravity = Vector3.ZERO
	fireflies.initial_velocity_min = 0.15
	fireflies.initial_velocity_max = 0.55
	fireflies.scale_amount_min = 0.7
	fireflies.scale_amount_max = 1.4
	fireflies.color_ramp = glow_ramp
	fireflies.color = Color("c9f070")
	fireflies.visible = night
	scenery.add_child(fireflies)
	var mist_ramp := Gradient.new()
	mist_ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	mist_ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var mist_core := Gradient.new()
	mist_core.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	mist_core.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var mist_texture := GradientTexture2D.new()
	mist_texture.gradient = mist_core
	mist_texture.fill = GradientTexture2D.FILL_RADIAL
	mist_texture.fill_from = Vector2(0.5, 0.5)
	mist_texture.fill_to = Vector2(1.0, 0.5)
	mist_texture.width = 128
	mist_texture.height = 128
	var mist_material := StandardMaterial3D.new()
	mist_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mist_material.vertex_color_use_as_albedo = true
	mist_material.albedo_texture = mist_texture
	mist_material.albedo_color = Color(0.62, 0.7, 0.85, 0.35)
	mist_material.disable_receive_shadows = true
	var mist_quad := QuadMesh.new()
	mist_quad.size = Vector2(8, 8)
	mist_quad.material = mist_material
	mist = CPUParticles3D.new()
	mist.name = "Mist"
	mist.mesh = mist_quad
	mist.amount = 22
	mist.lifetime = 20.0
	mist.preprocess = 20.0
	mist.local_coords = false
	mist.position = Vector3(0, 0.5, 0)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(21, 0.1, 17)
	mist.direction = Vector3(1, 0, 0.3)
	mist.spread = 25.0
	mist.gravity = Vector3.ZERO
	mist.initial_velocity_min = 0.25
	mist.initial_velocity_max = 0.5
	mist.scale_amount_min = 0.7
	mist.scale_amount_max = 1.3
	mist.color_ramp = mist_ramp
	mist.visible = night
	scenery.add_child(mist)
	var star_image := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	star_image.fill(Color(0, 0, 0, 0))
	var star_rng := RandomNumberGenerator.new()
	star_rng.seed = 77
	for star_index in 150:
		var sx: int = star_rng.randi_range(2, 1021)
		var sy: int = star_rng.randi_range(2, 1021)
		var bright: float = star_rng.randf_range(0.5, 1.0)
		var tint: Color = Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.95, 0.8), star_rng.randf())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var falloff: float = 1.0 if dx == 0 and dy == 0 else (0.55 if dx == 0 or dy == 0 else 0.3)
				star_image.set_pixel(sx + dx, sy + dy, Color(tint.r, tint.g, tint.b, bright * falloff))
	star_image.generate_mipmaps()
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_material.albedo_texture = ImageTexture.create_from_image(star_image)
	star_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	star_material.uv1_scale = Vector3(10, 10, 1)
	star_material.disable_fog = true
	star_material.disable_receive_shadows = true
	var star_plane := PlaneMesh.new()
	star_plane.size = Vector2(400, 400)
	stars = MeshInstance3D.new()
	stars.name = "Stars"
	stars.mesh = star_plane
	stars.material_override = star_material
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.position = Vector3(0, -9.0, 0)
	stars.visible = night
	scenery.add_child(stars)


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
	environment.fog_enabled = true
	environment.fog_light_color = Color("2a2f52") if night else Color("c9d8dc")
	environment.fog_density = 0.006 if night else 0.002
	environment.fog_sky_affect = 0.0 if night else 1.0
	sun.light_color = Color("ffc48a") if night else Color("fff2cf")
	sun.light_energy = 0.85 if night else 1.0
	if is_instance_valid(fireflies):
		fireflies.visible = night and not battery_saver
	if is_instance_valid(mist):
		mist.visible = night and not battery_saver
	if is_instance_valid(stars):
		stars.visible = night
	_update_light_pool()


func _flicker_lamps() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	for id in building_views:
		var lamp: OmniLight3D = building_views[id].get("lamp")
		if is_instance_valid(lamp) and lamp.visible:
			var phase: float = float(id) * 1.7
			lamp.light_energy = 1.15 * (0.92 + 0.05 * sin(t * 6.3 + phase) + 0.03 * sin(t * 13.1 + phase * 2.3))


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
	var key: String = "%s_t%d" % [type_name, tier]
	if _asset_exists(key):
		return key
	var base: String = "%s_t1" % type_name
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


func _find_player_cached(asset_name: String, spawned: Node3D) -> AnimationPlayer:
	if player_paths.has(asset_name):
		var cached_path: NodePath = player_paths[asset_name]
		if cached_path == ^"":
			return null
		return spawned.get_node_or_null(cached_path) as AnimationPlayer
	var player: AnimationPlayer = _find_player(spawned)
	if player == null:
		player_paths[asset_name] = ^""
		return null
	player_paths[asset_name] = spawned.get_path_to(player)
	return player


func _enemy_asset(u: Dictionary) -> String:
	var role: String = str(u.get("role", "raider"))
	if role in ["archer", "bombard"]:
		return "char_archer"
	if role in ["breaker", "ram"]:
		return "char_builder"
	if role == "scout":
		return "char_lumberjack"
	return "char_warrior"


func _enemy_scale(role: String) -> float:
	match role:
		"scout": return 0.88
		"breaker": return 1.10
		"ram": return 1.22
		"bombard": return 1.08
	return 1.0


func _tint_enemy(node: Node, tint: Color) -> void:
	# Faction colour + role silhouette are deliberately restrained: readable at
	# phone zoom without multiplying enemy materials every frame.
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var key := "%d/%d/%s" % [mesh.get_rid().get_id(), surface, tint.to_html(false)]
				if not tint_cache.has(key):
					var active: Material = (node as MeshInstance3D).get_active_material(surface)
					if active == null:
						continue
					var tinted: StandardMaterial3D = active.duplicate()
					tinted.albedo_color = tint
					tint_cache[key] = tinted
				(node as MeshInstance3D).set_surface_override_material(surface, tint_cache[key])
	for child in node.get_children():
		_tint_enemy(child, tint)


func _physical_to_canvas(px: float) -> float:
	if not touch_mode:
		return px
	var win := DisplayServer.window_get_size()
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	if win.x <= 0 or win.y <= 0:
		return px
	return px * maxf(canvas.x / float(win.x), canvas.y / float(win.y))


func _touch_slop() -> float:
	return _physical_to_canvas(18.0) if touch_mode else 12.0


func _selection_radius() -> float:
	return _physical_to_canvas(30.0) if touch_mode else 18.0


func _actor_should_render(at: Vector3) -> bool:
	var elevated := at + Vector3(0, 0.8, 0)
	if camera.is_position_behind(elevated):
		return false
	var point: Vector2 = camera.unproject_position(elevated)
	return get_viewport().get_visible_rect().grow(_physical_to_canvas(96.0)).has_point(point)


func _update_actors(delta: float) -> void:
	var present: Dictionary = {}
	for enemy_group in [false, true]:
		var group: Array = sim.enemies if enemy_group else sim.units
		for u: Dictionary in group:
			var id: int = int(u["id"])
			present[id] = true
			if not actors.has(id):
				var asset: String = _enemy_asset(u) if enemy_group else "char_" + str(u["type"])
				var spawned: Node3D = _model(asset)
				actor_layer.add_child(spawned)
				if enemy_group:
					_tint_enemy(spawned, sim.faction_color(str(u.get("faction", "thornband"))))
					spawned.scale = Vector3.ONE * _enemy_scale(str(u.get("role", "raider")))
				actors[id] = {"model": spawned, "player": _find_player_cached(asset, spawned), "clip": "", "previous": Vector3.ZERO}
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
			var onscreen: bool = _actor_should_render(destination)
			model.visible = onscreen
			model.position = destination
			if not onscreen:
				if player != null:
					player.speed_scale = 0.0
				continue
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
	ui.rule(mv)
	var command_head := Label.new()
	command_head.text = "COMMAND"
	command_head.add_theme_font_size_override("font_size", 12)
	command_head.add_theme_color_override("font_color", UI.BRASS_SOFT)
	mv.add_child(command_head)
	var command_grid := GridContainer.new()
	command_grid.columns = 3
	command_grid.add_theme_constant_override("h_separation", 8)
	command_grid.add_theme_constant_override("v_separation", 8)
	mv.add_child(command_grid)
	more_pave_button = _action_button("Pave Roads", _toggle_pave, command_grid)
	collect_button = _action_button("Collect", _collect_selected, command_grid)
	upgrade_button = _action_button("Upgrade", _upgrade_selected, command_grid)
	row_upgrade_button = _action_button("Upgrade Row", _upgrade_wall_row, command_grid)
	move_button = _action_button("Move", _move_selected, command_grid)
	repair_button = _action_button("Repair", _repair_selected, command_grid)
	workers_button = _action_button("People", _open_workers, command_grid)
	var campaign_head := Label.new()
	campaign_head.text = "CAMPAIGN"
	campaign_head.add_theme_font_size_override("font_size", 12)
	campaign_head.add_theme_color_override("font_color", UI.BRASS_SOFT)
	mv.add_child(campaign_head)
	var campaign_grid := GridContainer.new()
	campaign_grid.columns = 3
	campaign_grid.add_theme_constant_override("h_separation", 8)
	campaign_grid.add_theme_constant_override("v_separation", 8)
	mv.add_child(campaign_grid)
	more_chronicle_button = _action_button("Chronicle", _open_panel.bind("quests"), campaign_grid)
	more_tech_button = _action_button("Chart", _open_panel.bind("tech"), campaign_grid)
	more_frontier_button = _action_button("Frontier", _open_panel.bind("frontier"), campaign_grid)
	more_board_button = _action_button("Manor Board", _open_panel.bind("board"), campaign_grid)
	more_doctrine_button = _action_button("Doctrine", _open_panel.bind("doctrine"), campaign_grid)
	var system_head := Label.new()
	system_head.text = "VIEW & SYSTEM"
	system_head.add_theme_font_size_override("font_size", 12)
	system_head.add_theme_color_override("font_color", UI.BRASS_SOFT)
	mv.add_child(system_head)
	var system_grid := GridContainer.new()
	system_grid.columns = 3
	system_grid.add_theme_constant_override("h_separation", 8)
	system_grid.add_theme_constant_override("v_separation", 8)
	mv.add_child(system_grid)
	_action_button("⟲ Orbit", _orbit_left, system_grid)
	_action_button("⟳ Orbit", _orbit_right, system_grid)
	_action_button("Pause / Save", _open_pause, system_grid)
	_action_button("Close", _toggle_more, system_grid)
	more_sheet.hide()


func _toggle_more() -> void:
	if panel == "pause":
		sidebar.hide()
		panel = ""
	else:
		_close_panel()
	more_sheet.visible = not more_sheet.visible
	_paint_more()
	_layout_ui()


func _paint_more() -> void:
	if more_button == null or not is_instance_valid(more_button):
		return
	_paint_ring(more_button, UI.GOLD if more_sheet.visible else UI.SLATE, 56.0)


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
	left_dock.add_theme_stylebox_override("panel", ui.panel_box())
	left_content.add_theme_constant_override("separation", 6)
	left_dock.add_child(left_content)
	title_label = Label.new()
	title_label.text = "MIDNIGHT MANOR II"
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", UI.BRASS)
	left_content.add_child(title_label)
	ui.rule(left_content)
	var crest_row := HBoxContainer.new()
	crest_row.add_theme_constant_override("separation", 6)
	left_content.add_child(crest_row)
	crest_label = ui.crest("I", crest_row, "gold", 15)
	crest_label.tooltip_text = "Settlement crest and act"
	pop_label = Label.new()
	pop_label.add_theme_font_size_override("font_size", 13)
	pop_label.add_theme_color_override("font_color", UI.PAPER)
	crest_row.add_child(pop_label)
	hud.add_theme_font_size_override("font_size", 14)
	left_content.add_child(hud)
	level_bar = ui.bar(0, 1, left_content)
	quest_label.add_theme_color_override("font_color", GOLD)
	left_content.add_child(quest_label)
	path_button = ui.command_button("Chronicle", _open_panel.bind("quests"), left_content, 28.0)
	path_button.add_theme_font_size_override("font_size", 12)
	horn_label = raid_hud
	left_content.add_child(raid_hud)
	research_button = ui.command_button("Chart", _open_panel.bind("tech"), left_content, 28)
	research_button.add_theme_font_size_override("font_size", 12)
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
	resource_stack.add_theme_stylebox_override("panel", ui.panel_box())
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	resource_stack.add_child(stack)
	for resource: String in ["wood", "food", "gold", "lumber", "stone"]:
		var row := ui.resource_row(stack, "", RESOURCE_GLYPHS.get(resource, "*"))
		resource_rows[resource] = row["value"]
		resource_bars[resource] = row["bar"]
	root_control.add_child(bottom)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.add_theme_stylebox_override("panel", ui.notice_box())
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dock := VBoxContainer.new()
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_theme_constant_override("separation", 10)
	bottom.add_child(dock)
	var notice_wrap := HBoxContainer.new()
	notice_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_wrap.add_theme_constant_override("separation", 6)
	dock.add_child(notice_wrap)
	var notice_tick := ColorRect.new()
	notice_tick.color = UI.BRASS
	notice_tick.custom_minimum_size = Vector2(3, 0)
	notice_tick.size_flags_vertical = Control.SIZE_EXPAND_FILL
	notice_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_wrap.add_child(notice_tick)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_stylebox_override("panel", ui.notice_box())
	toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	toast_label.clip_text = true
	toast_label.max_lines_visible = 1
	toast_label.custom_minimum_size = Vector2(0, 24)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 12)
	toast_label.add_theme_color_override("font_color", UI.PAPER)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast.add_child(toast_label)
	notice_wrap.add_child(toast)
	root_control.add_child(banner_panel)
	banner_panel.add_theme_stylebox_override("panel", ui.panel_box(true))
	banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.add_child(banner_row)
	story_banner = ui.portrait_medallion("", banner_row, 38.0)
	story_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_label = Label.new()
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_label.add_theme_font_size_override("font_size", 13)
	banner_label.add_theme_color_override("font_color", UI.PARCHMENT_INK)
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_row.add_child(banner_label)
	banner_panel.modulate = Color(1, 1, 1, 0)
	banner_panel.hide()
	combat_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combat_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	combat_banner.add_theme_font_size_override("font_size", 28)
	combat_banner.add_theme_color_override("font_color", UI.GOLD)
	combat_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_banner.hide()
	root_control.add_child(combat_banner)
	nav = HBoxContainer.new()
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_theme_constant_override("separation", 12)
	dock.add_child(nav)
	nav_attack = ui.command_button("Horn", _test_raid, nav, 84.0)
	_paint_ring(nav_attack, UI.BLOOD, 84.0)
	var spacer_left := Control.new()
	spacer_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer_left)
	more_button = ui.command_button("···", _toggle_more, nav, 56.0)
	_paint_ring(more_button, UI.SLATE, 56.0)
	more_button.tooltip_text = "More actions"
	collect_all_button = ui.command_button("Collect", _collect_all, nav, 56.0)
	_paint_ring(collect_all_button, UI.SLATE, 56.0)
	collect_all_button.add_theme_font_size_override("font_size", 13)
	collect_all_button.tooltip_text = "Collect from every workplace"
	repair_all_button = ui.command_button("Repair", _repair_all, nav, 56.0)
	_paint_ring(repair_all_button, UI.SLATE, 56.0)
	repair_all_button.add_theme_font_size_override("font_size", 13)
	repair_all_button.tooltip_text = "Repair every damaged structure"
	var spacer_right := Control.new()
	spacer_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer_right)
	nav_shop = ui.command_button("Build", _shop_pressed, nav, 84.0)
	_paint_ring(nav_shop, UI.GOLD, 84.0)
	nav_shop.tooltip_text = "Raise new structures"
	_build_more_sheet(root_control)
	root_control.add_child(sidebar)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(side_scroll)
	side_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side_content)
	sidebar.hide()
	root_control.add_child(placement_box)
	placement_box.add_theme_stylebox_override("panel", ui.panel_box())
	var placement := VBoxContainer.new()
	placement_box.add_child(placement)
	placement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement.add_child(placement_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	placement.add_child(actions)
	confirm_button = ui.gold_button("Confirm Build", _confirm_placement, actions, 44.0)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cancel_button := ui.command_button("Cancel", _cancel_placement, actions, 44.0)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placement_box.hide()
	root_control.add_child(welcome)
	welcome.add_theme_stylebox_override("panel", ui.panel_box())
	var intro := VBoxContainer.new()
	intro.add_theme_constant_override("separation", 8)
	welcome.add_child(intro)
	ui.heading("THE MANOR STANDS", intro)
	ui.rule(intro)
	ui.body("Build your village beneath the moon.\nGather, grow, and hold the walls.", intro)
	welcome_help = ui.body("", intro)
	_refresh_input_copy()
	ui.body("Your current Chronicle objective stays visible while you play. Builds never spend resources until you confirm.", intro, 12)
	var enter_button := ui.gold_button("Enter Village", _enter_village, intro, 48.0)
	enter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var welcome_day := ui.command_button("Day / Night", _toggle_day, intro, 40.0)
	welcome_day.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _research_cost(node: Dictionary) -> String:
	return "%s + %d Insight" % [_cost_text(node["cost"]), int(node["insight"])]


func _toggle_research() -> void:
	research_list.visible = not research_list.visible
	_layout_ui()


func _input_verb() -> String:
	return "Tap" if touch_mode else "Click"


func _refresh_input_copy() -> void:
	if welcome_help == null or not is_instance_valid(welcome_help):
		return
	if touch_mode:
		welcome_help.text = "One finger: tap to select or drag to pan.\nTwo fingers: pinch to zoom, move to pan, twist to orbit.\nSelect a fighter, then tap open ground to give orders."
	else:
		welcome_help.text = "Left-drag to pan / wheel to zoom / right-drag or Q-E to orbit.\nClick buildings or villagers to select them.\nSelect a fighter, then click open ground to give orders."


func _research_surface_ready() -> bool:
	var quest: Dictionary = sim.quest_current()
	return sim.chronicle.act >= 3 or str(quest.get("id", "")) == "the-stone-line" or not sim.living.discoveries.is_empty() or not sim.living.active.is_empty()


func _objective_summary(compact: bool = false) -> String:
	var quest: Dictionary = sim.quest_current()
	if quest.is_empty():
		return "Chronicle complete"
	for objective: Dictionary in quest.get("objectives", []):
		var value: float = sim._objective_value(objective)
		var target_value: float = sim._objective_target(objective)
		if value < target_value:
			var step: String = str(objective.get("text", objective.get("kind", "Next objective")))
			if compact:
				return "%s  %d/%d" % [step, int(minf(value, target_value)), int(target_value)]
			return "%s\n%s  %d/%d" % [str(quest["name"]), step, int(minf(value, target_value)), int(target_value)]
	return str(quest["name"])


func _refresh_progressive_ui() -> void:
	var defense_ready: bool = sim.chronicle.act >= 3 or sim.raid_warning or sim.raid_active
	if nav_attack != null and is_instance_valid(nav_attack):
		nav_attack.visible = defense_ready
	if raid_hud != null and is_instance_valid(raid_hud):
		raid_hud.visible = defense_ready
	if more_pave_button != null and is_instance_valid(more_pave_button):
		more_pave_button.visible = "road_masonry" in sim.living.discoveries
	if more_tech_button != null and is_instance_valid(more_tech_button):
		more_tech_button.visible = _research_surface_ready()
	if more_frontier_button != null and is_instance_valid(more_frontier_button):
		more_frontier_button.visible = sim.chronicle.act >= 4
	if more_board_button != null and is_instance_valid(more_board_button):
		more_board_button.visible = sim.chronicle.act >= 5
	if more_doctrine_button != null and is_instance_valid(more_doctrine_button):
		more_doctrine_button.visible = sim.chronicle.act >= 5


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
	crest_label.text = str(sim.chronicle.act_data(sim.chronicle.act).get("numeral", "I"))
	crest_label.tooltip_text = "Act %s - %s" % [str(sim.chronicle.act_data(sim.chronicle.act).get("numeral", "I")), str(sim.chronicle.act_data(sim.chronicle.act).get("name", "Unwritten"))]
	pop_label.text = "%d/%d souls" % [sim.units.size(), sim.beds()]
	title_label.visible = not small
	for label in [hud, raid_hud, quest_label, research_label]:
		label.add_theme_font_size_override("font_size", 12 if small else 14)
	# Portrait phones: collapse the left dock to title + HUD + raid so the
	# world dominates; Path/Research stay one tap away in the bottom nav.
	var compact_dock: bool = small
	path_button.visible = not compact_dock
	# The next objective stays visible on phones even when the Chronicle button
	# collapses into More. New players should never have to guess what is next.
	quest_label.visible = true
	research_button.visible = not compact_dock and _research_surface_ready()
	research_label.visible = not compact_dock and _research_surface_ready()
	if compact_dock:
		research_list.hide()
	var bar_h: float = maxf(UI.BOTTOM_BAR_H, bottom.get_combined_minimum_size().y)
	# Five bottom buttons fit phones only with tighter spacing and smaller hero discs.
	if small != nav_compact:
		nav_compact = small
		nav.add_theme_constant_override("separation", 8.0 if small else 12.0)
		_paint_ring(nav_attack, UI.BLOOD, 76.0 if small else 84.0)
		_paint_ring(nav_shop, UI.GOLD, 76.0 if small else 84.0)
	bottom.offset_left = safe
	bottom.offset_right = -safe
	bottom.offset_top = -bar_h - safe
	bottom.offset_bottom = -safe
	# Corners are structural now (ATTACK left, SHOP right): no reorder needed.
	# The two HUD clusters split whatever is left BETWEEN the safe margins, so
	# the budget has to be measured from safe*2, not a hardcoded 44 (which left
	# a 4px overlap on portrait phones).
	var gutter: float = maxf(0.0, size.x - safe * 2.0)
	var dock_width: float = gutter * 0.52 if narrow else UI.RAIL_WIDTH + 198.0
	left_dock.size = Vector2(dock_width, 0)
	left_dock.position = Vector2(safe, safe)
	var stack_width: float = gutter * 0.48 if narrow else 226.0
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
	# The story banner sits above the command bar and below the HUD cluster, so
	# it never covers a control the player needs mid-raid.
	var banner_w: float = minf(size.x - safe * 2.0, 420.0)
	banner_panel.size = Vector2(banner_w, banner_panel.get_combined_minimum_size().y)
	banner_panel.position = Vector2((size.x - banner_w) * 0.5, maxf(8.0, bar_h + safe * 2.0 + 120.0))
	welcome.size = Vector2(minf(480, size.x - 36), 0)
	welcome.position = Vector2((size.x - welcome.size.x) / 2, maxf(110, size.y * 0.28))
	combat_banner.size = Vector2(minf(390.0, size.x - safe * 2.0), 58.0)
	combat_banner.position = Vector2((size.x - combat_banner.size.x) * 0.5, maxf(96.0, size.y * 0.18))
	_camera_update()


func _clear_sidebar() -> void:
	hire_buttons.clear()
	build_cards.clear()
	research_sheet_buttons.clear()
	for child in side_content.get_children():
		side_content.remove_child(child)
		child.queue_free()
	ui.command_button("Close", _close_panel, side_content, 36.0)


func _open_panel(which: String) -> void:
	if panel == "pause" and which != "pause": paused = false
	panel = which
	more_sheet.hide()
	_paint_more()
	sidebar.show()
	_clear_sidebar()
	match which:
		"build":
			_build_catalog()
		"people":
			roster_count = sim.units.size()
			_label("PEOPLE & WORKERS", side_content, true)
			ui.rule(side_content)
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
			_build_missions()
		"tech":
			_build_tech_tree()
		"frontier":
			_build_frontier()
		"board":
			_build_board()
		"doctrine":
			_build_doctrines()
		"building":
			_build_inspector()
			sidebar.hide()
		"research":
			_open_panel("tech")
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


# --- Mission panel -----------------------------------------------------------
# Portrait + parchment message + live objectives + optional challenges.

func _build_missions() -> void:
	var quest: Dictionary = sim.quest_current()
	var current_act: int = sim.chronicle.act
	ui.heading("THE CHRONICLE", side_content)
	ui.rule(side_content)
	var plate := ui.manor_panel(side_content, true)
	var plate_col := VBoxContainer.new()
	plate_col.add_theme_constant_override("separation", 2)
	plate.add_child(plate_col)
	ui.parchment_text("ACT %s - %s" % [str(sim.chronicle.act_data(current_act).get("numeral", "?")), str(sim.chronicle.act_data(current_act).get("name", "Unwritten"))], plate_col, 15)
	ui.parchment_text(str(sim.chronicle.act_data(current_act).get("summary", "")), plate_col, 13)
	if quest.is_empty():
		ui.parchment_text("Every mission in this act is written. The next page opens when the campaign turns.", plate_col)
		ui.command_button("Frontier", _open_panel.bind("frontier"), side_content, 40.0)
		return
	ui.mission_banner(str(quest.get("giver", "")), str(quest["text"]), side_content)
	var prize := PackedStringArray()
	if int(quest.get("xp", 0)) > 0:
		prize.append("%d XP" % int(quest.get("xp", 0)))
	if int(quest.get("insight", 0)) > 0:
		prize.append("%d Insight" % int(quest.get("insight", 0)))
	if int(quest.get("reputation", 0)) > 0:
		prize.append("%d Rep" % int(quest.get("reputation", 0)))
	var goods := _cost_text(quest.get("rewards", {}))
	if goods != "Free":
		prize.append(goods)
	if not prize.is_empty():
		ui.body("Reward: " + " · ".join(prize), side_content, 12)
	var record: Dictionary = sim.quest_progress.get(str(quest["id"]), {})
	for objective: Dictionary in quest["objectives"]:
		var value: float = sim._objective_value(objective)
		var target: float = sim._objective_target(objective)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		side_content.add_child(row)
		var mark: Label = ui.crest("OK" if value >= target else "-", row, "positive" if value >= target else "iron", 12)
		mark.custom_minimum_size.x = 26
		var text := Label.new()
		text.text = "%s — %d/%d" % [str(objective.get("text", objective["kind"])), int(minf(value, target)), int(target)]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 14)
		text.add_theme_color_override("font_color", UI.PAPER if value >= target else UI.EDGE)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
	var optional: Array = quest.get("optional", [])
	if not optional.is_empty():
		ui.heading("OPTIONAL CHALLENGES", side_content)
		for entry: Dictionary in optional:
			var won: bool = bool(record.get("optional", {}).get(str(entry["id"]), false))
			var orow := HBoxContainer.new()
			orow.add_theme_constant_override("separation", 6)
			side_content.add_child(orow)
			ui.crest("SEAL" if won else "OPEN", orow, "gold" if won else "iron", 11)
			var otext := Label.new()
			otext.text = "%s  (%s)" % [str(entry["text"]), _cost_text(entry.get("reward", {}))]
			otext.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			otext.add_theme_font_size_override("font_size", 12)
			otext.add_theme_color_override("font_color", UI.BRASS if won else UI.EDGE)
			otext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			orow.add_child(otext)
	# Compact act progress: the current act already has its summary above, so the
	# index only needs numerals, state color and mission counts.
	ui.heading("ACTS", side_content)
	var acts := GridContainer.new()
	acts.columns = 5
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	side_content.add_child(acts)
	for entry: Dictionary in sim.chronicle.acts():
		var number: int = int(str(entry["id"]).replace("act", ""))
		var total: int = 0
		var done_count: int = 0
		for quest_entry: Dictionary in sim.quests:
			if int(quest_entry["act"]) == number:
				total += 1
				if str(quest_entry["id"]) in sim.completed_quests:
					done_count += 1
		var tone := "gold" if number == sim.chronicle.act else ("positive" if number < sim.chronicle.act else "iron")
		var badge := ui.crest(str(entry["numeral"]), acts, tone, 13)
		badge.tooltip_text = "%s — %s\n%d/%d missions" % [str(entry["numeral"]), str(entry["name"]), done_count, total]


# --- Tech tree ---------------------------------------------------------------
# An illuminated chart: six branch tabs, prerequisite lines, cost, duration,
# unlock summary and the reason a node is still sealed.

func _build_tech_tree() -> void:
	var chronicle = sim.chronicle
	if tech_branch.is_empty() or not chronicle.branches().has(tech_branch):
		tech_branch = str(chronicle.branches()[0]) if not chronicle.branches().is_empty() else ""
	ui.heading("THE MANOR CHART", side_content)
	ui.rule(side_content)
	ui.body("Insight %d / %d / tier %d. Research pauses during an alarm." % [int(sim.living.insight), int(sim.living.config["research"]["insight_cap"]), chronicle.current_tier()], side_content)
	var tabs := GridContainer.new()
	tabs.columns = 3
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	side_content.add_child(tabs)
	for branch: Variant in chronicle.branches():
		var key := str(branch)
		var branch_ids: Array = chronicle.branch_nodes(key)
		var found: int = 0
		for node_id: Variant in branch_ids:
			if str(node_id) in sim.living.discoveries:
				found += 1
		var tab := ui.command_button(key.to_upper(), _select_tech_branch.bind(key), tabs, 40.0)
		tab.text = "%s %d/%d" % [key.to_upper(), found, branch_ids.size()]
		tab.tooltip_text = "%s branch — %d of %d technologies stamped" % [key, found, branch_ids.size()]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if key == tech_branch:
			ui.paint_command(tab, "gold")
	tech_node_buttons.clear()
	var chart := ui.manor_panel(side_content, true)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	chart.add_child(column)
	var ids: Array = chronicle.branch_nodes(tech_branch)
	for tier in range(1, chronicle.max_tier() + 1):
		var rows: Array[String] = []
		for id: Variant in ids:
			if chronicle.tier_of(str(id)) == tier:
				rows.append(str(id))
		if rows.is_empty():
			continue
		var heading := Label.new()
		var gate: Dictionary = chronicle.tier_data(tier)
		var tier_open: bool = tier <= chronicle.current_tier()
		var tier_done: bool = tier < chronicle.current_tier()
		heading.text = "TIER %d · %s · %s" % [tier, str(gate.get("name", "")).to_upper(), "OPEN" if tier_open else ("ACT %s" % str(gate.get("minAct", "?")))]
		heading.add_theme_font_size_override("font_size", 12)
		heading.add_theme_color_override("font_color", UI.BRASS_SOFT if tier_open and not tier_done else (UI.POSITIVE if tier_done else UI.EDGE))
		column.add_child(heading)
		for id in rows:
			_tech_node_row(id, column)


func _tech_node_row(id: String, chart: VBoxContainer) -> Control:
	var chronicle = sim.chronicle
	var node: Dictionary = chronicle.node(id)
	var row := ui.inset_row(chart)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	row.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	column.add_child(head)
	var state := "SEALED"
	var tone := "iron"
	if id in sim.living.discoveries:
		state = "STAMPED"
		tone = "gold"
	elif sim.living.active == id:
		state = "%.0fs" % sim.living.remaining
		tone = "ready"
	var reason: String = sim.living.research_reason(sim, id)
	if state == "SEALED" and reason.is_empty():
		state = "READY"
		tone = "ready"
	ui.crest(state, head, tone, 11)
	var title := Label.new()
	title.text = str(node.get("name", id))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", UI.PARCHMENT_INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 12)
	line.add_theme_color_override("font_color", UI.PARCHMENT_INK)
	var prereqs: Array = node.get("requires", [])
	var unlocks := PackedStringArray()
	for raw: Variant in node.get("unlocks", []):
		unlocks.append(str(raw).replace("command:", "").replace("doctrine:", "").replace("aura:", "").replace("recipe:", "").replace("variant:", "").replace("greatwork:", "").replace("-", " ").replace("_", " "))
	var unlock_text := ("Unlocks %s\n" % [", ".join(unlocks)]) if not unlocks.is_empty() else ""
	if not prereqs.is_empty():
		var names := PackedStringArray()
		for need: Variant in prereqs:
			names.append(str(chronicle.node(str(need)).get("name", need)))
		line.text = "%safter %s\n%s\n%s / %d Insight / %ds" % [unlock_text, " + ".join(names), str(node.get("behavior", "")), _cost_text(node.get("cost", {})), int(node.get("insight", 0)), int(node.get("seconds", 0))]
	else:
		line.text = "%s%s\n%s / %d Insight / %ds" % [unlock_text, str(node.get("behavior", "")), _cost_text(node.get("cost", {})), int(node.get("insight", 0)), int(node.get("seconds", 0))]
	column.add_child(line)
	if not reason.is_empty():
		var locked := Label.new()
		locked.text = reason
		locked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		locked.add_theme_font_size_override("font_size", 12)
		locked.add_theme_color_override("font_color", Color("7a3b32"))
		column.add_child(locked)
	elif id not in sim.living.discoveries:
		var action := ui.command_button("Begin %ds" % int(node.get("seconds", 0)), _begin_research.bind(id), column, 34.0)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func _select_tech_branch(branch: String) -> void:
	tech_branch = branch
	if panel == "tech":
		_open_panel("tech")


# --- Frontier / campaign table ----------------------------------------------

func _build_frontier() -> void:
	var chronicle = sim.chronicle
	ui.heading("THE FRONTIER", side_content)
	ui.rule(side_content)
	ui.body("Regions move UNSEEN > SCOUTED > CONTESTED > SECURED > DEVELOPED. Developed regions pay for the manor.", side_content)
	for region_id: String in chronicle.region_order():
		var data: Dictionary = chronicle.region_data(region_id)
		if data.is_empty():
			continue
		var row := ui.inset_row(side_content)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		row.add_child(column)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		column.add_child(head)
		ui.crest(chronicle.region_state(region_id).substr(0, 3).to_upper(), head, "gold" if chronicle.region_state(region_id) == "developed" else "iron", 11)
		var title := Label.new()
		title.text = str(data.get("name", region_id))
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", UI.BRASS)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var benefit := Label.new()
		benefit.text = str(data.get("benefit", ""))
		benefit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		benefit.add_theme_font_size_override("font_size", 12)
		benefit.add_theme_color_override("font_color", UI.PAPER)
		column.add_child(benefit)
		if chronicle.region_state(region_id) == "developed":
			var gained := Label.new()
			gained.text = str(data.get("developsTo", ""))
			gained.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gained.add_theme_font_size_override("font_size", 12)
			gained.add_theme_color_override("font_color", UI.POSITIVE)
			column.add_child(gained)
			continue
		var states: Array = chronicle.region_states()
		var next: String = str(states[mini(chronicle.region_index(region_id) + 1, states.size() - 1)])
		var action := ui.command_button("Advance to %s" % next.to_upper(), _advance_region.bind(region_id, next), column, 36.0)
		action.disabled = not chronicle.region_reason(region_id, next).is_empty()
		action.tooltip_text = chronicle.region_reason(region_id, next)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.heading("FACTIONS", side_content)
	for entry: Dictionary in sim.world_specs.get("enemyFactions", []):
		var known: bool = sim.wave >= int(entry.get("minWave", 1))
		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 6)
		side_content.add_child(frow)
		ui.crest(str(entry.get("id", "").substr(0, 2).to_upper()), frow, "danger" if known else "iron", 11)
		var flabel := Label.new()
		flabel.text = "%s / wave %d - %s" % [str(entry.get("name", "")), int(entry.get("minWave", 1)), str(entry.get("lore", ""))]
		flabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flabel.add_theme_font_size_override("font_size", 12)
		flabel.add_theme_color_override("font_color", UI.PAPER if known else UI.EDGE)
		flabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frow.add_child(flabel)


func _advance_region(region_id: String, target: String) -> void:
	var reason: String = sim.chronicle.set_region(region_id, target)
	sim.notice = reason if not reason.is_empty() else "%s is now %s." % [str(sim.chronicle.region_data(region_id).get("name", region_id)), target]
	if reason.is_empty():
		_open_panel("frontier")


# --- Manor Board -------------------------------------------------------------
# Repeatable side work. Never holds essential campaign unlocks.

func _build_board() -> void:
	var chronicle = sim.chronicle
	ui.heading("THE MANOR BOARD", side_content)
	ui.rule(side_content)
	ui.body("Standing contracts. Reputation %d." % chronicle.reputation, side_content)
	for offer: Dictionary in chronicle.board_offer():
		if offer.is_empty():
			continue
		var template: Dictionary = offer["template"]
		var id: String = str(offer["id"])
		var contract: Dictionary = chronicle.board_contract(id)
		var row := ui.inset_row(side_content)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		row.add_child(column)
		var head := HBoxContainer.new()
		column.add_child(head)
		ui.crest(str(offer["slot"]).substr(0, 3).to_upper(), head, "iron", 11)
		var title := Label.new()
		title.text = str(template["name"])
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", UI.BRASS)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		ui.body(str(template.get("text", "")), column, 12)
		var objective: Dictionary = template.get("objective", {})
		var progress := Label.new()
		var reward: Dictionary = chronicle.board_reward(id)
		if contract.is_empty():
			progress.text = "%s / reward %s + %d Insight" % [str(objective.get("kind", "")), _cost_text(reward.get("resources", {})), int(reward.get("insight", 0))]
		else:
			progress.text = "On the board / %d of %d" % [int(contract["progress"]), int(chronicle.board_target(id))]
		progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		progress.add_theme_font_size_override("font_size", 12)
		progress.add_theme_color_override("font_color", UI.PAPER)
		column.add_child(progress)
		var action: Button
		if contract.is_empty():
			action = ui.command_button("Accept", _accept_contract.bind(id), column, 36.0)
		elif float(contract["progress"]) >= chronicle.board_target(id):
			action = ui.gold_button("Claim", _claim_contract.bind(id), column, 36.0)
		else:
			action = ui.command_button("In hand", Callable(), column, 36.0)
			action.disabled = true
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _accept_contract(id: String) -> void:
	var reason: String = sim.chronicle.board_accept(id)
	sim.notice = reason if not reason.is_empty() else "Contract accepted."
	if reason.is_empty():
		_open_panel("board")


func _claim_contract(id: String) -> void:
	if not sim.chronicle.board_complete(id):
		sim.notice = "Not finished yet."
		return
	var reward: Dictionary = sim.chronicle.board_reward(id)
	sim._reward(reward.get("resources", {}))
	sim.living.insight = minf(float(sim.living.config["research"]["insight_cap"]), sim.living.insight + float(reward.get("insight", 0)))
	sim.chronicle.reputation += int(reward.get("reputation", 0))
	sim.notice = "Contract paid."
	_open_panel("board")


# --- Doctrines ---------------------------------------------------------------

func _build_doctrines() -> void:
	var chronicle = sim.chronicle
	ui.heading("DOCTRINE", side_content)
	ui.rule(side_content)
	var switching: bool = sim.raid_active or sim.raid_warning
	ui.body("%d of %d slots held. %s" % [chronicle.doctrines.size(), chronicle.doctrine_slots(), "Locked during an alarm." if switching else "Swappable in peace."], side_content)
	for entry: Dictionary in chronicle.doctrines_config():
		var id := str(entry["id"])
		var held: bool = chronicle.has_doctrine(id)
		var row := ui.inset_row(side_content)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		row.add_child(column)
		var head := HBoxContainer.new()
		column.add_child(head)
		ui.crest("HELD" if held else "OPEN", head, "gold" if held else "iron", 11)
		var title := Label.new()
		title.text = str(entry["name"])
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", UI.BRASS)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		ui.body(str(entry.get("text", "")), column, 12)
		var action: Button
		if switching:
			action = ui.command_button("Held" if held else "Locked during raid", Callable(), column, 34.0)
			action.disabled = true
		else:
			action = ui.gold_button("Release" if held else "Swear", _toggle_doctrine.bind(id), column, 34.0)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _toggle_doctrine(id: String) -> void:
	var reason: String = sim.chronicle.toggle_doctrine(id, sim.living.discoveries)
	sim.notice = reason if not reason.is_empty() else "Doctrine %s." % ("released" if not sim.chronicle.has_doctrine(id) else "sworn")
	if reason.is_empty():
		_open_panel("doctrine")


# Categorised build cards, each showing the real exported model as a cached thumbnail.
func _build_catalog() -> void:
	_label("RAISE THE VILLAGE", side_content, true)
	ui.rule(side_content)
	_label("Choose a structure, %s a tile, then confirm.\nThumbnails are the real exported models." % _input_verb().to_lower(), side_content)
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
			var cap_raw: Variant = spec.get("maxCount", 999)
			var cap: int = 999 if cap_raw is Array else int(cap_raw)
			if type_name == "stone_quarry" and "stoneworking" not in sim.living.discoveries:
				lock = "Research Stoneworking first."
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
	if panel == "tech":
		_open_panel("tech")
	_refresh_hud()


func _open_workers() -> void:
	_open_panel("people" if sim.get_building(selected_building).is_empty() else "workers")


func _build_inspector() -> void:
	var b: Dictionary = sim.get_building(selected_building)
	if b.is_empty():
		return
	# Compact Manor sheet: title crest, then recessed rows. No giant cards.
	var head := ui.inset_row(side_content)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	head.add_child(head_row)
	ui.crest("LV%d" % int(b["tier"]), head_row, "gold", 13)
	var title := Label.new()
	title.text = str(sim.building_specs[b["type"]]["name"])
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UI.BRASS)
	head_row.add_child(title)
	inspect_hp = ui.bar(0, 1, side_content)
	inspect_text = _label("", side_content)
	inspect_text.add_theme_color_override("font_color", UI.PAPER)
	var output := ui.inset_row(side_content)
	var ocol := VBoxContainer.new()
	ocol.add_theme_constant_override("separation", 1)
	output.add_child(ocol)
	ui.body("ON-SITE RESERVE", ocol, 12)
	var produced: Variant = sim.building_specs[b["type"]].get("production")
	ui.body(str(sim.building_specs[b["type"]].get("name", "")) + (" / no output" if produced == null else " / %s" % str(produced).capitalize()), ocol, 13)
	inspect_reserve = ui.bar(0, 1, ocol)
	var crew := ui.inset_row(side_content)
	var crew_row := HBoxContainer.new()
	crew_row.add_theme_constant_override("separation", 6)
	crew.add_child(crew_row)
	ui.crest("CREW", crew_row, "iron", 12)
	var workplace: String = str(sim.building_specs[b["type"]].get("workplace", ""))
	var posted: int = 0
	for u: Dictionary in sim.units:
		if workplace != "" and str(u["type"]) == workplace and int(u["workplace"]) == selected_building:
			posted += 1
			ui.portrait_medallion(str(u["type"]), crew_row, 26.0)
	ui.crest("%d/2" % posted, crew_row, "ready" if posted > 0 else "iron", 12)
	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	side_content.add_child(act_row)
	inspect_collect = ui.command_button("Collect", _collect_selected, act_row, 40.0)
	inspect_collect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect_upgrade = ui.command_button("Upgrade", _upgrade_selected, act_row, 40.0)
	inspect_upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if sim.upgrade_reason(selected_building).is_empty():
		ui.paint_command(inspect_upgrade, "gold")
	ui.body("Move and Repair live under More / ··· .", side_content)
	_label("Upgrade / %s." % _cost_text(sim.building_cost(b["type"], int(b["tier"]) + 1)), side_content)
	_label("Matching workers", side_content, true)
	for u: Dictionary in sim.units:
		if workplace != "" and str(u["type"]) == workplace:
			var text: String = "Release " if int(u["workplace"]) == selected_building else "Assign "
			_command_button_with(text, str(u["type"]).capitalize(), _assign.bind(int(u["id"]), -1 if int(u["workplace"]) == selected_building else selected_building), side_content, 34.0)
	_refresh_inspector()


func _command_button_with(prefix: String, name: String, action: Callable, parent: Node, minimum: float) -> Button:
	var made: Button = ui.command_button(prefix + name, action, parent, minimum)
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	made.add_theme_font_size_override("font_size", 13)
	return made


func _unit_inspector() -> void:
	var u: Dictionary = sim.get_unit(selected_unit)
	if u.is_empty():
		return
	_label("%s / Level %d" % [str(u["type"]).capitalize(), u["level"]], side_content, true)
	ui.rule(side_content)
	inspect_text = _label("", side_content)
	_label("%s open ground to move. Orders keep carried goods and assignments." % _input_verb(), side_content)
	_button("Hold position", _hold_selected, side_content)
	_button("Resume duties", _resume_selected, side_content)
	var training_cost: Dictionary = sim.troop_specs[u["type"]]["levelCost"].duplicate()
	for resource in training_cost:
		training_cost[resource] = float(training_cost[resource]) * int(u["level"])
	_button("Train / " + _cost_text(training_cost), _train_selected, side_content).disabled = int(u["level"]) >= 25
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
			if inspect_collect != null and is_instance_valid(inspect_collect):
				inspect_collect.disabled = float(shown.get("reserve", 0.0)) < 1 or float(shown.get("hp", 0.0)) <= 0 or float(shown.get("remaining", 0.0)) > 0
				inspect_collect.tooltip_text = "Bank the on-site reserve of %s" % str(sim.building_specs[shown["type"]]["name"])
			if inspect_upgrade != null and is_instance_valid(inspect_upgrade):
				var upgrade_reason: String = sim.upgrade_reason(selected_building)
				inspect_upgrade.disabled = not upgrade_reason.is_empty()
				inspect_upgrade.tooltip_text = upgrade_reason if not upgrade_reason.is_empty() else "Upgrade to tier %d" % (int(shown["tier"]) + 1)
			if inspect_hp != null and is_instance_valid(inspect_hp):
				inspect_hp.max_value = maxf(1.0, float(shown["max_hp"]))
				inspect_hp.value = clampf(float(shown["hp"]), 0.0, maxf(1.0, float(shown["max_hp"])))
			if inspect_reserve != null and is_instance_valid(inspect_reserve):
				inspect_reserve.max_value = maxf(1.0, float(sim.reserve_cap(shown)))
				inspect_reserve.value = clampf(float(shown["reserve"]), 0.0, maxf(1.0, float(sim.reserve_cap(shown))))
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
	upgrade_button.visible = not b.is_empty()
	upgrade_button.disabled = b.is_empty() or not sim.upgrade_reason(selected_building).is_empty()
	upgrade_button.tooltip_text = sim.upgrade_reason(selected_building) if not b.is_empty() else "Select a building"
	if row_upgrade_button != null and is_instance_valid(row_upgrade_button):
		var row_ids: Array[int] = sim.wall_row(selected_building)
		row_upgrade_button.visible = row_ids.size() > 1
		var row_reason: String = sim.upgrade_wall_row_reason(selected_building)
		row_upgrade_button.disabled = row_ids.size() <= 1 or not row_reason.is_empty()
		row_upgrade_button.text = "Upgrade Row ×%d" % row_ids.size() if row_ids.size() > 1 else "Upgrade Row"
		row_upgrade_button.tooltip_text = row_reason if not row_reason.is_empty() else "Upgrade this connected wall row together"
	repair_button.visible = not b.is_empty()
	repair_button.disabled = b.is_empty() or float(b["hp"]) >= float(b["max_hp"]) or float(b["remaining"]) > 0
	repair_button.tooltip_text = "Repair spends 15 HP per Wood" if not b.is_empty() else "Select a building"
	move_button.visible = not b.is_empty()
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
	ui.rule(side_content)
	_label("Simulation is paused. Your village saves locally; closed time does not generate resources.", side_content)
	var resume_button := ui.gold_button("Resume", _close_panel, side_content, 44.0)
	resume_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var save_button := ui.command_button("Save now", _save_now, side_content, 40.0)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var update_btn: Button = ui.command_button("Update Game", _update_game, side_content, 40.0)
	update_btn.tooltip_text = "Save the village and reload the latest build."
	update_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for setting: Array in [["Day / Night", _toggle_day], ["Sound On / Off", _toggle_sound]]:
		var setting_button := ui.command_button(str(setting[0]), setting[1], side_content, 40.0)
		setting_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_button = ui.command_button("Grid: On" if show_grid else "Grid: Off", _toggle_grid, side_content, 40.0)
	grid_button.tooltip_text = "Show or hide the 20x16 tile grid."
	grid_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power_button = ui.command_button("Battery saver: On" if battery_saver else "Battery saver: Off", _toggle_power, side_content, 40.0)
	power_button.tooltip_text = "Cap at 30 fps to save battery."
	power_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shadow_button = ui.command_button("Shadows: On" if shadows_on else "Shadows: Off", _toggle_shadows, side_content, 40.0)
	shadow_button.tooltip_text = "Toggle sun shadows (biggest phone speedup)."
	shadow_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var recenter_button := ui.command_button("Recenter camera", _recenter, side_content, 40.0)
	recenter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label("Chronicle, research, defenses, doctrines, regions and Great Works are live. Closed time does not advance the village.", side_content)


func _enter_village() -> void:
	started = true
	sim.paused = paused or not focused
	welcome.hide()
	if not save_blocked:
		sim.notice = "Next / " + _objective_summary(true)
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
	selected_building = -1
	selected_unit = -1
	preview_tile = Vector2i(-1, -1)
	placement_anchor = Vector2i(-1, -1)
	placement_row.clear()
	more_sheet.hide()
	_close_panel()
	placement_box.show()
	placement_label.text = "Place %s / %s the map" % [str(sim.building_specs[type_name]["name"]), _input_verb().to_lower()]
	confirm_button.disabled = true
	confirm_button.text = "Confirm Build"


# Paving mode: live reasons come from the living system, and nothing is spent until confirm.
func _toggle_pave() -> void:
	if paving:
		_cancel_placement()
		return
	paving = true
	build_type = ""
	moving_id = -1
	selected_building = -1
	selected_unit = -1
	preview_tile = Vector2i(-1, -1)
	placement_anchor = Vector2i(-1, -1)
	placement_row.clear()
	more_sheet.hide()
	_close_panel()
	placement_box.show()
	placement_label.text = "Pave stone road / %s a worn dirt trail" % _input_verb().to_lower()
	confirm_button.disabled = true
	confirm_button.text = "Confirm Pave"


func _placement_active() -> bool:
	return paving or not build_type.is_empty()


func _is_wall_row_mode() -> bool:
	return moving_id < 0 and build_type in ["wall", "stonewall"]


func _wall_row_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if a.x < 0 or b.x < 0:
		return out
	var dx: int = b.x - a.x
	var dy: int = b.y - a.y
	if absi(dx) >= absi(dy):
		var step_x: int = 1 if dx >= 0 else -1
		for x in range(a.x, b.x + step_x, step_x):
			out.append(Vector2i(x, a.y))
	else:
		var step_y: int = 1 if dy >= 0 else -1
		for y in range(a.y, b.y + step_y, step_y):
			out.append(Vector2i(a.x, y))
	return out


func _cost_times(cost: Dictionary, count: int) -> Dictionary:
	var total: Dictionary = {}
	for resource: Variant in cost:
		total[resource] = int(cost[resource]) * count
	return total


func _placement_tiles() -> Array[Vector2i]:
	if _is_wall_row_mode() and not placement_row.is_empty():
		return placement_row
	var out: Array[Vector2i] = []
	if preview_tile.x >= 0:
		out.append(preview_tile)
	return out


func _placement_reason() -> String:
	if preview_tile.x < 0:
		return "%s a tile on the map" % _input_verb()
	if paving:
		return sim.living.pave_reason(sim, preview_tile)
	if _is_wall_row_mode() and placement_row.size() > 1:
		return sim.build_row_reason(build_type, placement_row)
	return sim.build_reason(build_type, preview_tile.x, preview_tile.y, moving_id)


func _ghost_tile(tile: Vector2i, size: int, valid: bool, tint: Color) -> void:
	var centre := Vector2(tile) + Vector2.ONE * size * 0.5
	var ghost: MeshInstance3D = _box(Vector3(size * TILE - 0.1, 0.14, size * TILE - 0.1), world_position(centre, 0.12), tint if valid else Color("d26c62"), ghost_layer)
	var material: StandardMaterial3D = ghost.material_override
	material.albedo_color.a = 0.65
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _preview() -> void:
	if not _placement_active():
		return
	var reason: String = _placement_reason()
	confirm_button.disabled = not reason.is_empty()
	var tiles: Array[Vector2i] = _placement_tiles()
	var row_count: int = tiles.size()
	var headline: String = "Stone road" if paving else str(sim.building_specs[build_type]["name"])
	var detail: String = _cost_text({"stone": int(sim.living.config["stone"]["pave_cost"])})
	if not paving:
		if moving_id >= 0:
			detail = "Move here / no cost"
		elif _is_wall_row_mode() and row_count > 1:
			headline += " row ×%d" % row_count
			detail = _cost_text(_cost_times(sim.building_cost(build_type), row_count))
		else:
			detail = _cost_text(sim.building_cost(build_type))
	var coord: String = "tile %d, %d" % [preview_tile.x, preview_tile.y] if preview_tile.x >= 0 else "choose a tile"
	placement_label.text = "%s  /  %s\n%s" % [headline, coord, reason if not reason.is_empty() else detail]
	var signature: String = "%s/%s/%s/%s" % ["pave" if paving else build_type, str(tiles), preview_tile, reason]
	if signature == ghost_signature:
		return
	ghost_signature = signature
	for child in ghost_layer.get_children():
		ghost_layer.remove_child(child)
		child.queue_free()
	if preview_tile.x < 0:
		return
	if _is_wall_row_mode() and row_count > 1:
		for tile: Vector2i in tiles:
			_ghost_tile(tile, 1, reason.is_empty(), Color("93d78a"))
		return
	var size: int = 1 if paving else int(sim.building_specs[build_type]["size"])
	_ghost_tile(preview_tile, size, reason.is_empty(), Color("b9bcc0") if paving else Color("93d78a"))


func _confirm_placement() -> void:
	if paving:
		if sim.living.pave(sim, preview_tile):
			_update_roads()
			_refresh_hud()
			_preview()
		return
	var success: bool = false
	if _is_wall_row_mode() and placement_row.size() > 1:
		success = sim.build_row(build_type, placement_row)
	elif moving_id >= 0:
		success = sim.move_building(moving_id, preview_tile.x, preview_tile.y)
	else:
		success = sim.build(build_type, preview_tile.x, preview_tile.y)
	if success:
		if build_type in ["wall", "stonewall", "gate"] and moving_id < 0:
			preview_tile = Vector2i(-1, -1)
			placement_anchor = Vector2i(-1, -1)
			placement_row.clear()
			ghost_signature = ""
			confirm_button.disabled = true
		else:
			_cancel_placement()
		_rebuild_buildings()
	_preview()
	_refresh_hud()


func _cancel_placement() -> void:
	build_type = ""
	paving = false
	moving_id = -1
	preview_tile = Vector2i(-1, -1)
	placement_anchor = Vector2i(-1, -1)
	placement_row.clear()
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


func _collect_all() -> void:
	sim.collect_all()
	_refresh_hud()


func _repair_all() -> void:
	# Ruins (hp 0) count: after a lost raid they are exactly what must be rebuilt.
	for b: Dictionary in sim.buildings:
		if float(b.get("hp", 0.0)) < float(b.get("max_hp", 0.0)) and float(b.get("remaining", 0.0)) <= 0.0:
			if float(sim.resources.get("wood", 0.0)) <= 0.0:
				break
			sim.repair(int(b["id"]))
	_refresh_hud()


# The bottom Build button turns into Upgrade while a building is selected, so a
# tap on the village always offers the next thing to do with what was tapped.
func _shop_pressed() -> void:
	if sim.get_building(selected_building).is_empty():
		_open_panel("build")
	else:
		_upgrade_selected()


func _refresh_shop() -> void:
	if nav_shop == null or not is_instance_valid(nav_shop):
		return
	var b: Dictionary = sim.get_building(selected_building)
	if b.is_empty():
		nav_shop.text = "Build"
		nav_shop.disabled = false
		nav_shop.tooltip_text = "Raise new structures"
		return
	nav_shop.text = "Upgrade"
	var reason: String = sim.upgrade_reason(selected_building)
	nav_shop.disabled = not reason.is_empty()
	nav_shop.tooltip_text = reason if not reason.is_empty() else "Upgrade to tier %d" % (int(b["tier"]) + 1)


func _upgrade_selected() -> void:
	sim.upgrade(selected_building)
	_rebuild_buildings()
	_open_panel("building")
	_refresh_hud()


func _upgrade_wall_row() -> void:
	if sim.upgrade_wall_row(selected_building):
		_rebuild_buildings()
	_refresh_hud()


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


func _test_raid() -> void:
	sim.start_raid()
	_close_panel()
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
	_pump_banner()
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
			resource_rows[resource].text = "%s %d" % [RESOURCE_GLYPHS.get(resource, "*"), held]
		else:
			resource_rows[resource].text = "%s  %d / %d" % [resource.capitalize(), held, cap]
		var gauge: ProgressBar = resource_bars[resource]
		gauge.max_value = maxf(1.0, float(cap))
		gauge.value = float(held)
		resource_rows[resource].add_theme_color_override("font_color", UI.READY if held >= cap else UI.PAPER)
	# Collect stays compact but glows amber when there is something to bank.
	var bankable: bool = false
	for b: Dictionary in sim.buildings:
		if float(b.get("reserve", 0.0)) >= 1 and float(b.get("hp", 0.0)) > 0.0 and float(b.get("remaining", 0.0)) <= 0.0:
			bankable = true
			break
	if collect_button != null and is_instance_valid(collect_button):
		ui.paint_command(collect_button, "ready" if bankable else "normal")
	if collect_all_button != null and is_instance_valid(collect_all_button):
		collect_all_button.disabled = not bankable
		collect_all_button.tooltip_text = "Collect from every workplace" if bankable else "Nothing to collect yet"
		if bankable != collect_glow:
			collect_glow = bankable
			_paint_ring(collect_all_button, UI.READY if bankable else UI.SLATE, 56.0)
	var repair_wood: int = 0
	for b: Dictionary in sim.buildings:
		if float(b.get("hp", 0.0)) < float(b.get("max_hp", 0.0)) and float(b.get("remaining", 0.0)) <= 0.0:
			repair_wood += ceili((float(b["max_hp"]) - float(b["hp"])) / 15.0)
	var repairable: bool = repair_wood > 0 and float(sim.resources.get("wood", 0.0)) > 0.0
	if repair_all_button != null and is_instance_valid(repair_all_button):
		repair_all_button.disabled = not repairable
		repair_all_button.tooltip_text = "Repair every damaged structure (%d wood)" % repair_wood if repairable else "Nothing to repair"
		if repairable != repair_glow:
			repair_glow = repairable
			_paint_ring(repair_all_button, UI.READY if repairable else UI.SLATE, 56.0)
	hud.text = "Level %d    %d XP" % [sim.village_level(), sim.xp]
	var lower := 0
	var upper := 1
	for need: Variant in Sim.XP_LEVELS:
		if sim.xp >= int(need):
			lower = int(need)
		else:
			upper = int(need)
			break
	if upper <= lower:
		upper = lower + 1
	if level_bar != null and is_instance_valid(level_bar):
		level_bar.max_value = maxf(1.0, float(upper - lower))
		level_bar.value = clampf(float(sim.xp - lower), 0.0, maxf(1.0, float(upper - lower)))
	var quest: Dictionary = sim.quest_current()
	quest_label.text = _objective_summary()
	if sim.raid_active:
		raid_hud.text = "WAVE %d / %s / %d / %s" % [sim.wave, sim.raid_faction_name(), sim.enemies.size(), sim.raid_direction()]
		music.set_mood("danger")
	elif sim.raid_warning:
		raid_hud.text = "HORNS / %s / %.0fs" % [sim.raid_direction(), maxf(0.0, sim.next_raid_at - sim.elapsed)]
		music.set_mood("tension")
	else:
		raid_hud.text = "Quiet / next horns in %.0fs" % maxf(0, sim.next_raid_at - sim.elapsed - 25)
		music.set_mood("night" if night else "day")
	# One horn tick on the rising edge of an alarm; the music mood already
	# carries the sustained danger, so this never repeats while held.
	var alarm: bool = sim.raid_active or sim.raid_warning
	if alarm and not alarm_latched and started and sound:
		sfx.play()
	alarm_latched = alarm
	music.set_calm(sim.paused)
	if _is_small():
		hud.text = "Lv%d" % sim.village_level()
		quest_label.text = _objective_summary(true)
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
	toast_label.text = "◆ " + ("PAUSED / " if sim.paused else "") + sim.notice
	repair_all_button.visible = repairable or sim.chronicle.act >= 3
	_refresh_progressive_ui()
	_refresh_shop()
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


var BANNER_HOLD: float = 7.0
var BANNER_FADE: float = 0.45

# Story presentation: portrait + parchment plate, retracts on its own, never
# blocks a control, and the objective always stays reachable in the mission UI.
func _pump_banner() -> void:
	if banner_left > 0.0:
		banner_left -= 0.25
		var alpha: float = clampf(banner_left / BANNER_FADE, 0.0, 1.0) if banner_left < BANNER_FADE else 1.0
		banner_panel.modulate = Color(1, 1, 1, alpha)
		if banner_left <= 0.0:
			banner_panel.hide()
		return
	if sim.chronicle.banner_count() == 0 or not started:
		return
	var entry: Dictionary = sim.chronicle.take_banner()
	if entry.is_empty():
		return
	banner_label.text = str(entry.get("line", ""))
	banner_tooltip(str(entry.get("character", "")))
	banner_panel.show()
	banner_panel.modulate = Color(1, 1, 1, 0)
	banner_left = BANNER_HOLD


func banner_tooltip(character: String) -> void:
	var initials := Label.new()
	for child in story_banner.get_children():
		if child is Label:
			initials = child
	if not character.is_empty():
		initials.text = _initials_for(character)
		story_banner.tooltip_text = character


func _initials_for(character: String) -> String:
	var letters: String = ""
	for word in character.split(" "):
		if not word.is_empty():
			letters += word.substr(0, 1)
		if letters.length() >= 2:
			break
	return letters.to_upper() if not letters.is_empty() else "M"


func _setup_audio() -> void:
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
		elif event.get("kind") in ["hit", "defeat"]:
			var label := Label3D.new()
			label.text = "DOWN" if event.get("kind") == "defeat" else "-%d" % int(event.get("amount", 0))
			label.modulate = Color("ff8b78") if bool(event.get("friendly", false)) else Color("f6d58a")
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 34 if event.get("kind") == "defeat" else 28
			label.pixel_size = 0.012
			label.position = world_position(Vector2(float(event["x"]), float(event["y"])), 2.0)
			add_child(label)
			effect_nodes.append(label)
			var tween := create_tween()
			tween.tween_property(label, "position:y", label.position.y + 0.9, 0.55)
			tween.parallel().tween_property(label, "modulate:a", 0.0, 0.55)
			tween.tween_callback(label.queue_free)
		elif event.get("kind") == "raid_result":
			_show_combat_banner("THE MANOR STANDS" if bool(event.get("victory", false)) else "THE MANOR FELL", bool(event.get("victory", false)))
	sim.events.clear()


func _show_combat_banner(text: String, positive: bool) -> void:
	combat_banner.text = text
	combat_banner.add_theme_color_override("font_color", UI.READY if positive else UI.BLOOD)
	combat_banner.modulate = Color(1, 1, 1, 1)
	combat_banner.show()
	var tween := create_tween()
	tween.tween_interval(1.1)
	tween.tween_property(combat_banner, "modulate:a", 0.0, 0.55)
	tween.tween_callback(combat_banner.hide)


func _process(delta: float) -> void:
	sim.paused = not started or paused or (not focused and capture_path.is_empty())
	if not sim.paused:
		tick_accumulator += minf(delta, 0.25)
		while tick_accumulator >= 0.05:
			var spike_start: int = Time.get_ticks_usec() if spike_active else 0
			sim.tick(0.05)
			if spike_active:
				spike_worst_tick = maxf(spike_worst_tick, float(Time.get_ticks_usec() - spike_start) / 1000.0)
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
	lamp_accumulator += delta
	if night and lamp_accumulator >= (0.20 if battery_saver else 0.10):
		_flicker_lamps()
		lamp_accumulator = 0.0
	actor_accumulator += delta
	var actor_step: float = 0.08 if battery_saver else 0.05
	if actor_accumulator >= actor_step:
		var spike_actors_start: int = Time.get_ticks_usec() if spike_active else 0
		_update_actors(actor_accumulator)
		if spike_active:
			spike_worst_actors = maxf(spike_worst_actors, float(Time.get_ticks_usec() - spike_actors_start) / 1000.0)
		actor_accumulator = 0.0
	if spike_active:
		spike_next -= delta
		if spike_next <= 0.0:
			spike_next = 1.0
			spike_lines.append("t=%.0f fps=%d worst_tick_ms=%.2f worst_actors_ms=%.2f enemies=%d actors=%d raid=%s" % [
				Time.get_ticks_msec() / 1000.0, Engine.get_frames_per_second(),
				spike_worst_tick, spike_worst_actors, sim.enemies.size(), actors.size(),
				"active" if sim.raid_active else ("warn" if sim.raid_warning else "quiet")])
			spike_worst_tick = 0.0
			spike_worst_actors = 0.0
			if spike_lines.size() >= 5:
				var f: FileAccess
				if FileAccess.file_exists("res://raid_start.log"):
					f = FileAccess.open("res://raid_start.log", FileAccess.READ_WRITE)
					if f != null:
						f.seek_end()
				else:
					f = FileAccess.open("res://raid_start.log", FileAccess.WRITE)
				if f != null:
					f.store_string("\n".join(spike_lines) + "\n")
				spike_lines.clear()
	detail_accumulator += delta
	if detail_accumulator >= (0.10 if battery_saver else 0.05):
		details.update(self, detail_accumulator)
		detail_accumulator = 0.0
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


func _point_hits_ui(point: Vector2) -> bool:
	for control: Control in [welcome, sidebar, more_sheet, bottom, left_dock, resource_stack, placement_box]:
		if is_instance_valid(control) and control.visible and control.get_global_rect().has_point(point):
			return true
	return false


func _touch_pair() -> Array[Vector2]:
	var keys: Array = touches.keys()
	keys.sort()
	var pair: Array[Vector2] = []
	for key: Variant in keys:
		pair.append(touches[key])
		if pair.size() == 2:
			break
	return pair


func _map_click(screen: Vector2) -> void:
	var point: Vector2 = pick_ground(screen)
	var tile := Vector2i(floori(point.x), floori(point.y))
	if tile.x < 0 or tile.x >= 20 or tile.y < 0 or tile.y >= 16:
		return
	if _placement_active():
		preview_tile = tile
		if _is_wall_row_mode():
			placement_anchor = tile
			placement_row.assign([tile])
		_preview()
		return
	var chosen_id: int = -1
	var chosen_distance: float = INF
	var radius: float = _selection_radius()
	for u: Dictionary in sim.units:
		var p: Vector2 = camera.unproject_position(world_position(sim.position_of(u), 0.8))
		var distance: float = p.distance_to(screen)
		if distance < radius and distance < chosen_distance:
			chosen_distance = distance
			chosen_id = int(u["id"])
	if chosen_id >= 0:
		_select_unit(chosen_id)
		return
	for b: Dictionary in sim.buildings:
		var bounds := Rect2(Vector2(float(b["x"]), float(b["y"])), Vector2.ONE * int(b["size"]))
		if bounds.has_point(point):
			selected_building = int(b["id"])
			selected_unit = -1
			_update_marker()
			_open_panel("building")
			return
	if selected_unit >= 0:
		sim.order_unit(selected_unit, point.x, point.y)
		sim.notice = "Marching orders sent."
	else:
		selected_building = -1
		_update_marker()
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
		if not touch_mode:
			touch_mode = true
			_refresh_input_copy()
		if event.pressed:
			if _point_hits_ui(event.position):
				return
			touches[event.index] = event.position
			if touches.size() >= 2:
				_pinch_begin()
			elif touches.size() == 1:
				left_pressed = true
				left_dragged = false
				press_point = event.position
				last_pointer = event.position
		else:
			var was_world: bool = touches.has(event.index)
			if not was_world:
				return
			touches.erase(event.index)
			if touches.size() >= 2:
				_pinch_begin()
			else:
				pinch_has_mid = false
				pinch_dist = 0.0
				pinch_active = false
			if touches.is_empty():
				if left_pressed and not left_dragged and not _point_hits_ui(event.position):
					_map_click(event.position)
				left_pressed = false
				left_dragged = false
			elif touches.size() == 1:
				_pinch_rebase_single()
		return
	if event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		touches[event.index] = event.position
		if touches.size() >= 2 and pinch_active:
			_pinch_update()
		elif touches.size() == 1 and left_pressed:
			_drag_map(event.position)
		return


func _pinch_begin() -> void:
	var pts: Array[Vector2] = _touch_pair()
	if pts.size() < 2:
		return
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	pinch_dist = maxf(a.distance_to(b), 1.0)
	pinch_zoom = zoom
	pinch_mid = (a + b) * 0.5
	pinch_angle = atan2(b.y - a.y, b.x - a.x)
	pinch_yaw = yaw
	pinch_has_mid = false
	pinch_active = true
	left_pressed = false
	left_dragged = true


func _pinch_update() -> void:
	var pts: Array[Vector2] = _touch_pair()
	if pts.size() < 2 or pinch_zoom <= 0.0:
		return
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var cur_dist: float = maxf(a.distance_to(b), 1.0)
	zoom = clampf(pinch_zoom * pinch_dist / cur_dist, 12, 55)
	var cur_angle: float = atan2(b.y - a.y, b.x - a.x)
	yaw = pinch_yaw - wrapf(cur_angle - pinch_angle, -PI, PI)
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
		preview_tile = tile
		if _is_wall_row_mode():
			if placement_anchor.x < 0:
				var start_point: Vector2 = pick_ground(press_point)
				placement_anchor = Vector2i(floori(start_point.x), floori(start_point.y))
			placement_row = _wall_row_tiles(placement_anchor, tile)
			if pointer.distance_to(press_point) > _touch_slop():
				left_dragged = true
		_preview()
	elif pointer.distance_to(press_point) > _touch_slop() or left_dragged:
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
