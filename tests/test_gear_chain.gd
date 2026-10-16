extends SceneTree

# The gear chain: pastures give hides, a staffed Tannery cures leather, a staffed Forge makes arms
# from plate and lumber, and veteran troops need that gear to be hired.
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
	test_hides_and_leather()
	test_forge()
	test_hiring()
	test_saves()
	print("GEAR_CHAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	for u: Dictionary in sim.units:
		u["hold"] = true
	return sim


func staff(sim, b: Dictionary, role: String) -> void:
	sim._add_unit(role)
	var u: Dictionary = sim.units.back()
	u["workplace"] = int(b["id"])
	u["hold"] = true


func run(sim, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		sim.gear.tick(sim, 0.5)
		t += 0.5


func test_hides_and_leather() -> void:
	var sim = fresh()
	var pasture: Dictionary = sim._new_building("pasture", 12, 3, false)
	sim.buildings.append(pasture)
	run(sim, 20.0)
	check(int(sim.resources.get("hides", 0)) >= 2, "a pasture gives hides beside its food (%s)" % sim.resources.get("hides", 0))
	var tannery: Dictionary = sim._new_building("tannery", 15, 3, false)
	sim.buildings.append(tannery)
	sim.resources["hides"] = 10.0
	run(sim, 8.0)
	check(int(sim.resources.get("leather", 0)) == 0, "an empty Tannery cures nothing")
	staff(sim, tannery, "leatherworker")
	var hides: float = float(sim.resources["hides"])
	run(sim, 8.0)
	check(int(sim.resources.get("leather", 0)) >= 1 and float(sim.resources["hides"]) < hides + 3.0, "a staffed Tannery cures hides into leather")
	check(sim.gear.describe(sim, tannery).begins_with("Makes 1 Leather from 2 Hides"), "the Tannery card names its recipe")


func test_forge() -> void:
	var sim = fresh()
	var forge: Dictionary = sim._new_building("forge", 12, 3, false)
	sim.buildings.append(forge)
	staff(sim, forge, "weaponsmith")
	sim.resources["plate"] = 3.0
	sim.resources["lumber"] = 0.0
	run(sim, 20.0)
	check(int(sim.resources.get("arms", 0)) == 0 and float(sim.resources["plate"]) == 3.0, "without lumber the Forge waits and spends nothing")
	sim.resources["lumber"] = 10.0
	run(sim, 30.0)
	check(int(sim.resources.get("arms", 0)) == 3 and float(sim.resources["plate"]) == 0.0, "with plate and lumber the Forge makes arms, one plate each")


func test_hiring() -> void:
	var sim = fresh()
	check(sim.gear.hire_cost(sim, "warrior") == sim.troop_specs["warrior"]["recruitCost"], "a warrior still costs only Food and Gold")
	var cost: Dictionary = sim.gear.hire_cost(sim, "halberdier")
	check(int(cost.get("arms", 0)) == 2 and int(cost.get("food", 0)) == int(sim.troop_specs["halberdier"]["recruitCost"]["food"]), "a halberdier also needs two Arms")
	var barracks: Dictionary = sim._new_building("barracks", 12, 3, false)
	sim.buildings.append(barracks)
	for r: String in ["food", "gold"]:
		sim.resources[r] = 999.0
	sim.living.discoveries.append("drill")
	var reason: String = sim.gear.gear_reason(sim, "halberdier")
	check(reason.begins_with("Needs 2 Arms"), "without arms the reason names them and the Forge (%s)" % reason)
	sim.resources["arms"] = 5.0
	check(sim.gear.gear_reason(sim, "halberdier").is_empty(), "with arms in store nothing is missing")
	# recruit() spends the gear when the role is open to hire.
	if sim.recruit_reason("halberdier").is_empty():
		var units: int = sim.units.size()
		check(sim.recruit("halberdier") and sim.units.size() == units + 1 and float(sim.resources["arms"]) == 3.0, "hiring a halberdier spends its arms")
	else:
		sim.resources["arms"] = 0.0
		check(not sim.recruit_reason("halberdier").is_empty(), "a halberdier locked by the story stays locked")


func test_saves() -> void:
	var sim = fresh()
	sim.resources["arms"] = 4.0
	sim.resources["leather"] = 2.0
	sim.resources["hides"] = 7.0
	var state: Variant = JSON.parse_string(JSON.stringify(sim.export_state()))
	var loaded = Sim.new()
	check(loaded.restore_state(state) and int(loaded.resources["arms"]) == 4 and int(loaded.resources["hides"]) == 7, "gear in store survives a save")
