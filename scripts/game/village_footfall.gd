extends "res://scripts/game/village_combat_fx.gd"

# Footfall looks, layered over the unit animation. Walk and run clips play at a speed
# matched to how far each model really moved this frame, so a figure eased along by a
# raid or a slow road keeps its stride instead of gliding or running on the spot. Every
# stride of ground covered throws a tiny, low puff of dust from the feet. Puffs share the
# combat burst pool and the effect budget, are capped per frame, and are skipped while the
# sim is paused, in heavy rain, or for figures off screen. The base update still decides
# what plays, when it pauses and where each model stands.

const REFERENCE_SPEED: float = 2.4    # world units per second that plays a clip at 1.0x (assumed)
const SPEED_MIN: float = 0.6
const SPEED_MAX: float = 1.6
const STRIDE: float = 0.9             # world units of ground covered between dust puffs
const MAX_PUFFS_PER_FRAME: int = 2
const MAX_STEP: float = 2.5           # larger jumps are spawns or resets, not strides
const HEAVY_RAIN: float = 0.35
const LOCOMOTION: Array = ["walk", "run"]

var _footfall: Dictionary = {}        # actor id -> {"last": Vector3, "stride": float}
var _puffs_this_frame: int = 0


func _update_actors(delta: float) -> void:
	super(delta)
	_puffs_this_frame = 0
	for id: int in _footfall.keys():
		if not actors.has(id):
			_footfall.erase(id)
	var stepping: bool = delta > 0.0 and is_finite(delta) and not sim.paused
	for id: int in actors.keys():
		var record: Dictionary = actors[id]
		var model: Node3D = record["model"]
		if not is_instance_valid(model):
			continue
		var entry: Dictionary = _footfall.get(id, {"last": model.position, "stride": 0.0})
		var step: Vector3 = model.position - entry["last"]
		step.y = 0.0
		var moved: float = step.length()
		entry["last"] = model.position
		_footfall[id] = entry
		var player: AnimationPlayer = record["player"]
		if not stepping or player == null or not model.visible or not (str(record["clip"]) in LOCOMOTION):
			continue
		if moved > MAX_STEP:
			continue
		# The base sets speed_scale to 1.0 each live frame; replace it with the measured pace.
		player.speed_scale = clampf((moved / delta) / REFERENCE_SPEED, SPEED_MIN, SPEED_MAX)
		entry["stride"] = float(entry["stride"]) + moved
		if float(entry["stride"]) >= STRIDE:
			entry["stride"] = fmod(float(entry["stride"]), STRIDE)
			_footfall_puff(model.position)


# One small, low puff of dust at a figure's feet, within the frame cap and effect budget.
func _footfall_puff(at: Vector3) -> void:
	if _puffs_this_frame >= MAX_PUFFS_PER_FRAME or rain_level > HEAVY_RAIN or not _effect_budget_open():
		return
	_puffs_this_frame += 1
	burst_pool.spawn(at + Vector3(0, 0.08, 0), DUST, 2, 0.3, false)
