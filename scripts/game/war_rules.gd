extends RefCounted

# War rules: how each defense fights, how siege raiders behave, and the warlords.
#
# Every defense used to fire the same single arrow at the nearest raider once a second.
# Now each one has its own weapon:
#   * Watchtower: one arrow, as before.
#   * Archer Tower: a volley, a second arrow at another raider in range (60% damage).
#   * Ballista: a heavy bolt every 1.8 s that goes through every raider on its line,
#     and it picks siege engines first.
#   * Grand Bastion: an iron shell every 2 s that bursts, hurting everyone near the hit.
#   * Signal Watchfire: its shot marks the raider; marked raiders take 25% more damage.
#   * Spike Trap: one snap, as before. Fire Trap: a roar of flame that sets every raider
#     on it burning for a few seconds.
# Raiders:
#   * Bombards shell buildings from range instead of walking up to them.
#   * Rams go for the gates.
#   * Every fourth wave a warlord leads the band: a big, hard-hitting raider whose shout
#     makes nearby raiders hit harder. Kill it and the band breaks: the rest turn and run
#     for the edge of the land, and the raid is won.
#
# The rules here change only the sim's own dictionaries and add events for the view.
# The war log (damage by defense, routed raiders) is not saved: it only feeds the
# after-battle report.

const MARK_SECONDS: float = 5.0
const MARK_BONUS: float = 0.25
const BURN_SECONDS: float = 3.0
const BURN_SHARE: float = 0.3        # of the trap's hit, per second, while burning
const RALLY_RADIUS: float = 3.0
const RALLY_BONUS: float = 0.25
const ROUT_SECONDS: float = 10.0     # a fleeing raider that cannot get out is gone after this
const WARLORD_EVERY: int = 4
const SIEGE: Array[String] = ["ram", "bombard", "breaker"]

# type -> weapon. Missing types fire a plain arrow.
const WEAPONS: Dictionary = {
	"tower": {"weapon": "arrow", "cooldown": 1.0},
	"archer_tower": {"weapon": "volley", "cooldown": 1.0, "second": 0.6},
	"ballista": {"weapon": "bolt", "cooldown": 1.8, "scale": 1.5, "width": 0.6},
	"bastion": {"weapon": "shell", "cooldown": 2.0, "scale": 1.6, "radius": 1.4, "splash": 0.6},
	"watchfire": {"weapon": "mark", "cooldown": 1.0},
	"trap": {"weapon": "spike", "cooldown": 5.0},
	"fire-trap": {"weapon": "fire", "cooldown": 4.0, "radius": 1.3},
}


static func weapon_of(type_name: String) -> Dictionary:
	return WEAPONS.get(type_name, {"weapon": "arrow", "cooldown": 1.0})


static func new_log() -> Dictionary:
	return {"damage_by": {}, "slain": {}, "routed": 0, "warlord": "", "warlord_slain": false, "bounty": 0, "spoils": 0.0}


# Damage a raider. Marked raiders take more. Returns the damage dealt.
static func harm(sim, enemy: Dictionary, amount: float, source: String = "") -> float:
	if float(enemy["hp"]) <= 0.0:
		return 0.0
	if float(enemy.get("lit", 0.0)) > 0.0:
		amount *= 1.0 + MARK_BONUS
	var dealt: float = minf(amount, float(enemy["hp"]))
	enemy["hp"] = float(enemy["hp"]) - amount
	if not source.is_empty():
		var by: Dictionary = sim.war_log["damage_by"]
		by[source] = float(by.get(source, 0.0)) + dealt
	return amount


static func _alive(enemy: Dictionary) -> bool:
	return float(enemy["hp"]) > 0.0


# A defense fires if a raider is in range. Returns true when it fired.
static func fire(sim, b: Dictionary, stats: Dictionary) -> bool:
	var type_name: String = str(b["type"])
	var spec: Dictionary = weapon_of(type_name)
	var weapon: String = str(spec["weapon"])
	var origin: Vector2 = sim.center(b)
	var reach: float = float(stats["range"])
	var damage: float = float(stats["damage"])
	var target: Dictionary = _ballista_target(sim, origin, reach) if weapon == "bolt" else sim._tower_target(origin)
	if target.is_empty() or origin.distance_to(sim.position_of(target)) > reach:
		return false
	var aim: Vector2 = sim.position_of(target)
	var cooldown: float = float(spec["cooldown"])
	match weapon:
		"spike":
			cooldown = 3.0 if sim.chronicle.effect("command:trap-reset") else 5.0
			_strike(sim, target, damage, type_name)
			sim._shot(origin, aim)
		"volley":
			_strike(sim, target, damage, type_name)
			sim._shot(origin, aim)
			var other: Dictionary = {}
			var best: float = INF
			for enemy: Dictionary in sim.enemies:
				if enemy == target or not _alive(enemy):
					continue
				var gap: float = origin.distance_to(sim.position_of(enemy))
				if gap <= reach and gap < best:
					best = gap
					other = enemy
			if not other.is_empty():
				_strike(sim, other, damage * float(spec["second"]), type_name)
				sim._shot(origin, sim.position_of(other))
		"bolt":
			damage *= float(spec["scale"])
			var direction: Vector2 = (aim - origin).normalized()
			var end: Vector2 = origin + direction * reach
			var struck: int = 0
			for enemy: Dictionary in sim.enemies:
				if not _alive(enemy):
					continue
				var point: Vector2 = sim.position_of(enemy)
				var along: float = (point - origin).dot(direction)
				if along < 0.0 or along > reach:
					continue
				if (origin + direction * along).distance_to(point) <= float(spec["width"]) or enemy == target:
					_strike(sim, enemy, damage, type_name)
					struck += 1
			sim.events.append({"kind": "shot", "weapon": "bolt", "from_x": origin.x, "from_y": origin.y,
				"x": end.x, "y": end.y, "pierced": struck})
		"shell":
			damage *= float(spec["scale"])
			_strike(sim, target, damage, type_name)
			for enemy: Dictionary in sim.enemies:
				if enemy == target or not _alive(enemy):
					continue
				if sim.position_of(enemy).distance_to(aim) <= float(spec["radius"]):
					_strike(sim, enemy, damage * float(spec["splash"]), type_name)
			sim._shot(origin, aim)
			sim.events.append({"kind": "blast", "x": aim.x, "y": aim.y, "radius": float(spec["radius"]), "side": "home"})
		"mark":
			_strike(sim, target, damage, type_name)
			target["lit"] = MARK_SECONDS
			sim._shot(origin, aim)
			sim.events.append({"kind": "mark", "id": int(target["id"]), "x": aim.x, "y": aim.y})
		"fire":
			for enemy: Dictionary in sim.enemies:
				if _alive(enemy) and sim.position_of(enemy).distance_to(origin) <= float(spec["radius"]):
					_strike(sim, enemy, damage, type_name)
					enemy["burn"] = BURN_SECONDS
					enemy["burn_dps"] = maxf(float(enemy.get("burn_dps", 0.0)), damage * BURN_SHARE)
			sim._shot(origin, aim)
			sim.events.append({"kind": "blast", "x": origin.x, "y": origin.y, "radius": float(spec["radius"]), "side": "fire"})
		_:
			_strike(sim, target, damage, type_name)
			sim._shot(origin, aim)
	b["cooldown"] = cooldown
	return true


static func _strike(sim, enemy: Dictionary, damage: float, source: String) -> void:
	var dealt: float = harm(sim, enemy, damage, source)
	sim.events.append({"kind": "hit", "x": float(enemy["x"]), "y": float(enemy["y"]), "amount": dealt, "friendly": false})


# Ballistas are siege-killers: the nearest engine in range first, then the nearest raider.
static func _ballista_target(sim, origin: Vector2, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var best_gap: float = INF
	for enemy: Dictionary in sim.enemies:
		if not _alive(enemy) or not SIEGE.has(str(enemy.get("role", ""))):
			continue
		var gap: float = origin.distance_to(sim.position_of(enemy))
		if gap <= reach and gap < best_gap:
			best_gap = gap
			best = enemy
	return best if not best.is_empty() else sim._tower_target(origin)


# Burning, marks and the warlord's rally. Runs once per raid tick before raiders act.
static func tick_raiders(sim, dt: float) -> void:
	var warlord: Dictionary = {}
	for enemy: Dictionary in sim.enemies:
		if _alive(enemy) and str(enemy.get("role", "")) == "warlord":
			warlord = enemy
	for enemy: Dictionary in sim.enemies:
		if not _alive(enemy):
			continue
		if float(enemy.get("lit", 0.0)) > 0.0:
			enemy["lit"] = maxf(0.0, float(enemy["lit"]) - dt)
		if float(enemy.get("burn", 0.0)) > 0.0:
			enemy["burn"] = maxf(0.0, float(enemy["burn"]) - dt)
			harm(sim, enemy, float(enemy.get("burn_dps", 0.0)) * dt, "fire-trap")
			if float(enemy["burn"]) <= 0.0:
				enemy.erase("burn_dps")
		enemy["rallied"] = not warlord.is_empty() and enemy != warlord \
			and sim.position_of(enemy).distance_to(sim.position_of(warlord)) <= RALLY_RADIUS


static func raider_damage(enemy: Dictionary, base: float) -> float:
	return base * (1.0 + RALLY_BONUS if bool(enemy.get("rallied", false)) else 1.0)


# --------------------------------------------------------------- siege


# A bombard with nothing to fight shells the nearest building within its reach:
# defenses and walls first, since those stand between the band and the Manor.
static func bombard_target(sim, enemy: Dictionary, reach: float) -> Dictionary:
	var here: Vector2 = sim.position_of(enemy)
	var best: Dictionary = {}
	var best_score: float = INF
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) <= 0.0 or float(b["remaining"]) > 0.0 or str(b["type"]) in ["trap", "fire-trap"]:
			continue
		var gap: float = sim._building_distance(here, b)
		if gap > reach:
			continue
		var stats: Dictionary = sim.building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]
		var score: float = gap
		if float(stats.get("damage", 0.0)) > 0.0 or str(b["type"]) in ["wall", "stonewall", "gate"]:
			score -= 3.0
		if score < best_score:
			best_score = score
			best = b
	return best


# Rams make for the nearest standing gate when there is one.
static func ram_target(sim, enemy: Dictionary) -> Dictionary:
	var here: Vector2 = sim.position_of(enemy)
	var best: Dictionary = {}
	var best_gap: float = INF
	for b: Dictionary in sim.buildings:
		if str(b["type"]) != "gate" or float(b["hp"]) <= 0.0:
			continue
		var gap: float = sim._building_distance(here, b)
		if gap < best_gap:
			best_gap = gap
			best = b
	return best


# --------------------------------------------------------------- warlords


static func warlord_wave(wave: int) -> bool:
	return wave >= WARLORD_EVERY and wave % WARLORD_EVERY == 0


static func warlord_name(faction: Dictionary) -> String:
	return str(faction.get("warlord", "The Warlord"))


# The living warlord of the current raid, or an empty dictionary.
static func warlord_of(sim) -> Dictionary:
	for enemy: Dictionary in sim.enemies:
		if float(enemy["hp"]) > 0.0 and str(enemy.get("role", "")) == "warlord":
			return enemy
	return {}


# The warlord's name, also after a reload mid-raid (the war log is not saved).
static func current_warlord_name(sim, enemy: Dictionary = {}) -> String:
	if not str(sim.war_log.get("warlord", "")).is_empty():
		return str(sim.war_log["warlord"])
	var faction_id: String = str(enemy.get("faction", "")) if not enemy.is_empty() else ""
	for entry: Dictionary in sim.world_specs.get("enemyFactions", []):
		if str(entry.get("id", "")) == faction_id:
			return warlord_name(entry)
	return "The Warlord"


# Called when the warlord falls: the rest of the band breaks and runs.
static func rout(sim, at: Vector2, faction_id: String = "") -> void:
	if str(sim.war_log.get("warlord", "")).is_empty():
		sim.war_log["warlord"] = current_warlord_name(sim, {"faction": faction_id})
	sim.war_log["warlord_slain"] = true
	var bounty: int = 40 + sim.wave * 15
	sim.war_log["bounty"] = bounty
	sim._reward({"gold": bounty})
	for enemy: Dictionary in sim.enemies:
		if _alive(enemy) and str(enemy.get("role", "")) != "warlord":
			enemy["routed"] = ROUT_SECONDS
			enemy["raids_resources"] = false
	sim.events.append({"kind": "warlord_fall", "x": at.x, "y": at.y, "bounty": bounty, "name": str(sim.war_log.get("warlord", ""))})
	sim.notice = "%s has fallen! The band breaks and runs. +%d gold bounty." % [str(sim.war_log["warlord"]), bounty]


# A routed raider runs for the nearest edge of the land and leaves. Returns true when gone.
static func flee(sim, enemy: Dictionary, dt: float) -> bool:
	enemy["routed"] = float(enemy["routed"]) - dt
	var here: Vector2 = sim.position_of(enemy)
	var bounds: Rect2i = sim.world_bounds()
	var exits: Array[Vector2] = [Vector2(bounds.position.x + 0.5, here.y), Vector2(bounds.end.x - 0.5, here.y),
		Vector2(here.x, bounds.position.y + 0.5), Vector2(here.x, bounds.end.y - 0.5)]
	var exit: Vector2 = exits[0]
	for point: Vector2 in exits:
		if here.distance_to(point) < here.distance_to(exit):
			exit = point
	if here.distance_to(exit) < 0.6 or float(enemy["routed"]) <= 0.0:
		return true
	var goal: Vector2 = sim._entry_point(exit)
	enemy["fx"] = goal.x
	enemy["fy"] = goal.y
	if not sim._walk(enemy, goal, dt, true):
		# No path out (walled in): the raider still slips away when its time runs out.
		enemy["phase"] = "idle"
	return false
