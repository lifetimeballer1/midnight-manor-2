extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
const Moon = preload("res://scripts/game/village_moon_rules.gd")
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
	test_config()
	test_phase_advance()
	test_blood_and_new_moon()
	test_raid_advances_phase()
	test_persistence()
	print("MOON ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func test_config() -> void:
	check(Moon.config()["phase_names"].size() == 8, "moon.json names eight phases")
	check(Moon.phase_name(0) == "New Moon" and Moon.phase_name(4) == "Full Moon", "phase names come from moon.json")
	check(Moon.is_blood_moon(4) and not Moon.is_blood_moon(3), "the Full Moon is the blood moon")
	check(Moon.clamp_phase("junk") == 0 and Moon.clamp_phase(9) == 1 and Moon.clamp_phase(-1) == 7, "phase values fold into 0..7")


func test_phase_advance() -> void:
	for phase in 7:
		check(Moon.next_phase(phase) == phase + 1, "phase %d advances to %d" % [phase, phase + 1])
	check(Moon.next_phase(7) == 0, "the Waning Crescent wraps to the New Moon")
	var phase: int = 0
	for cycle in 16:
		phase = Moon.next_phase(phase)
	check(phase == 0, "sixteen cycles return to the same phase")


func test_blood_and_new_moon() -> void:
	check(is_equal_approx(Moon.enemy_multiplier(4), 1.25), "blood moon adds 25 percent enemies")
	check(is_equal_approx(Moon.enemy_multiplier(0), 0.75), "new moon brings 25 percent fewer enemies")
	check(is_equal_approx(Moon.enemy_multiplier(2), 1.0), "ordinary phases keep the base enemy count")
	check(is_equal_approx(Moon.loot_multiplier(4), 2.0), "blood moon doubles raid loot")
	check(is_equal_approx(Moon.loot_multiplier(3), 1.0), "other phases keep base loot")


func test_raid_advances_phase() -> void:
	var sim = Sim.new()
	check(sim.moon_phase == 0, "a new village starts at the New Moon")
	sim.raid_active = true
	sim.moon_phase = 3
	sim._finish_raid(true)
	check(sim.moon_phase == 4, "a finished raid advances the moon by one phase")
	sim.raid_active = true
	sim.moon_phase = 7
	sim._finish_raid(true)
	check(sim.moon_phase == 0, "the moon wraps after the Waning Crescent raid")


func test_persistence() -> void:
	var sim = Sim.new()
	sim.moon_phase = 6
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	check(int(state.get("moon_phase", -1)) == 6, "moon phase is written to the save payload")
	var restored = Sim.new()
	check(restored.restore_state(state), "moon phase round-trips through a JSON payload")
	check(restored.moon_phase == 6, "reload keeps the saved moon phase")
	check(int(state.get("version", 0)) == 4, "payload stays at version four")

	var missing: Dictionary = state.duplicate(true)
	missing.erase("moon_phase")
	restored.moon_phase = 5
	check(restored.restore_state(missing), "a save without moon_phase still loads")
	check(restored.moon_phase == 0, "a missing moon_phase defaults to phase 0")

	var legacy: Dictionary = state.duplicate(true)
	legacy["version"] = 3
	legacy.erase("moon_phase")
	legacy.erase("needs")
	check(restored.restore_state(legacy), "version-three saves without a moon phase still migrate")
	check(restored.moon_phase == 0, "older saves start at the New Moon")

	var bad: Dictionary = state.duplicate(true)
	bad["moon_phase"] = "full"
	check(not restored.restore_state(bad), "a nonnumeric saved moon_phase is rejected")
