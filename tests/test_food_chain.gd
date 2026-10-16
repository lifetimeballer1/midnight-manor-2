extends SceneTree

# The food chain: bread before plain food, Well fed bonuses, feasts, soldiers' appetite, rations
# for expeditions, and starvation that slows the village and sends people away (never kills).
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
	test_bread_first()
	test_mixed_meal()
	test_feast()
	test_starvation()
	test_rations()
	test_saves()
	print("FOOD_CHAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	return sim


func meal(sim) -> void:
	sim.needs.meal_clock = float(sim.world_specs["townMeal"]["secondsPerDay"]) - 0.5
	sim.needs.tick(sim, 1.0)


func test_bread_first() -> void:
	var sim = fresh()
	# Starting village: warrior, archer, miner, builder, farmer. Fighters eat double: 7 portions.
	check(is_equal_approx(sim.needs.shares(sim), 7.0), "two fighters eat double, so five villagers eat seven portions")
	sim.resources["bread"] = 20.0
	sim.resources["food"] = 100.0
	meal(sim)
	check(sim.resources["bread"] == 13.0 and sim.resources["food"] == 100.0, "the village eats bread before plain food")
	check(sim.needs.well_fed() and sim.needs.summary(sim).begins_with("Well fed"), "a bread-fed village is Well fed")
	check(sim.needs.fed_bonus(sim, "gather") > 0.0 and sim.needs.growth_multiplier(sim) > 1.0, "Well fed gives the authored gathering and growth bonuses")
	var farm: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if b["type"] == "farm":
			farm = b
	farm["reserve"] = 0.0
	for u: Dictionary in sim.units:
		u["hold"] = true
	sim.tick(1.0)
	var fed_rate: float = float(farm["reserve"])
	var plain = fresh()
	var plain_farm: Dictionary = {}
	for b: Dictionary in plain.buildings:
		if b["type"] == "farm":
			plain_farm = b
	plain_farm["reserve"] = 0.0
	for u: Dictionary in plain.units:
		u["hold"] = true
	plain.tick(1.0)
	check(fed_rate > float(plain_farm["reserve"]), "a Well fed village's farms work faster")


func test_mixed_meal() -> void:
	var sim = fresh()
	sim.resources["bread"] = 3.0
	sim.resources["food"] = 100.0
	meal(sim)
	check(sim.resources["bread"] == 0.0 and sim.resources["food"] == 80.0, "bread covers who it can, plain food the rest")
	check(not sim.needs.well_fed() and sim.needs.fed == "fed", "a part-bread meal is only Fed")


func test_feast() -> void:
	var sim = fresh()
	sim.resources["bread"] = 50.0
	sim.resources["feast-supplies"] = 5.0
	meal(sim)
	check(sim.needs.fed == "feast" and sim.resources["feast-supplies"] == 4.0, "a bread meal with feast supplies to spare becomes a feast")
	for i in 400:
		sim.needs.tick(sim, 1.0)
	check(sim.needs.morale > 70.0, "a feast lifts morale above its usual ceiling")
	check(sim.needs.growth_multiplier(sim) > 1.25 or sim.needs.fed != "feast", "a feast brings newcomers faster still")


func test_starvation() -> void:
	var sim = fresh()
	sim.resources["food"] = 0.0
	sim.resources["bread"] = 0.0
	meal(sim)
	check(sim.needs.missed == 1 and not sim.needs.starving() and sim.notice.contains("Another missed meal"), "one missed meal warns before anyone stops working")
	meal(sim)
	check(sim.needs.starving() and sim.needs.production_multiplier() <= 0.5, "two missed meals in a row halve the village's work")
	check(sim.needs.summary(sim).begins_with("Starving"), "the status says the village is starving")
	meal(sim)
	meal(sim)
	check(sim.units.size() == 5, "nobody leaves before the fifth missed meal")
	meal(sim)
	check(sim.units.size() == 4 and sim.notice.contains("leaves the village"), "the fifth missed meal sends one villager away")
	var fighters: int = 0
	for u: Dictionary in sim.units:
		if str(sim.troop_specs[u["type"]]["role"]) == "combat":
			fighters += 1
	check(fighters == 2, "a gatherer leaves before a fighter")
	sim.resources["food"] = 500.0
	meal(sim)
	check(sim.needs.missed == 0 and not sim.needs.starving(), "a full meal ends the starving")


func test_rations() -> void:
	var sim = fresh()
	var crew: Array = []
	for u: Dictionary in sim.units:
		if str(sim.troop_specs[u["type"]]["role"]) == "combat":
			crew.append(int(u["id"]))
	var cost: Dictionary = sim.frontier.cost(sim, crew)
	check(cost == {"food": 20, "gold": 10}, "without rations an expedition still costs 20 Food and 10 Gold")
	sim.resources["rations"] = 10.0
	cost = sim.frontier.cost(sim, crew)
	check(cost == {"rations": 4, "gold": 10}, "with rations each fighter takes two instead of Food")
	var region: String = str(sim.chronicle.region_order()[0])
	check(sim.frontier.reason(sim, region, crew).is_empty(), "a rationed expedition can set out")
	var warrior: Dictionary = sim.get_unit(int(crew[0]))
	var plain: float = sim._stat(warrior, "damage")
	check(sim.frontier.begin(sim, region, crew), "the expedition sets out")
	check(sim.resources["rations"] == 6.0, "rations leave the stores")
	check(sim.frontier.active.get("rationed", false) and float(sim.frontier.active["army"][0]["damage"]) > plain, "rationed fighters hit harder on the march")


func test_saves() -> void:
	var sim = fresh()
	sim.needs.missed = 3
	sim.needs.fed = "short"
	var state: Variant = JSON.parse_string(JSON.stringify(sim.export_state()))
	var loaded = Sim.new()
	check(loaded.restore_state(state) and loaded.needs.missed == 3 and loaded.needs.fed == "short", "missed meals survive a save")
	state["needs"]["fed"] = "banquet"
	check(not Sim.new().restore_state(state), "an unknown meal state is refused")
	var old: Variant = JSON.parse_string(JSON.stringify(sim.export_state()))
	old["needs"].erase("missed")
	old["needs"].erase("fed")
	var older = Sim.new()
	check(older.restore_state(old) and older.needs.missed == 0 and older.needs.fed == "fed", "older saves without meal history still load")
