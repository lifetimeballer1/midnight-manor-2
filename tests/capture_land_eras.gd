extends SceneTree

# Scratch QA capture for unlocked land: claims the North Reach, then the East Reach, and shoots the
# village from above by day and night so each era of land can be told apart. Not a regression test.
# Run WITHOUT --headless:
#   godot --path <project> --resolution 1280x800 --script res://tests/capture_land_eras.gd -- --no-save --capture-dir=<abs dir>

var directory: String = ""
var game


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if is_instance_valid(game):
		game.focused = true
	return false


func capture(file_name: String) -> void:
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	print("CAPTURED ", file_name, " result=", image.save_png(directory.path_join(file_name)))


func view(center: Vector2, zoom: float, tilt: float = 0.75, yaw: float = 0.66) -> void:
	game.target = game.world_position(center)
	game.zoom = zoom
	game.tilt = tilt
	game.yaw = yaw
	game._camera_update()


func set_day(day: bool) -> void:
	game.night = day
	game._toggle_day()
	await create_timer(0.6).timeout


func claim(id: String) -> void:
	for resource: String in ["wood", "stone", "gold"]:
		game.sim.resources[resource] = 99999
	game._claim_plot(id)
	await create_timer(4.0).timeout


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.focused = true
	game.paused = false
	await create_timer(1.5).timeout
	await set_day(true)
	view(Vector2(10.0, 8.0), 46.0, 0.9)
	await capture("0_no_reaches_day.png")
	await claim("north")
	await claim("east")
	game.sim.notice = ""
	view(Vector2(16.0, 2.0), 30.0)
	await capture("1_two_reaches_day.png")
	view(Vector2(20.0, 0.0), 14.0)
	await capture("2_seam_close_day.png")
	await claim("west")
	await claim("south")
	game.sim.notice = ""
	view(Vector2(10.0, 8.0), 46.0, 0.9)
	await capture("3_all_reaches_day.png")
	await set_day(false)
	await capture("4_all_reaches_night.png")
	quit()
