extends SceneTree

# Income a minute on the HUD: the pace the sim reports must be the pace tick() actually fills
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
