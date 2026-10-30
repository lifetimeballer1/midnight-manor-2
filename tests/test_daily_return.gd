extends SceneTree

# Daily return (The Manor Endures, C3): one omen and one contract per calendar day, a chest that
# grows with the streak, a streak that resets after a missed day, omen effects on output and threat,
# and the state saved with the village.
const Sim = preload("res://scripts/game/village_sim.gd")
const Daily = preload("res://scripts/game/village_daily.gd")
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
	test_days_and_streak()
	test_contract_and_chest()
	test_omens()
	test_saved()
	await test_card()
	print("DAILY_RETURN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	return sim


func test_days_and_streak() -> void:
	check(Daily.day_number(86400.0 * 20000.0 + 10.0, 0) == 20000, "day numbers count calendar days")
	check(Daily.day_number(86400.0 * 20000.0 - 3600.0, 120) == 20000, "the local time zone moves the day")
	var sim = fresh()
	sim.daily.visit(sim, 20000)
	check(sim.daily.just_turned and sim.daily.streak == 1, "the first visit starts a streak of 1")
	var omen: String = sim.daily.omen
	var contract: Dictionary = sim.daily.contract.duplicate()
	sim.daily.visit(sim, 20000)
	check(not sim.daily.just_turned and sim.daily.omen == omen and sim.daily.contract == contract, "a second visit the same day changes nothing")
	sim.daily.visit(sim, 20001)
	check(sim.daily.streak == 2, "the next day adds to the streak")
	sim.daily.visit(sim, 20004)
	check(sim.daily.streak == 1, "a missed day starts the streak again")
	var other = fresh()
	other.daily.visit(other, 20004)
	check(other.daily.omen == sim.daily.omen, "the same day draws the same omen in any village")
	var seen: Dictionary = {}
	for d in 40:
		other.daily.visit(other, 21000 + d)
		seen[other.daily.omen] = true
	check(seen.size() == Daily.OMENS.size(), "every omen turns up over a month or so (%d)" % seen.size())


func test_contract_and_chest() -> void:
	var sim = fresh()
	sim.daily.visit(sim, 20000)
	var resource: String = str(sim.daily.contract["resource"])
	var target: float = float(sim.daily.contract["target"])
	check(target >= Daily.CONTRACT_MIN, "the contract asks for a real amount (%d %s)" % [target, resource])
	check(not sim.daily.is_ready(sim) and sim.daily.claim(sim).is_empty(), "the chest stays shut until the contract is done")
	sim.gathered[resource] = float(sim.gathered.get(resource, 0.0)) + target
	check(sim.daily.is_ready(sim), "gathering the amount finishes the contract")
	for r: String in ["wood", "food", "gold"]:
		sim.resources[r] = 0.0
	var prize: Dictionary = sim.daily.chest(sim)
	check(not prize.has(resource) and prize.size() == 2, "the chest pays the other two resources")
	var banked: Dictionary = sim.daily.claim(sim)
	check(not banked.is_empty(), "the chest opens into the stores")
	check(sim.daily.claim(sim).is_empty(), "a chest opens once a day")
	var later = fresh()
	later.daily.visit(later, 20000)
	var first: float = float(later.daily.chest(later).values()[0])
	for d in range(1, 9):
		later.daily.visit(later, 20000 + d)
	later.daily.contract["target"] = float(later.daily.contract["target"])
	var day_one = fresh()
	day_one.daily.visit(day_one, 20008)
	day_one.daily.contract = later.daily.contract.duplicate()
	var plain: float = float(day_one.daily.chest(day_one).values()[0])
	var grown: float = float(later.daily.chest(later).values()[0])
	check(absf(grown - plain * (1.0 + Daily.STREAK_STEP * (Daily.STREAK_CAP - 1))) < 1.01, "a long streak grows the chest to its cap (%.0f vs %.0f)" % [grown, plain])
	check(first > 0.0, "a first-day chest is worth something")


func test_omens() -> void:
	var sim = fresh()
	var farm: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if str(b["type"]) == "farm":
			farm = b
	var plain: float = sim.production_rate(farm)
	sim.daily.omen = "full-larder"
	check(absf(sim.production_rate(farm) - plain * Daily.OMEN_BONUS) < 0.0001, "Full Larder raises food output")
	sim.daily.omen = "fair-winds"
	check(absf(sim.production_rate(farm) - plain) < 0.0001, "another resource's omen leaves food alone")
	sim.daily.omen = "quiet-roads"
	sim.raid_active = true
	sim.enemies.clear()
	sim._finish_raid(true)
	check(is_equal_approx(sim.raid_span, 240.0 * Daily.QUIET_ROADS), "Quiet Roads slows the threat meter (%.0f)" % sim.raid_span)


func test_saved() -> void:
	var sim = fresh()
	sim.daily.visit(sim, 20000)
	sim.daily.visit(sim, 20001)
	var copy = Sim.new()
	check(copy.restore_state(JSON.parse_string(JSON.stringify(sim.export_state()))), "a village with a daily saves and loads")
	check(copy.daily.day == 20001 and copy.daily.streak == 2 and copy.daily.omen == sim.daily.omen, "day, streak and omen survive a reload")
	check(is_equal_approx(float(copy.daily.contract["target"]), float(sim.daily.contract["target"])), "the contract survives a reload")
	var old: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	old.erase("daily")
	var older = Sim.new()
	check(older.restore_state(old) and older.daily.day == -1, "a save from before dailies starts fresh")


func test_card() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	check(game.sim.daily.day >= 0, "entering the village draws today's omen")
	game._open_panel("daily")
	for i in 3:
		await process_frame
	var joined: String = ""
	for node: Node in game.sidebar.find_children("*", "", true, false):
		if node is Label or node is Button:
			joined += str(node.text) + " | "
	check(joined.contains("Omen:") and joined.contains("Daily contract") and joined.contains("Streak: 1 day"), "the Daily card shows omen, contract and streak")
	var resource: String = str(game.sim.daily.contract["resource"])
	game.sim.gathered[resource] = float(game.sim.gathered.get(resource, 0.0)) + float(game.sim.daily.contract["target"])
	game._claim_daily()
	check(bool(game.sim.daily.contract["claimed"]), "the card's button opens the chest")
	game.queue_free()
	await process_frame
