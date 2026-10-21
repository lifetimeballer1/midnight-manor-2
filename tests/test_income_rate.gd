extends SceneTree

# Income a minute on the HUD, and offline earnings: the pace the sim reports must be the pace tick() actually fills
# workplace reserves at, full or broken workplaces count nothing, and mills count only with stock.
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
	test_rate_matches_tick()
	test_income_sums_workplaces()
	test_full_and_broken_count_nothing()
	test_mills_need_stock()
	test_offline_earnings()
	test_offline_banking_respects_storage()
	test_saved_at_round_trip()
	print("INCOME_RATE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	return sim


func producers(sim) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for b: Dictionary in sim.buildings:
		if sim.building_specs[b["type"]].get("production") != null and float(b["remaining"]) <= 0.0:
			found.append(b)
	return found


func test_rate_matches_tick() -> void:
	var sim = fresh()
	var list: Array[Dictionary] = producers(sim)
	check(not list.is_empty(), "the starting village has a producing workplace")
	for u: Dictionary in sim.units:
		u["hold"] = true   # nobody hauls, so reserves only grow
	for b: Dictionary in list:
		b["reserve"] = 0.0
	var expected: Dictionary = {}
	for b: Dictionary in list:
		expected[int(b["id"])] = sim.production_rate(b)
	sim.tick(1.0)
	for b: Dictionary in list:
		var want: float = minf(float(expected[int(b["id"])]), sim.reserve_cap(b))
		check(absf(float(b["reserve"]) - want) < 0.001, "%s fills at production_rate (%.3f vs %.3f)" % [b["type"], float(b["reserve"]), want])
		check(float(expected[int(b["id"])]) > 0.0, "%s produces something" % b["type"])


func test_income_sums_workplaces() -> void:
	var sim = fresh()
	var want: Dictionary = {}
	for b: Dictionary in producers(sim):
		b["reserve"] = 0.0
		var resource: String = str(sim.building_specs[b["type"]]["production"])
		want[resource] = float(want.get(resource, 0.0)) + sim.production_rate(b) * 60.0
	var income: Dictionary = sim.income_per_minute()
	for resource: String in want:
		var got: float = float(income.get(resource, {}).get("Workplaces", 0.0))
		check(absf(got - float(want[resource])) < 0.001, "%s a minute from workplaces (%.2f vs %.2f)" % [resource, got, float(want[resource])])


func test_full_and_broken_count_nothing() -> void:
	var sim = fresh()
	for b: Dictionary in producers(sim):
		b["reserve"] = sim.reserve_cap(b)
	var income: Dictionary = sim.income_per_minute()
	var workplaces: float = 0.0
	for resource: String in income:
		workplaces += float(income[resource].get("Workplaces", 0.0))
	check(workplaces == 0.0, "full workplaces have stalled and count nothing")
	var other = fresh()
	for b: Dictionary in producers(other):
		b["reserve"] = 0.0
		b["hp"] = 0.0
	check(other.production_rate(producers(other)[0]) == 0.0, "a ruined workplace produces nothing")
	income = other.income_per_minute()
	workplaces = 0.0
	for resource: String in income:
		workplaces += float(income[resource].get("Workplaces", 0.0))
	check(workplaces == 0.0, "ruined workplaces count nothing")


func test_mills_need_stock() -> void:
	var sim = fresh()
	var mill_type: String = ""
	for type: String in sim.building_specs:
		if not (sim.building_specs[type].get("refine", []) as Array).is_empty():
			mill_type = type
			break
	check(mill_type != "", "some building refines goods")
	if mill_type == "":
		return
	var recipe: Dictionary = sim.building_specs[mill_type]["refine"][0]
	var made: String = str(recipe["out"].keys()[0])
	var mill: Dictionary = sim.buildings[0].duplicate(true)
	mill["id"] = 99999
	mill["type"] = mill_type
	mill["tier"] = 1
	mill["hp"] = 100.0
	mill["remaining"] = 0.0
	mill["reserve"] = 0.0
	sim.buildings.append(mill)
	for need: String in recipe["in"]:
		sim.resources[need] = 0.0
	sim.resources[made] = 0.0
	check(float(sim.income_per_minute().get(made, {}).get("Mills", 0.0)) == 0.0, "a mill with no stock makes nothing")
	for need: String in recipe["in"]:
		sim.resources[need] = 1000.0
	var want: float = float(recipe["perSec"]) * float(recipe["out"][made]) * 60.0
	check(float(sim.income_per_minute().get(made, {}).get("Mills", 0.0)) >= want - 0.001, "a stocked mill counts %.1f %s a minute" % [want, made])


func test_offline_earnings() -> void:
	var sim = fresh()
	var per_second: Dictionary = {}
	for b: Dictionary in producers(sim):
		var resource: String = str(sim.building_specs[b["type"]]["production"])
		per_second[resource] = float(per_second.get(resource, 0.0)) + sim.production_rate(b)
	var hour: Dictionary = sim.offline_earnings(3600.0)
	for resource: String in per_second:
		check(absf(float(hour.get(resource, 0.0)) - floorf(float(per_second[resource]) * 3600.0)) < 1.0, "an hour away pays an hour of %s" % resource)
	var long: Dictionary = sim.offline_earnings(48.0 * 3600.0)
	var capped: Dictionary = sim.offline_earnings(Sim.OFFLINE_CAP_SECONDS)
	check(long == capped, "time away past the cap pays no more than the cap")
	check(sim.offline_earnings(0.0).is_empty() and sim.offline_earnings(-50.0).is_empty(), "no time away pays nothing")
	var town: Dictionary = sim.offline_earnings(600.0, {"gold": 6.0})
	var plain: Dictionary = sim.offline_earnings(600.0)
	check(absf(float(town.get("gold", 0.0)) - float(plain.get("gold", 0.0)) - 60.0) < 1.0, "the town's lots add their pace (6 a minute for 10 minutes = 60)")


func test_offline_banking_respects_storage() -> void:
	var sim = fresh()
	var before: Dictionary = sim.resources.duplicate()
	var raids: float = sim.next_raid_at
	var units: int = sim.units.size()
	var banked: Dictionary = sim.bank_offline({"wood": 1.0e9, "food": 5.0})
	check(int(banked.get("wood", 0)) == int(sim.storage_cap("wood") - float(before["wood"])), "wood fills only to its storage cap")
	check(float(sim.resources["wood"]) <= sim.storage_cap("wood"), "stores never overflow")
	check(int(banked.get("food", 0)) == 5, "small payouts bank whole")
	check(sim.next_raid_at == raids and sim.units.size() == units, "offline pay changes nothing but the stores")


func test_saved_at_round_trip() -> void:
	var sim = fresh()
	var path: String = "user://test-income-offline.json"
	check(sim.save_game(path), "the village saves")
	var text: String = FileAccess.get_file_as_string(path)
	var data: Dictionary = JSON.parse_string(text)
	check(data.has("saved_at"), "a save carries the real time it was written")
	data["saved_at"] = Time.get_unix_time_from_system() - 7200.0
	var other = fresh()
	check(other.restore_state(data), "a save with saved_at loads")
	check(absf(other.away_seconds - 7200.0) < 5.0, "loading measures the time away (%.0f s)" % other.away_seconds)
	data.erase("saved_at")
	var old = fresh()
	check(old.restore_state(data) and old.away_seconds == 0.0, "an older save without a clock pays nothing")
	data["saved_at"] = Time.get_unix_time_from_system() + 9999.0
	check(old.restore_state(data) and old.away_seconds == 0.0, "a clock that ran backwards pays nothing")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
