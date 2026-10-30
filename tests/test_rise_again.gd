extends SceneTree

# Rise again after a lost raid (The Manor Endures, B1): builders rebuild the Hall first, then
# workplaces, paid from the stores a tenth at a time; ruined workplaces still trickle; progress is
# saved; and an untouched village left for an hour still earns after the first warlord.
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
	test_hall_first_then_workplaces()
	test_paid_from_stores()
	test_ruins_trickle()
	test_progress_saved()
	test_no_builder_neighbours_help()
	test_idle_hour()
	print("RISE_AGAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	sim.paused = false
	return sim


func first(sim, type_name: String) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if str(b["type"]) == type_name:
			return b
	return {}


func ruin(b: Dictionary) -> void:
	b["hp"] = 0.0
	b["reserve"] = 0.0


func run(sim, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		sim.tick(0.1)
		t += 0.1


func test_hall_first_then_workplaces() -> void:
	var sim = fresh()
	var hall: Dictionary = first(sim, "hall")
	var farm: Dictionary = first(sim, "farm")
	var tower: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if sim.rebuild.priority(sim, b) < 0 and str(b["type"]) != "hall":
			tower = b
			break
	check(not hall.is_empty() and not farm.is_empty(), "starting village has a Hall and a farm")
	ruin(hall)
	ruin(farm)
	if not tower.is_empty():
		ruin(tower)
	sim.resources["wood"] = 2000.0
	sim.resources["stone"] = 2000.0
	check(sim.rebuild.target(sim) == hall, "the Hall is rebuilt first")
	var hall_up: float = -1.0
	var farm_up: float = -1.0
	var t: float = 0.0
	while t < 400.0 and (hall_up < 0.0 or farm_up < 0.0):
		sim.tick(0.1)
		t += 0.1
		if hall_up < 0.0 and float(hall["hp"]) > 0.0:
			hall_up = t
		if farm_up < 0.0 and float(farm["hp"]) > 0.0:
			farm_up = t
	check(hall_up > 0.0, "the Hall stands again (%.0fs)" % hall_up)
	check(farm_up > 0.0, "the farm stands again (%.0fs)" % farm_up)
	check(hall_up > 0.0 and farm_up >= hall_up, "the farm comes after the Hall")
	check(is_equal_approx(float(hall["hp"]), float(hall["max_hp"])), "a rebuilt Hall stands at full health")
	check(not hall.has("rebuild") and not hall.has("rebuild_paid"), "rebuild progress is cleared when done")
	if not tower.is_empty():
		check(float(tower["hp"]) <= 0.0, "defences are left for the player to repair (%s)" % tower["type"])
	sim.raid_warning = true
	ruin(farm)
	check(sim.rebuild.target(sim).is_empty(), "no rebuilding while the horns sound")


func test_paid_from_stores() -> void:
	var sim = fresh()
	var hall: Dictionary = first(sim, "hall")
	ruin(hall)
	sim.resources["wood"] = 0.0
	sim.resources["stone"] = 0.0
	check(not sim.rebuild.can_work(sim, hall), "an empty store cannot pay for the next tenth")
	run(sim, 30.0)
	check(float(hall["hp"]) <= 0.0 and float(hall.get("rebuild", 0.0)) <= 0.0, "the work waits on empty stores")
	var cost: Dictionary = sim.rebuild.step_cost(sim, hall)
	for resource: String in cost:
		sim.resources[resource] = float(cost[resource])
	check(sim.rebuild.work(sim, hall, 1.0, 0.1) == false, "work starts once a tenth is affordable")
	check(is_equal_approx(float(hall["rebuild_paid"]), 0.1), "one tenth is paid")
	for resource: String in cost:
		check(float(sim.resources[resource]) < 0.5, "%s was spent on the tenth" % resource)
	var before: float = float(hall["rebuild"])
	for i in 2000:
		sim.rebuild.work(sim, hall, 1.0, 0.1)
	check(float(hall["rebuild"]) <= 0.1 + 0.0001 and float(hall["rebuild"]) > before, "work stops where the paid share ends")


func test_ruins_trickle() -> void:
	var sim = fresh()
	var farm: Dictionary = first(sim, "farm")
	ruin(farm)
	for u: Dictionary in sim.units:
		if str(u["type"]) == "builder":
			u["hp"] = 0.0   # nobody rebuilds; only the trickle remains
	sim.resources["wood"] = 0.0
	sim.resources["stone"] = 0.0
	var rate: float = sim.rebuild.trickle_rate(sim, farm)
	check(rate > 0.0, "a ruined farm still yields a trickle")
	var income: Dictionary = sim.income_per_minute()
	check(float(income.get("food", {}).get("Ruins", 0.0)) > 0.0, "the trickle shows in income a minute")
	var earned: Dictionary = sim.offline_earnings(3600.0)
	check(float(earned.get("food", 0.0)) >= floorf(rate * 3600.0) - 1.0, "time away pays the trickle too")
	var food: float = float(sim.resources.get("food", 0.0))
	sim.rebuild.tick(sim, 60.0, 1)
	check(float(sim.resources.get("food", 0.0)) > food, "the trickle reaches the stores")


func test_progress_saved() -> void:
	var sim = fresh()
	var hall: Dictionary = first(sim, "hall")
	ruin(hall)
	sim.resources["wood"] = 500.0
	sim.resources["stone"] = 500.0
	for i in 30:
		sim.rebuild.work(sim, hall, 1.0, 1.0)
	var done: float = float(hall["rebuild"])
	check(done > 0.0 and done < 1.0, "a rebuild is part done (%.2f)" % done)
	var copy = Sim.new()
	check(copy.restore_state(JSON.parse_string(JSON.stringify(sim.export_state()))), "a village mid-rebuild saves and loads")
	var loaded: Dictionary = first(copy, "hall")
	check(absf(float(loaded.get("rebuild", 0.0)) - done) < 0.001, "rebuild progress survives a reload")
	check(float(loaded["hp"]) <= 0.0, "the Hall is still a ruin after the reload")


func test_no_builder_neighbours_help() -> void:
	var sim = fresh()
	var hall: Dictionary = first(sim, "hall")
	ruin(hall)
	sim.resources["wood"] = 2000.0
	sim.resources["stone"] = 2000.0
	sim.units = sim.units.filter(func(u: Dictionary) -> bool: return str(u["type"]) != "builder")
	run(sim, 20.0)
	check(float(hall.get("rebuild", 0.0)) > 0.0 or float(hall["hp"]) > 0.0, "with no builder, neighbours still rebuild")


# The review's case: an untouched village loses the first warlord around minute 22. It must earn again.
func test_idle_hour() -> void:
	var sim = Sim.new()
	sim.paused = false
	var hall_fell: bool = false
	var t: float = 0.0
	while t < 3600.0:
		sim.tick(0.1)
		t += 0.1
		if float(sim._hall().get("hp", 0.0)) <= 0.0:
			hall_fell = true
	var total: float = 0.0
	var income: Dictionary = sim.income_per_minute()
	for resource: String in income:
		for source: String in income[resource]:
			total += float(income[resource][source])
	print("idle hour: hall fell=", hall_fell, " wave=", sim.wave, " income/min=", int(total), " hall hp=", int(sim._hall().get("hp", 0)))
	check(float(sim._hall().get("hp", 0.0)) > 0.0, "after an idle hour the Hall stands")
	check(total > 50.0, "after an idle hour the village still earns (%.0f a minute)" % total)
	check(sim.wave > 4, "raids carry on past the first warlord (wave %d)" % sim.wave)
