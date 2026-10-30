extends SceneTree

# Scratch QA capture for the zoning update (zone tags, the village bar, the zone card, choosing what
# grows, rims with the tools away, the phone tool row). Not a regression test; never loads or writes
# a player's save (it runs with --no-save and builds its own fixture).
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 1280x800 --script res://tests/capture_zoning_update.gd -- --no-save --day --capture-dir=<abs dir> [--phone]

var directory: String = ""
var phone: bool = false
var game


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if is_instance_valid(game):
		game.focused = true
		game.paused = false
	return false


func capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(directory.path_join(file_name))
	print("CAPTURED ", file_name, " result=", result, " size=", image.get_size())


func frame(x: float, z: float, zoom: float, yaw_deg: float = -1.0, tilt_deg: float = -1.0) -> void:
	game.target = Vector3(x, 0.0, z)
	game.zoom = zoom
	if yaw_deg >= 0.0:
		game.yaw = deg_to_rad(yaw_deg)
	if tilt_deg >= 0.0:
		game.tilt = deg_to_rad(tilt_deg)
	game._camera_update()
	game.realm_stream(true)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
		if argument == "--phone":
			phone = true
	if not directory.is_absolute_path():
		printerr("ERROR missing absolute --capture-dir")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(390, 844) if phone else Vector2i(1280, 800)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	await process_frame
	var growth = game.growth
	var sim = game.sim
	var town = game.town
	sim.next_raid_at = 1.0e9

	# Homes west, farms north-middle, industry east, civic south: the same split as a player might.
	var taken: Dictionary = game._village_taken()
	var open: Array[Vector2i] = []
	for cy in range(-4, 4):
		for cx in range(-5, 5):
			var c := Vector2i(cx, cy)
			if not taken.has(c) and growth.cell_reason(sim, c).is_empty():
				open.append(c)
	game.town_open()
	var civic_cell := Vector2i(-9999, -9999)
	for c: Vector2i in open:
		var tool: String = "housing"
		if c.x >= 2:
			tool = "industrial"
		elif c.y >= 2:
			tool = "civic"
			civic_cell = c
		elif c.x >= -2:
			tool = "farming"
		game.town_set_tool(tool)
		game._town_stroke_denied = false
		game.town_paint_cell(c)
	for i in 60:
		for b: Dictionary in sim.buildings:
			b["remaining"] = 0.0
		if growth.grow_one(sim, town).is_empty():
			break
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
	sim.revision += 1
	game.town_set_tool("civic")
	frame(0.0, 0.0, 34.0 if not phone else 44.0, 38.0, 50.0)
	await create_timer(1.6).timeout
	await capture("update_1_tags_and_bar.png")

	# The zone card: tap a civic patch.
	game._town_card_cell = civic_cell
	game._open_panel("town_vcell")
	await create_timer(1.0).timeout
	await capture("update_2_zone_card.png")
	game._close_panel()

	# Choosing what grows on Industry.
	game.town_set_tool("industrial")
	game._town_tool_pressed("industrial")
	await create_timer(1.0).timeout
	await capture("update_3_what_grows.png")
	game._town_choose_pick("industrial", "mine")
	await create_timer(1.0).timeout
	await capture("update_4_picked_mine.png")
	if phone:
		game._town_toggle_more()
		await create_timer(0.6).timeout
		await capture("update_5_more_tools.png")
		game._town_toggle_more()

	# Tools away: zones waiting to grow show a thin rim only.
	game.town_close()
	await create_timer(1.2).timeout
	await capture("update_6_tools_away.png")
	quit(0)
