extends RefCounted

# Rise again after a lost raid (The Manor Endures, B1).
#   * Builders with no construction site rebuild ruins on their own: the Manor Hall first, then the
#     workplaces that make goods, then the other workplaces. Walls, gates, towers and traps stay
#     the player's (or a steward's) to mend.
#   * A rebuild is paid from the stores as it goes, one tenth at a time, at the normal repair price.
#     When the stores cannot pay the next tenth the work waits; nothing is ever spent in advance.
#   * Progress is kept on the building ("rebuild", 0..1, and "rebuild_paid") so it is saved with the
#     village and survives a reload. The building stays a ruin until the work is done, then stands
#     at full health.
#   * A ruined workplace still yields a trickle (RUIN_TRICKLE of its base rate): survivors pick
#     through it, so income never drops to zero.
#   * With no builder in the village, neighbours lend a hand at NEIGHBOUR_SHARE of one builder.

const STEP: float = 0.1
const BASE_SECONDS: float = 30.0      # one builder, plus HP_SECONDS for every point of health
const HP_SECONDS: float = 0.02
const RUIN_TRICKLE: float = 0.2
const NEIGHBOUR_SHARE: float = 0.35

var _trickle: Dictionary = {}         # resource -> part of a unit not yet banked (not saved)


# 0 Hall, 1 makes goods, 2 other workplace, -1 never rebuilt on its own.
func priority(sim, b: Dictionary) -> int:
	var type_name: String = str(b["type"])
	if type_name == "hall":
		return 0
	var spec: Dictionary = sim.building_specs.get(type_name, {})
	if spec.get("production") != null or not (spec.get("refine", []) as Array).is_empty():
		return 1
	if not str(spec.get("workplace", "")).is_empty():
		return 2
	return -1


func is_ruin(b: Dictionary) -> bool:
	return float(b["hp"]) <= 0.0 and float(b.get("remaining", 0.0)) <= 0.0


# The ruin builders should work on next: highest priority, then nearest the Hall, then most done.
func target(sim) -> Dictionary:
	if sim.raid_active or sim.raid_warning:
		return {}
	var hall: Dictionary = sim._hall()
	var home: Vector2 = sim.center(hall) if not hall.is_empty() else Vector2(10, 8)
	var best: Dictionary = {}
	var best_score: float = INF
	for b: Dictionary in sim.buildings:
		if not is_ruin(b):
			continue
		var rank: int = priority(sim, b)
		if rank < 0:
			continue
		var score: float = rank * 10000.0 + home.distance_to(sim.center(b)) - float(b.get("rebuild", 0.0)) * 50.0
		if score < best_score:
			best_score = score
			best = b
	return best


func seconds_for(b: Dictionary) -> float:
	return BASE_SECONDS + float(b["max_hp"]) * HP_SECONDS


func _per_unit(sim) -> float:
	return float(sim.materials.config.get("repair", {}).get("hpPerUnit", 15.0)) / (1.0 - minf(0.6, sim.chronicle.bonus("repair")))


# The price of the next tenth of the rebuild, at the normal repair rate.
func step_cost(sim, b: Dictionary) -> Dictionary:
	return sim.materials.repair_cost(sim, b, float(b["max_hp"]) * STEP, _per_unit(sim))


# Whether the work can move on now: the paid share is ahead of the work, or the next share is affordable.
func can_work(sim, b: Dictionary) -> bool:
	if float(b.get("rebuild", 0.0)) < float(b.get("rebuild_paid", 0.0)) - 0.0001:
		return true
	return sim._affordable(step_cost(sim, b))


# `hands` builders' worth of work for dt seconds. Returns true when the building stands again.
func work(sim, b: Dictionary, hands: float, dt: float) -> bool:
	if not is_ruin(b) or hands <= 0.0:
		return false
	var done: float = float(b.get("rebuild", 0.0))
	var paid: float = float(b.get("rebuild_paid", 0.0))
	if done >= paid - 0.0001:
		var cost: Dictionary = step_cost(sim, b)
		if not sim._affordable(cost):
			return false
		sim._spend(cost)
		paid = minf(1.0, paid + STEP)
		b["rebuild_paid"] = paid
	done = minf(paid, done + hands * dt / seconds_for(b))
	b["rebuild"] = done
	if done < 1.0 - 0.0001:
		return false
	b.erase("rebuild")
	b.erase("rebuild_paid")
	b["hp"] = float(b["max_hp"])
	sim.revision += 1
	sim._invalidate()
	var at: Vector2 = sim.center(b)
	sim.events.append({"kind": "rebuilt", "id": int(b["id"]), "x": at.x, "y": at.y})
	var name: String = str(sim.building_specs[b["type"]].get("name", b["type"]))
	sim.notice = "The Manor Hall rises again." if str(b["type"]) == "hall" else "%s rebuilt." % name
	return true


# Called once a tick: neighbours rebuild when the village has no builder, and ruined workplaces trickle.
func tick(sim, dt: float, builders: int) -> void:
	if builders <= 0:
		var site: Dictionary = target(sim)
		if not site.is_empty():
			work(sim, site, NEIGHBOUR_SHARE, dt)
	for b: Dictionary in sim.buildings:
		if not is_ruin(b):
			continue
		var rate: float = trickle_rate(sim, b)
		if rate <= 0.0:
			continue
		var resource: String = str(sim.building_specs[b["type"]]["production"])
		var owed: float = float(_trickle.get(resource, 0.0)) + rate * dt
		var whole: float = floorf(owed)
		if whole >= 1.0:
			sim._bank(resource, whole)
			owed -= whole
		_trickle[resource] = owed


# Goods per second a ruined workplace still yields (0 for anything standing or not producing).
func trickle_rate(sim, b: Dictionary) -> float:
	if not is_ruin(b):
		return 0.0
	var spec: Dictionary = sim.building_specs.get(str(b["type"]), {})
	if spec.get("production") == null:
		return 0.0
	return float(spec.get("rate", 0.0)) * float(spec["tiers"][int(b["tier"]) - 1]["rateMultiplier"]) * RUIN_TRICKLE
