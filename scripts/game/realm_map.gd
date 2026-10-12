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

const VERSION: int = 1
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
var settlements: Array[Dictionary] = []  # {id, name, color, centre: Vector2, ground: float, pop, growth}
var _elev := FastNoiseLite.new()
var _moist := FastNoiseLite.new()


func generate(new_seed: int) -> void:
	seed_value = new_seed
	elapsed = 0.0
	_setup_noise()
	settlements.clear()
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


# "home", a settlement id, or "" for wild land. The strongest claim (radius minus distance) wins.
func owner_at(x: float, z: float) -> String:
	var point := Vector2(x, z)
	var best: String = ""
	var best_margin: float = 0.0
	var home_margin: float = home_radius() - point.length()
	if home_margin > best_margin:
		best = "home"
		best_margin = home_margin
	for site: Dictionary in settlements:
		var margin: float = claim_radius(site) - (site["centre"] as Vector2).distance_to(point)
		if margin > best_margin:
			best = str(site["id"])
			best_margin = margin
	return best


func owner_color(owner: String) -> Color:
	if owner == "home":
		return HOME_COLOR
	var site: Dictionary = settlement(owner)
	return site.get("color", Color.WHITE)


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
		if int(site["pop"]) >= POP_CAP:
			continue
		site["growth"] = float(site["growth"]) + seconds
		while float(site["growth"]) >= GROWTH_SECONDS and int(site["pop"]) < POP_CAP:
			site["growth"] = float(site["growth"]) - GROWTH_SECONDS
			site["pop"] = int(site["pop"]) + 1
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
		sites.append({"id": site["id"], "pop": int(site["pop"]), "growth": float(site["growth"])})
	return {"version": VERSION, "seed": seed_value, "elapsed": elapsed, "settlements": sites}


# Regenerates the world from its seed, then restores each settlement's growth. Returns false and
# leaves a fresh realm for anything malformed.
func from_dict(data: Variant) -> bool:
	if not data is Dictionary or int((data as Dictionary).get("version", 0)) != VERSION:
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
	revision += 1
	return true
