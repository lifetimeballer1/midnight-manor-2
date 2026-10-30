extends RefCounted

# Weapon Drill (The Manor Endures, C4): a place for big numbers to go that keeps the rule that only
# war and land are bought. Each level of drill makes every defence's weapon hit DAMAGE_STEP harder,
# for good. The price grows by COST_GROWTH a level, so there is always a next level to save for.
# Stronger defences also mean stronger raids (village_threat.gd follows defence power), so the
# drill raises the stakes as well as the walls. Saved with the village as "drill"; older saves start at 0.

const DAMAGE_STEP: float = 0.1
const BASE_COST: Dictionary = {"gold": 400.0, "wood": 300.0, "food": 200.0}
const COST_GROWTH: float = 1.6
const MAX_LEVEL: int = 30
const OPENS_AT_ACT: int = 3

var level: int = 0


func state() -> Dictionary:
	return {"level": level}


func restore(data: Variant) -> void:
	level = 0
	if data is Dictionary:
		var saved: Variant = (data as Dictionary).get("level", 0)
		if saved is int or saved is float:
			level = clampi(int(saved), 0, MAX_LEVEL)


func multiplier() -> float:
	return 1.0 + DAMAGE_STEP * float(level)


func cost() -> Dictionary:
	var out: Dictionary = {}
	var scale: float = pow(COST_GROWTH, float(level))
	for resource: String in BASE_COST:
		out[resource] = int(roundf(float(BASE_COST[resource]) * scale / 10.0) * 10.0)
	return out


func reason(sim) -> String:
	if level >= MAX_LEVEL:
		return "The drill is as sharp as it gets."
	if sim.chronicle.act < OPENS_AT_ACT:
		return "The Chronicle opens the drill yard in Act %d." % OPENS_AT_ACT
	if sim.raid_active or sim.raid_warning:
		return "No drilling while the horns sound."
	if not sim._affordable(cost()):
		return "Not enough in the stores."
	return ""


func train(sim) -> bool:
	var why: String = reason(sim)
	if not why.is_empty():
		sim.notice = why
		return false
	sim._spend(cost())
	level += 1
	sim.notice = "Weapon Drill %d / every defence hits %d%% harder." % [level, int(roundf((multiplier() - 1.0) * 100.0))]
	return true


# A defence's tier stats with the drill applied (the same dictionary when there is no drill yet).
func drilled(stats: Dictionary) -> Dictionary:
	if level <= 0:
		return stats
	var out: Dictionary = stats.duplicate()
	out["damage"] = float(stats.get("damage", 0.0)) * multiplier()
	return out
