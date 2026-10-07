extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
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
	var sim = Sim.new()
	check(sim.get("needs") != null, "village needs are connected to the simulation")
	if sim.get("needs") != null:
		test_meals(sim)
		test_pause()
		test_shortage_and_recovery()
		test_housing()
		test_persistence()
	print("VILLAGE_NEEDS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func advance(sim, seconds: int) -> void:
	for second in seconds:
		sim.needs.tick(sim, 1.0)


func test_meals(sim) -> void:
	sim.resources["food"] = 100.0
	advance(sim, 179)
	check(sim.resources["food"] == 100.0, "meals wait for their active-time interval")
	advance(sim, 1)
	check(sim.resources["food"] == 75.0, "five villagers consume five Food each at the authored town meal")
	check(sim.needs.hunger == 0.0 and sim.needs.morale == 70.0, "a fed, housed starting village stays stable")
	check(sim.needs.production_multiplier() == 1.0, "healthy village preserves the original production rate")


func test_pause() -> void:
	var sim = Sim.new()
	sim.paused = true
	var before: Dictionary = sim.export_state()
	advance(sim, 600)
	sim.tick(1.0)
	check(sim.needs.meal_clock == 0.0 and sim.resources["food"] == 180.0, "paused time does not consume meals or grow hunger")
	check(sim.needs.state() == before["needs"], "paused needs remain unchanged")


func test_shortage_and_recovery() -> void:
	var sim = Sim.new()
	sim.resources["food"] = 0.0
	advance(sim, 240)
	check(sim.needs.hunger > 0.0 and sim.needs.morale < 70.0, "missed meals cause visible hunger and lower morale")
	check(sim.needs.production_multiplier() < 1.0 and sim.needs.production_multiplier() >= 0.75, "shortage reduces productivity without a death spiral")
	check(sim.resources["food"] == 0.0 and sim.units.size() == 5, "shortages never make negative resources or secretly kill villagers")
	check(sim.needs.summary(sim).contains("Food"), "shortage status explains the resource to restore")
	sim.resources["food"] = 200.0
	advance(sim, 600)
	check(sim.needs.hunger == 0.0 and sim.needs.morale >= 69.0, "restored food recovers hunger and morale")
	check(sim.needs.production_multiplier() == 1.0, "recovery restores normal production")


func test_housing() -> void:
	var sim = Sim.new()
	for index in 5:
		sim._add_unit("farmer")
	advance(sim, 60)
	check(sim.needs.morale < 70.0, "insufficient beds lower morale")
	var cottage: Dictionary = sim._new_building("cottage", 1, 1, false)
	sim.buildings.append(cottage)
	advance(sim, 300)
	check(sim.needs.morale >= 69.0, "completed housing restores morale")


func test_persistence() -> void:
	var sim = Sim.new()
	sim.needs.hunger = 25.0
	sim.needs.morale = 45.0
	sim.needs.meal_clock = 120.0
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	var restored = Sim.new()
	check(restored.restore_state(state), "needs round-trip through a real JSON payload")
	check(restored.needs.hunger == 25.0 and restored.needs.morale == 45.0 and restored.needs.meal_clock == 120.0, "reload preserves hunger, morale and the partial meal interval")
	check(restored.elapsed == sim.elapsed, "loading adds no offline time")
	var legacy: Dictionary = state.duplicate(true)
	legacy["version"] = 3
	legacy.erase("needs")
	check(restored.restore_state(legacy), "version-three villages migrate without a reset")
	check(restored.needs.hunger == 0.0 and restored.needs.morale == 70.0, "older saves receive a healthy needs baseline")
	for field: String in ["hunger", "morale", "meal_clock"]:
		var bad: Dictionary = state.duplicate(true)
		bad["needs"][field] = -1.0
		check(not restored.restore_state(bad), "negative saved " + field + " is rejected")
		bad["needs"][field] = "invalid"
		check(not restored.restore_state(bad), "nonnumeric saved " + field + " is rejected")
	var bad: Dictionary = state.duplicate(true)
	bad["needs"]["hunger"] = 101.0
	check(not restored.restore_state(bad), "out-of-range hunger is rejected")
	bad = state.duplicate(true)
	bad.erase("needs")
	check(not restored.restore_state(bad), "new-version saves cannot silently lose their needs section")
	check(restored.needs.hunger == 0.0, "rejected saves leave the current village unchanged")
