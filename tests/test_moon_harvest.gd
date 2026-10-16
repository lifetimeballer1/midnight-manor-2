extends SceneTree

# The moon and the larder: crops yield more under the Full Moon and less under the New Moon, and
# food held above what keeps (base store, Manor Hall, Grand Granary) slowly spoils.
const Sim = preload("res://scripts/game/village_sim.gd")
const MoonRules = preload("res://scripts/game/village_moon_rules.gd")
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
	test_moon_harvest()
	test_spoilage()
	print("MOON_HARVEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	return sim


func farm_yield(phase: int) -> float:
	var sim = fresh()
	sim.wave = 1
	sim.moon_phase = phase
	var farm: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if b["type"] == "farm":
			farm = b
	farm["reserve"] = 0.0
	for u: Dictionary in sim.units:
		u["hold"] = true
	sim.tick(1.0)
	return float(farm["reserve"])


func test_moon_harvest() -> void:
	check(is_equal_approx(MoonRules.harvest_multiplier(4, "farm"), 1.2), "the Full Moon gives 20% more harvest")
	check(is_equal_approx(MoonRules.harvest_multiplier(0, "farm"), 0.8), "the New Moon gives 20% less")
	check(is_equal_approx(MoonRules.harvest_multiplier(2, "farm"), 1.0) and is_equal_approx(MoonRules.harvest_multiplier(6, "pond"), 1.0), "the quarters change nothing")
	check(is_equal_approx(MoonRules.harvest_multiplier(4, "mine"), 1.0), "mines and mills ignore the moon")
	var full: float = farm_yield(4)
	var dark: float = farm_yield(0)
	var half: float = farm_yield(2)
	check(full > half and half > dark, "a farm fills fastest under the Full Moon (%.2f / %.2f / %.2f)" % [full, half, dark])
	check(is_equal_approx(full / half, 1.2), "by a fifth more than at the quarter")
	check(MoonRules.harvest_text(4) == "Full Moon: +20% harvest" and MoonRules.harvest_text(2) == "", "the farm card names the moon's effect")
	var opening = fresh()
	opening.moon_phase = 0
	var farm: Dictionary = {}
	for b: Dictionary in opening.buildings:
		if b["type"] == "farm":
			farm = b
	farm["reserve"] = 0.0
	for u: Dictionary in opening.units:
		u["hold"] = true
	opening.tick(1.0)
	check(is_equal_approx(float(farm["reserve"]), half), "before the first raid the moon does not touch the harvest")


func test_spoilage() -> void:
	var sim = fresh()
	var keeps: float = sim.needs.keeps(sim)
	check(is_equal_approx(keeps, sim.storage_cap("food")), "a village with no Storehouse keeps all the food it can hold")
	sim.resources["food"] = keeps
	sim.needs.tick(sim, 1.0)
	check(is_equal_approx(float(sim.resources["food"]), keeps), "food within what keeps does not spoil")
	var store: Dictionary = sim._new_building("storehouse", 14, 2, false)
	sim.buildings.append(store)
	check(sim.storage_cap("food") > keeps and is_equal_approx(sim.needs.keeps(sim), keeps), "a Storehouse holds more food but does not keep it")
	sim.resources["food"] = keeps + 3000.0
	check(is_equal_approx(sim.needs.spoiling(sim), 30.0), "1% of the excess spoils each minute")
	check(sim.needs.summary(sim).contains("30 Food spoiling a minute"), "the people panel says food is spoiling")
	for i in 60:
		sim.needs.tick(sim, 1.0)
	check(float(sim.resources["food"]) < keeps + 3000.0 - 25.0 and float(sim.resources["food"]) > keeps + 3000.0 - 31.0, "about a minute's spoilage is lost (%.1f)" % (keeps + 3000.0 - float(sim.resources["food"])))
	sim.resources["bread"] = 5000.0
	var bread: float = float(sim.resources["bread"])
	sim.needs.tick(sim, 1.0)
	check(float(sim.resources["bread"]) == bread, "bread keeps")
	var granary: Dictionary = sim._new_building("grand-granary", 16, 4, false)
	sim.buildings.append(granary)
	check(sim.needs.keeps(sim) >= keeps + 3000.0, "a Grand Granary keeps food")
	sim.resources["food"] = keeps + 2000.0
	check(sim.needs.spoiling(sim) == 0.0, "with a Granary nothing spoils")
