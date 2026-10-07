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


func emitters(game) -> Array:
	var pool: Variant = game.get("burst_pool")
	if pool is Node:
		return pool.get_children()
	return game.effect_nodes.filter(func(node): return is_instance_valid(node) and node is CPUParticles3D)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)
	var point: Vector3 = game.world_position(Vector2(4.0, 12.0), 1.2)
	game._impact_burst(point)
	var particles: Array = emitters(game)
	check(not particles.is_empty(), "impact has an emitter")
	for emitter: CPUParticles3D in particles:
		check(emitter.mesh != null, "every combat emitter has render geometry")
		if emitter.mesh != null:
			check(emitter.mesh.surface_get_material(0) != null, "combat geometry has a material")
	var ids: Array = particles.map(func(emitter): return emitter.get_instance_id())
	for index in 100:
		game._impact_burst(point)
	check(emitters(game).size() <= 12, "a burst storm stays within twelve allocated emitters")
	check(emitters(game).map(func(emitter): return emitter.get_instance_id()) == ids, "burst storm does not allocate new emitters")
	await create_timer(2.1).timeout
	game._consume_events()
	game._impact_burst(point, Color("dd705f"), 6)
	check(emitters(game).map(func(emitter): return emitter.get_instance_id()) == ids, "expired emitters are reused rather than destroyed")
	var pool: Variant = game.get("burst_pool")
	check(pool != null, "home impacts use a reusable pool")
	if pool != null:
		pool.paused = true
		var alive: int = pool.active_count()
		await create_timer(1.5).timeout
		check(pool.active_count() == alive, "pausing preserves live effects instead of expiring them")
		pool.paused = false
		await create_timer(2.1).timeout
		check(pool.active_count() == 0, "resuming releases all expired effects")
		check(pool.spawn(Vector3(INF, 0, 0)) == null, "nonfinite burst positions are rejected")
		check(pool.get_child_count() == ids.size(), "cleanup retains the bounded emitter allocation")
		await home_lifecycle(game, point)
	if DisplayServer.get_name() != "headless":
		await render_proof(game, point)
	game.queue_free()
	await process_frame
	await process_frame
	print("COMBAT_VFX ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func home_lifecycle(game, point: Vector3) -> void:
	game.focused = true
	game.paused = false
	game.burst_pool.paused = false
	game.burst_pool.reset()
	game.sim.events.append({"kind": "shot", "from_x": 4.0, "from_y": 12.0, "x": 5.0, "y": 12.0})
	game._consume_events()
	var projectile: Node3D = game.effect_nodes.back()
	var origin: Vector3 = projectile.position
	game._impact_burst(point)
	game.paused = true
	game._process(0.0)
	await create_timer(0.3).timeout
	check(is_instance_valid(projectile) and projectile.position == origin, "paused home projectiles stay frozen until resumed")
	check(game.burst_pool.active_count() == 1, "home pause preserves the live burst")
	game.paused = false
	game._process(0.0)
	await create_timer(0.3).timeout
	check(not is_instance_valid(projectile), "resumed projectile completes and cleans up")
	check(game.effect_tweens.is_empty(), "finished effects leave the tween registry immediately")
	check(game.burst_pool.active_count() >= 2, "resumed projectile lands through the impact pipeline")
	game._consume_events()
	game._confirm_new_game()
	check(game.burst_pool.active_count() == 0, "New Game resets active effects from the old village")
	game.sim.events.append({"kind": "shot", "from_x": 4.0, "from_y": 12.0, "x": 5.0, "y": 12.0})
	game._consume_events()
	game._confirm_new_game()
	check(game.effect_nodes.is_empty(), "New Game clears the old transient effect list")
	game.burst_pool.paused = false
	await create_timer(0.3).timeout
	check(game.burst_pool.active_count() == 0, "old projectile callbacks cannot spawn effects in the new village")
	for index in 12: game._impact_burst(point)
	for index in 30: game._poof(Vector2i(4, 12), Color.WHITE)
	check(game.effect_nodes.size() + game.burst_pool.active_count() == game.EFFECT_LIMIT, "bursts and other effects share the total decoration cap")
	game._confirm_new_game()
	await process_frame


func freeze_ambience(node: Node) -> void:
	if node is CPUParticles3D: node.speed_scale = 0.0
	if node is AnimationPlayer: node.pause()
	for child in node.get_children(): freeze_ambience(child)


func render_proof(game, point: Vector3) -> void:
	game.details.update(game, 0.0)
	freeze_ambience(game)
	for tween: Tween in get_processed_tweens(): tween.pause()
	var pool: Variant = game.get("burst_pool")
	if pool != null: pool.reset()
	await RenderingServer.frame_post_draw
	var before: Image = root.get_texture().get_image()
	var screen: Vector2 = game.camera.unproject_position(point)
	game._impact_burst(point, Color("ffd080"), 16, 1.6)
	var most_changed: int = 0
	var best: Image = before
	for index in 8:
		await create_timer(0.05).timeout
		await RenderingServer.frame_post_draw
		var after: Image = root.get_texture().get_image()
		var changed: int = 0
		for x in range(maxi(0, int(screen.x) - 80), mini(before.get_width(), int(screen.x) + 80)):
			for y in range(maxi(0, int(screen.y) - 100), mini(before.get_height(), int(screen.y) + 60)):
				var a: Color = before.get_pixel(x, y)
				var b: Color = after.get_pixel(x, y)
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.2: changed += 1
		if changed > most_changed:
			most_changed = changed
			best = after
	check(most_changed > 4, "real Compatibility renderer draws the transient impact")
	print("VFX_RENDER_CHANGED_PIXELS ", most_changed)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			var directory: String = argument.trim_prefix("--capture-dir=")
			if directory.is_absolute_path() and DirAccess.dir_exists_absolute(directory):
				check(best.save_png(directory.path_join("combat-impact-proof.png")) == OK, "impact proof capture succeeds")
