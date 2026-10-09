extends SceneTree

# Equivalence + speed checks for the optimised pathfinding (village_sim.gd walk grids)
# and the incremental building view rebuild (village_game.gd _rebuild_buildings).

const Sim = preload("res://scripts/game/village_sim.gd")

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		printerr("FAIL ", text)


func _run() -> void:
	_routes()
	await _views()
	print("RAID_PERF ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- reference algorithms

# Original BFS: a tile is walkable iff _inside and not _blocked; DIRECTIONS order; first discovery wins.
func ref_bfs(sim, start: Vector2i, goal: Vector2i, enemy: bool) -> Array:
	if not sim._inside(start) or not sim._inside(goal):
		return []
	if start == goal:
		return [start]
	if sim._blocked(goal, enemy):
		return []
	var previous: Dictionary = {start: start}
	var queue: Array = [start]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for direction: Vector2i in Sim.DIRECTIONS:
			var next: Vector2i = current + direction
			if previous.has(next) or not sim._inside(next) or sim._blocked(next, enemy):
				continue
			previous[next] = current
			queue.append(next)
			if next == goal:
				return _trace(previous, start, goal)
	return []


# Original Dijkstra for friendly units: lowest distance wins, earliest queued wins ties.
func ref_dijkstra(sim, start: Vector2i, goal: Vector2i) -> Array:
	if not sim._inside(start) or not sim._inside(goal):
		return []
	if start == goal:
		return [start]
	if sim._blocked(goal, false):
		return []
	var distances: Dictionary = {start: 0.0}
	var previous: Dictionary = {}
	var queued: Dictionary = {start: true}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var best: int = 0
		var best_distance: float = distances[frontier[0]]
		for index in range(1, frontier.size()):
			var candidate: float = distances[frontier[index]]
			if candidate < best_distance:
				best = index
				best_distance = candidate
		var tile: Vector2i = frontier[best]
		frontier.remove_at(best)
		queued.erase(tile)
		if tile == goal:
			return _trace(previous, start, goal)
		for direction: Vector2i in Sim.DIRECTIONS:
			var next: Vector2i = tile + direction
			if not sim._inside(next) or sim._blocked(next, false):
				continue
			var cost: float = float(distances[tile]) + sim.living.route_cost(next)
			if not distances.has(next) or cost < float(distances[next]):
				distances[next] = cost
				previous[next] = tile
				if not queued.has(next):
					queued[next] = true
					frontier.append(next)
	return []


func _trace(previous: Dictionary, start: Vector2i, goal: Vector2i) -> Array:
	var path: Array = []
	var step: Vector2i = goal
	while step != start:
		path.append(step)
		step = previous[step]
	path.append(start)
	path.reverse()
	return path


# ---------------------------------------------------------------- fixtures

func _fixture():
	var sim = Sim.new()
	sim.buildings.clear()
	sim.buildings.append(sim._new_building("hall", 9, 7, false))
	# Wall row at y=4 with a gate at x=7.
	for x in range(2, 14):
		sim.buildings.append(sim._new_building("gate" if x == 7 else "wall", x, 4, false))
	# Wall row at y=11 with a gate at x=10 that starts shut.
	for x in range(3, 17):
		sim.buildings.append(sim._new_building("gate" if x == 10 else "wall", x, 11, false))
	# Short vertical wall.
	for y in range(6, 10):
		sim.buildings.append(sim._new_building("wall", 5, y, false))
	for t: Vector2i in [Vector2i(1, 1), Vector2i(18, 1), Vector2i(1, 14), Vector2i(18, 14)]:
		sim.buildings.append(sim._new_building("tower", t.x, t.y, false))
	for t: Vector2i in [Vector2i(13, 7), Vector2i(16, 1), Vector2i(2, 7)]:
		sim.buildings.append(sim._new_building("cottage", t.x, t.y, false))
	for t: Vector2i in [Vector2i(7, 13), Vector2i(12, 13)]:
		sim.buildings.append(sim._new_building("farm", t.x, t.y, false))
	for b: Dictionary in sim.buildings:
		if b["type"] == "gate" and int(b["y"]) == 11:
			b["gate_open"] = false
	# Weighted terrain so friendly Dijkstra costs differ (stone roads and worn trails).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 80:
		var tile: Vector2i = _tile(rng)
		sim.living.cells[sim.living.key(tile)] = {"wear": 1.0 if i % 2 == 0 else 0.2, "last": 0.0, "stone": rng.randf() < 0.25}
	sim._invalidate()
	return sim


func _tile(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(rng.randi_range(0, 19), rng.randi_range(0, 15))


func _plain(path: Array) -> Array:
	var out: Array = []
	for tile in path:
		out.append(tile)
	return out


# Returns {"bad": [[a, b], ...], "found": n} for the given pairs.
func _compare(sim, pairs: Array, enemy: bool, weighted: bool) -> Dictionary:
	var bad: Array = []
	var found: int = 0
	for pair in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var got: Array = _plain(sim.route(a, b, enemy))
		var want: Array = ref_dijkstra(sim, a, b) if weighted else ref_bfs(sim, a, b, enemy)
		if not got.is_empty():
			found += 1
		if got != want:
			bad.append([a, b])
	return {"bad": bad, "found": found}


func _make_pairs(seed_value: int, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pairs: Array = []
	for i in count:
		pairs.append([_tile(rng), _tile(rng)])
	return pairs


func _find_wall(sim, tile: Vector2i) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if b["type"] == "wall" and Vector2i(int(b["x"]), int(b["y"])) == tile:
			return b
	return {}


# ---------------------------------------------------------------- A and B: routing

func _routes() -> void:
	var sim = _fixture()
	var pairs: Array = _make_pairs(20261009, 150)

	# Friendly BFS (navigation_revision == 0) and enemy BFS against the reference.
	sim.living.navigation_revision = 0
	var result: Dictionary = _compare(sim, pairs, true, false)
	check(result["bad"].is_empty(), "enemy route matches reference BFS on 150 random pairs (mismatches=%d)" % result["bad"].size())
	check(int(result["found"]) >= 60, "random pairs produce real enemy routes, not just empties (found=%d)" % int(result["found"]))
	result = _compare(sim, pairs, false, false)
	check(result["bad"].is_empty(), "friendly route with navigation_revision 0 matches reference BFS (mismatches=%d)" % result["bad"].size())

	# Friendly Dijkstra (navigation_revision > 0) and enemy BFS unchanged.
	sim.living.navigation_revision = 1
	result = _compare(sim, pairs, true, false)
	check(result["bad"].is_empty(), "enemy route still matches reference BFS with navigation_revision 1 (mismatches=%d)" % result["bad"].size())
	result = _compare(sim, pairs, false, true)
	check(result["bad"].is_empty(), "friendly weighted route matches reference Dijkstra on 150 random pairs (mismatches=%d)" % result["bad"].size())
	check(int(result["found"]) >= 60, "random pairs produce real friendly routes (found=%d)" % int(result["found"]))

	# Edge cases, under both friendly modes.
	for nav in [0, 1]:
		sim.living.navigation_revision = nav
		check(_plain(sim.route(Vector2i(3, 2), Vector2i(3, 2), false)) == [Vector2i(3, 2)], "start == goal returns [start] for friendlies (nav %d)" % nav)
		check(_plain(sim.route(Vector2i(3, 2), Vector2i(3, 2), true)) == [Vector2i(3, 2)], "start == goal returns [start] for enemies (nav %d)" % nav)
		check(sim.route(Vector2i(0, 0), Vector2i(9, 8), false).is_empty(), "goal inside a standing hall is unreachable for friendlies (nav %d)" % nav)
		check(sim.route(Vector2i(0, 0), Vector2i(9, 8), true).is_empty(), "goal inside a standing hall is unreachable for enemies (nav %d)" % nav)

	# Destroy the wall at (10,4): the grid must refresh with no other change.
	sim.living.navigation_revision = 1
	check(sim.route(Vector2i(10, 2), Vector2i(10, 6), true).size() > 5, "wall row blocks the direct enemy path before the wall falls")
	var fallen: Dictionary = _find_wall(sim, Vector2i(10, 4))
	fallen["hp"] = 0.0
	sim._invalidate()
	check(_plain(sim.route(Vector2i(10, 2), Vector2i(10, 6), true)) == [Vector2i(10, 2), Vector2i(10, 3), Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 6)], "a fallen wall opens the direct enemy path (grid refreshed)")
	var after_loss: Array = _make_pairs(77, 40)
	result = _compare(sim, after_loss, true, false)
	check(result["bad"].is_empty(), "enemy route matches reference BFS after a wall falls (mismatches=%d)" % result["bad"].size())
	result = _compare(sim, after_loss, false, true)
	check(result["bad"].is_empty(), "friendly weighted route matches reference Dijkstra after a wall falls (mismatches=%d)" % result["bad"].size())

	# B: speed of enemy route() on the developed village.
	var speed_pairs: Array = _make_pairs(5, 30)
	var total_us: int = 0
	for pair in speed_pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var t0: int = Time.get_ticks_usec()
		sim.route(a, b, true)
		total_us += Time.get_ticks_usec() - t0
	var avg_ms: float = total_us / 1000.0 / 30.0
	print("route avg ms=%.3f over 30 enemy calls" % avg_ms)
	check(avg_ms < 25.0, "enemy route averages under 25 ms on a developed village (%.3f ms)" % avg_ms)


# ---------------------------------------------------------------- C: incremental view rebuild

func _roots(game) -> Dictionary:
	var roots: Dictionary = {}
	for id in game.building_views:
		roots[id] = game.building_views[id]["root"]
	return roots


func _free_tile(sim, tile: Vector2i) -> bool:
	if not sim.in_world(tile):
		return false
	for b: Dictionary in sim.buildings:
		if Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"])).has_point(tile):
			return false
	return true


func _find_free_pair(sim) -> Array:
	for y in range(0, 16):
		for x in range(0, 19):
			var a := Vector2i(x, y)
			var b := Vector2i(x + 1, y)
			if _free_tile(sim, a) and _free_tile(sim, b):
				return [a, b]
	return []


func _first_building(sim, excluded: Array) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if int(b["hp"]) > 0 and b["type"] not in excluded:
			return b
	return {}


func _far_building(sim, tile: Vector2i) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if b["type"] in ["wall", "stonewall", "gate"] or float(b["hp"]) <= 0.0:
			continue
		if absi(int(b["x"]) - tile.x) + absi(int(b["y"]) - tile.y) > 6:
			return b
	return {}


func _views() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	await process_frame
	var sim = game.sim
	check(game.building_views.size() == sim.buildings.size(), "starting building views match the sim's buildings")

	# C1: one non-wall building falls. Every other non-wall root must be the same instance.
	var before: Dictionary = _roots(game)
	var target: Dictionary = _first_building(sim, ["wall", "stonewall", "gate", "hall"])
	var dead_id: int = int(target["id"])
	target["hp"] = 0.0
	sim.revision += 1
	sim._invalidate()
	game._rebuild_buildings()
	var others_count: int = 0
	var others_kept: bool = true
	for b: Dictionary in sim.buildings:
		var id: int = int(b["id"])
		if id == dead_id or b["type"] in ["wall", "stonewall", "gate"]:
			continue
		others_count += 1
		if not is_instance_valid(before.get(id)) or game.building_views[id]["root"] != before[id]:
			others_kept = false
	check(others_count > 0 and others_kept, "losing one building keeps every other non-wall building's root instance (%d checked)" % others_count)
	check(game.building_views.has(dead_id), "the destroyed building keeps its (ruined) view")
	check(game.view_revision == sim.revision, "view revision follows the sim after an incremental rebuild")

	# C2: two adjacent walls; losing one must rebuild its standing neighbour (join mask) only.
	var pair: Array = _find_free_pair(sim)
	check(pair.size() == 2, "found two free adjacent tiles for a wall pair")
	var a: Vector2i = pair[0]
	var w1: Dictionary = sim._new_building("wall", a.x, a.y, false)
	var w2: Dictionary = sim._new_building("wall", a.x + 1, a.y, false)
	sim.buildings.append(w1)
	sim.buildings.append(w2)
	sim.revision += 1
	sim._invalidate()
	game._rebuild_buildings()
	var far: Dictionary = _far_building(sim, a)
	check(not far.is_empty(), "village has a far-away non-wall building to watch")
	var w2_root: Node3D = game.building_views[int(w2["id"])]["root"]
	var far_root: Node3D = game.building_views[int(far["id"])]["root"]
	w1["hp"] = 0.0
	sim.revision += 1
	sim._invalidate()
	game._rebuild_buildings()
	var new_w2_root: Node3D = game.building_views[int(w2["id"])]["root"]
	check(new_w2_root != w2_root, "losing a wall rebuilds its standing neighbour (join mask changed)")
	check(game.building_views[int(far["id"])]["root"] == far_root, "a far-away building's root is untouched by a wall loss")
	check(game.building_views.has(int(w1["id"])), "the destroyed wall keeps its view")
	check(game.view_revision == sim.revision, "view revision follows the sim after a wall loss")

	# C3: full rebuild after clear() gives every building a fresh root.
	var old: Dictionary = _roots(game)
	game.building_views.clear()
	game._rebuild_buildings()
	var all_fresh: bool = true
	for id in old:
		var fresh = game.building_views.get(id, {}).get("root")
		if not is_instance_valid(fresh) or (is_instance_valid(old[id]) and fresh == old[id]):
			all_fresh = false
	check(all_fresh, "clearing building_views forces every building root to be rebuilt")
	check(game.building_views.size() == sim.buildings.size(), "full rebuild has one view per sim building")

	game.free()
	for i in 30:
		await process_frame
