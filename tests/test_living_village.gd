extends SceneTree
const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)

func step(sim, seconds: float) -> void:
	for i in ceili(seconds / 0.05): sim.tick(0.05)


func cell(living, tile: Vector2i) -> Dictionary:
	return living.cells.get(living.key(tile), {})


func _run() -> void:
	var sim = Sim.new()
	sim.units.clear()
	var living = sim.living
	living.walked(Vector2(2.1, 2.5), Vector2(2.1, 2.5), 0)
	check(living.cells.is_empty(), "standing and turning make no path")
	for i in 25: living.walked(Vector2(2.0, 2.5), Vector2(3.0, 2.5), i)
	check(absf(float(living.at(Vector2(2.5, 2.5))["wear"]) - 25.0 / 150.0) < 0.0001, "wear records distance not frames")
	for i in 125: living.walked(Vector2(2.0, 2.5), Vector2(3.0, 2.5), 100)
	check(float(living.at(Vector2(2.5, 2.5))["wear"]) > 0.999, "150 crossings establish a dirt path")
	check(not living.pave(sim, Vector2i(2, 2)), "paving is research locked")
	check(not sim.build("stone_quarry", 1, 1), "quarry is research locked")
	sim.xp = 100
	living.insight = 20
	check(living.research(sim, "stoneworking"), "Stoneworking pays once and starts")
	var wood: float = sim.resources["wood"]
	check(not living.research(sim, "stoneworking") and sim.resources["wood"] == wood, "active research cannot double charge")
	sim.paused = true
	step(sim, 5)
	check(living.remaining == 60, "pause stops research")
	sim.paused = false
	sim.raid_warning = true
	step(sim, 5)
	check(living.remaining == 60, "raid warning pauses research")
	sim.raid_warning = false
	step(sim, 61)
	check("stoneworking" in living.discoveries and living.active.is_empty(), "research finishes once")
	# 1,5 keeps the quarry off the worn 2,2 trail so paving's overlap rule stays intact.
	check(sim.build("stone_quarry", 1, 5), "research unlocks quarry before Stone costs")
	step(sim, 7)
	var quarry: Dictionary = sim.buildings.back()
	step(sim, 5)
	check(float(quarry["reserve"]) >= 5, "quarry produces real Stone on-site")
	check(sim.collect(int(quarry["id"])) >= 5 and sim.resources["stone"] >= 5, "Stone uses normal collection and capacity rules")
	check(not living.pave(sim, Vector2i(1, 5)), "paving still cannot overlap a building footprint")
	living.insight = 30
	sim.resources["stone"] = 39
	check(not living.research(sim, "road_masonry") and living.insight == 30, "insufficient Stone rejects research atomically")
	sim.resources["stone"] = 80
	check(living.research(sim, "road_masonry"), "Road Masonry starts after prerequisite and cost")
	step(sim, 91)
	check("road_masonry" in living.discoveries, "paving research completes")
	var stone: float = sim.resources["stone"]
	check(living.pave(sim, Vector2i(2, 2)), "established path can be paved")
	check(sim.resources["stone"] == stone - 8, "paving spends eight Stone")
	check(not living.pave(sim, Vector2i(2, 2)) and sim.resources["stone"] == stone - 8, "same segment cannot charge twice")
	check(not living.pave(sim, Vector2i(3, 2)), "unworn ground cannot be paved")
	check(is_equal_approx(living.speed_at(Vector2(2.5, 2.5)), 1.15), "friendly paved speed bonus")
	living.cells["4,4"] = {"wear": 0.7, "last": 0.0, "stone": false}
	sim.elapsed = 700
	step(sim, 2)
	check(float(cell(living, Vector2i(4, 4)).get("wear", 1.0)) < 0.7, "unused dirt regrows after active-time delay")
	check(float(cell(living, Vector2i(2, 2)).get("wear", 0.0)) > 0.999 and bool(cell(living, Vector2i(2, 2)).get("stone", false)), "stone roads do not decay")
	check(sim.raid_active and sim.enemies.size() == 2, "the elapsed jump really does trigger a scheduled raid")
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	check(float(state["version"]) == 3.0 and typeof(state["version"]) == TYPE_FLOAT, "JSON hands back the field version as a number")
	var restored = Sim.new()
	var accepted: bool = restored.restore_state(state)
	check(accepted, "version2 restores living state")
	if not accepted:
		printerr("Cannot continue: the version 2 snapshot was rejected")
		_report()
		return
	check(bool(cell(restored.living, Vector2i(2, 2)).get("stone", false)) and "road_masonry" in restored.living.discoveries, "road/research/Stone survive reload")
	check(bool(restored.raid_active) and restored.enemies.size() == sim.enemies.size(), "a mid-raid save keeps its raid phase")
	check(restored.enemies.size() == int(state["enemies"].size()), "hostiles survive the reload so the raid can finish")
	var quarry_id: int = int(sim.buildings.back()["id"])
	var old: Dictionary = state.duplicate(true)
	old["version"] = 1
	old.erase("living")
	old["resources"].erase("stone")
	old["buildings"] = old["buildings"].filter(func(b): return b["type"] != "stone_quarry")
	for unit: Dictionary in old["units"]:
		if int(unit["workplace"]) == quarry_id:
			unit["workplace"] = -1
			unit["post"] = -1
			unit["slot"] = 0
			unit["sx"] = -1.0
			unit["sy"] = -1.0
	check(restored.restore_state(old) and float(restored.resources["stone"]) == 0.0 and restored.living.cells.is_empty(), "v1 migration preserves old village and defaults new systems")
	check(float(restored.resources["wood"]) == float(old["resources"]["wood"]) and restored.units.size() == old["units"].size(), "migration never resets stock or roster")
	check(restored.completed_quests.size() == old["completed_quests"].size() and restored.living.insight == 0.0, "migration keeps quest progress and starts Insight at zero")
	var bad: Dictionary = state.duplicate(true)
	bad["living"]["cells"]["-1,0"] = {"wear": 1, "last": 0, "stone": false}
	check(not restored.restore_state(bad), "invalid saved road coordinates rejected")
	bad = state.duplicate(true)
	bad["living"]["insight"] = INF
	check(not restored.restore_state(bad), "nonfinite research rejected")
	bad = state.duplicate(true)
	bad["living"]["discoveries"] = ["road_masonry"]
	check(not restored.restore_state(bad), "saved research cannot bypass prerequisites")
	bad = state.duplicate(true)
	bad["living"]["cells"]["2,2"]["stone"] = 1
	check(not restored.restore_state(bad), "non-boolean road flag rejected")
	bad = state.duplicate(true)
	bad["living"]["cells"]["2, 2"] = {"wear": 1.0, "last": 0.0, "stone": true}
	check(not restored.restore_state(bad), "road keys must be canonical coordinates")
	bad = state.duplicate(true)
	bad["living"].erase("cells")
	check(not restored.restore_state(bad), "a missing living section is rejected instead of crashing")
	bad = state.duplicate(true)
	bad["living"]["cells"] = {}
	bad["living"]["active"] = ""
	bad["living"]["remaining"] = 12.0
	check(not restored.restore_state(bad), "saved research time without an active project is rejected")
	check(restored.restore_state(state), "the untouched save still loads after rejected attempts")
	var empty = Sim.new()
	empty.buildings.clear()
	empty.units.clear()
	for x in range(2, 12): empty.living.cells["%d,3" % x] = {"wear": 1.0, "last": 0.0, "stone": true}
	empty.living.navigation_revision = 1
	var road_route: Array[Vector2i] = empty.route(Vector2i(2, 3), Vector2i(11, 3))
	check(road_route.size() == 10, "roads do not invent long detours")
	var a: Dictionary = {"id": 500, "type": "warrior", "level": 1, "x": 2.5, "y": 3.5, "phase": "idle"}
	empty._walk(a, Vector2(3.5, 3.5), 0.05)
	check(is_equal_approx(float(a["x"]) - 2.5, 1.5 * 1.15 * 0.05), "bonus changes real friendly movement")
	var enemy: Dictionary = {"id": 501, "type": "raider", "x": 2.5, "y": 3.5, "phase": "idle"}
	var before: Dictionary = empty.living.cells.duplicate(true)
	empty._walk(enemy, Vector2(3.5, 3.5), 0.05, true)
	check(is_equal_approx(float(enemy["x"]) - 2.5, 1.2 * 0.05), "enemy has no road speed bonus")
	check(empty.living.cells == before, "enemies do not wear friendly paths")
	_report()


func _report() -> void:
	print("LIVING_VILLAGE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	var file := FileAccess.open("res://docs/living_verification.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}, "\t"))
		file.close()
	else:
		printerr("Could not write res://docs/living_verification.json")
	quit(0 if failures.is_empty() else 1)
