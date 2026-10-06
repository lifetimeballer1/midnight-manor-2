extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		printerr("FAIL ", text)


func building(sim, type_name: String) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if b["type"] == type_name:
			return b
	return {}


func step(sim, seconds: float) -> void:
	for tick in ceili(seconds / 0.05):
		sim.tick(0.05)


func _run() -> void:
	var sim = Sim.new()
	check(sim.buildings.size() == 9 and sim.units.size() == 5, "original starting layout and roster")
	check(sim.resources["wood"] == 320 and sim.resources["food"] == 180 and sim.resources["gold"] == 210, "original starting resources")
	var farm: Dictionary = building(sim, "farm")
	sim.units.clear()
	var before: float = float(sim.resources["food"])
	step(sim, 5)
	check(is_equal_approx(float(farm["reserve"]), 10), "farm produces two per second")
	check(sim.resources["food"] == before, "passive output does not bank automatically")
	farm["reserve"] = 499
	step(sim, 1)
	check(farm["reserve"] == 500, "on-site cap holds at500")
	sim.paused = true
	var time: float = sim.elapsed
	step(sim, 3)
	check(sim.elapsed == time, "pause freezes authoritative clock")
	sim.paused = false
	sim.resources["food"] = sim.storage_cap("food") - 3
	check(sim.collect(int(farm["id"])) == 3 and farm["reserve"] == 497, "partial collection preserves overflow")
	check(sim.collect(int(farm["id"])) == 0 and farm["reserve"] == 497, "full stores cannot double-claim")
	check(sim.gathered["food"] == 3, "only banked harvest counts toward goals")
	sim = Sim.new()
	before = float(sim.resources["wood"])
	check(sim.build_reason("farm", 1, 1).is_empty(), "valid placement preview")
	check(sim.resources["wood"] == before, "preview never charges")
	check(not sim.build("farm", 19, 15) and sim.resources["wood"] == before, "out-of-bounds spends nothing")
	check(not sim.build("farm", 9, 7) and sim.resources["wood"] == before, "overlap spends nothing")
	check(sim.build("farm", 1, 1), "confirmed build succeeds")
	check(sim.resources["wood"] == before - 55, "build charges original55wood exactly")
	var new_farm: Dictionary = sim.buildings.back()
	check(new_farm["remaining"] == 4, "original four-second build time")
	step(sim, 4.1)
	check(new_farm["remaining"] == 0 and "second-field" in sim.completed_quests, "construction and first quest complete")
	var rewarded_xp: int = sim.xp
	step(sim, 2)
	check(sim.xp == rewarded_xp, "quest XP is not repeat-farmable")
	var old_position := Vector2(int(new_farm["x"]), int(new_farm["y"]))
	check(sim.move_building(int(new_farm["id"]), 2, 2), "relocation ignores own footprint")
	check(Vector2(int(new_farm["x"]), int(new_farm["y"])) != old_position, "relocation moves real state")
	sim.resources["wood"] = 500
	check(sim.building_cost("farm", 2)["wood"] == 110, "friendly tier2 price stays twice base")
	check(sim.upgrade(int(new_farm["id"])), "tier2 upgrade succeeds")
	before = float(sim.resources["wood"])
	check(not sim.upgrade(int(new_farm["id"])) and sim.resources["wood"] == before, "busy upgrade refuses duplicate payment")
	step(sim, 4.1)
	check(new_farm["tier"] == 2 and sim.reserve_cap(new_farm) == 1000, "tier2 visual state and reserve cap")
	check(sim.building_cost("farm", 3)["lumber"] == 30, "tier3 worked-goods price retained")
	sim = Sim.new()
	var farmer: Dictionary = {}
	for u: Dictionary in sim.units:
		if u["type"] == "farmer":
			farmer = u
	check(not sim.assign(int(farmer["id"]), int(building(sim, "mine")["id"])), "wrong-role assignment rejected")
	check(sim.assign(int(farmer["id"]), int(building(sim, "farm")["id"])), "matching worker assignment succeeds")
	# Compare one production tick before any collector arrival/delivery.
	farm = building(sim, "farm")
	farm["reserve"] = 0
	sim.tick(0.05)
	check(is_equal_approx(float(farm["reserve"]), 0.125), "matching posted worker grants1.25production")
	check(sim.order_unit(int(farmer["id"]), 1.5, 1.5), "worker explicit order accepted")
	farm["reserve"] = 0
	sim.tick(0.05)
	check(is_equal_approx(float(farm["reserve"]), 0.1), "ordered-away worker loses productivity boost")
	sim.resources["food"] = 0
	before = float(sim.resources["gold"])
	check(not sim.recruit("fisherman") and sim.resources["gold"] == before, "unaffordable hire does not partially charge")
	sim.resources["food"] = 180
	check(sim.recruit("fisherman"), "recruit eighth-role asset with original costs")
	check(not sim.recruit("warrior") and sim.units.size() == 6, "free-bed cap is enforced")
	var warrior: Dictionary = sim.units[0]
	check(sim.train(int(warrior["id"])) and warrior["level"] == 2 and warrior["max_hp"] > 140, "original training curve increases stats")
	sim.buildings.clear()
	for y in 16:
		sim.buildings.append(sim._new_building("wall", 10, y, false))
	check(sim.route(Vector2i(1, 1), Vector2i(15, 1)).is_empty(), "complete wall line blocks routes")
	sim.buildings[8]["type"] = "gate"
	var allied_path: Array[Vector2i] = sim.route(Vector2i(1, 8), Vector2i(15, 8))
	check(not allied_path.is_empty(), "friendly gate gives valid path")
	check(sim.route(Vector2i(1, 8), Vector2i(15, 8), true).is_empty(), "enemy gate stays blocked")
	check(sim.route(Vector2i(3, 2), Vector2i(3, 2)) == [Vector2i(3, 2)], "start-equals-goal route")
	check(sim.route(Vector2i(-1, 0), Vector2i(3, 2)).is_empty(), "invalid route bounds")
	for index in range(1, allied_path.size()):
		check((allied_path[index] - allied_path[index - 1]).length_squared() == 1, "path has four-neighbour steps")
	sim = Sim.new()
	check(sim.start_raid(), "test raid starts a real warning")
	check(not sim.move_building(int(building(sim, "farm")["id"]), 1, 1), "warning prohibits relocation")
	step(sim, 3.2)
	check(sim.raid_active and sim.enemies.size() == 2, "first wave spawns two perimeter raiders")
	# Force enemies into range to exercise real unit/tower combat, not clearing them manually.
	for enemy: Dictionary in sim.enemies:
		enemy["x"] = 6.0
		enemy["y"] = 7.0
		enemy["hp"] = 10
	step(sim, 2)
	check(not sim.raid_active and sim.enemies.is_empty(), "combat damage resolves actual victory")
	check(sim.next_raid_at >= sim.elapsed + 235, "victory schedules recovery")
	check(float(sim.resources["gold"]) > 210 or not sim.pending_rewards.is_empty(), "victory salvage earned or safely held")
	sim.next_raid_at = 300
	sim.start_raid()
	step(sim, 3.2)
	var hall: Dictionary = building(sim, "hall")
	hall["hp"] = 0
	warrior["hp"] = 0
	sim.units[0]["hp"] = 0
	sim.tick(0.05)
	check(not sim.raid_active and sim.enemies.is_empty(), "manor defeat ends raid")
	check(sim.units[0]["hp"] > 0, "fallen defender revives after raid")
	check(sim.repair(int(hall["id"])) and hall["hp"] > 0, "ruin repaired using real resources")
	sim.units[0]["carry"] = 7
	sim.units[0]["carry_resource"] = "wood"
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	var restored = Sim.new()
	check(restored.restore_state(state), "primitive JSON save roundtrip accepted")
	check(restored.units[0]["carry"] == 7 and is_equal_approx(restored.elapsed, sim.elapsed), "carried goods and active time survive")
	var bad: Dictionary = state.duplicate(true)
	bad["resources"]["wood"] = -5
	var stable: String = JSON.stringify(restored.export_state())
	check(not restored.restore_state(bad) and JSON.stringify(restored.export_state()) == stable, "bad state rejected without partial mutation")
	bad = state.duplicate(true)
	bad["units"][0]["order"] = [INF, 3]
	check(not restored.restore_state(bad), "nonfinite unit order rejected")
	var path: String = "user://core-loop-test-%d.json" % Time.get_ticks_usec()
	check(sim.save_game(path), "disk save succeeds")
	check(restored.load_game(path), "disk save reload succeeds")
	check(not sim.save_game("user://missing-parent-for-test/village.json") and "failed" in sim.notice.to_lower(), "save failures are visible")
	DirAccess.remove_absolute(path)
	check(sim.quests.size() == 44, "every authored mission is loaded across all ten acts")
	sim = Sim.new()
	sim.start_raid()
	var started_at: int = Time.get_ticks_msec()
	step(sim, 100)
	check(not sim.raid_active and not sim.raid_warning and sim.wave == 1, "natural perimeter wave resolves without moving enemies artificially")
	print("NATURAL_RAID_CPU_MS ", Time.get_ticks_msec() - started_at)
	# A held fighter still defends in-range; hold does not turn off combat.
	sim = Sim.new()
	warrior = sim.units[0]
	sim.order_unit(int(warrior["id"]), float(warrior["x"]), float(warrior["y"]), true)
	sim.enemies.append({"id": sim._id(), "type": "raider", "x": float(warrior["x"]) + 0.2, "y": warrior["y"], "hp": 80.0, "max_hp": 80.0, "phase": "idle", "cooldown": 0.0})
	sim.raid_active = true
	sim.tick(0.05)
	check(sim.enemies[0]["hp"] < 80, "holding defender attacks within range")
	bad = sim.export_state()
	bad["buildings"][0]["x"] = 9.25
	check(not sim.restore_state(bad), "fractional building coordinates rejected")
	bad = sim.export_state()
	bad["units"][0]["carry"] = 3
	bad["units"][0]["carry_resource"] = "unknown"
	check(not sim.restore_state(bad), "unknown carried resource rejected")
	sim = Sim.new()
	sim.resources["wood"] = 3000
	sim.resources["food"] = 2000
	sim.resources["gold"] = 1000
	check(sim.build("farm", 1, 1) and sim.build("pond", 1, 5) and sim.build("cottage", 1, 9) and sim.build("pasture", 15, 11), "original quest chain has valid build footprints")
	step(sim, 6)
	check(sim.recruit("fisherman"), "first-cast profession can be recruited after cottage")
	step(sim, 0.3)
	sim.recruit("builder")
	sim.recruit("archer")
	step(sim, 0.2)
	building(sim, "lumber")["reserve"] = 100
	sim.collect(int(building(sim, "lumber")["id"]))
	step(sim, 0.2)
	for role in ["farmer", "lumberjack", "miner", "shepherd"]:
		check(sim.recruit(role), "full-crew roster fits cottage housing: " + str(role))
	step(sim, 0.2)
	building(sim, "mine")["reserve"] = 400
	sim.collect(int(building(sim, "mine")["id"]))
	step(sim, 0.2)
	check(sim.upgrade(int(building(sim, "pasture")["id"])), "pasture tier2 goal is attainable")
	step(sim, 4.2)
	var act1_ids: Array[String] = ["second-field", "still-water", "first-cast", "roof-for-night", "every-hand", "the-moon-dial"]
	var resolved: int = 0
	for quest_id in act1_ids:
		if quest_id in sim.completed_quests:
			resolved += 1
	check(resolved == act1_ids.size(), "every Act I mission resolves through actual command APIs")
	check(sim.chronicle.act == 1 and not sim.chronicle.is_unlocked("orrery"), "Act II and beyond stay closed while Act I is unfinished")
	check(not "new-blood" in sim.completed_quests, "an Act II objective cannot complete early")
	# Finishing Act I opens Act II, and the Act II objectives bank on their own.
	check(sim.build("grove", 5, 13), "Act I final mission builds what it introduces")
	step(sim, 4.2)
	check("moon-orchard" in sim.completed_quests, "the Act I mission closes on its own objective")
	check(sim.chronicle.act == 2, "campaign advances to Act II when Act I is finished")
	check(sim.chronicle.act_name(2) == "II / A Village Worth Keeping", "act naming is readable in the UI")
	var act2_ids: Array[String] = ["new-blood", "east-field", "full-crew"]
	var resolved2: int = 0
	for quest_id in act2_ids:
		if quest_id in sim.completed_quests:
			resolved2 += 1
	check(resolved2 == act2_ids.size(), "Act II missions complete once the act opens")
	var complete_xp: int = sim.xp
	step(sim, 2)
	check(sim.xp == complete_xp, "completed full quest chain does not repeat XP")
	path = "user://unreadable-save-test-%d.json" % Time.get_ticks_usec()
	var corrupt_file := FileAccess.open(path, FileAccess.WRITE)
	corrupt_file.store_string('{"version":9}')
	corrupt_file.close()
	check(not sim.save_game(path) and FileAccess.get_file_as_string(path) == '{"version":9}', "autosave refuses to overwrite an unreadable existing village")
	DirAccess.remove_absolute(path)
	sim = Sim.new()
	sim.units.clear()
	farm = building(sim, "farm")
	farm["reserve"] = 550
	sim.tick(0.05)
	check(farm["reserve"] == 550, "loaded over-cap on-site stock is never discarded")
	bad = sim.export_state()
	bad["buildings"][1]["x"] = bad["buildings"][0]["x"]
	bad["buildings"][1]["y"] = bad["buildings"][0]["y"]
	check(not sim.restore_state(bad), "corrupt overlapping saved footprints rejected")
	bad = sim.export_state()
	bad["raid_active"] = true
	bad["raid_warning"] = true
	check(not sim.restore_state(bad), "inconsistent saved raid phase rejected")
	# Command & Control: atomic straight-row placement and connected row upgrading.
	var row_sim = Sim.new()
	row_sim.buildings.clear()
	row_sim.resources["wood"] = 5000
	row_sim.resources["food"] = 5000
	row_sim.resources["gold"] = 5000
	row_sim.resources["lumber"] = 5000
	row_sim.resources["stone"] = 5000
	row_sim.xp = 10000
	row_sim.chronicle.grant("wall", "test")
	var row_tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]
	var row_wood: float = float(row_sim.resources["wood"])
	var one_wall_wood: int = int(row_sim.building_cost("wall").get("wood", 0))
	check(row_sim.build_row_reason("wall", row_tiles).is_empty(), "straight wall row previews as one valid atomic command")
	check(row_sim.build_row("wall", row_tiles), "wall row confirms as one command")
	check(row_sim.buildings.size() == 4, "wall row creates every previewed segment")
	check(is_equal_approx(float(row_sim.resources["wood"]), row_wood - one_wall_wood * 4), "wall row charges the full row exactly once")
	var stable_row_count: int = row_sim.buildings.size()
	var stable_row_wood: float = float(row_sim.resources["wood"])
	var broken_row: Array[Vector2i] = [Vector2i(6, 1), Vector2i(8, 1)]
	check(not row_sim.build_row_reason("wall", broken_row).is_empty(), "gapped wall row is rejected in preview")
	check(not row_sim.build_row("wall", broken_row) and row_sim.buildings.size() == stable_row_count and is_equal_approx(float(row_sim.resources["wood"]), stable_row_wood), "invalid wall row spends nothing and builds nothing")
	for wall: Dictionary in row_sim.buildings:
		wall["remaining"] = 0.0
	var row_ids: Array[int] = row_sim.wall_row(int(row_sim.buildings[1]["id"]))
	check(row_ids.size() == 4, "connected wall row is discovered from any middle segment")
	check(row_sim.upgrade_wall_row_reason(int(row_sim.buildings[1]["id"])).is_empty(), "whole connected wall row can validate one upgrade")
	check(row_sim.upgrade_wall_row(int(row_sim.buildings[1]["id"])), "wall row upgrades as one command")
	var tier_two: int = 0
	for wall: Dictionary in row_sim.buildings:
		if int(wall["tier"]) == 2 and float(wall["remaining"]) > 0.0:
			tier_two += 1
	check(tier_two == 4, "row upgrade advances every connected segment together")

	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "Core-loop simulation, commands, pathfinding, raid outcomes, original11quests and versioned save checks."}
	var report_file := FileAccess.open("res://docs/village_verification.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("VILLAGE_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
