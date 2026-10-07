extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		printerr("FAIL ", text)


func step(sim, seconds: float) -> void:
	for tick in ceili(seconds / 0.05):
		sim.tick(0.05)


func tile_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x), floori(point.y))


func building(sim, type_name: String) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if b["type"] == type_name:
			return b
	return {}


func place(sim, type_name: String, x: int, y: int) -> Dictionary:
	var b: Dictionary = sim._new_building(type_name, x, y, false)
	sim.buildings.append(b)
	sim.revision += 1
	sim._invalidate()
	return b


func worker(sim, role: String, x: float, y: float) -> Dictionary:
	sim._add_unit(role)
	var u: Dictionary = sim.units.back()
	u["x"] = x
	u["y"] = y
	return u


func raider(sim, x: float, y: float, hp: float = 80.0) -> Dictionary:
	var enemy := {"id": sim._id(), "type": "raider", "x": x, "y": y, "hp": hp, "max_hp": hp,
		"phase": "idle", "cooldown": 0.0}
	sim.enemies.append(enemy)
	return enemy


func walkable(sim, start: Vector2, point: Vector2) -> bool:
	var goal := tile_of(point)
	return sim._inside(goal) and not sim._blocked(goal, false) and not sim.route(tile_of(start), goal).is_empty()


func work_spec() -> Dictionary:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/workplaces.json"))
	return parsed["workplaces"]


func _run() -> void:
	# --- declared stand and job data for every worked workplace type ---
	var spec: Dictionary = work_spec()
	for type_name in ["farm", "lumber", "timber_yard", "mine", "pond", "pasture"]:
		check(spec.has(type_name), "workplaces.json declares " + type_name)
		var sim = Sim.new()
		sim.units.clear()
		sim.buildings.clear()
		var site: Dictionary = place(sim, type_name, 8, 6)
		var stands: Array = spec[type_name]["stands"]
		check(stands.size() == 2, type_name + " declares two distinct stands")
		var footprint := Rect2i(8, 6, int(site["size"]), int(site["size"]))
		var points: Array[Vector2] = []
		for stand: Array in stands:
			var world: Vector2 = sim.center(site) + Vector2(float(stand[0]), float(stand[1]))
			points.append(world)
			check(sim._inside(tile_of(world)), type_name + " stand stays inside the 20x16 map")
			check(not footprint.has_point(tile_of(world)), type_name + " stand sits outside the footprint")
			check(not sim._blocked(tile_of(world), false), type_name + " stand is walkable ground")
			check(walkable(sim, Vector2(8.5, 12.5), world), type_name + " stand is reachable on foot")
		check(points[0] != points[1], type_name + " stands are different tiles")
		var job: Vector2 = sim.center(site) + Vector2(float(spec[type_name]["target"][0]), float(spec[type_name]["target"][1]))
		check(footprint.has_point(tile_of(job)), type_name + " job target sits at the actual work")
		check(sim.job_target(site).is_equal_approx(job), type_name + " job_target matches the data file")

	# --- two same-role workers reserve distinct reachable stands ---
	var sim = Sim.new()
	sim.units.clear()
	sim.buildings.clear()
	place(sim, "hall", 12, 9)
	var farm: Dictionary = place(sim, "farm", 8, 6)
	var first := worker(sim, "farmer", 8.0, 10.5)
	var second := worker(sim, "farmer", 8.6, 10.5)
	check(sim.assign(int(first["id"]), int(farm["id"])), "first crew member is posted to the farm")
	check(sim.assign(int(second["id"]), int(farm["id"])), "second crew member is posted to the farm")
	var stand_a: Vector2 = sim.work_position(first, farm)
	var stand_b: Vector2 = sim.work_position(second, farm)
	var declared: Array = spec["farm"]["stands"]
	check(stand_a.is_equal_approx(sim.center(farm) + Vector2(float(declared[0][0]), float(declared[0][1]))), "crew slot 0 takes the first declared stand")
	check(stand_b.is_equal_approx(sim.center(farm) + Vector2(float(declared[1][0]), float(declared[1][1]))), "crew slot 1 takes the second declared stand")
	check(stand_a != stand_b, "two same-role workers never share one stand")
	check(walkable(sim, Vector2(first["x"], first["y"]), stand_a), "first stand is reachable")
	check(walkable(sim, Vector2(second["x"], second["y"]), stand_b), "second stand is reachable")
	check(sim.work_position(first, farm) == stand_a and sim.work_position(second, farm) == stand_b, "reserved stands are stable across ticks")

	# --- a posted worker faces its job target once it arrives ---
	var crop := sim.job_target(farm)
	farm["reserve"] = 0.0
	var both_working: bool = false
	for tick in 200:
		sim.tick(0.05)
		if first["phase"] == "work" and second["phase"] == "work":
			both_working = true
			break
	check(both_working, "both crew members reach their stands and work")
	check(Vector2(first["x"], first["y"]).distance_to(stand_a) < 0.06, "first worker stands on its reserved tile")
	check(Vector2(second["x"], second["y"]).distance_to(stand_b) < 0.06, "second worker stands on its reserved tile")
	check(sim.facing_target(first).is_equal_approx(crop) and sim.facing_target(second).is_equal_approx(crop), "working farmers face the crop target")
	check(sim.facing_target(first) != sim.position_of(first), "facing target is the job, not the worker")

	# --- a blocked stand falls back to another reachable safe edge ---
	var blocked = Sim.new()
	blocked.units.clear()
	blocked.buildings.clear()
	place(blocked, "hall", 12, 9)
	var woods: Dictionary = place(blocked, "lumber", 8, 6)
	place(blocked, "wall", 9, 6)
	var fallback := worker(blocked, "lumberjack", 8.5, 12.5)
	blocked.assign(int(fallback["id"]), int(woods["id"]))
	var declared_stand: Vector2 = blocked.work_position(fallback, woods)
	check(tile_of(declared_stand) != Vector2i(9, 6), "declared lumber stand would be walled off")
	check(blocked._blocked(Vector2i(9, 6), false), "wall tile is blocked ground")
	check(declared_stand != Vector2(-1, -1) and not blocked._blocked(tile_of(declared_stand), false), "blocked workpoint falls back to another safe edge")
	check(declared_stand.distance_to(Vector2(9.5, 6.5)) > 0.01, "fallback edge is not the blocked stand")
	var fallback_works: bool = false
	for tick in 240:
		blocked.tick(0.05)
		if fallback["phase"] == "work":
			fallback_works = true
			break
	check(fallback_works, "fallback worker still reaches its workplace and works")
	check(Vector2(fallback["x"], fallback["y"]).distance_to(declared_stand) < 0.06, "fallback worker occupies the fallback edge")

	# --- a fully walled workplace makes the worker wait instead of faking work ---
	var sealed = Sim.new()
	sealed.units.clear()
	sealed.buildings.clear()
	place(sealed, "hall", 12, 9)
	var pond: Dictionary = place(sealed, "pond", 8, 6)
	for tile: Vector2i in [Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5), Vector2i(7, 6), Vector2i(10, 6),
			Vector2i(7, 7), Vector2i(10, 7), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8)]:
		place(sealed, "wall", tile.x, tile.y)
	var waiting := worker(sealed, "fisherman", 8.5, 12.5)
	sealed.assign(int(waiting["id"]), int(pond["id"]))
	var home := Vector2(waiting["x"], waiting["y"])
	check(sealed.work_position(waiting, pond) == Vector2(-1, -1), "no reachable stand means no work position")
	pond["reserve"] = 5.0
	var ever_worked: bool = false
	for tick in 120:
		sealed.tick(0.05)
		ever_worked = ever_worked or waiting["phase"] == "work"
	check(not ever_worked, "sealed-in worker waits instead of animating work")
	check(Vector2(waiting["x"], waiting["y"]) == home, "waiting worker holds position")
	check(float(waiting["carry"]) == 0.0, "waiting worker takes no goods")
	check(float(pond["reserve"]) >= 5.0, "waiting worker never harvests the workplace")

	# --- released and ordered-away workers do not perform work ---
	var absent = Sim.new()
	absent.units.clear()
	var mine_site: Dictionary = building(absent, "mine")
	var hired := worker(absent, "miner", 5.5, 6.5)
	absent.assign(int(hired["id"]), int(mine_site["id"]))
	var miner_works: bool = false
	for tick in 400:
		absent.tick(0.05)
		if hired["phase"] == "work":
			miner_works = true
			break
	check(miner_works, "miner starts working at the mine")
	check(absent.facing_target(hired).is_equal_approx(absent.job_target(mine_site)), "miner faces the mine mouth")
	hired["carry"] = 0.0
	hired["carry_resource"] = ""
	mine_site["reserve"] = 0.0
	check(absent.assign(int(hired["id"]), -1), "worker can be released from the mine")
	absent.job_timer = 0.0
	var stocked: float = 6.0
	mine_site["reserve"] = stocked
	step(absent, 2)
	check(hired["phase"] == "idle" and float(hired["carry"]) == 0.0, "released worker performs no work")
	check(float(mine_site["reserve"]) >= stocked, "released worker takes nothing from the workplace")
	check(absent.facing_target(hired).is_equal_approx(absent.position_of(hired)), "idle worker has no job facing")
	var ordered = Sim.new()
	ordered.units.clear()
	var farm_two: Dictionary = building(ordered, "farm")
	var marched := worker(ordered, "farmer", 8.0, 10.5)
	ordered.assign(int(marched["id"]), int(farm_two["id"]))
	farm_two["reserve"] = 6.0
	check(ordered.order_unit(int(marched["id"]), 1.5, 13.5), "manual order is accepted")
	step(ordered, 2)
	check(marched["phase"] != "work" and float(marched["carry"]) == 0.0, "ordered-away worker performs no work")
	check(float(farm_two["reserve"]) >= 6.0, "ordered-away worker leaves the workplace stock alone")

	# --- defenders prioritise threats on the Manor over threats on other structures ---
	var defend = Sim.new()
	defend.units.clear()
	defend.buildings.clear()
	place(defend, "hall", 9, 7)
	place(defend, "mine", 6, 2)
	var warrior := worker(defend, "warrior", 2.5, 2.5)
	var hall_threat := raider(defend, 8.5, 7.5)
	var mine_threat := raider(defend, 4.5, 3.5)
	var away_hall: float = Vector2(warrior["x"], warrior["y"]).distance_to(Vector2(8.5, 7.5))
	var away_mine: float = Vector2(warrior["x"], warrior["y"]).distance_to(Vector2(4.5, 3.5))
	check(away_mine < away_hall, "structure threat starts closer than the Manor threat")
	check(defend._threat_enemy(warrior) == hall_threat, "Manor threat outranks the closer structure threat")
	step(defend, 1)
	check(defend._threat_enemy(warrior) == hall_threat, "threat scoring is stable between ticks")
	check(Vector2(warrior["x"], warrior["y"]).distance_to(Vector2(8.5, 7.5)) < away_hall, "melee intercepts the Manor threat")
	check(defend.facing_target(warrior).is_equal_approx(Vector2(8.5, 7.5)), "fighting melee faces its chosen threat")
	defend.enemies.clear()
	defend._invalidate()
	step(defend, 1)
	check(Vector2(warrior["x"], warrior["y"]).distance_to(Vector2(4.5, 3.5)) < away_mine, "melee intercepts a lone structure threat")
	check(defend._threat_enemy(defend.units[0]) == {}, "no surviving threat means no autonomous target")

	# --- archers shoot at useful range, then retreat onto safe reachable ground ---
	var shoot = Sim.new()
	shoot.units.clear()
	shoot.buildings.clear()
	place(shoot, "hall", 9, 7)
	var archer := worker(shoot, "archer", 5.5, 5.5)
	var target_enemy := raider(shoot, 5.5, 8.5)
	step(shoot, 0.5)
	check(float(target_enemy["hp"]) < 80.0, "archer shoots an enemy at useful range")
	check(archer["phase"] == "attack", "archer attacks instead of closing distance")
	check(Vector2(archer["x"], archer["y"]) == Vector2(5.5, 5.5), "archer holds ground while the range is safe")
	var shots: int = 0
	for event: Dictionary in shoot.events:
		if event.get("kind") == "shot":
			shots += 1
	check(shots > 0, "archer shots are emitted as real events")
	check(shoot.facing_target(archer).is_equal_approx(Vector2(5.5, 8.5)), "attacking archer faces the struck enemy")
	target_enemy["x"] = 5.5
	target_enemy["y"] = 6.5
	shoot._invalidate()
	var before: Vector2 = Vector2(archer["x"], archer["y"])
	check(walkable(shoot, before, Vector2(5.5, 6.5)), "the close threat is a real reachable tile")
	step(shoot, 5)
	var after: Vector2 = Vector2(archer["x"], archer["y"])
	check(not after.is_equal_approx(before), "archer retreats when a threat closes inside 1.5 tiles")
	check(after.distance_to(Vector2(5.5, 6.5)) >= 1.5, "archer reopens the gap past the threat threshold")
	check(not shoot._blocked(tile_of(after), false), "retreat never enters a blocked tile")
	check(not shoot.route(tile_of(before), tile_of(after)).is_empty(), "retreat tile is reachable from the archer")
	var settled: Vector2 = after
	step(shoot, 4)
	check(Vector2(archer["x"], archer["y"]).distance_to(settled) < 0.2, "archer stops retreating once the gap is safe")
	check(bool(shoot.units[0]["kite"]) == false, "kiting hysteresis releases instead of oscillating")
	step(shoot, 2)
	check(not shoot._blocked(tile_of(Vector2(archer["x"], archer["y"])), false), "archer never ends a retreat inside a wall")

	# --- held defenders fight in range without moving ---
	var hold = Sim.new()
	hold.units.clear()
	var holder := worker(hold, "warrior", 4.5, 4.5)
	check(hold.order_unit(int(holder["id"]), 4.5, 4.5, true), "hold order is accepted")
	var held_enemy := raider(hold, 4.9, 4.5)
	step(hold, 1)
	check(float(held_enemy["hp"]) < 80.0, "held defender attacks an in-range threat")
	check(Vector2(holder["x"], holder["y"]) == Vector2(4.5, 4.5), "held defender never moves")
	check(bool(holder["hold"]) and not holder["order"].is_empty(), "manual hold is not dropped by combat")

	# --- manual orders outrank autonomous behaviour ---
	var march = Sim.new()
	march.units.clear()
	march.buildings.clear()
	place(march, "hall", 9, 7)
	var ordered_fighter := worker(march, "warrior", 4.5, 4.5)
	var pressed := raider(march, 4.8, 4.5)
	check(march.order_unit(int(ordered_fighter["id"]), 12.5, 12.5), "march order is accepted")
	step(march, 1)
	check(float(pressed["hp"]) == 80.0, "manual march order suppresses autonomous combat")
	check(Vector2(ordered_fighter["x"], ordered_fighter["y"]).distance_to(Vector2(4.5, 4.5)) > 1.0, "ordered fighter marches to its order")
	march.units[0]["order"] = []
	step(march, 2)
	check(float(pressed["hp"]) < 80.0, "autonomy resumes once the manual order is spent")

	# --- two workers whose declared stands are both blocked still hold different ground ---
	var twin = Sim.new()
	twin.units.clear()
	twin.buildings.clear()
	place(twin, "hall", 12, 9)
	var twin_farm: Dictionary = place(twin, "farm", 8, 6)
	var twin_footprint := Rect2i(8, 6, int(twin_farm["size"]), int(twin_farm["size"]))
	for tile: Vector2i in [Vector2i(9, 8), Vector2i(7, 6)]:
		place(twin, "wall", tile.x, tile.y)
	var blocked_a := worker(twin, "farmer", 7.5, 5.5)
	var blocked_b := worker(twin, "farmer", 7.5, 5.5)
	twin.assign(int(blocked_a["id"]), int(twin_farm["id"]))
	twin.assign(int(blocked_b["id"]), int(twin_farm["id"]))
	var twin_stand_a: Vector2 = twin.work_position(blocked_a, twin_farm)
	var twin_stand_b: Vector2 = twin.work_position(blocked_b, twin_farm)
	check(twin._blocked(Vector2i(9, 8), false) and twin._blocked(Vector2i(7, 6), false), "both declared farm stands are walled off")
	check(twin_stand_a.x >= 0 and twin_stand_b.x >= 0, "two blocked declared stands still resolve")
	check(twin_stand_a != twin_stand_b, "two workers never share the same fallback edge")
	check(int(blocked_a["slot"]) == 0 and int(blocked_b["slot"]) == 1, "crew slots are reserved by assigned worker")
	for point: Vector2 in [twin_stand_a, twin_stand_b]:
		check(not twin_footprint.has_point(tile_of(point)), "fallback edge sits outside the workplace footprint")
		check(not twin._blocked(tile_of(point), false), "fallback edge is walkable ground")
		check(walkable(twin, Vector2(7.5, 5.5), point), "fallback edge is reachable on foot")
	var twins_arrived: bool = false
	for tick in 400:
		twin.tick(0.05)
		if blocked_a["phase"] == "work" and blocked_b["phase"] == "work":
			twins_arrived = true
			break
	check(twins_arrived, "both fallback workers reach their own ground")
	check(tile_of(Vector2(blocked_a["x"], blocked_a["y"])) != tile_of(Vector2(blocked_b["x"], blocked_b["y"])), "both fallback workers physically stand apart")
	var settled_a: Vector2i = tile_of(Vector2(blocked_a["x"], blocked_a["y"]))
	step(twin, 2)
	check(tile_of(Vector2(blocked_a["x"], blocked_a["y"])) == settled_a, "held fallback ground is not traded or re-rolled mid-shift")

	# --- reservations are primitive per-unit state that survives save and load ---
	check(blocked_a["post"] == int(twin_farm["id"]) and blocked_b["post"] == int(twin_farm["id"]), "resolved reservation records its workplace on the unit")
	var twin_state: Dictionary = JSON.parse_string(JSON.stringify(twin.export_state()))
	check(twin_state["units"][0].has("slot") and twin_state["units"][0].has("sx") and twin_state["units"][0].has("sy"), "saved unit carries its slot and resolved stand")
	var reversed_state: Dictionary = twin_state.duplicate(true)
	reversed_state["units"].reverse()
	var reversed_sim = Sim.new()
	check(reversed_sim.restore_state(reversed_state), "save with reversed unit iteration still validates")
	var reversed_farm: Dictionary = reversed_sim.get_building(int(twin_farm["id"]))
	var reversed_a: Vector2 = reversed_sim.work_position(reversed_sim.get_unit(int(blocked_a["id"])), reversed_farm)
	var reversed_b: Vector2 = reversed_sim.work_position(reversed_sim.get_unit(int(blocked_b["id"])), reversed_farm)
	check(reversed_a == twin_stand_a and reversed_b == twin_stand_b, "reversed iteration restores each worker's own stand")
	check(reversed_a != reversed_b, "reversed iteration keeps the two stands distinct")
	var reused = Sim.new()
	step(reused, 6)
	reused.assign(int(reused.units[0]["id"]), -1)
	check(reused.restore_state(reversed_state), "an already-used simulation accepts the save")
	check(reused.units.size() == twin_state["units"].size(), "loading replaces the previous roster instead of merging it")
	var reused_a: Vector2 = reused.work_position(reused.get_unit(int(blocked_a["id"])), reused.get_building(int(twin_farm["id"])))
	var reused_b: Vector2 = reused.work_position(reused.get_unit(int(blocked_b["id"])), reused.get_building(int(twin_farm["id"])))
	check(reused_a == twin_stand_a and reused_b == twin_stand_b, "no stale reservation from the previous world leaks in")
	check(reused_a != reused_b, "reused simulation still resolves distinct stands")
	var tamper: Dictionary = reversed_state.duplicate(true)
	tamper["units"][0]["slot"] = 1.5
	check(not reused.restore_state(tamper), "fractional slot metadata is rejected")
	tamper = reversed_state.duplicate(true)
	tamper["units"][0]["post"] = int(twin_farm["id"]) + 977
	check(not reused.restore_state(tamper), "reservation pointing at another workplace is rejected")
	check(reused.restore_state(reversed_state), "the untampered save still loads after rejected attempts")
	twin.assign(int(blocked_a["id"]), -1)
	check(int(blocked_a["post"]) == -1 and int(blocked_a["slot"]) == 0 and float(blocked_a["sx"]) == -1.0, "releasing a worker frees its reservation")

	# --- an archer breaks from whatever is actually next to it, Manor threat or not ---
	var caught = Sim.new()
	caught.units.clear()
	caught.buildings.clear()
	place(caught, "hall", 9, 7)
	var pinned := worker(caught, "archer", 9.5, 8.5)
	var on_the_manor := raider(caught, 9.5, 7.1)
	var on_the_archer := raider(caught, 9.5, 9.4)
	check(caught._threat_enemy(pinned) == on_the_manor, "the raider on the Manor outranks the adjacent raider")
	check(Vector2(9.5, 8.5).distance_to(Vector2(9.5, 9.4)) <= 1.5, "the adjacent raider is inside the retreat trigger")
	var pinned_start: Vector2 = Vector2(9.5, 8.5)
	var away_manor: float = pinned_start.distance_to(Vector2(9.5, 7.1))
	var escape: bool = false
	for tick in 400:
		caught.tick(0.05)
		if Vector2(pinned["x"], pinned["y"]).distance_to(Vector2(9.5, 9.4)) >= 1.5:
			escape = true
			break
	check(escape, "archer breaks from an adjacent raider even while a Manor raider outranks it")
	check(not caught._blocked(tile_of(Vector2(pinned["x"], pinned["y"])), false), "escape never lands inside a blocked tile")
	check(caught.route(tile_of(pinned_start), tile_of(Vector2(pinned["x"], pinned["y"]))).size() > 0, "escape tile is reachable from where the archer stood")
	check(pinned["kite"] == true, "escape records the kiting decision")
	var settled_gap: float = Vector2(pinned["x"], pinned["y"]).distance_to(Vector2(9.5, 9.4))
	step(caught, 2)
	check(Vector2(pinned["x"], pinned["y"]).distance_to(Vector2(9.5, 9.4)) >= 1.5, "archer holds the opened gap instead of closing back in")
	check(Vector2(pinned["x"], pinned["y"]).distance_to(Vector2(9.5, 7.1)) >= away_manor - 0.01, "archer does not charge the Manor raider while escaping")
	caught.enemies.remove_at(caught.enemies.find(on_the_archer))
	caught._invalidate()
	var threat_hp: float = float(on_the_manor["hp"])
	step(caught, 1.5)
	check(float(on_the_manor["hp"]) < threat_hp, "with the close raider gone the archer shoots the Manor threat rather than charging")

	# --- retreat scanning is not capped: sealed tiles never hide a valid safe route ---
	var sealed_off = Sim.new()
	sealed_off.units.clear()
	sealed_off.buildings.clear()
	place(sealed_off, "hall", 14, 12)
	var boxed := worker(sealed_off, "archer", 9.5, 8.5)
	var boxed_enemy := raider(sealed_off, 9.5, 9.5)
	for pocket: Vector2i in [Vector2i(6, 5), Vector2i(12, 5)]:
		for wall_tile: Vector2i in [Vector2i(pocket.x - 1, pocket.y), Vector2i(pocket.x + 1, pocket.y), Vector2i(pocket.x, pocket.y - 1), Vector2i(pocket.x, pocket.y + 1)]:
			place(sealed_off, "wall", wall_tile.x, wall_tile.y)
	check(not sealed_off._walkable(tile_of(Vector2(9.5, 8.5)), Vector2(6.5, 5.5)), "sealed pocket tile is walkable ground but unreachable")
	check(not sealed_off._walkable(tile_of(Vector2(9.5, 8.5)), Vector2(12.5, 5.5)), "second sealed pocket tile is unreachable")
	var route_home: Vector2 = sealed_off._flee_point(boxed, boxed_enemy, 2.66)
	check(route_home.x >= 0, "a safe retreat route is still found past the unreachable tiles")
	check(sealed_off._walkable(tile_of(Vector2(9.5, 8.5)), route_home), "chosen retreat route is genuinely reachable")
	check(not sealed_off._blocked(tile_of(route_home), false), "chosen retreat route is walkable ground")
	var boxed_escape: bool = false
	for tick in 400:
		sealed_off.tick(0.05)
		if boxed["phase"] == "work" or boxed["kite"] == false and Vector2(boxed["x"], boxed["y"]).distance_to(Vector2(9.5, 9.5)) >= 1.5:
			boxed_escape = true
			break
	check(boxed_escape, "archer opens the gap with sealed tiles crowding the ranking")

	# --- walled siege never freezes: sealed hall retargets to nearest building ---
	var siege = Sim.new()
	var siege_hall: Dictionary = building(siege, "hall")
	var hx: int = int(siege_hall["x"])
	var hy: int = int(siege_hall["y"])
	var hs: int = int(siege_hall["size"])
	for x in range(hx - 1, hx + hs + 1):
		place(siege, "wall", x, hy - 1)
		place(siege, "wall", x, hy + hs)
	for y in range(hy, hy + hs):
		place(siege, "wall", hx - 1, y)
		place(siege, "wall", hx + hs, y)
	siege.raid_active = true
	raider(siege, 0.5, 0.5, 5000.0)
	var damaged: bool = false
	for tick in 1200:
		siege.tick(0.05)
		for b: Dictionary in siege.buildings:
			if float(b["hp"]) < float(b["max_hp"]):
				damaged = true
				break
		if damaged:
			break
	check(damaged, "sealed-hall raiders chew through nearby buildings instead of freezing")

	# --- saved unit fields roundtrip through the versioned save ---
	var saved = Sim.new()
	saved.units.clear()
	var saved_farm: Dictionary = building(saved, "farm")
	var keeper := worker(saved, "farmer", 8.0, 10.5)
	saved.assign(int(keeper["id"]), int(saved_farm["id"]))
	var keeper_works: bool = false
	for tick in 200:
		saved.tick(0.05)
		if keeper["phase"] == "work":
			keeper_works = true
			break
	check(keeper_works, "saved farmer is posted and working")
	var saved_archer := worker(saved, "archer", 5.5, 5.5)
	var kite_enemy := raider(saved, 5.5, 6.5)
	step(saved, 0.3)
	var stand_before: Vector2 = saved.work_position(saved.get_unit(int(keeper["id"])), saved_farm)
	var facing_before: Vector2 = saved.facing_target(saved.get_unit(int(keeper["id"])))
	check(saved_archer["kite"] == true and float(saved_archer["rx"]) >= 0.0, "close-range archer records a retreat goal")
	check(Vector2(saved_archer["x"], saved_archer["y"]).distance_to(Vector2(5.5, 6.5)) > 1.0, "archer has already moved off the threat")
	saved.enemies.clear()
	var state: Dictionary = JSON.parse_string(JSON.stringify(saved.export_state()))
	var restored = Sim.new()
	check(restored.restore_state(state), "extended unit state survives the JSON roundtrip")
	var loaded: Dictionary = restored.get_unit(int(keeper["id"]))
	if loaded.is_empty():
		printerr("Cannot continue: saved worker did not restore")
		quit(1)
		return
	check(is_equal_approx(float(loaded["fx"]), float(keeper["fx"])) and is_equal_approx(float(loaded["fy"]), float(keeper["fy"])), "recorded facing target roundtrips")
	check(restored.facing_target(loaded).is_equal_approx(facing_before), "facing target is unchanged after loading")
	check(bool(restored.get_unit(int(saved_archer["id"]))["kite"]) == bool(saved_archer["kite"]), "kiting flag roundtrips")
	check(is_equal_approx(float(restored.get_unit(int(saved_archer["id"]))["rx"]), float(saved_archer["rx"])), "retreat goal roundtrips")
	check(restored.work_position(loaded, restored.get_building(int(saved_farm["id"]))).is_equal_approx(stand_before), "reserved stand is stable after loading")
	var bad: Dictionary = state.duplicate(true)
	bad["units"][0]["fx"] = INF
	check(not restored.restore_state(bad), "non-finite facing target is rejected")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "Worker orientation on reserved stands, job facing targets, blocked-workpoint fallback, smart defensive prioritisation, archer kiting, order precedence and save roundtrip."}
	var report_file := FileAccess.open("res://docs/workers_defense_verification.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("WORKERS_DEFENSE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
