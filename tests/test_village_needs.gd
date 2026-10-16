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
		test_newcomers_take_open_jobs()
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
	check(sim.resources["food"] == 65.0, "five Food a portion at the authored town meal; the two fighters eat a double portion")
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


# A villager born into warm beds takes up the trade of a workplace with room, and goes to work.
func test_newcomers_take_open_jobs() -> void:
	var sim = Sim.new()
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
	sim._auto_assign()
	var open_role: String = sim.open_job_role()
	var open_place: int = -1
	for b: Dictionary in sim.buildings:
		var crew: int = 0
		for u: Dictionary in sim.units:
			if int(u["workplace"]) == int(b["id"]):
				crew += 1
		if str(sim.building_specs[b["type"]].get("workplace", "")) == open_role and crew < 2:
			open_place = int(b["id"])
	check(open_role != "farmer" and open_place >= 0, "the starting village has an open job (%s)" % open_role)
	sim.buildings.append(sim._new_building("cottage", 4, 12, false))
	sim.resources["food"] = 500.0
	var before: int = sim.units.size()
	for i in 1300:
		sim.tick(0.05)
	check(sim.units.size() == before + 1, "a villager is born into the free beds")
	var newcomer: Dictionary = sim.units.back()
	var place: Dictionary = sim.get_building(int(newcomer["workplace"]))
	check(str(newcomer["type"]) == open_role and not place.is_empty() and str(sim.building_specs[place["type"]].get("workplace", "")) == open_role, "the newcomer is a %s and goes straight to work (%s at %d)" % [open_role, newcomer["type"], int(newcomer["workplace"])])
	for b: Dictionary in sim.buildings:
		if str(sim.building_specs[b["type"]].get("workplace", "")) != "":
			for n in 2:
				sim._add_unit(str(sim.building_specs[b["type"]]["workplace"]))
	sim._auto_assign()
	check(sim.open_job_role() == "farmer", "with every crew full, newcomers are farmers as before")
