extends SceneTree

# Scratch QA capture for the walls-and-defenses look and animations. Not a regression test;
# never saves and never loads the player's village. Combat moments are staged by feeding the
# same decoration events the sim raises (shot / hit / destroyed), so every run frames alike.
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 1280x720 --script res://tests/capture_defenses.gd -- --no-save --capture-dir=<abs dir> [--prefix=after]

const SHOWCASE: Array = [
	# A walled corner: palisade, a gate, stone wall and rampart, with every defense behind it.
	["wall", 2, 2], ["wall", 3, 2], ["wall", 4, 2], ["gate", 5, 2], ["stonewall", 6, 2], ["stonewall", 7, 2],
	["rampart", 8, 2], ["rampart", 9, 2], ["wall", 2, 3], ["wall", 2, 4], ["stonewall", 2, 5],
	["tower", 4, 4], ["archer_tower", 6, 4], ["ballista", 8, 4], ["bastion", 4, 6],
	["trap", 6, 6], ["fire-trap", 7, 6], ["watchfire", 8, 6],
]
const FOE := Vector2(6.5, 0.4)

var directory: String = ""
var prefix: String = "shot"
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
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = directory.path_join("%s_%s" % [prefix, file_name])
	print("CAPTURED ", path, " result=", image.save_png(path))


func at(x: int, y: int) -> Dictionary:
	return sim.building_at(x, y)


func frame(center: Vector2, zoom: float) -> void:
	var ground: float = 0.0
	var b: Dictionary = at(int(center.x), int(center.y))
	if not b.is_empty() and game.building_views.has(int(b["id"])):
		ground = (game.building_views[int(b["id"])]["root"] as Node3D).global_position.y
	game.target = game.world_position(center, ground)
	game.zoom = zoom
	game._camera_update()


func shoot(x: int, y: int, to: Vector2) -> void:
	var from: Vector2 = sim.center(at(x, y))
	sim.events.append({"kind": "shot", "from_x": from.x, "from_y": from.y, "x": to.x, "y": to.y})
	sim.events.append({"kind": "hit", "x": to.x, "y": to.y, "amount": 10.0, "friendly": false})


func strike(x: int, y: int) -> void:
	var c: Vector2 = sim.center(at(x, y))
	sim.events.append({"kind": "hit", "x": c.x, "y": c.y, "amount": 10.0, "friendly": true})
	sim.events.append({"kind": "hit", "x": c.x, "y": c.y, "side": "foe"})


# Records frames every 0.05 s, calling stage(i) first on each frame.
func record(name: String, frames: int, stage: Callable) -> void:
	for i in frames:
		stage.call(i)
		await create_timer(0.05).timeout
		await capture("%s_%02d.png" % [name, i])


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--prefix="):
			prefix = argument.trim_prefix("--prefix=")
	if not directory.is_absolute_path():
		printerr("ERROR missing absolute --capture-dir")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	await process_frame
	sim = game.sim
	for spot: Array in SHOWCASE:
		var other: Dictionary = at(int(spot[1]), int(spot[2]))
		if not other.is_empty() and str(other["type"]) != "hall":
			sim.buildings.erase(other)
	for spot: Array in SHOWCASE:
		if at(int(spot[1]), int(spot[2])).is_empty():
			sim.buildings.append(sim._new_building(str(spot[0]), int(spot[1]), int(spot[2]), false))
	sim.revision += 1
	sim._invalidate()
	for layer in game.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await create_timer(1.5).timeout

	frame(Vector2(6.0, 4.0), 12.0)
	await create_timer(0.4).timeout
	await capture("01_overview.png")
	frame(Vector2(5.5, 2.5), 6.0)
	await create_timer(0.3).timeout
	await capture("02_walls.png")
	frame(Vector2(3.0, 3.5), 5.0)
	await create_timer(0.3).timeout
	await capture("03_corner.png")

	frame(Vector2(5.5, 3.6), 5.0)
	await create_timer(0.3).timeout
	await record("towers", 36, func(i: int) -> void:
		if i % 12 == 0: shoot(6, 4, FOE)
		if i % 12 == 6: shoot(4, 4, FOE + Vector2(-1.5, 0.0)))
	frame(Vector2(6.5, 4.6), 5.5)
	await create_timer(0.3).timeout
	await record("siege", 36, func(i: int) -> void:
		if i % 18 == 0: shoot(8, 4, FOE + Vector2(2.0, 0.0))
		if i % 18 == 9: shoot(4, 6, FOE + Vector2(-1.0, 0.0)))
	frame(Vector2(7.0, 6.5), 3.5)
	await create_timer(0.3).timeout
	await record("traps", 30, func(i: int) -> void:
		if i % 15 == 0: shoot(6, 6, Vector2(6.5, 6.5))
		if i % 15 == 7: shoot(7, 6, Vector2(7.5, 6.5)))
	frame(Vector2(6.5, 2.5), 3.5)
	await create_timer(0.3).timeout
	await record("wall_hits", 24, func(i: int) -> void:
		if i % 8 == 0: strike(6, 2)
		if i % 8 == 4: strike(7, 2))
	for b: Dictionary in sim.buildings:
		if str(b["type"]) in ["stonewall", "archer_tower", "tower"]:
			b["hp"] = float(b["max_hp"]) * 0.2
	await create_timer(2.0).timeout
	frame(Vector2(5.5, 3.4), 5.5)
	await create_timer(0.3).timeout
	await capture("04_damaged.png")
	await record("collapse", 30, func(i: int) -> void:
		if i == 2:
			for target: Array in [[7, 2], [6, 4], [4, 4]]:
				var b: Dictionary = at(target[0], target[1])
				b["hp"] = 0.0
				sim._ruin(sim.center(b))   # the event a raider's killing blow raises
		)
	await create_timer(1.5).timeout
	await capture("05_ruins.png")
	print("CAPTURE DONE")
	game.queue_free()
	await process_frame
	quit(0)
