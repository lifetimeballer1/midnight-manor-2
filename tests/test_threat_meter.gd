extends SceneTree

# Raids that fit idle play (The Manor Endures, B2): threat builds on a meter, holds while the Hall
# lies in ruins, the Horn still calls a raid early, ambient raids follow the village's defence
# strength, story raids keep their size, and the meter's span is saved.
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
	test_meter_fills()
	test_meter_holds_while_hall_ruined()
	test_horn_calls_early()
	test_strength_follows_defence()
	test_story_raid_keeps_size()
	test_span_saved()
	print("THREAT_METER ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


# A village past the onboarding lane, with the next raid `seconds` away.
func veteran(seconds: float) -> Variant:
	var sim = Sim.new()
	sim.paused = false
	sim.completed_quests.append("the-first-horn")
	sim.elapsed = 1000.0
	sim.raid_span = 240.0
	sim.next_raid_at = sim.elapsed + seconds
	return sim


func run(sim, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		sim.tick(0.1)
		t += 0.1


func test_meter_fills() -> void:
	var sim = veteran(240.0)
	check(Threat.meter(sim) < 0.01, "a fresh span starts empty (%.2f)" % Threat.meter(sim))
	sim.next_raid_at = sim.elapsed + 25.0 + 107.5
	check(absf(Threat.meter(sim) - 0.5) < 0.01, "halfway through the span the meter is half full (%.2f)" % Threat.meter(sim))
	sim.next_raid_at = sim.elapsed + 30.0
	run(sim, 6.0)
	check(sim.raid_warning, "a full meter sounds the horns")
	check(is_equal_approx(Threat.meter(sim), 1.0), "the meter reads full while the horns sound")


func test_meter_holds_while_hall_ruined() -> void:
	var sim = veteran(130.0)
	var before: float = Threat.meter(sim)
	sim._hall()["hp"] = 0.0
	for u: Dictionary in sim.units:
		if str(u["type"]) == "builder":
			u["hp"] = 0.0
	sim.resources["wood"] = 0.0
	sim.resources["stone"] = 0.0
	var t: float = 0.0
	while t < 300.0:
		sim._hall()["hp"] = 0.0   # nobody rebuilds it in this test
		sim.tick(0.1)
		t += 0.1
	check(not sim.raid_warning and not sim.raid_active, "no raid comes while the Hall lies in ruins")
	check(Threat.meter(sim) <= before + 0.01, "the meter holds while the Hall is down (%.2f -> %.2f)" % [before, Threat.meter(sim)])
	check(sim.next_raid_at - sim.elapsed >= 84.0, "a standing Hall gets at least a minute of quiet")


func test_horn_calls_early() -> void:
	var sim = veteran(200.0)
	check(sim.start_raid(), "the Horn calls the next raid early")
	check(sim.raid_warning and sim.next_raid_at - sim.elapsed <= 3.01, "the called raid comes in 3 seconds")


func spawn(sim) -> Dictionary:
	sim.raid_warning = true
	sim.next_raid_at = sim.elapsed
	sim._spawn_raid()
	var health: float = 0.0
	for enemy: Dictionary in sim.enemies:
		health += float(enemy["max_hp"])
		check(is_equal_approx(float(enemy["hp"]), float(enemy["max_hp"])), "a raider starts at full (eased) health")
	return {"health": health, "share": float(sim.war_log.get("share", 1.0))}


func test_strength_follows_defence() -> void:
	# Same wave, same moon: one village with its defences, one without.
	var strong = veteran(0.0)
	strong.wave = 4
	var weak = veteran(0.0)
	weak.wave = 4
	for b: Dictionary in weak.buildings:
		var stats: Dictionary = weak.building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]
		if float(stats.get("damage", 0.0)) > 0.0:
			b["hp"] = 0.0
	for u: Dictionary in weak.units:
		if str(weak.troop_specs[u["type"]]["role"]) == "combat":
			u["hp"] = 0.0
	check(Threat.defence_power(weak) < Threat.defence_power(strong), "losing defences lowers defence power")
	var hard: Dictionary = spawn(strong)
	var soft: Dictionary = spawn(weak)
	check(float(soft["health"]) < float(hard["health"]), "a village without defences meets a smaller band (%.0f vs %.0f)" % [soft["health"], hard["health"]])
	check(float(soft["share"]) >= Threat.MIN_SHARE - 0.001, "raids never shrink below the floor share")
	check(float(hard["share"]) <= 1.0, "raids never grow past the usual wave curve")
	# A village with a lot of defence meets the full curve.
	var fort = veteran(0.0)
	fort.wave = 2
	for u: Dictionary in fort.units:
		u["level"] = 25
	var full: Dictionary = spawn(fort)
	check(is_equal_approx(float(full["share"]), 1.0), "strong defences face the full raid (share %.2f)" % full["share"])


func test_story_raid_keeps_size() -> void:
	var sim = veteran(500.0)
	sim.wave = 7
	for u: Dictionary in sim.units:
		u["hp"] = 0.0
	sim._start_story_raid(3)
	run(sim, 7.0)
	check(sim.raid_active, "the story raid arrives")
	check(is_equal_approx(float(sim.war_log.get("share", 0.0)), 1.0), "story raids keep their full size")


func test_span_saved() -> void:
	var sim = veteran(100.0)
	sim.raid_span = 360.0
	var copy = Sim.new()
	check(copy.restore_state(JSON.parse_string(JSON.stringify(sim.export_state()))), "the village saves and loads")
	check(is_equal_approx(float(copy.raid_span), 360.0), "the meter's span survives a reload")
	var old: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	old.erase("raid_span")
	var older = Sim.new()
	check(older.restore_state(old), "a save from before the meter still loads")
	check(is_equal_approx(float(older.raid_span), 240.0), "older saves get the usual span")
