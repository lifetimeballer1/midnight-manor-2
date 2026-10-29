extends RefCounted

# Workplace perks: the bonuses written on buildings in data/buildings.json (buildAura, gatherAura,
# damageAura, healRate, xpRate, researchRate, carryBonus, tradeAura). A perk only counts while the
# building stands finished with at least one living worker posted there. Aura perks reach the
# buildings or villagers within REACH tiles; the rest help the whole village. A higher tier adds
# half the base value again per tier. Recomputed on a slow clock, not per building per frame.

const REACH: float = 6.0
const REFRESH_SECONDS: float = 1.0
const TIER_STEP: float = 0.5
# Village-wide perks add up across buildings, to these limits.
const CAPS: Dictionary = {"damage": 0.3, "xp": 0.36, "research": 0.45, "carry": 12.0, "trade": 0.2}
const KEYS: Dictionary = {"buildAura": "build", "gatherAura": "gather", "healRate": "heal",
	"damageAura": "damage", "xpRate": "xp", "researchRate": "research", "carryBonus": "carry", "tradeAura": "trade"}
const AURAS: Array[String] = ["build", "gather", "heal"]

var clock: float = REFRESH_SECONDS
var signature: int = -1
var sources: Array[Dictionary] = []     # {id, kind, value, centre}
var totals: Dictionary = {}             # village-wide kind -> value
var _gather: Dictionary = {}            # building id -> best gather bonus
var _build: Dictionary = {}             # building id -> best build bonus
var _reached: Dictionary = {}           # source id -> buildings it helps


func tick(sim, dt: float) -> void:
	clock += dt
	if clock < REFRESH_SECONDS:
		return
	clock = 0.0
	refresh(sim)


func _signature(sim) -> int:
	var parts: Array = [sim.revision]
	for u: Dictionary in sim.units:
		if float(u["hp"]) > 0.0:
			parts.append(int(u["workplace"]))
	return hash(parts)


func staffed(sim, b: Dictionary) -> bool:
	if float(b["hp"]) <= 0.0 or float(b["remaining"]) > 0.0:
		return false
	for u: Dictionary in sim.units:
		if int(u["workplace"]) == int(b["id"]) and float(u["hp"]) > 0.0:
			return true
	return false


func value_of(sim, b: Dictionary, field: String) -> float:
	var base: float = float(sim.building_specs[b["type"]].get(field, 0.0))
	return base * (1.0 + TIER_STEP * float(int(b["tier"]) - 1))


func refresh(sim, force: bool = false) -> void:
	var sig: int = _signature(sim)
	if sig == signature and not force:
		return
	signature = sig
	sources.clear()
	totals.clear()
	_gather.clear()
	_build.clear()
	_reached.clear()
	for b: Dictionary in sim.buildings:
		var spec: Dictionary = sim.building_specs.get(b["type"], {})
		var fields: Array = []
		for field: String in KEYS:
			if float(spec.get(field, 0.0)) > 0.0:
				fields.append(field)
		if fields.is_empty() or not staffed(sim, b):
			continue
		for field: String in fields:
			var kind: String = KEYS[field]
			var value: float = value_of(sim, b, field)
			sources.append({"id": int(b["id"]), "kind": kind, "value": value, "centre": sim.center(b)})
			if kind not in AURAS:
				totals[kind] = minf(float(CAPS.get(kind, value)), float(totals.get(kind, 0.0)) + value)
	for source: Dictionary in sources:
		if source["kind"] not in ["build", "gather"]:
			continue
		var helped: Array[int] = []
		for b: Dictionary in sim.buildings:
			if int(b["id"]) == int(source["id"]) or float(b["hp"]) <= 0.0:
				continue
			if source["kind"] == "gather" and sim.building_specs[b["type"]].get("production") == null:
				continue
			if sim._building_distance(source["centre"], b) > REACH:
				continue
			helped.append(int(b["id"]))
			var into: Dictionary = _gather if source["kind"] == "gather" else _build
			into[int(b["id"])] = maxf(float(into.get(int(b["id"]), 0.0)), float(source["value"]))
		_reached[str(source["id"]) + ":" + str(source["kind"])] = helped


# Output multiplier for a producing building from nearby staffed workshops.
func gather_for(b: Dictionary) -> float:
	return 1.0 + float(_gather.get(int(b["id"]), 0.0))


# Construction speed multiplier for a site from nearby staffed mason yards.
func build_for(b: Dictionary) -> float:
	return 1.0 + float(_build.get(int(b["id"]), 0.0))


# Healing multiplier for a villager standing at point, from nearby staffed chapels.
func heal_at(sim, point: Vector2) -> float:
	var best: float = 0.0
	for source: Dictionary in sources:
		if source["kind"] == "heal" and (source["centre"] as Vector2).distance_to(point) <= REACH:
			best = maxf(best, float(source["value"]))
	return 1.0 + best


func total(kind: String) -> float:
	return float(totals.get(kind, 0.0))


# One line for the building card: what this building's perk is doing right now, or "".
func describe(sim, b: Dictionary) -> String:
	var spec: Dictionary = sim.building_specs.get(b["type"], {})
	var lines: Array[String] = []
	for field: String in KEYS:
		if float(spec.get(field, 0.0)) <= 0.0:
			continue
		var kind: String = KEYS[field]
		var value: float = value_of(sim, b, field)
		var active: bool = false
		for source: Dictionary in sources:
			if int(source["id"]) == int(b["id"]) and source["kind"] == kind:
				active = true
		var text: String = ""
		match kind:
			"gather":
				var n: int = (_reached.get(str(b["id"]) + ":gather", []) as Array).size()
				text = "Boosting %d nearby workplace%s +%d%% output" % [n, "" if n == 1 else "s", roundi(value * 100)]
			"build":
				var n: int = (_reached.get(str(b["id"]) + ":build", []) as Array).size()
				text = "Nearby building work +%d%% faster (%d in reach)" % [roundi(value * 100), n]
			"heal":
				text = "Villagers nearby heal +%d%% faster" % roundi(value * 100)
			"damage":
				text = "Village fighters +%d%% damage" % roundi(value * 100)
			"xp":
				text = "Village XP from missions +%d%%" % roundi(value * 100)
			"research":
				text = "Research insight +%d%%" % roundi(value * 100)
			"carry":
				text = "Gatherers carry +%d more" % roundi(value)
			"trade":
				text = "Town gold income +%d%%" % roundi(value * 100)
		if not active:
			text += " (needs a worker)" if float(b["remaining"]) <= 0.0 and float(b["hp"]) > 0.0 else " (once finished and staffed)"
		lines.append(text)
	return "\n".join(PackedStringArray(lines))
