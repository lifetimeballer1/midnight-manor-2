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
	check(sim.has_method("deliver") and sim.has_method("prestige"), "campaign delivery and prestige have real commands")
	if sim.has_method("deliver") and sim.has_method("prestige"):
		test_delivery()
		test_prestige()
	test_gate()
	check(sim.has_method("accept_contract"), "contracts capture the real acceptance baseline")
	if sim.has_method("accept_contract"): test_contracts()
	test_enemy_roles()
	var refinery = Sim.new()
	refinery._refine({"perSec": 1.0, "in": {"wood": 2}, "out": {"plate": 1}}, 1.0)
	check(refinery._objective_value({"kind": "gather", "resource": "plate"}) == 1.0, "banked refinery output advances authored material-gathering missions")
	var fractional = Sim.new()
	fractional._refine({"perSec": 1.0, "in": {"wood": 2}, "out": {"plate": 1}}, 0.05)
	check(is_equal_approx(fractional.resources.get("plate", 0.0), 0.05), "20Hz refinery ticks retain fractional output rather than flooring it away")
	print("CAMPAIGN_ACTIONS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func test_enemy_roles() -> void:
	var sim = Sim.new()
	var defender: Dictionary = sim.units[0]
	defender["x"] = 6.0
	defender["y"] = 4.0
	defender["hold"] = true
	sim.raid_active = true
	sim.enemies.append({"id": sim._id(), "type": "raider", "role": "archer", "x": 4.0, "y": 4.0, "hp": 100.0, "max_hp": 100.0, "cooldown": 0.0, "phase": "idle"})
	sim.tick(1.0)
	check(defender["hp"] < defender["max_hp"], "enemy archer uses its authored range rather than melee distance")
	var scout: Dictionary = {"id": 900, "type": "raider", "role": "scout", "x": 1.5, "y": 1.5, "phase": "idle"}
	var breaker: Dictionary = {"id": 901, "type": "raider", "role": "breaker", "x": 1.5, "y": 1.5, "phase": "idle"}
	sim._walk(scout, Vector2(5.5, 1.5), 1.0, true)
	sim._walk(breaker, Vector2(5.5, 1.5), 1.0, true)
	check(float(scout["x"]) > float(breaker["x"]), "enemy roles have distinct authored movement speeds")


func test_delivery() -> void:
	var sim = Sim.new()
	var wood: float = sim.resources["wood"]
	check(not sim.deliver("wood", 80), "supplies require a scouted frontier")
	sim.chronicle.act = 4
	sim.chronicle.set_region("starwatch-ridge", "scouted")
	check(sim.deliver("wood", 80), "legal delivery sends actual stocked goods")
	check(sim.resources["wood"] == wood - 80 and sim.raid_stats["delivered"]["wood"] == 80, "delivery charges once and advances its authored counter")
	check(not sim.deliver("wood", -1) and not sim.deliver("unknown", 1) and not sim.deliver("wood", 100000), "invalid and unaffordable deliveries are rejected")
	var restored = Sim.new()
	check(restored.restore_state(JSON.parse_string(JSON.stringify(sim.export_state()))) and restored.raid_stats["delivered"]["wood"] == 80, "delivery progress survives JSON reload")


func test_prestige() -> void:
	var sim = Sim.new()
	sim.chronicle.act = 8
	sim._quest_record("the-bell-remembers")
	check(sim.chronicle.is_unlocked("bell-tower"), "the prestige mission introduces its required Bell Tower before its reward")
	var unit: Dictionary = sim.units[0]
	check(not sim.prestige(int(unit["id"])), "a recruit cannot prestige")
	var bell: Dictionary = sim._new_building("bell-tower", 1, 1, false)
	sim.buildings.append(bell)
	unit["level"] = 25
	unit["max_hp"] = sim._stat(unit, "hp")
	unit["hp"] = unit["max_hp"]
	check(sim.prestige(int(unit["id"])), "a level-25 veteran can prestige at a completed Bell Tower")
	check(unit["level"] == 1 and unit.get("prestige", 0) == 1 and sim.raid_stats["prestige"] == 1, "prestige resets training while preserving one honor and campaign credit")
	check(unit["max_hp"] > sim.troop_specs[unit["type"]]["base"]["hp"], "prestige keeps a tangible veteran benefit")
	check(not sim.prestige(int(unit["id"])) and sim.raid_stats["prestige"] == 1, "prestige cannot be repeated without retraining")
	var restored = Sim.new()
	check(restored.restore_state(JSON.parse_string(JSON.stringify(sim.export_state()))), "prestiged unit state remains saveable")


func test_gate() -> void:
	var sim = Sim.new()
	sim.chronicle.act = 8
	sim._quest_record("dawn-of-the-manner")
	check(sim.chronicle.is_unlocked("dawn-gate"), "Act VIII introduces the Dawn Gate rather than requiring its own completion reward")
	var objective: Dictionary = {"kind": "construct_great_work", "id": "dawn-gate", "count": 1}
	check(sim._objective_value(objective) == 0.0, "an unlock is not a physically constructed Great Work")
	var gate: Dictionary = sim._new_building("dawn-gate", 1, 1, true)
	sim.buildings.append(gate)
	check(sim._objective_value(objective) == 0.0, "construction scaffolding cannot complete the Great Work objective")
	gate["remaining"] = 0.0
	check(sim._objective_value(objective) == 1.0, "a live completed Dawn Gate satisfies its physical objective")


func test_contracts() -> void:
	var sim = Sim.new()
	var offer: Dictionary = sim.chronicle.board_offer()[0]
	var id: String = str(offer["id"])
	var objective: Dictionary = offer["template"]["objective"]
	if objective["kind"] == "gather": sim.gathered[objective["resource"]] = 10000.0
	check(sim.accept_contract(id), "posted contract can be accepted through the simulation")
	sim._quest_tick()
	check(sim.chronicle.board_contract(id)["progress"] == 0.0, "historical output does not instantly complete a newly accepted contract")
	if objective["kind"] == "gather":
		var resource: String = objective["resource"]
		for b: Dictionary in sim.buildings:
			if str(sim.building_specs[b["type"]].get("production", "")) == resource:
				b["reserve"] = float(objective["amount"])
				sim.collect(int(b["id"]))
				break
		sim._quest_tick()
		check(sim.chronicle.board_complete(id), "new real collections complete their contract")
		check(not sim.chronicle.board_accept(id).is_empty(), "claimed contract cannot be immediately farmed again")
		sim.chronicle.board_tick(240.0)
		check(sim.chronicle.board["done"].is_empty(), "board refresh opens the next bounded repeatable contract cycle")
