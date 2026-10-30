extends RefCounted

# Raids that fit idle play (The Manor Endures, B2).
#   * Threat builds up on a meter between raids. When it is full the horns sound and the raid comes
#     25 seconds later. The meter holds still while the Manor Hall lies in ruins, so a village that
#     is rising again is not raided before its Hall stands. The Horn still calls a raid early.
#   * Raid strength follows defence strength: a raid's total health is capped at STRENGTH_PER_POWER
#     times the village's defence power (standing defences' damage a second plus its fighters'),
#     never above the usual wave curve and never below MIN_SHARE of it. A village that has lost its
#     defences meets smaller bands until it builds them back; one that builds more meets the full curve.
#   * Only the timing of the raids and the size of ambient raids change. Story raids keep their size.

const WarRules = preload("res://scripts/game/war_rules.gd")

const WARNING_SECONDS: float = 25.0
const STRENGTH_PER_POWER: float = 10.0
const MIN_SHARE: float = 0.3


# 0..1: how full the threat meter is. Full means the horns are sounding.
static func meter(sim) -> float:
	if sim.raid_active or sim.raid_warning:
		return 1.0
	var span: float = maxf(1.0, float(sim.raid_span) - WARNING_SECONDS)
	var left: float = maxf(0.0, float(sim.next_raid_at) - WARNING_SECONDS - float(sim.elapsed))
	return clampf(1.0 - left / span, 0.0, 1.0)


# Damage a second the village can answer a raid with: standing defences and living fighters.
static func defence_power(sim) -> float:
	var power: float = 0.0
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) <= 0.0 or float(b.get("remaining", 0.0)) > 0.0:
			continue
		var stats: Dictionary = sim.building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]
		var damage: float = float(stats.get("damage", 0.0)) * sim.drill.multiplier()
		if damage > 0.0:
			power += damage / maxf(0.1, float(WarRules.weapon_of(str(b["type"]))["cooldown"]))
	for u: Dictionary in sim.units:
		if float(u["hp"]) <= 0.0:
			continue
		var spec: Dictionary = sim.troop_specs.get(str(u["type"]), {})
		if str(spec.get("role", "")) != "combat":
			continue
		var base: float = float(spec.get("base", {}).get("damage", 0.0))
		power += base * (1.0 + float(spec.get("growth", {}).get("damage", 0.0)) * (int(u.get("level", 1)) - 1))
	return power


# The share (MIN_SHARE..1) of a raid's usual health that this village's defences call for.
static func strength_share(sim, raid_health: float) -> float:
	if raid_health <= 0.0:
		return 1.0
	var cap: float = defence_power(sim) * STRENGTH_PER_POWER
	return clampf(cap / raid_health, MIN_SHARE, 1.0)


# Scales a freshly spawned ambient raid to the village's defences. Returns the share used.
static func ease_raid(sim) -> float:
	var health: float = 0.0
	for enemy: Dictionary in sim.enemies:
		health += float(enemy["max_hp"])
	var share: float = strength_share(sim, health)
	if share < 1.0:
		for enemy: Dictionary in sim.enemies:
			enemy["max_hp"] = float(enemy["max_hp"]) * share
			enemy["hp"] = float(enemy["max_hp"])
	return share
