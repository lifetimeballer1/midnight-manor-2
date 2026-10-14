extends SceneTree

# Town zoning (town_zoning.gd + village_zoning.gd): cells outside the walls on the manor's own land
# take zones and roads, the village and foreign land never do; zones grow only beside a road that
# reaches the manor (or an outpost) and only with demand; lots move up a level when their needs are
# met; income banks through the village's storage rules; the art named in data/zones.json exists;
# saves round-trip and refuse junk; and the scene paints, grows and shows lots without touching the
# village simulation's own buildings or save.

const RealmMap = preload("res://scripts/game/realm_map.gd")
const Town = preload("res://scripts/game/town_zoning.gd")

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
	_data_checks()
	_land_checks()
	_growth_checks()
	_save_checks()
	await _scene_checks()
	print("test_town_zoning: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("PASS test_town_zoning")
	quit(0 if failures.is_empty() else 1)


func _town():
	var realm = RealmMap.new()
	realm.generate(7)
	var town = Town.new()
	town.realm = realm
	return town


# A straight road south from the village edge, and the cells either side of it.
func _south_strip(town, length: int) -> Array[Vector2i]:
	var sides: Array[Vector2i] = []
	for step in length:
		var c := Vector2i(0, 9 + step)
		check(town.paint_road(c).is_empty(), "road %s can be laid (%s)" % [c, town.road_reason(c)])
		sides.append(Vector2i(-1, 9 + step))
		sides.append(Vector2i(1, 9 + step))
	return sides


func _data_checks() -> void:
	var town = Town.new()
	var catalog: Dictionary = {}
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/catalog.json"))
	for entry: Dictionary in parsed["assets"]:
		catalog[entry["asset"]] = true
	check(town.zone_ids() == ["housing", "farming", "industrial", "civic"], "four zones in order")
	for zone: String in town.zone_ids():
		check(town.max_level(zone) == 3, "%s has three levels" % zone)
		for level in range(1, town.max_level(zone) + 1):
			for asset: Variant in town.level_spec(zone, level).get("assets", []):
				check(catalog.has(str(asset)), "%s level %d art %s is a delivered asset" % [zone, level, asset])
	check(int(town.road_cost().get("wood", 0)) > 0, "roads cost Wood")


func _land_checks() -> void:
	var town = _town()
	check(town.cell == 4.0, "cells are 4 m")
	# Village and its four reaches are never zoned.
	for c: Vector2i in [Vector2i(0, 0), Vector2i(-10, -9), Vector2i(9, 8), Vector2i(5, -5)]:
		check(town.in_village(c) and not town.can_build(c), "village cell %s stays hand-built" % c)
	# The manor's ring just outside the reaches is buildable land.
	for c: Vector2i in [Vector2i(0, 9), Vector2i(0, -10), Vector2i(10, 0), Vector2i(-11, 0)]:
		check(town.can_build(c), "manor land %s is zonable (%s)" % [c, town.land_reason(c)])
	check(town.village_edge(Vector2i(0, 9)) and not town.village_edge(Vector2i(0, 11)), "the village edge is where roads start")
	# Beyond the claim is someone else's or wild.
	check(not town.can_build(Vector2i(0, 20)), "land past the manor's claim is not zonable")
	check(town.paint_zone(Vector2i(0, 20), "housing") != "", "painting foreign land is refused")
	check(town.paint_zone(Vector2i(0, 0), "housing") != "", "painting the village is refused")
	check(town.paint_zone(Vector2i(0, 9), "nonsense") != "", "unknown zones are refused")
	# An outpost brings its land in.
	var realm = town.realm
	var far := Vector2(0, 90)
	while not realm.outpost_reason(far).is_empty() and far.y > 60.0:
		far.y -= 2.0
	if realm.found_outpost(far):
		var near: Vector2i = town.cell_of(far + Vector2(8, 0))
		check(town.can_build(near) or town.land_reason(near).contains("river") or town.land_reason(near).contains("steep"), "an outpost's land becomes zonable (%s)" % town.land_reason(near))
		check(not town.can_build(town.cell_of(far)), "the outpost's own spot stays clear")


func _growth_checks() -> void:
	var town = _town()
	# Zones without a road never grow.
	for x in range(-4, 5):
		town.paint_zone(Vector2i(x, 11), "housing")
	for step in 40:
		town.tick(1.0)
	check(town.lots.is_empty(), "zones without a road stay empty")
	# A road that does not reach the manor is not enough either.
	town.paint_road(Vector2i(0, 12))
	for step in 20:
		town.tick(1.0)
	check(town.lots.is_empty(), "a road cut off from the manor grows nothing")
	check(not town.network().has(Vector2i(0, 12)), "a stray road is outside the network")
	town.erase(Vector2i(0, 12))
	for x in range(-4, 5):
		town.erase(Vector2i(x, 11))
	check(town.zones.is_empty() and town.roads.is_empty(), "erase clears zones and roads")

	var sides: Array[Vector2i] = _south_strip(town, 4)
	check(town.network().size() == 4, "a road from the village edge joins the network")
	for c: Vector2i in sides:
		check(town.paint_zone(c, "housing").is_empty(), "housing beside the road at %s" % c)
	check(town.paint_zone(Vector2i(0, 9), "housing") == "A road runs here.", "zones do not paint over roads")
	check(town.demand()["housing"] > 0.5, "an empty town wants homes")
	check(town.demand()["industrial"] <= 0.1 and town.demand()["civic"] == 0.0, "industry and civic wait for people")
	var started: int = 0
	var grew: int = 0
	for step in 120:
		town.tick(0.5)
		for event: Dictionary in town.take_events():
			if event["kind"] == "started":
				started += 1
			if event["kind"] == "grew":
				grew += 1
	check(started > 0 and grew > 0, "zoned cells beside a road grow lots (%d started, %d built)" % [started, grew])
	check(town.lots.size() < sides.size(), "homes stop growing without jobs (%d of %d)" % [town.lots.size(), sides.size()])
	var homes_then: int = town.lots.size()
	# Farms on the other side bring jobs, so more homes follow.
	var farm_cells: Array[Vector2i] = []
	for step in 4:
		var c := Vector2i(2, 9 + step)
		farm_cells.append(c)
	for c: Vector2i in farm_cells:
		check(town.paint_zone(c, "farming").is_empty() or town.lots.has(c), "farm zone at %s" % c)
	for c: Vector2i in farm_cells:
		check(town.zones.has(c) and str(town.zones[c]) == "farming", "farm painted at %s" % c)
	# The farms sit beside the housing column, which is not a road: give them their own road.
	for step in 4:
		town.paint_road(Vector2i(3, 9 + step))
	check(town.demand()["farming"] > 0.2, "homes make farms wanted")
	for step in 240:
		town.tick(0.5)
	town.take_events()
	var stats: Dictionary = town.stats()
	check(int(stats["by_zone"]["farming"]) > 0, "farms grow when wanted")
	check(town.lots.size() > homes_then, "jobs let more homes grow")
	check(int(stats["people"]) > 0 and int(stats["jobs"]) > 0, "the town counts people and jobs")

	# Levelling: a home beside farms with food and safety moves up.
	town.village_food = 100.0
	var home: Vector2i = Vector2i(-9999, -9999)
	for c: Vector2i in town.lots:
		if town.lots[c]["zone"] == "housing" and town.built(town.lots[c]):
			home = c
			break
	check(home.x != -9999, "a built home exists")
	if home.x != -9999:
		var needs: Array = town.next_needs(home)
		check(needs.size() >= 3, "a home lists its next level's needs")
		for step in 200:
			town.tick(0.5)
		check(int(town.lots[home]["level"]) >= 2, "a home with food, farms and safety becomes cottages")
	var levelled: bool = false
	for event: Dictionary in town.take_events():
		levelled = levelled or event["kind"] == "levelled"
	# Food runs out: homes stop levelling (they keep what they have).
	town.village_food = 0.0
	var level_now: Dictionary = {}
	for c: Vector2i in town.lots:
		level_now[c] = int(town.lots[c]["level"])
	for step in 100:
		town.tick(0.5)
	var dropped: bool = false
	for c: Vector2i in level_now:
		if town.lots.has(c) and int(town.lots[c]["level"]) < int(level_now[c]):
			dropped = true
	check(not dropped, "lots never lose levels")

	# Income: every period, built lots send their level's income.
	var income: Dictionary = town.income_now()
	check(int(income.get("gold", 0)) > 0 and int(income.get("food", 0)) > 0, "homes pay Gold, farms send Food (%s)" % income)
	town.income_clock = float(town.specs["incomeSeconds"]) - 0.25
	town.tick(0.5)
	var paid: bool = false
	for event: Dictionary in town.take_events():
		paid = paid or event["kind"] == "income"
	check(paid, "income arrives once a period")

	# Repainting a grown lot as another zone clears it; erasing a road cuts lots off from growth.
	var lot_cell: Vector2i = town.lots.keys()[0]
	var old_zone: String = str(town.lots[lot_cell]["zone"])
	town.paint_zone(lot_cell, "civic" if old_zone != "civic" else "housing")
	check(not town.lots.has(lot_cell), "repainting a lot clears it")
	check(town.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "cleared"), "the clearing is announced")
	town.paint_road(lot_cell)
	check(town.roads.has(lot_cell) and not town.zones.has(lot_cell), "a road replaces a zone")


func _save_checks() -> void:
	var town = _town()
	_south_strip(town, 3)
	town.paint_zone(Vector2i(-1, 9), "housing")
	town.paint_zone(Vector2i(1, 9), "farming")
	for step in 30:
		town.tick(1.0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(town.to_dict()))
	var copy = _town()
	check(copy.from_dict(data), "a town save loads")
	check(copy.zones == town.zones and copy.roads.size() == town.roads.size() and copy.lots.size() == town.lots.size(), "zones, roads and lots survive a save")
	for c: Vector2i in town.lots:
		check(copy.lots.has(c) and copy.lots[c]["zone"] == town.lots[c]["zone"] and int(copy.lots[c]["level"]) == int(town.lots[c]["level"]), "lot %s survives" % c)
	var junk = _town()
	junk.paint_zone(Vector2i(0, 9), "civic")
	check(not junk.from_dict({"version": 99}), "a future save is refused")
	check(not junk.from_dict({"version": 1, "zones": {"x,y": "housing"}}), "bad cell keys are refused")
	check(not junk.from_dict({"version": 1, "zones": {"1,1": "palace"}}), "unknown zones are refused")
	check(not junk.from_dict({"version": 1, "lots": {"1,1": {"zone": "housing", "level": NAN}}}), "non-finite lot numbers are refused")
	check(junk.zones.size() == 1, "a refused save leaves the town as it was")


func _scene_checks() -> void:
	root.size = Vector2i(1280, 800)   # headless windows are tiny; the HUD lays out for a real one
	var scene: PackedScene = load("res://scenes/game.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.has_method("town_set_tool"), "the game scene has the town layer")
	if not game.has_method("town_set_tool"):
		game.queue_free()
		return
	check(game.town != null, "the town model exists")
	var buildings_before: int = game.sim.buildings.size()
	var village_revision: int = game.sim.revision
	game._enter_village()
	game.sim.resources["wood"] = 500
	game.town_open()
	check(game.town_active(), "the town tools open")
	check(game.town_bar.visible, "the zoning bar shows")
	# Lay a road from the south edge and paint homes and farms beside it.
	game.town_set_tool("road")
	var wood_before: float = float(game.sim.resources["wood"])
	for step in 4:
		game.town_paint_cell(Vector2i(0, 9 + step))
	check(game.town.roads.size() == 4, "roads are laid through the scene")
	check(float(game.sim.resources["wood"]) < wood_before, "roads cost Wood")
	game.town_set_tool("housing")
	for step in 4:
		game.town_paint_cell(Vector2i(-1, 9 + step))
	game.town_set_tool("farming")
	for step in 4:
		game.town_paint_cell(Vector2i(1, 9 + step))
	check(game.town.zones.size() == 8, "zones are painted through the scene")
	game.town_set_tool("housing")
	game.town_paint_cell(Vector2i(0, 0))
	check(not game.town.zones.has(Vector2i(0, 0)), "the village cannot be zoned from the scene")
	game.sim.paused = false
	game.paused = false
	game.focused = true
	for step in 120:
		game._town_advance(0.5)
	game._town_sync()
	check(not game.town.lots.is_empty(), "lots grow in the scene")
	check(game.town_lot_views() > 0, "grown lots have views")
	check(game.town_road_mesh_ok(), "roads draw")
	check(game.town_overlay_ok(), "zone colours draw")
	# Income banks through the village's storage.
	game.town.income_clock = float(game.town.specs["incomeSeconds"]) - 0.1
	game._town_advance(0.5)
	for resource: String in ["gold", "food", "wood", "stone"]:
		check(float(game.sim.resources.get(resource, 0.0)) <= game.sim.storage_cap(resource) + 0.01, "town income respects %s storage" % resource)
	# The info card opens for a lot.
	var lot_cell: Vector2i = game.town.lots.keys()[0]
	game.town_inspect(lot_cell)
	check(game.panel == "town_lot", "tapping a lot opens its card")
	game.town_close()
	check(not game.town_active(), "the town tools close")
	check(game.sim.buildings.size() == buildings_before and game.sim.revision == village_revision, "the village's own buildings are untouched")
	game.queue_free()
	await process_frame
