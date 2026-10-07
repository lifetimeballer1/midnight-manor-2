extends RefCounted

const RESOURCES: Array[String] = ["wood", "food", "gold"]
const EXCLUDED: Array[String] = ["wall", "stonewall", "gate", "trap", "fire_trap"]
const LOOT_FRACTION: float = 0.2
const MAX_SECONDS: float = 300.0
var active: Dictionary = {}
var last: Dictionary = {}


func _stocks() -> Dictionary:
	return {"wood": 0, "food": 0, "gold": 0}


func begin(sim) -> void:
	var budget: Dictionary = _stocks()
	for resource: String in RESOURCES: budget[resource] = floori(float(sim.resources.get(resource, 0.0)) * LOOT_FRACTION)
	active = {"wave": sim.wave, "seconds": 0.0, "hall_lost": sim._hall().get("hp", 0.0) <= 0.0,
		"targets": {}, "budget": budget, "loot": _stocks()}
	for b: Dictionary in sim.buildings:
		if b["type"] in EXCLUDED or b["hp"] <= 0.0 or b["remaining"] > 0.0: continue
		active["targets"][str(int(b["id"]))] = {"type": b["type"], "hp": float(b["hp"]), "damage": 0.0,
			"destroyed": false, "cap": _stocks(), "paid": _stocks()}
	for resource: String in RESOURCES:
		var sites: Array = []
		for id: String in active["targets"]:
			var spec: Dictionary = sim.building_specs[active["targets"][id]["type"]]
			if spec.get("production") == resource or spec.get("storage", {}).has(resource): sites.append(id)
		for index in sites.size():
			# Integer shares (including the remainder) add up to the single raid budget.
			active["targets"][sites[index]]["cap"][resource] = int(budget[resource]) / sites.size() + (1 if index < int(budget[resource]) % sites.size() else 0)


func hit(sim, building: Dictionary, damage: float) -> void:
	if active.is_empty() or damage <= 0.0: return
	var target: Dictionary = active["targets"].get(str(int(building["id"])), {})
	if target.is_empty(): return
	target["damage"] = minf(float(target["hp"]), float(target["damage"]) + damage)
	if building["hp"] <= 0.0:
		target["destroyed"] = true
		target["damage"] = target["hp"]
		if target["type"] == "hall": active["hall_lost"] = true
	for resource: String in RESOURCES:
		var earned: int = floori(float(target["cap"][resource]) * float(target["damage"]) / float(target["hp"]))
		var amount: int = mini(earned - int(target["paid"][resource]), floori(float(sim.resources.get(resource, 0.0))))
		if amount <= 0: continue
		sim.resources[resource] -= amount
		target["paid"][resource] += amount
		active["loot"][resource] += amount


func _destroyed() -> int:
	var count: int = 0
	for target: Dictionary in active.get("targets", {}).values():
		if target["destroyed"]: count += 1
	return count


func loot_target(sim, point: Vector2) -> Dictionary:
	var chosen: Dictionary = {}
	var nearest: float = INF
	for id: String in active.get("targets", {}):
		var target: Dictionary = active["targets"][id]
		var available: bool = false
		for resource: String in RESOURCES:
			if target["paid"][resource] < target["cap"][resource]: available = true
		if not available: continue
		var b: Dictionary = sim.get_building(int(id))
		if b.is_empty() or b["hp"] <= 0.0 or b["remaining"] > 0.0: continue
		var distance: float = sim._building_distance(point, b)
		if distance < nearest:
			nearest = distance
			chosen = b
	return chosen


func _stars(destroyed: int, total: int, hall_lost: bool) -> int:
	return int(hall_lost) + int(total > 0 and destroyed * 2 >= total) + int(total > 0 and destroyed == total)


func stars() -> int:
	if active.is_empty(): return int(last.get("stars", 0))
	return _stars(_destroyed(), active["targets"].size(), active["hall_lost"])


func summary() -> Dictionary:
	if active.is_empty(): return last.duplicate(true)
	var destroyed: int = _destroyed()
	var total: int = active["targets"].size()
	var score: int = _stars(destroyed, total, active["hall_lost"])
	return {"wave": active["wave"], "seconds": active["seconds"], "total": total, "destroyed": destroyed,
		"hall_lost": active["hall_lost"], "stars": score, "destruction": 100 * destroyed / total if total > 0 else 0,
		"loot": active["loot"].duplicate(), "defense_won": score == 0}


func finish() -> bool:
	last = summary()
	active.clear()
	return bool(last.get("defense_won", false))


func state() -> Dictionary:
	return {"active": active.duplicate(true), "last": last.duplicate(true)}


func restore(saved: Dictionary) -> void:
	active = saved.get("active", {}).duplicate(true)
	last = saved.get("last", {}).duplicate(true)


func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


func _valid_stocks(value: Variant) -> bool:
	if not value is Dictionary or value.size() != RESOURCES.size(): return false
	for resource: String in RESOURCES:
		if not _integer(value.get(resource)): return false
	return true


func valid(saved: Variant, village: Dictionary) -> bool:
	if not saved is Dictionary or not saved.get("active") is Dictionary or not saved.get("last") is Dictionary: return false
	var raid: Dictionary = saved["active"]
	if raid.is_empty() and bool(village.get("raid_active", false)): return false
	if not raid.is_empty():
		if not bool(village.get("raid_active", false)) or not _integer(raid.get("wave")) or raid["wave"] != village.get("wave"): return false
		if not _number(raid.get("seconds")) or raid["seconds"] > MAX_SECONDS or not raid.get("hall_lost") is bool: return false
		if not raid.get("targets") is Dictionary or raid["targets"].size() > 320: return false
		if not _valid_stocks(raid.get("budget")) or not _valid_stocks(raid.get("loot")): return false
		var caps: Dictionary = _stocks()
		var paid: Dictionary = _stocks()
		for id: Variant in raid["targets"]:
			if not id is String or not id.is_valid_int() or str(int(id)) != id or int(id) <= 0: return false
			var target: Variant = raid["targets"][id]
			if not target is Dictionary or not target.get("type") is String or target["type"] in EXCLUDED: return false
			if not _number(target.get("hp")) or target["hp"] <= 0.0 or not _number(target.get("damage")) or target["damage"] > target["hp"]: return false
			if not target.get("destroyed") is bool or not _valid_stocks(target.get("cap")) or not _valid_stocks(target.get("paid")): return false
			var found: bool = false
			for b: Variant in village.get("buildings", []):
				if b is Dictionary and b.get("id") == int(id) and b.get("type") == target["type"]: found = true
			if not found: return false
			for resource: String in RESOURCES:
				if target["paid"][resource] > target["cap"][resource]: return false
				caps[resource] += target["cap"][resource]
				paid[resource] += target["paid"][resource]
		for resource: String in RESOURCES:
			if caps[resource] > raid["budget"][resource] or paid[resource] != raid["loot"][resource]: return false
			if raid["loot"][resource] > raid["budget"][resource]: return false
	var report: Dictionary = saved["last"]
	if report.is_empty(): return true
	for key: String in ["wave", "total", "destroyed", "stars", "destruction"]:
		if not _integer(report.get(key)): return false
	if report["wave"] > float(village.get("wave", 0)) or report["total"] > 320 or report["destroyed"] > report["total"]: return false
	if not report.get("hall_lost") is bool or not report.get("defense_won") is bool or not _valid_stocks(report.get("loot")): return false
	if not _number(report.get("seconds")) or report["seconds"] > MAX_SECONDS: return false
	var score: int = _stars(int(report["destroyed"]), int(report["total"]), report["hall_lost"])
	var percent: int = 100 * int(report["destroyed"]) / int(report["total"]) if report["total"] > 0 else 0
	return report["stars"] == score and report["destruction"] == percent and report["defense_won"] == (score == 0)
