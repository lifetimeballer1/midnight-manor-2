extends SceneTree

# Walls and defenses presentation layer (village_defenses.gd): joined wall runs, manned towers,
# firing / hit / damage / collapse animation. Visual only, so it also checks the sim is untouched.
#   godot --headless --path . --script res://tests/test_defenses.gd -- --no-save

var checks: int = 0
var failures: Array[String] = []
var game
var sim


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func place(type_name: String, x: int, y: int) -> Dictionary:
	var other: Dictionary = sim.building_at(x, y)
	if not other.is_empty():
		sim.buildings.erase(other)
	var b: Dictionary = sim._new_building(type_name, x, y, false)
	sim.buildings.append(b)
	return b


func state(b: Dictionary) -> Dictionary:
	return game._def.get(int(b["id"]), {})


func body_scale(node: Node3D) -> float:
	for part: MeshInstance3D in game._def_parts(node):
		if "ground" not in str(part.name).to_lower():
			return part.scale.x
	return 0.0


func settle(frames: int = 3) -> void:
	for i in frames:
		await process_frame


func snapshot() -> String:
	var rows: Array = []
	for b: Dictionary in sim.buildings:
		rows.append([b["id"], b["type"], b["x"], b["y"], b["hp"], b["tier"]])
	return JSON.stringify(rows)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.focused = true
	game.paused = false
	sim = game.sim
	await settle()
	check(game.get("_def") is Dictionary, "the game scene runs the defense layer")
	check(game.model_asset("fire-trap", 1) == "fire_trap_t1", "the fire trap shows its own model, not the mine")

	# A palisade run with a gate, turning a corner, and a pair of ramparts.
	var run: Array = [place("wall", 2, 2), place("wall", 3, 2), place("gate", 4, 2), place("wall", 5, 2), place("wall", 2, 3), place("wall", 2, 4)]
	var tower: Dictionary = place("archer_tower", 4, 5)
	var ballista: Dictionary = place("ballista", 6, 5)
	var trap: Dictionary = place("trap", 4, 7)
	var rampart: Dictionary = place("rampart", 8, 2)
	sim.revision += 1
	sim._invalidate()
	await settle()
	for b: Dictionary in run + [tower, ballista, trap, rampart]:
		check(not state(b).is_empty(), "%s at %d,%d is dressed" % [b["type"], b["x"], b["y"]])
	var middle: Dictionary = state(run[1])
	var length: float = game._def_body_length(middle["model"]) * (middle["model"] as Node3D).scale.x
	check(absf(body_scale(middle["model"]) * length - 2.02) < 0.05, "a piece inside a run spans the whole tile")
	check(body_scale(state(run[2])["model"]) > 1.2, "a gate set in a run stretches to meet the walls")
	var corner: Dictionary = state(run[0])
	check(corner.has("arms") and (corner["arms"] as Node3D).get_child_count() == 1, "a corner grows one arm for its second run")
	var joins: Variant = game.building_views[int(run[1]["id"])].get("joins")
	check(joins == null or not (joins as Node3D).visible, "the old flat connector rails are hidden")
	check(absf((corner["model"] as Node3D).rotation.y) < 0.01, "a north wall faces its fence outward")
	var lone_signature: String = game._view_signature(rampart)
	var rampart_two: Dictionary = place("rampart", 9, 2)
	check(game._view_signature(rampart) != lone_signature, "a rampart rebuilds when a rampart rises beside it")
	sim.revision += 1
	await settle()
	check(body_scale(state(rampart)["model"]) > 1.0, "ramparts join into a run too")

	# Manned towers.
	var tower_state: Dictionary = state(tower)
	check(tower_state.has("sentry") and is_instance_valid(tower_state["sentry"]), "an archer tower is manned")
	check(not state(ballista).has("sentry"), "a ballista keeps its own crossbow and no sentry")
	check(game._def_sentries <= game.DEF_SENTRY_MAX, "sentries stay within the cap")

	var before: String = snapshot()
	# Firing: the tower kicks, then settles back to rest.
	var from: Vector2 = sim.center(tower)
	sim.events.append({"kind": "shot", "from_x": from.x, "from_y": from.y, "x": from.x, "y": from.y - 3.0})
	await settle(2)
	check(float(tower_state["kick"]) > 0.0 or bool(tower_state.get("moved", false)), "a tower shot starts the kick")
	var player: AnimationPlayer = tower_state.get("player")
	check(player == null or player.current_animation == "attack", "the sentry draws when the tower fires")
	await create_timer(0.9).timeout
	await settle(2)
	check((tower_state["pivot"] as Node3D).transform.is_equal_approx(Transform3D.IDENTITY), "the tower settles back to rest")
	check(player == null or player.current_animation == "idle", "the sentry returns to idle")

	# Traps snap instead of shooting an arrow.
	var effects: int = game.effect_nodes.size()
	var trap_at: Vector2 = sim.center(trap)
	sim.events.append({"kind": "shot", "from_x": trap_at.x, "from_y": trap_at.y, "x": trap_at.x, "y": trap_at.y})
	await settle(2)
	check(game.effect_nodes.size() <= effects, "a trap throws no arrow")
	check(float(state(trap)["snap"]) > 0.0, "a trap's spikes snap up")

	# The ballista fires its own bolt from the top.
	var ballista_at: Vector2 = sim.center(ballista)
	effects = game.effect_nodes.size()
	game._launch_arrow(game.world_position(ballista_at, 1.8), game.world_position(ballista_at + Vector2(0, -3), 1.0), false)
	check(game.effect_nodes.size() == effects + 1, "a ballista launches one bolt")
	if game.effect_nodes.size() > effects:
		check((game.effect_nodes.back() as Node3D).position.y > 1.8, "the bolt leaves the top of the ballista")

	# Hit: a struck wall shudders.
	var struck: Vector2 = sim.center(run[3])
	sim.events.append({"kind": "hit", "x": struck.x, "y": struck.y, "amount": 5.0, "friendly": true})
	await settle(2)
	check(float(state(run[3])["shake"]) > 0.0, "a struck wall shudders")
	check(snapshot() == before, "animations never change the sim's buildings")

	# Damage: below half health a defense leans; destruction leaves rubble until repaired.
	tower["hp"] = float(tower["max_hp"]) * 0.2
	await create_timer(0.6).timeout
	check(float(tower_state["lean_goal"]) > 0.0 and float(tower_state["lean"]) > 0.0, "a badly damaged tower starts to lean")
	effects = game.effect_nodes.size()
	run[0]["hp"] = 0.0
	sim._ruin(sim.center(run[0]))
	await settle(2)
	check(game.effect_nodes.size() > effects, "a falling wall topples as a transient copy")
	await create_timer(0.4).timeout
	check(corner["rubble"] != null and is_instance_valid(corner["rubble"]), "a ruined wall leaves rubble")
	check(not (corner["arms"] as Node3D).visible, "a ruined corner hides its arm")
	run[0]["hp"] = run[0]["max_hp"]
	await create_timer(0.4).timeout
	await settle(2)
	var repaired: Dictionary = state(run[0])
	check(repaired.is_empty() or repaired["rubble"] == null, "repairing clears the rubble")

	# Pause holds every pose.
	game.paused = true
	sim.paused = true
	sim.events.append({"kind": "shot", "from_x": from.x, "from_y": from.y, "x": from.x, "y": from.y - 3.0})
	await create_timer(0.2).timeout
	var held: Transform3D = (tower_state["pivot"] as Node3D).transform
	await create_timer(0.3).timeout
	check(float(tower_state["kick"]) > 0.0, "a shot while paused waits to play")
	check((tower_state["pivot"] as Node3D).transform.is_equal_approx(held), "a paused village holds defense poses")
	game.paused = false

	game.queue_free()
	await settle(2)
	print("DEFENSES ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
