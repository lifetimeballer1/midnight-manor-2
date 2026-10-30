extends RefCounted

# Village ranks: the settlement's standing, read from what the player can see grow. Every finished
# non-defense building counts its level (a level 3 cottage counts 3; the Hall counts double, as the
# seat of the manor), and the total lifts the village from Camp to Hamlet, Village, Town and Manor.
# Each rank above Camp lifts all workplace output by BONUS_STEP.
#
# Nothing is saved: the rank is worked out from the buildings, so old saves simply arrive at the
# rank they have earned. Ruins still count (they are rebuilt), so a lost raid never demotes the
# village. Walls, towers and traps are left out so a ring of wall segments cannot buy a rank.

const Tiers = preload("res://scripts/game/village_tiers.gd")

const RANKS: Array[Dictionary] = [
	{"name": "Camp", "levels": 0},
	{"name": "Hamlet", "levels": 10},
	{"name": "Village", "levels": 25},
	{"name": "Town", "levels": 45},
	{"name": "Manor", "levels": 75},
]
const BONUS_STEP: float = 0.05
const HALL_WEIGHT: int = 2
const REFRESH_TICKS: int = 10            # recount about once a second of game time

var levels: int = 0
var index: int = 0
var _ticks: int = 0


func refresh(sim) -> void:
	var total: int = 0
	for b: Dictionary in sim.buildings:
		var type_name: String = str(b["type"])
		if Tiers.skipped(type_name) or float(b.get("remaining", 0.0)) > 0.0:
			continue
		total += int(b["tier"]) * (HALL_WEIGHT if type_name == "hall" else 1)
	levels = total
	index = index_for(total)


# Called every sim tick; recounts now and then.
func tick(sim) -> void:
	_ticks -= 1
	if _ticks <= 0:
		_ticks = REFRESH_TICKS
		refresh(sim)


static func index_for(total: int) -> int:
	var found: int = 0
	for i in RANKS.size():
		if total >= int(RANKS[i]["levels"]):
			found = i
	return found


func title() -> String:
	return str(RANKS[index]["name"])


func multiplier() -> float:
	return 1.0 + BONUS_STEP * float(index)


func next_levels() -> int:
	return int(RANKS[index + 1]["levels"]) if index + 1 < RANKS.size() else -1


func summary() -> String:
	var text: String = "%s · %d building levels" % [title(), levels]
	if index > 0:
		text += " · +%d%% output" % roundi(BONUS_STEP * 100.0 * float(index))
	var next: int = next_levels()
	if next > 0:
		text += "\nNext: %s at %d levels. Raise and upgrade buildings to climb." % [str(RANKS[index + 1]["name"]), next]
	else:
		text += "\nThe highest rank: a true manor."
	return text
