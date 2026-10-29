extends SceneTree

# War rules: each defense fights its own way, bombards shell from range, rams go for the
# gates, and a warlord leads every fourth wave; killing it breaks the band.
const Sim = preload("res://scripts/game/village_sim.gd")
const WarRules = preload("res://scripts/game/war_rules.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_volley()
	_bolt_pierces()
	_shell_splashes()
	_watchfire_marks()
	_fire_trap_burns()
	_bombard_shells_from_range()
	_ram_goes_for_gate()
	_warlord_spawns_and_rallies()
	_warlord_fall_routs_band()
	_warlord_save_round_trip()
	print("WARFARE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _bare() -> Variant:
	var sim = Sim.new()
	sim.units.clear()
	var hall: Dictionary = sim._hall()
	sim.buildings.clear()
	sim.buildings.append(hall)
	sim._invalidate()
	sim.raid_active = true
	sim.wave = 3
	sim.home_raid.begin(sim)
	return sim


func _raider(sim, x: float, y: float, role: String = "raider", hp: float = 500.0) -> Dictionary:
	var enemy: Dictionary = {"id": sim._id(), "type": "raider", "role": role, "raids_resources": false, "faction": "thornband",
		"x": x, "y": y, "hp": hp, "max_hp": hp, "phase": "walk", "cooldown": 5.0}
	sim.enemies.append(enemy)
	return enemy


func _defense(sim, type_name: String, x: int, y: int) -> Dictionary:
	var b: Dictionary = sim._new_building(type_name, x, y, false)
	sim.buildings.append(b)
	sim._invalidate()
	return b


func _stats(sim, b: Dictionary) -> Dictionary:
	return sim.building_specs[b["type"]]["tiers"][int(b["tier"]) - 1]


func _volley() -> void:
	var sim = _bare()
	var tower: Dictionary = _defense(sim, "archer_tower", 2, 2)
	var a: Dictionary = _raider(sim, 4.5, 2.5)
	var b: Dictionary = _raider(sim, 2.5, 5.5)
	check(WarRules.fire(sim, tower, _stats(sim, tower)), "the archer tower fires at raiders in range")
	check(float(a["hp"]) < 500.0 and float(b["hp"]) < 500.0, "an archer tower volley strikes two raiders")
	check(float(a["hp"]) < float(b["hp"]), "the second arrow of a volley hits softer")


func _bolt_pierces() -> void:
	var sim = _bare()
	var ballista: Dictionary = _defense(sim, "ballista", 2, 2)
	var near: Dictionary = _raider(sim, 4.0, 2.5)
	var far: Dictionary = _raider(sim, 6.0, 2.6)
	var aside: Dictionary = _raider(sim, 2.5, 6.0)
	WarRules.fire(sim, ballista, _stats(sim, ballista))
	check(float(near["hp"]) < 500.0 and float(far["hp"]) < 500.0, "a ballista bolt goes through every raider on its line")
	check(is_equal_approx(float(aside["hp"]), 500.0), "a ballista bolt misses raiders off its line")
	check(float(ballista["cooldown"]) > 1.0, "a ballista reloads slower than a tower")
	var ram: Dictionary = _raider(sim, 2.5, 5.0, "ram")
	ballista["cooldown"] = 0.0
	WarRules.fire(sim, ballista, _stats(sim, ballista))
	check(float(ram["hp"]) < 500.0, "a ballista picks a siege engine first")


func _shell_splashes() -> void:
	var sim = _bare()
	var bastion: Dictionary = _defense(sim, "bastion", 2, 2)
	var target: Dictionary = _raider(sim, 5.0, 2.5)
	var beside: Dictionary = _raider(sim, 5.6, 3.0)
	WarRules.fire(sim, bastion, _stats(sim, bastion))
	check(float(target["hp"]) < 500.0 and float(beside["hp"]) < 500.0, "a bastion shell bursts on raiders near the hit")
	check(float(beside["hp"]) > float(target["hp"]), "the burst hurts less than the direct hit")
	check(sim.events.any(func(e): return e.get("kind") == "blast"), "a bastion shell leaves a blast for the view")


func _watchfire_marks() -> void:
	var sim = _bare()
	var fire: Dictionary = _defense(sim, "watchfire", 2, 2)
	var target: Dictionary = _raider(sim, 4.5, 2.5)
	WarRules.fire(sim, fire, _stats(sim, fire))
	check(float(target.get("lit", 0.0)) > 0.0, "the watchfire marks the raider it hits")
	var before: float = float(target["hp"])
	var dealt: float = WarRules.harm(sim, target, 20.0, "tower")
	check(dealt > 20.0 and before - float(target["hp"]) > 20.0, "a marked raider takes more damage")
	WarRules.tick_raiders(sim, 6.0)
	check(float(target.get("lit", 0.0)) <= 0.0, "the mark wears off")


func _fire_trap_burns() -> void:
	var sim = _bare()
	var trap: Dictionary = _defense(sim, "fire-trap", 2, 2)
	var a: Dictionary = _raider(sim, 2.5, 2.5)
	var b: Dictionary = _raider(sim, 3.2, 2.9)
	WarRules.fire(sim, trap, _stats(sim, trap))
	check(float(a["hp"]) < 500.0 and float(b["hp"]) < 500.0, "a fire trap scorches every raider on it")
	var after_roar: float = float(a["hp"])
	WarRules.tick_raiders(sim, 1.0)
	check(float(a["hp"]) < after_roar, "a scorched raider keeps burning")
	check(float(sim.war_log["damage_by"].get("fire-trap", 0.0)) > 0.0, "the war log counts the fire trap's damage")


func _bombard_shells_from_range() -> void:
	var sim = _bare()
	var tower: Dictionary = _defense(sim, "tower", 10, 2)
	tower["cooldown"] = 99.0
	var bombard: Dictionary = _raider(sim, 14.5, 2.5, "bombard")
	bombard["cooldown"] = 0.0
	var start: Vector2 = sim.position_of(bombard)
	var hp: float = float(tower["hp"])
	sim._raid_tick(0.1)
	check(float(tower["hp"]) < hp, "a bombard shells a defense from range")
	check(sim.position_of(bombard).is_equal_approx(start), "a bombard in range stands and shells instead of walking up")
	check(sim.events.any(func(e): return e.get("kind") == "lob"), "the shell is drawn as a lob")


func _ram_goes_for_gate() -> void:
	var sim = _bare()
	var gate: Dictionary = _defense(sim, "gate", 4, 12)
	var ram: Dictionary = _raider(sim, 2.5, 13.5, "ram")
	check(WarRules.ram_target(sim, ram) == gate, "a ram makes for the gate")


func _warlord_spawns_and_rallies() -> void:
	var sim = Sim.new()
	sim.wave = WarRules.WARLORD_EVERY - 1
	sim._spawn_raid()
	var warlord: Dictionary = WarRules.warlord_of(sim)
	check(not warlord.is_empty(), "a warlord leads every fourth wave")
	check(float(warlord.get("max_hp", 0.0)) > float(sim.enemies[0]["max_hp"]) * 3.0, "the warlord is much tougher than its band")
	check(not str(sim.war_log["warlord"]).is_empty(), "the warlord has a name")
	check(sim.enemies.size() <= sim._max_raiders(), "a warlord raid still fits the save check")
	var quiet = Sim.new()
	quiet.wave = WarRules.WARLORD_EVERY
	quiet._spawn_raid()
	check(WarRules.warlord_of(quiet).is_empty(), "other waves have no warlord")
	var near: Dictionary = sim.enemies[0]
	near["x"] = float(warlord["x"]) + 1.0
	near["y"] = float(warlord["y"])
	WarRules.tick_raiders(sim, 0.1)
	check(bool(near.get("rallied", false)), "raiders near the warlord are rallied")
	check(WarRules.raider_damage(near, 10.0) > 10.0, "rallied raiders hit harder")


func _warlord_fall_routs_band() -> void:
	var sim = _bare()
	var warlord: Dictionary = _raider(sim, 3.5, 3.5, "warlord", 10.0)
	var other: Dictionary = _raider(sim, 1.5, 8.5)
	var gold_before: float = float(sim.pending_rewards.get("gold", 0.0))
	warlord["hp"] = 0.0
	sim._raid_tick(0.1)
	check(other.has("routed"), "when the warlord falls the band breaks")
	check(float(sim.pending_rewards.get("gold", 0.0)) > gold_before, "the warlord's fall pays a bounty")
	check(sim.events.any(func(e): return e.get("kind") == "warlord_fall"), "the fall is announced to the view")
	var steps: int = 0
	while sim.raid_active and steps < 400:
		sim._raid_tick(0.1)
		steps += 1
	check(not sim.raid_active, "the routed band leaves and the raid ends")
	check(int(sim.war_log["routed"]) >= 1, "the war log counts the raiders who fled")
	check(bool(sim.home_raid.last.get("defense_won", false)) and bool(sim.war_log.get("victory", false)), "breaking the band counts as holding the Manor")
	check(int(sim.war_log["slain"].get("warlord", 0)) == 1, "the war log counts the warlord among the slain")


func _warlord_save_round_trip() -> void:
	var sim = Sim.new()
	sim.wave = WarRules.WARLORD_EVERY * 2 - 1
	sim._spawn_raid()
	sim._raid_tick(0.1)
	var path: String = "user://test_warfare_save.json"
	check(sim.save_game(path), "a raid led by a warlord saves")
	var loaded = Sim.new()
	check(loaded.load_game(path), "a raid led by a warlord loads")
	check(not WarRules.warlord_of(loaded).is_empty(), "the warlord is still there after loading")
	check(not WarRules.current_warlord_name(loaded, WarRules.warlord_of(loaded)).is_empty(), "the warlord keeps a name after loading")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)
