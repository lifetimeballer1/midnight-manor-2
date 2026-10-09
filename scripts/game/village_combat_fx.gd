extends "res://scripts/game/village_haunt.gd"

# Combat flourishes, layered over the haunt look. A raider that rises into a home raid
# puffs out a short burst of dark violet smoke tinted by its faction, but only for raiders
# that appear after the raid's first frame: the raiders already present when a raid
# starts, and anyone restored from a save, are recorded silently. Each shot throws a
# four-spark muzzle flash at the shooter's height, and a friendly unit struck in combat
# gives the camera a small jolt, far lighter than a broken building, with its own cap.
# The simulation, the save data and the game's own event handling are untouched: this
# layer only reads the sim, shares the decoration budget and feeds the existing burst pool.

const RAIDER_SMOKE: Color = Color(0.26, 0.14, 0.36)   # dark violet, mixed toward the faction colour
const SMOKE_MIX: float = 0.3
const SMOKE_COUNT: int = 10
const SMOKE_SIZE: float = 1.3
const SMOKE_HEIGHT: float = 0.6
const MUZZLE_COUNT: int = 4
const MUZZLE_SIZE: float = 0.45
const MUZZLE_HEIGHT: float = 1.8
const FRIENDLY_JOLT: float = 0.18                      # against BREAK_JOLT of 1.0 in the parent
const FRIENDLY_SHAKE_CAP: float = 0.45                 # friendly hits never push the shake past this

var _known_raiders: Dictionary = {}                    # enemy id -> true, for the current raid
var _raid_primed: bool = false                         # false until the first raid frame has been seeded
var _fx_sim: Object = null                             # sim the known set belongs to; a new sim reseeds


func _update_actors(delta: float) -> void:
	super(delta)
	_burst_new_raiders()


# Reads this frame's events before the parent consumes them, because the parent removes
# shot events from the list. Friendly hits feed the camera jolt; the parent still runs
# after so arrows, flashes and everything else happen as before.
func _read_combat_events() -> void:
	for event: Dictionary in sim.events:
		var kind: String = str(event.get("kind", ""))
		if kind == "shot":
			_muzzle_flash(event)
		elif kind == "hit" and bool(event.get("friendly", false)):
			_friendly_jolt()
	super()


# Puffs smoke at each raider as it appears. Raiders already present the first time a
# sim is seen (game start or a loaded save) are seeded silently.
func _burst_new_raiders() -> void:
	if sim != _fx_sim:
		_fx_sim = sim
		_known_raiders.clear()
		_raid_primed = false
	if not sim.raid_active:
		# Stay primed: the next raid's whole wave spawns on one tick and should puff.
		_known_raiders.clear()
		_raid_primed = true
		return
	var fresh: Array[Dictionary] = []
	for u: Dictionary in sim.enemies:
		var id: int = int(u["id"])
		if not _known_raiders.has(id):
			_known_raiders[id] = true
			fresh.append(u)
	if not _raid_primed:
		_raid_primed = true
		return
	for u: Dictionary in fresh:
		if not _effect_budget_open():
			return
		var faction: String = str(u.get("faction", "thornband"))
		var tint: Color = RAIDER_SMOKE.lerp(sim.faction_color(faction), SMOKE_MIX)
		burst_pool.spawn(world_position(sim.position_of(u), SMOKE_HEIGHT), tint, SMOKE_COUNT, SMOKE_SIZE, true)


# A small spark cluster at the shooter, lifted to bow or tower height. Shares the same
# budget check the parent uses for its arrows.
func _muzzle_flash(event: Dictionary) -> void:
	if not _effect_budget_open() or not event.has("from_x") or not event.has("from_y"):
		return
	var from_tile := Vector2(float(event["from_x"]), float(event["from_y"]))
	var tint: Color = RAIDER_SPARK if _raider_near(from_tile, 0.7) else ARROW_SPARK
	burst_pool.spawn(world_position(from_tile, MUZZLE_HEIGHT), tint, MUZZLE_COUNT, MUZZLE_SIZE, false)


# A short, capped jolt for a friendly loss. It never lowers a shake that is already
# stronger from a building break.
func _friendly_jolt() -> void:
	if _shake_level < FRIENDLY_SHAKE_CAP:
		_shake_level = minf(_shake_level + FRIENDLY_JOLT, FRIENDLY_SHAKE_CAP)
