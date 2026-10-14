extends SceneTree

# Scratch QA capture for the building-by-building fit review. Not a regression test; never saves
# and never loads the player's village. Each non-defense building type is placed alone on the same
# plot of the starting village and framed close at night (its lights) and by day (its fit).
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 640x480 --script res://tests/capture_buildings.gd -- --no-save --capture-dir=<abs dir> [--prefix=before] [--only=a,b] [--top-tier]

const DEFENSES: Array[String] = ["wall", "stonewall", "gate", "rampart", "tower", "archer_tower",
	"ballista", "bastion", "trap", "fire-trap", "watchfire"]
const PLOT := Vector2i(12, 9)

var directory: String = ""
var prefix: String = "shot"
var only: Array[String] = []
var top_tier: bool = false
var game
var sim


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if is_instance_valid(game):
		game.focused = true
		game.paused = false
	return false


func capture(file_name: String) -> void:
	# Celebration banners float over the plot; they are not part of the building.
	for label in game.find_children("*", "Label3D", true, false):
		if not game.building_layer.is_ancestor_of(label):
			(label as Label3D).visible = false
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = directory.path_join("%s_%s" % [prefix, file_name])
	print("CAPTURED ", path, " result=", image.save_png(path))


func set_time(day: bool) -> void:
	# Position in the 8-minute cycle: 0.7 is full day, 0.1 deep night.
	var want: float = (0.7 if day else 0.1) * game.DAY_LENGTH
	game.cycle_offset = want - fmod(sim.elapsed, game.DAY_LENGTH)
	game.day_blend = game._day_blend()
	game.last_blend = game.day_blend
	game.night = game.day_blend < 0.5
	game._apply_lighting()


func place(type_name: String, tier: int) -> Dictionary:
	var size: int = int(sim.building_specs[type_name]["size"])
	for other: Dictionary in sim.buildings.duplicate():
		var ox: int = int(other["x"])
		var oy: int = int(other["y"])
		var osize: int = int(other["size"])
		var clear: bool = ox + osize <= PLOT.x - 1 or ox >= PLOT.x + size + 1 or oy + osize <= PLOT.y - 1 or oy >= PLOT.y + size + 1
		if not clear and str(other["type"]) != "hall":
			sim.buildings.erase(other)
	var b: Dictionary = sim._new_building(type_name, PLOT.x, PLOT.y, false)
	b["tier"] = tier
	sim.buildings.append(b)
	sim.revision += 1
	sim._invalidate()
	if game.has_method("_vfx_sync_sites"):
		game._vfx_sync_sites()
	return b


func frame(b: Dictionary) -> void:
	var size: float = float(b["size"])
	var middle: Vector3 = game.world_position(sim.center(b))
	if game.building_views.has(int(b["id"])):
		var view: Dictionary = game.building_views[int(b["id"])]
		middle = (view["root"] as Node3D).global_position
		middle.y += 0.5 * maxf(0.5, (view["label"] as Node3D).position.y - 0.5)
	game.target = middle
	game.zoom = 3.4 + 2.6 * size
	game._camera_update()
	# Recentre on screen: later layers may bias the view, so measure and correct once.
	var camera: Camera3D = game.camera
	var rect: Vector2 = camera.get_viewport().get_visible_rect().size
	var half: Vector2 = rect * 0.5
	var off: Vector2 = camera.unproject_position(middle) - half
	var metres: float = camera.size / rect.y
	var right: Vector3 = camera.global_transform.basis.x
	var up: Vector3 = camera.global_transform.basis.y
	game.target += right * off.x * metres - up * off.y * metres
	game._camera_update()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--prefix="):
			prefix = argument.trim_prefix("--prefix=")
		elif argument.begins_with("--only="):
			for name: String in argument.trim_prefix("--only=").split(","):
				only.append(name)
		elif argument == "--top-tier":
			top_tier = true
	if not directory.is_absolute_path():
		printerr("ERROR missing absolute --capture-dir")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(960, 720)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	await process_frame
	sim = game.sim
	for layer in game.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await create_timer(1.0).timeout
	var types: Array = sim.building_specs.keys()
	types.sort()
	for type_name: String in types:
		if type_name in DEFENSES or type_name == "hall":
			continue
		if not only.is_empty() and type_name not in only:
			continue
		var tiers: int = (sim.building_specs[type_name]["tiers"] as Array).size()
		var b: Dictionary = place(type_name, tiers if top_tier else 1)
		await process_frame
		await process_frame
		frame(b)
		set_time(false)
		await create_timer(0.35).timeout
		await capture("%s_night.png" % type_name)
		set_time(true)
		await create_timer(0.35).timeout
		await capture("%s_day.png" % type_name)
	if only.is_empty() or "hall" in only:
		for b: Dictionary in sim.buildings:
			if str(b["type"]) == "hall":
				frame(b)
				set_time(false)
				await create_timer(0.35).timeout
				await capture("hall_night.png")
				set_time(true)
				await create_timer(0.35).timeout
				await capture("hall_day.png")
	print("CAPTURE DONE")
	game.queue_free()
	await process_frame
	quit(0)
