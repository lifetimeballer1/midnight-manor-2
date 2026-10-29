extends SceneTree

# Scratch QA capture for raids and defenses. Not a regression test.
# Run WITHOUT --headless (needs a renderer):
#   xvfb-run godot --path . --resolution 1280x800 --script res://tests/capture_warfare.gd -- --no-save --size=1280x800 --capture-dir=<abs dir> [--wave=9] [--prefix=after]

var directory: String = ""
var prefix: String = "shot"
var wave: int = 8
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
	var path: String = directory.path_join(prefix + "-" + file_name)
	print("CAPTURED ", path, " result=", image.save_png(path))


func view(center: Vector2, zoom: float, tilt: float = 0.75, yaw: float = 0.66) -> void:
	game.target = game.world_position(center)
	game.zoom = zoom
	game.tilt = tilt
	game.yaw = yaw
	game._camera_update()


func stage() -> void:
	var sim = game.sim
	sim.xp = 2600
	sim.wave = wave - 1
	for resource in sim.resources.keys():
		sim.resources[resource] = 5000.0
	var defenses: Array = [["archer_tower", 3, 5], ["ballista", 3, 11], ["tower", 15, 6], ["bastion", 14, 10],
		["watchfire", 9, 3], ["trap", 2, 8], ["trap", 2, 9], ["fire-trap", 16, 8], ["fire-trap", 9, 13]]
	for entry: Array in defenses:
		if sim.building_specs.has(entry[0]) and sim.building_at(entry[1], entry[2]).is_empty():
			sim.buildings.append(sim._new_building(entry[0], entry[1], entry[2], false))
	for y in range(4, 13):
		if sim.building_at(4, y).is_empty():
			sim.buildings.append(sim._new_building("gate" if y == 8 else "stonewall", 4, y, false))
	for role: String in ["warrior", "warrior", "warrior", "archer", "archer", "archer"]:
		sim._add_unit(role)
	sim._invalidate()
	sim.revision += 1


func _run() -> void:
	var size := Vector2i(1280, 800)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--size="):
			var parts: PackedStringArray = argument.trim_prefix("--size=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--prefix="):
			prefix = argument.trim_prefix("--prefix=")
		elif argument.begins_with("--wave="):
			wave = int(argument.trim_prefix("--wave="))
	if not directory.is_absolute_path():
		printerr("ERROR missing absolute --capture-dir")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = size
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.focused = true
	game.paused = false
	stage()
	await create_timer(1.5).timeout
	var mid := Vector2(10.0, 8.0)
	game.night = true
	game._toggle_day()
	await create_timer(0.6).timeout
	view(mid, 24.0)
	await capture("0-defended.png")
	game.sim.start_raid()
	var t0: int = Time.get_ticks_msec()
	while not game.sim.raid_active and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	await create_timer(2.0).timeout
	view(mid, 26.0)
	await capture("1-arrive.png")
	for i in 6:
		await create_timer(2.5).timeout
		var focus: Vector2 = mid
		var role: String = ["warlord", "ram", "bombard", "warlord", "", ""][i]
		for e: Dictionary in game.sim.enemies:
			if float(e["hp"]) > 0.0 and (role.is_empty() or str(e.get("role", "")) == role):
				focus = Vector2(float(e["x"]), float(e["y"]))
				break
		view(focus, 9.0 if not role.is_empty() else 14.0, 0.62)
		await capture("%d-fight-%s.png" % [i + 2, role if not role.is_empty() else "wide"])
	var waited: int = Time.get_ticks_msec()
	while game.sim.raid_active and Time.get_ticks_msec() - waited < 60000:
		await create_timer(0.5).timeout
	await create_timer(1.2).timeout
	view(mid, 24.0)
	await capture("9-after.png")

	print("CAPTURE DONE raid_active=", game.sim.raid_active, " stats=", game.sim.raid_stats)
	game.queue_free()
	await process_frame
	quit(0)
