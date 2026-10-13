extends RefCounted

# The Realm (data only): the open world around the manor, in the spirit of a WorldBox-style sandbox.
#
# The home village stays exactly where it was, at the centre of a 512 m (256 x 256 tile) square of
# rolling hills, woods and one winding river with bridges and fishing spots. Every bit of dry land is
# buildable; slopes get stilts. Five rival settlements sit out in the realm. Each one has a population that
# grows over active play time, and every settlement claims the land around it. Where two claims
# overlap the stronger claim (radius minus distance) wins the ground, which is how borders move when
# a neighbour grows: the groundwork for taking land and fighting neighbours.
#
# Nothing here draws anything or touches the village simulation or its save. The realm layer
# (village_realm.gd) renders it, and its own small save lives beside the village save.
#
# Phone budget: the world is sized for streaming. Terrain is one low-poly mesh, trees are built per
# 64 m chunk only near the camera, and rival settlements are simulated as numbers (population,
# claim radius); only the one or two nearest the camera get models and walking people.

const VERSION: int = 2                    # v1 saves (growth only) still load
const HALF: float = 256.0                 # metres from the centre to the realm edge
const TILE: float = 2.0
const REALM_TILES: int = 256              # 512 m / 2 m tiles per side
const TREE_CHUNK: float = 64.0            # tree streaming cell, metres
const BASE_Y: float = -0.58               # just under the outskirts slab top (-0.55)
const WATER_Y: float = -1.3
const HOME_CALM: Vector2 = Vector2(62.0, 100.0)   # hills fade in between these distances from home
const SCENERY_CLEAR: Vector2 = Vector2(52.0, 48.0)  # the existing outskirts trees fill this box
const EDGE_DROP_FROM: float = 236.0         # playable ground ends about here (camera pan limit)
# Past the realm's edge the land runs on to the horizon: foothills rise into a ring of mountains
# (scenery only), with the river's valley cutting through them, so the realm never ends in a cliff.
const OUTER_HALF: float = 720.0            # the scenery ring reaches this far from the centre
const FOOTHILLS_FROM: float = 250.0
const MOUNTAIN_HEIGHT: float = 60.0
const HILL_HEIGHT: float = 12.5           # rolling hills; slopes stay gentle enough to build on
const KNOLL_HEIGHT: float = 1.1          # small ridges and knolls over the hills
const SITE_CORE: float = 16.0             # a settlement's streets (trees and outposts keep clear)
const SITE_RIVER_CLEAR: float = 36.0      # settlements keep their streets this far from the river
# The river: one winding river crosses the whole realm (the only water apart from the sea at the
# edge). It keeps RIVER_CLEAR from home so the village is never flooded, and its banks are a
# straight slope one terrain cell wide or more, so the shoreline stays smooth on phones' 8 m grid.
const RIVER_CLEAR: float = 74.0           # closest the river line comes to the manor
const RIVER_HALF: float = 3.0             # flat bed either side of the line
const RIVER_BANK: float = 8.0             # bed up to the bank top
const RIVER_VALLEY: float = 44.0          # the valley floor rises into the hills over this
const RIVER_STEP: float = 4.0
const RIVER_WIGGLE: Vector2 = Vector2(18.0, 7.0)  # the two meanders' amplitudes, metres
const BRIDGE_WIDTH: float = 2.4
const FISH_MAX: int = 8
const FISH_SECONDS: float = 60.0          # active seconds per catch
const FISH_FOOD: int = 6                  # Food per catch from each spot on the manor's land
const HOME_COLOR := Color("d4b275")
const HOME_CLAIM_BASE: float = 52.0
const HOME_CLAIM_PER_PLOT: float = 8.0
const GROWTH_SECONDS: float = 75.0        # active seconds per new settler
const POP_CAP: int = 40
# Neighbours: relations drift with border pressure and what the manor does.
const RELATION_START: float = 50.0
const FRIENDLY_AT: float = 65.0
const HOSTILE_BELOW: float = 35.0
const PRESSURE_PER_SECOND: float = 0.05   # touching borders sour a neighbour by about 3 a minute
const DRIFT_PER_SECOND: float = 0.02      # apart, relations ease back toward the start
const HOSTILE_GROWTH: float = 1.5         # hostile neighbours spread faster
const TRADER_SECONDS: float = 90.0        # a friendly neighbour sends a trader this often
const SCOUT_SECONDS: float = 70.0         # a hostile one sends a scout
const TRADER_GIFT: Dictionary = {"gold": 10}
const GIFT_COST: Dictionary = {"gold": 40}
const GIFT_RELATION: float = 20.0
# Outposts: the manor's way to take land.
const OUTPOST_RADIUS: float = 26.0
const OUTPOST_REACH: float = 36.0         # how far past the manor's land a new outpost may stand
const OUTPOST_MAX: int = 6
const OUTPOST_COST: Dictionary = {"wood": 120, "gold": 60}
const OUTPOST_SITE_CLEAR: float = 24.0    # never inside a settlement's own streets
const OUTPOST_OVERRUN: float = 10.0       # a hostile claim this far past an outpost takes it
# Raids: the manor's fighters march out and fight a neighbour.
const RAID_COST: Dictionary = {"food": 20, "gold": 10}
const RAID_MIN_FIGHTERS: int = 2
const RAID_COOLDOWN: float = 120.0
const MARCH_SPEED: float = 4.0            # m/s, start at the village edge
const RAID_RELATION: float = 25.0         # starting a raid sours the target
const RAID_LOSS_RELATION: float = 15.0
const VASSAL_POP: int = 5                 # a beaten settlement this small submits

const FACTIONS: Array = [
	{"id": "ashfen", "name": "Ashfen Hollow", "color": "b0543a"},
	{"id": "briar", "name": "Briarwatch", "color": "7c9a3c"},
	{"id": "cinder", "name": "Cinderholt", "color": "d08a2e"},
	{"id": "gallow", "name": "Gallowmere", "color": "7a64b0"},
	{"id": "thorn", "name": "Thornvale", "color": "3f8a99"},
]

const BIOME_COLORS: Dictionary = {
	"meadow": Color("5f6b33"),
	"wheat": Color("8f7d3c"),
	"forest": Color("3f4a26"),
	"rocky": Color("6d6857"),
	"shore": Color("7d745a"),
	"water": Color("2c3a3e"),
}

var seed_value: int = 7
var elapsed: float = 0.0
var revision: int = 0                     # bumps when any claim radius changes
var home_plots: int = 0
var settlements: Array[Dictionary] = []  # {id, name, color, centre: Vector2, ground: float, pop, growth,
                                          #  relation, vassal, cooldown, travel}
var outposts: Array[Dictionary] = []     # {id, pos: Vector2}
var raid: Dictionary = {}                # {site, strength, left, total, start: Vector2} while marching
var events: Array[Dictionary] = []       # for the realm layer: take_events() drains them
var bridges: Array[Dictionary] = []      # {pos: Vector2, dir: Vector2, length: float}
var fishing_spots: Array[Dictionary] = []  # {id, pos: Vector2 (bank end of the jetty), dir: Vector2 (toward the water)}
var fish_clock: float = 0.0
var _next_outpost: int = 1
var _elev := FastNoiseLite.new()
var _moist := FastNoiseLite.new()
var _river_axis: Vector2 = Vector2.RIGHT  # the river runs along this, meandering across it
var _river_from: float = 0.0              # along-axis position of the first river sample
var _river_line := PackedFloat32Array()   # across-axis offset of the river line every RIVER_STEP


func generate(new_seed: int) -> void:
	seed_value = new_seed
	elapsed = 0.0
	_setup_noise()
	settlements.clear()
	outposts.clear()
	raid = {}
	events.clear()
	_next_outpost = 1
	fish_clock = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed * 7919 + 13
	_setup_river(rng)
	var turn: float = rng.randf_range(0.0, TAU)
	for index in FACTIONS.size():
		var faction: Dictionary = FACTIONS[index]
		var angle: float = turn + TAU * float(index) / float(FACTIONS.size()) + rng.randf_range(-0.25, 0.25)
		# The nearest neighbour is close enough to spot from home when zoomed out; the rest are farther.
		var distance: float = 92.0 + float((index * 3) % FACTIONS.size()) * 26.0 + rng.randf_range(0.0, 10.0)
		var centre: Vector2 = _dry_spot(angle, distance)
		settlements.append({
			"id": faction["id"], "name": faction["name"], "color": Color(faction["color"]),
			"centre": centre, "ground": maxf(_raw_height(centre.x, centre.y), 0.25),
			"pop": 6 + rng.randi_range(0, 8), "growth": 0.0,
			"relation": RELATION_START + rng.randf_range(-8.0, 8.0), "vassal": false, "cooldown": 0.0,
			"travel": rng.randf_range(0.0, 40.0),
		})
	_place_bridges()
	_place_fishing_spots()
	revision += 1


func _setup_noise() -> void:
	_elev.noise_type = FastNoiseLite.TYPE_PERLIN
	_elev.seed = seed_value
	_elev.frequency = 0.006
	_elev.fractal_type = FastNoiseLite.FRACTAL_FBM
	_elev.fractal_octaves = 3
	_moist.noise_type = FastNoiseLite.TYPE_PERLIN
	_moist.seed = seed_value + 101
	_moist.frequency = 0.012
	_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moist.fractal_octaves = 2


# Walks outward along a bearing until the ground is dry and inside the realm.
func _dry_spot(angle: float, distance: float) -> Vector2:
	var direction := Vector2(cos(angle), sin(angle))
	var best: Vector2 = direction * distance
	for step in 12:
		var spot: Vector2 = direction * (distance + float(step) * 8.0)
		if absf(spot.x) > HALF - 40.0 or absf(spot.y) > HALF - 40.0:
			break
		if _raw_height(spot.x, spot.y) > 0.25 and river_distance(spot.x, spot.y) > SITE_RIVER_CLEAR:
			return spot
		best = spot
	return best


# --- Ground -------------------------------------------------------------------------------------

# Rolling hills with flat meadows between them, never below the waterline: every bit of dry land
# can take a building (slopes get stilts). Calm near home so the village diorama looks as before.
func _land_height(x: float, z: float) -> float:
	var t: float = _elev.get_noise_2d(x, z) + 0.12
	var hill: float = (t + sqrt(t * t + 0.004)) * 0.5   # a soft max(t, 0): meadows meet hills smoothly
	# Knolls and low ridges ride on the big hills (and rumple the meadows a little), so the land
	# reads as rolling country from above rather than a few smooth domes.
	var bump: float = _moist.get_noise_2d(x * 1.9 + 300.0, z * 1.9 - 170.0)
	var ridge: float = 1.0 - minf(bump * bump * 4.0, 1.0)   # rounded crests where the noise crosses zero
	var knolls: float = ridge * ridge * (0.6 + hill * 1.2) * KNOLL_HEIGHT
	var calm: float = smoothstep(HOME_CALM.x, HOME_CALM.y, Vector2(x, z).length())
	return (0.3 + hill * HILL_HEIGHT + knolls) * calm


# Woodland moisture in -1..1 (the same field that places the forests), for scenery placement.
func woodland(x: float, z: float) -> float:
	return _moist.get_noise_2d(x, z)


# Height above BASE_Y: the land, the river cut through it, and the drop to the sea at the edge.
func _raw_height(x: float, z: float) -> float:
	var h: float = _land_height(x, z)
	var d: float = river_distance(x, z)
	if d < RIVER_HALF + RIVER_BANK + RIVER_VALLEY:
		var water: float = WATER_Y - BASE_Y
		var bed: float = water - 0.9
		var bank: float = water + 0.5
		if d <= RIVER_HALF:
			h = bed
		elif d <= RIVER_HALF + RIVER_BANK:
			h = lerpf(bed, bank, (d - RIVER_HALF) / RIVER_BANK)
		else:
			h = lerpf(bank, maxf(h, bank), smoothstep(RIVER_HALF + RIVER_BANK, RIVER_HALF + RIVER_BANK + RIVER_VALLEY, d))
	var edge: float = maxf(absf(x), absf(z))
	if edge > FOOTHILLS_FROM:
		h += _mountains(x, z, edge, river_distance(x, z, 96.0))
	return h


# Scenery past the edge: a rise that grows with distance, rumpled into ridges and peaks, held
# low along the river so it leaves through a valley.
func _mountains(x: float, z: float, edge: float, river: float) -> float:
	var rise: float = smoothstep(FOOTHILLS_FROM - 10.0, FOOTHILLS_FROM + 170.0, edge)
	var ridges: float = 1.0 - absf(_elev.get_noise_2d(x * 0.55 + 911.0, z * 0.55 - 377.0))
	var peaks: float = 0.45 + ridges * ridges * 0.75 + _moist.get_noise_2d(x * 0.7, z * 0.7) * 0.25
	var valley: float = smoothstep(RIVER_HALF + RIVER_BANK + 6.0, 90.0, river)
	return rise * (0.35 + rise * 0.65) * MOUNTAIN_HEIGHT * peaks * valley + smoothstep(FOOTHILLS_FROM, FOOTHILLS_FROM + 60.0, edge) * 2.0 * valley


# World Y of the ground at (x, z), metres. Settlements are no longer levelled: their buildings
# stand on footings or stilts where the ground slopes.
func height_at(x: float, z: float) -> float:
	return BASE_Y + _raw_height(x, z)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_Y


# Where people walk: bridge decks over the river, otherwise the ground, wading at most knee deep.
func walk_height(x: float, z: float) -> float:
	var deck: float = bridge_deck_at(x, z)
	if not is_nan(deck):
		return deck
	return maxf(height_at(x, z), WATER_Y - 0.4)


func biome_at(x: float, z: float) -> String:
	var y: float = height_at(x, z)
	if y < WATER_Y:
		return "water"
	if y < WATER_Y + 0.3:
		return "shore"
	var m: float = _moist.get_noise_2d(x, z)
	if m > 0.18:
		return "forest"
	if _elev.get_noise_2d(x, z) > 0.42:
		return "rocky"
	if m < -0.22:
		return "wheat"
	return "meadow"


# Ground colour, blended rather than banded: meadow, wheat and woodland floor by moisture,
# sun-bleached hilltops, bare earth and stone on the steeper slopes, mud and sand down to the
# water, and a little patchiness so open country never reads as one flat wash. slope is
# rise over run, from the terrain normals.
func ground_color(x: float, z: float, slope: float = 0.0) -> Color:
	var y: float = height_at(x, z)
	if y < WATER_Y:
		return BIOME_COLORS["water"]
	var m: float = _moist.get_noise_2d(x, z)
	var colour: Color = BIOME_COLORS["meadow"]
	colour = colour.lerp(BIOME_COLORS["wheat"], 1.0 - smoothstep(-0.32, -0.12, m))
	colour = colour.lerp(BIOME_COLORS["forest"], smoothstep(0.08, 0.26, m))
	var h: float = y - BASE_Y
	colour = colour.lerp(Color("8c8452"), smoothstep(3.0, 10.0, h) * 0.4)
	var stony: float = smoothstep(0.14, 0.32, slope) * 0.65 + smoothstep(0.4, 0.58, _elev.get_noise_2d(x, z)) * 0.5
	colour = colour.lerp(BIOME_COLORS["rocky"], clampf(stony, 0.0, 0.8))
	var above: float = y - WATER_Y
	if above < 0.7:
		colour = colour.lerp(BIOME_COLORS["shore"], 1.0 - smoothstep(0.25, 0.7, above))
		colour = colour.lerp(Color("4a4130"), 1.0 - smoothstep(0.0, 0.22, above))
	var shade: float = _moist.get_noise_2d(x * 3.1, z * 3.1) * 0.06 + _elev.get_noise_2d(x * 7.3, z * 7.3) * 0.035
	return Color(colour.r + shade, colour.g + shade, colour.b + shade * 0.6)


# --- River --------------------------------------------------------------------------------------

# The river line in its own frame: along the axis it crosses the realm; across it, two meanders
# add up around an offset that keeps it RIVER_CLEAR from the manor at its closest.
func _setup_river(rng: RandomNumberGenerator) -> void:
	_river_axis = Vector2.from_angle(rng.randf_range(0.0, TAU))
	var side: float = -1.0 if rng.randf() < 0.5 else 1.0
	var offset: float = side * (RIVER_CLEAR + RIVER_WIGGLE.x + RIVER_WIGGLE.y)
	var wave_a: float = TAU / rng.randf_range(190.0, 240.0)
	var wave_b: float = TAU / rng.randf_range(70.0, 95.0)
	var phase_a: float = rng.randf_range(0.0, TAU)
	var phase_b: float = rng.randf_range(0.0, TAU)
	var reach: float = OUTER_HALF * 1.45   # the river runs on through the scenery ring
	_river_from = -reach
	var count: int = int(reach * 2.0 / RIVER_STEP) + 1
	_river_line.resize(count)
	for index in count:
		var along: float = _river_from + float(index) * RIVER_STEP
		_river_line[index] = offset + sin(along * wave_a + phase_a) * RIVER_WIGGLE.x + sin(along * wave_b + phase_b) * RIVER_WIGGLE.y
	# A meander leaning toward home can bring the line closer than its offset; push it back out.
	for attempt in 6:
		var closest: float = river_distance(0.0, 0.0)
		if closest >= RIVER_CLEAR:
			break
		for index in count:
			_river_line[index] += side * (RIVER_CLEAR - closest + 1.0)


func _river_frame(x: float, z: float) -> Vector2:
	var across := Vector2(-_river_axis.y, _river_axis.x)
	var p := Vector2(x, z)
	return Vector2(p.dot(_river_axis), p.dot(across))


func _river_world(along: float, across: float) -> Vector2:
	return _river_axis * along + Vector2(-_river_axis.y, _river_axis.x) * across


# Point on the river line at sample index (world metres).
func river_point(index: int) -> Vector2:
	index = clampi(index, 0, _river_line.size() - 1)
	return _river_world(_river_from + float(index) * RIVER_STEP, _river_line[index])


func river_samples() -> int:
	return _river_line.size()


# Metres from (x, z) to the river line. Far from the river a cheap bound answers without the
# segment search (the meanders never turn more than about 50 degrees off the axis).
func river_distance(x: float, z: float, limit: float = RIVER_HALF + RIVER_BANK + RIVER_VALLEY + 4.0) -> float:
	if _river_line.is_empty():
		return INF
	var f: Vector2 = _river_frame(x, z)
	var i: int = clampi(int(floor((f.x - _river_from) / RIVER_STEP)), 0, _river_line.size() - 2)
	var rough: float = absf(f.y - _river_line[i])
	if rough * 0.6 > limit:
		return rough * 0.6
	var span: int = ceili(minf(rough, limit) / RIVER_STEP) + 1
	var best: float = INF
	for k in range(maxi(i - span, 0), mini(i + span, _river_line.size() - 2) + 1):
		var a := Vector2(_river_from + float(k) * RIVER_STEP, _river_line[k])
		var b := Vector2(a.x + RIVER_STEP, _river_line[k + 1])
		var ab: Vector2 = b - a
		var t: float = clampf((f - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, f.distance_to(a + ab * t))
	return best


# Unit vector across the river at the line point nearest (x, z), pointing toward (x, z)'s side.
func river_side(x: float, z: float) -> Vector2:
	var f: Vector2 = _river_frame(x, z)
	var i: int = clampi(int(floor((f.x - _river_from) / RIVER_STEP)), 0, _river_line.size() - 2)
	var tangent := Vector2(RIVER_STEP, _river_line[i + 1] - _river_line[i]).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	if (f - Vector2(_river_from + float(i) * RIVER_STEP, _river_line[i])).dot(normal) < 0.0:
		normal = -normal
	return _river_world(normal.x, normal.y)


# Bridges carry the roads from the manor to each neighbour over the river, so traders, scouts and
# the warband cross dry-shod (anyone else wades). One bridge per crossing; near ones are shared.
func _place_bridges() -> void:
	bridges.clear()
	for site: Dictionary in settlements:
		var to: Vector2 = site["centre"]
		var from: Vector2 = to.normalized() * 40.0
		var heading: Vector2 = (to - from).normalized()
		var length: float = from.distance_to(to)
		var wet_from: float = -1.0
		var wet_to: float = -1.0
		var step: float = 0.5
		var along: float = 0.0
		while along <= length:
			var p: Vector2 = from + heading * along
			if height_at(p.x, p.y) < WATER_Y + 0.15:
				if wet_from < 0.0:
					wet_from = along
				wet_to = along
			elif wet_from >= 0.0:
				break
			along += step
		if wet_from < 0.0:
			continue
		var middle: Vector2 = from + heading * (wet_from + wet_to) * 0.5
		var shared: bool = false
		for bridge: Dictionary in bridges:
			if (bridge["pos"] as Vector2).distance_to(middle) < 24.0:
				shared = true
		if not shared:
			bridges.append({"pos": middle, "dir": heading, "length": wet_to - wet_from + 5.0})


# Deck height at (x, z), or NAN off every bridge. The deck arches a little over the water.
func bridge_deck_at(x: float, z: float) -> float:
	for bridge: Dictionary in bridges:
		var offset: Vector2 = Vector2(x, z) - (bridge["pos"] as Vector2)
		var dir: Vector2 = bridge["dir"]
		var along: float = offset.dot(dir)
		var half: float = float(bridge["length"]) * 0.5
		if absf(along) <= half and absf(offset.dot(Vector2(-dir.y, dir.x))) <= BRIDGE_WIDTH * 0.5:
			var t: float = along / half
			return WATER_Y + 0.5 + 0.45 * (1.0 - t * t)
	return NAN


# Fishing spots: little jetties along the banks, nearest the manor first, never at a bridge or in
# a neighbour's streets. Any on the manor's land feed it (see advance).
func _place_fishing_spots() -> void:
	fishing_spots.clear()
	var found: Array[Dictionary] = []
	var side: float = 1.0
	var index: int = 6
	while index < _river_line.size() - 6:
		var line: Vector2 = river_point(index)
		var tangent: Vector2 = (river_point(index + 1) - river_point(index - 1)).normalized()
		var normal: Vector2 = Vector2(-tangent.y, tangent.x) * side
		var pos: Vector2 = line + normal * (RIVER_HALF + RIVER_BANK * 0.82)
		index += 14
		side = -side
		if absf(pos.x) > HALF - 24.0 or absf(pos.y) > HALF - 24.0 or is_water(pos.x, pos.y):
			continue
		if _near_site(pos.x, pos.y, SITE_CORE + 8.0):
			continue
		var clear: bool = true
		for bridge: Dictionary in bridges:
			if (bridge["pos"] as Vector2).distance_to(pos) < 26.0:
				clear = false
		if clear:
			found.append({"pos": pos, "dir": -normal})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector2).length() < (b["pos"] as Vector2).length())
	for spot_index in mini(found.size(), FISH_MAX):
		var spot: Dictionary = found[spot_index]
		spot["id"] = spot_index + 1
		fishing_spots.append(spot)


func fishing_spot(id: int) -> Dictionary:
	for spot: Dictionary in fishing_spots:
		if int(spot["id"]) == id:
			return spot
	return {}


# Fishing spots on the manor's land right now (its village, outposts and sworn neighbours).
func home_fishing_spots() -> int:
	var all_claims: Array[Dictionary] = claims()
	var count: int = 0
	for spot: Dictionary in fishing_spots:
		var pos: Vector2 = spot["pos"]
		if _owner_from(all_claims, pos) == "home":
			count += 1
	return count


# Moves a point that ended up in the river (an old save's outpost) out to the nearest dry bank.
func dry_ground_near(pos: Vector2) -> Vector2:
	if not is_water(pos.x, pos.y):
		return pos
	var out: Vector2 = river_side(pos.x, pos.y)
	for step in 30:
		var spot: Vector2 = pos + out * float(step + 1)
		if not is_water(spot.x, spot.y):
			return spot + out * 2.0
	return pos


# --- Territory ----------------------------------------------------------------------------------

func home_radius() -> float:
	return HOME_CLAIM_BASE + HOME_CLAIM_PER_PLOT * float(home_plots)


func claim_radius(site: Dictionary) -> float:
	return 20.0 + sqrt(float(site["pop"])) * 5.5


# Every claim on the land: {owner, centre, radius}. The manor's village, its outposts and any
# settlement that has submitted all claim for "home".
func claims() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"owner": "home", "centre": Vector2.ZERO, "radius": home_radius()}]
	for outpost: Dictionary in outposts:
		result.append({"owner": "home", "centre": outpost["pos"], "radius": OUTPOST_RADIUS})
	for site: Dictionary in settlements:
		result.append({"owner": "home" if bool(site["vassal"]) else str(site["id"]), "centre": site["centre"], "radius": claim_radius(site)})
	return result


# "home", a settlement id, or "" for wild land. The strongest claim (radius minus distance) wins.
func owner_at(x: float, z: float) -> String:
	return _owner_from(claims(), Vector2(x, z))


func _owner_from(all_claims: Array[Dictionary], point: Vector2) -> String:
	var best: String = ""
	var best_margin: float = 0.0
	for claim: Dictionary in all_claims:
		var margin: float = float(claim["radius"]) - (claim["centre"] as Vector2).distance_to(point)
		if margin > best_margin:
			best = str(claim["owner"])
			best_margin = margin
	return best


# Faster owner lookups for many points (the ground repaint): claims are gathered once.
func owners_at(points: PackedVector3Array) -> Array[String]:
	var all_claims: Array[Dictionary] = claims()
	var result: Array[String] = []
	result.resize(points.size())
	for index in points.size():
		result[index] = _owner_from(all_claims, Vector2(points[index].x, points[index].z))
	return result


func owner_color(owner: String) -> Color:
	if owner == "home":
		return HOME_COLOR
	var site: Dictionary = settlement(owner)
	return site.get("color", Color.WHITE)


# --- Neighbours ---------------------------------------------------------------------------------

func attitude(site: Dictionary) -> String:
	if bool(site["vassal"]):
		return "sworn"
	if float(site["relation"]) >= FRIENDLY_AT:
		return "friendly"
	if float(site["relation"]) < HOSTILE_BELOW:
		return "hostile"
	return "wary"


func _touches_home(site: Dictionary) -> bool:
	var reach: float = claim_radius(site)
	for claim: Dictionary in claims():
		if claim["owner"] == "home" and (claim["centre"] as Vector2).distance_to(site["centre"]) < reach + float(claim["radius"]):
			return true
	return false


func _shift_relation(site: Dictionary, amount: float) -> void:
	var before: String = attitude(site)
	site["relation"] = clampf(float(site["relation"]) + amount, 0.0, 100.0)
	var after: String = attitude(site)
	if after != before:
		events.append({"kind": "attitude", "site": site["id"], "attitude": after})


# Gifts buy goodwill; the caller pays GIFT_COST first.
func send_gift(id: String) -> bool:
	var site: Dictionary = settlement(id)
	if site.is_empty() or bool(site["vassal"]):
		return false
	_shift_relation(site, GIFT_RELATION)
	return true


func take_events() -> Array[Dictionary]:
	var drained: Array[Dictionary] = events.duplicate()
	events.clear()
	return drained


# --- Outposts -----------------------------------------------------------------------------------

func outpost_reason(pos: Vector2) -> String:
	if outposts.size() >= OUTPOST_MAX:
		return "The manor can hold %d outposts." % OUTPOST_MAX
	if absf(pos.x) > HALF - 12.0 or absf(pos.y) > HALF - 12.0:
		return "Too close to the edge of the realm."
	if is_water(pos.x, pos.y):
		return "An outpost needs dry ground."
	if pos.length() < home_radius() * 0.6:
		return "The manor already holds this ground."
	for site: Dictionary in settlements:
		if (site["centre"] as Vector2).distance_to(pos) < OUTPOST_SITE_CLEAR:
			return "That is %s's own streets." % site["name"]
	var near_home: bool = false
	for claim: Dictionary in claims():
		if claim["owner"] == "home" and (claim["centre"] as Vector2).distance_to(pos) <= float(claim["radius"]) + OUTPOST_REACH:
			near_home = true
	if not near_home:
		return "Too far from the manor's land. Build outward step by step."
	return ""


# The caller pays OUTPOST_COST first.
func found_outpost(pos: Vector2) -> bool:
	if not outpost_reason(pos).is_empty():
		return false
	outposts.append({"id": _next_outpost, "pos": pos})
	_next_outpost += 1
	revision += 1
	# Planting a flag on someone's land is noticed.
	var holder: String = _owner_from(_site_claims(), pos)
	if holder != "":
		_shift_relation(settlement(holder), -10.0)
	return true


func _site_claims() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for site: Dictionary in settlements:
		if not bool(site["vassal"]):
			result.append({"owner": str(site["id"]), "centre": site["centre"], "radius": claim_radius(site)})
	return result


# --- Raids --------------------------------------------------------------------------------------

func raid_reason(id: String, fighters: int) -> String:
	var site: Dictionary = settlement(id)
	if site.is_empty():
		return "Unknown settlement."
	if bool(site["vassal"]):
		return "%s is already sworn to the manor." % site["name"]
	if not raid.is_empty():
		return "The warband is already marching."
	if float(site["cooldown"]) > 0.0:
		return "%s is still on guard (%ds)." % [site["name"], ceili(float(site["cooldown"]))]
	if fighters < RAID_MIN_FIGHTERS:
		return "Raise at least %d fighters first." % RAID_MIN_FIGHTERS
	return ""


# The caller pays RAID_COST first. strength is the warband's combined fighter levels.
func start_raid(id: String, fighters: int, strength: int) -> bool:
	if not raid_reason(id, fighters).is_empty():
		return false
	var site: Dictionary = settlement(id)
	var target: Vector2 = site["centre"]
	var start: Vector2 = target.normalized() * 40.0
	var total: float = maxf(start.distance_to(target) / MARCH_SPEED, 1.0)
	raid = {"site": id, "strength": strength, "fighters": fighters, "left": total, "total": total, "start": start}
	_shift_relation(site, -RAID_RELATION)
	return true


# 0 at the village edge .. 1 at the target.
func raid_progress() -> float:
	if raid.is_empty():
		return 0.0
	return clampf(1.0 - float(raid["left"]) / maxf(float(raid["total"]), 0.001), 0.0, 1.0)


func defence_of(site: Dictionary) -> float:
	return float(site["pop"]) * 1.6 + float(tier_of(site)) * 4.0


func _resolve_raid() -> void:
	var site: Dictionary = settlement(str(raid["site"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + int(elapsed * 10.0)
	var attack: float = float(raid["strength"]) * 4.0 * rng.randf_range(0.8, 1.25)
	var won: bool = attack > defence_of(site)
	site["cooldown"] = RAID_COOLDOWN
	if won:
		var lost: int = maxi(3, int(site["pop"]) / 4)
		var loot: Dictionary = {"gold": 25 + int(site["pop"]) * 3, "food": 15 + int(site["pop"]) * 2}
		site["pop"] = maxi(1, int(site["pop"]) - lost)
		var sworn: bool = int(site["pop"]) <= VASSAL_POP
		if sworn:
			site["vassal"] = true
			site["relation"] = RELATION_START
		events.append({"kind": "raid_won", "site": site["id"], "loot": loot, "sworn": sworn})
		revision += 1
	else:
		_shift_relation(site, -RAID_LOSS_RELATION)
		events.append({"kind": "raid_lost", "site": site["id"]})
	raid = {}


func settlement(id: String) -> Dictionary:
	for site: Dictionary in settlements:
		if site["id"] == id:
			return site
	return {}


func set_home_plots(count: int) -> void:
	if count != home_plots:
		home_plots = count
		revision += 1


# --- Growth -------------------------------------------------------------------------------------

# Active time only: the caller skips this while the village is paused. Returns true when borders moved.
func advance(seconds: float) -> bool:
	elapsed += seconds
	var moved: bool = false
	for site: Dictionary in settlements:
		site["cooldown"] = maxf(0.0, float(site["cooldown"]) - seconds)
		if not bool(site["vassal"]):
			if _touches_home(site):
				_shift_relation(site, -PRESSURE_PER_SECOND * seconds)
			else:
				var gap: float = RELATION_START - float(site["relation"])
				_shift_relation(site, clampf(gap, -DRIFT_PER_SECOND * seconds, DRIFT_PER_SECOND * seconds))
			var mood: String = attitude(site)
			site["travel"] = float(site["travel"]) + seconds
			if mood == "friendly" and float(site["travel"]) >= TRADER_SECONDS:
				site["travel"] = 0.0
				events.append({"kind": "trader", "site": site["id"]})
			elif mood == "hostile" and float(site["travel"]) >= SCOUT_SECONDS:
				site["travel"] = 0.0
				events.append({"kind": "scout", "site": site["id"]})
		if int(site["pop"]) >= POP_CAP:
			continue
		var rate: float = HOSTILE_GROWTH if attitude(site) == "hostile" else 1.0
		site["growth"] = float(site["growth"]) + seconds * rate
		while float(site["growth"]) >= GROWTH_SECONDS and int(site["pop"]) < POP_CAP:
			site["growth"] = float(site["growth"]) - GROWTH_SECONDS
			site["pop"] = int(site["pop"]) + 1
			moved = true
	# A hostile neighbour whose land swallows an outpost takes it.
	for index in range(outposts.size() - 1, -1, -1):
		var pos: Vector2 = outposts[index]["pos"]
		for site: Dictionary in settlements:
			if attitude(site) == "hostile" and claim_radius(site) - (site["centre"] as Vector2).distance_to(pos) > OUTPOST_OVERRUN:
				events.append({"kind": "outpost_lost", "site": site["id"], "outpost": outposts[index]["id"]})
				outposts.remove_at(index)
				moved = true
				break
	# Fishers on the manor's banks land a catch every FISH_SECONDS of active play.
	fish_clock += seconds
	if fish_clock >= FISH_SECONDS:
		fish_clock -= FISH_SECONDS
		var spots: int = home_fishing_spots()
		if spots > 0:
			events.append({"kind": "catch", "spots": spots, "loot": {"food": spots * FISH_FOOD}})
	if not raid.is_empty():
		raid["left"] = float(raid["left"]) - seconds
		if float(raid["left"]) <= 0.0:
			_resolve_raid()
			moved = true
	if moved:
		revision += 1
	return moved


# Settlement tier follows its population, like the home village's building tiers.
func tier_of(site: Dictionary) -> int:
	return clampi(1 + int(site["pop"]) / 12, 1, 3)


# Where each building of a settlement stands: {type, pos: Vector2, facing: float, size: int}.
# More people means more cottages, so a growing neighbour visibly spreads out.
func layout(site: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var centre: Vector2 = site["centre"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(site["id"])) + seed_value
	result.append({"type": "manor_hall", "pos": centre, "facing": rng.randf_range(0.0, TAU), "size": 2})
	var cottages: int = clampi(2 + int(site["pop"]) / 5, 2, 9)
	var turn: float = rng.randf_range(0.0, TAU)
	for index in cottages:
		var angle: float = turn + TAU * float(index) / float(cottages) + rng.randf_range(-0.15, 0.15)
		var ring: float = 8.0 + float(index % 2) * 3.5 + rng.randf_range(-0.5, 0.5)
		var spot: Vector2 = centre + Vector2(cos(angle), sin(angle)) * ring
		result.append({"type": "cottage", "pos": spot, "facing": angle + PI * 0.5, "size": 2})
	var extras: Array = ["farm", "tower", "storehouse", "farm", "market"]
	var extra_count: int = clampi(1 + int(site["pop"]) / 10, 1, extras.size())
	for index in extra_count:
		var angle: float = turn + PI / float(cottages) + TAU * float(index) / float(extra_count)
		var spot: Vector2 = centre + Vector2(cos(angle), sin(angle)) * (15.0 + rng.randf_range(0.0, 2.0))
		result.append({"type": extras[index], "pos": spot, "facing": angle, "size": 1 if extras[index] == "tower" else 2})
	return result


# --- Trees --------------------------------------------------------------------------------------

func chunk_count() -> int:
	return int(HALF * 2.0 / TREE_CHUNK)


func chunk_of(x: float, z: float) -> Vector2i:
	var last: int = chunk_count() - 1
	return Vector2i(clampi(floori((x + HALF) / TREE_CHUNK), 0, last), clampi(floori((z + HALF) / TREE_CHUNK), 0, last))


func chunk_centre(chunk: Vector2i) -> Vector2:
	return Vector2((float(chunk.x) + 0.5) * TREE_CHUNK - HALF, (float(chunk.y) + 0.5) * TREE_CHUNK - HALF)


# Deterministic trees for one chunk: [{pos: Vector3, scale, turn, round: bool, kind, tone: int}].
# kind: 0 pine, 1 round tree, 2 reeds at the water's edge, 3 boulder, 4 meadow bush, 5 poplar.
# density < 1 thins them for phones. Trees never land on water, near settlements or over the
# outskirts box that already has its own hand-placed trees.
func trees_in_chunk(chunk: Vector2i, density: float = 1.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 92821 + chunk.x * 4099 + chunk.y * 131
	var step: float = 4.0
	var cells: int = int(TREE_CHUNK / step)
	var corner: Vector2 = chunk_centre(chunk) - Vector2.ONE * TREE_CHUNK * 0.5
	for gz in cells:
		for gx in cells:
			var x: float = corner.x + (float(gx) + rng.randf_range(0.1, 0.9)) * step
			var z: float = corner.y + (float(gz) + rng.randf_range(0.1, 0.9)) * step
			var roll: float = rng.randf()
			var shape: float = rng.randf()
			var size: float = rng.randf_range(0.85, 1.6)
			var turn: float = rng.randf_range(0.0, TAU)
			var tone: int = rng.randi() % 9
			if absf(x) < SCENERY_CLEAR.x and absf(z) < SCENERY_CLEAR.y:
				continue
			if _near_site(x, z, SITE_CORE + 4.0):
				continue
			var biome: String = biome_at(x, z)
			if biome == "water":
				continue
			var y: float = height_at(x, z)
			# Reeds crowd the river's edge; boulders sit on the stony hills.
			if y < WATER_Y + 0.45:
				if roll < 0.55 * density:
					result.append({"pos": Vector3(x, y, z), "scale": size * 0.8, "turn": turn, "round": false, "kind": 2, "tone": tone})
				continue
			var chance: float = {"forest": 0.7, "meadow": 0.05, "wheat": 0.02, "rocky": 0.08}.get(biome, 0.0) * density
			if roll >= chance:
				if biome == "rocky" and roll < chance + 0.05 * density:
					result.append({"pos": Vector3(x, y, z), "scale": size * 0.9, "turn": turn, "round": false, "kind": 3, "tone": tone})
				elif biome in ["meadow", "wheat"] and roll < chance + 0.03 * density:
					result.append({"pos": Vector3(x, y, z), "scale": size * 0.85, "turn": turn, "round": false, "kind": 4, "tone": tone})
				continue
			# Kinds: 0 pine, 1 round broadleaf, 5 slim poplar (2 reeds, 3 boulder, 4 bush above).
			var kind: int = 1 if shape < 0.45 else (5 if shape < 0.55 else 0)
			result.append({"pos": Vector3(x, y, z), "scale": size, "turn": turn, "round": kind == 1, "kind": kind, "tone": tone})
	return result


func _near_site(x: float, z: float, reach: float) -> bool:
	for site: Dictionary in settlements:
		if (site["centre"] as Vector2).distance_to(Vector2(x, z)) < reach:
			return true
	return false


# --- Save ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var sites: Array = []
	for site: Dictionary in settlements:
		sites.append({"id": site["id"], "pop": int(site["pop"]), "growth": float(site["growth"]),
			"relation": float(site["relation"]), "vassal": bool(site["vassal"]), "cooldown": float(site["cooldown"]),
			"travel": float(site["travel"])})
	var posts: Array = []
	for outpost: Dictionary in outposts:
		posts.append({"id": int(outpost["id"]), "x": (outpost["pos"] as Vector2).x, "z": (outpost["pos"] as Vector2).y})
	var march: Dictionary = {}
	if not raid.is_empty():
		march = {"site": raid["site"], "strength": int(raid["strength"]), "fighters": int(raid["fighters"]),
			"left": float(raid["left"]), "total": float(raid["total"]),
			"x": (raid["start"] as Vector2).x, "z": (raid["start"] as Vector2).y}
	return {"version": VERSION, "seed": seed_value, "elapsed": elapsed, "settlements": sites, "outposts": posts, "raid": march, "fish_clock": fish_clock}


# Regenerates the world from its seed, then restores each settlement's growth. Returns false and
# leaves a fresh realm for anything malformed.
func from_dict(data: Variant) -> bool:
	if not data is Dictionary or int((data as Dictionary).get("version", 0)) not in [1, VERSION]:
		return false
	var seed_read: Variant = data.get("seed")
	if not (seed_read is float or seed_read is int):
		return false
	generate(int(seed_read))
	elapsed = maxf(0.0, float(data.get("elapsed", 0.0)))
	fish_clock = clampf(float(data.get("fish_clock", 0.0)), 0.0, FISH_SECONDS)
	var saved: Variant = data.get("settlements", [])
	if not saved is Array:
		return false
	for entry: Variant in saved:
		if not entry is Dictionary:
			continue
		var site: Dictionary = settlement(str(entry.get("id", "")))
		if site.is_empty():
			continue
		site["pop"] = clampi(int(entry.get("pop", site["pop"])), 1, POP_CAP)
		site["growth"] = clampf(float(entry.get("growth", 0.0)), 0.0, GROWTH_SECONDS)
		site["relation"] = clampf(float(entry.get("relation", site["relation"])), 0.0, 100.0)
		site["vassal"] = bool(entry.get("vassal", false))
		site["cooldown"] = clampf(float(entry.get("cooldown", 0.0)), 0.0, RAID_COOLDOWN)
		site["travel"] = clampf(float(entry.get("travel", 0.0)), 0.0, maxf(TRADER_SECONDS, SCOUT_SECONDS))
	var posts: Variant = data.get("outposts", [])
	if posts is Array:
		for entry: Variant in posts:
			if entry is Dictionary and outposts.size() < OUTPOST_MAX:
				var pos := Vector2(float(entry.get("x", 0.0)), float(entry.get("z", 0.0)))
				if absf(pos.x) <= HALF and absf(pos.y) <= HALF:
					pos = dry_ground_near(pos)   # saves from before the river: never leave one in it
					var id: int = int(entry.get("id", _next_outpost))
					outposts.append({"id": id, "pos": pos})
					_next_outpost = maxi(_next_outpost, id + 1)
	var march: Variant = data.get("raid", {})
	if march is Dictionary and not (march as Dictionary).is_empty() and not settlement(str(march.get("site", ""))).is_empty():
		var total: float = maxf(float(march.get("total", 1.0)), 1.0)
		raid = {"site": str(march["site"]), "strength": maxi(0, int(march.get("strength", 0))), "fighters": maxi(0, int(march.get("fighters", 0))),
			"left": clampf(float(march.get("left", 0.0)), 0.0, total), "total": total,
			"start": Vector2(float(march.get("x", 0.0)), float(march.get("z", 0.0)))}
	revision += 1
	return true
