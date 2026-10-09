extends SceneTree

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)
	check(game.has_method("_clash_hit") and game.has_method("_hit_stop"), "the scene root includes the clash layer")
	check(is_equal_approx(Engine.time_scale, 1.0), "time starts at full speed")

	# A kill freezes time for a blink, and time always comes back.
	game._last_stop_ms = -10000
	game.sim.events.append({"kind": "fall", "x": 6.0, "y": 6.0, "side": "foe"})
	game._read_clash_events()
	check(Engine.time_scale < 0.2, "a kill triggers a hit-stop")
	check(game.sim.events[0].has("clash"), "a read event is marked so it is never read twice")
	game._restore_time()
	check(is_equal_approx(Engine.time_scale, 1.0), "time is restored after the freeze")
	game._hit_stop(0.04)
	check(is_equal_approx(Engine.time_scale, 1.0), "freezes are rate-limited so a melee does not stutter")
	game._last_stop_ms = -10000
	game._slow_active = false

	# Marked events are not replayed.
	var before_effects: int = game.effect_nodes.size()
	game._read_clash_events()
	check(game.effect_nodes.size() == before_effects, "an already-read event adds nothing")
	game._restore_time()
	game.sim.events.clear()

	# A held raid eases through a slow beat and a vignette, then returns to full speed.
	game.sim.events.append({"kind": "raid_result", "victory": true})
	game._read_clash_events()
	check(Engine.time_scale < 0.5 and Engine.time_scale > 0.2, "a held raid slows time for a beat")
	check(game._vignette_layer != null and game._vignette_layer.visible, "a held raid flashes the vignette")
	game._slow_end_ms = Time.get_ticks_msec() - 1
	game._update_time_scale()
	check(is_equal_approx(Engine.time_scale, 1.0) and not game._slow_active, "the beat ends at full speed")
	game.sim.events.clear()

	# A melee blow makes the attacker lunge, then settle back exactly.
	var fighter: Dictionary = {}
	for u: Dictionary in game.sim.units:
		if float(u["hp"]) > 0.0 and str(u["type"]) != "archer":
			fighter = u
			break
	check(not fighter.is_empty(), "the village has a melee fighter")
	if not fighter.is_empty():
		game._update_actors(0.0)
		var here: Vector2 = game.sim.position_of(fighter)
		var target := here + Vector2(1.0, 0.0)
		fighter["phase"] = "attack"
		fighter["fx"] = target.x
		fighter["fy"] = target.y
		game._clash_hit(target, false)
		var id: int = int(fighter["id"])
		check(game._swings.has(id), "a melee blow starts a swing on the attacker")
		game._update_actors(0.05)
		var model: Node3D = game.actors[id]["model"]
		var rest: Vector3 = game.world_position(game.sim.position_of(fighter))
		check(model.position.distance_to(rest) > 0.05, "the attacker lunges toward the target")
		check(absf(model.rotation.x) > 0.01, "the attacker leans into the blow")
		game._update_actors(1.0)
		check(not game._swings.has(id), "the swing ends")
		check(model.position.distance_to(game.world_position(game.sim.position_of(fighter))) < 0.01, "the attacker returns to its place")
		check(is_zero_approx(model.rotation.x), "the lean is reset")

	# Damage numbers merge when blows land close together, and stay capped.
	game._damage_number(Vector2(8.0, 8.0), 10.0, false)
	game._damage_number(Vector2(8.2, 8.0), 5.0, false)
	check(game._numbers.size() == 1, "close blows share one number")
	check((game._numbers[0]["label"] as Label3D).text == "15", "merged numbers add up")
	for index in 12:
		game._damage_number(Vector2(float(index) * 2.0, 3.0), 4.0, true)
	check(game._numbers.size() <= game.NUMBER_MAX, "damage numbers are capped")

	# Effects respect the shared budget.
	for index in 40:
		game._spirit_release(Vector2(5.0, 5.0), true)
		game._chips(Vector3(3.0, 1.0, 3.0))
	check(game.effect_nodes.size() <= game.EFFECT_LIMIT + 1, "effects stay inside the decoration budget")

	Engine.time_scale = 1.0
	print("CLASH ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
