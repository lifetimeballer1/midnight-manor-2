extends RefCounted

const ChronicleData = preload("res://scripts/game/chronicle.gd")
const COST := {"food": 20, "gold": 10}
var active: Dictionary = {}
var last_result: Dictionary = {}
var attempt: int = 0


func reason(sim, region: String, crew: Array) -> String:
	if not active.is_empty(): return "An expedition is already away."
	if sim.chronicle.region_data(region).is_empty(): return "Unknown region."
	if sim.chronicle.act < 4: return "Requires Act IV / Beyond the Lanterns."
	if sim.raid_active or sim.raid_warning: return "Hold the Manor until the alarm passes."
	if crew.is_empty() or crew.size() > 8: return "Choose one to eight defenders."
	var seen: Dictionary = {}
	for id: Variant in crew:
		if not (id is int) or seen.has(id): return "Choose each defender once."
		var unit: Dictionary = sim.get_unit(id)
		if unit.is_empty() or unit["hp"] <= 0.0 or sim.troop_specs[unit["type"]]["role"] != "combat":
			return "Only living defenders can join the expedition."
		seen[id] = true
	return "" if sim._affordable(COST) else "Requires 20 Food and 10 Gold."


func begin(sim, region: String, crew: Array) -> bool:
	sim.notice = reason(sim, region, crew)
	if not sim.notice.is_empty(): return false
	var army: Array[Dictionary] = []
	for id: int in crew:
		var unit: Dictionary = sim.get_unit(id)
		army.append(_body(id, str(unit["type"]), 3.0, 4.0 + army.size(), float(unit["hp"]), float(unit["max_hp"]), sim._stat(unit, "damage"), sim._stat(unit, "range"), sim._stat(unit, "speed")))
	var index: int = sim.chronicle.region_order().find(region)
	var stage: int = sim.chronicle.region_index(region)
	var difficulty: int = mini(2, stage)
	var roles: Array = ["raider", "archer"]
	for faction: Dictionary in sim.world_specs.get("enemyFactions", []):
		if str(faction["id"]) == str(sim.chronicle.region_data(region).get("faction", "")):
			roles = faction.get("roles", roles)
	var enemies: Array[Dictionary] = []
	for slot in mini(8, 2 + index + difficulty):
		var role: String = str(roles[slot % roles.size()])
		var stats: Dictionary = sim._role_stats(role)
		var hp: float = 45.0 * (1.0 + index * 0.2 + difficulty * 0.3) * float(stats.get("hp", 1.0))
		enemies.append(_body(slot, role, 16.0, 3.0 + slot * 1.2, hp, hp, 6.0 * (1.0 + index * 0.1 + stage * 0.2) * float(stats.get("damage", 1.0)), float(stats.get("range", 1.1)), float(stats.get("speed", 1.0))))
	sim._spend(COST)
	attempt += 1
	active = {"region": region, "target": str(sim.chronicle.region_states()[stage + 1 if stage < 3 else stage]), "status": "running", "clock": 0.0, "army": army, "enemies": enemies}
	sim.notice = "Expedition away. The home village waits safely."
	return true


func _body(id: int, type_name: String, x: float, y: float, hp: float, maximum: float, damage: float, reach: float, speed: float) -> Dictionary:
	return {"id": id, "type": type_name, "x": x, "y": y, "hp": hp, "max_hp": maximum, "damage": damage, "range": reach, "speed": speed, "cooldown": 0.0, "phase": "idle", "order": [], "fx": x, "fy": y}


func tick(dt: float) -> void:
	if active.is_empty() or active["status"] != "running" or not is_finite(dt) or dt <= 0.0 or dt > 1.0:
		return
	active["clock"] = minf(180.0, float(active["clock"]) + dt)
	for body: Dictionary in active["army"]:
		_turn(body, active["enemies"], dt)
	for body: Dictionary in active["enemies"]:
		_turn(body, active["army"], dt)
	if alive(active["enemies"]) == 0:
		active["status"] = "won"
	elif alive(active["army"]) == 0:
		active["status"] = "lost"
	elif active["clock"] >= 180.0:
		active["status"] = "withdrawn"


func alive(group: Array) -> int:
	var count: int = 0
	for body: Dictionary in group:
		if body["hp"] > 0.0: count += 1
	return count


func _turn(body: Dictionary, opponents: Array, dt: float) -> void:
	if body["hp"] <= 0.0:
		body["phase"] = "death"
		return
	body["cooldown"] = maxf(0.0, float(body["cooldown"]) - dt)
	var here := Vector2(body["x"], body["y"])
	var target: Dictionary = {}
	var distance: float = INF
	for other: Dictionary in opponents:
		var gap: float = here.distance_to(Vector2(other["x"], other["y"]))
		if other["hp"] > 0.0 and gap < distance:
			target = other
			distance = gap
	if target.is_empty():
		body["phase"] = "idle"
		return
	var destination := Vector2(target["x"], target["y"])
	if not body["order"].is_empty():
		destination = Vector2(body["order"][0], body["order"][1])
		if here.distance_to(destination) < 0.15: body["order"] = []
	body["fx"] = destination.x
	body["fy"] = destination.y
	if distance <= float(body["range"]) and body["order"].is_empty():
		body["phase"] = "attack"
		if body["cooldown"] <= 0.0:
			target["hp"] = maxf(0.0, float(target["hp"]) - float(body["damage"]))
			body["cooldown"] = 1.0
	else:
		body["phase"] = "walk"
		var next: Vector2 = here.move_toward(destination, float(body["speed"]) * dt)
		body["x"] = clampf(next.x, 0.5, 19.5)
		body["y"] = clampf(next.y, 0.5, 15.5)


func rally(point: Vector2) -> bool:
	if active.is_empty() or active["status"] != "running" or not is_finite(point.x) or not is_finite(point.y) or point.x < 0.5 or point.x > 19.5 or point.y < 0.5 or point.y > 15.5:
		return false
	for body: Dictionary in active["army"]:
		if body["hp"] > 0.0: body["order"] = [point.x, point.y]
	return true


func withdraw() -> void:
	if not active.is_empty() and active["status"] == "running": active["status"] = "withdrawn"


func settle(sim) -> bool:
	if active.is_empty() or active["status"] == "running": return false
	var won: bool = active["status"] == "won"
	if won and not sim.chronicle.set_region(active["region"], active["target"]).is_empty(): return false
	var fallen: int = 0
	for body: Dictionary in active["army"]:
		var unit: Dictionary = sim.get_unit(int(body["id"]))
		if body["hp"] <= 0.0: fallen += 1
		unit["hp"] = float(body["hp"]) if body["hp"] > 0.0 else float(unit["max_hp"]) * 0.5
	var gold: int = 0
	if won:
		gold = 40 + sim.chronicle.region_order().find(active["region"]) * 15
		sim.raid_stats["expeditions"] += 1
		sim._reward({"gold": gold})
	for enemy: Dictionary in active["enemies"]:
		if enemy["hp"] <= 0.0:
			sim.raid_stats["kills"] += 1
			sim.raid_stats["kills_by"][enemy["type"]] = int(sim.raid_stats["kills_by"].get(enemy["type"], 0)) + 1
	last_result = {"region": active["region"], "status": active["status"], "recovering": fallen, "gold": gold}
	sim.notice = "Expedition %s / %d recovering defenders / %d Gold." % [str(active["status"]), fallen, gold]
	active = {}
	return true


func state() -> Dictionary:
	return {"active": active.duplicate(true), "last_result": last_result.duplicate(true), "attempt": attempt}


func valid(data: Variant, units: Array, progression: Dictionary, roles: Dictionary) -> bool:
	if not data is Dictionary or not data.get("active") is Dictionary or not data.get("last_result") is Dictionary or not _number(data.get("attempt")) or float(data["attempt"]) != floorf(float(data["attempt"])):
		return false
	var battle: Dictionary = data["active"]
	var result: Dictionary = data["last_result"]
	if not result.is_empty():
		if result.get("region", "") not in ChronicleData.REGION_ORDER or result.get("status", "") not in ["won", "lost", "withdrawn"]: return false
		for field: String in ["recovering", "gold"]:
			if not _number(result.get(field)) or float(result[field]) != floorf(float(result[field])): return false
		if result["recovering"] > 8 or result["gold"] > 130: return false
	if battle.is_empty(): return true
	if int(data["attempt"]) < 1 or int(progression["act"]) < 4: return false
	if battle.get("region", "") not in ChronicleData.REGION_ORDER or battle.get("status", "") not in ["running", "won", "lost", "withdrawn"] or battle.get("target", "") not in ["scouted", "contested", "secured", "developed"] or not _number(battle.get("clock")) or battle["clock"] > 180.1:
		return false
	var stages: Array = ["unseen", "scouted", "contested", "secured", "developed"]
	var stage: int = stages.find(str(progression["regions"].get(battle["region"], "unseen")))
	if stage + 1 != stages.find(battle["target"]) and not (stage >= 3 and stage == stages.find(battle["target"])): return false
	for group_name: String in ["army", "enemies"]:
		var group: Variant = battle.get(group_name)
		if not group is Array or group.is_empty() or group.size() > 8: return false
		var seen: Dictionary = {}
		for body: Variant in group:
			if not body is Dictionary: return false
			for field: String in ["id", "x", "y", "hp", "max_hp", "damage", "range", "speed", "cooldown", "fx", "fy"]:
				if not _number(body.get(field)): return false
			if float(body["id"]) != floorf(float(body["id"])) or seen.has(int(body["id"])) or body["x"] >= 20.0 or body["y"] >= 16.0 or body["hp"] > body["max_hp"] or body["max_hp"] <= 0.0 or body["damage"] <= 0.0 or body["speed"] <= 0.0 or body["cooldown"] > 1.0 or body.get("phase", "") not in ["idle", "walk", "attack", "death"] or not body.get("type") is String or not body.get("order") is Array: return false
			seen[int(body["id"])] = true
			if not body["order"].is_empty() and (body["order"].size() != 2 or not _number(body["order"][0]) or not _number(body["order"][1]) or body["order"][0] >= 20.0 or body["order"][1] >= 16.0): return false
			if group_name == "army":
				var found: bool = false
				for unit: Dictionary in units:
					if int(unit["id"]) == int(body["id"]) and unit["type"] == body["type"] and roles[unit["type"]]["role"] == "combat" and unit["max_hp"] == body["max_hp"]: found = true
				if not found: return false
			elif body.get("type", "") not in ["raider", "scout", "archer", "breaker", "ram", "bombard"]: return false
	return true


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0


func restore(data: Dictionary) -> void:
	active = data["active"].duplicate(true)
	last_result = data["last_result"].duplicate(true)
	attempt = int(data["attempt"])
