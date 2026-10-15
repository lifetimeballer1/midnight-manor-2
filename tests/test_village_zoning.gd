extends SceneTree

# Zoning inside the village (village_growth.gd + village_zoning.gd): village ground takes zones from
# the first day; homes, farms, industry and civic buildings rise there free and grow a tier on their
# own; the Manor Hall grows with the village's people; the Build menu keeps only what is bought
# (defences, troops, Great Works); a Raise button for a zoned building opens its zone instead; reaches
# the manor does not hold refuse zones; and village zones round-trip in the town save.

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
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://town-v1.json"))
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	await process_frame
	var growth = game.growth
	var sim = game.sim
	var town = game.town
	check(growth != null, "the village has a growth layer")
	check(growth.grows("farm") and growth.grows("cottage") and growth.grows("lumber") and growth.grows("mine"), "economy and homes grow from zones")
	for bought: String in ["wall", "tower", "archer_tower", "trap", "gate", "barracks", "stonewall"]:
		check(not growth.grows(bought), "%s is still bought" % bought)
	for zone: String in ["housing", "farming", "industrial", "civic"]:
		for type_name: String in growth.zone_types(zone):
			check(sim.building_specs.has(type_name), "zoned type %s exists" % type_name)
	check(growth.cell_tiles(Vector2i(-5, -4))[0] == Vector2i(0, 0), "town cell (-5,-4) starts at village tile (0,0)")
	check(growth.tile_cell(Vector2i(19, 15)) == Vector2i(4, 3), "village tiles map back to their cell")

	# Build menu: defences only (plus Roads and Great Works), with a pointer to zoning.
	game._open_panel("build")
	check(not game.build_cards.has("farm") and not game.build_cards.has("cottage") and not game.build_cards.has("lumber"), "no economy or home cards to buy")
	check(game.build_cards.has("tower") and game.build_cards.has("wall") and game.build_cards.has("barracks"), "defence cards stay")
	check(game.build_category_order == ["Defense", "Roads"], "only Defense and Roads remain (%s)" % [game.build_category_order])
	game._close_panel()

	# A Raise button for a farm opens the Farms zone, and the farm rises first there.
	game._choose_build("farm")
	check(game.town_active() and game._town_tool == "farming" and "farm" in growth.wishes, "Raise a Farm opens the Farms zone")
	check(game.build_type.is_empty(), "no hand placement for a zoned building")
	game.town_close()
	game._choose_build("tower")
	check(game.build_type == "tower", "towers are still placed by hand")
	game._cancel_placement()

	# Zone two open cells of village ground as farms: a farm rises there, free.
	var open: Array[Vector2i] = []
	var taken: Dictionary = game._village_taken()
	for cy in range(-4, 4):
		for cx in range(-5, 5):
			var c := Vector2i(cx, cy)
			if not taken.has(c) and growth.cell_reason(sim, c).is_empty():
				open.append(c)
	check(open.size() >= 4, "open village ground to zone (%d cells)" % open.size())
	var wood: float = float(sim.resources["wood"])
	var count: int = sim.buildings.size()
	game.town_open()
	game.town_set_tool("farming")
	game._town_stroke_denied = false
	check(game.town_paint_cell(open[0]), "village ground takes a Farms zone")
	check(str(town.village.get(open[0], "")) == "farming", "the zone is kept in the town model")
	check(not town.zones.has(open[0]), "village zones are not town zones")
	var rose: Dictionary = growth.grow_one(sim, town)
	check(not rose.is_empty() and str(rose.get("type", "")) == "farm", "a farm rises on the zone (%s)" % [rose])
	check(sim.buildings.size() == count + 1 and float(sim.resources["wood"]) == wood, "it cost nothing")
	if not rose.is_empty():
		var b: Dictionary = sim.get_building(int(rose["id"]))
		check(growth.tile_cell(Vector2i(int(b["x"]), int(b["y"]))) == open[0], "it stands on the zoned cell")
		check(float(b["remaining"]) > 0.0, "it goes up as a construction")
	check(growth.wishes.is_empty(), "the wished-for farm is no longer waiting")
	check(growth.grow_one(sim, town).is_empty(), "nothing more fits on a full zone")

	# A reach the manor does not hold refuses zones.
	var reach := Vector2i(0, -6)
	check(not growth.cell_reason(sim, reach).is_empty(), "the north reach is not the manor's yet")
	game._town_stroke_denied = false
	check(not game.town_paint_cell(reach), "unheld reach cannot be zoned")

	# Homes when beds run short; nothing during a raid.
	game.town_set_tool("housing")
	game.town_paint_cell(open[1])
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
	sim.raid_warning = true
	check(growth.grow_one(sim, town).is_empty(), "nothing rises during a raid")
	sim.raid_warning = false
	rose = growth.grow_one(sim, town)
	check(str(rose.get("type", "")) == "cottage", "a cottage rises on the homes zone (%s)" % [rose])

	# Upgrades come on their own, free, as the village levels up.
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
	var farm: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if str(b["type"]) == "farm":
			farm = b
	sim.xp = 0
	check(growth.upgrade_one(sim).is_empty(), "no free upgrade before the village level allows it")
	sim.xp = 100000
	var before: Dictionary = sim.resources.duplicate()
	var tiers: Dictionary = {}
	for b: Dictionary in sim.buildings:
		tiers[int(b["id"])] = int(b["tier"])
	var up: Dictionary = growth.upgrade_one(sim)
	check(not up.is_empty() and growth.grows(str(up["type"])), "a zoned building grows a tier (%s)" % [up])
	check(sim.resources == before, "the upgrade cost nothing")
	if not up.is_empty():
		check(int(sim.get_building(int(up["id"]))["tier"]) == tiers[int(up["id"])] + 1, "its tier went up by one")
	check(growth.upgrade_one(sim).is_empty(), "one upgrade at a time")

	# The Manor Hall grows with the village's people.
	var hall: Dictionary = sim._hall()
	var hall_tier: int = int(hall["tier"])
	check(growth.hall_one(sim).is_empty(), "the Hall waits for more villagers")
	while sim.units.size() < growth.hall_people_next(sim):
		sim._add_unit("farmer")
	var grew: Dictionary = growth.hall_one(sim)
	check(not grew.is_empty() and int(hall["tier"]) == hall_tier + 1, "the Hall rises a tier on its own (%s)" % [grew])
	check(sim.resources == before, "the Hall upgrade cost nothing")

	# The inspector offers no paid upgrade for a zoned building.
	if not farm.is_empty():
		game.town_close()
		farm["remaining"] = 0.0
		game.selected_building = int(farm["id"])
		game._open_panel("building")
		game._refresh_inspector()
		check(game.inspect_upgrade.disabled, "a zoned building has no paid upgrade")
		var tier: int = int(farm["tier"])
		game._upgrade_selected()
		check(int(farm["tier"]) == tier, "the Upgrade action does not buy one")
		game._close_panel()

	# Clear removes the zone (not the building), and the save round-trips village zones.
	var saved: Dictionary = town.to_dict()
	check(saved.has("village") and (saved["village"] as Dictionary).size() == 2, "village zones are saved")
	var copy = load("res://scripts/game/town_zoning.gd").new()
	copy.realm = town.realm
	check(copy.from_dict(JSON.parse_string(JSON.stringify(saved))) and copy.village.size() == 2, "village zones load back")
	var junk: Dictionary = saved.duplicate(true)
	junk["village"] = {"0,0": "volcano"}
	check(not copy.from_dict(junk), "an unknown village zone is refused")
	var older: Dictionary = saved.duplicate(true)
	older.erase("village")
	check(copy.from_dict(older) and copy.village.is_empty(), "older saves without village zones load")
	count = sim.buildings.size()
	game.town_open()
	game.town_set_tool("erase")
	game.town_paint_cell(open[0])
	check(not town.village.has(open[0]) and sim.buildings.size() == count, "Clear removes the zone and leaves the building")
	game.town_close()

	# The view draws village zones without errors.
	game.town_open()
	game.town_set_tool("housing")
	game._town_sync()
	check(game.town_overlay_ok(), "zone overlay draws with village zones")
	game.town_close()

	_ways_in_and_out(game)

	print("test_village_zoning: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("PASS test_village_zoning")
	quit(0 if failures.is_empty() else 1)


# Packed zones keep their ways in and out: every open village cell zoned, everything that fits grown,
# then nobody is walled in, work stands stay open, paths lead to each new building and out of the
# village, paved road is never built over, and the workers really reach their work.
func _ways_in_and_out(game) -> void:
	var growth = game.growth
	var sim = game.sim
	var town = game.town
	game.paused = true
	sim.xp = 100000
	for resource: String in sim.resources:
		sim.resources[resource] = 99999.0
	sim.next_raid_at = 1.0e9
	var taken: Dictionary = game._village_taken()
	var open: Array[Vector2i] = []
	for cy in range(-4, 4):
		for cx in range(-5, 5):
			var c := Vector2i(cx, cy)
			if not taken.has(c) and growth.cell_reason(sim, c).is_empty():
				open.append(c)
	# A stretch of paved road through the middle of the zones.
	var road: Vector2i = growth.cell_tiles(open[open.size() / 2])[0]
	sim.living.cells[sim.living.key(road)] = {"wear": 1.0, "last": sim.elapsed, "stone": true}
	game.town_open()
	for c: Vector2i in open:
		game.town_set_tool("housing" if c.x <= -3 else ("farming" if c.x <= 1 else "industrial"))
		game.town_paint_cell(c)
	game.town_close()
	var start: int = sim.buildings.size()
	var worst: int = 0
	for i in 120:
		for b: Dictionary in sim.buildings:
			b["remaining"] = 0.0
		var before: int = Time.get_ticks_msec()
		var rose: Dictionary = growth.grow_one(sim, town)
		worst = maxi(worst, Time.get_ticks_msec() - before)
		if rose.is_empty():
			break
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
	sim.revision += 1
	print("ways in and out: %d buildings grew, slowest step %d ms" % [sim.buildings.size() - start, worst])
	check(sim.buildings.size() - start >= 10, "packed zones still fill up (%d grew)" % [sim.buildings.size() - start])
	check(growth.cut_off(sim).is_empty(), "no zoned building is walled in (%s)" % [growth.cut_off(sim)])
	check(sim.building_at(road.x, road.y).is_empty(), "nothing rises on a paved road")

	# Work stands: inside the village, each grown workplace's stands are open and reached, and every
	# grown building has a path at its door.
	var walk: Dictionary = growth._walk(sim)
	var blocked_stands: Array[String] = []
	var pathless: Array[String] = []
	for b: Dictionary in sim.buildings.slice(start):
		for point: Vector2 in sim.stand_candidates(b):
			var tile := Vector2i(floori(point.x), floori(point.y))
			if sim.in_world(tile) and walk["reached"][growth._index(walk, tile)] == 0:
				blocked_stands.append("%s@%d,%d" % [b["type"], tile.x, tile.y])
		var door: bool = false
		for tile: Vector2i in growth._ring(Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"]))):
			if growth._on_path(sim, tile):
				door = true
		if not door:
			pathless.append(str(b["type"]))
	check(blocked_stands.is_empty(), "grown workplaces keep their work stands open (%s)" % [blocked_stands])
	check(pathless.is_empty(), "a path reaches every building that grew (%s)" % [pathless])
	check(growth.lay_way_out(sim) == 0, "a path already leads from the hall out of the village")

	# The workers really get to work: one of each trade per grown workplace, then let the day run.
	var crew: Dictionary = {}
	for b: Dictionary in sim.buildings.slice(start):
		var trade: String = str(sim.building_specs[b["type"]].get("workplace", ""))
		if trade.is_empty() or sim.stand_candidates(b).is_empty() or not sim.troop_specs.has(trade):
			continue
		sim._add_unit(trade)
		var u: Dictionary = sim.units[sim.units.size() - 1]
		if sim.assign(int(u["id"]), int(b["id"])):
			crew[int(u["id"])] = str(b["type"])
	var worked: Dictionary = {}
	sim.paused = false
	for step in 900:
		sim.next_raid_at = 1.0e9
		sim.tick(0.1)
		for u: Dictionary in sim.units:
			if crew.has(int(u["id"])) and str(u["phase"]) == "work":
				worked[int(u["id"])] = true
	var idle: Array[String] = []
	for id: int in crew:
		if not worked.has(id):
			idle.append(str(crew[id]))
	print("ways in and out: %d workers posted, %d reached work" % [crew.size(), worked.size()])
	check(crew.size() >= 5, "workers were posted to grown workplaces (%d)" % crew.size())
	check(idle.is_empty(), "every worker reaches a grown workplace (%d of %d; stuck at %s)" % [crew.size() - idle.size(), crew.size(), idle])

	# A hand-built wall that closes a zoned building in is called out once.
	var target: Dictionary = sim.buildings[sim.buildings.size() - 1]
	var walled: int = 0
	for tile: Vector2i in growth._ring(Rect2i(int(target["x"]), int(target["y"]), int(target["size"]), int(target["size"]))):
		if sim.in_world(tile) and sim.building_at(tile.x, tile.y).is_empty():
			sim.buildings.append(sim._new_building("wall", tile.x, tile.y, false))
			walled += 1
	sim.revision += 1
	sim._invalidate()
	sim.notice = ""
	growth._warn_cut_off(sim)
	check(int(target["id"]) in growth.cut_off(sim) and "walled in" in sim.notice, "a walled-in zoned building is called out (%s)" % sim.notice)
	sim.notice = ""
	growth._warn_cut_off(sim)
	check(sim.notice.is_empty(), "and only once")
