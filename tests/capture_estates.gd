extends SceneTree

# Scratch QA capture for farm estates (one big farm per farm zone). Not a regression test; never loads or writes a
# player's save (it runs with --no-save and builds its own fixture).
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 1280x800 --script res://tests/capture_estates.gd -- --no-save --day --capture-dir=<abs dir> [--phone]

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
	var taken: Dictionary = game._village_taken()
	game.town_open()
	# A big farm patch on the east side, a small one in the west, homes between.
	for cy in range(-4, 4):
		for cx in range(-5, 5):
			var c := Vector2i(cx, cy)
			if taken.has(c) or not growth.cell_reason(sim, c).is_empty():
				continue
			var tool: String = ""
			if cx >= 1:
				tool = "farming"
			elif cx <= -4 and cy >= 1:
				tool = "farming"
			elif cx <= -3:
				tool = "housing"
			if tool.is_empty():
				continue
			game.town_set_tool(tool)
			game.town_paint_cell(c)
	for i in 40:
		for b: Dictionary in sim.buildings:
			b["remaining"] = 0.0
			sim.materials.close_site(b)
		if growth.grow_one(sim, town).is_empty():
			break
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
		sim.materials.close_site(b)
	sim.revision += 1
	growth.refresh_estates(sim, town)
	for id: int in sim.estates:
		print("ESTATE ", id, " ", sim.get_building(id)["type"], " ", sim.estates[id]["name"], " tiles=", sim.estates[id]["tiles"])
	game.town_close()
	sim.elapsed = 105.0
	frame(4.0, 0.0, 34.0 if not phone else 40.0, 38.0, 50.0)
	await create_timer(1.5).timeout
	await capture("estates_1_wide.png")
	frame(8.0, 0.0, 16.0 if not phone else 22.0, 30.0, 48.0)
	await create_timer(1.2).timeout
	await capture("estates_2_ripe.png")
	sim.elapsed = 75.0
	await create_timer(1.5).timeout
	await capture("estates_3_sprouting.png")
	sim.elapsed = 135.0
	await create_timer(1.5).timeout
	await capture("estates_3b_harvested.png")
	var ids: Array = sim.estates.keys()
	ids.sort()
	if ids.size() >= 2:
		for crop: String in ["grove", "pasture", "pond"]:
			var small: int = int(ids[1]) if int(sim.estates[ids[1]]["tiles"]) < int(sim.estates[ids[0]]["tiles"]) else int(ids[0])
			var b: Dictionary = sim.get_building(small)
			b["type"] = crop
			sim.revision += 1
			growth.refresh_estates(sim, town)
			frame(-12.0, 6.0, 14.0 if not phone else 20.0, 30.0, 48.0)
			sim.elapsed = 95.0
			await create_timer(1.5).timeout
			await capture("estates_crop_%s.png" % crop)
	for id: int in sim.estates:
		game.selected_building = id
		game._open_panel("building")
		break
	await create_timer(1.0).timeout
	await capture("estates_4_card.png")
	quit(0)
