extends SceneTree

# Defenders engage raiders: raiders always enter on the land, fighters go for what they can
# reach, strike what is already in reach, and meet a walled-off raider at the nearest ground.
const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_spawns_on_land()
	_stray_raider_returns()
	_walled_fighter_moves_up()
	_strikes_attacker_in_reach()
	_prefers_reachable_raider()
	_north_reach_raid_resolves()
	print("RAID_ENGAGEMENT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _fighter(sim, type_name: String, x: float, y: float) -> Dictionary:
	sim._add_unit(type_name)
	var u: Dictionary = sim.units.back()
	u["x"] = x
	u["y"] = y
	return u


func _raider(sim, x: float, y: float, hp: float = 500.0) -> Dictionary:
	var enemy: Dictionary = {"id": sim._id(), "type": "raider", "role": "raider", "raids_resources": false, "faction": "thornband",
		"x": x, "y": y, "hp": hp, "max_hp": hp, "phase": "walk", "cooldown": 5.0}
	sim.enemies.append(enemy)
	return enemy


func _bare(sim) -> void:
	sim.units.clear()
	var hall: Dictionary = sim._hall()
	sim.buildings.clear()
	sim.buildings.append(hall)
	sim._invalidate()


func _spawns_on_land() -> void:
	for claim: Array in [["north"], ["south"], ["north", "south"], ["east"], []]:
		var sim = Sim.new()
		sim.expansions.assign(claim)
		sim._invalidate()
		sim.wave = 5
		sim._spawn_raid()
		var on_land: bool = true
		for enemy: Dictionary in sim.enemies:
			on_land = on_land and sim.in_world(sim.tile_of(enemy)) and not sim._blocked(sim.tile_of(enemy), true)
		check(on_land and sim.enemies.size() >= 4, "raiders enter on claimed land with %s held" % str(claim))
	var base = Sim.new()
	check(base._entry_point(Vector2(0.5, 3.5)) == Vector2(0.5, 3.5), "a spawn already on the land is left where it was")


func _stray_raider_returns() -> void:
	var sim = Sim.new()
	sim.expansions.append("north")
	sim._invalidate()
	sim.raid_active = true
	var stray: Dictionary = _raider(sim, 29.5, 4.5)
	sim._raid_tick(0.1)
	check(sim.in_world(sim.tile_of(stray)), "a raider saved off the land steps back onto it")


func _walled_fighter_moves_up() -> void:
	var sim = Sim.new()
	_bare(sim)
	for x in range(1, 6):
		for y in range(1, 6):
			if x == 1 or y == 1 or x == 5 or y == 5:
				sim.buildings.append(sim._new_building("wall", x, y, false))
	sim._invalidate()
	var warrior: Dictionary = _fighter(sim, "warrior", 2.5, 2.5)
	var raider: Dictionary = _raider(sim, 8.5, 3.5)
	sim.raid_active = true
	var start: float = sim.position_of(warrior).distance_to(sim.position_of(raider))
	for i in 30:
		sim.tick_count += 1
		sim._unit_tick(warrior, 0.1)
	check(sim.position_of(warrior).distance_to(sim.position_of(raider)) < start - 0.5, "a walled-in fighter moves up to the wall nearest the raider")
	check(sim.position_of(warrior).x > 3.4, "the walled-in fighter stands at the wall facing the raider")


func _strikes_attacker_in_reach() -> void:
	var sim = Sim.new()
	_bare(sim)
	var hall: Dictionary = sim._hall()
	var warrior: Dictionary = _fighter(sim, "warrior", 2.5, 13.5)
	warrior["hold"] = true
	warrior["order"] = [2.5, 13.5]
	# A raider at the Manor outranks the one beside the warrior, yet the warrior is held.
	var far: Dictionary = _raider(sim, float(hall["x"]) - 0.5, float(hall["y"]) + 0.5)
	var near: Dictionary = _raider(sim, 3.2, 13.5)
	sim.raid_active = true
	sim.tick_count += 1
	sim._unit_tick(warrior, 0.1)
	check(float(near["hp"]) < float(near["max_hp"]) and is_equal_approx(float(far["hp"]), float(far["max_hp"])), "a held fighter strikes the raider already in reach")
	var free: Dictionary = _fighter(sim, "warrior", 3.2, 12.7)
	free["cooldown"] = 0.0
	var before: float = float(near["hp"])
	sim.tick_count += 1
	sim._unit_tick(free, 0.1)
	check(float(near["hp"]) < before, "a free fighter strikes an attacker beside it before chasing the Manor's")


func _prefers_reachable_raider() -> void:
	var sim = Sim.new()
	_bare(sim)
	var hall: Dictionary = sim._hall()
	# A raider sealed in a walled pen right at the Manor, and one in the open field.
	for x in range(13, 18):
		for y in range(10, 15):
			if x == 13 or y == 10 or x == 17 or y == 14:
				sim.buildings.append(sim._new_building("wall", x, y, false))
	sim._invalidate()
	var sealed: Dictionary = _raider(sim, 15.5, 12.5)
	var open: Dictionary = _raider(sim, 3.5, 3.5)
	var warrior: Dictionary = _fighter(sim, "warrior", 8.5, 12.5)
	sim.raid_active = true
	sim.tick_count += 1
	check(sim._threat_enemy(warrior) == open, "a fighter goes for the raider it can reach")
	check(not hall.is_empty() and sim.friendly_area(sim.position_of(sealed)) != sim.friendly_area(sim.position_of(warrior)), "walls split the defenders' ground")


func _north_reach_raid_resolves() -> void:
	var sim = Sim.new()
	sim.expansions.append("north")
	sim._invalidate()
	sim.wave = 2
	for i in 4:
		var u: Dictionary = _fighter(sim, "warrior", 9.5, 12.5)
		u["level"] = 5
		u["hp"] = sim._stat(u, "hp")
		u["max_hp"] = u["hp"]
	sim.completed_quests.append("the-first-horn")
	sim.elapsed = 1000.0
	sim.next_raid_at = 1000.0
	sim.raid_warning = true
	var raided: bool = false
	for i in 1800:
		sim.tick(0.1)
		raided = raided or sim.raid_active
		if raided and not sim.raid_active:
			break
	check(raided and not sim.raid_active, "a raid with the North Reach held ends instead of freezing")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)
