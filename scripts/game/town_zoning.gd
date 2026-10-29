extends RefCounted

# The town outside the walls: a zoning model in the spirit of a city builder, on the manor's own
# land in the realm (its claim around the village, its outposts and any sworn neighbour's land).
#
#   * The land is a grid of 4 m cells (two village tiles each, aligned with the village grid).
#     The village and its four reaches are not part of the town. Their ground can be zoned too
#     (village, below), where the village's own buildings rise instead of town lots.
#   * The player paints cells as housing, farming, industry or civic, and lays roads. Nothing is
#     built by hand: a zoned cell beside a road that leads back to the manor (or an outpost) grows
#     a lot when there is demand for its kind, and the lot moves up a level when its needs are met
#     (food, safety, nearby farms, homes, civic buildings, enough townsfolk).
#   * Demand follows the town itself: homes want jobs, farms and industry want hands, civic wants a
#     growing population.
#   * Built lots send income to the manor every incomeSeconds of active play; the village layer banks
#     it through the simulation's own storage rules. A lot whose road no longer reaches the manor or
#     an outpost is cut off and sends nothing until it is joined up again.
#   * Roads can be paved with Stone. Lots beside a paved road level faster, and the finest homes and
#     halls want one. Neighbours matter too: industry next door slows a home, civic buildings nearby
#     speed lots along (pace()).
#   * The town earns a title as it grows (Hamlet, Village, Market Town...), each with a one-off
#     reward the first time it is reached.
#
# Everything here is data in data/zones.json (art per level, needs, income, timings), its own save
# (town-v1.json, beside the village and realm saves) and plain numbers advanced by active time, so
# paused or closed time adds nothing. The village simulation and its save are not touched.
#
# Village zoning: cells inside the village may be zoned as well (`village`, cell -> zone). Nothing
# here grows on them; village_growth.gd raises the village's own buildings there, free. Those zones
# are kept in this save so the village save stays as it was.

const VERSION: int = 1
const VILLAGE_HALF := Vector2(40.0, 36.0)   # the village and all four reaches, world metres
const ROOT_REACH: float = 7.0               # a road cell this close to an outpost joins its network
const STEEP: float = 2.4                    # corner-to-corner fall that makes a cell unbuildable
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DEMAND_GROW: float = 0.12             # a zone grows only above this demand

var specs: Dictionary = {}
var cell: float = 4.0
var realm = null                            # realm_map.gd; land, outposts and heights come from it
var height_at: Callable                     # optional: (x, z) -> ground height, for the slope check

var zones: Dictionary = {}                  # Vector2i -> zone id
var roads: Dictionary = {}                  # Vector2i -> true
var paved: Dictionary = {}                  # Vector2i -> true, a subset of roads
var lots: Dictionary = {}                   # Vector2i -> {zone, level, build, progress, variant, age}
var village: Dictionary = {}                # Vector2i -> zone id, zoned ground inside the village
var elapsed: float = 0.0
var grow_clock: float = 0.0
var income_clock: float = 0.0
var zone_boost: Dictionary = {}             # zone -> income multiplier from milestones (set by the game layer; not saved)
var level_clock: float = 0.0                # needs are checked a couple of times a second, not per frame
var revision: int = 0                       # bumps on any change the view draws
var events: Array[Dictionary] = []          # grew / levelled / income / cleared; take_events() drains them
var village_food: float = 0.0               # set by the village layer each tick (the "food" need)
var rng := RandomNumberGenerator.new()
var best_tier: int = 0                      # the highest town title reached (-1: set it quietly from the town)

var _land: Dictionary = {}                  # Vector2i -> reason ("" = buildable), per land key
var _land_key: String = ""
var _ground: Dictionary = {}                # Vector2i -> reason from the ground alone (never changes)
var _claims: Array[Dictionary] = []
var _network: Dictionary = {}               # road cells that reach the manor or an outpost
var _network_key: String = ""
var _people_now: int = -1                   # townsfolk, refreshed with each needs check
var _near: Dictionary = {}                  # _nearby() answers for the current revision
var _near_revision: int = -1


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/zones.json"))
	specs = parsed if parsed is Dictionary else {}
	cell = float(specs.get("cellMetres", 4.0))
	rng.seed = 2207


func zone_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in specs.get("order", []):
		ids.append(str(id))
	return ids


func zone_spec(zone: String) -> Dictionary:
	return specs.get("zones", {}).get(zone, {})


func level_spec(zone: String, level: int) -> Dictionary:
	var levels: Array = zone_spec(zone).get("levels", [])
	if levels.is_empty():
		return {}
	return levels[clampi(level - 1, 0, levels.size() - 1)]


func max_level(zone: String) -> int:
	return (zone_spec(zone).get("levels", []) as Array).size()


func zone_color(zone: String) -> Color:
	if zone == "road":
		return Color(str(specs.get("road", {}).get("color", "a68a62")))
	return Color(str(zone_spec(zone).get("color", "ffffff")))


func village_spec() -> Dictionary:
	return specs.get("village", {})


# Zones a village cell can take: those with village building types listed for them.
func village_zone_ids() -> Array[String]:
	var ids: Array[String] = []
	for zone: String in zone_ids():
		if not (village_spec().get("zones", {}).get(zone, []) as Array).is_empty():
			ids.append(zone)
	return ids


# Zones a village cell. The village layer checks first that the ground is the manor's.
func paint_village(c: Vector2i, zone: String) -> String:
	if not in_village(c):
		return "Outside the village."
	if zone not in village_zone_ids():
		return "Unknown zone."
	if str(village.get(c, "")) == zone:
		return ""
	village[c] = zone
	revision += 1
	return ""


func road_cost() -> Dictionary:
	return specs.get("road", {}).get("cost", {})


func pave_cost() -> Dictionary:
	return specs.get("road", {}).get("paveCost", {})


func pace_spec() -> Dictionary:
	return specs.get("pace", {})


# Town titles by townsfolk, lowest first: [{name, people, reward}].
func titles() -> Array:
	return specs.get("titles", [{"name": "Outskirts", "people": 0}])


func tier_for(people: int) -> int:
	var tier: int = 0
	var list: Array = titles()
	for index in list.size():
		if people >= int(list[index].get("people", 0)):
			tier = index
	return tier


func title() -> String:
	var list: Array = titles()
	return str(list[clampi(tier_for(int(stats()["people"])), 0, list.size() - 1)].get("name", ""))


# The next title and the townsfolk it takes, or {} at the top.
func next_title() -> Dictionary:
	var list: Array = titles()
	var tier: int = tier_for(int(stats()["people"]))
	return list[tier + 1] if tier + 1 < list.size() else {}


# --- Grid -----------------------------------------------------------------------------------------

func cell_of(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / cell), floori(world.y / cell))


func cell_centre(c: Vector2i) -> Vector2:
	return Vector2((float(c.x) + 0.5) * cell, (float(c.y) + 0.5) * cell)


func in_village(c: Vector2i) -> bool:
	var centre: Vector2 = cell_centre(c)
	return absf(centre.x) < VILLAGE_HALF.x and absf(centre.y) < VILLAGE_HALF.y


# Distance from a point to the village rectangle (0 inside it).
func village_distance(point: Vector2) -> float:
	var dx: float = maxf(absf(point.x) - VILLAGE_HALF.x, 0.0)
	var dz: float = maxf(absf(point.y) - VILLAGE_HALF.y, 0.0)
	return Vector2(dx, dz).length()


# Why a cell cannot be zoned or built on, or "" when it can. The ground itself (river, slope,
# bridges, jetties) never changes and is cached for good; ownership is rechecked when borders or
# outposts move, against claims gathered once per change.
func land_reason(c: Vector2i) -> String:
	var key: String = _current_land_key()
	if key != _land_key:
		_land_key = key
		_land.clear()
		_claims = realm.claims() if realm != null else []
	if _land.has(c):
		return _land[c]
	var reason: String = _ground_reason(c)
	if reason.is_empty():
		var centre: Vector2 = cell_centre(c)
		var owner: String = realm._owner_from(_claims, centre)
		if owner == "":
			reason = "Wild land. Tap it to buy it for the town."
		elif owner != "home":
			reason = "%s's land. Tap it to see how to take it." % str(realm.settlement(owner).get("name", "A neighbour"))
		else:
			for outpost: Dictionary in realm.outposts:
				if (outpost["pos"] as Vector2).distance_to(centre) < cell * 0.9:
					reason = "An outpost stands here."
	_land[c] = reason
	return reason


# Who holds a cell's ground: "home", a neighbour's id, or "" for wild land.
func land_owner(c: Vector2i) -> String:
	if realm == null:
		return ""
	land_reason(c)   # refreshes the claims when borders moved
	return realm._owner_from(_claims, cell_centre(c))


# Wild ground beside the manor's own that the town could buy (realm deeds), cell by cell.
func buyable(c: Vector2i) -> bool:
	if realm == null or in_village(c) or not _ground_reason(c).is_empty():
		return false
	land_reason(c)
	return realm.deed_reason(cell_centre(c), _claims).is_empty()


func _current_land_key() -> String:
	if realm == null:
		return "none"
	return "%d/%d" % [int(realm.revision), (realm.outposts as Array).size()]


func _ground_reason(c: Vector2i) -> String:
	if _ground.has(c):
		return _ground[c]
	var reason: String = _ground_check(c)
	_ground[c] = reason
	return reason


func _ground_check(c: Vector2i) -> String:
	if in_village(c):
		return "The village keeps its own paths. Roads start at its edge."
	if realm == null:
		return "There is no land out here."
	var centre: Vector2 = cell_centre(c)
	var edge: float = float(realm.EDGE_DROP_FROM) - 8.0
	if absf(centre.x) > edge or absf(centre.y) > edge:
		return "Too far out."
	var half: float = cell * 0.5
	var low: float = INF
	var high: float = -INF
	for corner: Vector2 in [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half), Vector2.ZERO]:
		var p: Vector2 = centre + corner
		if realm.is_water(p.x, p.y):
			return "The river runs here."
		var y: float = float(height_at.call(p.x, p.y)) if height_at.is_valid() else float(realm.height_at(p.x, p.y))
		low = minf(low, y)
		high = maxf(high, y)
	if high - low > STEEP:
		return "Too steep to build on."
	if not is_nan(float(realm.bridge_deck_at(centre.x, centre.y))):
		return "A bridge stands here."
	for spot: Dictionary in realm.fishing_spots:
		var jetty: Vector2 = (spot["pos"] as Vector2) + (spot["dir"] as Vector2) * 2.5
		if jetty.distance_to(centre) < cell * 0.9 or (spot["pos"] as Vector2).distance_to(centre) < cell * 0.6:
			return "A jetty stands here."
	return ""


func can_build(c: Vector2i) -> bool:
	return land_reason(c).is_empty()


# --- Painting -------------------------------------------------------------------------------------

# Paints a zone. Returns "" on success (or when the cell already has that zone).
func paint_zone(c: Vector2i, zone: String) -> String:
	if zone_spec(zone).is_empty():
		return "Unknown zone."
	var reason: String = land_reason(c)
	if not reason.is_empty():
		return reason
	if roads.has(c):
		return "A road runs here."
	if str(zones.get(c, "")) == zone:
		return ""
	if lots.has(c):
		_clear_lot(c)
	zones[c] = zone
	revision += 1
	return ""


# Lays a road (the village layer charges road_cost() first). Clears any zone and lot on the cell.
func road_reason(c: Vector2i) -> String:
	if roads.has(c):
		return "There is a road here already."
	return land_reason(c)


func paint_road(c: Vector2i) -> String:
	var reason: String = road_reason(c)
	if not reason.is_empty():
		return reason
	if lots.has(c):
		_clear_lot(c)
	zones.erase(c)
	roads[c] = true
	revision += 1
	return ""


# Paving an existing road (the village layer charges pave_cost() first).
func pave_reason(c: Vector2i) -> String:
	if not roads.has(c):
		return "Pave a road: lay one here first."
	if paved.has(c):
		return "This road is paved already."
	return ""


func pave(c: Vector2i) -> String:
	var reason: String = pave_reason(c)
	if not reason.is_empty():
		return reason
	paved[c] = true
	revision += 1
	return ""


# Removes whatever is on a cell. Returns true when something was there.
func erase(c: Vector2i) -> bool:
	var changed: bool = false
	if lots.has(c):
		_clear_lot(c)
		changed = true
	if zones.has(c):
		zones.erase(c)
		changed = true
	if roads.has(c):
		roads.erase(c)
		paved.erase(c)
		changed = true
	if village.has(c):
		village.erase(c)
		changed = true
	if changed:
		revision += 1
	return changed


func _clear_lot(c: Vector2i) -> void:
	var lot: Dictionary = lots[c]
	lots.erase(c)
	events.append({"kind": "cleared", "cell": c, "zone": str(lot["zone"]), "level": int(lot["level"])})
	revision += 1


# --- Roads ----------------------------------------------------------------------------------------

# Road cells that lead back to the manor (touching the village edge) or to an outpost.
func network() -> Dictionary:
	var key: String = "%d/%s" % [revision, _current_land_key()]
	if key == _network_key:
		return _network
	_network_key = key
	_network = {}
	var queue: Array[Vector2i] = []
	for c: Vector2i in roads:
		if is_root(c):
			_network[c] = true
			queue.append(c)
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for d: Vector2i in DIRS:
			var next: Vector2i = at + d
			if roads.has(next) and not _network.has(next):
				_network[next] = true
				queue.append(next)
	return _network


# A road cell that starts a network: beside the village edge, or next to an outpost.
func is_root(c: Vector2i) -> bool:
	for d: Vector2i in DIRS:
		if in_village(c + d):
			return true
	if realm != null:
		var centre: Vector2 = cell_centre(c)
		for outpost: Dictionary in realm.outposts:
			if (outpost["pos"] as Vector2).distance_to(centre) <= ROOT_REACH:
				return true
	return false


# Where a road may start: cells beside the village edge (for the view's hint).
func village_edge(c: Vector2i) -> bool:
	if in_village(c):
		return false
	for d: Vector2i in DIRS:
		if in_village(c + d):
			return true
	return false


func has_access(c: Vector2i) -> bool:
	var net: Dictionary = network()
	for d: Vector2i in DIRS:
		if net.has(c + d):
			return true
	return false


# A connected, paved road beside the cell.
func paved_access(c: Vector2i) -> bool:
	var net: Dictionary = network()
	for d: Vector2i in DIRS:
		if paved.has(c + d) and net.has(c + d):
			return true
	return false


# The road neighbour a lot faces, or (0, 0) when it has none.
func road_side(c: Vector2i) -> Vector2i:
	var net: Dictionary = network()
	for d: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		if net.has(c + d):
			return d
	for d: Vector2i in DIRS:
		if roads.has(c + d):
			return d
	return Vector2i.ZERO


# --- Town figures ---------------------------------------------------------------------------------

func built(lot: Dictionary) -> bool:
	return float(lot.get("build", 0.0)) <= 0.0


func stats() -> Dictionary:
	var result: Dictionary = {"people": 0, "jobs": 0, "lots": 0, "building": 0, "zoned": zones.size(), "roads": roads.size(),
		"paved": paved.size(), "cut_off": 0}
	var by_zone: Dictionary = {}
	var jobs_by: Dictionary = {}
	for id: String in zone_ids():
		by_zone[id] = 0
		jobs_by[id] = 0
	for c: Vector2i in lots:
		var lot: Dictionary = lots[c]
		if not built(lot):
			result["building"] = int(result["building"]) + 1
			continue
		var zone: String = str(lot["zone"])
		var level: Dictionary = level_spec(zone, int(lot["level"]))
		result["lots"] = int(result["lots"]) + 1
		if not has_access(c):
			result["cut_off"] = int(result["cut_off"]) + 1
		by_zone[zone] = int(by_zone.get(zone, 0)) + 1
		result["people"] = int(result["people"]) + int(level.get("residents", 0))
		result["jobs"] = int(result["jobs"]) + int(level.get("jobs", 0))
		jobs_by[zone] = int(jobs_by.get(zone, 0)) + int(level.get("jobs", 0))
	result["by_zone"] = by_zone
	result["jobs_by"] = jobs_by
	return result


# Demand for each zone, 0..1, like a city builder's demand bars. Lots under construction count as
# if built so one wave of demand does not start a dozen houses at once.
func demand() -> Dictionary:
	var people: float = 0.0
	var jobs: Dictionary = {}
	var count: Dictionary = {}
	for id: String in zone_ids():
		jobs[id] = 0.0
		count[id] = 0
	for c: Vector2i in lots:
		var lot: Dictionary = lots[c]
		var zone: String = str(lot["zone"])
		var level: Dictionary = level_spec(zone, int(lot["level"]))
		people += float(level.get("residents", 0))
		jobs[zone] = float(jobs.get(zone, 0.0)) + float(level.get("jobs", 0))
		count[zone] = int(count.get(zone, 0)) + 1
	var all_jobs: float = 0.0
	for id: String in jobs:
		all_jobs += float(jobs[id])
	# Homes: a little room to start, then they follow the jobs on offer.
	var housing: float = clampf((all_jobs + 10.0 - people) / 12.0, 0.0, 1.0)
	# Farms and industry: about half the town works the fields, a third in the yards.
	var farming: float = clampf((people * 0.5 + 3.0 - float(jobs.get("farming", 0.0))) / 8.0, 0.0, 1.0)
	var industrial: float = clampf((people * 0.35 + 1.0 - float(jobs.get("industrial", 0.0))) / 8.0, 0.0, 1.0)
	if people < 4.0:
		industrial = minf(industrial, 0.1)
	# Civic: one for every twenty townsfolk or so, once there are people to serve.
	var civic: float = clampf(people / 20.0 + 0.4 - float(count.get("civic", 0)), 0.0, 1.0) if people >= 4.0 else 0.0
	return {"housing": housing, "farming": farming, "industrial": industrial, "civic": civic}


# --- Needs ----------------------------------------------------------------------------------------

func _nearby(c: Vector2i, zone: String, within: int, min_level: int = 1) -> int:
	# Every lot asks this for each need a couple of times a second; the answers only change with
	# the town, so they are kept until the next change.
	if _near_revision != revision:
		_near_revision = revision
		_near.clear()
	var key: String = "%d,%d,%s,%d,%d" % [c.x, c.y, zone, within, min_level]
	if _near.has(key):
		return _near[key]
	var found: int = 0
	for other: Vector2i in lots:
		if other == c:
			continue
		var lot: Dictionary = lots[other]
		if str(lot["zone"]) != zone or not built(lot) or int(lot["level"]) < min_level:
			continue
		if absi(other.x - c.x) <= within and absi(other.y - c.y) <= within:
			found += 1
	_near[key] = found
	return found


func safe(c: Vector2i) -> bool:
	var centre: Vector2 = cell_centre(c)
	if village_distance(centre) <= float(specs.get("safeFromWalls", 22.0)):
		return true
	if realm != null:
		for outpost: Dictionary in realm.outposts:
			if (outpost["pos"] as Vector2).distance_to(centre) <= float(specs.get("safeFromOutpost", 20.0)):
				return true
	return _nearby(c, "civic", 5) > 0


# One need's label and whether the cell meets it now.
func need_status(c: Vector2i, need: Dictionary) -> Dictionary:
	var kind: String = str(need.get("kind", ""))
	match kind:
		"food":
			var amount: float = float(need.get("amount", 1))
			return {"label": "The manor has Food in store (%d)" % int(amount), "met": village_food >= amount, "short": "Food"}
		"safety":
			return {"label": "Safe: near the walls, an outpost or a watch post", "met": safe(c), "short": "Safety"}
		"people":
			var amount: int = int(need.get("amount", 1))
			var people: int = _people_now if _people_now >= 0 else int(stats()["people"])
			return {"label": "%d townsfolk" % amount, "met": people >= amount, "short": "%d folk" % amount}
		"road":
			return {"label": "A road to the manor", "met": has_access(c), "short": "Road"}
		"paved":
			return {"label": "A paved road beside it", "met": paved_access(c), "short": "Paved road"}
	if zone_spec(kind).is_empty():
		return {"label": kind, "met": true, "short": kind}
	var within: int = int(need.get("within", 6))
	var wanted: int = int(need.get("count", 1))
	var name: String = str(zone_spec(kind).get("short", kind)).to_lower()
	var label: String = "%s nearby" % name.capitalize() if wanted <= 1 else "%d %s nearby" % [wanted, name]
	return {"label": label, "met": _nearby(c, kind, within) >= wanted, "short": name.capitalize() if wanted <= 1 else "%d %s" % [wanted, name]}


# The next level's needs for a lot, each {label, met}. Empty at the top level.
func next_needs(c: Vector2i) -> Array[Dictionary]:
	_people_now = int(stats()["people"])
	var result: Array[Dictionary] = []
	if not lots.has(c):
		return result
	var lot: Dictionary = lots[c]
	var zone: String = str(lot["zone"])
	var level: int = int(lot["level"])
	if level >= max_level(zone):
		return result
	result.append(need_status(c, {"kind": "road"}))
	for need: Dictionary in level_spec(zone, level + 1).get("needs", []):
		result.append(need_status(c, need))
	return result


# The first thing holding a lot back, as a short label ("" when nothing is): its road first, then
# its next level's unmet needs.
func problem(c: Vector2i) -> String:
	if not lots.has(c) or not built(lots[c]):
		return ""
	if not has_access(c):
		return "No road"
	for need: Dictionary in next_needs(c):
		if not bool(need["met"]):
			return str(need.get("short", need["label"]))
	return ""


# How fast a lot works toward its next level, and why: {factor, notes: [{label, good}]}.
func pace(c: Vector2i) -> Dictionary:
	var rules: Dictionary = pace_spec()
	var factor: float = 1.0
	var notes: Array[Dictionary] = []
	if not lots.has(c):
		return {"factor": factor, "notes": notes}
	var zone: String = str(lots[c]["zone"])
	if zone == "housing" and _nearby(c, "industrial", 1) > 0:
		factor *= float(rules.get("noisyNeighbour", 0.5))
		notes.append({"label": "Industry next door: slower", "good": false})
	if zone != "civic" and _nearby(c, "civic", int(rules.get("civicWithin", 3))) > 0:
		factor *= float(rules.get("civicNearby", 1.25))
		notes.append({"label": "Civic nearby: faster", "good": true})
	if paved_access(c):
		factor *= float(rules.get("pavedRoad", 1.25))
		notes.append({"label": "Paved road: faster", "good": true})
	return {"factor": factor, "notes": notes}


func needs_met(c: Vector2i, zone: String, level: int) -> bool:
	if not has_access(c):
		return false
	for need: Dictionary in level_spec(zone, level).get("needs", []):
		if not bool(need_status(c, need)["met"]):
			return false
	return true


# --- Time -----------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	elapsed += dt
	_construct(dt)
	level_clock += dt
	if level_clock >= 0.5:
		_people_now = int(stats()["people"])
		_level_up(level_clock)
		level_clock = 0.0
		_check_title()
	grow_clock += dt
	if grow_clock >= float(specs.get("growSeconds", 3.5)):
		grow_clock = 0.0
		grow_one()
	income_clock += dt
	if income_clock >= float(specs.get("incomeSeconds", 60.0)):
		income_clock = 0.0
		var income: Dictionary = income_now()
		if not income.is_empty():
			events.append({"kind": "income", "income": income})


func _construct(dt: float) -> void:
	for c: Vector2i in lots:
		var lot: Dictionary = lots[c]
		if float(lot["build"]) > 0.0:
			lot["build"] = maxf(float(lot["build"]) - dt, 0.0)
			if float(lot["build"]) <= 0.0:
				events.append({"kind": "grew", "cell": c, "zone": str(lot["zone"]), "level": int(lot["level"])})
				revision += 1


# Built lots whose next level's needs are met work toward it; unmet needs ease the progress back.
func _level_up(dt: float) -> void:
	for c: Vector2i in lots:
		var lot: Dictionary = lots[c]
		if not built(lot):
			continue
		var zone: String = str(lot["zone"])
		var level: int = int(lot["level"])
		if level >= max_level(zone):
			continue
		if needs_met(c, zone, level + 1):
			lot["progress"] = float(lot["progress"]) + dt * float(pace(c)["factor"])
			if float(lot["progress"]) >= float(level_spec(zone, level + 1).get("seconds", 60.0)):
				lot["level"] = level + 1
				lot["progress"] = 0.0
				events.append({"kind": "levelled", "cell": c, "zone": zone, "level": level + 1})
				revision += 1
		else:
			lot["progress"] = maxf(float(lot["progress"]) - dt * 0.5, 0.0)


# A new title the first time the town reaches it, with its reward. A save from before titles
# existed takes the town's current title quietly.
func _check_title() -> void:
	var tier: int = tier_for(maxi(_people_now, 0))
	if best_tier < 0:
		best_tier = tier
		return
	if tier <= best_tier:
		return
	best_tier = tier
	var entry: Dictionary = titles()[tier]
	events.append({"kind": "title", "tier": tier, "name": str(entry.get("name", "")), "reward": entry.get("reward", {})})


# Zoned cells with a road and no lot yet, grouped by zone.
func candidates() -> Dictionary:
	var result: Dictionary = {}
	for c: Vector2i in zones:
		if lots.has(c) or not can_build(c) or not has_access(c):
			continue
		var zone: String = str(zones[c])
		if not result.has(zone):
			result[zone] = []
		(result[zone] as Array).append(c)
	return result


# Starts one lot where demand is highest (weighted, so every wanted zone gets its turn).
# Returns the cell, or (-9999, -9999) when nothing could grow.
func grow_one() -> Vector2i:
	var none := Vector2i(-9999, -9999)
	var open: Dictionary = candidates()
	if open.is_empty():
		return none
	var wants: Dictionary = demand()
	var total: float = 0.0
	for zone: String in open:
		if float(wants.get(zone, 0.0)) > DEMAND_GROW:
			total += float(wants[zone])
	if total <= 0.0:
		return none
	var pick: float = rng.randf() * total
	var chosen: String = ""
	for zone: String in open:
		var want: float = float(wants.get(zone, 0.0))
		if want <= DEMAND_GROW:
			continue
		chosen = zone
		pick -= want
		if pick <= 0.0:
			break
	var cells: Array = open[chosen]
	# Grow inward from the road network's start, so towns fill out from the gate.
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _grow_rank(a) < _grow_rank(b))
	var c: Vector2i = cells[mini(rng.randi() % 2, cells.size() - 1)]
	lots[c] = {"zone": chosen, "level": 1, "build": float(specs.get("buildSeconds", 6.0)), "progress": 0.0,
		"variant": rng.randi() % 997, "age": elapsed}
	events.append({"kind": "started", "cell": c, "zone": chosen, "level": 1})
	revision += 1
	return c


func _grow_rank(c: Vector2i) -> float:
	var centre: Vector2 = cell_centre(c)
	var rank: float = village_distance(centre)
	if realm != null:
		for outpost: Dictionary in realm.outposts:
			rank = minf(rank, (outpost["pos"] as Vector2).distance_to(centre))
	return rank + float(posmod(c.x * 7 + c.y * 13, 5)) * 0.3


# What every built lot on the manor's land sends in one income period.
func income_now() -> Dictionary:
	var total: Dictionary = {}
	for c: Vector2i in lots:
		var lot: Dictionary = lots[c]
		if not built(lot) or not can_build(c) or not has_access(c):
			continue
		var income: Dictionary = level_spec(str(lot["zone"]), int(lot["level"])).get("income", {})
		var boost: float = float(zone_boost.get(str(lot["zone"]), 1.0))
		for resource: String in income:
			total[resource] = int(total.get(resource, 0)) + int(round(float(income[resource]) * boost))
	return total


# Income milestones (zones.json "milestones"): how many of them `count` standing buildings reach,
# and the income multiplier that gives.
func milestone_counts() -> Array:
	return specs.get("milestones", {}).get("counts", [])


func milestone_tier(count: int) -> int:
	var tier: int = 0
	for need: Variant in milestone_counts():
		if count >= int(need):
			tier += 1
	return tier


func milestone_multiplier(tier: int) -> float:
	return pow(float(specs.get("milestones", {}).get("multiplier", 1.0)), tier)


func take_events() -> Array[Dictionary]:
	var drained: Array[Dictionary] = events.duplicate()
	events.clear()
	return drained


# The asset a lot shows: its level's art list, picked by the lot's own variant.
func lot_asset(lot: Dictionary) -> String:
	var assets: Array = level_spec(str(lot["zone"]), int(lot["level"])).get("assets", [])
	if assets.is_empty():
		return ""
	return str(assets[int(lot.get("variant", 0)) % assets.size()])


# --- Save -----------------------------------------------------------------------------------------

func _key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


func _cell_from(key: Variant) -> Variant:
	if not key is String:
		return null
	var parts: PackedStringArray = (key as String).split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))


func to_dict() -> Dictionary:
	var zone_data: Dictionary = {}
	for c: Vector2i in zones:
		zone_data[_key(c)] = zones[c]
	var road_data: Array = []
	for c: Vector2i in roads:
		road_data.append(_key(c))
	var paved_data: Array = []
	for c: Vector2i in paved:
		paved_data.append(_key(c))
	var lot_data: Dictionary = {}
	for c: Vector2i in lots:
		var lot: Dictionary = lots[c]
		lot_data[_key(c)] = {"zone": lot["zone"], "level": lot["level"], "build": lot["build"],
			"progress": lot["progress"], "variant": lot["variant"], "age": lot["age"]}
	var village_data: Dictionary = {}
	for c: Vector2i in village:
		village_data[_key(c)] = village[c]
	return {"version": VERSION, "elapsed": elapsed, "grow": grow_clock, "income": income_clock,
		"zones": zone_data, "roads": road_data, "paved": paved_data, "lots": lot_data, "rng": str(rng.state),
		"tier": best_tier, "village": village_data}


# Loads a save. Anything malformed is refused whole, leaving the town as it was.
func from_dict(data: Variant) -> bool:
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return false
	var new_zones: Dictionary = {}
	var new_roads: Dictionary = {}
	var new_lots: Dictionary = {}
	var zone_data: Variant = data.get("zones", {})
	var road_data: Variant = data.get("roads", [])
	var lot_data: Variant = data.get("lots", {})
	var paved_data: Variant = data.get("paved", [])
	if not zone_data is Dictionary or not road_data is Array or not lot_data is Dictionary or not paved_data is Array:
		return false
	var new_paved: Dictionary = {}
	var village_data: Variant = data.get("village", {})
	if not village_data is Dictionary:
		return false
	var new_village: Dictionary = {}
	for key: Variant in village_data:
		var c: Variant = _cell_from(key)
		if c == null or str(village_data[key]) not in village_zone_ids():
			return false
		if in_village(c):
			new_village[c] = str(village_data[key])
	for key: Variant in zone_data:
		var c: Variant = _cell_from(key)
		if c == null or zone_spec(str(zone_data[key])).is_empty():
			return false
		new_zones[c] = str(zone_data[key])
	for key: Variant in road_data:
		var c: Variant = _cell_from(key)
		if c == null:
			return false
		new_roads[c] = true
		new_zones.erase(c)
	for key: Variant in paved_data:
		var c: Variant = _cell_from(key)
		if c == null:
			return false
		if new_roads.has(c):
			new_paved[c] = true
	for key: Variant in lot_data:
		var c: Variant = _cell_from(key)
		var raw: Variant = lot_data[key]
		if c == null or not raw is Dictionary or zone_spec(str(raw.get("zone", ""))).is_empty():
			return false
		var zone: String = str(raw["zone"])
		for field: String in ["level", "build", "progress", "variant", "age"]:
			var value: Variant = raw.get(field, 0)
			if not (value is int or value is float) or not is_finite(float(value)):
				return false
		new_lots[c] = {"zone": zone, "level": clampi(int(raw.get("level", 1)), 1, max_level(zone)),
			"build": maxf(float(raw.get("build", 0.0)), 0.0), "progress": maxf(float(raw.get("progress", 0.0)), 0.0),
			"variant": absi(int(raw.get("variant", 0))), "age": float(raw.get("age", 0.0))}
	zones = new_zones
	roads = new_roads
	paved = new_paved
	lots = new_lots
	village = new_village
	var tier: Variant = data.get("tier", null)
	best_tier = clampi(int(tier), 0, titles().size() - 1) if (tier is int or tier is float) and is_finite(float(tier)) else -1
	elapsed = maxf(float(data.get("elapsed", 0.0)), 0.0)
	grow_clock = maxf(float(data.get("grow", 0.0)), 0.0)
	income_clock = maxf(float(data.get("income", 0.0)), 0.0)
	if data.get("rng", null) is String and str(data["rng"]).is_valid_int():
		rng.state = int(str(data["rng"]))
	revision += 1
	return true
