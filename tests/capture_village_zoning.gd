extends SceneTree

# Scratch QA capture for zoning inside the village. Not a regression test; never loads or writes a
# player's save (it runs with --no-save and builds its own fixture).
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 1280x800 --script res://tests/capture_village_zoning.gd -- --no-save --day --capture-dir=<abs dir> [--phone]

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

	# Open village ground, split into homes (west), farms (middle) and industry (east).
	var taken: Dictionary = game._village_taken()
	var open: Array[Vector2i] = []
	for cy in range(-4, 4):
		for cx in range(-5, 5):
			var c := Vector2i(cx, cy)
			if not taken.has(c) and growth.cell_reason(sim, c).is_empty():
				open.append(c)
	print("OPEN ", open.size())
	game.town_open()
	for c: Vector2i in open:
		var tool: String = "housing" if c.x <= -3 else ("farming" if c.x <= 1 else "industrial")
		game.town_set_tool(tool)
		game.town_paint_cell(c)
	game.town_set_tool("farming")

	# 1. Zones painted, tools out, before anything rises.
	frame(0.0, 0.0, 34.0 if not phone else 40.0, 38.0, 50.0)
	await create_timer(1.0).timeout
	await capture("village_1_zoned.png")

	# 2. Two buildings rising on their zones.
	growth.grow_one(sim, town)
	growth.grow_one(sim, town)
	await create_timer(1.2).timeout
	await capture("village_2_rising.png")

	# 3. Grown: everything that fits, finished, tools out.
	for i in 40:
		for b: Dictionary in sim.buildings:
			b["remaining"] = 0.0
		if growth.grow_one(sim, town).is_empty():
			break
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
	sim.revision += 1
	print("BUILDINGS ", sim.buildings.size())
	await create_timer(1.2).timeout
	await capture("village_3_grown_tools.png")

	# 4. Tools away.
	game.town_close()
	await create_timer(1.2).timeout
	await capture("village_4_grown.png")

	# 5. The Build menu now: defences, troops and Great Works.
	game._open_panel("build")
	await create_timer(1.0).timeout
	await capture("village_5_build_menu.png")
	game._close_panel()
	quit(0)
