extends SceneTree

# Stewards (The Manor Endures, B3): earned, never bought; once earned they stay earned; each can rest.
# The Reeve collects half-full workplaces, the Master Mason mends damage (defences too) at the repair
# price, the Warden sounds the Horn once the village is ready.
const Sim = preload("res://scripts/game/village_sim.gd")
const Threat = preload("res://scripts/game/village_threat.gd")
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
	test_earning()
	test_reeve()
	test_mason()
	test_warden()
	test_saved()
	await test_card()
	print("STEWARDS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.paused = false
	sim.next_raid_at = 1.0e9
	sim.completed_quests.append("the-first-horn")
	sim.elapsed = 1000.0
	return sim


func first(sim, type_name: String) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if str(b["type"]) == type_name:
			return b
	return {}


func hall_tier(sim, tier: int) -> void:
	var hall: Dictionary = sim._hall()
	hall["tier"] = tier
	hall["max_hp"] = float(sim.building_specs["hall"]["tiers"][tier - 1]["hp"])
	hall["hp"] = float(hall["max_hp"])


func pass_time(sim) -> void:
	sim.stewards.tick(sim, Sim.Stewards.INTERVAL + 0.01)


func test_earning() -> void:
	var sim = fresh()
	pass_time(sim)
	check(sim.stewards.earned.is_empty(), "a new village has no stewards")
	hall_tier(sim, 2)
	pass_time(sim)
	check(sim.stewards.has("reeve") and not sim.stewards.has("mason"), "Hall tier 2 earns the Reeve only")
	sim.zone_boost = {"farm": 2.0}
	pass_time(sim)
	check(sim.stewards.has("mason") and not sim.stewards.has("warden"), "a zone milestone earns the Master Mason")
	hall_tier(sim, 3)
	pass_time(sim)
	check(sim.stewards.has("warden"), "Hall tier 3 earns the Warden")
	hall_tier(sim, 1)
	sim.zone_boost = {}
	pass_time(sim)
	check(sim.stewards.earned.size() == 3, "earned stewards stay earned")
	check(sim.stewards.toggle("reeve") and not sim.stewards.working("reeve"), "a steward can be told to rest")
	check(sim.stewards.toggle("reeve") and sim.stewards.working("reeve"), "and sent back to work")
	var plain = fresh()
	check(not plain.stewards.toggle("reeve"), "an unearned steward cannot be switched")


func test_reeve() -> void:
	var sim = fresh()
	sim.stewards.earned["reeve"] = true
	var farm: Dictionary = first(sim, "farm")
	var lumber: Dictionary = first(sim, "lumber")
	farm["reserve"] = sim.reserve_cap(farm) * 0.6
	lumber["reserve"] = sim.reserve_cap(lumber) * 0.2
	var food: float = float(sim.resources["food"])
	sim.notice = "keep me"
	pass_time(sim)
	check(float(farm["reserve"]) < 1.0 and float(sim.resources["food"]) > food, "the Reeve collects a half-full farm")
	check(float(lumber["reserve"]) > 1.0, "the Reeve leaves a nearly empty workplace be")
	check(sim.notice == "keep me", "the Reeve works quietly")
	sim.stewards.off["reeve"] = true
	farm["reserve"] = sim.reserve_cap(farm)
	pass_time(sim)
	check(float(farm["reserve"]) > 1.0, "a resting Reeve collects nothing")


func test_mason() -> void:
	var sim = fresh()
	sim.stewards.earned["mason"] = true
	var tower: Dictionary = first(sim, "tower")
	check(not tower.is_empty(), "the starting village has a tower")
	tower["hp"] = float(tower["max_hp"]) * 0.5
	sim.resources["wood"] = 1000.0
	sim.resources["stone"] = 1000.0
	var wood: float = float(sim.resources["wood"])
	var before: float = float(tower["hp"])
	pass_time(sim)
	check(float(tower["hp"]) > before, "the Master Mason mends a damaged tower")
	check(float(sim.resources["wood"]) < wood, "mending is paid from the stores")
	tower["hp"] = 0.0
	for i in 40:
		pass_time(sim)
	check(float(tower["hp"]) > 0.0, "the Master Mason raises a ruined tower")
	var hall: Dictionary = sim._hall()
	hall["hp"] = 0.0
	tower["hp"] = float(tower["max_hp"])
	var hall_wood: float = float(sim.resources["wood"])
	pass_time(sim)
	check(float(hall["hp"]) <= 0.0, "a ruined Hall is the builders' to raise, not the Mason's")
	sim.resources["wood"] = 0.0
	sim.resources["stone"] = 0.0
	hall["hp"] = float(hall["max_hp"]) * 0.5
	pass_time(sim)
	check(is_equal_approx(float(hall["hp"]), float(hall["max_hp"]) * 0.5), "empty stores pay for nothing")
	sim.resources["wood"] = 1000.0
	sim.raid_warning = true
	pass_time(sim)
	check(is_equal_approx(float(hall["hp"]), float(hall["max_hp"]) * 0.5), "no mending while the horns sound")


func test_warden() -> void:
	var sim = fresh()
	sim.stewards.earned["warden"] = true
	sim.raid_span = 240.0
	sim.next_raid_at = sim.elapsed + 200.0
	pass_time(sim)
	check(not sim.raid_warning, "the Warden waits while threat is low")
	sim.next_raid_at = sim.elapsed + 90.0
	check(Threat.meter(sim) >= Sim.Stewards.WARDEN_THREAT, "threat is high enough")
	var tower: Dictionary = first(sim, "tower")
	tower["hp"] = float(tower["max_hp"]) * 0.4
	pass_time(sim)
	check(not sim.raid_warning, "the Warden waits while a defence is damaged")
	tower["hp"] = float(tower["max_hp"])
	pass_time(sim)
	check(sim.raid_warning and sim.horn_called, "the Warden sounds the Horn once the village is ready")
	check(sim.notice.contains("Warden"), "the notice names the Warden")


func test_saved() -> void:
	var sim = fresh()
	sim.stewards.earned["reeve"] = true
	sim.stewards.earned["mason"] = true
	sim.stewards.off["mason"] = true
	var copy = Sim.new()
	check(copy.restore_state(JSON.parse_string(JSON.stringify(sim.export_state()))), "a village with stewards saves and loads")
	check(copy.stewards.has("reeve") and copy.stewards.has("mason") and not copy.stewards.has("warden"), "earned stewards survive a reload")
	check(copy.stewards.working("reeve") and not copy.stewards.working("mason"), "resting stewards stay resting")
	var old: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	old.erase("stewards")
	var older = Sim.new()
	check(older.restore_state(old) and older.stewards.earned.is_empty(), "a save from before stewards loads with none")


func test_card() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.sim.stewards.earned["reeve"] = true
	game._open_panel("stewards")
	for i in 3:
		await process_frame
	var texts: Array[String] = []
	for node: Node in game.side_content.find_children("*", "", true, false):
		if node is Label or node is Button:
			texts.append(str(node.text))
	var joined: String = " | ".join(PackedStringArray(texts))
	check(joined.contains("The Reeve") and joined.contains("The Warden"), "the Stewards card lists every steward")
	check(joined.contains("At work: On"), "an earned steward shows its switch")
	check(joined.contains("Manor Hall reaches tier 3"), "an unearned steward says how to earn it")
	game._toggle_steward("reeve")
	check(not game.sim.stewards.working("reeve"), "the card's switch rests the Reeve")
	game.queue_free()
	await process_frame
