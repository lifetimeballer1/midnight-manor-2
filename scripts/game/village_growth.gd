extends RefCounted

# Zoning inside the village, from the first day. The player paints village ground as homes, farms,
# industry or civic (town_zoning.gd keeps those cells in its own save) and the village's own
# buildings rise there by themselves, free: a cottage on homes, a farm or pond on farms, a lumber
# camp or mine on industry, a chapel on civic. Later they move up a tier on their own, free as well.
# The Manor Hall moves up on its own too, once enough villagers live here. Only what is not listed
# for a zone (walls, towers, traps, the gate, barracks) is still bought.
#
#   * Which buildings belong to which zone, and the pace, are data: zones.json "village".
#   * A building rises only where its whole footprint is zoned for its kind, inside the village's
#     own ground (the base village and the reaches it holds). The simulation's own rules still
#     decide everything else: research and story locks, village level, building limits, overlap.
#   * What rises first follows the village's needs: homes only while few beds stand empty, a type
#     the player asked for (a Raise button, a quest), then whatever there is least of.
#   * Only active time counts, nothing rises during a raid, and a few rise at once at most.
#
# The simulation is driven only through its existing building records (_new_building), so the
# village save keeps its format.

var spec: Dictionary = {}
var tile_offset := Vector2i(10, 8)        # the village tile at the corner of town cell (0, 0)
var tiles_per_cell: int = 2
var grow_clock: float = 0.0
var upgrade_clock: float = 0.0
var wishes: Array[String] = []            # types the player asked for, raised first
var _turn: int = 0                        # which zone gets the first look next time


func setup(config: Dictionary, offset: Vector2i, per_cell: int) -> void:
	spec = config
	tile_offset = offset
	tiles_per_cell = maxi(per_cell, 1)


func zone_types(zone: String) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in spec.get("zones", {}).get(zone, []):
		if entry is Dictionary:
			out.append(str(entry.get("type", "")))
	return out


# The zone a building type grows in, or "" when it is bought by hand.
func zone_of(type_name: String) -> String:
	for zone: Variant in spec.get("zones", {}):
		if type_name in zone_types(str(zone)):
			return str(zone)
	return ""


func grows(type_name: String) -> bool:
	return not zone_of(type_name).is_empty()


func _after(zone: String, type_name: String) -> int:
	for entry: Variant in spec.get("zones", {}).get(zone, []):
		if entry is Dictionary and str(entry.get("type", "")) == type_name:
			return int(entry.get("after", 0))
	return 0


func cell_tiles(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var corner: Vector2i = c * tiles_per_cell + tile_offset
	for dy in tiles_per_cell:
		for dx in tiles_per_cell:
			out.append(corner + Vector2i(dx, dy))
	return out


func tile_cell(tile: Vector2i) -> Vector2i:
	var local: Vector2i = tile - tile_offset
	return Vector2i(floori(float(local.x) / tiles_per_cell), floori(float(local.y) / tiles_per_cell))


# Why a village cell cannot be zoned, or "" when it can: all of it must be the village's own ground.
func cell_reason(sim, c: Vector2i) -> String:
	for tile: Vector2i in cell_tiles(c):
		if not sim.in_world(tile):
			return "This reach is not the manor's yet. Buy it or win it on the Frontier."
	return ""


# Village tiles zoned for each zone: zone -> {Vector2i: true}.
func zoned_tiles(town, sim) -> Dictionary:
	var out: Dictionary = {}
	for c: Vector2i in town.village:
		var zone: String = str(town.village[c])
		if not out.has(zone):
			out[zone] = {}
		for tile: Vector2i in cell_tiles(c):
			if sim.in_world(tile):
				out[zone][tile] = true
	return out


func _standing(sim, zone: String) -> int:
	var count: int = 0
	var types: Array[String] = zone_types(zone)
	for b: Dictionary in sim.buildings:
		if str(b["type"]) in types and float(b["hp"]) > 0.0:
			count += 1
	return count


func _owned(sim, type_name: String) -> int:
	var count: int = 0
	for b: Dictionary in sim.buildings:
		if str(b["type"]) == type_name and float(b["hp"]) > 0.0:
			count += 1
	return count


func rising(sim) -> int:
	var count: int = 0
	for b: Dictionary in sim.buildings:
		if float(b["remaining"]) > 0.0 and float(b["hp"]) > 0.0 and grows(str(b["type"])):
			count += 1
	return count


# Types the current quest still asks for.
func _quest_wants(sim) -> Array[String]:
	var out: Array[String] = []
	var quest: Dictionary = sim.quest_current()
	for objective: Dictionary in quest.get("objectives", []):
		if str(objective.get("kind", "")) != "build":
			continue
		if sim._objective_value(objective) >= sim._objective_target(objective):
			continue
		for type_name: Variant in objective.get("types", []):
			out.append(str(type_name))
	return out


# The order a zone's types are tried in: what the village needs most first.
func ranked(sim, zone: String) -> Array[String]:
	var types: Array[String] = []
	var standing: int = _standing(sim, zone)
	for type_name: String in zone_types(zone):
		if sim.building_specs.has(type_name) and standing >= _after(zone, type_name):
			types.append(type_name)
	var wanted: Array[String] = []
	for type_name: String in wishes + _quest_wants(sim):
		if type_name in types and type_name not in wanted:
			wanted.append(type_name)
	# Homes follow the people: they rise only while few beds stand empty, and then before the rest.
	var spare: int = sim.beds() - sim.units.size()
	var scored: Array = []
	for i in types.size():
		var type_name: String = types[i]
		var score: float = float(_owned(sim, type_name)) * 10.0 + float(i)
		if not (sim.building_specs[type_name].get("housing", []) as Array).is_empty():
			if spare >= int(spec.get("bedsSpare", 3)) and type_name not in wanted:
				continue
			score -= 1000.0
		if type_name in wanted:
			score -= 2000.0 + float(wanted.find(type_name)) * 0.1
		scored.append([score, type_name])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array[String] = []
	for row: Array in scored:
		out.append(str(row[1]))
	return out


# Where a type could rise on its zone, nearest the hall first, or (-1, -1).
func find_spot(sim, type_name: String, tiles: Dictionary) -> Vector2i:
	var size: int = int(sim.building_specs[type_name].get("size", 1))
	var hall: Dictionary = sim._hall()
	var heart: Vector2 = sim.center(hall) if not hall.is_empty() else Vector2(10, 8)
	var anchors: Array = tiles.keys()
	anchors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: float = (Vector2(a) + Vector2.ONE * size * 0.5).distance_squared_to(heart)
		var db: float = (Vector2(b) + Vector2.ONE * size * 0.5).distance_squared_to(heart)
		return da < db if not is_equal_approx(da, db) else (a.y < b.y or (a.y == b.y and a.x < b.x)))
	for anchor: Vector2i in anchors:
		var fits: bool = true
		for dy in size:
			for dx in size:
				if not tiles.has(anchor + Vector2i(dx, dy)):
					fits = false
		if not fits:
			continue
		var reason: String = sim.build_reason(type_name, anchor.x, anchor.y)
		if reason.is_empty() or reason == "Not enough resources.":
			return anchor
		if reason not in ["This footprint is occupied.", "Outside the village."]:
			return Vector2i(-1, -1)   # locked, limited or too early: no spot will do
	return Vector2i(-1, -1)


# Raises one building somewhere zoned for it, free. Returns {type, id, x, y} or {}.
func grow_one(sim, town) -> Dictionary:
	if sim.raid_active or sim.raid_warning or rising(sim) >= int(spec.get("maxRising", 2)):
		return {}
	var tiles: Dictionary = zoned_tiles(town, sim)
	var zones: Array = tiles.keys()
	if zones.is_empty():
		return {}
	zones.sort()
	for i in zones.size():
		var zone: String = str(zones[(i + _turn) % zones.size()])
		for type_name: String in ranked(sim, zone):
			var spot: Vector2i = find_spot(sim, type_name, tiles[zone])
			if spot.x < 0 and spot.y < 0:
				continue
			_turn += i + 1
			var b: Dictionary = sim._new_building(type_name, spot.x, spot.y, true)
			sim.buildings.append(b)
			sim.revision += 1
			sim._invalidate()
			wishes.erase(type_name)
			sim.notice = "%s rises on the %s zone." % [str(sim.building_specs[type_name]["name"]), zone_name(zone)]
			return {"type": type_name, "id": int(b["id"]), "x": spot.x, "y": spot.y}
	return {}


func zone_name(zone: String) -> String:
	return {"housing": "homes", "farming": "farm", "industrial": "industry", "civic": "civic"}.get(zone, zone)


# Moves one grown-type building up a tier, free, once the village level allows it (tierLevels, and
# the simulation's own tier gates).
# Returns {type, id, tier} or {}.
func upgrade_one(sim) -> Dictionary:
	if sim.raid_active or sim.raid_warning:
		return {}
	var best: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if not grows(str(b["type"])) or float(b["hp"]) <= 0.0:
			continue
		if float(b["remaining"]) > 0.0:
			if int(b["tier"]) > 1:
				return {}   # one upgrade at a time
			continue
		if sim.village_level() < int(spec.get("tierLevels", {}).get(str(int(b["tier"]) + 1), 1)):
			continue
		var reason: String = sim.upgrade_reason(int(b["id"]))
		if not reason.is_empty() and reason != "Not enough resources to upgrade.":
			continue
		if best.is_empty() or int(b["tier"]) < int(best["tier"]) or (int(b["tier"]) == int(best["tier"]) and int(b["id"]) < int(best["id"])):
			best = b
	if best.is_empty():
		return {}
	var spec_b: Dictionary = sim.building_specs[best["type"]]
	best["tier"] = int(best["tier"]) + 1
	best["max_hp"] = float(spec_b["tiers"][int(best["tier"]) - 1]["hp"])
	best["hp"] = float(best["max_hp"])
	best["remaining"] = float(spec_b["buildSeconds"])
	sim.revision += 1
	sim.notice = "%s grows to tier %d on its own." % [str(spec_b["name"]), int(best["tier"])]
	return {"type": str(best["type"]), "id": int(best["id"]), "tier": int(best["tier"])}


# The Manor Hall moves up a tier on its own once enough villagers live in the village (hallPeople).
# Returns {type, id, tier} or {}.
func hall_one(sim) -> Dictionary:
	var hall: Dictionary = sim._hall()
	if hall.is_empty() or sim.raid_active or sim.raid_warning:
		return {}
	var next: int = int(hall["tier"]) + 1
	var people: Variant = spec.get("hallPeople", {}).get(str(next), null)
	if people == null or sim.units.size() < int(people) or not sim.upgrade_reason(int(hall["id"])).is_empty():
		return {}
	var spec_b: Dictionary = sim.building_specs["hall"]
	hall["tier"] = next
	hall["max_hp"] = float(spec_b["tiers"][next - 1]["hp"])
	hall["hp"] = float(hall["max_hp"])
	hall["remaining"] = float(spec_b["buildSeconds"])
	sim.revision += 1
	sim.notice = "The village has grown: the %s rises to tier %d." % [str(spec_b["name"]), next]
	return {"type": "hall", "id": int(hall["id"]), "tier": next}


# Hall people needed for its next tier, or -1 at the top.
func hall_people_next(sim) -> int:
	var hall: Dictionary = sim._hall()
	if hall.is_empty():
		return -1
	return int(spec.get("hallPeople", {}).get(str(int(hall["tier"]) + 1), -1))


# Active time only. Returns what happened: [{kind: "rose"|"upgraded", ...}].
func tick(sim, town, dt: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if town == null:
		return out
	grow_clock += dt
	upgrade_clock += dt
	if grow_clock >= float(spec.get("growSeconds", 5.0)):
		grow_clock = 0.0
		var rose: Dictionary = grow_one(sim, town)
		if not rose.is_empty():
			rose["kind"] = "rose"
			out.append(rose)
	if upgrade_clock >= float(spec.get("upgradeSeconds", 24.0)):
		upgrade_clock = 0.0
		var up: Dictionary = hall_one(sim)
		if up.is_empty():
			up = upgrade_one(sim)
		if not up.is_empty():
			up["kind"] = "upgraded"
			out.append(up)
	return out
