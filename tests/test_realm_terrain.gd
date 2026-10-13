extends SceneTree

# Realm terrain: rolling hills that stay buildable, one river (the only inland water) with bridges
# on the manor's roads and fishing spots on its banks, buildings that stand level on footings or
# stilts, and fishing that feeds the manor only from its own land. Past the playable edge the land
# runs on into wooded foothills and mountains, with the river leaving through its valley.

const RealmMap = preload("res://scripts/game/realm_map.gd")
const BUILDABLE_SLOPE: float = 0.42       # rise over run, about 23 degrees

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func _run() -> void:
	_land_checks()
	_river_checks()
	_beyond_checks()
	_fishing_checks()
	await _scene_checks()
	print("test_realm_terrain: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("PASS test_realm_terrain")
	quit(0 if failures.is_empty() else 1)


func _fresh():
	var realm = RealmMap.new()
	realm.generate(7)
	return realm


func _land_checks() -> void:
	var realm = _fresh()
	var steepest: float = 0.0
	var tallest: float = 0.0
	var stray_water: int = 0
	var step: float = 4.0
	var x: float = -RealmMap.EDGE_DROP_FROM + 4.0
	while x < RealmMap.EDGE_DROP_FROM - 4.0:
		var z: float = -RealmMap.EDGE_DROP_FROM + 4.0
		while z < RealmMap.EDGE_DROP_FROM - 4.0:
			var h: float = realm.height_at(x, z)
			tallest = maxf(tallest, h - RealmMap.BASE_Y)
			if realm.is_water(x, z):
				if realm.river_distance(x, z) > RealmMap.RIVER_HALF + RealmMap.RIVER_BANK:
					stray_water += 1
			elif realm.river_distance(x, z) > RealmMap.RIVER_HALF + RealmMap.RIVER_BANK + 2.0:
				var sx: float = (realm.height_at(x + 1.0, z) - h)
				var sz: float = (realm.height_at(x, z + 1.0) - h)
				steepest = maxf(steepest, sqrt(sx * sx + sz * sz))
			z += step
		x += step
	check(tallest > 5.0, "the land has real hills (%.1f m)" % tallest)
	check(steepest < BUILDABLE_SLOPE, "every slope stays buildable (steepest %.2f)" % steepest)
	check(stray_water == 0, "no lakes: the river is the only inland water")
	check(is_equal_approx(realm.height_at(0.0, 0.0), RealmMap.BASE_Y), "the ground around home stays flat")
	for site: Dictionary in realm.settlements:
		var centre: Vector2 = site["centre"]
		check(realm.river_distance(centre.x, centre.y) > RealmMap.SITE_RIVER_CLEAR, "%s keeps its streets out of the river" % site["name"])


func _river_checks() -> void:
	var realm = _fresh()
	check(realm.river_distance(0.0, 0.0) >= RealmMap.RIVER_CLEAR, "the river keeps clear of the manor")
	# It crosses the whole realm: water near both ends of its line inside the map.
	var wet_points: int = 0
	for index in realm.river_samples():
		var p: Vector2 = realm.river_point(index)
		if absf(p.x) < RealmMap.HALF - 30.0 and absf(p.y) < RealmMap.HALF - 30.0:
			check(realm.is_water(p.x, p.y), "the river line is water at %s" % p.round())
			wet_points += 1
	check(wet_points > 60, "the river runs a long way across the realm (%d samples)" % wet_points)
	check(not realm.bridges.is_empty(), "the manor's roads cross the river on bridges")
	for bridge: Dictionary in realm.bridges:
		var pos: Vector2 = bridge["pos"]
		var deck: float = realm.walk_height(pos.x, pos.y)
		check(deck > RealmMap.WATER_Y + 0.3, "a bridge deck stands above the water")
		var ends: Vector2 = pos + (bridge["dir"] as Vector2) * (float(bridge["length"]) * 0.5 + 0.5)
		check(not realm.is_water(ends.x, ends.y), "a bridge reaches dry bank")
	# Anyone off a bridge wades at most knee deep.
	var line: Vector2 = realm.river_point(realm.river_samples() / 2)
	check(realm.walk_height(line.x, line.y) >= RealmMap.WATER_Y - 0.41, "waders stay knee deep")
	check(not realm.outpost_reason(line).is_empty(), "no outpost in the river")
	# A save from before the river: an outpost in the water moves to the bank.
	var saved: Dictionary = realm.to_dict()
	saved["outposts"] = [{"id": 1, "x": line.x, "z": line.y}]
	var loaded = RealmMap.new()
	check(loaded.from_dict(saved), "a realm save with an outpost in the river still loads")
	var moved: Vector2 = loaded.outposts[0]["pos"]
	check(not loaded.is_water(moved.x, moved.y) and moved.distance_to(line) < 20.0, "that outpost moves to the nearest dry bank")


func _beyond_checks() -> void:
	var realm = _fresh()
	# No cliff at the edge: the ground just past it is no lower than the realm's own.
	var lowest: float = INF
	var tallest: float = 0.0
	for i in 64:
		var t: float = float(i) / 64.0 * TAU
		var dir := Vector2(cos(t), sin(t))
		var edge: Vector2 = dir * RealmMap.HALF / maxf(absf(dir.x), absf(dir.y))
		if realm.river_distance(edge.x, edge.y) > 40.0:
			lowest = minf(lowest, realm.height_at(edge.x * 1.06, edge.y * 1.06))
		var far: Vector2 = edge * 1.9
		if realm.river_distance(far.x, far.y) > 100.0:
			tallest = maxf(tallest, realm.height_at(far.x, far.y) - RealmMap.BASE_Y)
	check(lowest > RealmMap.WATER_Y + 0.3, "the land past the edge never drops away (lowest %.1f)" % lowest)
	check(tallest > 25.0, "mountains ring the realm (%.0f m)" % tallest)
	# The river runs on through the scenery in its valley, still water to the horizon.
	var beyond: int = 0
	for index in realm.river_samples():
		var p: Vector2 = realm.river_point(index)
		var edge: float = maxf(absf(p.x), absf(p.y))
		if edge > RealmMap.HALF + 20.0 and edge < RealmMap.OUTER_HALF - 20.0:
			beyond += 1
			if not realm.is_water(p.x, p.y):
				check(false, "the river stays water past the edge at %s" % p.round())
	check(beyond > 40, "the river leaves the realm through the mountains (%d samples)" % beyond)
	# Every tree shape turns up somewhere.
	var kinds: Dictionary = {}
	for cz in realm.chunk_count():
		for cx in realm.chunk_count():
			for tree: Dictionary in realm.trees_in_chunk(Vector2i(cx, cz)):
				kinds[int(tree["kind"])] = true
	check(kinds.size() == 6, "pines, broadleaf, reeds, boulders, bushes and poplars all grow (%s)" % str(kinds.keys()))


func _fishing_checks() -> void:
	var realm = _fresh()
	check(realm.fishing_spots.size() >= 4 and realm.fishing_spots.size() <= RealmMap.FISH_MAX, "fishing spots line the river (%d)" % realm.fishing_spots.size())
	for spot: Dictionary in realm.fishing_spots:
		var pos: Vector2 = spot["pos"]
		var cast: Vector2 = pos + (spot["dir"] as Vector2) * 7.4
		check(not realm.is_water(pos.x, pos.y) and realm.is_water(cast.x, cast.y), "spot %d stands on the bank facing the water" % int(spot["id"]))
	check(realm.home_fishing_spots() == 0, "a new manor holds no river bank yet")
	realm.advance(RealmMap.FISH_SECONDS)
	var caught: bool = false
	for event: Dictionary in realm.take_events():
		caught = caught or event["kind"] == "catch"
	check(not caught, "no catch without a spot on the manor's land")
	# Take the bank behind the nearest spot with an outpost: a catch every FISH_SECONDS.
	var first: Dictionary = realm.fishing_spots[0]
	realm.outposts.append({"id": 50, "pos": (first["pos"] as Vector2) - (first["dir"] as Vector2) * 8.0})
	check(realm.home_fishing_spots() >= 1, "an outpost brings the spot into the manor's land")
	realm.advance(RealmMap.FISH_SECONDS * 0.5)
	var early: bool = false
	for event: Dictionary in realm.take_events():
		early = early or event["kind"] == "catch"
	check(not early, "the catch waits for a full minute of play")
	realm.advance(RealmMap.FISH_SECONDS * 0.5)
	var food: int = 0
	for event: Dictionary in realm.take_events():
		if event["kind"] == "catch":
			food += int(event["loot"]["food"])
	check(food == RealmMap.FISH_FOOD * realm.home_fishing_spots(), "each held spot lands %d Food" % RealmMap.FISH_FOOD)
	var saved: Dictionary = realm.to_dict()
	var loaded = RealmMap.new()
	check(loaded.from_dict(saved) and is_equal_approx(loaded.fish_clock, realm.fish_clock), "the fishing clock is saved")
	var older: Dictionary = saved.duplicate()
	older.erase("fish_clock")
	check(loaded.from_dict(older) and loaded.fish_clock == 0.0, "realm saves without a fishing clock still load")


func _scene_checks() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)
	var realm = game.realm
	var bridges: int = 0
	var jetties: int = 0
	for child: Node in game._realm_root.get_children():
		if child.name.begins_with("Bridge"):
			bridges += 1
		if child.name.begins_with("Jetty_"):
			jetties += 1
	check(bridges == realm.bridges.size(), "every bridge is built")
	check(jetties == realm.fishing_spots.size(), "every fishing spot has a jetty")
	var water: MeshInstance3D = game._realm_root.get_node_or_null("RealmWater")
	check(water != null and water.material_override is ShaderMaterial, "the river has moving water")
	check(water != null and water.get_aabb().size.x < RealmMap.OUTER_HALF * 2.2 and water.get_aabb().end.x > RealmMap.HALF, "the water follows the river out past the edge, with no sea")
	var outskirts: MeshInstance3D = game._realm_root.get_node_or_null("RealmOutskirts")
	check(outskirts != null and outskirts.get_aabb().size.x >= RealmMap.OUTER_HALF * 2.0 - 1.0, "land runs on to the horizon past the edge")
	check(game._realm_ground.material_override is ShaderMaterial, "the ground has painted detail")
	var forest: int = 0
	for child: Node in game._realm_root.get_children():
		if child.name.begins_with("BorderForest"):
			forest += (child as MultiMeshInstance3D).multimesh.instance_count
	check(forest > 300, "woods cover the foothills past the edge (%d trees)" % forest)
	# Grass tufts only close up, within the phone cap.
	game.target = Vector3(120.0, 0.0, -60.0)
	game.zoom = 30.0
	game._camera_update()
	game.realm_stream(true)
	var grass_cap: int = game.REALM_GRASS_CHUNKS_LOW if game._realm_phone else game.REALM_GRASS_CHUNKS
	check(game.realm_grass_chunks_loaded() >= 1 and game.realm_grass_chunks_loaded() <= grass_cap, "grass tufts grow around a close view")
	game.zoom = game.zoom_max
	game._camera_update()
	game.realm_stream(true)
	check(game.realm_grass_chunks_loaded() == 0, "zoomed out, the tufts are dropped")

	# Footings: a building on a slope stands level at or above every corner of its ground.
	var steep := Vector2.ZERO
	var fall: float = 0.0
	for site: Dictionary in realm.settlements:
		for entry: Dictionary in realm.layout(site):
			var pos: Vector2 = entry["pos"]
			var ys: Array[float] = []
			for corner: Vector2 in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
				ys.append(game.realm_surface_y(pos.x + corner.x, pos.y + corner.y))
			var here: float = ys.max() - ys.min()
			if here > fall:
				fall = here
				steep = pos
	check(fall > 0.5, "some settlement building sits on a real slope (%.2f m)" % fall)
	var holder := Node3D.new()
	game._realm_root.add_child(holder)
	var top: float = game._realm_footing(holder, steep, 0.0, 2.0)
	var highest: float = -INF
	for corner: Vector2 in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
		highest = maxf(highest, game.realm_surface_y(steep.x + corner.x, steep.y + corner.y))
	check(top >= highest, "the building stands level above its highest corner")
	check(holder.get_child_count() == 1 and (holder.get_child(0) as MeshInstance3D).mesh.get_surface_count() == 1, "its stilts are one draw call")
	var flat_holder := Node3D.new()
	game._realm_root.add_child(flat_holder)
	game._realm_footing(flat_holder, Vector2(58.0, 0.0), 0.0, 2.0)   # calm ground beside home
	check(flat_holder.get_child_count() == 0, "flat ground needs no footing")

	# Fishers stream like settlements: only on held banks, within the phone cap.
	var spot: Dictionary = realm.fishing_spots[0]
	realm.outposts.append({"id": 60, "pos": (spot["pos"] as Vector2) - (spot["dir"] as Vector2) * 8.0})
	realm.revision += 1
	game.target = Vector3((spot["pos"] as Vector2).x, 0.0, (spot["pos"] as Vector2).y)
	game.zoom = 30.0
	game._camera_update()
	game.realm_stream(true)
	var cap: int = game.REALM_FISHERS_LOW if game._realm_phone else game.REALM_FISHERS
	check(game.realm_fishers_loaded() >= 1 and game.realm_fishers_loaded() <= cap, "a fisher works the manor's jetty")
	# Tapping the jetty opens its card.
	var jetty: Vector2 = (spot["pos"] as Vector2) + (spot["dir"] as Vector2) * 2.5
	check(game.realm_tap(jetty) and game.panel == "realm_fish", "tapping a jetty opens the fishing card")
	game._close_panel()
	game.queue_free()
	await process_frame
