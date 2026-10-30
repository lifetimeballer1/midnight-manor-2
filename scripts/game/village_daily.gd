extends RefCounted

# Daily return (The Manor Endures, C3). Saved with the village; older saves start fresh.
#   * One omen a day, drawn from the calendar date, nudges the rules a little: a resource's
#     workplaces yield OMEN_BONUS more, or Quiet Roads lets threat build QUIET_ROADS slower.
#   * One contract a day: gather an amount of one resource, sized from the village's own pace.
#     Finishing it opens a chest that grows with the streak.
#   * The streak counts days in a row the manor was opened; a missed day starts it again at 1.
# The game layer passes in today's day number (local calendar days since 1970), so the sim
# itself never reads the clock and tests can step through days.

const OMENS: Array[Dictionary] = [
	{"id": "fair-winds", "name": "Fair Winds", "text": "Lumber camps and groves yield 15% more Wood today.", "resource": "wood"},
	{"id": "full-larder", "name": "Full Larder", "text": "Farms, ponds and pastures yield 15% more Food today.", "resource": "food"},
	{"id": "golden-hour", "name": "Golden Hour", "text": "Mines yield 15% more Gold today.", "resource": "gold"},
	{"id": "quiet-roads", "name": "Quiet Roads", "text": "Threat builds a quarter slower today.", "resource": ""},
]
const OMEN_BONUS: float = 1.15
const QUIET_ROADS: float = 1.25
const CONTRACT_RESOURCES: Array[String] = ["wood", "food", "gold"]
const CONTRACT_MINUTES: float = 12.0     # the target is about this many minutes of the village's pace
const CONTRACT_MIN: int = 150
const CHEST_SHARE: float = 0.6           # chest = this share of the target, in each of the other two resources
const STREAK_STEP: float = 0.1
const STREAK_CAP: int = 6                # the chest stops growing after this many days (+50%)

var day: int = -1
var streak: int = 0
var omen: String = ""
var contract: Dictionary = {}            # {resource, target, base, claimed}
var just_turned: bool = false            # a new day began on the last visit (for the game's banner; not saved)


func state() -> Dictionary:
	return {"day": day, "streak": streak, "omen": omen, "contract": contract.duplicate(true)}


func restore(data: Variant) -> void:
	day = -1
	streak = 0
	omen = ""
	contract = {}
	if not data is Dictionary:
		return
	var saved: Dictionary = data
	if (saved.get("day") is int or saved.get("day") is float) and (saved.get("streak") is int or saved.get("streak") is float):
		day = int(saved["day"])
		streak = clampi(int(saved["streak"]), 0, 100000)
	if _omen(str(saved.get("omen", ""))).has("id"):
		omen = str(saved["omen"])
	var held: Variant = saved.get("contract", {})
	if held is Dictionary and str((held as Dictionary).get("resource", "")) in CONTRACT_RESOURCES:
		contract = (held as Dictionary).duplicate(true)
		for key: String in ["target", "base"]:
			contract[key] = float(contract.get(key, 0.0)) if (contract.get(key) is float or contract.get(key) is int) else 0.0
		contract["claimed"] = bool(contract.get("claimed", false))


# Local calendar days since 1970 for a unix time; the game passes the real clock.
static func day_number(unix_seconds: float, bias_minutes: int) -> int:
	return floori((unix_seconds + bias_minutes * 60.0) / 86400.0)


static func _omen(id: String) -> Dictionary:
	for entry: Dictionary in OMENS:
		if str(entry["id"]) == id:
			return entry
	return {}


func omen_info() -> Dictionary:
	return _omen(omen)


# Opening the manor on `today`: a new day draws its omen and contract and moves the streak.
func visit(sim, today: int) -> void:
	just_turned = false
	if today == day:
		return
	just_turned = true
	streak = streak + 1 if day >= 0 and today == day + 1 else 1
	day = today
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("manor-day-%d" % today)
	omen = str(OMENS[rng.randi() % OMENS.size()]["id"])
	var resource: String = CONTRACT_RESOURCES[rng.randi() % CONTRACT_RESOURCES.size()]
	var pace: float = 0.0
	var income: Dictionary = sim.income_per_minute()
	for source: Variant in income.get(resource, {}):
		pace += float(income[resource][source])
	var target: float = maxf(float(CONTRACT_MIN), roundf(pace * CONTRACT_MINUTES / 10.0) * 10.0)
	contract = {"resource": resource, "target": target, "base": float(sim.gathered.get(resource, 0.0)), "claimed": false}


func progress(sim) -> float:
	if contract.is_empty():
		return 0.0
	var resource: String = str(contract["resource"])
	return clampf(float(sim.gathered.get(resource, 0.0)) - float(contract["base"]), 0.0, float(contract["target"]))


func is_ready(sim) -> bool:
	return not contract.is_empty() and not bool(contract["claimed"]) and progress(sim) >= float(contract["target"])


func chest(sim) -> Dictionary:
	if contract.is_empty():
		return {}
	var scale: float = 1.0 + STREAK_STEP * float(mini(maxi(streak, 1), STREAK_CAP) - 1)
	var amount: float = roundf(float(contract["target"]) * CHEST_SHARE * scale)
	var out: Dictionary = {}
	for resource: String in CONTRACT_RESOURCES:
		if resource != str(contract["resource"]):
			out[resource] = amount
	return out


# Opens the chest into the stores (storage caps apply). Returns what was banked, or {} when not ready.
func claim(sim) -> Dictionary:
	if not is_ready(sim):
		return {}
	contract["claimed"] = true
	var banked: Dictionary = {}
	var prize: Dictionary = chest(sim)
	for resource: String in prize:
		var taken: int = sim._bank(resource, float(prize[resource]))
		if taken > 0:
			banked[resource] = taken
	return banked


# Multiplier on a workplace's output from today's omen.
func rate_for(resource: String) -> float:
	var info: Dictionary = omen_info()
	return OMEN_BONUS if not info.is_empty() and str(info["resource"]) == resource else 1.0


# Multiplier on the threat meter's span from today's omen.
func span_scale() -> float:
	return QUIET_ROADS if omen == "quiet-roads" else 1.0
