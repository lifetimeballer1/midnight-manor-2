extends SceneTree

# Workplace perks: the bonuses on buildings in data/buildings.json do something, and only while staffed.
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
	test_workshop()
	test_mason_yard()
	test_global_perks()
	test_chapel()
	test_caps_and_describe()
	print("WORKPLACE_PERKS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func place(sim, type_name: String, x: int, y: int, constructing: bool = false) -> Dictionary:
	var b: Dictionary = sim._new_building(type_name, x, y, constructing)
	sim.buildings.append(b)
	sim.revision += 1
	return b


func staff(sim, b: Dictionary) -> Dictionary:
	var role: String = str(sim.building_specs[b["type"]]["workplace"])
	sim._add_unit(role)
	var u: Dictionary = sim.units[sim.units.size() - 1]
	u["workplace"] = int(b["id"])
	return u


func test_workshop() -> void:
	var sim = Sim.new()
	var farm: Dictionary = place(sim, "farm", 2, 2)
	var far_farm: Dictionary = place(sim, "farm", 17, 13)
	var shop: Dictionary = place(sim, "workshop", 5, 2)
	sim.perks.refresh(sim, true)
	check(sim.perks.gather_for(farm) == 1.0, "an empty workshop gives nothing")
	check(sim.perks.describe(sim, shop).contains("needs a worker"), "the card says an empty workshop needs a worker")
	var smith: Dictionary = staff(sim, shop)
	sim.perks.refresh(sim, true)
	check(is_equal_approx(sim.perks.gather_for(farm), 1.15), "a staffed workshop speeds a farm in reach by its gatherAura")
	check(sim.perks.gather_for(far_farm) == 1.0, "a farm out of reach gets no workshop bonus")
	check(sim.perks.gather_for(shop) == 1.0, "the workshop does not boost itself")
	check(sim.perks.describe(sim, shop).begins_with("Boosting 1 nearby workplace +15%"), "the card counts the workplaces it boosts")
	# A second workshop in reach does not stack: the best one counts.
	var shop2: Dictionary = place(sim, "workshop", 2, 5)
	staff(sim, shop2)
	sim.perks.refresh(sim, true)
	check(is_equal_approx(sim.perks.gather_for(farm), 1.15), "workshop auras take the best, they do not stack")
	shop["tier"] = 2
	sim.perks.refresh(sim, true)
	check(is_equal_approx(sim.perks.gather_for(farm), 1.225), "a tier 2 workshop adds half its bonus again")
	# The bonus reaches the farm's real output.
	farm["reserve"] = 0.0
	far_farm["reserve"] = 0.0
	smith["hp"] = 0.0
	shop2["hp"] = 0.0
	sim.perks.refresh(sim, true)
	check(sim.perks.gather_for(farm) == 1.0, "a fallen worker switches the perk off")
	smith["hp"] = smith["max_hp"]
	sim.perks.refresh(sim, true)
	for u: Dictionary in sim.units:
		u["hold"] = true
	sim.tick(1.0)
	check(float(farm["reserve"]) > float(far_farm["reserve"]) * 1.2, "the boosted farm fills its reserve faster during play")


func test_mason_yard() -> void:
	var sim = Sim.new()
	var site: Dictionary = place(sim, "cottage", 2, 2, true)
	var other: Dictionary = place(sim, "cottage", 16, 12, true)
	var yard: Dictionary = place(sim, "mason_yard", 5, 2)
	staff(sim, yard)
	sim.perks.refresh(sim, true)
	var before_site: float = float(site["remaining"])
	var before_other: float = float(other["remaining"])
	sim.tick(1.0)
	check(is_equal_approx(before_site - float(site["remaining"]), 1.25), "a staffed mason yard makes nearby building work 25% faster")
	check(is_equal_approx(before_other - float(other["remaining"]), 1.0), "building out of reach goes at the normal pace")


func test_global_perks() -> void:
	var sim = Sim.new()
	var warrior: Dictionary = {}
	sim._add_unit("warrior")
	warrior = sim.units[sim.units.size() - 1]
	var plain: float = sim._stat(warrior, "damage")
	var forge: Dictionary = place(sim, "forge", 3, 3)
	staff(sim, forge)
	sim.perks.refresh(sim, true)
	check(is_equal_approx(sim._stat(warrior, "damage"), plain * 1.1), "a staffed forge adds 10% to fighters' damage")
	var smith: Dictionary = sim.units[sim.units.size() - 1]
	check(is_equal_approx(sim._stat(smith, "hp"), float(sim.troop_specs["weaponsmith"]["base"]["hp"])), "the forge does not touch other stats")
	var farmer: Dictionary = {}
	for u: Dictionary in sim.units:
		if u["type"] == "farmer":
			farmer = u
	var base_carry: int = sim.carry_of(farmer)
	var tannery: Dictionary = place(sim, "tannery", 8, 3)
	staff(sim, tannery)
	sim.perks.refresh(sim, true)
	check(sim.carry_of(farmer) == base_carry + 6, "a staffed tannery lets gatherers carry 6 more")
	var scriptorium: Dictionary = place(sim, "scriptorium", 10, 3)
	staff(sim, scriptorium)
	sim.perks.refresh(sim, true)
	check(is_equal_approx(sim.perks.total("xp"), 0.12) and is_equal_approx(sim.perks.total("research"), 0.15), "a staffed scriptorium adds XP and research")
	var insight: float = sim.living.insight
	sim.living.tick(sim, 1.0)
	var gained: float = sim.living.insight - insight
	var expected: float = float(sim.living.config["research"]["rate_per_minute"]) * 1.15 / 60.0
	check(is_equal_approx(gained, expected) or sim.living.insight >= float(sim.living.config["research"]["insight_cap"]), "scribes speed research insight")
	var market: Dictionary = place(sim, "market", 12, 8)
	staff(sim, market)
	sim.perks.refresh(sim, true)
	check(is_equal_approx(sim.perks.total("trade"), 0.1), "a staffed market raises town gold income")


func test_chapel() -> void:
	var sim = Sim.new()
	var chapel: Dictionary = place(sim, "chapel", 2, 2)
	staff(sim, chapel)
	sim.perks.refresh(sim, true)
	check(sim.perks.heal_at(sim, Vector2(3, 3)) > 2.0, "villagers by a staffed chapel heal much faster")
	check(sim.perks.heal_at(sim, Vector2(18, 14)) == 1.0, "villagers far from the chapel heal at the normal rate")


func test_caps_and_describe() -> void:
	var sim = Sim.new()
	for i in 5:
		var forge: Dictionary = place(sim, "forge", 1 + i * 3, 12)
		staff(sim, forge)
	sim.perks.refresh(sim, true)
	check(is_equal_approx(sim.perks.total("damage"), 0.3), "village-wide perks stop at their cap")
	var cottage: Dictionary = place(sim, "cottage", 4, 4)
	check(sim.perks.describe(sim, cottage).is_empty(), "buildings without a perk show no perk line")
	var building: Dictionary = place(sim, "workshop", 9, 4, true)
	check(sim.perks.describe(sim, building).contains("once finished"), "a site still being built says when its perk starts")
