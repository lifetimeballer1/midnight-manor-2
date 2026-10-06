extends RefCounted

const Chronicle = preload("res://scripts/game/chronicle.gd")
# Content available without a story introduction. Everything else in
# buildings.json / troops.json is gated by the Chronicle unlock registry.
const BUILD_TYPES: Array[String] = ["farm", "lumber", "timber_yard", "mine", "cottage", "pond", "pasture", "barracks", "tower", "archer_tower", "wall", "stonewall", "gate", "trap", "storehouse", "sawmill", "stone_quarry"]
const Living = preload("res://scripts/game/living_village.gd")
var living = Living.new()
var chronicle = Chronicle.new()
var navigation_revision: int = 0
const ROLES: Array[String] = ["builder", "warrior", "archer", "farmer", "lumberjack", "miner", "fisherman", "shepherd"]
const XP_LEVELS: Array[int] = [0, 100, 220, 380, 580, 830, 1150, 1500, 2100, 2400, 2600]
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var building_specs: Dictionary = {}
var troop_specs: Dictionary = {}
var world_specs: Dictionary = {}
var quests: Array = []
var buildings: Array[Dictionary] = []
var units: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var resources: Dictionary = {}
var pending_rewards: Dictionary = {}
var gathered: Dictionary = {}
var completed_quests: Array[String] = []
var events: Array[Dictionary] = []
var elapsed: float = 0
var xp: int = 0
var wave: int = 0
var next_raid_at: float = 300
var raid_active: bool = false
var raid_warning: bool = false
var paused: bool = false
var revision: int = 0
# Path caches key on path_revision, NOT revision: gate open/close flips
# change friendly walkability but need no 3D rebuild, so they invalidate
# paths without touching revision (which rebuilds the whole village view).
var path_revision: int = 0
# Transient per-tick caches (never saved): threat base ranks, tick counter.
var threat_ranks: Dictionary = {}
var threat_stamp: int = -1
var tick_count: int = 0
var notice: String = "The Manner stands."
var quest_progress: Dictionary = {}
var optional_won: Dictionary = {}
var raid_stats: Dictionary = {"defended": 0, "kills": 0, "kills_by": {}, "built_lost": 0, "defenders_lost": 0, "gates_lost": 0, "seconds_held": 0.0, "prestige": 0, "expeditions": 0, "delivered": {}}
var scripted_raid: String = ""
var region_progress: Dictionary = {}
var next_id: int = 1
var birth_timer: float = 0
var paths: Dictionary = {}
var job_timer: float = 0
var workplace_specs: Dictionary = {}
var stand_cache: Dictionary = {}

const KITE_TRIGGER: float = 1.5
const KITE_RELEASE_RATIO: float = 0.7
const KITE_THINK: float = 0.6
# Guard Posts hold defenders without giving them a profession, so Organized
# Watch can fill them on its own.
const GUARD_POSTS: Array[String] = ["watchfire", "bastion", "gate", "tower", "archer_tower", "ballista", "oathstone"]


func _init() -> void:
	building_specs = _json("buildings")
	troop_specs = _json("troops")
	world_specs = _json("world")
	living.bind_chronicle(chronicle)
	world_specs["startingResources"]["stone"] = 0
	world_specs["storageBase"]["stone"] = living.config["stone"]["base_storage"]
	building_specs["hall"]["storage"]["stone"] = living.config["stone"]["hall_storage"]
	building_specs["storehouse"]["storage"]["stone"] = living.config["stone"]["storehouse_storage"]
	building_specs["stone_quarry"] = living.config["quarry"].duplicate(true)
	var work_spec: Dictionary = _json("workplaces")
	workplace_specs = work_spec["workplaces"] if work_spec.get("workplaces") is Dictionary else work_spec
	workplace_specs["stone_quarry"] = {"stands": [[-1.5, -0.5], [1.5, -0.5]], "target": [0, 0]}
	var all_quests: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests.json"))
	quests = _normalise_quests(all_quests)
	resources = world_specs["startingResources"].duplicate(true)
	for entry: Dictionary in world_specs["buildings"]:
		buildings.append(_new_building(entry["type"], int(entry["x"]), int(entry["y"]), false))
	for role: String in world_specs["troops"]:
		_add_unit(role)
	_auto_assign()


# Every mission in the file is loaded. Availability is decided by act progress
# and the unlock registry, not by an array slice, so Acts IV-X need no rewrite.
func _normalise_quests(raw: Array) -> Array:
	var out: Array = []
	for entry: Variant in raw:
		if not entry is Dictionary:
			continue
		var quest: Dictionary = (entry as Dictionary).duplicate(true)
		var raw_act: Variant = quest.get("act", 1)
		quest["act"] = _roman(raw_act) if raw_act is String else int(raw_act)
		var objectives: Array = quest.get("objectives", [])
		if objectives.is_empty() and quest.has("task"):
			# Legacy single-task quests become a one-objective list.
			quest["objectives"] = [quest["task"]]
		quest["objectives"] = _normalise_objectives(quest.get("objectives", []))
		quest["optional"] = _normalise_objectives(quest.get("optional", []))
		for field: String in ["unlocks", "introduces"]:
			if not quest.get(field) is Array:
				quest[field] = []
		for field: String in ["xp", "insight", "reputation"]:
			if not _number(quest.get(field, 0)):
				quest[field] = 0
		if not quest.get("rewards") is Dictionary:
			quest["rewards"] = {}
		quest.erase("task")
		out.append(quest)
	return out


func _normalise_objectives(raw: Array) -> Array:
	var out: Array = []
	for entry: Variant in raw:
		if not entry is Dictionary:
			continue
		var objective: Dictionary = (entry as Dictionary).duplicate(true)
		var kinds: Array = objective.get("types", [])
		if objective.has("type") and not kinds.has(str(objective["type"])):
			kinds.append(str(objective["type"]))
		objective["types"] = kinds
		objective["count"] = int(objective.get("count", objective.get("amount", 1)))
		out.append(objective)
	return out


func _roman(value: String) -> int:
	var index: int = _roman_order().find(value.strip_edges().to_upper())
	return index + 1 if index >= 0 else 1


func _roman_order() -> Array[String]:
	return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]


func _json(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % name))
	return value if value is Dictionary else {}


func _id() -> int:
	var value: int = next_id
	next_id += 1
	return value


func _new_building(type_name: String, x: int, y: int, constructing: bool) -> Dictionary:
	var spec: Dictionary = building_specs[type_name]
	var hp: float = float(spec["tiers"][0]["hp"])
	return {"id": _id(), "type": type_name, "x": x, "y": y, "size": int(spec["size"]), "tier": 1,
		"hp": hp, "max_hp": hp, "remaining": float(spec["buildSeconds"]) if constructing else 0.0,
		"reserve": 0.0, "cooldown": 0.0}


func _add_unit(role: String) -> void:
	var hp: float = float(troop_specs[role]["base"]["hp"])
	units.append({"id": _id(), "type": role, "x": 8.0 + (units.size() % 6) * 0.65, "y": 10.8,
		"hp": hp, "max_hp": hp, "phase": "idle", "workplace": -1, "carry": 0.0, "carry_resource": "",
		"level": 1, "cooldown": 0.0, "order": [], "hold": false,
		"fx": -1.0, "fy": -1.0, "rx": -1.0, "ry": -1.0, "kite": false, "think": 0.0,
		"post": -1, "slot": 0, "sx": -1.0, "sy": -1.0})


func _invalidate() -> void:
	paths.clear()
	stand_cache.clear()
	path_revision += 1


func get_building(id: int) -> Dictionary:
	for b in buildings:
		if int(b["id"]) == id:
			return b
	return {}


func get_unit(id: int) -> Dictionary:
	for u in units:
		if int(u["id"]) == id:
			return u
	return {}


func center(b: Dictionary) -> Vector2:
	return Vector2(float(b["x"]) + float(b["size"]) / 2, float(b["y"]) + float(b["size"]) / 2)


func position_of(u: Dictionary) -> Vector2:
	return Vector2(float(u["x"]), float(u["y"]))


func tile_of(u: Dictionary) -> Vector2i:
	return Vector2i(floori(float(u["x"])), floori(float(u["y"])))


func village_level() -> int:
	var level: int = 1
	for threshold in XP_LEVELS:
		if xp >= threshold:
			level += 1
	return level - 1


func _affordable(cost: Dictionary) -> bool:
	for resource in cost:
		if float(resources.get(resource, 0)) < float(cost[resource]):
			return false
	return true


func _spend(cost: Dictionary) -> bool:
	if not _affordable(cost):
		return false
	for resource in cost:
		resources[resource] = float(resources.get(resource, 0)) - float(cost[resource])
	return true


func building_cost(type_name: String, tier: int = 1) -> Dictionary:
	var spec: Dictionary = building_specs.get(type_name, {})
	var cost: Dictionary = {}
	var curve: Array = spec.get("costCurve", [])
	var multiplier: float = float(curve[mini(tier - 1, curve.size() - 1)]) if not curve.is_empty() else float(tier)
	for resource in spec.get("cost", {}):
		cost[resource] = ceili(float(spec["cost"][resource]) * multiplier)
	var extra: Dictionary = spec.get("tierCosts", {}).get(str(tier), {})
	for resource in extra:
		cost[resource] = int(cost.get(resource, 0)) + int(extra[resource])
	return cost


func unlock_reason(id: String) -> String:
	# One registry for buildings, professions, equipment and behaviour. Nothing
	# outside it is reachable, and nothing in it has two owners.
	if chronicle.is_unlocked(id):
		return ""
	var spec: Dictionary = building_specs.get(id, {})
	if bool(spec.get("project", false)):
		if not chronicle.effect("command:great-works-permit"):
			return "Requires the Great Works charter."
		return "No Great Work has been chartered for this yet."
	var source: String = chronicle.source_of(id)
	if source.is_empty():
		return "Not yet. Research or story has to introduce this."
	return "Not yet."


func playable_building_types() -> Array[String]:
	var out: Array[String] = []
	for type_name: Variant in building_specs:
		if not bool(building_specs[type_name].get("project", false)):
			out.append(str(type_name))
	return out


func playable_roles() -> Array[String]:
	var out: Array[String] = []
	for role: Variant in troop_specs:
		out.append(str(role))
	return out


func build_reason(type_name: String, x: int, y: int, ignore_id: int = -1) -> String:
	var spec: Dictionary = building_specs.get(type_name, {})
	if spec.is_empty():
		return "Unknown building."
	if ignore_id < 0:
		var gate: String = unlock_reason(type_name)
		if not gate.is_empty():
			return gate
	var size: int = int(spec["size"])
	if x < 0 or y < 0 or x + size > 20 or y + size > 16:
		return "Outside the village."
	var bounds := Rect2i(x, y, size, size)
	for b in buildings:
		if int(b["id"]) != ignore_id and bounds.intersects(Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"]))):
			return "This footprint is occupied."
	if ignore_id >= 0:
		return "" if not raid_active and not raid_warning else "No relocation during raids."
	if village_level() < int(spec.get("minLevel", 1)):
		return "Requires village level %d." % int(spec["minLevel"])
	var limit: Variant = spec.get("maxCount", 999)
	if limit is Array:
		limit = limit[mini(village_level() - 1, limit.size() - 1)]
	var count: int = 0
	for b in buildings:
		if b["type"] == type_name and b["hp"] > 0:
			count += 1
	if count >= int(limit):
		return "Building limit reached."
	return "" if _affordable(building_cost(type_name)) else "Not enough resources."


func build(type_name: String, x: int, y: int) -> bool:
	notice = build_reason(type_name, x, y)
	if not notice.is_empty():
		return false
	_spend(building_cost(type_name))
	buildings.append(_new_building(type_name, x, y, true))
	revision += 1
	_invalidate()
	notice = "Raising %s." % building_specs[type_name]["name"]
	return true


func _scaled_cost(cost: Dictionary, count: int) -> Dictionary:
	var total: Dictionary = {}
	for resource: Variant in cost:
		total[resource] = int(cost[resource]) * count
	return total


func build_row_reason(type_name: String, tiles: Array[Vector2i]) -> String:
	if type_name not in ["wall", "stonewall"]:
		return "Wall-row placement is only for walls."
	if tiles.is_empty():
		return "Choose at least one wall tile."
	var same_x: bool = true
	var same_y: bool = true
	var unique: Dictionary = {}
	for tile: Vector2i in tiles:
		same_x = same_x and tile.x == tiles[0].x
		same_y = same_y and tile.y == tiles[0].y
		var key := "%d,%d" % [tile.x, tile.y]
		if unique.has(key):
			return "Wall row contains the same tile twice."
		unique[key] = true
	if not same_x and not same_y:
		return "Drag a straight wall row."
	var sorted: Array[Vector2i] = tiles.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a.y < b.y) if same_x else (a.x < b.x))
	for index in range(1, sorted.size()):
		if absi(sorted[index].x - sorted[index - 1].x) + absi(sorted[index].y - sorted[index - 1].y) != 1:
			return "Wall row must be continuous."
	var spec: Dictionary = building_specs.get(type_name, {})
	if spec.is_empty() or int(spec.get("size", 1)) != 1:
		return "This wall cannot be placed as a row."
	var limit: Variant = spec.get("maxCount", 999)
	if limit is Array:
		limit = limit[mini(village_level() - 1, limit.size() - 1)]
	var standing: int = 0
	for b: Dictionary in buildings:
		if str(b["type"]) == type_name and float(b["hp"]) > 0:
			standing += 1
	if standing + tiles.size() > int(limit):
		return "Building limit reached."
	var total_cost: Dictionary = _scaled_cost(building_cost(type_name), tiles.size())
	if not _affordable(total_cost):
		return "Not enough resources for %d wall segments." % tiles.size()
	for tile: Vector2i in tiles:
		var reason: String = build_reason(type_name, tile.x, tile.y)
		if not reason.is_empty():
			return reason
	return ""


func build_row(type_name: String, tiles: Array[Vector2i]) -> bool:
	notice = build_row_reason(type_name, tiles)
	if not notice.is_empty():
		return false
	_spend(_scaled_cost(building_cost(type_name), tiles.size()))
	for tile: Vector2i in tiles:
		buildings.append(_new_building(type_name, tile.x, tile.y, true))
	revision += 1
	_invalidate()
	notice = "Raising %d %s segments." % [tiles.size(), str(building_specs[type_name]["name"])]
	return true


func _wall_match(x: int, y: int, type_name: String, tier: int) -> int:
	for b: Dictionary in buildings:
		if int(b["x"]) == x and int(b["y"]) == y and str(b["type"]) == type_name and int(b["tier"]) == tier and float(b["hp"]) > 0:
			return int(b["id"])
	return -1


func wall_row(id: int) -> Array[int]:
	var selected: Dictionary = get_building(id)
	if selected.is_empty() or str(selected["type"]) not in ["wall", "stonewall"] or int(selected["size"]) != 1:
		return []
	var type_name: String = str(selected["type"])
	var tier: int = int(selected["tier"])
	var x: int = int(selected["x"])
	var y: int = int(selected["y"])
	var horizontal: Array[int] = [id]
	var vertical: Array[int] = [id]
	for direction in [-1, 1]:
		var cursor: int = x + direction
		while cursor >= 0 and cursor < 20:
			var found: int = _wall_match(cursor, y, type_name, tier)
			if found < 0:
				break
			if direction < 0: horizontal.push_front(found)
			else: horizontal.append(found)
			cursor += direction
	for direction in [-1, 1]:
		var cursor: int = y + direction
		while cursor >= 0 and cursor < 16:
			var found: int = _wall_match(x, cursor, type_name, tier)
			if found < 0:
				break
			if direction < 0: vertical.push_front(found)
			else: vertical.append(found)
			cursor += direction
	return horizontal if horizontal.size() >= vertical.size() else vertical


func upgrade_wall_row_reason(id: int) -> String:
	var ids: Array[int] = wall_row(id)
	if ids.size() <= 1:
		return "No matching wall row is connected here."
	var total: Dictionary = {}
	for wall_id: int in ids:
		var b: Dictionary = get_building(wall_id)
		if float(b["remaining"]) > 0 or float(b["hp"]) <= 0:
			return "Finish or repair the whole row first."
		var spec: Dictionary = building_specs[b["type"]]
		if int(b["tier"]) >= spec["tiers"].size():
			return "This row is already at maximum tier."
		var next: int = int(b["tier"]) + 1
		var required: int = int(spec.get("tierGates", {}).get(str(next), 1))
		if village_level() < required:
			return "Requires village level %d." % required
		var cost: Dictionary = building_cost(str(b["type"]), next)
		for resource: Variant in cost:
			total[resource] = int(total.get(resource, 0)) + int(cost[resource])
	return "" if _affordable(total) else "Not enough resources to upgrade the whole row."


func upgrade_wall_row(id: int) -> bool:
	notice = upgrade_wall_row_reason(id)
	if not notice.is_empty():
		return false
	var ids: Array[int] = wall_row(id)
	var total: Dictionary = {}
	for wall_id: int in ids:
		var b: Dictionary = get_building(wall_id)
		var cost: Dictionary = building_cost(str(b["type"]), int(b["tier"]) + 1)
		for resource: Variant in cost:
			total[resource] = int(total.get(resource, 0)) + int(cost[resource])
	_spend(total)
	for wall_id: int in ids:
		var b: Dictionary = get_building(wall_id)
		b["tier"] = int(b["tier"]) + 1
		b["max_hp"] = float(building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]["hp"])
		b["remaining"] = float(building_specs[b["type"]]["buildSeconds"])
		b["hp"] = float(b["max_hp"])
	revision += 1
	_invalidate()
	notice = "Wall row upgrade underway / %d segments." % ids.size()
	return true


func move_building(id: int, x: int, y: int) -> bool:
	var b: Dictionary = get_building(id)
	if b.is_empty() or b["remaining"] > 0:
		notice = "Wait until construction finishes."
		return false
	notice = build_reason(b["type"], x, y, id)
	if not notice.is_empty():
		return false
	b["x"] = x
	b["y"] = y
	revision += 1
	_invalidate()
	notice = "Building moved."
	return true


func upgrade_reason(id: int) -> String:
	var b: Dictionary = get_building(id)
	if b.is_empty():
		return "Unknown building."
	if b["remaining"] > 0 or b["hp"] <= 0:
		return "Finish construction or repair the ruin first."
	var spec: Dictionary = building_specs[b["type"]]
	if int(b["tier"]) >= spec["tiers"].size():
		return "Maximum gameplay tier."
	var next: int = int(b["tier"]) + 1
	var required: int = int(spec.get("tierGates", {}).get(str(next), 1))
	if village_level() < required:
		return "Requires village level %d." % required
	return "" if _affordable(building_cost(b["type"], next)) else "Not enough resources to upgrade."


func upgrade(id: int) -> bool:
	notice = upgrade_reason(id)
	if not notice.is_empty():
		return false
	var b: Dictionary = get_building(id)
	_spend(building_cost(b["type"], int(b["tier"]) + 1))
	b["tier"] = int(b["tier"]) + 1
	b["max_hp"] = float(building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]["hp"])
	b["remaining"] = float(building_specs[b["type"]]["buildSeconds"])
	b["hp"] = float(b["max_hp"])
	revision += 1
	notice = "Upgrade underway."
	return true


func repair(id: int) -> bool:
	var b: Dictionary = get_building(id)
	if b.is_empty() or b["remaining"] > 0:
		return false
	# Tool Standardization: the same wall costs less timber to put back up.
	var per_wood: float = 15.0 * (1.0 - minf(0.6, chronicle.bonus("repair")))
	var wood: int = mini(int(resources["wood"]), ceili((float(b["max_hp"]) - float(b["hp"])) / per_wood))
	if wood <= 0:
		notice = "No repair needed, or not enough Wood."
		return false
	resources["wood"] -= wood
	b["hp"] = minf(float(b["max_hp"]), float(b["hp"]) + wood * 15)
	revision += 1
	_invalidate()
	notice = "Repaired / %d Wood." % wood
	return true


func reserve_cap(b: Dictionary) -> float:
	var harvest: Dictionary = building_specs[b["type"]].get("harvest", {})
	return float(harvest.get("capacity", 0)) + float(harvest.get("perTier", 0)) * (int(b["tier"]) - 1)


func storage_cap(resource: String) -> float:
	var value: float = float(world_specs.get("storageBase", {}).get(resource, 0))
	for b in buildings:
		if b["hp"] > 0 and b["remaining"] <= 0:
			var amount: float = float(building_specs[b["type"]].get("storage", {}).get(resource, 0))
			value += amount * float(building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]["rateMultiplier"])
	return value


func _bank(resource: String, amount: float, harvest: bool = false) -> int:
	var accepted: int = maxi(0, mini(floori(amount), floori(storage_cap(resource) - float(resources.get(resource, 0)))))
	resources[resource] = float(resources.get(resource, 0)) + accepted
	if harvest:
		gathered[resource] = float(gathered.get(resource, 0)) + accepted
	return accepted


func collect(id: int) -> int:
	var b: Dictionary = get_building(id)
	if b.is_empty() or b["hp"] <= 0 or b["remaining"] > 0:
		return 0
	var resource: Variant = building_specs[b["type"]].get("production")
	if resource == null:
		return 0
	var accepted: int = _bank(resource, float(b["reserve"]), true)
	b["reserve"] -= accepted
	if accepted > 0:
		notice = "+%d %s." % [accepted, str(resource).capitalize()]
		var point: Vector2 = center(b)
		events.append({"kind": "collect", "resource": resource, "amount": accepted, "x": point.x, "y": point.y})
	elif b["reserve"] >= 1:
		notice = "Central stores are full / goods remain at the workplace."
	return accepted


func collect_all() -> int:
	var total: int = 0
	for b in buildings:
		total += collect(int(b["id"]))
	return total


func beds() -> int:
	var total: int = 6
	for b in buildings:
		var housing: Array = building_specs[b["type"]].get("housing", [])
		if b["hp"] > 0 and b["remaining"] <= 0 and not housing.is_empty():
			total += int(housing[mini(int(b["tier"]) - 1, housing.size() - 1)])
	return total


func recruit_reason(role: String) -> String:
	if not troop_specs.has(role):
		return "Unknown role."
	var gate: String = unlock_reason(role)
	if not gate.is_empty():
		return gate
	if units.size() >= beds():
		return "No free beds / build or upgrade a Cottage."
	if troop_specs[role]["role"] == "combat":
		var found: bool = false
		for b in buildings:
			if b["type"] == "barracks" and b["hp"] > 0 and b["remaining"] <= 0:
				found = true
		if not found:
			return "Finish a Barracks first."
	return "" if _affordable(troop_specs[role]["recruitCost"]) else "Not enough resources to hire."


func recruit(role: String) -> bool:
	notice = recruit_reason(role)
	if not notice.is_empty():
		return false
	_spend(troop_specs[role]["recruitCost"])
	_add_unit(role)
	_auto_assign()
	notice = "A %s joins the village." % troop_specs[role]["name"]
	return true


func assign(unit_id: int, building_id: int) -> bool:
	var u: Dictionary = get_unit(unit_id)
	if u.is_empty():
		return false
	if building_id < 0:
		u["workplace"] = -1
		u["post"] = -1
		u["slot"] = 0
		u["sx"] = -1.0
		u["sy"] = -1.0
		paths.erase(unit_id)
		stand_cache.clear()
		notice = "Worker released."
		return true
	var b: Dictionary = get_building(building_id)
	if b.is_empty() or b["hp"] <= 0 or b["remaining"] > 0:
		notice = "That workplace is not ready."
		return false
	var workplace: String = str(building_specs[b["type"]].get("workplace", ""))
	var is_post: bool = GUARD_POSTS.has(str(b["type"]))
	var is_defender: bool = str(troop_specs[u["type"]]["role"]) == "combat"
	if workplace != str(u["type"]) and not (is_post and is_defender):
		notice = "This profession does not match that workplace."
		return false
	var count: int = 0
	for other in units:
		if int(other["id"]) != unit_id and int(other["workplace"]) == building_id:
			count += 1
	if count >= 2:
		notice = "This workplace crew is full."
		return false
	u["workplace"] = building_id
	u["post"] = -1
	u["slot"] = 0
	u["sx"] = -1.0
	u["sy"] = -1.0
	u["hold"] = false
	u["order"] = []
	paths.erase(unit_id)
	stand_cache.clear()
	notice = "Worker assigned."
	return true


func _auto_assign() -> void:
	var previous_notice: String = notice
	for u in units:
		if int(u["workplace"]) >= 0 or not u["order"].is_empty() or u["hold"]:
			continue
		for b in buildings:
			if str(building_specs[b["type"]].get("workplace", "")) == str(u["type"]) and assign(int(u["id"]), int(b["id"])):
				break
	notice = previous_notice


func order_unit(id: int, x: float, y: float, hold_position: bool = false) -> bool:
	var u: Dictionary = get_unit(id)
	if u.is_empty() or not is_finite(x) or not is_finite(y) or x < 0 or x >= 20 or y < 0 or y >= 16:
		return false
	var goal := Vector2i(floori(x), floori(y))
	if not hold_position and _blocked(goal, false):
		notice = "Choose open ground."
		return false
	u["order"] = [x, y]
	u["hold"] = hold_position
	paths.erase(id)
	return true


func train(id: int) -> bool:
	var u: Dictionary = get_unit(id)
	if u.is_empty() or int(u["level"]) >= int(troop_specs[u["type"]]["maxLevel"]):
		return false
	var cost: Dictionary = troop_specs[u["type"]]["levelCost"].duplicate()
	# Education: the school makes further training cheaper.
	var discount: float = minf(0.6, chronicle.bonus("school-lessons"))
	for resource in cost:
		cost[resource] = ceilf(float(cost[resource]) * float(u["level"]) * (1.0 - discount))
	if not _spend(cost):
		notice = "Not enough resources to train."
		return false
	u["level"] += 1
	u["max_hp"] = _stat(u, "hp")
	u["hp"] = u["max_hp"]
	notice = "Training complete / level %d." % u["level"]
	return true


func _stat(u: Dictionary, stat: String) -> float:
	var spec: Dictionary = troop_specs[u["type"]]
	return float(spec["base"].get(stat, 0)) * (1 + float(spec["growth"].get(stat, 0)) * (int(u["level"]) - 1))


func _inside(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < 20 and tile.y >= 0 and tile.y < 16


func _blocked(tile: Vector2i, enemy: bool) -> bool:
	for b in buildings:
		if b["hp"] <= 0 or b["type"] == "trap" or (b["type"] == "gate" and not enemy and b.get("gate_open", true)):
			continue
		if Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"])).has_point(tile):
			return true
	return false


func route(start: Vector2i, goal: Vector2i, enemy: bool = false) -> Array[Vector2i]:
	if not enemy and living.navigation_revision > 0:
		return _weighted_route(start, goal)
	var result: Array[Vector2i] = []
	if not _inside(start) or not _inside(goal):
		return result
	if start == goal:
		return [start]
	if _blocked(goal, enemy):
		return result
	var previous: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var index: int = 0
	while index < queue.size():
		var tile: Vector2i = queue[index]
		index += 1
		for direction in DIRECTIONS:
			var next: Vector2i = tile + direction
			if not _inside(next) or previous.has(next) or _blocked(next, enemy):
				continue
			previous[next] = tile
			queue.append(next)
			if next == goal:
				var step: Vector2i = goal
				while step != start:
					result.push_front(step)
					step = previous[step]
				result.push_front(start)
				return result
	return result


func _weighted_route(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _inside(start) or not _inside(goal): return result
	if start == goal: return [start]
	if _blocked(goal, false): return result
	var frontier: Array[Vector2i] = [start]
	var distances: Dictionary = {start: 0.0}
	var previous: Dictionary = {}
	while not frontier.is_empty():
		var best: int = 0
		for index in range(1, frontier.size()):
			if float(distances[frontier[index]]) < float(distances[frontier[best]]): best = index
		var tile: Vector2i = frontier[best]
		frontier.remove_at(best)
		if tile == goal:
			while tile != start:
				result.push_front(tile)
				tile = previous[tile]
			result.push_front(start)
			return result
		for direction in DIRECTIONS:
			var next: Vector2i = tile + direction
			if not _inside(next) or _blocked(next, false): continue
			var cost: float = float(distances[tile]) + living.route_cost(next)
			if cost < float(distances.get(next, INF)):
				distances[next] = cost
				previous[next] = tile
				if not frontier.has(next): frontier.append(next)
	return result


func stand_candidates(b: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for offset in workplace_specs.get(str(b["type"]), {}).get("stands", []):
		if offset is Array and offset.size() == 2:
			result.append(center(b) + Vector2(float(offset[0]), float(offset[1])))
	return result


func job_target(b: Dictionary) -> Vector2:
	var target: Variant = workplace_specs.get(str(b["type"]), {}).get("target", [])
	if target is Array and target.size() == 2:
		return center(b) + Vector2(float(target[0]), float(target[1]))
	return center(b)


func stand_tile(b: Dictionary, slot: int) -> Vector2:
	var candidates := stand_candidates(b)
	return candidates[posmod(slot, candidates.size())] if not candidates.is_empty() else Vector2(-1, -1)


func _declared_stands(b: Dictionary, except_slot: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var candidates := stand_candidates(b)
	for index in candidates.size():
		if index != posmod(except_slot, candidates.size()):
			result.append(candidates[index])
	return result


func _stand_slot(u: Dictionary, workplace_id: int) -> int:
	# The reservation lives on the unit, so it survives save and load with no world-wide table.
	if int(u.get("post", -1)) == workplace_id:
		return int(u.get("slot", 0))
	var taken: Dictionary = {}
	for other: Dictionary in units:
		if int(other["id"]) != int(u["id"]) and int(other.get("post", -1)) == workplace_id:
			taken[int(other.get("slot", 0))] = true
	var slot: int = 0
	while taken.has(slot):
		slot += 1
	if int(u["workplace"]) == workplace_id:
		u["post"] = workplace_id
		u["slot"] = slot
	return slot


func _walkable(start: Vector2i, point: Vector2) -> bool:
	var goal := Vector2i(floori(point.x), floori(point.y))
	if not _inside(goal) or _blocked(goal, false):
		return false
	return not route(start, goal, false).is_empty()


func edge_candidates(b: Dictionary, enemy: bool = false) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if b.is_empty():
		return result
	for x in range(int(b["x"]) - 1, int(b["x"]) + int(b["size"]) + 1):
		for y in range(int(b["y"]) - 1, int(b["y"]) + int(b["size"]) + 1):
			var tile := Vector2i(x, y)
			if _inside(tile) and not _blocked(tile, enemy):
				result.append(Vector2(tile) + Vector2.ONE * 0.5)
	return result


func _declared(b: Dictionary, slot: int, excluded: Array[Vector2]) -> Vector2:
	var candidates := stand_candidates(b)
	for offset in candidates.size():
		var point: Vector2 = candidates[(slot + offset) % candidates.size()]
		if not excluded.has(point):
			return point
	return Vector2(-1, -1)


func _held_stand(u: Dictionary) -> Vector2:
	return Vector2(float(u.get("sx", -1.0)), float(u.get("sy", -1.0)))


func _remember_stand(u: Dictionary, point: Vector2) -> void:
	u["sx"] = point.x
	u["sy"] = point.y


func _resolve_stand(u: Dictionary, b: Dictionary, excluded: Array[Vector2]) -> Vector2:
	# The reserved stand first, then any other reachable safe edge, then wait.
	var start := tile_of(u)
	var point: Vector2 = _declared(b, _stand_slot(u, int(b["id"])), excluded)
	if point.x >= 0 and _walkable(start, point):
		_remember_stand(u, point)
		return point
	var best := Vector2(-1, -1)
	var best_distance: float = INF
	for edge in edge_candidates(b):
		if excluded.has(edge) or not _walkable(start, edge):
			continue
		var distance: float = position_of(u).distance_squared_to(edge)
		if distance < best_distance:
			best_distance = distance
			best = edge
	_remember_stand(u, best)
	return best


func work_position(u: Dictionary, b: Dictionary) -> Vector2:
	# Reserved crew stand first, then any other reachable safe edge, then wait.
	if b.is_empty():
		return Vector2(-1, -1)
	var start := tile_of(u)
	var crew: String = ""
	for other: Dictionary in units:
		if int(other["workplace"]) == int(b["id"]):
			var tile := tile_of(other)
			crew += "%d@%d,%d;" % [int(other["id"]), tile.x, tile.y]
	var key: String = "%d|%d|%d,%d|%d|%s" % [int(b["id"]), int(u["id"]), start.x, start.y, revision, crew]
	if stand_cache.has(key):
		return stand_cache[key]
	if stand_candidates(b).is_empty():
		stand_cache[key] = _edge_goal(u, b)
		return stand_cache[key]
	var _slot: int = _stand_slot(u, int(b["id"]))
	var taken: Array[Vector2] = []
	for other: Dictionary in units:
		if int(other["id"]) == int(u["id"]) or int(other["workplace"]) != int(b["id"]):
			continue
		var other_slot: int = _stand_slot(other, int(b["id"]))
		var other_held: Vector2 = _held_stand(other)
		if other_held.x < 0 or not _walkable(tile_of(other), other_held):
			other_held = stand_tile(b, other_slot)
			if not _walkable(tile_of(other), other_held):
				other_held = Vector2(-1, -1)
		if other_held.x >= 0:
			taken.append(other_held)
	var held: Vector2 = _held_stand(u)
	if held.x >= 0 and not taken.has(held) and _walkable(start, held):
		stand_cache[key] = held
		return held
	var resolved: Vector2 = _resolve_stand(u, b, taken)
	stand_cache[key] = resolved
	return resolved


func facing_target(u: Dictionary) -> Vector2:
	var x: float = float(u.get("fx", -1.0))
	var y: float = float(u.get("fy", -1.0))
	if x >= 0 and y >= 0 and is_finite(x) and is_finite(y):
		return Vector2(x, y)
	return position_of(u)


func _face_job(u: Dictionary, b: Dictionary) -> void:
	var point: Vector2 = job_target(b)
	u["fx"] = point.x
	u["fy"] = point.y


func _clear_facing(u: Dictionary) -> void:
	u["fx"] = -1.0
	u["fy"] = -1.0


func _edge_goal(u: Dictionary, b: Dictionary, enemy: bool = false) -> Vector2:
	var candidates: Array[Vector2] = edge_candidates(b, enemy)
	var start := Vector2i(floori(float(u["x"])), floori(float(u["y"])))
	var best := Vector2(-1, -1)
	var best_distance: float = INF
	for point: Vector2 in candidates:
		var distance: float = position_of(u).distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	if best.x >= 0 and not route(start, Vector2i(floori(best.x), floori(best.y)), enemy).is_empty():
		return best
	# A nearby edge can be sealed while the far entrance is still reachable.
	for point: Vector2 in candidates:
		if not route(start, Vector2i(floori(point.x), floori(point.y)), enemy).is_empty():
			return point
	return Vector2(-1, -1)


# Memoized edge goals: same result as _edge_goal, recomputed only when the
# unit changed tiles, the target building changed, or the world revision
# moved (walls/demolitions). Cached values ride on the unit dict, so they
# vanish with the unit and never touch saves (validation ignores extra keys).
func _cached_edge_goal(u: Dictionary, b: Dictionary, enemy: bool = false) -> Vector2:
	var tile := Vector2i(floori(float(u["x"])), floori(float(u["y"])))
	var bid: int = int(b.get("id", -1))
	# Type guards: older saves may carry these keys as JSON strings.
	var cached_tile: Variant = u.get("edge_tile")
	var cached_goal: Variant = u.get("edge_goal")
	if u.get("edge_rev") == revision and cached_tile is Vector2i and cached_tile == tile and int(u.get("edge_bid", -999)) == bid and cached_goal is Vector2:
		return cached_goal
	var goal: Vector2 = _edge_goal(u, b, enemy)
	u["edge_goal"] = goal
	u["edge_tile"] = tile
	u["edge_rev"] = revision
	u["edge_bid"] = bid
	return goal


# Reachability without a wasted pathfind: _walk's own paths cache already
# proves a goal reachable for this revision, so only probe route() on miss.
func _path_reachable(u: Dictionary, target: Vector2, enemy: bool) -> bool:
	var goal := Vector2i(floori(target.x), floori(target.y))
	var cached: Dictionary = paths.get(int(u["id"]), {})
	if not cached.is_empty() and cached.get("goal") == goal and cached.get("revision") == revision:
		return true
	var start := Vector2i(floori(float(u["x"])), floori(float(u["y"])))
	if start == goal:
		return true
	return not route(start, goal, enemy).is_empty()


func _walk(u: Dictionary, target: Vector2, dt: float, enemy: bool = false) -> bool:
	if target.x < 0:
		return false
	var id: int = int(u["id"])
	var start := Vector2i(floori(float(u["x"])), floori(float(u["y"])))
	var goal := Vector2i(floori(target.x), floori(target.y))
	var cached: Dictionary = paths.get(id, {})
	if cached.is_empty() or cached.get("goal") != goal or cached.get("revision") != revision:
		var fresh: Array[Vector2i] = route(start, goal, enemy)
		if fresh.is_empty():
			return false
		fresh.pop_front()
		cached = {"goal": goal, "revision": revision, "steps": fresh}
		paths[id] = cached
	var steps: Array = cached["steps"]
	var waypoint: Vector2 = Vector2(steps[0]) + Vector2.ONE * 0.5 if not steps.is_empty() else target
	var before: Vector2 = position_of(u)
	var speed: float = (1.2 if enemy else _stat(u, "speed") * living.speed_at(before)) * dt
	var point: Vector2 = before.move_toward(waypoint, speed)
	if not enemy:
		living.walked(before, point, elapsed)
	u["x"] = point.x
	u["y"] = point.y
	u["phase"] = "walk"
	if not steps.is_empty() and point.distance_to(waypoint) < 0.01:
		steps.pop_front()
	return point.distance_to(target) < 0.05


func _hall() -> Dictionary:
	for b in buildings:
		if b["type"] == "hall":
			return b
	return {}


func tick(dt: float) -> void:
	if paused or not is_finite(dt) or dt <= 0 or dt > 1:
		return
	tick_count += 1
	elapsed += dt
	_gate_tick()
	job_timer += dt
	if job_timer >= 5:
		job_timer = 0
		_auto_assign()
	for b in buildings:
		b["cooldown"] = maxf(0, float(b["cooldown"]) - dt)
		if b["hp"] <= 0:
			continue
		if b["remaining"] > 0:
			if not raid_active and not raid_warning:
				b["remaining"] = maxf(0, float(b["remaining"]) - dt)
			continue
		var spec: Dictionary = building_specs[b["type"]]
		if spec.get("production") != null:
			var posted: bool = false
			for u in units:
				if int(u["workplace"]) == int(b["id"]) and u["hp"] > 0 and u["order"].is_empty() and not u["hold"] and not raid_active and not raid_warning:
					posted = true
			var rate: float = float(spec["rate"]) * float(spec["tiers"][int(b["tier"]) - 1]["rateMultiplier"]) * (1.25 if posted else 1.0)
			# Moon Orchards / Full Granaries: food production, not a flat buff.
			if str(spec.get("production", "")) == "food":
				rate *= 1.0 + chronicle.bonus("growth")
			b["reserve"] = maxf(float(b["reserve"]), minf(reserve_cap(b), float(b["reserve"]) + rate * dt))
		for recipe: Dictionary in spec.get("refine", []):
			_refine(recipe, dt)
	for u in units:
		u["cooldown"] = maxf(0, float(u["cooldown"]) - dt)
		if not raid_active and not raid_warning and u["hp"] > 0 and u["hp"] < u["max_hp"]:
			# Village Medicine / Field Medicine: recovery between horns.
			u["hp"] = minf(float(u["max_hp"]), float(u["hp"]) + float(u["max_hp"]) * (0.012 + chronicle.bonus("heal")) * dt)
		_unit_tick(u, dt)
	_raid_tick(dt)
	_automation_tick(dt)
	living.tick(self, dt)
	if navigation_revision != living.navigation_revision:
		navigation_revision = living.navigation_revision
		paths.clear()
	_quest_tick()
	for resource in pending_rewards.keys():
		pending_rewards[resource] -= _bank(resource, float(pending_rewards[resource]))
	if not raid_active and not raid_warning and units.size() < beds() and float(resources.get("food", 0)) >= 30:
		birth_timer += dt
		if birth_timer >= 60:
			birth_timer = 0
			resources["food"] -= 20
			_add_unit("farmer")
			_auto_assign()
			notice = "Warm beds and full bellies / a new villager joins."


func _gate_tick() -> void:
	for b in buildings:
		if b["type"] != "gate": continue
		var open: bool = true
		for enemy in enemies:
			if enemy["hp"] > 0 and center(b).distance_to(position_of(enemy)) < 1.8:
				open = false
		if bool(b.get("gate_open", true)) != open:
			b["gate_open"] = open
			_invalidate()


# Research that changes behaviour instead of percentages. Runs on a slow clock:
# these are standing orders, not per-frame decisions.
var auto_clock: float = 0.0
const AUTO_INTERVAL: float = 10.0

func _automation_tick(dt: float) -> void:
	auto_clock += dt
	if auto_clock < AUTO_INTERVAL:
		return
	auto_clock = 0.0
	if raid_active or raid_warning:
		return
	if chronicle.effect("command:auto-post"):
		_auto_post()
	if chronicle.effect("command:auto-pave"):
		_auto_pave()


# Organized Watch: Guard Posts fill themselves from idle defenders.
func _auto_post() -> void:
	var posts: Array[Dictionary] = []
	for b in buildings:
		if float(b["hp"]) <= 0.0 or float(b.get("remaining", 0.0)) > 0.0:
			continue
		if GUARD_POSTS.has(str(b["type"])):
			posts.append(b)
	for post in posts:
		var posted: int = 0
		for u: Dictionary in units:
			if int(u["workplace"]) == int(post["id"]):
				posted += 1
		if posted >= 2:
			continue
		for u: Dictionary in units:
			if float(u["hp"]) <= 0.0 or not u["order"].is_empty() or u["hold"]:
				continue
			if str(troop_specs[u["type"]]["role"]) != "combat":
				continue
			var previous: String = notice
			if assign(int(u["id"]), int(post["id"])):
				notice = previous
				posted += 1
			if posted >= 2:
				break


# Road Masonry: builders convert heavily used dirt trails into permanent roads.
func _auto_pave() -> void:
	var cost: int = int(living.config["stone"]["pave_cost"])
	if not _affordable({"stone": cost}):
		return
	var builders: int = 0
	for u: Dictionary in units:
		if str(u["type"]) == "builder" and float(u["hp"]) > 0.0 and not u["hold"]:
			builders += 1
	if builders <= 0:
		return
	var previous: String = notice
	for id: String in living.cells.keys():
		if builders <= 0:
			break
		var cell: Dictionary = living.cells[id]
		if bool(cell.get("stone", false)) or float(cell.get("wear", 0.0)) < 0.999:
			continue
		var parts: PackedStringArray = id.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		if living.pave(self, Vector2i(int(parts[0]), int(parts[1]))):
			builders -= 1
	notice = previous


func _refine(recipe: Dictionary, dt: float) -> void:
	var times: float = float(recipe["perSec"]) * dt
	for resource in recipe["in"]:
		times = minf(times, float(resources.get(resource, 0)) / float(recipe["in"][resource]))
	for resource in recipe["out"]:
		times = minf(times, maxf(0, storage_cap(resource) - float(resources.get(resource, 0))) / float(recipe["out"][resource]))
	if times <= 0:
		return
	for resource in recipe["in"]:
		resources[resource] -= float(recipe["in"][resource]) * times
	for resource in recipe["out"]:
		resources[resource] = float(resources.get(resource, 0)) + float(recipe["out"][resource]) * times


func _unit_tick(u: Dictionary, dt: float) -> void:
	if u["hp"] <= 0:
		u["phase"] = "death"
		return
	u["phase"] = "idle"
	u["think"] = maxf(0.0, float(u.get("think", 0.0)) - dt)
	if not u["order"].is_empty():
		if u["hold"] and troop_specs[u["type"]]["role"] == "combat":
			_fighter(u, dt)
		elif not u["hold"]:
			_clear_facing(u)
			if _walk(u, Vector2(float(u["order"][0]), float(u["order"][1])), dt):
				u["order"] = []
		return
	var role: String = str(troop_specs[u["type"]]["role"])
	if role == "combat":
		_fighter(u, dt)
		return
	if raid_active or raid_warning:
		_clear_facing(u)
		_walk(u, _cached_edge_goal(u, _hall()), dt)
		return
	if role == "builder":
		for b in buildings:
			if b["remaining"] > 0 and b["hp"] > 0:
				_face_job(u, b)
				if _walk(u, _edge_goal(u, b), dt):
					u["phase"] = "work"
				return
		_clear_facing(u)
		return
	if float(u["carry"]) >= 1:
		_clear_facing(u)
		if _walk(u, _edge_goal(u, _hall()), dt):
			var accepted: int = _bank(u["carry_resource"], float(u["carry"]), true)
			u["carry"] -= accepted
			if accepted > 0:
				events.append({"kind": "collect", "resource": u["carry_resource"], "amount": accepted, "x": float(u["x"]), "y": float(u["y"])})
		return
	var workplace: Dictionary = get_building(int(u["workplace"]))
	if workplace.is_empty() or workplace["hp"] <= 0 or workplace["remaining"] > 0:
		_clear_facing(u)
		return
	var stand: Vector2 = work_position(u, workplace)
	if stand.x < 0:
		_clear_facing(u)
		return
	_face_job(u, workplace)
	if _walk(u, stand, dt):
		u["phase"] = "work"
		u["cooldown"] += dt
		if u["cooldown"] >= 2 or float(workplace["reserve"]) >= float(troop_specs[u["type"]]["carry"]):
			var amount: int = mini(floori(float(workplace["reserve"])), int(troop_specs[u["type"]]["carry"]))
			if amount > 0:
				workplace["reserve"] -= amount
				u["carry"] = amount
				u["carry_resource"] = str(building_specs[workplace["type"]]["production"])
				u["cooldown"] = 0


func _nearest_enemy(point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = INF
	for enemy in enemies:
		if enemy["hp"] <= 0:
			continue
		var candidate: float = point.distance_squared_to(position_of(enemy))
		if candidate < distance:
			distance = candidate
			best = enemy
	return best


func _threat_rank(enemy: Dictionary) -> float:
	# The Manor first, then any standing structure; proximity to the defender only breaks ties.
	return _threat_base_rank(enemy, _hall())


func _threat_base_rank(enemy: Dictionary, hall: Dictionary) -> float:
	var point: Vector2 = position_of(enemy)
	var rank: float = 0.0
	if not hall.is_empty():
		rank += 60.0 / (1.0 + _building_distance(point, hall))
	for b: Dictionary in buildings:
		if b["hp"] > 0 and str(b["type"]) != "trap":
			rank += 10.0 / (1.0 + _building_distance(point, b))
	return rank


func _threat_enemy(u: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_rank: float = -INF
	var here: Vector2 = position_of(u)
	if threat_stamp != tick_count:
		threat_stamp = tick_count
		threat_ranks.clear()
		var hall := _hall()
		for enemy in enemies:
			if enemy["hp"] > 0:
				threat_ranks[int(enemy["id"])] = _threat_base_rank(enemy, hall)
	for enemy in enemies:
		if enemy["hp"] <= 0:
			continue
		var rank: float = float(threat_ranks.get(int(enemy["id"]), -INF)) - 0.35 * here.distance_to(position_of(enemy))
		if rank > best_rank:
			best_rank = rank
			best = enemy
	return best


func _flee_point(u: Dictionary, enemy: Dictionary, release: float) -> Vector2:
	var here: Vector2 = position_of(u)
	var here_tile := Vector2i(floori(here.x), floori(here.y))
	var gap: float = here.distance_to(position_of(enemy))
	var options: Array = []
	for x in range(here_tile.x - 3, here_tile.x + 4):
		for y in range(here_tile.y - 3, here_tile.y + 4):
			var tile := Vector2i(x, y)
			if not _inside(tile) or _blocked(tile, false):
				continue
			var point := Vector2(tile) + Vector2.ONE * 0.5
			var away: float = point.distance_to(position_of(enemy))
			if away < release or away <= gap + 0.3:
				continue
			var steps: int = maxi(absi(x - here_tile.x), absi(y - here_tile.y))
			options.append([away - steps * 0.35, point])
	if options.is_empty():
		return Vector2(-1, -1)
	options.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for option: Array in options:
		var point: Vector2 = option[1]
		if route(here_tile, Vector2i(floori(point.x), floori(point.y)), false).is_empty():
			continue
		return point
	return Vector2(-1, -1)


func _close_kite(u: Dictionary) -> void:
	u["kite"] = false
	u["rx"] = -1.0
	u["ry"] = -1.0


func _archer_space(u: Dictionary, enemy: Dictionary) -> Vector2:
	var here: Vector2 = position_of(u)
	var here_tile := Vector2i(floori(here.x), floori(here.y))
	var gap: float = here.distance_to(position_of(enemy))
	var release: float = maxf(KITE_TRIGGER + 0.9, _stat(u, "range") * KITE_RELEASE_RATIO)
	if bool(u.get("kite", false)):
		if gap >= release:
			_close_kite(u)
			return Vector2(-1, -1)
	elif gap > KITE_TRIGGER:
		return Vector2(-1, -1)
	else:
		u["kite"] = true
	var goal := Vector2(float(u.get("rx", -1.0)), float(u.get("ry", -1.0)))
	if goal.x >= 0 and u["think"] > 0 and _walkable(here_tile, goal):
		return goal
	var point: Vector2 = _flee_point(u, enemy, release)
	if point.x < 0:
		_close_kite(u)
		return Vector2(-1, -1)
	u["rx"] = point.x
	u["ry"] = point.y
	u["think"] = KITE_THINK
	return point


func _shot(from: Vector2, to: Vector2) -> void:
	events.append({"kind": "shot", "from_x": from.x, "from_y": from.y, "x": to.x, "y": to.y})


func _fighter(u: Dictionary, dt: float) -> void:
	var enemy: Dictionary = _threat_enemy(u)
	if enemy.is_empty():
		_clear_facing(u)
		_close_kite(u)
		return
	var here: Vector2 = position_of(u)
	var gap: float = here.distance_to(position_of(enemy))
	u["fx"] = position_of(enemy).x
	u["fy"] = position_of(enemy).y
	if str(u["type"]) == "archer" and not u["hold"]:
		# Survival comes first: break from whatever is actually swinging at this archer.
		var closest: Dictionary = _nearest_enemy(here)
		if not closest.is_empty() and (here.distance_to(position_of(closest)) <= KITE_TRIGGER or bool(u.get("kite", false))):
			var space: Vector2 = _archer_space(u, closest)
			if space.x >= 0:
				_walk(u, space, dt)
				return
			_close_kite(u)
	if gap <= _stat(u, "range"):
		u["phase"] = "attack"
		if u["cooldown"] <= 0:
			var damage: float = _stat(u, "damage")
			enemy["hp"] -= damage
			events.append({"kind": "hit", "x": float(enemy["x"]), "y": float(enemy["y"]), "amount": damage, "friendly": false})
			u["cooldown"] = 1.0
			if u["type"] == "archer":
				_shot(here, position_of(enemy))
		return
	if not u["hold"]:
		_walk(u, position_of(enemy), dt)


func start_raid() -> bool:
	if raid_active or raid_warning:
		notice = "A raid is already on the road."
		return false
	if _hall().get("hp", 0) <= 0:
		notice = "Repair the Manor Hall before testing defenses."
		return false
	raid_warning = true
	next_raid_at = elapsed + 3
	notice = "Test wave / horns in 3 seconds."
	return true


func _faction_for_wave(wave_number: int) -> Dictionary:
	var chosen: Dictionary = {}
	for entry: Dictionary in world_specs.get("enemyFactions", []):
		if wave_number < int(entry.get("minWave", 1)): continue
		if village_level() < int(entry.get("minLevel", 1)): continue
		chosen = entry
	return chosen


func _active_faction() -> Dictionary:
	return _faction_for_wave(maxi(1, wave))


func faction_color(id: String) -> Color:
	for entry: Dictionary in world_specs.get("enemyFactions", []):
		if str(entry.get("id", "")) == id:
			return Color(str(entry.get("color", "#997747")))
	return Color("997747")


func raid_faction_name() -> String:
	if raid_active and not enemies.is_empty():
		var faction_id: String = str(enemies[0].get("faction", "thornband"))
		for entry: Dictionary in world_specs.get("enemyFactions", []):
			if str(entry.get("id", "")) == faction_id:
				return str(entry.get("name", "Raiders"))
	var next_faction: Dictionary = _faction_for_wave(maxi(1, wave + 1))
	return str(next_faction.get("name", "Raiders"))


func raid_direction() -> String:
	var wave_number: int = wave if raid_active else wave + 1
	var count: int = mini(int(world_specs["homeRaids"].get("maxCount", 8)), wave_number + 1)
	if count >= 4:
		return "ALL SIDES"
	return ["WEST", "EAST", "NORTH", "SOUTH"][(wave_number - 1) % 4]


func _role_stats(role: String) -> Dictionary:
	return world_specs.get("enemyRoles", {}).get(role, {})


func _spawn_raid() -> void:
	raid_warning = false
	raid_active = true
	wave += 1
	var faction: Dictionary = _active_faction()
	var roles: Array = faction.get("roles", ["raider"])
	var count: int = mini(int(world_specs["homeRaids"].get("maxCount", 8)), wave + 1)
	var base: float = 70.0 + wave * 10.0
	for index in count:
		var side: int = index % 4 if count >= 4 else (wave - 1) % 4
		var point := Vector2(0.5, 3.5 + index * 1.1)
		match side:
			1: point = Vector2(19.5, 4.5 + index)
			2: point = Vector2(5.5 + index, 0.5)
			3: point = Vector2(6.5 + index, 15.5)
		# Hostiles stay "raider" in the save schema; the role drives their stats.
		var role: String = str(roles[index % roles.size()])
		var stats: Dictionary = _role_stats(role)
		var hp: float = base * float(stats.get("hp", 1.0))
		enemies.append({"id": _id(), "type": "raider", "role": role, "faction": str(faction.get("id", "thornband")),
			"x": point.x, "y": point.y, "hp": hp, "max_hp": hp, "phase": "walk", "cooldown": 0.0})
	raid_stats["seconds_held"] = 0.0
	notice = "Wave %d / %s / hold the Manor!" % [wave, str(faction.get("name", "Raiders"))]


func _building_distance(point: Vector2, b: Dictionary) -> float:
	var near := Vector2(clampf(point.x, float(b["x"]), float(b["x"]) + float(b["size"])), clampf(point.y, float(b["y"]), float(b["y"]) + float(b["size"])))
	return point.distance_to(near)


# Watchtower Doctrine: towers shoot siege engines and breakers first instead of
# whoever happens to be nearest. Siege Doctrine widens that list.
func _tower_target(origin: Vector2) -> Dictionary:
	var nearest: Dictionary = _nearest_enemy(origin)
	if not chronicle.effect("command:tower-priority"):
		return nearest
	var wanted: Array[String] = ["ram", "bombard", "breaker"]
	if chronicle.effect("command:siege-response"):
		wanted = ["ram", "bombard", "breaker", "archer", "scout"]
	var best: Dictionary = {}
	var best_distance: float = INF
	for enemy in enemies:
		if float(enemy.get("hp", 0.0)) <= 0.0:
			continue
		if not wanted.has(str(enemy.get("role", "raider"))):
			continue
		var gap: float = origin.distance_to(position_of(enemy))
		if gap < best_distance:
			best_distance = gap
			best = enemy
	return best if not best.is_empty() else nearest


func _raid_tick(dt: float) -> void:
	if not raid_active:
		# Ambient raids stay out of the onboarding lane until the Chronicle has
		# taught defenses. Manual/test and scripted warnings still proceed.
		if not raid_warning and elapsed < 600.0 and "the-first-horn" not in completed_quests:
			# Give a new player ten active minutes to learn the village unless the
			# Chronicle deliberately summons the first defense lesson sooner.
			next_raid_at = maxf(next_raid_at, elapsed + 90.0)
			return
		if _hall().get("hp", 0) > 0 and elapsed >= next_raid_at - 25:
			raid_warning = true
		if raid_warning and elapsed >= next_raid_at:
			_spawn_raid()
		return
	raid_stats["seconds_held"] = float(raid_stats.get("seconds_held", 0.0)) + dt
	for b in buildings:
		if b["hp"] <= 0 or b["remaining"] > 0 or b["cooldown"] > 0:
			continue
		var stats: Dictionary = building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]
		if float(stats["damage"]) <= 0:
			continue
		var enemy: Dictionary = _tower_target(center(b))
		if not enemy.is_empty() and center(b).distance_to(position_of(enemy)) <= float(stats["range"]):
			var damage: float = float(stats["damage"])
			enemy["hp"] -= damage
			b["cooldown"] = (3.0 if chronicle.effect("command:trap-reset") else 5.0) if b["type"] == "trap" else 1.0
			_shot(center(b), position_of(enemy))
			events.append({"kind": "hit", "x": float(enemy["x"]), "y": float(enemy["y"]), "amount": damage, "friendly": false})
	for enemy in enemies:
		if enemy["hp"] <= 0:
			continue
		enemy["cooldown"] = maxf(0, float(enemy["cooldown"]) - dt)
		enemy["phase"] = "idle"
		var opponent: Dictionary = {}
		for u in units:
			if u["hp"] > 0 and troop_specs[u["type"]]["role"] == "combat" and position_of(enemy).distance_to(position_of(u)) < 1.1:
				opponent = u
				break
		if not opponent.is_empty():
			enemy["phase"] = "attack"
			enemy["fx"] = float(opponent["x"])
			enemy["fy"] = float(opponent["y"])
			if enemy["cooldown"] <= 0:
				var damage: float = (8 + wave * 2) * float(_role_stats(str(enemy.get("role", "raider"))).get("damage", 1.0))
				opponent["hp"] = maxf(0, float(opponent["hp"]) - damage)
				events.append({"kind": "hit", "x": float(opponent["x"]), "y": float(opponent["y"]), "amount": damage, "friendly": true})
				enemy["cooldown"] = 1
			continue
		var objective: Dictionary = _hall()
		var goal: Vector2 = _cached_edge_goal(enemy, objective, true)
		if not _path_reachable(enemy, goal, true):
			var nearest: float = INF
			for b in buildings:
				if b["hp"] > 0 and b["type"] != "trap":
					var distance: float = _building_distance(position_of(enemy), b)
					if distance < nearest:
						nearest = distance
						objective = b
			goal = _cached_edge_goal(enemy, objective, true)
		if _building_distance(position_of(enemy), objective) <= 0.8:
			enemy["phase"] = "attack"
			enemy["fx"] = center(objective).x
			enemy["fy"] = center(objective).y
			if enemy["cooldown"] <= 0:
				var wall_mult: float = float(_role_stats(str(enemy.get("role", "raider"))).get("wallDamage", 1.0))
				# Gate Engineering braces a gate while a ram works on it.
				if str(objective["type"]) == "gate" and chronicle.effect("command:gate-brace"):
					wall_mult *= 0.6
				var damage: float = (8 + wave * 2) * wall_mult
				objective["hp"] = maxf(0, float(objective["hp"]) - damage)
				events.append({"kind": "hit", "x": center(objective).x, "y": center(objective).y, "amount": damage, "friendly": true})
				enemy["cooldown"] = 1
				if objective["hp"] <= 0:
					raid_stats["built_lost"] = int(raid_stats["built_lost"]) + 1
					if str(objective["type"]) == "gate":
						raid_stats["gates_lost"] = int(raid_stats["gates_lost"]) + 1
					revision += 1
					_invalidate()
		else:
			_walk(enemy, goal, dt, true)
	for index in range(enemies.size() - 1, -1, -1):
		if enemies[index]["hp"] <= 0:
			paths.erase(int(enemies[index]["id"]))
			events.append({"kind": "defeat", "x": float(enemies[index]["x"]), "y": float(enemies[index]["y"]), "friendly": false})
			var role: String = str(enemies[index].get("role", "raider"))
			raid_stats["kills"] = int(raid_stats["kills"]) + 1
			var by_role: Dictionary = raid_stats["kills_by"]
			by_role[role] = int(by_role.get(role, 0)) + 1
			enemies.remove_at(index)
	if _hall().get("hp", 0) <= 0:
		_finish_raid(false)
	elif enemies.is_empty():
		_finish_raid(true)


func _finish_raid(victory: bool) -> void:
	var held: float = float(raid_stats.get("seconds_held", 0.0))
	raid_active = false
	raid_warning = false
	enemies.clear()
	_invalidate()
	scripted_raid = ""
	next_raid_at = elapsed + (240 if victory else 360)
	for u in units:
		if u["hp"] <= 0:
			u["hp"] = float(u["max_hp"]) * 0.5
			u["x"] = 8.0
			u["y"] = 10.8
			u["phase"] = "idle"
	if victory:
		raid_stats["defended"] = int(raid_stats["defended"]) + 1
		# Organized Watch research repairs the damage instead of leaving it.
		if chronicle.effect("command:auto-repair"):
			for b: Dictionary in buildings:
				if float(b["hp"]) > 0.0 and float(b["remaining"]) <= 0.0:
					b["hp"] = minf(float(b["max_hp"]), float(b["hp"]) + float(b["max_hp"]) * 0.35)
			notice = "The Manor stands / masons put the damage back."
		else:
			notice = "The Manor stands / salvage and recovery."
		_reward({"gold": 20 + wave * 10})
	else:
		notice = "The Manor fell / salvage Wood waits. Repair and rise again."
		_reward({"wood": 80})
	raid_stats["seconds_held"] = maxf(held, 0.0)
	events.append({"kind": "raid_result", "victory": victory})


func _reward(rewards: Dictionary) -> void:
	for resource in rewards:
		if str(resource) == "insight":
			living.insight = minf(float(living.config["research"]["insight_cap"]), living.insight + float(rewards[resource]))
			continue
		if str(resource) == "reputation":
			chronicle.reputation += int(rewards[resource])
			continue
		pending_rewards[resource] = float(pending_rewards.get(resource, 0)) + float(rewards[resource])


func quest_current() -> Dictionary:
	# Availability is campaign progress, not an array slice.
	for quest: Dictionary in quests:
		var id: String = str(quest["id"])
		if id in completed_quests or int(quest["act"]) > chronicle.act:
			continue
		return quest
	return {}


func quest_by_id(id: String) -> Dictionary:
	for quest: Dictionary in quests:
		if str(quest["id"]) == id:
			return quest
	return {}


func _quest_record(id: String) -> Dictionary:
	if not quest_progress.has(id):
		quest_progress[id] = {"optional": {}, "raid_started": false, "started_at": elapsed}
		# A mission introduces its own content while it is the current mission,
		# so objectives can ask for what the mission itself introduces.
		var quest: Dictionary = quest_by_id(id)
		chronicle.grant_many(quest.get("introduces", []), "story:" + id + "/introduces")
	return quest_progress[id]


func _quest_tick() -> void:
	# Every mission in the current act can be completed. Nothing blocks on
	# anything else: the player pursues the objective they can actually do.
	var active: Dictionary = quest_current()
	var active_id: String = str(active.get("id", ""))
	for quest: Dictionary in quests:
		if int(quest["act"]) > chronicle.act:
			continue
		var id: String = str(quest["id"])
		if id in completed_quests:
			continue
		var record: Dictionary = _quest_record(id)
		if id == active_id:
			_maybe_start_scripted_raid(quest, record)
		var complete: bool = true
		for objective: Dictionary in quest["objectives"]:
			if _objective_value(objective) < _objective_target(objective):
				complete = false
				break
		if not complete:
			continue
		completed_quests.append(id)
		xp += int(quest.get("xp", 0))
		living.insight = minf(float(living.config["research"]["insight_cap"]), living.insight + float(quest.get("insight", 0)))
		chronicle.reputation += int(quest.get("reputation", 0))
		_reward(quest.get("rewards", {}))
		chronicle.grant_many(quest.get("unlocks", []), "story:" + id)
		_award_optionals(quest, record)
		chronicle.queue_banner(str(quest.get("giver", "")), str(quest.get("log", "%s complete." % str(quest["name"]))))
		notice = "Act %d / %s complete / +%d XP." % [int(quest["act"]), str(quest["name"]), int(quest.get("xp", 0))]
	_check_act_complete()
	# Board contracts ride the same counters, so a mission never has to feed them.
	for contract_id: String in chronicle.board_active_ids():
		chronicle.board_advance(contract_id, 0.0)


func _award_optionals(quest: Dictionary, record: Dictionary) -> void:
	for objective: Dictionary in quest.get("optional", []):
		var oid: String = str(objective["id"])
		if bool(record["optional"].get(oid, false)) or not _optional_met(objective, record):
			continue
		record["optional"][oid] = true
		var reward: Dictionary = objective.get("reward", {})
		_reward(reward)
		living.insight = minf(float(living.config["research"]["insight_cap"]), living.insight + float(reward.get("insight", 0)))
		chronicle.reputation += int(reward.get("reputation", 0))
		chronicle.grant_many(reward.get("unlocks", []), "story:%s/%s" % [str(quest["id"]), oid])


func _check_act_complete() -> void:
	for quest: Dictionary in quests:
		if int(quest["act"]) == chronicle.act and str(quest["id"]) not in completed_quests:
			return
	if chronicle.act >= chronicle.act_count():
		return
	chronicle.advance_act()
	notice = "Act %s opens / %s." % [chronicle.act_name(chronicle.act), str(chronicle.act_data(chronicle.act).get("summary", ""))]


func _objective_target(objective: Dictionary) -> float:
	match str(objective["kind"]):
		"upgrade": return float(objective.get("level", 1))
		"under_time", "defend_for_time": return float(objective.get("seconds", 0))
		"all": return float(objective.get("count", 1))
	return float(objective.get("count", 1))


func _buildings_of(types: Array, tier_level: int = 0) -> int:
	var count: int = 0
	for b: Dictionary in buildings:
		if not types.has(str(b["type"])): continue
		if float(b["hp"]) <= 0.0 or float(b.get("remaining", 0.0)) > 0.0: continue
		if tier_level > 0 and int(b["tier"]) < tier_level: continue
		count += 1
	return count


func _units_of(types: Array) -> int:
	var count: int = 0
	for u: Dictionary in units:
		if types.has(str(u["type"])):
			count += 1
	return count


func _objective_value(objective: Dictionary) -> float:
	var kinds: Array = objective.get("types", [])
	var resource: String = str(objective.get("resource", ""))
	match str(objective["kind"]):
		"build": return float(_buildings_of(kinds))
		"upgrade": return float(_buildings_of(kinds, int(objective.get("level", 1))))
		"recruit": return float(_units_of(kinds))
		"assign":
			var assigned: int = 0
			for u: Dictionary in units:
				if int(u["workplace"]) >= 0: assigned += 1
			return float(assigned)
		"population": return float(units.size())
		"gather": return float(gathered.get(resource, 0))
		"deliver_resources": return float(raid_stats.get("delivered", {}).get(resource, 0))
		"maintain_resource": return float(resources.get(resource, 0))
		"research": return float(living.discoveries.size())
		"defeat", "survive_raid": return float(int(raid_stats["defended"]))
		"prestige_unit", "prestige": return float(int(raid_stats["prestige"]))
		"kill_enemy": return float(int(raid_stats["kills_by"].get(str(objective.get("enemy", "raider")), 0)))
		"preserve_gate":
			var gates: int = 0
			for b: Dictionary in buildings:
				if str(b["type"]) in ["gate", "stonewall"] and float(b["hp"]) > 0.0: gates += 1
			return float(gates)
		"defend_for_time": return float(raid_stats["seconds_held"])
		"complete_expedition": return float(int(raid_stats["expeditions"]))
		"secure_region", "scout_region":
			var region_id: String = str(objective.get("region", ""))
			var wanted: int = 2 if str(objective["kind"]) == "scout_region" else 3
			var states: Array = chronicle.region_states()
			return float(states.find(chronicle.region_state(region_id)) + 1) if chronicle.region_index(region_id) >= wanted else 0.0
		"construct_great_work":
			var gw: String = str(objective.get("id", objective.get("type", "")))
			return 1.0 if (chronicle.great_works.has(gw) or chronicle.is_unlocked(gw)) else 0.0
		"wonder":
			var want: String = str(objective.get("type", ""))
			return 1.0 if (chronicle.great_works.has(want) or chronicle.is_unlocked(want)) else 0.0
		"all": return 1.0
	return 0.0


func _optional_met(objective: Dictionary, record: Dictionary) -> bool:
	match str(objective["kind"]):
		"no_buildings_destroyed": return int(raid_stats["built_lost"]) == 0
		"no_defenders_lost": return int(raid_stats["defenders_lost"]) == 0
		"no_gate_breached": return int(raid_stats["gates_lost"]) == 0
		"under_time": return float(record.get("started_at", elapsed)) + float(objective.get("seconds", 0)) >= elapsed
		"keep_resource_above": return float(resources.get(str(objective.get("resource", "")), 0)) >= float(objective.get("amount", 1))
	return true


# The first horn is a story beat, not a random timer: a mission that asks the
# player to survive a raid summons one once its build objectives are done.
func _maybe_start_scripted_raid(quest: Dictionary, record: Dictionary) -> void:
	if bool(record.get("raid_started", false)) or raid_active or raid_warning:
		return
	var wants_raid: bool = false
	for objective: Dictionary in quest["objectives"]:
		var kind: String = str(objective["kind"])
		if kind == "survive_raid":
			wants_raid = true
		elif kind != "defend_for_time" and _objective_value(objective) < _objective_target(objective):
			return
	if not wants_raid:
		return
	record["raid_started"] = true
	_start_story_raid(int(quest["act"]))
	notice = "The horn sounds / %s" % str(quest["name"])


func _start_story_raid(act_number: int) -> void:
	raid_warning = true
	next_raid_at = elapsed + 6
	scripted_raid = "act%d" % act_number
	notice = "Horn on the road / hold for 6 seconds."


func export_state() -> Dictionary:
	# Strip transient memoization keys: Vector2i/Vector2 serialize as JSON
	# strings and would come back as Strings on load.
	for group in [units, enemies]:
		for u in (group as Array):
			for transient in ["edge_goal", "edge_tile", "edge_rev", "edge_bid"]:
				(u as Dictionary).erase(transient)
	return {"version": 3, "living": living.state(), "chronicle": chronicle.state(),
		"buildings": buildings.duplicate(true), "units": units.duplicate(true), "enemies": enemies.duplicate(true),
		"resources": resources.duplicate(true), "pending_rewards": pending_rewards.duplicate(true), "gathered": gathered.duplicate(true),
		"completed_quests": completed_quests.duplicate(), "quest_progress": quest_progress.duplicate(true),
		"optional_won": optional_won.duplicate(), "raid_stats": raid_stats.duplicate(true),
		"elapsed": elapsed, "xp": xp, "wave": wave, "next_raid_at": next_raid_at,
		"raid_active": raid_active, "raid_warning": raid_warning, "next_id": next_id, "birth_timer": birth_timer}


func _migrate(state: Dictionary) -> Dictionary:
	# v1 and v2 saves stay valid. New progression sections get safe defaults and
	# the act is derived from the quests the player already finished.
	var version: int = int(state.get("version", 1))
	if version >= 3:
		return state
	var migrated: Dictionary = state.duplicate(true)
	migrated["version"] = 3
	# v1 predates Living Village and v2 predates the Chronicle: give the new
	# sections their real defaults instead of rejecting the save.
	if not migrated.get("living") is Dictionary:
		migrated["living"] = Living.new().state()
	migrated["quest_progress"] = state.get("quest_progress", {})
	migrated["optional_won"] = state.get("optional_won", {})
	migrated["raid_stats"] = {"defended": 0, "kills": 0, "kills_by": {}, "built_lost": 0,
		"defenders_lost": 0, "gates_lost": 0, "seconds_held": 0.0, "prestige": 0,
		"expeditions": 0, "delivered": {}}
	var chronicle_state: Dictionary = state["chronicle"].duplicate(true) if chronicle.valid(state.get("chronicle")) else chronicle.state()
	# A returning player is as far along as their quest record proves.
	var reached: int = 1
	var done: Dictionary = {}
	for quest_id: Variant in state.get("completed_quests", []):
		done[str(quest_id)] = true
	for quest: Dictionary in quests:
		if str(quest["id"]) in done:
			reached = maxi(reached, int(quest["act"]) + 1)
	for quest: Dictionary in quests:
		if str(quest["id"]) in done:
			continue
		reached = mini(reached, int(quest["act"]))
		break
	chronicle_state["act"] = clampi(reached, 1, chronicle.act_count())
	migrated["chronicle"] = chronicle_state
	# Re-derive what the player's finished missions already introduced, so an old
	# save never loses content it had earned. Missions complete independently,
	# so membership is checked per mission rather than by list position.
	for quest: Dictionary in quests:
		if str(quest["id"]) not in done:
			continue
		chronicle.grant_many(quest.get("introduces", []), "story:" + str(quest["id"]) + "/introduces")
		chronicle.grant_many(quest.get("unlocks", []), "story:" + str(quest["id"]))
	migrated["chronicle"] = chronicle.state()
	# Stone is a v3 resource; old saves simply start at zero.
	var clean: Dictionary = migrated["resources"]
	if not clean.has("stone"):
		clean["stone"] = 0.0
	return migrated


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0


func restore_state(state: Dictionary) -> bool:
	if not _validate_state(state):
		return false
	var data: Dictionary = _migrate(state)
	if not _validate_state(data):
		return false
	buildings.assign(data["buildings"].duplicate(true))
	units.assign(data["units"].duplicate(true))
	enemies.assign(data["enemies"].duplicate(true))
	resources = data["resources"].duplicate(true)
	for resource in world_specs["startingResources"]:
		resources[resource] = resources.get(resource, 0)
	pending_rewards = data["pending_rewards"].duplicate(true)
	gathered = data["gathered"].duplicate(true)
	completed_quests.assign(data["completed_quests"])
	quest_progress = data.get("quest_progress", {}).duplicate(true)
	optional_won = data.get("optional_won", {}).duplicate()
	raid_stats = data.get("raid_stats", {"defended": 0, "kills": 0, "kills_by": {}, "built_lost": 0,
		"defenders_lost": 0, "gates_lost": 0, "seconds_held": 0.0, "prestige": 0,
		"expeditions": 0, "delivered": {}}).duplicate(true)
	elapsed = float(data["elapsed"])
	xp = int(data["xp"])
	wave = int(data["wave"])
	next_raid_at = float(data["next_raid_at"])
	raid_active = data["raid_active"]
	raid_warning = data["raid_warning"]
	next_id = int(data["next_id"])
	birth_timer = float(data["birth_timer"])
	living.restore(data.get("living", Living.new().state()))
	chronicle.restore(data["chronicle"])
	navigation_revision = living.navigation_revision
	_invalidate()
	revision += 1
	return true


func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


func _validate_state(state: Dictionary) -> bool:
	# JSON hands back every number as a float, so the version is checked as a finite integer and cast once.
	if not _integer(state.get("version")) or int(state["version"]) not in [1, 2, 3]:
		return false
	if int(state["version"]) >= 2 and not living.valid(state.get("living")):
		return false
	if int(state["version"]) >= 3 and not chronicle.valid(state.get("chronicle")):
		return false
	for key in ["buildings", "units", "enemies", "completed_quests"]:
		if not state.get(key) is Array:
			return false
	for key in ["resources", "pending_rewards", "gathered"]:
		if not state.get(key) is Dictionary:
			return false
		for resource in state[key]:
			if resource not in world_specs["startingResources"] or not _number(state[key][resource]):
				return false
	for key in ["elapsed", "xp", "wave", "next_raid_at", "next_id", "birth_timer"]:
		if not _number(state.get(key)):
			return false
	if int(state["version"]) >= 2:
		for cell: Dictionary in state["living"]["cells"].values():
			if float(cell["last"]) > float(state["elapsed"]) + 0.01: return false
			if cell["stone"] and "road_masonry" not in state["living"]["discoveries"]: return false
	if not state.get("raid_active") is bool or not state.get("raid_warning") is bool:
		return false
	if state["units"].size() > 200 or state["buildings"].size() > 320 or state["enemies"].size() > 8:
		return false
	if (state["raid_active"] and state["raid_warning"]) or (not state["raid_active"] and not state["enemies"].is_empty()):
		return false
	var ids: Dictionary = {}
	var building_index: Dictionary = {}
	var hall_count: int = 0
	for b in state["buildings"]:
		if not b is Dictionary or not building_specs.has(str(b.get("type", ""))):
			return false
		for key in ["id", "x", "y", "size", "tier", "hp", "max_hp", "remaining", "reserve", "cooldown"]:
			if not _number(b.get(key)):
				return false
		var spec: Dictionary = building_specs[b["type"]]
		for key in ["id", "x", "y", "size", "tier"]:
			if not _integer(b[key]):
				return false
		if int(b["size"]) != int(spec["size"]) or int(b["tier"]) < 1 or int(b["tier"]) > spec["tiers"].size() or float(b["x"]) + float(b["size"]) > 20 or float(b["y"]) + float(b["size"]) > 16:
			return false
		if ids.has(int(b["id"])) or int(b["id"]) >= int(state["next_id"]) or b["hp"] > b["max_hp"]:
			return false
		for other: Dictionary in building_index.values():
			if Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"])).intersects(Rect2i(int(other["x"]), int(other["y"]), int(other["size"]), int(other["size"]))):
				return false
		ids[int(b["id"])] = true
		building_index[int(b["id"])] = b
		hall_count += 1 if b["type"] == "hall" else 0
	if hall_count != 1:
		return false
	for group in [state["units"], state["enemies"]]:
		for u in group:
			if not u is Dictionary:
				return false
			var hostile: bool = group == state["enemies"]
			if (hostile and u.get("type") != "raider") or (not hostile and not troop_specs.has(str(u.get("type", "")))):
				return false
			for key in ["id", "x", "y", "hp", "max_hp", "cooldown"]:
				if not _number(u.get(key)):
					return false
			if float(u["x"]) >= 20 or float(u["y"]) >= 16 or ids.has(int(u["id"])) or int(u["id"]) >= int(state["next_id"]) or u["hp"] > u["max_hp"] or not u.get("phase") is String:
				return false
			ids[int(u["id"])] = true
			if not hostile:
				if not _number(u.get("level")) or int(u["level"]) < 1 or int(u["level"]) > 25 or not _number(u.get("carry")) or not u.get("carry_resource") is String or not u.get("order") is Array or not u.get("hold") is bool:
					return false
				if float(u["carry"]) > 0 and u["carry_resource"] not in world_specs["startingResources"]:
					return false
				if not _integer(u["carry"]) or not _integer(u["level"]) or not _integer(u["id"]):
					return false
				if not u.get("workplace") is int and not u.get("workplace") is float:
					return false
				if u["workplace"] != -1:
					if not _integer(u["workplace"]) or not building_index.has(int(u["workplace"])):
						return false
					var post: Dictionary = building_index[int(u["workplace"])]
					if str(building_specs[post["type"]].get("workplace", "")) != str(u["type"]) \
							and not (GUARD_POSTS.has(str(post["type"])) and str(troop_specs[str(u["type"])]["role"]) == "combat"):
						return false
				if not u["order"].is_empty() and (u["order"].size() != 2 or not _number(u["order"][0]) or not _number(u["order"][1]) or u["order"][0] >= 20 or u["order"][1] >= 16):
					return false
				for key in ["fx", "fy", "rx", "ry", "think", "sx", "sy"]:
					var extra: Variant = u.get(key, -1.0)
					if not (extra is int or extra is float) or not is_finite(float(extra)):
						return false
				if (float(u.get("sx", -1.0)) >= 0) != (float(u.get("sy", -1.0)) >= 0):
					return false
				if not u.get("kite", false) is bool:
					return false
				if not _integer(u.get("slot", 0)) or int(u.get("slot", 0)) < 0:
					return false
				var reserved: Variant = u.get("post", -1)
				if reserved != -1 and not _integer(reserved):
					return false
				if int(reserved) != -1 and int(reserved) != int(u["workplace"]):
					return false
	var known: Array = []
	for quest: Dictionary in quests:
		known.append(quest["id"])
	for quest_id in state["completed_quests"]:
		if quest_id not in known:
			return false
	if int(state["version"]) >= 3:
		if not state.get("quest_progress") is Dictionary or state["quest_progress"].size() > known.size():
			return false
		for quest_id: Variant in state["quest_progress"]:
			if str(quest_id) not in known or not state["quest_progress"][quest_id] is Dictionary:
				return false
			var record: Dictionary = state["quest_progress"][quest_id]
			if not record.get("optional") is Dictionary or not record.get("raid_started", false) is bool:
				return false
			if not _number(record.get("started_at", 0)):
				return false
		if not state.get("raid_stats") is Dictionary:
			return false
		var stats: Dictionary = state["raid_stats"]
		for field in ["defended", "kills", "built_lost", "defenders_lost", "gates_lost", "seconds_held", "prestige", "expeditions"]:
			if not _number(stats.get(field, 0)):
				return false
		for field in ["kills_by", "delivered"]:
			var tally: Dictionary = stats.get(field, {})
			if not tally is Dictionary:
				return false
			if tally.size() > 64:
				return false
			for tally_key: Variant in tally:
				if not tally_key is String or not _number(tally[tally_key]) or float(tally[tally_key]) < 0:
					return false
	return true


func save_game(path: String = "user://village-v1.json") -> bool:
	if FileAccess.file_exists(path):
		var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not existing is Dictionary or not _validate_state(existing):
			notice = "Save failed / existing save unreadable; original and backup retained."
			return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		notice = "Save failed / could not open storage."
		return false
	file.store_string(JSON.stringify(export_state()))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		notice = "Save failed / could not write storage."
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		if DirAccess.rename_absolute(path, path + ".bak") != OK:
			notice = "Save failed / previous save retained."
			return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(path + ".bak", path)
		notice = "Save failed / previous save retained."
		return false
	return true


func load_game(path: String = "user://village-v1.json") -> bool:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if value is Dictionary and restore_state(value):
			notice = "Village restored." if candidate == path else "Primary save unreadable / restored backup."
			return true
	notice = "Save unreadable / original files retained."
	return false
