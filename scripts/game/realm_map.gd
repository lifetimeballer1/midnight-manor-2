extends RefCounted

# The Realm (data only): the open world around the manor, in the spirit of a WorldBox-style sandbox.
#
# The home village stays exactly where it was, at the centre of a 512 m (256 x 256 tile) square of
# hills, woods and lakes. Five rival settlements sit out in the realm. Each one has a population that
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
const EDGE_DROP_FROM: float = 236.0
const HILL_HEIGHT: float = 4.5
const SITE_CORE: float = 16.0             # flattened ground around a settlement centre
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
var _next_outpost: int = 1
var _elev := FastNoiseLite.new()
var _moist := FastNoiseLite.new()


func generate(new_seed: int) -> void:
	seed_value = new_seed
	elapsed = 0.0
	_setup_noise()
	settlements.clear()
	outposts.clear()
	raid = {}
	events.clear()
	_next_outpost = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed * 7919 + 13
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
		if _raw_height(spot.x, spot.y) > 0.25:
			return spot
		best = spot
	return best


# --- Ground -------------------------------------------------------------------------------------

# Height above BASE_Y before settlements flatten it.
func _raw_height(x: float, z: float) -> float:
	var n: float = _elev.get_noise_2d(x, z)
	var calm: float = smoothstep(HOME_CALM.x, HOME_CALM.y, Vector2(x, z).length())
	var h: float = (n + 0.25) * HILL_HEIGHT * calm
	var edge: float = maxf(absf(x), absf(z))
	if edge > EDGE_DROP_FROM:
		h -= (edge - EDGE_DROP_FROM) * 0.3
	return h


# World Y of the ground at (x, z), metres.
func height_at(x: float, z: float) -> float:
	var h: float = _raw_height(x, z)
	for site: Dictionary in settlements:
		var reach: float = (site["centre"] as Vector2).distance_to(Vector2(x, z))
		if reach < SITE_CORE + 16.0:
			h = lerpf(float(site["ground"]), h, smoothstep(SITE_CORE, SITE_CORE + 16.0, reach))
	return BASE_Y + h


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_Y


func biome_at(x: float, z: float) -> String:
	var y: float = height_at(x, z)
	if y < WATER_Y:
		return "water"
	if y < WATER_Y + 0.25:
		return "shore"
	var m: float = _moist.get_noise_2d(x, z)
	if m > 0.18:
		return "forest"
	if _elev.get_noise_2d(x, z) > 0.42:
		return "rocky"
	if m < -0.22:
		return "wheat"
	return "meadow"


func ground_color(x: float, z: float) -> Color:
	var colour: Color = BIOME_COLORS[biome_at(x, z)]
	var shade: float = _moist.get_noise_2d(x * 3.1, z * 3.1) * 0.06
	return Color(colour.r + shade, colour.g + shade, colour.b + shade * 0.6)


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


# Deterministic trees for one chunk: [{pos: Vector3, scale, turn, round: bool, tone: int}].
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
			var biome: String = biome_at(x, z)
			var chance: float = {"forest": 0.7, "meadow": 0.05, "wheat": 0.02, "rocky": 0.08}.get(biome, 0.0) * density
			if roll >= chance or _near_site(x, z, SITE_CORE + 4.0):
				continue
			result.append({"pos": Vector3(x, height_at(x, z), z), "scale": size, "turn": turn, "round": shape < 0.45, "tone": tone})
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
	return {"version": VERSION, "seed": seed_value, "elapsed": elapsed, "settlements": sites, "outposts": posts, "raid": march}


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
