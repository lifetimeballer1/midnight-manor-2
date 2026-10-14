extends SceneTree

# Scratch QA capture for the town zoning layer. Not a regression test; never loads or writes a
# player's save (it runs with --no-save and builds its own fixture town).
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 1280x800 --script res://tests/capture_zoning.gd -- --no-save --day --capture-dir=<abs dir> [--phone]

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


func paint(tool: String, cells: Array) -> void:
	game.town_set_tool(tool)
	for c: Vector2i in cells:
		game.town_paint_cell(c)


func grow(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		game._town_advance(0.5)
		t += 0.5
	game._town_sync()


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
	var packed: PackedScene = load("res://scenes/game.tscn")
	game = packed.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.sim.resources["wood"] = 3000.0
	game.sim.resources["food"] = 400.0
	game.sim.resources["stone"] = 400.0
	await process_frame

	# Fixture: a main street along the south side, a lane out to the far edge, and zones beside them.
	var street: Array = []
	for x in range(-7, 7):
		street.append(Vector2i(x, 10))
	var lane: Array = [Vector2i(-1, 9), Vector2i(4, 11), Vector2i(4, 12)]
	game.town_open()
	paint("road", [Vector2i(-1, 9)] + street + [Vector2i(4, 11), Vector2i(4, 12)])
	var homes: Array = []
	for x in range(-6, 3):
		if x != -1:
			homes.append(Vector2i(x, 9))
	for x in range(-5, 2):
		homes.append(Vector2i(x, 11))
	paint("housing", homes)
	paint("farming", [Vector2i(-7, 9), Vector2i(-6, 11), Vector2i(-7, 11), Vector2i(-4, 12), Vector2i(-3, 12), Vector2i(-2, 12)])
	paint("industrial", [Vector2i(5, 11), Vector2i(5, 12), Vector2i(3, 12), Vector2i(5, 9), Vector2i(6, 9)])
	paint("civic", [Vector2i(3, 9), Vector2i(4, 9), Vector2i(2, 11), Vector2i(3, 11)])
	game.town.village_food = 400.0
	# The main street is paved; the lane stays dirt.
	paint("pave", street)

	# 1. The tools out over freshly painted zones, before anything grows, with a road run planned.
	frame(-2.0, 38.0, 46.0, 38.0, 46.0)
	await create_timer(0.8).timeout
	game.town_set_tool("road")
	game.town_plan(Vector2i(-1, 12), Vector2i(2, 12))
	game._town_place_cursor(Vector2i(2, 12))
	await capture("zoning_1_paint.png")
	game._town_clear_plan()
	game.town_set_tool("housing")

	# 2. The town grown (accelerated fixture time), tools out.
	grow(600.0)
	await create_timer(0.6).timeout
	print("TOWN ", game.town.stats())
	frame(-2.0, 40.0, 40.0, 38.0, 46.0)
	game.town.village_food = 0.0   # so some homes show what holds them back
	game._town_refresh_badges()
	await create_timer(0.5).timeout
	await capture("zoning_2_grown_tools.png")
	game.town.village_food = 400.0

	# 3. The same town as you'd see it playing, tools away.
	game.town_close()
	frame(-4.0, 42.0, 30.0, 30.0, 40.0)
	await create_timer(1.5).timeout
	game.town.income_clock = float(game.town.specs["incomeSeconds"]) - 0.1
	game._town_advance(0.5)
	await create_timer(0.7).timeout
	await capture("zoning_3_town.png")
	# A new title, as it lands.
	await create_timer(2.5).timeout
	game._town_event({"kind": "title", "tier": 3, "name": "Market Town", "reward": {}})
	await create_timer(0.5).timeout
	await capture("zoning_6_title.png")

	# 4. A lot's card.
	var card_cell := Vector2i(-3, 9)
	for c: Vector2i in game.town.lots:
		if game.town.lots[c]["zone"] == "housing" and int(game.town.lots[c]["level"]) == 2:
			card_cell = c
			break
	game.town_open()
	game.town_inspect(card_cell)
	frame(-2.0, 40.0, 40.0, 38.0, 46.0)
	await create_timer(0.6).timeout
	await capture("zoning_4_card.png")
	game._close_panel()

	# 5. Growth: a lot's scaffold rising, then the pop, as numbered frames. The fixture clears one
	# home beside the street and starts it again in view.
	game.town_close()
	var lot_cell := Vector2i(0, 9)
	game.town.erase(lot_cell)
	game.town.paint_zone(lot_cell, "housing")
	game.town.lots[lot_cell] = {"zone": "housing", "level": 1, "build": float(game.town.specs["buildSeconds"]),
		"progress": 0.0, "variant": 0, "age": 0.0}
	game.town.revision += 1
	game._town_sync()
	var centre: Vector2 = game.town.cell_centre(lot_cell)
	frame(centre.x + 1.0, centre.y + 2.0, 14.0, 30.0, 40.0)
	await create_timer(0.6).timeout
	for index in 26:
		game._town_advance(0.3)
		await create_timer(0.06).timeout
		await capture("zoning_anim_%02d.png" % index)

	# 6. An outpost's land: a second town out in the hills, on footings where the ground falls.
	var spot := Vector2(-70.0, 60.0)
	var found: bool = false
	for attempt in 60:
		var angle: float = float(attempt) * 0.41
		var probe := Vector2(cos(angle), sin(angle)) * (78.0 + float(attempt % 5) * 4.0)
		if game.realm.outpost_reason(probe).is_empty():
			spot = probe
			found = game.realm.found_outpost(probe)
			break
	print("OUTPOST ", found, " at ", spot)
	if found:
		game._realm_sync_outposts()
		var hub: Vector2i = game.town.cell_of(spot)
		var cells: Array = []
		for step in range(1, 6):
			cells.append(hub + Vector2i(step, 0))
		game.town_open()
		paint("road", cells)
		var side_cells: Array = []
		for step in range(1, 6):
			side_cells.append(hub + Vector2i(step, -1))
			side_cells.append(hub + Vector2i(step, 1))
		paint("housing", side_cells.slice(0, 6))
		paint("farming", side_cells.slice(6))
		game.town_close()
		grow(240.0)
		var middle: Vector2 = game.town.cell_centre(hub + Vector2i(3, 0))
		frame(middle.x, middle.y, 30.0, 30.0, 42.0)
		await create_timer(1.5).timeout
		await capture("zoning_5_outpost.png")

	# 7. Past the border: wild land for sale (gold grid) and its card.
	game._close_panel()
	game.town_open()
	game.town_set_tool("housing")
	game.sim.resources["gold"] = 400.0
	frame(2.0, 52.0, 44.0, 38.0, 46.0)
	game._town_build_grid()
	game._town_card_cell = Vector2i(0, 14)
	game._open_panel("town_land")
	await create_timer(0.8).timeout
	await capture("zoning_7_buy_land.png")
	# 8. A neighbour's land: not for sale, take it or win them over.
	var nearest: Dictionary = {}
	for site: Dictionary in game.realm.settlements:
		if not bool(site["vassal"]) and (nearest.is_empty() or (site["centre"] as Vector2).length() < (nearest["centre"] as Vector2).length()):
			nearest = site
	if not nearest.is_empty():
		var at: Vector2 = nearest["centre"]
		frame(at.x, at.y, 60.0, 38.0, 46.0)
		game._town_card_cell = game.town.cell_of(at + at.normalized() * -8.0)
		game._open_panel("town_land")
		await create_timer(1.2).timeout
		await capture("zoning_8_neighbour_land.png")
	game._close_panel()
	game.town_close()
	# 9. The reaches around the village: for sale, or cheaper once their region is won.
	frame(0.0, 10.0, 70.0, 38.0, 46.0)
	await create_timer(1.0).timeout
	await capture("zoning_9_reaches.png")

	print("CAPTURE DONE")
	game.queue_free()
	await process_frame
	quit(0)
