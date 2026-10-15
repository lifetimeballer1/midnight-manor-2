extends SceneTree

# Scratch QA capture for a whole-game visual review. Not a regression test.
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 1280x800 --script res://tests/capture_review.gd -- --no-save --size=1280x800 --capture-dir=<abs dir> [--only=name,name]

var directory: String = ""
var only: PackedStringArray = []
var game


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if is_instance_valid(game):
		game.focused = true
	return false


func capture(file_name: String) -> void:
	if not only.is_empty() and not only.has(file_name.get_basename()):
		return
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(directory.path_join(file_name))
	print("CAPTURED ", file_name, " result=", result, " size=", image.get_size())


func view(center: Vector2, zoom: float, tilt: float = 0.75, yaw: float = 0.66) -> void:
	game.target = game.world_position(center)
	game.zoom = zoom
	game.tilt = tilt
	game.yaw = yaw
	game._camera_update()


func set_day(day: bool) -> void:
	game.night = day   # _toggle_day flips it
	game._toggle_day()
	await create_timer(0.6).timeout


func _run() -> void:
	var size := Vector2i(1280, 800)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--size="):
			var parts: PackedStringArray = argument.trim_prefix("--size=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--only="):
			only = argument.trim_prefix("--only=").split(",")
	if not directory.is_absolute_path():
		printerr("ERROR missing absolute --capture-dir")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = size
	var packed: PackedScene = load("res://scenes/game.tscn")
	game = packed.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	await capture("00_title.png")
	game._enter_village()
	game.focused = true
	game.paused = false
	await create_timer(2.0).timeout

	var mid := Vector2(10.0, 8.0)
	await set_day(false)
	view(mid, 31.0)
	await capture("01_overview_night.png")
	view(mid, 13.0)
	await capture("02_close_night.png")
	view(mid, 12.0, 0.45)
	await capture("03_low_night.png")
	await set_day(true)
	view(mid, 31.0)
	await capture("04_overview_day.png")
	view(mid, 13.0)
	await capture("05_close_day.png")
	view(mid, 12.0, 0.45)
	await capture("06_low_day.png")
	# Villagers close up.
	if not game.sim.units.is_empty():
		var v: Dictionary = game.sim.units[0]
		var p := Vector2(float(v["x"]), float(v["y"]))
		view(p, 6.0, 0.6)
		await capture("07_villager_day.png")
	# Realm zoomed out.
	view(mid, 80.0)
	await capture("08_realm_day.png")
	await set_day(false)
	view(mid, 80.0)
	await capture("09_realm_night.png")
	view(mid + Vector2(-14.0, 0.0), 16.0, 0.6)
	await capture("10_edge_night.png")
	# Raid.
	view(mid, 15.0)
	if game.sim.start_raid():
		var started_at: int = Time.get_ticks_msec()
		while not game.sim.raid_active and Time.get_ticks_msec() - started_at < 10000:
			await process_frame
		await create_timer(8.0).timeout
		var focus: Vector2 = mid
		if not game.sim.enemies.is_empty():
			focus = Vector2(float(game.sim.enemies[0]["x"]), float(game.sim.enemies[0]["y"]))
		view(focus, 9.0, 0.65)
		await capture("11_raid_close.png")
		view(mid, 18.0)
		await capture("12_raid_wide.png")
	print("CAPTURE DONE")
	game.queue_free()
	await process_frame
	quit(0)
