extends SceneTree

# Scratch QA capture: the starting village, then the same village with every building raised to
# its top tier, by day and night. Not a regression test. Run WITHOUT --headless:
#   godot --path . --resolution 1280x800 --script res://tests/capture_progression.gd -- --capture-dir=<abs>

var directory := ""
var game


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if is_instance_valid(game):
		game.focused = true
	return false


func capture(file_name: String) -> void:
	for i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(file_name))
	print("CAPTURED ", file_name)


func view(center: Vector2, zoom: float, tilt: float = 0.75) -> void:
	game.target = game.world_position(center)
	game.zoom = zoom
	game.tilt = tilt
	game.yaw = 0.66
	game._camera_update()


func set_day(day: bool) -> void:
	game.night = day
	game._toggle_day()
	await create_timer(0.6).timeout


func shots(prefix: String) -> void:
	var mid := Vector2(10.0, 8.0)
	await set_day(true)
	view(mid, 15.0)
	await capture(prefix + "_day.png")
	view(mid, 26.0)
	await capture(prefix + "_wide_day.png")
	await set_day(false)
	view(mid, 15.0)
	await capture(prefix + "_night.png")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 800)
	game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.focused = true
	game.paused = true
	await create_timer(2.0).timeout
	await shots("1_start")
	for b: Dictionary in game.sim.buildings:
		var spec: Dictionary = game.sim.building_specs.get(str(b["type"]), {})
		b["tier"] = (spec.get("tiers", [1]) as Array).size()
	game.sim.revision += 1
	await create_timer(1.0).timeout
	await shots("2_top_tier")
	print("CAPTURE DONE")
	quit(0)
