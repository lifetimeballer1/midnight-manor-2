extends RefCounted

var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/living_village.json"))
var cells: Dictionary = {}
var insight: float = 0
var discoveries: Array[String] = []
var active: String = ""
var remaining: float = 0
var revision: int = 0
var navigation_revision: int = 0
var decay_clock: float = 0


func key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


func at(point: Vector2) -> Dictionary:
	return cells.get(key(Vector2i(floori(point.x), floori(point.y))), {})


func stage(wear: float) -> int:
	return mini(12, floori(wear * 12))


func walked(from: Vector2, to: Vector2, now: float) -> void:
	var distance: float = from.distance_to(to)
	if distance < 0.000001:
		return
	var samples: int = maxi(1, ceili(distance * 4))
	for index in samples:
		var point: Vector2 = from.lerp(to, (index + 0.5) / samples)
		var tile := Vector2i(floori(point.x), floori(point.y))
		if tile.x < 0 or tile.x >= 20 or tile.y < 0 or tile.y >= 16:
			continue
		var id: String = key(tile)
		var cell: Dictionary = cells.get(id, {"wear": 0.0, "last": now, "stone": false})
		var before: float = float(cell["wear"])
		cell["wear"] = minf(1, before + distance / samples / float(config["trail"]["crossings"]))
		cell["last"] = now
		cells[id] = cell
		if stage(before) != stage(float(cell["wear"])):
			revision += 1
		if before < faint_threshold() and float(cell["wear"]) >= faint_threshold():
			navigation_revision += 1


func faint_threshold() -> float:
	return float(config["trail"]["faint_crossings"]) / float(config["trail"]["crossings"])


func route_cost(tile: Vector2i) -> float:
	var cell: Dictionary = cells.get(key(tile), {})
	if cell.get("stone", false):
		return 1.0 / (1.0 + float(config["stone"]["speed_bonus"]))
	return 0.97 if float(cell.get("wear", 0)) >= faint_threshold() else 1.0


func speed_at(point: Vector2) -> float:
	return 1.0 + float(config["stone"]["speed_bonus"]) if at(point).get("stone", false) else 1.0


func tick(sim, dt: float) -> void:
	decay_clock += dt
	if decay_clock >= 1:
		for id in cells.keys():
			var cell: Dictionary = cells[id]
			if cell["stone"] or sim.elapsed - float(cell["last"]) < float(config["trail"]["decay_delay"]):
				continue
			var before: float = float(cell["wear"])
			cell["wear"] = maxf(0, before - decay_clock / float(config["trail"]["decay_seconds"]))
			if stage(before) != stage(float(cell["wear"])):
				revision += 1
			if before >= faint_threshold() and float(cell["wear"]) < faint_threshold():
				navigation_revision += 1
			if float(cell["wear"]) <= 0:
				cells.erase(id)
		decay_clock = 0
	if sim.raid_active or sim.raid_warning:
		return
	var hall: Dictionary = sim._hall()
	if hall.is_empty() or hall["hp"] <= 0 or hall["remaining"] > 0:
		return
	insight = minf(float(config["research"]["insight_cap"]), insight + float(config["research"]["rate_per_minute"]) * dt / 60)
	if not active.is_empty():
		remaining = maxf(0, remaining - dt)
		if remaining <= 0:
			discoveries.append(active)
			sim.notice = "Research complete / " + str(config["research"]["nodes"][active]["name"])
			active = ""


func research_reason(sim, id: String) -> String:
	var node: Dictionary = config["research"]["nodes"].get(id, {})
	if node.is_empty(): return "Unknown research."
	if id in discoveries: return "Already discovered."
	if not active.is_empty(): return "Another research project is active."
	if sim.raid_active or sim.raid_warning: return "Research waits until the alarm passes."
	if sim.village_level() < int(node["level"]): return "Requires village level %d." % node["level"]
	var prerequisite: String = str(node.get("requires", ""))
	if not prerequisite.is_empty() and prerequisite not in discoveries:
		var required_node: Dictionary = config["research"]["nodes"].get(prerequisite, {})
		return "Requires %s." % str(required_node.get("name", prerequisite.capitalize()))
	if insight < float(node["insight"]): return "Requires %d Insight." % node["insight"]
	return "" if sim._affordable(node["cost"]) else "Not enough research resources."


func research(sim, id: String) -> bool:
	sim.notice = research_reason(sim, id)
	if not sim.notice.is_empty(): return false
	var node: Dictionary = config["research"]["nodes"][id]
	sim._spend(node["cost"])
	insight -= float(node["insight"])
	active = id
	remaining = float(node["seconds"])
	sim.notice = "Research begun / " + str(node["name"])
	return true


func pave_reason(sim, tile: Vector2i) -> String:
	if "road_masonry" not in discoveries: return "Research Road Masonry first."
	if tile.x < 0 or tile.x >= 20 or tile.y < 0 or tile.y >= 16: return "Outside the village."
	var cell: Dictionary = cells.get(key(tile), {})
	if cell.get("stone", false): return "Already paved."
	if float(cell.get("wear", 0)) < 0.999: return "This trail needs more traffic before paving."
	for b: Dictionary in sim.buildings:
		if b["type"] not in ["gate", "trap"] and Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"])).has_point(tile):
			return "Roads cannot overlap buildings."
	return "" if sim._affordable({"stone": int(config["stone"]["pave_cost"])}) else "Not enough Stone."


func pave(sim, tile: Vector2i) -> bool:
	sim.notice = pave_reason(sim, tile)
	if not sim.notice.is_empty(): return false
	sim._spend({"stone": int(config["stone"]["pave_cost"])})
	cells[key(tile)]["stone"] = true
	revision += 1
	navigation_revision += 1
	sim.notice = "Stone road laid / friendly travel +15%."
	return true


func state() -> Dictionary:
	return {"cells": cells.duplicate(true), "insight": insight, "discoveries": discoveries.duplicate(), "active": active, "remaining": remaining}


func valid(data: Variant) -> bool:
	if not data is Dictionary or not data.get("cells") is Dictionary or not data.get("discoveries") is Array:
		return false
	for field in ["insight", "remaining"]:
		var value: Variant = data.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0: return false
	if data["insight"] > float(config["research"]["insight_cap"]) or data["cells"].size() > 320: return false
	if not data.get("active") is String: return false
	if data["active"] != "" and not config["research"]["nodes"].has(data["active"]): return false
	var seen: Dictionary = {}
	for id in data["discoveries"]:
		if not id is String or not config["research"]["nodes"].has(id) or seen.has(id): return false
		seen[id] = true
	if data["active"] in seen: return false
	for id in seen:
		var prerequisite: String = str(config["research"]["nodes"][id].get("requires", ""))
		if not prerequisite.is_empty() and prerequisite not in seen: return false
	if data["active"] != "":
		var active_requires: String = str(config["research"]["nodes"][data["active"]].get("requires", ""))
		if not active_requires.is_empty() and active_requires not in seen: return false
	if data["active"] == "" and data["remaining"] != 0: return false
	if data["active"] != "" and data["remaining"] > config["research"]["nodes"][data["active"]]["seconds"]: return false
	for id in data["cells"]:
		if not id is String: return false
		var parts: PackedStringArray = id.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return false
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		if key(tile) != id or tile.x < 0 or tile.x >= 20 or tile.y < 0 or tile.y >= 16: return false
		var cell: Variant = data["cells"][id]
		if not cell is Dictionary or not cell.get("stone") is bool: return false
		for field in ["wear", "last"]:
			var value: Variant = cell.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or value < 0: return false
		if cell["wear"] > 1: return false
	return true


func restore(data: Dictionary) -> void:
	cells = data["cells"].duplicate(true)
	insight = float(data["insight"])
	discoveries.assign(data["discoveries"])
	active = data["active"]
	remaining = float(data["remaining"])
	decay_clock = 0
	revision += 1
	navigation_revision += 1
