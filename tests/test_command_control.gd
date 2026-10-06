extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func _run() -> void:
	var sim = Sim.new()
	sim.units.clear()
	for index in 400:
		sim._add_unit(["builder", "farmer", "lumberjack", "miner"][index % 4])
	sim.paused = false
	var sim_start: int = Time.get_ticks_msec()
	for tick in 40:
		sim.tick(0.05)
	var sim_ms: int = Time.get_ticks_msec() - sim_start
	check(sim.units.size() == 400, "400-villager simulation keeps the full population")
	var finite_positions: bool = true
	for unit: Dictionary in sim.units:
		finite_positions = finite_positions and is_finite(float(unit["x"])) and is_finite(float(unit["y"]))
	check(finite_positions, "heavy-population simulation keeps valid positions")
	print("COMMAND_CONTROL_SIM_400_MS ", sim_ms)

	root.size = Vector2i(1280, 800)
	var packed: PackedScene = load("res://scenes/game.tscn")
	var game = packed.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	var initial_actor_count: int = game.actors.size()
	game.sim.units.clear()
	for index in 400:
		game.sim._add_unit(["builder", "farmer", "lumberjack", "miner"][index % 4])
	game.actor_accumulator = 0.0
	game._process(0.016)
	check(game.actors.size() == initial_actor_count, "render actors are not rebuilt every display frame")
	var render_start: int = Time.get_ticks_msec()
	game._process(0.04)
	var first_sync_ms: int = Time.get_ticks_msec() - render_start
	check(game.actors.size() == 400, "20 Hz visual sync catches up to all 400 villagers")
	print("COMMAND_CONTROL_RENDER_400_FIRST_SYNC_MS ", first_sync_ms)
	game.target = Vector3(200, 0, 200)
	game._camera_update()
	game._update_actors(0.05)
	var visible: int = 0
	for record: Dictionary in game.actors.values():
		if (record["model"] as Node3D).visible:
			visible += 1
	check(visible < 50, "off-screen actor culling drops insignificant villagers from rendering")
	game.battery_saver = true
	game._apply_power_settings()
	check(Engine.max_fps == 30, "battery saver caps rendering at 30 fps")
	game.battery_saver = false
	game._apply_power_settings()
	game.free()
	await process_frame
	print("COMMAND_CONTROL_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
