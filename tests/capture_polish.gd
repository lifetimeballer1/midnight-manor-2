extends SceneTree

# Scratch QA capture for new combat/damage visual effects. Not a regression test.
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 390x844 --script res://tests/capture_polish.gd -- --no-save --capture-dir=<abs dir>

var directory: String = ""
var game
var building: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	# Keep the village simulating even when the window lacks OS focus.
	if is_instance_valid(game):
		game.focused = true
		game.paused = false
	return false


func capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(directory.path_join(file_name))
	print("CAPTURED ", file_name, " result=", result, " size=", image.get_size())


func focus_on_action() -> void:
	# Frame the building and the raiders around it, zoomed in for phone width.
	var center: Vector2 = Vector2(9.0, 8.0)
	if not building.is_empty():
		var c: Vector2 = game.sim.center(building)
		center = (c + Vector2(9.0, 8.0)) * 0.5
	game.target = game.world_position(center)
	game.zoom = 14.0
	game._camera_update()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	if not directory.is_absolute_path():
		printerr("ERROR missing absolute --capture-dir")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)

	root.size = Vector2i(390, 844)
	var packed: PackedScene = load("res://scenes/game.tscn")
	game = packed.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.focused = true
	game.paused = false
	await process_frame

	# Pick a real, living, multi-tile building near the western-central approach.
	var best_distance: float = INF
	for b: Dictionary in game.sim.buildings:
		if float(b["hp"]) <= 0.0 or int(b["size"]) < 2 or "hall" in str(b["type"]):
			continue
		var d: float = game.sim.center(b).distance_to(Vector2(9.0, 8.0))
		if d < best_distance:
			best_distance = d
			building = b
	print("TARGET_BUILDING ", building.get("type", "none"), " id=", building.get("id", -1))

	if not game.sim.start_raid():
		printerr("ERROR start_raid refused: ", game.sim.notice)
		quit(1)
		return
	game._refresh_hud()
	focus_on_action()

	# Wait for the raiders to actually spawn (warning is 3 simulated seconds).
	var started_at: int = Time.get_ticks_msec()
	while not game.sim.raid_active and Time.get_ticks_msec() - started_at < 10000:
		await process_frame
	if not game.sim.raid_active:
		printerr("ERROR raid never spawned")
		quit(1)
		return
	print("RAID_SPAWNED enemies=", game.sim.enemies.size())

	# 1. Spawn smoke, shortly after raiders appear.
	await create_timer(0.3).timeout
	focus_on_action()
	await capture("shot_01_spawn.png")

	# 2. Combat, roughly 6-10s into the raid.
	await create_timer(7.0).timeout
	focus_on_action()
	print("COMBAT enemies=", game.sim.enemies.size(), " notice=", game.sim.notice)
	await capture("shot_02_combat.png")

	# 3. Damaged building: 25% hp, smoke + embers.
	if not building.is_empty():
		building["hp"] = float(building["max_hp"]) * 0.25
	await create_timer(1.5).timeout
	focus_on_action()
	await capture("shot_03_damaged.png")

	# 4. Destroyed building: debris + dust.
	if not building.is_empty():
		building["hp"] = 0.0
	await create_timer(0.4).timeout
	focus_on_action()
	await capture("shot_04_destroyed.png")

	print("CAPTURE DONE")
	game.queue_free()
	await process_frame
	quit(0)
