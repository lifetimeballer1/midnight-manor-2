extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		printerr("FAIL ", text)


func step(sim, seconds: float) -> void:
	for tick in ceili(seconds / 0.05):
		sim.tick(0.05)


func building(sim, type_name: String) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if b["type"] == type_name:
			return b
	return {}


func find_build_spot(sim, type_name: String) -> Vector2i:
	var size: int = int(sim.building_specs[type_name]["size"])
	for y in range(0, 17 - size):
		for x in range(0, 21 - size):
			if sim.build_reason(type_name, x, y).is_empty():
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func find_wall_line(sim, length: int = 3) -> Array[Vector2i]:
	for y in 16:
		for x in range(0, 21 - length):
			var start := Vector2i(x, y)
			var finish := Vector2i(x + length - 1, y)
			if sim.wall_line_reason("wall", start, finish).is_empty():
				return [start, finish]
	return []


func _unlock_fortress(sim) -> void:
	sim.xp = 900
	sim.resources["wood"] = 10000
	sim.resources["food"] = 10000
	sim.resources["gold"] = 10000
	sim.resources["lumber"] = 10000
	sim.resources["stone"] = 10000
	sim.living.insight = 100
	sim.living.discoveries.assign([
		"stoneworking", "road_masonry", "fortifications",
		"gate_engineering", "watchtowers", "defensive_logistics"
	])


func _run() -> void:
	var sim = Sim.new()

	# Research is a real chain and old saves can still omit the new discoveries.
	check(sim.living.config["research"]["nodes"].size() == 6, "six-node research tree is loaded")
	check(sim.living.config["research"]["nodes"]["fortifications"]["requires"] == "road_masonry", "Fortifications follows Road Masonry")
	check(sim.living.config["research"]["nodes"]["gate_engineering"]["requires"] == "fortifications", "Gate Engineering follows Fortifications")
	check(sim.living.config["research"]["nodes"]["watchtowers"]["requires"] == "gate_engineering", "Watchtower Doctrine follows Gate Engineering")
	check(sim.living.config["research"]["nodes"]["defensive_logistics"]["requires"] == "watchtowers", "Defensive Logistics closes the chain")
	check("Research Fortifications" in sim.build_reason("guard_post", 0, 0), "Guard Post is tech-gated before Fortifications")
	check("Research Fortifications" in sim.recruit_reason("mason"), "Mason is tech-gated before Fortifications")
	check("Research Gate Engineering" in sim.recruit_reason("warden"), "Warden is tech-gated before Gate Engineering")
	check("Research Watchtower Doctrine" in sim.recruit_reason("longbowman"), "Longbowman is tech-gated before Watchtower Doctrine")

	_unlock_fortress(sim)

	# Wall-line placement is atomic, cardinal and paid once for the whole run.
	var line: Array[Vector2i] = find_wall_line(sim, 3)
	check(line.size() == 2, "a free three-segment wall line can be found")
	if line.size() == 2:
		var before_walls: int = 0
		for b: Dictionary in sim.buildings:
			if b["type"] == "wall":
				before_walls += 1
		var one_cost: Dictionary = sim.building_cost("wall")
		var before_wood: float = float(sim.resources["wood"])
		check(sim.wall_line_tiles(line[0], line[1]).size() == 3, "wall drag resolves to three cardinal tiles")
		check(sim.build_wall_line("wall", line[0], line[1]), "wall line builds atomically")
		var after_walls: int = 0
		var first_wall: Dictionary = {}
		for b: Dictionary in sim.buildings:
			if b["type"] == "wall":
				after_walls += 1
				if first_wall.is_empty() and Vector2i(int(b["x"]), int(b["y"])) in sim.wall_line_tiles(line[0], line[1]):
					first_wall = b
		check(after_walls == before_walls + 3, "wall line creates exactly three segments")
		check(is_equal_approx(float(sim.resources["wood"]), before_wood - float(one_cost.get("wood", 0)) * 3.0), "wall line charges the full run exactly once")
		step(sim, 6.0)
		var connected: Array[Dictionary] = sim._connected_barriers(int(first_wall["id"]))
		check(connected.size() >= 3, "cardinal wall segments form one connected defense")
		sim.resources["wood"] = 10000
		sim.resources["gold"] = 10000
		check(sim.insert_gate(int(first_wall["id"])), "Gate Engineering inserts a gate into an existing wall segment")
		check(first_wall["type"] == "gate" and first_wall["gate_open"], "inserted gate keeps the connected segment identity and gate state")
		step(sim, 6.0)
		connected = sim._connected_barriers(int(first_wall["id"]))
		check(connected.size() >= 3, "inserted gate remains part of the connected defense")
		if sim.building_specs["wall"]["tiers"].size() > 1:
			sim.resources["wood"] = 10000
			sim.resources["gold"] = 10000
			sim.resources["lumber"] = 10000
			sim.resources["stone"] = 10000
			check(sim.upgrade_wall_line(int(first_wall["id"])), "connected wall section upgrades as one command")

	# Rally points and exact defensive posts are persistent tactical state.
	var rally := Vector2(-1, -1)
	for y in 16:
		for x in 20:
			if not sim._blocked(Vector2i(x, y), false):
				rally = Vector2(x + 0.5, y + 0.5)
				break
		if rally.x >= 0:
			break
	check(rally.x >= 0 and sim.set_rally(rally.x, rally.y), "rally point accepts open ground")
	var guard_spot: Vector2i = find_build_spot(sim, "guard_post")
	check(guard_spot.x >= 0 and sim.build("guard_post", guard_spot.x, guard_spot.y), "Fortifications unlocks a real Guard Post build")
	step(sim, 5.0)
	var guard: Dictionary = building(sim, "guard_post")
	check(not guard.is_empty() and guard["remaining"] <= 0, "Guard Post finishes construction")
	var warrior: Dictionary = {}
	for u: Dictionary in sim.units:
		if u["type"] == "warrior":
			warrior = u
			break
	check(not warrior.is_empty() and sim.assign_defense_post(int(warrior["id"]), int(guard["id"])), "warrior can be posted to an exact defensive structure")
	check(int(warrior.get("defense_post", -1)) == int(guard["id"]) and warrior["defense_priority"] == "gate", "exact Guard Post assignment is recorded")
	check(sim.set_defense_priority(int(warrior["id"]), "rally"), "defender can switch from a post to rally duty")
	check(int(warrior.get("defense_post", -1)) == -1 and warrior["defense_priority"] == "rally", "switching duty releases the exact post")

	# Advanced targeting and mixed enemy composition.
	var tower_spot: Vector2i = find_build_spot(sim, "tower")
	check(tower_spot.x >= 0 and sim.build("tower", tower_spot.x, tower_spot.y), "a tower can be added for command testing")
	step(sim, 5.0)
	var tower: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if b["type"] == "tower" and Vector2i(int(b["x"]), int(b["y"])) == tower_spot:
			tower = b
			break
	check(not tower.is_empty() and sim.set_tower_targeting(int(tower["id"]), "sappers"), "Watchtower Doctrine unlocks sapper-priority targeting")
	check(tower.get("target_mode") == "sappers", "tower stores its targeting order")
	var manifest: Array[String] = sim.raid_manifest(5)
	check("raider" in manifest and "skirmisher" in manifest and "brute" in manifest and "marksman" in manifest and "sapper" in manifest, "wave five mixes all five raid archetypes")
	var intel: Dictionary = sim.raid_preview()
	check(intel.has("composition") and intel.has("sides"), "warning intelligence exposes composition and approach sides")

	# Dormant professions are now reachable through actual support buildings.
	var oath_spot: Vector2i = find_build_spot(sim, "oathstone")
	check(oath_spot.x >= 0 and sim.build("oathstone", oath_spot.x, oath_spot.y), "Gate Engineering unlocks the Oathstone")
	step(sim, 6.5)
	check(sim.recruit_reason("warden").is_empty(), "finished Oathstone makes Warden recruitment available")
	var forge_spot: Vector2i = find_build_spot(sim, "forge")
	check(forge_spot.x >= 0 and sim.build("forge", forge_spot.x, forge_spot.y), "Watchtower Doctrine unlocks the Emberforge")
	step(sim, 5.5)
	check(sim.recruit_reason("weaponsmith").is_empty(), "finished Emberforge makes Weaponsmith recruitment available")

	# Fortress tactical state survives JSON saves.
	sim.set_defense_priority(int(warrior["id"]), "rally")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	var restored = Sim.new()
	check(restored.restore_state(saved), "Fortress & Command state survives JSON roundtrip")
	check(restored.rally_point.is_equal_approx(sim.rally_point), "rally point survives save/load")
	var restored_warrior: Dictionary = restored.get_unit(int(warrior["id"]))
	check(not restored_warrior.is_empty() and restored_warrior["defense_priority"] == "rally", "defender duty survives save/load")
	var restored_tower: Dictionary = restored.get_building(int(tower["id"]))
	check(not restored_tower.is_empty() and restored_tower.get("target_mode") == "sappers", "tower targeting survives save/load")

	# Defensive Logistics gives builders a real post-raid repair job.
	var repair_sim = Sim.new()
	_unlock_fortress(repair_sim)
	repair_sim._add_unit("builder")
	var builder: Dictionary = repair_sim.units.back()
	var hall: Dictionary = repair_sim._hall()
	var damaged_hp: float = float(hall["max_hp"]) - 45.0
	hall["hp"] = damaged_hp
	var repair_wood: float = float(repair_sim.resources["wood"])
	step(repair_sim, 20.0)
	check(float(hall["hp"]) > damaged_hp, "builder automatically repairs damaged structures after Defensive Logistics")
	check(float(repair_sim.resources["wood"]) < repair_wood, "automatic repair consumes real Wood")
	check(builder["phase"] in ["repair", "idle", "walk"], "builder uses the normal movement/work state machine for repairs")

	# A raid ends with an actionable after-action report.
	var report_sim = Sim.new()
	_unlock_fortress(report_sim)
	report_sim.wave = 4
	report_sim.raid_active = true
	report_sim.raid_started_at = 3.0
	report_sim.elapsed = 15.0
	report_sim.raid_kills = 6
	for b: Dictionary in report_sim.buildings:
		report_sim.raid_baseline[str(int(b["id"]))] = float(b["hp"])
	var report_hall: Dictionary = report_sim._hall()
	report_hall["hp"] = float(report_hall["hp"]) - 20.0
	report_sim._finish_raid(true)
	check(not report_sim.last_raid_report.is_empty(), "raid completion creates a battle report")
	check(report_sim.last_raid_report["victory"] and int(report_sim.last_raid_report["enemies_defeated"]) == 6, "battle report records victory and defeated enemies")
	check(int(report_sim.last_raid_report["buildings_damaged"]) >= 1, "battle report records building damage")
	check(float(report_sim.last_raid_report["duration"]) >= 12.0, "battle report records raid duration")

	var report := {
		"passed": failures.is_empty(),
		"checks": checks,
		"failures": failures,
		"scope": "Fortress research, wall lines, rally/posts, targeting, mixed raids, activated professions, persistence, automatic repair and after-action reporting."
	}
	var file := FileAccess.open("res://docs/fortress_command_verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("FORTRESS_COMMAND ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
