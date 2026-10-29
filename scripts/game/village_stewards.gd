extends RefCounted

# Stewards (The Manor Endures, B3): helpers the village earns, never buys. Once earned a steward
# stays earned (saved with the village), and each can be switched off on the Stewards card.
#   * The Reeve (Manor Hall tier 2) collects from workplaces whose stores are half full.
#   * The Master Mason (the first zone milestone, or Manor Hall tier 3) mends damage between raids,
#     walls and defences included, a little at a time and at the normal repair price.
#   * The Warden (Manor Hall tier 3) sounds the Horn for the next raid once the village is ready
#     for it: threat at least WARDEN_THREAT, the Hall and defences mended, fighters back on their feet.
#     A called raid pays +25% spoils, as when the player sounds it.

const Threat = preload("res://scripts/game/village_threat.gd")

const ORDER: Array[String] = ["reeve", "mason", "warden"]
const INFO: Dictionary = {
	"reeve": {"name": "The Reeve", "does": "Collects from workplaces whose stores are half full.", "earn": "Earned when the Manor Hall reaches tier 2."},
	"mason": {"name": "The Master Mason", "does": "Mends damage between raids, walls and defences too, paid from the stores.", "earn": "Earned at the first zone milestone, or when the Manor Hall reaches tier 3."},
	"warden": {"name": "The Warden", "does": "Sounds the Horn for the next raid once the village is mended and ready, for +25% spoils.", "earn": "Earned when the Manor Hall reaches tier 3."},
}
const INTERVAL: float = 2.0
const REEVE_SHARE: float = 0.5
const MASON_SHARE: float = 0.06      # of a building's health mended each pass
const WARDEN_THREAT: float = 0.6
const READY_HEALTH: float = 0.9

var earned: Dictionary = {}          # id -> true
var off: Dictionary = {}             # id -> true when switched off
var _clock: float = 0.0
var just_earned: Array[String] = []  # for the game layer's announcement; not saved


func state() -> Dictionary:
	return {"earned": earned.keys(), "off": off.keys()}


func restore(data: Variant) -> void:
	earned.clear()
	off.clear()
	if not data is Dictionary:
		return
	for key: String in ["earned", "off"]:
		var list: Variant = (data as Dictionary).get(key, [])
		if not list is Array:
			continue
		for id: Variant in list:
			if str(id) in ORDER:
				(earned if key == "earned" else off)[str(id)] = true


func has(id: String) -> bool:
	return earned.has(id)


func working(id: String) -> bool:
	return earned.has(id) and not off.has(id)


func toggle(id: String) -> bool:
	if not earned.has(id):
		return false
	if off.has(id):
		off.erase(id)
	else:
		off[id] = true
	return true


func _hall_tier(sim) -> int:
	var hall: Dictionary = sim._hall()
	return 0 if hall.is_empty() else int(hall["tier"])


func _check_earned(sim) -> void:
	var tier: int = _hall_tier(sim)
	var milestone: bool = false
	for type_name: Variant in sim.zone_boost:
		if float(sim.zone_boost[type_name]) > 1.0:
			milestone = true
			break
	var wants: Dictionary = {"reeve": tier >= 2, "mason": milestone or tier >= 3, "warden": tier >= 3}
	for id: String in ORDER:
		if bool(wants[id]) and not earned.has(id):
			earned[id] = true
			just_earned.append(id)
			sim.chronicle.queue_banner("Old Bell", "%s joins the manor. %s" % [str(INFO[id]["name"]), str(INFO[id]["does"])])


func tick(sim, dt: float) -> void:
	_clock += dt
	if _clock < INTERVAL:
		return
	_clock = 0.0
	_check_earned(sim)
	if sim.raid_active or sim.raid_warning:
		return
	if working("reeve"):
		_reeve(sim)
	if working("mason"):
		_mason(sim)
	if working("warden"):
		_warden(sim)


func _reeve(sim) -> void:
	var before: String = sim.notice
	var gathered: int = 0
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) <= 0.0 or float(b["remaining"]) > 0.0:
			continue
		if sim.building_specs[b["type"]].get("production") == null:
			continue
		var cap: float = sim.reserve_cap(b)
		if cap > 0.0 and float(b["reserve"]) >= cap * REEVE_SHARE:
			gathered += sim.collect(int(b["id"]))
	sim.notice = before


# The most damaged building gets a share of its health back, as much as the stores pay for.
func _mason(sim) -> void:
	var worst: Dictionary = {}
	var worst_share: float = 1.0
	for b: Dictionary in sim.buildings:
		if float(b["remaining"]) > 0.0 or float(b["max_hp"]) <= 0.0:
			continue
		# Ruined Hall and workplaces are the builders' to raise (village_rebuild.gd).
		if float(b["hp"]) <= 0.0 and sim.rebuild.priority(sim, b) >= 0:
			continue
		var share: float = float(b["hp"]) / float(b["max_hp"])
		if share < worst_share - 0.001:
			worst_share = share
			worst = b
	if worst.is_empty():
		return
	var per_unit: float = float(sim.materials.config.get("repair", {}).get("hpPerUnit", 15.0)) / (1.0 - minf(0.6, sim.chronicle.bonus("repair")))
	var want: float = minf(float(worst["max_hp"]) - float(worst["hp"]), float(worst["max_hp"]) * MASON_SHARE)
	var restored: float = sim.materials.affordable_hp(sim, worst, want, per_unit)
	if restored <= 0.0:
		return
	var was_ruin: bool = float(worst["hp"]) <= 0.0
	sim._spend(sim.materials.repair_cost(sim, worst, restored, per_unit))
	worst["hp"] = minf(float(worst["max_hp"]), float(worst["hp"]) + restored)
	if was_ruin:
		sim.revision += 1
	sim._invalidate()


func ready_for_raid(sim) -> bool:
	var hall: Dictionary = sim._hall()
	if hall.is_empty() or float(hall["hp"]) < float(hall["max_hp"]) * READY_HEALTH:
		return false
	for b: Dictionary in sim.buildings:
		if float(b["remaining"]) > 0.0:
			continue
		var stats: Dictionary = sim.building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]
		if float(stats.get("damage", 0.0)) > 0.0 and float(b["hp"]) < float(b["max_hp"]) * READY_HEALTH:
			return false
	for u: Dictionary in sim.units:
		if str(sim.troop_specs[u["type"]].get("role", "")) == "combat" and float(u["hp"]) < float(u["max_hp"]) * READY_HEALTH:
			return false
	return true


func _warden(sim) -> void:
	if Threat.meter(sim) < WARDEN_THREAT or not ready_for_raid(sim):
		return
	if sim.start_raid():
		sim.notice = "The Warden sounds the horn / they come in 3 seconds. Spoils +25%."
