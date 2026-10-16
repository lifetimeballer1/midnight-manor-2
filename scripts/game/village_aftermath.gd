extends RefCounted

# What a raid leaves behind in the economy (saved with the village, optional in older saves).
#   * Raiders who cross a farm estate's fields trample them: a trampled tile grows nothing until the
#     estate's farmhands replant it (REPLANT_SECONDS per tile for each farmhand, between raids).
#   * A stone building that falls leaves rubble worth RUBBLE_SHARE of the stone it would take to
#     rebuild from nothing. Builders with no site to work carry it back to the stores.
#   * Fighters who fell come round beside the best healing building (the Chapel), where its healing
#     aura closes their wounds faster.

const REPLANT_SECONDS: float = 3.0
const RUBBLE_SHARE: float = 0.3
const MAX_RUBBLE: int = 24

var trampled: Dictionary = {}        # Vector2i field tile -> true
var rubble: Array[Dictionary] = []   # {x, y, stone}: piles where stone buildings fell
var raid_trampled: int = 0          # this raid's marks, for the notice when it ends
var raid_rubble: int = 0
var _replant: Dictionary = {}        # house id -> part-done replanting
var _index: Dictionary = {}          # field tile -> estate house id
var _indexed: Variant = null         # the sim.estates dictionary _index was built from


func _owner_index(sim) -> Dictionary:
	if not is_same(_indexed, sim.estates):
		_indexed = sim.estates
		_index.clear()
		for id: int in sim.estates:
			for tile: Vector2i in sim.estates[id]["fields"]:
				_index[tile] = id
	return _index


# The estate house whose field this tile is, or -1.
func field_owner(sim, tile: Vector2i) -> int:
	return int(_owner_index(sim).get(tile, -1))


# A raider steps on a tile: estate fields are trampled.
func trample(sim, tile: Vector2i) -> void:
	if not trampled.has(tile) and field_owner(sim, tile) >= 0:
		trampled[tile] = true
		raid_trampled += 1


func trampled_on(sim, house_id: int) -> int:
	if trampled.is_empty():
		return 0
	var count: int = 0
	var index: Dictionary = _owner_index(sim)
	for tile: Vector2i in trampled:
		if int(index.get(tile, -1)) == house_id:
			count += 1
	return count


# Fields the estate can grow on right now (its tiles less the trampled ones).
func growing_tiles(sim, house_id: int) -> int:
	var estate: Dictionary = sim.estates.get(house_id, {})
	if estate.is_empty():
		return 0
	return maxi(0, int(estate["tiles"]) - trampled_on(sim, house_id))


# A stone building has fallen: leave rubble worth part of its stone.
func fell(sim, b: Dictionary) -> void:
	if not sim.materials.stone_built(str(b["type"])) or not sim.materials.stone_known(sim):
		return
	var per_unit: float = float(sim.materials.config.get("repair", {}).get("hpPerUnit", 15.0))
	var stone: int = int(float(sim.materials.repair_cost(sim, b, float(b["max_hp"]), per_unit).get("stone", 0)) * RUBBLE_SHARE)
	if stone <= 0:
		return
	var at: Vector2 = sim.center(b)
	for pile: Dictionary in rubble:
		if Vector2(float(pile["x"]), float(pile["y"])).distance_to(at) < 0.5:
			pile["stone"] = int(pile["stone"]) + stone
			raid_rubble += stone
			return
	if rubble.size() >= MAX_RUBBLE:
		rubble.pop_front()
	rubble.append({"x": at.x, "y": at.y, "stone": stone})
	raid_rubble += stone


func begin_raid() -> void:
	raid_trampled = 0
	raid_rubble = 0


# One sentence on what this raid left behind, or "".
func raid_summary() -> String:
	var parts: PackedStringArray = []
	if raid_trampled > 0:
		parts.append("%d field %s trampled; farmhands will replant." % [raid_trampled, "tile" if raid_trampled == 1 else "tiles"])
	if raid_rubble > 0:
		parts.append("Builders can salvage %d Stone from the rubble." % raid_rubble)
	return " ".join(parts)


# The rubble pile nearest a point, or {}.
func nearest_rubble(at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for pile: Dictionary in rubble:
		var distance: float = at.distance_to(Vector2(float(pile["x"]), float(pile["y"])))
		if distance < best_distance:
			best = pile
			best_distance = distance
	return best


# Takes up to `amount` stone off a pile; an emptied pile goes.
func salvage(pile: Dictionary, amount: int) -> int:
	var taken: int = mini(amount, int(pile["stone"]))
	pile["stone"] = int(pile["stone"]) - taken
	if int(pile["stone"]) <= 0:
		rubble.erase(pile)
	return taken


func tick(sim, dt: float) -> void:
	if trampled.is_empty() or sim.raid_active or sim.paused or dt <= 0.0:
		return
	var index: Dictionary = _owner_index(sim)
	# Tiles no longer in any estate's fields need no replanting (the estates are worked out after a load).
	if index.is_empty():
		return
	for tile: Vector2i in trampled.keys():
		if not index.has(tile):
			trampled.erase(tile)
	var by_house: Dictionary = {}
	for tile: Vector2i in trampled:
		var id: int = int(index[tile])
		if not by_house.has(id):
			by_house[id] = []
		by_house[id].append(tile)
	for id: int in by_house:
		var house: Dictionary = sim.get_building(id)
		if house.is_empty() or float(house["hp"]) <= 0.0:
			continue
		var hands: int = sim.crew_of(house)
		if hands <= 0:
			continue
		var done: float = float(_replant.get(id, 0.0)) + dt * hands / REPLANT_SECONDS
		var tiles: Array = by_house[id]
		tiles.sort()
		while done >= 1.0 and not tiles.is_empty():
			trampled.erase(tiles.pop_front())
			done -= 1.0
		_replant[id] = done if not tiles.is_empty() else 0.0


# Where fighters who fell come round: beside the strongest standing healer, or Vector2(-1, -1).
func recovery_spot(sim) -> Vector2:
	var best: Dictionary = {}
	var best_rate: float = 0.0
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) <= 0.0 or float(b["remaining"]) > 0.0:
			continue
		var rate: float = float(sim.building_specs[b["type"]].get("healRate", 0.0))
		if rate > best_rate:
			best = b
			best_rate = rate
	if best.is_empty():
		return Vector2(-1, -1)
	for point: Vector2 in sim.stand_candidates(best) + sim.edge_candidates(best, false):
		if sim.in_world(Vector2i(floori(point.x), floori(point.y))):
			return point
	return Vector2(-1, -1)


func state() -> Dictionary:
	var tiles: Array = []
	for tile: Vector2i in trampled:
		tiles.append([tile.x, tile.y])
	return {"trampled": tiles, "rubble": rubble.duplicate(true)}


func valid(data: Variant) -> bool:
	if data == null:
		return true
	if not data is Dictionary:
		return false
	var tiles: Variant = data.get("trampled", [])
	if not tiles is Array or (tiles as Array).size() > 4000:
		return false
	for tile: Variant in tiles:
		if not tile is Array or (tile as Array).size() != 2 or not (tile[0] is int or tile[0] is float) or not (tile[1] is int or tile[1] is float):
			return false
	var piles: Variant = data.get("rubble", [])
	if not piles is Array or (piles as Array).size() > MAX_RUBBLE:
		return false
	for pile: Variant in piles:
		if not pile is Dictionary:
			return false
		for key: String in ["x", "y", "stone"]:
			var value: Variant = pile.get(key)
			if not (value is int or value is float) or not is_finite(float(value)):
				return false
		if float(pile["stone"]) <= 0.0:
			return false
	return true


func restore(data: Variant) -> void:
	trampled.clear()
	rubble.clear()
	_replant.clear()
	if not data is Dictionary:
		return
	for tile: Array in data.get("trampled", []):
		trampled[Vector2i(int(tile[0]), int(tile[1]))] = true
	for pile: Dictionary in data.get("rubble", []):
		rubble.append({"x": float(pile["x"]), "y": float(pile["y"]), "stone": int(pile["stone"])})
