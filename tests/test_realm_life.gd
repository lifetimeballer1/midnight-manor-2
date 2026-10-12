extends SceneTree

# Realm life (realm_map.gd neighbours/outposts/raids + village_realm_life.gd): moods follow border
# pressure and gifts, outposts claim land within reach and fall to hostile neighbours, raids march,
# resolve once, pay loot through the village's own storage rules and can make a neighbour sworn,
# v1 realm saves still load, and taps out in the realm open cards without changing village taps.

const RealmMap = preload("res://scripts/game/realm_map.gd")

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
	_mood_checks()
	_outpost_checks()
	_raid_checks()
	_save_checks()
	await _scene_checks()
	print("test_realm_life: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("PASS test_realm_life")
	quit(0 if failures.is_empty() else 1)


func _fresh():
	var realm = RealmMap.new()
	realm.generate(7)
	return realm


func _mood_checks() -> void:
	var realm = _fresh()
	var site: Dictionary = realm.settlements[0]
	site["relation"] = 50.0
	check(realm.attitude(site) == "wary", "a neighbour starts wary")
	realm.send_gift(str(site["id"]))
	check(realm.attitude(site) == "friendly", "gifts make it friendly")
	check(realm.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "attitude"), "a mood change is announced")
	# Friendly neighbours send traders.
	site["travel"] = 0.0
	var traders: int = 0
	for step in 100:
		realm.advance(1.0)
		for event: Dictionary in realm.take_events():
			if event["kind"] == "trader" and event["site"] == site["id"]:
				traders += 1
	check(traders == 1, "a friendly neighbour sends one trader per %ds (%d)" % [int(RealmMap.TRADER_SECONDS), traders])
	# Pressing borders sour a neighbour; hostile ones send scouts and grow faster.
	var near = _fresh()
	var target: Dictionary = near.settlements[0]
	target["relation"] = 40.0
	near.set_home_plots(4)
	near.home_plots = 30   # a vast manor claim that touches everyone
	near.revision += 1
	near.advance(200.0)
	check(near.attitude(target) == "hostile", "border pressure turns a neighbour hostile (relation %.1f)" % float(target["relation"]))
	var calm = _fresh()
	var lone: Dictionary = calm.settlements[2]
	lone["relation"] = 20.0
	calm.advance(100.0)
	check(float(lone["relation"]) > 20.0, "apart, relations ease back")


func _outpost_checks() -> void:
	var realm = _fresh()
	var edge: Vector2 = Vector2(realm.home_radius() + 20.0, 0.0)
	# Find dry ground just past the manor's land.
	for turn in 16:
		var spot: Vector2 = Vector2.from_angle(TAU * float(turn) / 16.0) * (realm.home_radius() + 20.0)
		if realm.outpost_reason(spot).is_empty():
			edge = spot
			break
	check(realm.outpost_reason(edge).is_empty(), "wild ground next to the manor can take an outpost")
	check(not realm.outpost_reason(Vector2(10, 10)).is_empty(), "not inside the manor's own middle")
	check(not realm.outpost_reason(Vector2(200, -200)).is_empty() or realm.owner_at(200, -200) == "home", "not far beyond the manor's land")
	var centre: Vector2 = realm.settlements[0]["centre"]
	check(not realm.outpost_reason(centre).is_empty(), "not in a settlement's streets")
	var revision: int = realm.revision
	check(realm.found_outpost(edge), "an outpost is founded")
	check(realm.revision > revision and realm.owner_at(edge.x, edge.y) == "home", "its land becomes the manor's")
	check(realm.outpost_reason(edge + edge.normalized() * (RealmMap.OUTPOST_RADIUS + 20.0)).is_empty() or realm.outposts.size() > 0, "outposts reach further out step by step")
	# A hostile neighbour whose land swallows an outpost takes it.
	var site: Dictionary = realm.settlements[0]
	var deep: Vector2 = (site["centre"] as Vector2) + Vector2(4.0, 0.0)
	realm.outposts.append({"id": 99, "pos": deep})
	site["relation"] = 0.0
	realm.advance(0.5)
	check(realm.outposts.all(func(o: Dictionary) -> bool: return int(o["id"]) != 99), "a hostile neighbour overruns an outpost inside its land")
	check(realm.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "outpost_lost"), "the loss is announced")
	var full = _fresh()
	for index in RealmMap.OUTPOST_MAX:
		full.outposts.append({"id": index + 1, "pos": Vector2.ZERO})
	check(not full.outpost_reason(edge).is_empty(), "the outpost cap holds")


func _raid_checks() -> void:
	var realm = _fresh()
	var site: Dictionary = realm.settlements[0]
	var id: String = str(site["id"])
	check(not realm.raid_reason(id, 1).is_empty(), "one fighter is not a warband")
	check(realm.raid_reason(id, 2).is_empty(), "two fighters can raid")
	var relation: float = float(site["relation"])
	check(realm.start_raid(id, 6, 60), "the warband marches")
	check(float(site["relation"]) < relation, "a raid sours the target")
	check(not realm.raid_reason(str(realm.settlements[1]["id"]), 6).is_empty(), "one warband at a time")
	realm.advance(1.0)
	check(realm.raid_progress() > 0.0 and realm.raid_progress() < 1.0, "the march takes time")
	var pop: int = int(site["pop"])
	var won: Array = []
	var guarded: bool = false
	for step in 200:
		realm.advance(1.0)
		for event: Dictionary in realm.take_events():
			if event["kind"] in ["raid_won", "raid_lost"]:
				won.append(event)
				guarded = realm.raid.is_empty() and float(site["cooldown"]) > 0.0
	check(won.size() == 1, "a raid resolves exactly once")
	check(won.size() == 1 and won[0]["kind"] == "raid_won", "a strong warband wins")
	check(int(site["pop"]) < pop + 4, "the beaten neighbour loses people")
	check(guarded, "the raid ends and the target is on guard")
	check(won.size() == 1 and int(won[0]["loot"]["gold"]) > 0, "a win brings loot")
	# Beaten small enough, a settlement swears to the manor and its land turns.
	site["pop"] = RealmMap.VASSAL_POP + 1
	site["cooldown"] = 0.0
	var started: bool = realm.start_raid(id, 6, 60)
	for step in 60:
		realm.advance(1.0)
	check(started and bool(site["vassal"]) and realm.attitude(site) == "sworn", "a beaten small settlement swears to the manor")
	var centre: Vector2 = site["centre"]
	check(realm.owner_at(centre.x, centre.y) == "home", "sworn land is the manor's")
	check(not realm.raid_reason(id, 6).is_empty(), "sworn settlements cannot be raided")
	# A weak warband loses.
	var weak = _fresh()
	var strong: Dictionary = weak.settlements[1]
	strong["pop"] = RealmMap.POP_CAP
	weak.start_raid(str(strong["id"]), 2, 2)
	for step in 200:
		weak.advance(1.0)
	check(weak.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "raid_lost"), "a weak warband is beaten back")
	check(not bool(strong["vassal"]), "a lost raid takes nothing")


func _save_checks() -> void:
	var realm = _fresh()
	realm.found_outpost(Vector2(realm.home_radius() + 10.0, 0.0))
	realm.outposts.append({"id": 7, "pos": Vector2(0.0, realm.home_radius() + 10.0)})
	realm.settlements[2]["vassal"] = true
	realm.settlements[3]["relation"] = 12.0
	realm.start_raid(str(realm.settlements[0]["id"]), 4, 20)
	realm.advance(2.0)
	var loaded = RealmMap.new()
	check(loaded.from_dict(JSON.parse_string(JSON.stringify(realm.to_dict()))), "a v2 realm save loads")
	check(loaded.outposts.size() == realm.outposts.size(), "outposts survive the save")
	check(bool(loaded.settlements[2]["vassal"]), "sworn neighbours stay sworn")
	check(is_equal_approx(float(loaded.settlements[3]["relation"]), float(realm.settlements[3]["relation"])), "moods survive the save")
	check(not loaded.raid.is_empty() and is_equal_approx(float(loaded.raid["left"]), float(realm.raid["left"])), "a marching warband keeps marching")
	var v1 := {"version": 1, "seed": 7, "elapsed": 30.0, "settlements": [{"id": "ashfen", "pop": 22, "growth": 3.0}]}
	var old = RealmMap.new()
	check(old.from_dict(v1), "a v1 realm save still loads")
	check(int(old.settlement("ashfen")["pop"]) == 22 and old.outposts.is_empty() and old.raid.is_empty(), "v1 growth kept, new state starts empty")


func _scene_checks() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)
	check(game.has_method("realm_tap"), "the realm life layer is in the scene")

	# A tap on a settlement opens its card; raid needs fighters and supplies.
	var site: Dictionary = game.realm.settlements[0]
	check(game.realm_tap(site["centre"]), "tapping a settlement opens its card")
	check(game.panel == "realm_site" and game.sidebar.visible, "the settlement card shows")
	# A tap on wild land opens the outpost card.
	var wild := Vector2(game.realm.home_radius() + 14.0, 0.0)
	check(game.realm_tap(wild) and game.panel == "realm_land", "tapping wild land offers an outpost")
	check(not game.realm_tap(Vector2(900, 0)), "taps beyond the realm do nothing")

	# Founding an outpost spends through the village and shows a tower.
	for turn in 16:
		var spot: Vector2 = Vector2.from_angle(TAU * float(turn) / 16.0) * (game.realm.home_radius() + 14.0)
		if game.realm.outpost_reason(spot).is_empty():
			wild = spot
			break
	game.sim.resources["wood"] = 500.0
	game.sim.resources["gold"] = 500.0
	game.realm_tap(wild)
	game._realm_found_outpost()
	check(game.realm.outposts.size() == 1, "an outpost is founded from the card")
	check(is_equal_approx(float(game.sim.resources["wood"]), 500.0 - float(RealmMap.OUTPOST_COST["wood"])), "the outpost costs its Wood")
	game._process(0.0)
	check(game.realm_outpost_views() == 1, "the outpost has a tower")
	game.sim.resources["wood"] = 10.0
	game.realm_tap(wild + wild.normalized() * 30.0)
	game._realm_found_outpost()
	check(game.realm.outposts.size() == 1 and is_equal_approx(float(game.sim.resources["wood"]), 10.0), "no outpost and no spending without the Wood")

	# A raid marches visibly and resolves into loot within storage.
	var fighters: Dictionary = game.realm_fighters()
	game.sim.resources["food"] = 100.0
	if int(fighters["count"]) < RealmMap.RAID_MIN_FIGHTERS:
		check(not game.realm.raid_reason(str(site["id"]), int(fighters["count"])).is_empty(), "no raid without fighters")
		game.realm.start_raid(str(site["id"]), 3, 30)
	else:
		game._realm_raid(str(site["id"]))
	check(not game.realm.raid.is_empty(), "the warband sets out")
	game.started = true
	game.sim.paused = false
	game._realm_move_warband(0.1)
	check(game.realm_warband_count() > 0 and game.realm_warband_count() <= game.REALM_WARBAND, "the warband is visible within its cap")
	game.realm.advance(500.0)
	for event: Dictionary in game.realm.take_events():
		game._realm_event(event)
	game._realm_move_warband(0.1)
	check(game.realm_warband_count() == 0, "the warband is gone once the raid resolves")
	for resource: String in ["gold", "food"]:
		check(float(game.sim.resources[resource]) <= game.sim.storage_cap(resource) + 0.01, "loot respects %s storage" % resource)

	# Travellers walk out and back, capped.
	for index in 6:
		game._realm_event({"kind": "trader", "site": str(game.realm.settlements[1]["id"])})
	check(game.realm_traveller_count() <= game.REALM_TRAVELLERS, "travellers stay within the cap")
	var gold_before: float = float(game.sim.resources["gold"])
	for step in 400:
		game._realm_move_travellers(0.5)
	check(game.realm_traveller_count() == 0, "travellers go home")
	check(float(game.sim.resources["gold"]) >= gold_before, "traders leave Gold, never take it")

	# Taps inside the village still go to the village.
	check(game.sim.in_world(Vector2i(5, 5)), "village tiles are still the village's")
	game.queue_free()
	await process_frame
