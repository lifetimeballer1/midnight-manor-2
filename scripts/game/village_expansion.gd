extends RefCounted

# Expansion plots (WP-B): the unexplored land the player can see and aim at, and the
# unveiling when a plot is claimed. A locked plot is real slab land built by the same
# builder as a claimed one, tinted dark and cool, under a soft fog, with survey stakes,
# a dashed brass claim line, a beacon and a label. Claiming lifts the fog, warms the
# land, sweeps a line of light outward and clears the stakes. Everything here is
# presentation. It reads sim state through the expansion contract in
# village_sim.gd (EXPANSION_PLOTS, expansions, expansion_reason) and never
# changes it. Built and driven by village_game.gd, which owns the host node.

const GOLD := Color("d4b275")
const GOLD_HOT := Color("ffd98a")
const SILVER := Color("cfd8ea")
const NAVY := Color("152334")
const VIOLET_LOCK := Color("7d8fd6")
const BRASS_DIM := Color("8a7048")
const CLAIM_BRASS_READY := Color("806c45")   # the ready claim line at about half of GOLD_HOT: muted brass, not bright gold
const LOCKED_TEXT := Color("c9c4e6")
const FOG := Color(0.5, 0.58, 0.74)
const GRASS := Color("4d6038")
const SOIL := Color("4a3a2a")
const LIP := Color("6f8553")
const SKIRT := Color("243529")
# Locked land: about 45% brightness of the claimed colours, cool blue-grey.
const LOCKED_GRASS := Color(0.26, 0.31, 0.36)
const LOCKED_SOIL := Color(0.13, 0.13, 0.17)
const LOCKED_LIP := Color(0.3, 0.34, 0.42)
const LOCKED_SKIRT := Color(0.09, 0.11, 0.15)
const LOCKED_TREE := Color(0.24, 0.28, 0.37)    # silhouettes on locked land, dark under the fog
const POST_COLOUR := Color("3a3440")
# Two fog layers: each is faint on its own, and they drift in opposite directions.
const FOG_ALPHA: float = 0.22
const FOG_HEIGHT_LOW: float = 0.4
const FOG_HEIGHT_HIGH: float = 1.0
const FOG_EDGE_CLEAR: float = 0.2                 # fog strength at the village edge, as a share of the outer edge
const FOG_TILE: float = 7.0                       # world units per noise repeat
const FOG_TILE_HIGH: float = 11.0
const FOG_DRIFT_SECONDS: float = 30.0
const FOG_GRID: Vector2i = Vector2i(2, 10)        # fog mesh cells across and along the plot
const KIND_PINE: int = 0
const KIND_ROUND: int = 1
const KIND_SHRUB: int = 2
const KIND_ROCK: int = 3
const SILHOUETTE_MIN: int = 10
const SILHOUETTE_SPREAD: int = 5                  # 10..14 per plot
const SILHOUETTE_CLEAR: float = 4.0               # two tiles of open ground beside the village edge
const SILHOUETTE_GAP: float = 1.4
# Foliage and rock tones per kind (pine, round, shrub, rock), from the scenery palette in village_game.gd.
const SILHOUETTE_TONES: Array = [
	[Color("2b4a2e"), Color("264128"), Color("35532f")],
	[Color("2f4f2c"), Color("3d5e33"), Color("283f27")],
	[Color("3a5630"), Color("4a6236"), Color("33502c")],
	[Color("5e5d55"), Color("6f6a5e"), Color("54534d")],
]
const BANNER_WIDTH: float = 220.0                  # widest status line before it wraps
const BANNER_GAP: float = 8.0                     # space between a banner and its beacon point
const POST_SIZE: Vector3 = Vector3(0.26, 1.4, 0.26)
const LANTERN_RADIUS: float = 0.34
const LANTERN_AMBER := Color("ffb060")           # warm lantern glow, matching the street lamps' amber
const IRON_POST := Color("2b2d33")               # dark iron survey stake
const LANTERN_Y: float = 1.5
const POST_SPACING: float = 10.0          # one stake every five tiles along the village edge
const DASH_LENGTH: float = 1.2
const DASH_STEP: float = 2.4
const DASH_WIDTH: float = 0.34
const BEACON_SIZE: Vector2 = Vector2(5.0, 14.0)
const BEAM_LOW_LOCKED: float = 0.25
const BEAM_HIGH_LOCKED: float = 0.55
const BEAM_LOW_READY: float = 0.4
const BEAM_HIGH_READY: float = 0.85
const ENERGY_LOW_LOCKED: float = 0.14            # about 40% of the old 0.35
const ENERGY_HIGH_LOCKED: float = 0.3            # about 40% of the old 0.75
const ENERGY_LOW_READY: float = 0.64             # about 40% of the old 1.6
const ENERGY_HIGH_READY: float = 1.04            # about 40% of the old 2.6
const HALF_CYCLE_LOCKED: float = 2.1
const HALF_CYCLE_READY: float = 0.6
const LABEL_HEIGHT: float = 5.2                   # beacon point the region banner hangs above
const UNVEIL_SECONDS: float = 1.2
const GROUND_SIZE: Vector2 = Vector2(40.0, 32.0)   # base slab size, so the grass texture keeps its scale
const TEXTURE_SIZE: int = 64
const BASE_RECT: Rect2i = Rect2i(0, 0, 20, 16)      # the starting village, in tiles
# The side of each plot that touches the base village. The normal points from the plot into the base.
const BASE_SIDE: Dictionary = {"north": Vector2(0, 1), "east": Vector2(-1, 0), "south": Vector2(0, -1), "west": Vector2(1, 0)}

var host: Node3D = null
var origin: Vector3 = Vector3.ZERO
var tile: float = 2.0
var grass_texture: Texture2D = null
var plots_root: Node3D = null
var ground_root: Node3D = null
var base_world: Rect2 = Rect2()
var ghosts: Dictionary = {}        # id -> props of a locked plot
var slabs: Dictionary = {}         # id -> {"group", "grass", "trim", "locked", "busy"}
var ground_tint: Color = GRASS
var saver: bool = false
var fog_texture: Texture2D = null
var dot_texture: Texture2D = null
var beam_texture: Texture2D = null
var banner_layer: Control = null                  # 2D overlay under the HUD; banners are screen-space so they can be clamped
var ui_kit: VillageUI = null                      # panel style source, set by attach_banners


func setup(host_node: Node3D, origin_point: Vector3, tile_units: float, grass: Texture2D) -> void:
	host = host_node
	origin = origin_point
	tile = tile_units
	grass_texture = grass
	plots_root = Node3D.new()
	plots_root.name = "ExpansionPlots"
	host.add_child(plots_root)
	ground_root = Node3D.new()
	ground_root.name = "ExpansionGround"
	host.add_child(ground_root)
	base_world = world_rect(BASE_RECT)
	fog_texture = _fog_texture()
	dot_texture = _dot_texture()
	beam_texture = _beam_texture()


# World-space XZ rectangle (x, z) of a tile rectangle.
func world_rect(rect: Rect2i) -> Rect2:
	var x0: float = origin.x + float(rect.position.x) * tile
	var z0: float = origin.z + float(rect.position.y) * tile
	return Rect2(x0, z0, float(rect.size.x) * tile, float(rect.size.y) * tile)


# Locked plot under a tap point (tile units, as pick_ground returns). Claimed plots never match.
func plot_at(point: Vector2, plots: Dictionary, claimed: Array) -> String:
	for id: String in plots:
		if id in claimed:
			continue
		var rect: Rect2i = plots[id]["rect"]
		if Rect2(Vector2(rect.position), Vector2(rect.size)).has_point(point):
			return id
	return ""


# Brings the nodes in line with sim state. A claimed plot has its slab; a locked plot has the same slab
# dark and cool, plus its ghost props. animate_id names the plot claimed this frame, which unveils.
# saver_on (battery saver) silences the fog wisps; lite (battery saver or low power) trims the sparks.
func sync(sim, plots: Dictionary, animate_id: String, saver_on: bool, lite: bool, burst: Callable) -> void:
	if host == null:
		return
	saver = saver_on
	for id: String in plots:
		var plot: Dictionary = plots[id]
		var claimed: bool = id in sim.expansions
		var animate: bool = claimed and id == animate_id
		# A slab in the wrong state (for example after a load) is rebuilt; an unveil keeps its locked slab.
		if not animate and slabs.has(id) and bool(slabs[id]["locked"]) == claimed:
			_drop_slab(id)
		if claimed:
			if not slabs.has(id):
				_build_slab(id, plot, false)
			if animate:
				_unveil(id, plot, lite, burst)
			else:
				_retire_ghost(id)
		else:
			if not slabs.has(id):
				_build_slab(id, plot, true)
			_ensure_ghost(id, plot, lite)
	refresh(sim, plots)


# Updates ghost labels and the ready/locked look when the sim's reason text changes. Cheap: four plots,
# and nothing is rebuilt unless the text changed. Fog wisps follow the battery saver setting.
func refresh(sim, plots: Dictionary) -> void:
	for id: String in ghosts:
		var record: Dictionary = ghosts[id]
		var wisps: CPUParticles3D = record["wisps"]
		wisps.emitting = not saver
		(record["fog_b"] as MeshInstance3D).visible = not saver
		var reason: String = str(sim.expansion_reason(id))
		var ready: bool = reason.is_empty()
		var status: String = "TAP TO CLAIM" if ready else reason
		var label_text: String = "%s\n%s" % [str(plots[id]["label"]), status]
		if label_text == str(record["text"]):
			continue
		record["text"] = label_text
		_set_banner_text(record, str(plots[id]["label"]), status, ready)
		_apply_ghost_state(record, ready)
	# Battery saver keeps half of each plot's trees, shrubs and rocks (the rest are hidden, not freed).
	for id: String in slabs:
		for multi: MultiMesh in slabs[id]["multis"]:
			multi.visible_instance_count = (multi.instance_count + 1) / 2 if saver else -1


# Region banners are 2D panels in the HUD style. attach_banners hands over the overlay once the UI exists;
# banners built earlier (during the first sync) are re-parented and styled here.
func attach_banners(layer: Control, kit: VillageUI) -> void:
	banner_layer = layer
	ui_kit = kit
	for id: String in ghosts:
		var record: Dictionary = ghosts[id]
		var panel: PanelContainer = record["panel"]
		record["style"] = kit.panel_box()
		panel.add_theme_stylebox_override("panel", record["style"])
		_paint_banner_border(record)
		if panel.get_parent() == null:
			layer.add_child(panel)


# Hangs each banner above its beacon point, clamped inside clip (the screen minus the bottom bar). A banner
# whose beacon is off screen or behind the camera, or that cannot fit inside clip, is hidden instead of cut off.
# Four plots, so this is cheap enough to run on every camera move.
func place_banners(camera: Camera3D, clip: Rect2) -> void:
	if banner_layer == null:
		return
	for id: String in ghosts:
		var record: Dictionary = ghosts[id]
		var panel: PanelContainer = record["panel"]
		var anchor: Vector3 = record["anchor"]
		if camera.is_position_behind(anchor):
			panel.hide()
			continue
		var screen: Vector2 = camera.unproject_position(anchor)
		var box: Vector2 = record["box"]
		if not clip.has_point(screen) or box.x > clip.size.x or box.y > clip.size.y:
			panel.hide()
			continue
		var at := Vector2(screen.x - box.x * 0.5, screen.y - box.y - BANNER_GAP)
		at.x = clampf(at.x, clip.position.x, clip.end.x - box.x)
		at.y = clampf(at.y, clip.position.y, clip.end.y - box.y)
		panel.position = at
		panel.show()


func _make_banner(id: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = "Banner_" + id
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = null
	if ui_kit != null:
		style = ui_kit.panel_box()
		panel.add_theme_stylebox_override("panel", style)
	panel.hide()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)
	var status := Label.new()
	status.name = "Status"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(BANNER_WIDTH, 0)
	status.add_theme_font_size_override("font_size", 12)
	column.add_child(status)
	return {"panel": panel, "title": title, "status": status, "style": style}


# Gold edge when the plot is claimable, iron when it is still locked.
func _paint_banner_border(record: Dictionary) -> void:
	var style: StyleBoxFlat = record.get("style")
	if style == null:
		return
	style.border_color = GOLD if bool(record.get("ready", false)) else BRASS_DIM


# Warm the claimed grass with the rain tint, same as the base slab. A slab that is unveiling keeps its tween.
func tint_ground(color: Color) -> void:
	ground_tint = color
	for id: String in slabs:
		var slab: Dictionary = slabs[id]
		if not bool(slab["locked"]) and not bool(slab["busy"]):
			(slab["grass"] as StandardMaterial3D).albedo_color = color


func _ensure_ghost(id: String, plot: Dictionary, lite: bool) -> void:
	if ghosts.has(id):
		return
	var world: Rect2 = world_rect(plot["rect"])
	var centre := Vector2(world.get_center().x, world.get_center().y)
	var root := Node3D.new()
	root.name = "Ghost_" + id
	plots_root.add_child(root)
	var spots: Array[Vector2] = _stake_points(id, world)

	# Fog: two soft layers just above the land. Both are thick at the outer edge and thin at the village edge,
	# and they drift in opposite directions on one looping tween. Battery saver keeps only the low layer.
	var fog_mesh: ArrayMesh = _fog_mesh(world, id)
	var fog_low_mat: StandardMaterial3D = _fog_material(world, FOG_TILE)
	_mesh_node(root, fog_mesh, fog_low_mat, Vector3(centre.x, FOG_HEIGHT_LOW, centre.y), "FogLow")
	var fog_high_mat: StandardMaterial3D = _fog_material(world, FOG_TILE_HIGH)
	var fog_high: MeshInstance3D = _mesh_node(root, fog_mesh, fog_high_mat, Vector3(centre.x, FOG_HEIGHT_HIGH, centre.y), "FogHigh")
	fog_high.visible = not saver
	var drift: Tween = host.create_tween()
	drift.set_loops()
	drift.tween_property(fog_low_mat, "uv1_offset", Vector3(1.0, 0.0, 0.0), FOG_DRIFT_SECONDS).from(Vector3.ZERO)
	drift.parallel().tween_property(fog_high_mat, "uv1_offset", Vector3(-1.0, 0.0, 0.0), FOG_DRIFT_SECONDS).from(Vector3.ZERO)

	# Drifting fog wisps: a few soft dots that rise and fade. Silenced by battery saver.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.5, Color(1, 1, 1, 1.0))
	var wisp_mat := StandardMaterial3D.new()
	wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wisp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	wisp_mat.vertex_color_use_as_albedo = true
	wisp_mat.albedo_texture = dot_texture
	wisp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wisp_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var wisp_dot := QuadMesh.new()
	wisp_dot.size = Vector2(1.0, 1.0)
	wisp_dot.material = wisp_mat
	var wisps := CPUParticles3D.new()
	wisps.name = "Wisps"
	wisps.mesh = wisp_dot
	wisps.amount = 4 if lite else 8
	wisps.lifetime = 9.0
	wisps.preprocess = 9.0
	wisps.position = Vector3(centre.x, 0.8, centre.y)
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	wisps.emission_box_extents = Vector3(maxf(world.size.x * 0.5 - 3.0, 1.0), 0.6, maxf(world.size.y * 0.5 - 3.0, 1.0))
	wisps.direction = Vector3.UP
	wisps.spread = 25.0
	wisps.gravity = Vector3.ZERO
	wisps.initial_velocity_min = 0.1
	wisps.initial_velocity_max = 0.35
	wisps.scale_amount_min = 2.0
	wisps.scale_amount_max = 3.5
	wisps.color = Color(0.86, 0.92, 1.0, 0.4)
	wisps.color_ramp = ramp
	wisps.emitting = not saver
	root.add_child(wisps)

	# Survey stakes: thin dark posts with a lantern on top, at the corners and along the village edge.
	var post_xf: Array[Transform3D] = []
	var lantern_xf: Array[Transform3D] = []
	for spot: Vector2 in spots:
		post_xf.append(Transform3D(Basis(), Vector3(spot.x, POST_SIZE.y * 0.5, spot.y)))
		lantern_xf.append(Transform3D(Basis(), Vector3(spot.x, LANTERN_Y, spot.y)))
	var post_box := BoxMesh.new()
	post_box.size = POST_SIZE
	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = IRON_POST
	iron_mat.metallic = 0.5
	iron_mat.roughness = 0.55
	var posts := _multimesh(post_box, iron_mat, post_xf, "Posts", root)
	var lantern_mat := StandardMaterial3D.new()
	lantern_mat.albedo_color = LANTERN_AMBER
	lantern_mat.emission = LANTERN_AMBER
	lantern_mat.roughness = 0.5
	lantern_mat.emission_enabled = true
	var lantern_ball := SphereMesh.new()
	lantern_ball.radius = LANTERN_RADIUS
	lantern_ball.height = LANTERN_RADIUS * 2.0
	lantern_ball.radial_segments = 8
	lantern_ball.rings = 4
	var lanterns := _multimesh(lantern_ball, lantern_mat, lantern_xf, "Lanterns", root)

	# Dashed brass claim line along the edge shared with the village.
	var dash_mat := StandardMaterial3D.new()
	dash_mat.roughness = 0.6
	dash_mat.emission_enabled = true
	var dash_box := BoxMesh.new()
	dash_box.size = Vector3(DASH_LENGTH, 0.05, DASH_WIDTH)
	_multimesh(dash_box, dash_mat, _dash_transforms(id, world), "ClaimLine", root)

	# Beacon: a tall soft shaft of light at the plot centre, facing the camera around Y.
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam_mat.albedo_color = Color(VIOLET_LOCK.r, VIOLET_LOCK.g, VIOLET_LOCK.b, BEAM_LOW_LOCKED)
	beam_mat.albedo_texture = beam_texture
	var beam_quad := QuadMesh.new()
	beam_quad.size = BEACON_SIZE
	_mesh_node(root, beam_quad, beam_mat, Vector3(centre.x, BEACON_SIZE.y * 0.5, centre.y), "Beacon")

	# Region banner: a 2D panel that place_banners keeps above the beacon, clamped on screen and clear of the bottom bar.
	var banner: Dictionary = _make_banner(id)
	if banner_layer != null:
		banner_layer.add_child(banner["panel"])

	ghosts[id] = {"node": root, "fog_mat": fog_low_mat, "fog_b": fog_high, "fog_b_mat": fog_high_mat, "drift": drift,
		"beam_mat": beam_mat, "lantern_mat": lantern_mat, "dash_mat": dash_mat,
		"panel": banner["panel"], "title": banner["title"], "status": banner["status"], "style": banner["style"],
		"anchor": Vector3(centre.x, LABEL_HEIGHT, centre.y), "box": Vector2.ZERO, "posts": posts, "lanterns": lanterns, "wisps": wisps,
		"pulse": null, "text": "", "ready": false}


# Gold when ready, dim violet-blue when locked. Sets the colours and restarts the pulse.
func _apply_ghost_state(record: Dictionary, ready: bool) -> void:
	record["ready"] = ready
	var beam_mat: StandardMaterial3D = record["beam_mat"]
	var lantern_mat: StandardMaterial3D = record["lantern_mat"]
	var dash_mat: StandardMaterial3D = record["dash_mat"]
	var tint: Color = GOLD if ready else VIOLET_LOCK
	var beam: Color = beam_mat.albedo_color
	beam_mat.albedo_color = Color(tint.r, tint.g, tint.b, beam.a)
	lantern_mat.albedo_color = LANTERN_AMBER
	lantern_mat.emission = LANTERN_AMBER
	var dash: Color = CLAIM_BRASS_READY if ready else BRASS_DIM
	dash_mat.albedo_color = dash
	dash_mat.emission = dash
	dash_mat.emission_energy_multiplier = 0.5 if ready else 0.3
	_start_pulse(record, ready)


# One looping tween per plot: slow and dim when locked, quicker and bright gold when ready.
func _start_pulse(record: Dictionary, ready: bool) -> void:
	_kill_pulse(record)
	var half: float = HALF_CYCLE_READY if ready else HALF_CYCLE_LOCKED
	var tween: Tween = host.create_tween()
	tween.set_loops()
	tween.tween_method(_pulse.bind(record), 0.0, 1.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_pulse.bind(record), 1.0, 0.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	record["pulse"] = tween


# One frame of the pulse: t runs 0..1 and drives the beacon alpha and the lantern glow.
func _pulse(t: float, record: Dictionary) -> void:
	var ready: bool = bool(record["ready"])
	var beam_mat: StandardMaterial3D = record["beam_mat"]
	var lantern_mat: StandardMaterial3D = record["lantern_mat"]
	var beam: Color = beam_mat.albedo_color
	beam.a = lerpf(BEAM_LOW_READY if ready else BEAM_LOW_LOCKED, BEAM_HIGH_READY if ready else BEAM_HIGH_LOCKED, t)
	beam_mat.albedo_color = beam
	lantern_mat.emission_energy_multiplier = lerpf(ENERGY_LOW_READY if ready else ENERGY_LOW_LOCKED, ENERGY_HIGH_READY if ready else ENERGY_HIGH_LOCKED, t)


func _kill_pulse(record: Dictionary) -> void:
	var old: Variant = record.get("pulse")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	record["pulse"] = null


# Removes a locked plot's props at once (a claimed plot that was not just claimed).
func _retire_ghost(id: String) -> void:
	if not ghosts.has(id):
		return
	var record: Dictionary = ghosts[id]
	ghosts.erase(id)
	_kill_pulse(record)
	var node: Node3D = record["node"]
	if is_instance_valid(node):
		node.queue_free()
	var panel: Node = record["panel"]
	if is_instance_valid(panel):
		panel.queue_free()


# Writes the banner's name and status, colours the status, and records the panel's size for placement.
func _set_banner_text(record: Dictionary, title_text: String, status_text: String, ready: bool) -> void:
	var title: Label = record["title"]
	var status: Label = record["status"]
	title.text = title_text
	status.text = status_text
	status.add_theme_color_override("font_color", GOLD_HOT if ready else LOCKED_TEXT)
	record["ready"] = ready
	_paint_banner_border(record)
	var panel: PanelContainer = record["panel"]
	var box: Vector2 = panel.get_combined_minimum_size()
	record["box"] = box
	panel.size = box


# The claim: the fog lifts, the land warms to its normal colours, the stakes pop and sparkle upward, a line
# of light sweeps out from the village edge, then the stakes come away. About 1.2 seconds. lite gives fewer sparks.
func _unveil(id: String, plot: Dictionary, lite: bool, burst: Callable) -> void:
	var world: Rect2 = world_rect(plot["rect"])
	var normal: Vector2 = BASE_SIDE[id]
	var slab: Dictionary = slabs[id]
	slab["locked"] = false
	slab["busy"] = true
	var warm := host.create_tween()
	warm.set_parallel(true)
	warm.tween_property(slab["grass"], "albedo_color", ground_tint, UNVEIL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for pair: Array in slab["trim"]:
		warm.tween_property(pair[0], "albedo_color", pair[1], UNVEIL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# The silhouettes come out of the dark and stay on the claimed land.
	warm.tween_property(slab["tree_mat"], "albedo_color", Color.WHITE, UNVEIL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	warm.chain().tween_callback(_clear_busy.bind(slab))

	var spots: Array[Vector2] = _stake_points(id, world)
	var edge: Array = _shared_edge(id, world)
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var record: Dictionary = ghosts.get(id, {})
	ghosts.erase(id)
	if not record.is_empty():
		_kill_pulse(record)
		var node: Node3D = record["node"]
		(record["wisps"] as CPUParticles3D).emitting = false
		var drift: Variant = record.get("drift")
		if drift is Tween and (drift as Tween).is_valid():
			(drift as Tween).kill()
		var fog := host.create_tween()
		fog.set_parallel(true)
		fog.tween_property(record["fog_mat"], "albedo_color:a", 0.0, UNVEIL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		fog.tween_property(record["fog_b_mat"], "albedo_color:a", 0.0, UNVEIL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		fog.chain().tween_callback(node.queue_free)
		var quick := host.create_tween()
		quick.set_parallel(true)
		quick.tween_property(record["beam_mat"], "albedo_color:a", 0.0, 0.5)
		quick.tween_property(record["panel"], "modulate:a", 0.0, 0.45)
		quick.chain().tween_callback((record["panel"] as PanelContainer).queue_free)
		var pop := host.create_tween()
		pop.tween_property(record["posts"], "scale", Vector3(1.0, 1.35, 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.parallel().tween_property(record["lanterns"], "scale", Vector3.ONE * 1.5, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.parallel().tween_property(record["lantern_mat"], "emission_energy_multiplier", 1.2, 0.22)
		pop.chain().tween_property(record["posts"], "scale", Vector3(1.0, 0.01, 1.0), 0.5).set_ease(Tween.EASE_IN)
		pop.parallel().tween_property(record["lanterns"], "scale", Vector3.ZERO, 0.5).set_ease(Tween.EASE_IN)

	# Sparks rise from the stakes; bursts of light sit along the claim line.
	for index in spots.size():
		if lite and index % 2 == 1:
			continue
		var stake: Vector2 = spots[index]
		_spark(Vector3(stake.x, 1.6, stake.y), GOLD_HOT if index % 2 == 0 else SILVER)
	if burst.is_valid():
		var bursts: int = 2 if lite else 4
		for step in bursts:
			var on_edge: Vector2 = a.lerp(b, (float(step) + 0.5) / float(bursts))
			burst.call(Vector3(on_edge.x, 0.8, on_edge.y), GOLD, 6 if lite else 12, 1.0, true)
	_sweep(world, a, b, normal)


func _clear_busy(slab: Dictionary) -> void:
	slab["busy"] = false


# A line of light sweeps outward from the village edge across the new plot, then fades.
func _sweep(world: Rect2, a: Vector2, b: Vector2, normal: Vector2) -> void:
	var sweep := MeshInstance3D.new()
	sweep.name = "ClaimSweep"
	var quad := QuadMesh.new()
	quad.size = Vector2(a.distance_to(b), 0.7)
	sweep.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(GOLD_HOT.r, GOLD_HOT.g, GOLD_HOT.b, 0.85)
	sweep.material_override = mat
	sweep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid: Vector2 = (a + b) * 0.5
	sweep.position = Vector3(mid.x, 0.15, mid.y)
	# Lie flat on the ground; the strip runs along the shared edge.
	sweep.rotation = Vector3(-PI * 0.5, PI * 0.5 if normal.x != 0.0 else 0.0, 0.0)
	host.add_child(sweep)
	var away: Vector2 = -normal
	var depth: float = world.size.y if normal.y != 0.0 else world.size.x
	var tween := host.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sweep, "position", sweep.position + Vector3(away.x, 0.0, away.y) * depth, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(sweep.queue_free)


# The slab for one plot, built the same way claimed or locked: grass top, soil band, and a lip and skirt on
# the outer sides only (the base-facing side is joined to the village). locked gives the dark, cool colours.
func _build_slab(id: String, plot: Dictionary, locked: bool) -> void:
	var world: Rect2 = world_rect(plot["rect"])
	var half: Vector2 = world.size * 0.5
	var group := Node3D.new()
	group.name = "Slab_" + id
	group.position = Vector3(world.get_center().x, 0.0, world.get_center().y)
	ground_root.add_child(group)

	# Grass top and soil band, matching _ground() in village_game.gd.
	var grass := StandardMaterial3D.new()
	grass.albedo_color = LOCKED_GRASS if locked else ground_tint
	grass.albedo_texture = grass_texture
	grass.roughness = 0.9
	grass.uv1_scale = Vector3(world.size.x / GROUND_SIZE.x, world.size.y / GROUND_SIZE.y, 1.0)
	_add_box(group, Vector3(world.size.x, 0.32, world.size.y), Vector3(0, -0.16, 0), grass)
	var soil := _solid(LOCKED_SOIL if locked else SOIL)
	_add_box(group, Vector3(world.size.x, 0.5, world.size.y), Vector3(0, -0.55, 0), soil)

	var lip := _solid(LOCKED_LIP if locked else LIP)
	var skirt := _solid(LOCKED_SKIRT if locked else SKIRT)
	var skip: Vector2 = BASE_SIDE[id]
	for normal: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		if normal == skip:
			continue
		if normal.x != 0.0:
			_add_box(group, Vector3(0.5, 0.05, world.size.y), Vector3(normal.x * (half.x + 0.1), 0.025, 0), lip)
			_add_box(group, Vector3(0.4, 0.7, world.size.y + 0.8), Vector3(normal.x * (half.x + 0.2), -0.35, 0), skirt)
		else:
			_add_box(group, Vector3(world.size.x, 0.05, 0.5), Vector3(0, 0.025, normal.y * (half.y + 0.1)), lip)
			_add_box(group, Vector3(world.size.x + 0.8, 0.7, 0.4), Vector3(0, -0.35, normal.y * (half.y + 0.2)), skirt)

	var silhouettes: Dictionary = _silhouettes(id, world, group, locked)

	# trim holds each non-grass material with its normal colour, for the unveil tween.
	slabs[id] = {"group": group, "grass": grass, "trim": [[soil, SOIL], [lip, LIP], [skirt, SKIRT]], "locked": locked, "busy": false,
		"tree_mat": silhouettes["mat"], "multis": silhouettes["multis"]}


# Trees, shrubs and rocks standing on the plot: 10 to 14 per plot, placed from a seed taken from the plot id, so
# every run looks the same. They keep SILHOUETTE_CLEAR units clear of the village edge. Locked, they sit dark
# under the fog; on unveil the shared material warms to white and they stay on the claimed land.
# Returns {"mat": StandardMaterial3D, "multis": Array[MultiMesh]}. Shapes match the scenery in village_game.gd.
func _silhouettes(id: String, world: Rect2, group: Node3D, locked: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	var normal: Vector2 = BASE_SIDE[id]
	var edge_point: Vector2 = _shared_edge(id, world)[0]
	var centre: Vector2 = world.get_center()
	var target: int = SILHOUETTE_MIN + rng.randi() % SILHOUETTE_SPREAD
	var placed: Array[Vector2] = []
	var kinds: Array[int] = []
	var xforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var attempts: int = 0
	while placed.size() < target and attempts < 300:
		attempts += 1
		var spot := Vector2(rng.randf_range(world.position.x + 1.0, world.end.x - 1.0), rng.randf_range(world.position.y + 1.0, world.end.y - 1.0))
		# Negative depth means inside the plot, away from the village edge.
		if (spot - edge_point).dot(normal) > -SILHOUETTE_CLEAR:
			continue
		var clash: bool = false
		for other: Vector2 in placed:
			if other.distance_to(spot) < SILHOUETTE_GAP:
				clash = true
				break
		if clash:
			continue
		placed.append(spot)
		var roll: float = rng.randf()
		var kind: int = KIND_PINE if roll < 0.35 else (KIND_ROUND if roll < 0.6 else (KIND_SHRUB if roll < 0.8 else KIND_ROCK))
		var size: float = rng.randf_range(1.3, 1.8)
		var spot_basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		var local := Vector3(spot.x - centre.x, 0.0, spot.y - centre.y)
		kinds.append(kind)
		xforms.append(Transform3D(spot_basis, local))
		var palette: Array = SILHOUETTE_TONES[kind]
		var tone: Color = palette[rng.randi() % palette.size()]
		colours.append(tone.darkened(rng.randf_range(0.0, 0.12)))

	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = LOCKED_TREE if locked else Color.WHITE
	var multis: Array = []
	for kind: int in [KIND_PINE, KIND_ROUND, KIND_SHRUB, KIND_ROCK]:
		var kind_xforms: Array[Transform3D] = []
		var kind_colours: Array[Color] = []
		for index in kinds.size():
			if kinds[index] == kind:
				kind_xforms.append(xforms[index])
				kind_colours.append(colours[index])
		if kind_xforms.is_empty():
			continue
		var node: MultiMeshInstance3D = _multimesh(_silhouette_mesh(kind), mat, kind_xforms, "Silhouette%d" % kind, group, kind_colours, kind == KIND_PINE or kind == KIND_ROUND)
		multis.append(node.multimesh)
	return {"mat": mat, "multis": multis}


# Mesh for one silhouette kind. Each shape is lifted in the mesh itself, so every instance sits on the ground at y 0.
func _silhouette_mesh(kind: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == KIND_PINE:
		for tier in 3:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.75 - tier * 0.18
			cone.height = 1.4 - tier * 0.2
			cone.radial_segments = 6
			st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 0.75 + tier * 0.6, 0)))
		return st.commit()
	var ball := SphereMesh.new()
	var lift: float = 0.0
	match kind:
		KIND_ROUND:
			ball.radius = 0.8
			ball.height = 1.6
			ball.radial_segments = 7
			ball.rings = 4
			lift = 0.85
		KIND_SHRUB:
			ball.radius = 0.42
			ball.height = 0.5
			ball.radial_segments = 6
			ball.rings = 3
			lift = 0.22
		_:
			ball.radius = 0.28
			ball.height = 0.22
			ball.radial_segments = 5
			ball.rings = 3
			lift = 0.08
	st.append_from(ball, 0, Transform3D(Basis(), Vector3(0, lift, 0)))
	return st.commit()


func _drop_slab(id: String) -> void:
	if not slabs.has(id):
		return
	var group: Node3D = slabs[id]["group"]
	slabs.erase(id)
	if is_instance_valid(group):
		group.queue_free()


# A mesh node with no shadow, placed under parent.
func _mesh_node(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


# One MultiMesh with an instance per transform: a single draw call for every stake, lantern or dash.
func _multimesh(mesh: Mesh, material: Material, transforms: Array[Transform3D], node_name: String, parent: Node3D,
		colors: Array = [], casts_shadow: bool = false) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colors.is_empty()
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index in transforms.size():
		multi.set_instance_transform(index, transforms[index])
		if multi.use_colors:
			multi.set_instance_color(index, colors[index])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


# The part of a plot's border that touches the village, as [start, end] in world XZ.
func _shared_edge(id: String, world: Rect2) -> Array:
	var normal: Vector2 = BASE_SIDE[id]
	if normal.y != 0.0:
		var z: float = world.end.y if normal.y > 0.0 else world.position.y
		return [Vector2(maxf(world.position.x, base_world.position.x), z), Vector2(minf(world.end.x, base_world.end.x), z)]
	var x: float = world.end.x if normal.x > 0.0 else world.position.x
	return [Vector2(x, maxf(world.position.y, base_world.position.y)), Vector2(x, minf(world.end.y, base_world.end.y))]


# Stake positions in world XZ: the four plot corners, and an even row along the shared edge.
func _stake_points(id: String, world: Rect2) -> Array[Vector2]:
	var points: Array[Vector2] = [world.position, Vector2(world.end.x, world.position.y), world.end, Vector2(world.position.x, world.end.y)]
	var edge: Array = _shared_edge(id, world)
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var segments: int = maxi(1, roundi(a.distance_to(b) / POST_SPACING))
	for index in segments + 1:
		var spot: Vector2 = a.lerp(b, float(index) / float(segments))
		var known: bool = false
		for point: Vector2 in points:
			if point.distance_to(spot) < 0.1:
				known = true
		if not known:
			points.append(spot)
	return points


# Short brass dashes along the shared edge, so the player sees exactly where the new land starts.
func _dash_transforms(id: String, world: Rect2) -> Array[Transform3D]:
	var edge: Array = _shared_edge(id, world)
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var normal: Vector2 = BASE_SIDE[id]
	var turn: Basis = Basis() if normal.y != 0.0 else Basis(Vector3.UP, PI * 0.5)
	var length: float = a.distance_to(b)
	var transforms: Array[Transform3D] = []
	var count: int = floori(length / DASH_STEP)
	for index in count:
		var spot: Vector2 = a.lerp(b, (float(index) + 0.5) * DASH_STEP / length)
		transforms.append(Transform3D(turn, Vector3(spot.x, 0.06, spot.y)))
	return transforms


func _spark(at: Vector3, tint: Color) -> void:
	var spark := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.16
	spark.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	spark.material_override = material
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spark.position = at
	host.add_child(spark)
	var tween: Tween = host.create_tween()
	tween.tween_property(spark, "position:y", at.y + 1.6, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(spark, "scale", Vector3.ZERO, 1.1).set_ease(Tween.EASE_IN)
	tween.tween_callback(spark.queue_free)


func _add_box(parent: Node3D, size: Vector3, at: Vector3, material: StandardMaterial3D, shadow: bool = true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	if not shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


# Fog texture: a seamless mottle (alpha only), so the drifting planes repeat with no seam. The soft edge
# comes from the vertex fade in _fog_mesh, not the texture, so the texture can scroll freely.
func _fog_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.06
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.seed = 7
	var source := noise.get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE)
	var low := 1.0
	var high := 0.0
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var sample: float = source.get_pixel(x, y).r
			low = minf(low, sample)
			high = maxf(high, sample)
	var span: float = maxf(high - low, 0.0001)
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var value: float = (source.get_pixel(x, y).r - low) / span
			image.set_pixel(x, y, Color(1, 1, 1, lerpf(0.05, 1.0, value)))
	return ImageTexture.create_from_image(image)


# One fog layer for a plot: a flat grid, tinted by vertex alpha, thin at the village edge and thick at the outer
# edge. Its UVs run 0..1 across the plot; _fog_material tiles them with the noise.
func _fog_mesh(world: Rect2, id: String) -> ArrayMesh:
	var normal: Vector2 = BASE_SIDE[id]
	var half: Vector2 = world.size * 0.5
	# Half the plot's depth measured along the normal (from the plot centre toward the village is positive).
	var depth_half: float = half.x * absf(normal.x) + half.y * absf(normal.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in FOG_GRID.x:
		for j in FOG_GRID.y:
			var x0: float = lerpf(-half.x, half.x, float(i) / float(FOG_GRID.x))
			var x1: float = lerpf(-half.x, half.x, float(i + 1) / float(FOG_GRID.x))
			var z0: float = lerpf(-half.y, half.y, float(j) / float(FOG_GRID.y))
			var z1: float = lerpf(-half.y, half.y, float(j + 1) / float(FOG_GRID.y))
			var corners: Array[Vector2] = [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = corners[corner]
				var along: float = p.dot(normal)
				var outer: float = clampf((depth_half - along) / (2.0 * depth_half), 0.0, 1.0)
				st.set_color(Color(1, 1, 1, lerpf(FOG_EDGE_CLEAR, 1.0, outer)))
				st.set_uv(Vector2(p.x / world.size.x + 0.5, p.y / world.size.y + 0.5))
				st.add_vertex(Vector3(p.x, 0.0, p.y))
	return st.commit()


# Fog material for one layer: cool, unshaded, with the noise tiled over the plot. Its uv1_offset is what drifts.
func _fog_material(world: Rect2, tile: float) -> StandardMaterial3D:
	var fog_mat := StandardMaterial3D.new()
	fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fog_mat.vertex_color_use_as_albedo = true
	fog_mat.albedo_color = Color(FOG.r, FOG.g, FOG.b, FOG_ALPHA)
	fog_mat.albedo_texture = fog_texture
	fog_mat.uv1_scale = Vector3(world.size.x / tile, world.size.y / tile, 1.0)
	return fog_mat


# A soft round dot for the fog wisps.
func _dot_texture() -> Texture2D:
	var side: int = 32
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var centre := Vector2(side, side) * 0.5
	for x in side:
		for y in side:
			var d: float = (Vector2(float(x), float(y)) + Vector2(0.5, 0.5)).distance_to(centre) / (float(side) * 0.5)
			image.set_pixel(x, y, Color(1, 1, 1, 1.0 - smoothstep(0.2, 1.0, d)))
	return ImageTexture.create_from_image(image)


# Vertical beam: narrow at the top, bright at the base, for the beacon quad.
func _beam_texture() -> Texture2D:
	var width: int = 16
	var height: int = 64
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for x in width:
		var across: float = 1.0 - absf(float(x) + 0.5 - float(width) * 0.5) / (float(width) * 0.5)
		across = pow(clampf(across, 0.0, 1.0), 0.8)
		for y in height:
			var up: float = pow(float(y) / float(height - 1), 1.1)
			image.set_pixel(x, y, Color(1, 1, 1, across * up))
	return ImageTexture.create_from_image(image)
