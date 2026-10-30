extends RefCounted

# Manor Renewal (The Manor Endures, C2): an optional prestige reset, open once the Vale is united.
# Renewing starts a fresh village and pays Moon Seals, which are kept for good in their own small
# file (LEGACY_PATH), apart from the village save, so v1 to v4 village saves are untouched.
# Each Moon Seal adds SEAL_BONUS to every workplace's output in every later village.
# After the first renewal the Vale stays sworn to the manor's line, and later renewals open once
# the new Manor Hall reaches LATER_HALL_TIER.

const LEGACY_PATH: String = "user://manor-legacy.json"
const SEAL_BONUS: float = 0.05
const LATER_HALL_TIER: int = 3

var seals: int = 0
var renewals: int = 0
var vale: bool = false        # the Vale was united in an earlier village


func to_dict() -> Dictionary:
	return {"version": 1, "seals": seals, "renewals": renewals, "vale": vale}


func from_dict(data: Variant) -> void:
	seals = 0
	renewals = 0
	vale = false
	if not data is Dictionary:
		return
	var saved: Dictionary = data
	for key: String in ["seals", "renewals"]:
		var value: Variant = saved.get(key, 0)
		if value is int or value is float:
			set(key, clampi(int(value), 0, 100000))
	vale = saved.get("vale", false) is bool and bool(saved["vale"])


func load_from(path: String = LEGACY_PATH) -> void:
	if FileAccess.file_exists(path):
		from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


func save_to(path: String = LEGACY_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict()))
	return true


func multiplier() -> float:
	return 1.0 + SEAL_BONUS * float(seals)


# Moon Seals this village would pay if renewed now: a base for the run, plus its Hall, its drill,
# how far the Chronicle got, and the Vale.
func seals_for(sim) -> int:
	var hall: Dictionary = sim._hall()
	var tier: int = 0 if hall.is_empty() else int(hall["tier"])
	return 3 + tier + int(sim.drill.level / 3) + int(sim.chronicle.act / 2) + (2 if sim.vale_united else 0)


func reason(sim) -> String:
	if sim.raid_active or sim.raid_warning:
		return "Not while the horns sound."
	if not sim.frontier.active.is_empty():
		return "Not during a frontier battle."
	if renewals == 0:
		return "" if sim.vale_united else "Unite the Vale first (Act XI)."
	var hall: Dictionary = sim._hall()
	if hall.is_empty() or int(hall["tier"]) < LATER_HALL_TIER or float(hall.get("remaining", 0.0)) > 0.0:
		return "Grow this village's Manor Hall to tier %d first." % LATER_HALL_TIER
	return ""


# Records a renewal of `sim` (call once the fresh village is in place). Returns the seals paid.
func record(sim) -> int:
	var paid: int = seals_for(sim)
	seals += paid
	renewals += 1
	vale = vale or sim.vale_united
	return paid
