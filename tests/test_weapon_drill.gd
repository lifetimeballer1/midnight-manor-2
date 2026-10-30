extends SceneTree

# Weapon Drill (The Manor Endures, C4): a war upgrade with rising prices, paid from the stores,
# opened by the Chronicle, that makes defences hit harder in a raid, counts toward defence power,
# and is saved with the village.
const Sim = preload("res://scripts/game/village_sim.gd")
const Drill = preload("res://scripts/game/village_drill.gd")
const Threat = preload("res://scripts/game/village_threat.gd")
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
	sim.next_raid_at = 1.0e9
	sim.chronicle.act = 1
	check(not sim.drill.reason(sim).is_empty(), "the drill yard waits for the Chronicle")
	sim.chronicle.act = Drill.OPENS_AT_ACT
	for r: String in ["gold", "wood", "food"]:
		sim.resources[r] = 0.0
	check(not sim.drill.train(sim) and sim.drill.level == 0, "an empty store buys no drill")
	var first: Dictionary = sim.drill.cost()
	for r: String in first:
		sim.resources[r] = float(first[r])
	check(sim.drill.train(sim) and sim.drill.level == 1, "a paid drill raises the level")
	for r: String in first:
		check(float(sim.resources[r]) < 0.5, "the drill spent its %s" % r)
	var second: Dictionary = sim.drill.cost()
	check(float(second["gold"]) > float(first["gold"]) * 1.5, "each level costs more (%d then %d gold)" % [first["gold"], second["gold"]])
	var deep = Drill.new()
	deep.level = 20
	check(float(deep.cost()["gold"]) > 1000000.0, "late levels ask for millions, a place for big numbers to go")

	# Drilled defences hit harder and count for more defence power.
	var plain = Sim.new()
	var power: float = Threat.defence_power(plain)
	plain.drill.level = 5
	check(Threat.defence_power(plain) > power, "the drill raises defence power")
	var stats: Dictionary = {"damage": 20.0, "range": 4.0}
	check(is_equal_approx(float(plain.drill.drilled(stats)["damage"]), 30.0), "drill 5 adds half again to a weapon's damage")
	check(is_equal_approx(float(stats["damage"]), 20.0), "the building's own data is left alone")
	plain.drill.level = 0
	check(plain.drill.drilled(stats) == stats, "no drill, no change")

	# In a raid: the same raider takes more from a drilled tower.
	var hits: Array[float] = []
	for level in [0, 5]:
		var raid = Sim.new()
		raid.next_raid_at = 1.0e9
		raid.drill.level = level
		var tower: Dictionary = {}
		for b: Dictionary in raid.buildings:
			if str(b["type"]) == "tower":
				tower = b
		for u: Dictionary in raid.units:
			u["hp"] = 0.0
		var at: Vector2 = raid.center(tower)
		raid.raid_active = true
		raid.home_raid.begin(raid)
		raid.enemies.clear()
		raid.enemies.append({"id": 9001, "type": "raider", "role": "raider", "raids_resources": false, "faction": "thornband",
			"x": at.x + 1.5, "y": at.y, "hp": 10000.0, "max_hp": 10000.0, "phase": "walk", "cooldown": 99.0})
		tower["cooldown"] = 0.0
		raid._raid_tick(0.05)
		hits.append(10000.0 - float(raid.enemies[0]["hp"]))
	check(hits[0] > 0.0 and hits[1] > hits[0] * 1.4, "a drilled tower hits harder (%.0f vs %.0f)" % [hits[1], hits[0]])

	# Saved with the village.
	var saved = Sim.new()
	saved.drill.level = 7
	var copy = Sim.new()
	check(copy.restore_state(JSON.parse_string(JSON.stringify(saved.export_state()))) and copy.drill.level == 7, "the drill level survives a reload")
	var old: Dictionary = JSON.parse_string(JSON.stringify(saved.export_state()))
	old.erase("drill")
	var older = Sim.new()
	check(older.restore_state(old) and older.drill.level == 0, "a save from before the drill starts at 0")
	print("WEAPON_DRILL ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
