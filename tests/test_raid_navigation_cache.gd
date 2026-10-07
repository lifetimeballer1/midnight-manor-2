extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	var sim = Sim.new()
	sim._invalidate()
	var enemy_path: Array = sim._cached_route(Vector2i(0, 0), Vector2i(0, 4), true)
	var cached: int = sim.route_cache.size()
	sim.living.navigation_revision += 1
	check(sim._cached_route(Vector2i(0, 0), Vector2i(0, 4), true) == enemy_path, "trail changes do not alter enemy routing")
	check(sim.route_cache.size() == cached, "enemy memo survives friendly-only road weight changes")
	sim._cached_route(Vector2i(0, 0), Vector2i(0, 4), false)
	cached = sim.route_cache.size()
	sim.living.navigation_revision += 1
	sim._cached_route(Vector2i(0, 0), Vector2i(0, 4), false)
	check(sim.route_cache.size() > cached, "friendly memo responds to road weight changes")
	sim.buildings.clear()
	var hall: Dictionary = sim._new_building("hall", 9, 7, false)
	sim.buildings.append(hall)
	for x in range(8, 12):
		for y in [6, 9]: sim.buildings.append(sim._new_building("wall", x, y, false))
	for y in [7, 8]:
		for x in [8, 11]:
			sim.buildings.append(sim._new_building("gate" if x == 8 and y == 7 else "wall", x, y, false))
	sim._invalidate()
	var worker: Dictionary = {"id": 900, "x": 7.5, "y": 7.5}
	check(sim._cached_edge_goal(worker, hall).x >= 0.0, "open gate permits the worker's cached hall approach")
	var revision: int = sim.revision
	sim.enemies.append({"id": 901, "type": "raider", "x": 8.7, "y": 7.5, "hp": 100.0})
	sim._gate_tick()
	check(sim.revision == revision, "gate animation does not rebuild all village models")
	check(sim._cached_edge_goal(worker, hall).x < 0.0, "closing a gate invalidates the old reachable edge goal")
	sim.enemies.clear()
	sim._gate_tick()
	check(sim._cached_edge_goal(worker, hall).x >= 0.0, "reopening a gate invalidates a cached unreachable goal")
	print("RAID_NAVIGATION_CACHE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)
