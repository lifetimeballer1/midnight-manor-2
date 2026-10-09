extends "res://scripts/game/village_bell.gd"

# Raid pacing: the simulation tick is the expensive part of a raid. The raid-start
# log showed ticks of 10-24 ms (72 ms at the first tick) against about 2.5 ms in
# quiet play, while actor updates stayed near 1 ms. While enemies are on the map
# the world advances in 0.1 s steps instead of 0.05 s, so the same game time costs
# half the tick work. Models ease toward their simulated spots during a raid, so
# the slower steps still read as motion. Outside raids nothing changes.

const TICK_STEP: float = 0.05
const RAID_STEP: float = 0.1
const SMOOTH_SPEED: float = 12.0

var _pace_acc: float = 0.0
var _raiding: bool = false


func _process(delta: float) -> void:
	# Hold back the game's own tick loop for this frame; this layer runs the ticks itself.
	tick_accumulator = -1000.0
	super(delta)
	if not started:
		_pace_acc = 0.0
		return
	_raiding = sim.raid_active or not sim.enemies.is_empty()
	if sim.paused or is_instance_valid(battle_view):
		_pace_acc = 0.0
	else:
		var step: float = RAID_STEP if _raiding else TICK_STEP
		_pace_acc += minf(delta, 0.25)
		while _pace_acc >= step:
			var spike_start: int = Time.get_ticks_usec() if spike_active else 0
			sim.tick(step)
			if spike_active:
				spike_worst_tick = maxf(spike_worst_tick, float(Time.get_ticks_usec() - spike_start) / 1000.0)
			_pace_acc -= step
	_smooth_actors(delta)


# The game places each model on its simulated spot every frame. During a raid the
# model eases toward that spot instead, so the 0.1 s steps still read as motion.
func _smooth_actors(delta: float) -> void:
	var weight: float = clampf(delta * SMOOTH_SPEED, 0.0, 1.0)
	for id in actors.keys():
		var record: Dictionary = actors[id]
		var model: Node3D = record.get("model")
		if not is_instance_valid(model):
			continue
		var destination: Vector3 = model.position
		var shown: Vector3 = destination
		if _raiding and record.has("shown"):
			shown = (record["shown"] as Vector3).lerp(destination, weight)
		record["shown"] = shown
		model.position = shown
