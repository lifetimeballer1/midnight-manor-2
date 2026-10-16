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
#   * Zones side by side still leave everyone a way in and out (find_spot), and each building that
#     rises gets a dirt path to its door (lay_lanes).
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
var _floods: int = 0                      # reach checks spent in this growth step
var _cut: Dictionary = {}                 # building id -> true while it has no way in (told once)
var _tend: int = 0                        # which grown building's paths are freshened next


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
			# A farm estate counts as the small farms its land would once have held.
			count += maxi(1, floori(sim.estate_scale(b)))
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


# Types the current quest still asks for (to build, or to stand and grow a tier).
func _quest_wants(sim) -> Array[String]:
	var out: Array[String] = []
	var quest: Dictionary = sim.quest_current()
	for objective: Dictionary in quest.get("objectives", []):
		var kind: String = str(objective.get("kind", ""))
		if kind not in ["build", "upgrade"]:
			continue
		if sim._objective_value(objective) >= sim._objective_target(objective):
			continue
		for type_name: Variant in objective.get("types", []):
			# An upgrade objective asks for buildings that grow tiers on their own: zone more while too few stand.
			if kind == "upgrade" and sim._buildings_of([str(type_name)]) >= int(objective.get("count", 1)):
				continue
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
		if is_crop(type_name):
			score = float(i)   # a new estate starts as the first crop that may rise; the card changes it
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


# Where a type could rise on its zone, nearest the hall first, or (-1, -1). A spot must keep the
# village walkable: the new building needs a way in from the hall (and a work stand to use), and it
# may not cut anyone else off, cover another building's work stand or sit on a paved road. Spots on a
# well-trodden trail are taken only when nothing else fits, so the village's paths stay lanes.
func find_spot(sim, type_name: String, tiles: Dictionary, walk: Variant = null) -> Vector2i:
	var size: int = int(sim.building_specs[type_name].get("size", 1))
	var hall: Dictionary = sim._hall()
	var heart: Vector2 = sim.center(hall) if not hall.is_empty() else Vector2(10, 8)
	if walk == null:
		walk = _walk(sim)
		_floods = 0
	if not sim.unlock_reason(type_name).is_empty():
		return Vector2i(-1, -1)
	var anchors: Array = _order(sim, tiles, size, heart, walk)
	for anchor: Vector2i in anchors:
		var fits: bool = true
		for dy in size:
			for dx in size:
				if not tiles.has(anchor + Vector2i(dx, dy)):
					fits = false
		if not fits:
			continue
		var reason: String = sim.build_reason(type_name, anchor.x, anchor.y)
		if not reason.is_empty() and reason != "Not enough resources.":
			if reason not in ["This footprint is occupied.", "Outside the village."]:
				return Vector2i(-1, -1)   # locked, limited or too early: no spot will do
			continue
		var footprint := Rect2i(anchor, Vector2i.ONE * size)
		if walk.is_empty():
			return anchor                # no hall to walk from: nothing to keep open
		if not _door_open(sim, walk, type_name, footprint, walk["reached"]) or _covers_stand(walk, footprint):
			continue
		if _floods >= FLOOD_BUDGET:
			return Vector2i(-1, -1)      # try again on the next tick rather than stall a frame
		_floods += 1
		var after: PackedByteArray = _flood(walk, footprint)
		if _door_open(sim, walk, type_name, footprint, after) and _keeps_everyone(walk, after):
			return anchor
	return Vector2i(-1, -1)


# Zoned anchors for a footprint size, nearest the hall first and trodden trails last; paved road is
# left out. Kept for the rest of the growth step.
func _order(sim, tiles: Dictionary, size: int, heart: Vector2, walk: Dictionary) -> Array:
	var key: String = "order/%d/%d" % [size, tiles.hash()]
	if walk.has(key):
		return walk[key]
	var trail: float = sim.living.faint_threshold()
	var rank: Dictionary = {}
	for anchor: Vector2i in tiles:
		var penalty: float = 0.0
		for dy in size:
			for dx in size:
				var cell: Dictionary = sim.living.cells.get(sim.living.key(anchor + Vector2i(dx, dy)), {})
				if cell.get("stone", false):
					penalty = INF
				elif float(cell.get("wear", 0.0)) >= trail:
					penalty = maxf(penalty, 10000.0)
		if not is_inf(penalty):
			rank[anchor] = penalty + (Vector2(anchor) + Vector2.ONE * size * 0.5).distance_squared_to(heart)
	var anchors: Array = rank.keys()
	anchors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: float = float(rank[a])
		var db: float = float(rank[b])
		return da < db if not is_equal_approx(da, db) else (a.y < b.y or (a.y == b.y and a.x < b.x)))
	if not walk.is_empty():
		walk[key] = anchors
	return anchors


# --- Ways in and out ------------------------------------------------------------------------------
# Walking is the simulation's own friendly walk grid (_walk_friendly): building footprints block,
# open gates and traps do not. "Reached" means walkable from the tiles around the Manor Hall.

const FLOOD_BUDGET: int = 24              # full reach checks per growth step
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


# The walk grid with today's reach from the hall, and what each building now relies on:
# {rect, grid, reached, seeds, needs: [{id, any: [index], all: [index]}], stands: {index: true}}.
# Empty when there is no standing hall to walk from.
func _walk(sim) -> Dictionary:
	var hall: Dictionary = sim._hall()
	if hall.is_empty() or float(hall["hp"]) <= 0.0:
		return {}
	sim._refresh_walk_grids()
	var walk: Dictionary = {"rect": sim._walk_rect, "grid": sim._walk_friendly, "seeds": PackedInt32Array()}
	for tile: Vector2i in _ring(Rect2i(int(hall["x"]), int(hall["y"]), int(hall["size"]), int(hall["size"]))):
		var i: int = _index(walk, tile)
		if i >= 0 and walk["grid"][i] == 0:
			walk["seeds"].append(i)
	walk["reached"] = _flood(walk, Rect2i())
	var needs: Array = []
	var stands: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) <= 0.0 or str(b["type"]) in ["trap", "fire-trap"] or int(b["id"]) == int(hall["id"]):
			continue
		var need: Dictionary = {"any": PackedInt32Array(), "all": PackedInt32Array()}
		for tile: Vector2i in _ring(Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"]))):
			var i: int = _index(walk, tile)
			if i >= 0 and walk["reached"][i] == 1:
				need["any"].append(i)
		for point: Vector2 in sim.stand_candidates(b):
			var i: int = _index(walk, Vector2i(floori(point.x), floori(point.y)))
			if i >= 0:
				stands[i] = true
				if walk["reached"][i] == 1:
					need["all"].append(i)
		if not need["any"].is_empty() or not need["all"].is_empty():
			needs.append(need)
	walk["needs"] = needs
	walk["stands"] = stands
	return walk


func _index(walk: Dictionary, tile: Vector2i) -> int:
	var rect: Rect2i = walk["rect"]
	if not rect.has_point(tile):
		return -1
	return (tile.y - rect.position.y) * rect.size.x + (tile.x - rect.position.x)


func _tile(walk: Dictionary, i: int) -> Vector2i:
	var rect: Rect2i = walk["rect"]
	return rect.position + Vector2i(i % rect.size.x, i / rect.size.x)


func _ring(footprint: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(footprint.position.y - 1, footprint.end.y + 1):
		for x in range(footprint.position.x - 1, footprint.end.x + 1):
			if not footprint.has_point(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


# Walkable tiles reached from the hall when `extra` (a building not yet raised) also blocks: 1 = reached.
func _flood(walk: Dictionary, extra: Rect2i) -> PackedByteArray:
	var rect: Rect2i = walk["rect"]
	var grid: PackedByteArray = walk["grid"]
	if extra.has_area():
		grid = grid.duplicate()
		var part: Rect2i = extra.intersection(rect)
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				grid[(y - rect.position.y) * rect.size.x + (x - rect.position.x)] = 1
	var width: int = rect.size.x
	var count: int = grid.size()
	var reached := PackedByteArray()
	reached.resize(count)
	var queue := PackedInt32Array()
	queue.resize(count)
	var tail: int = 0
	for i: int in walk["seeds"]:
		if grid[i] == 0 and reached[i] == 0:
			reached[i] = 1
			queue[tail] = i
			tail += 1
	var head: int = 0
	while head < tail:
		var i: int = queue[head]
		head += 1
		var x: int = i % width
		if x > 0 and grid[i - 1] == 0 and reached[i - 1] == 0:
			reached[i - 1] = 1
			queue[tail] = i - 1
			tail += 1
		if x < width - 1 and grid[i + 1] == 0 and reached[i + 1] == 0:
			reached[i + 1] = 1
			queue[tail] = i + 1
			tail += 1
		if i >= width and grid[i - width] == 0 and reached[i - width] == 0:
			reached[i - width] = 1
			queue[tail] = i - width
			tail += 1
		if i + width < count and grid[i + width] == 0 and reached[i + width] == 0:
			reached[i + width] = 1
			queue[tail] = i + width
			tail += 1
	return reached


# A new building needs a way in from the hall and, for a workplace, its work stands open and reached.
# A stand past the village's edge is let go (that worker works from the nearest open tile beside it).
func _door_open(sim, walk: Dictionary, type_name: String, footprint: Rect2i, reached: PackedByteArray) -> bool:
	var door: bool = false
	for tile: Vector2i in _ring(footprint):
		var i: int = _index(walk, tile)
		if i >= 0 and reached[i] == 1:
			door = true
			break
	if not door:
		return false
	var centre: Vector2 = Vector2(footprint.position) + Vector2.ONE * footprint.size.x * 0.5
	var stands: int = 0
	var open: int = 0
	for offset: Variant in sim.workplace_specs.get(type_name, {}).get("stands", []):
		if offset is Array and (offset as Array).size() == 2:
			stands += 1
			var point: Vector2 = centre + Vector2(float(offset[0]), float(offset[1]))
			var tile := Vector2i(floori(point.x), floori(point.y))
			var i: int = _index(walk, tile)
			if i >= 0 and reached[i] == 1 and not footprint.has_point(tile):
				open += 1
			elif sim.in_world(tile):
				return false     # its stand would sit inside a building or behind one
	return stands == 0 or open > 0


# True when the footprint would sit on another building's work stand.
func _covers_stand(walk: Dictionary, footprint: Rect2i) -> bool:
	for y in range(footprint.position.y, footprint.end.y):
		for x in range(footprint.position.x, footprint.end.x):
			if walk["stands"].has(_index(walk, Vector2i(x, y))):
				return true
	return false


# Everyone who could walk to their building (and its work stands) still can.
func _keeps_everyone(walk: Dictionary, after: PackedByteArray) -> bool:
	for need: Dictionary in walk["needs"]:
		var any: PackedInt32Array = need["any"]
		if not any.is_empty():
			var open: bool = false
			for i: int in any:
				if after[i] == 1:
					open = true
					break
			if not open:
				return false
		for i: int in need["all"]:
			if after[i] == 0:
				return false
	return true


# Raises one building somewhere zoned for it, free. Returns {type, id, x, y} or {}.
func grow_one(sim, town) -> Dictionary:
	if sim.raid_active or sim.raid_warning or rising(sim) >= int(spec.get("maxRising", 2)):
		return {}
	var tiles: Dictionary = zoned_tiles(town, sim)
	var zones: Array = tiles.keys()
	if zones.is_empty():
		return {}
	zones.sort()
	var walk: Dictionary = _walk(sim)
	_floods = 0
	for i in zones.size():
		var zone: String = str(zones[(i + _turn) % zones.size()])
		for type_name: String in ranked(sim, zone):
			# A farm estate has one crop house; the crop rises only on a patch that has none yet.
			var ground: Dictionary = tiles[zone]
			if is_crop(type_name):
				ground = _unfarmed_tiles(sim, town)
				if ground.is_empty():
					continue
			var spot: Vector2i = find_spot(sim, type_name, ground, walk)
			if spot.x < 0 and spot.y < 0:
				continue
			_turn += i + 1
			var b: Dictionary = sim._new_building(type_name, spot.x, spot.y, true)
			# Free to place, but it rises from materials the builders carry over.
			sim.materials.open_site(sim, b, 1)
			sim.buildings.append(b)
			sim.revision += 1
			sim._invalidate()
			wishes.erase(type_name)
			lay_lanes(sim, b)
			sim.notice = "%s rises on the %s zone." % [str(sim.building_specs[type_name]["name"]), zone_name(zone)]
			return {"type": type_name, "id": int(b["id"]), "x": spot.x, "y": spot.y}
	return {}


# --- Farm estates ---------------------------------------------------------------------------------
# A connected patch of farm zone (cells touching side by side) is one estate: one crop house (the
# first of estates.crops to rise there) and fields over the rest of the patch. Mills, bakeries and the
# like still rise on farm zone as their own buildings. Older villages that grew several small crop
# buildings on one patch fold them into the first one, crews and stores included.

const ESTATE_SECONDS: float = 2.0
var estate_clock: float = ESTATE_SECONDS
var _estate_sig: int = -1


func crops() -> Array[String]:
	var out: Array[String] = []
	for type_name: Variant in spec.get("estates", {}).get("crops", ["farm", "pasture", "grove", "pond"]):
		out.append(str(type_name))
	return out


func is_crop(type_name: String) -> bool:
	return type_name in crops()


func _estate_signature(sim, town) -> int:
	return hash([town.village.hash(), sim.revision])


# Connected farm-zone patches: [{tiles: {Vector2i: true}, cells: int}].
func estate_patches(sim, town) -> Array:
	var farm_cells: Dictionary = {}
	for c: Vector2i in town.village:
		if str(town.village[c]) == "farming":
			farm_cells[c] = true
	var seen: Dictionary = {}
	var out: Array = []
	var cells: Array = farm_cells.keys()
	cells.sort()
	for start: Vector2i in cells:
		if seen.has(start):
			continue
		var patch: Dictionary = {}
		var count: int = 0
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			count += 1
			for tile: Vector2i in cell_tiles(c):
				if sim.in_world(tile):
					patch[tile] = true
			for step: Vector2i in STEPS:
				var n: Vector2i = c + step
				if farm_cells.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		if not patch.is_empty():
			out.append({"tiles": patch, "cells": count})
	return out


func _in_patch(b: Dictionary, patch: Dictionary) -> bool:
	return patch.has(Vector2i(int(b["x"]), int(b["y"])))


# Farm-zone tiles on patches with no crop house yet.
func _unfarmed_tiles(sim, town) -> Dictionary:
	var out: Dictionary = {}
	for patch: Dictionary in estate_patches(sim, town):
		var farmed: bool = false
		for b: Dictionary in sim.buildings:
			if is_crop(str(b["type"])) and _in_patch(b, patch["tiles"]):
				farmed = true
				break
		if not farmed:
			out.merge(patch["tiles"])
	return out


func estate_name(tiles: int) -> String:
	var name: String = ""
	for size: Variant in spec.get("estates", {}).get("sizes", []):
		if size is Dictionary and tiles >= int(size.get("tiles", 0)):
			name = str(size.get("name", ""))
	return name


# Rebuilds sim.estates from the zone. Returns [{kind: "folded", id, into}] for small crop buildings
# that were folded into their patch's estate.
func refresh_estates(sim, town) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var found: Dictionary = {}
	for patch: Dictionary in estate_patches(sim, town):
		var tiles: Dictionary = patch["tiles"]
		var house: Dictionary = {}
		var extra: Array[Dictionary] = []
		for b: Dictionary in sim.buildings:
			if not is_crop(str(b["type"])) or not _in_patch(b, tiles):
				continue
			if house.is_empty():
				house = b
			else:
				extra.append(b)
		if house.is_empty():
			continue
		for b: Dictionary in extra:
			out.append({"kind": "folded", "id": int(b["id"]), "into": int(house["id"])})
			_fold(sim, b, house)
		var taken: Dictionary = {}
		for b: Dictionary in sim.buildings:
			for dy in int(b["size"]):
				for dx in int(b["size"]):
					taken[Vector2i(int(b["x"]) + dx, int(b["y"]) + dy)] = true
		var trail: float = sim.living.faint_threshold()
		var fields: Array[Vector2i] = []
		for tile: Vector2i in tiles:
			if taken.has(tile):
				continue
			var cell: Dictionary = sim.living.cells.get(sim.living.key(tile), {})
			if cell.get("stone", false) or float(cell.get("wear", 0.0)) >= trail:
				continue
			fields.append(tile)
		fields.sort()
		var size: int = fields.size() + int(house["size"]) * int(house["size"])
		found[int(house["id"])] = {"tiles": size, "fields": fields, "name": estate_name(size)}
	sim.estates = found
	_estate_sig = _estate_signature(sim, town)
	return out


# Folds a small crop building into its estate's house: its stores and crew move over, and it goes.
func _fold(sim, b: Dictionary, house: Dictionary) -> void:
	house["reserve"] = float(house["reserve"]) + float(b["reserve"])
	var role: String = str(sim.building_specs[house["type"]].get("workplace", ""))
	for u: Dictionary in sim.units:
		if int(u["workplace"]) == int(b["id"]):
			u["workplace"] = -1
			u["post"] = -1
			u["slot"] = 0
			u["sx"] = -1.0
			u["sy"] = -1.0
			if not role.is_empty() and sim.troop_specs.has(role):
				u["type"] = role
				u["workplace"] = int(house["id"])
		if int(u.get("site", -1)) == int(b["id"]):
			u["site"] = -1
	sim.buildings.erase(b)
	sim.revision += 1
	sim._invalidate()
	sim.stand_cache.clear()


# Why an estate cannot switch to this crop, or "" when it can.
func crop_reason(sim, id: int, type_name: String) -> String:
	var b: Dictionary = sim.get_building(id)
	if b.is_empty() or not sim.estates.has(id):
		return "Only a farm estate can change its crop."
	if not is_crop(type_name) or not sim.building_specs.has(type_name):
		return "Unknown crop."
	if str(b["type"]) == type_name:
		return "Already grown here."
	if sim.raid_active or sim.raid_warning:
		return "Hold the Manor until the alarm passes."
	if float(b["remaining"]) > 0.0 or float(b["hp"]) <= 0.0:
		return "Finish or repair the farm first."
	if int(sim.building_specs[type_name]["size"]) != int(b["size"]):
		return "That crop needs a different plot."
	# The simulation's own build rules (locks, prerequisites, limits), with this farm's plot treated as
	# empty: lift the house aside for the check and put it straight back.
	var x: int = int(b["x"])
	b["x"] = -100000
	var reason: String = sim.build_reason(type_name, x, int(b["y"]))
	b["x"] = x
	return "" if reason.is_empty() or reason == "Not enough resources." else reason


# Turns an estate over to another crop: the farmhouse is rebuilt for it (a tier 1 site with its
# materials bill), and its crew retrain for the new work.
func switch_crop(sim, id: int, type_name: String) -> bool:
	var reason: String = crop_reason(sim, id, type_name)
	if not reason.is_empty():
		sim.notice = reason
		return false
	var b: Dictionary = sim.get_building(id)
	var spec_b: Dictionary = sim.building_specs[type_name]
	b["type"] = type_name
	b["tier"] = 1
	b["max_hp"] = float(spec_b["tiers"][0]["hp"])
	b["hp"] = float(b["max_hp"])
	b["reserve"] = 0.0
	b["remaining"] = float(spec_b["buildSeconds"])
	sim.materials.open_site(sim, b, 1)
	var role: String = str(spec_b.get("workplace", ""))
	for u: Dictionary in sim.units:
		if int(u["workplace"]) == id and not role.is_empty() and sim.troop_specs.has(role):
			u["type"] = role
	sim.revision += 1
	sim._invalidate()
	sim.stand_cache.clear()
	sim.notice = "The estate turns to %s." % str(spec_b["name"])
	return true


# --- Paths ----------------------------------------------------------------------------------------
# A building that rises on a zone gets a dirt path from its door (its work stands, for a workplace)
# to the nearest path, road or the hall, and the hall keeps one out to the village's edge or gate.
# Paths are the living village's own trail cells, laid just past "faint" so villagers already
# prefer them; they wear in with use, fade if nobody walks them, and can be paved as before.

const LANE_WEAR: float = 1.6              # a laid path starts at this many times the faint-trail wear


func lane_wear(sim) -> float:
	return minf(1.0, sim.living.faint_threshold() * LANE_WEAR)


func _on_path(sim, tile: Vector2i) -> bool:
	var cell: Dictionary = sim.living.cells.get(sim.living.key(tile), {})
	return cell.get("stone", false) or float(cell.get("wear", 0.0)) >= sim.living.faint_threshold()


func _lay(sim, tiles: Array[Vector2i]) -> int:
	var wear: float = lane_wear(sim)
	var laid: int = 0
	for tile: Vector2i in tiles:
		var id: String = sim.living.key(tile)
		var cell: Dictionary = sim.living.cells.get(id, {"wear": 0.0, "last": sim.elapsed, "stone": false})
		if float(cell["wear"]) < wear:
			laid += 1
		cell["wear"] = maxf(float(cell["wear"]), wear)
		cell["last"] = sim.elapsed
		sim.living.cells[id] = cell
	if laid > 0:
		sim.living.revision += 1
		sim.living.navigation_revision += 1
	return laid


# Shortest walk from any start to a tile where `done` says yes, over reached tiles. [] when none.
func _walk_to(walk: Dictionary, starts: Array[Vector2i], done: Callable) -> Array[Vector2i]:
	var reached: PackedByteArray = walk["reached"]
	var width: int = (walk["rect"] as Rect2i).size.x
	var previous: Dictionary = {}
	var queue := PackedInt32Array()
	for tile: Vector2i in starts:
		var i: int = _index(walk, tile)
		if i >= 0 and reached[i] == 1 and not previous.has(i):
			previous[i] = -1
			queue.append(i)
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		if done.call(_tile(walk, i), i):
			var path: Array[Vector2i] = []
			while i >= 0:
				path.append(_tile(walk, i))
				i = int(previous[i])
			return path
		var x: int = i % width
		for next: int in [i - 1 if x > 0 else -1, i + 1 if x < width - 1 else -1, i - width, i + width]:
			if next < 0 or next >= reached.size() or reached[next] == 0 or previous.has(next):
				continue
			previous[next] = i
			queue.append(next)
	return []


# Lays the paths a building needs. Returns how many tiles were laid fresh.
func lay_lanes(sim, b: Dictionary) -> int:
	var walk: Dictionary = _walk(sim)
	if walk.is_empty():
		return 0
	var seeds: Dictionary = {}
	for i: int in walk["seeds"]:
		seeds[i] = true
	var laid: int = 0
	var joins: Callable = func(tile: Vector2i, i: int) -> bool: return seeds.has(i) or _on_path(sim, tile)
	var doors: Array = []
	for point: Vector2 in sim.stand_candidates(b):
		doors.append([Vector2i(floori(point.x), floori(point.y))])
	if doors.is_empty():
		var ring: Array[Vector2i] = _ring(Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"])))
		doors.append(ring)
	for door: Array in doors:
		var starts: Array[Vector2i] = []
		starts.assign(door)
		laid += _lay(sim, _walk_to(walk, starts, joins))
	return laid + lay_way_out(sim, walk)


# Keeps one path from the hall out of the village, to its edge (through an open gate when the
# village is walled). Returns how many tiles were laid fresh.
func lay_way_out(sim, walk: Dictionary = {}) -> int:
	if walk.is_empty():
		walk = _walk(sim)
		if walk.is_empty():
			return 0
	var edge: Callable = func(tile: Vector2i, _i: int) -> bool:
		for d: Vector2i in STEPS:
			if not sim.in_world(tile + d):
				return true
		return false
	var starts: Array[Vector2i] = []
	for i: int in walk["seeds"]:
		starts.append(_tile(walk, i))
	# Already out along a path (or road) all the way: nothing to lay.
	var along: Dictionary = walk.duplicate()
	var mask: PackedByteArray = (walk["reached"] as PackedByteArray).duplicate()
	for i in mask.size():
		if mask[i] == 1 and not _on_path(sim, _tile(walk, i)):
			mask[i] = 0
	for i: int in walk["seeds"]:
		mask[i] = 1
	along["reached"] = mask
	if not _walk_to(along, starts, edge).is_empty():
		return 0
	return _lay(sim, _walk_to(walk, starts, edge))

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
	sim.materials.open_site(sim, best, int(best["tier"]))
	sim.revision += 1
	sim.notice = "%s grows to tier %d on its own." % [str(spec_b["name"]), int(best["tier"])]
	lay_lanes(sim, best)
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


# Freshens one grown building's paths in turn, so paths stay down where people need them (and a
# village zoned before paths were laid gets them too). Returns how many tiles were laid fresh.
func tend_paths(sim) -> int:
	var grown: Array[Dictionary] = []
	for b: Dictionary in sim.buildings:
		if grows(str(b["type"])) and float(b["hp"]) > 0.0 and float(b["remaining"]) <= 0.0:
			grown.append(b)
	if grown.is_empty():
		return 0
	_tend = posmod(_tend, grown.size())
	var b: Dictionary = grown[_tend]
	_tend += 1
	return lay_lanes(sim, b)


# Zoned buildings nobody can walk to from the hall (a hand-built wall or tower can still close one
# in). Returns their ids.
func cut_off(sim) -> Array[int]:
	var out: Array[int] = []
	var walk: Dictionary = _walk(sim)
	if walk.is_empty():
		return out
	for b: Dictionary in sim.buildings:
		if not grows(str(b["type"])) or float(b["hp"]) <= 0.0:
			continue
		var door: bool = false
		for tile: Vector2i in _ring(Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"]))):
			var i: int = _index(walk, tile)
			if i >= 0 and walk["reached"][i] == 1:
				door = true
				break
		if not door:
			out.append(int(b["id"]))
	return out


# Tells the player once when a zoned building loses its way in.
func _warn_cut_off(sim) -> void:
	var now: Dictionary = {}
	for id: int in cut_off(sim):
		now[id] = true
		if not _cut.has(id):
			var b: Dictionary = sim.get_building(id)
			sim.notice = "The %s is walled in. Move what blocks it so its workers can reach it." % str(sim.building_specs[b["type"]]["name"])
	_cut = now


# Active time only. Returns what happened: [{kind: "rose"|"upgraded", ...}].
func tick(sim, town, dt: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if town == null:
		return out
	grow_clock += dt
	upgrade_clock += dt
	estate_clock += dt
	if estate_clock >= ESTATE_SECONDS or _estate_signature(sim, town) != _estate_sig:
		estate_clock = 0.0
		for event: Dictionary in refresh_estates(sim, town):
			out.append(event)
	if grow_clock >= float(spec.get("growSeconds", 5.0)):
		grow_clock = 0.0
		var rose: Dictionary = grow_one(sim, town)
		if not rose.is_empty():
			rose["kind"] = "rose"
			out.append(rose)
		elif not sim.raid_active and not sim.raid_warning:
			_warn_cut_off(sim)
	if upgrade_clock >= float(spec.get("upgradeSeconds", 24.0)):
		upgrade_clock = 0.0
		var up: Dictionary = hall_one(sim)
		if up.is_empty():
			up = upgrade_one(sim)
		if not up.is_empty():
			up["kind"] = "upgraded"
			out.append(up)
		elif not sim.raid_active and not sim.raid_warning:
			tend_paths(sim)
	return out
