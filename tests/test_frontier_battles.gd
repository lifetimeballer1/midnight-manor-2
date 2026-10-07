extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func crew(sim) -> Array[int]:
	var ids: Array[int] = []
	for u: Dictionary in sim.units:
		if sim.troop_specs[u["type"]]["role"] == "combat":
			ids.append(int(u["id"]))
	return ids


func _run() -> void:
	var sim = Sim.new()
	check(sim.get("frontier") != null, "separate frontier combat authority exists")
	if sim.get("frontier") != null:
		var ids: Array[int] = crew(sim)
		var food: float = sim.resources["food"]
		check(not sim.frontier.begin(sim, "starwatch-ridge", ids), "frontier waits for its campaign act")
		check(sim.resources["food"] == food, "blocked expedition spends nothing")
		sim.chronicle.act = 4
		check(not sim.frontier.begin(sim, "unknown-region", ids), "unknown region is rejected")
		check(not sim.frontier.begin(sim, "starwatch-ridge", [ids[0], ids[0]]), "duplicate crew member is rejected")
		check(sim.frontier.begin(sim, "starwatch-ridge", ids), "eligible real defenders can enter the first frontier map")
		check(sim.resources["food"] == food - 20.0, "expedition costs Food once")
		check(not sim.frontier.begin(sim, "whisperwood", ids), "only one expedition runs at a time")
		var elapsed: float = sim.elapsed
		var needs: Dictionary = sim.needs.state()
		sim.tick(1.0)
		check(sim.elapsed == elapsed and sim.needs.state() == needs, "active expedition freezes home time and meals")
		var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
		var restored = Sim.new()
		check(restored.restore_state(state), "active battle round-trips through JSON")
		check(restored.frontier.active["army"].size() == ids.size(), "loaded battle retains the selected crew")
		for index in 3600:
			restored.frontier.tick(0.05)
			if restored.frontier.active["status"] != "running": break
		check(restored.frontier.active["status"] == "won", "starting defenders can win the first patrol through real combat")
		check(restored.frontier.settle(restored), "won battle settles")
		check(restored.chronicle.region_state("starwatch-ridge") == "scouted", "battle victory advances only the earned region stage")
		check(restored.raid_stats["expeditions"] == 1, "won expedition feeds the campaign counter")
		var reward: float = restored.pending_rewards.get("gold", 0)
		check(not restored.frontier.settle(restored) and restored.pending_rewards.get("gold", 0) == reward, "settled battle cannot pay twice")
		check(restored.frontier.begin(restored, "whisperwood", crew(restored)), "a returned crew can begin another expedition")
		restored.frontier.withdraw()
		check(restored.frontier.settle(restored) and restored.chronicle.region_state("whisperwood") == "unseen", "retreat returns safely without granting victory")
		check(restored.raid_stats["expeditions"] == 1, "retreat is not counted as a completed expedition")
		var bad: Dictionary = state.duplicate(true)
		bad["frontier"]["active"]["army"][0]["hp"] = -1.0
		check(not restored.restore_state(bad), "invalid saved battle health is rejected")
		bad = state.duplicate(true)
		bad["frontier"]["active"]["region"] = "unknown-region"
		check(not restored.restore_state(bad), "invalid saved battle region is rejected")
		bad = state.duplicate(true)
		bad["frontier"]["active"]["army"][0]["id"] = 9999
		check(not restored.restore_state(bad), "saved battle cannot substitute an unknown home unit")
		check(ResourceLoader.exists("res://scenes/frontier_battle.tscn"), "frontier has a separate playable 3D scene")
		await test_scene()
	print("FRONTIER_BATTLES ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func test_scene() -> void:
	var scene: PackedScene = load("res://scenes/game.tscn")
	var game = scene.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.sim.chronicle.act = 4
	game._prepare_expedition("starwatch-ridge")
	game.left_pressed = true
	game.touches[0] = Vector2(200, 400)
	game._start_expedition()
	await process_frame
	check(is_instance_valid(game.battle_view) and not game.visible and not game.hud_root.visible, "launch switches into a separate battle scene and hides the home presentation")
	check(not game.left_pressed and game.touches.is_empty(), "battle transition clears unfinished home gestures")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(200, 400)
	touch.pressed = true
	game._input(touch)
	check(game.touches.is_empty(), "battle touches never enter the hidden home input handler")
	game._save_now()
	check(game.battle_view.get("save_status") != null, "battle screen exposes save feedback")
	if game.battle_view.get("save_status") != null:
		check(game.battle_view.save_status.text.contains("disabled"), "save-isolated battle gives visible save feedback")
	check(game.music.mood == "danger" and not game.music.calm, "battle save feedback does not switch music back to the hidden home mood")
	var elapsed: float = game.sim.elapsed
	game._process(1.0)
	check(game.sim.elapsed == elapsed, "battle scene does not advance the home clock")
	var battle = game.battle_view
	battle.set_process(false)
	battle.focused = true
	battle._burst(Vector3(14, 1, 11), Color.WHITE)
	var pool = battle.burst_pool
	var emitter: CPUParticles3D = pool.entries[0]["node"]
	check(emitter.global_position == battle.global_position + Vector3(14, 1, 11), "frontier bursts use the separate battlefield coordinate space")
	var clock: float = game.sim.frontier.active["clock"]
	battle._toggle_pause()
	battle._process(0.2)
	pool._process(2.0)
	check(game.sim.frontier.active["clock"] == clock and pool.active_count() == 1, "frontier pause freezes battle time and preserves bursts")
	battle._toggle_pause()
	battle.focused = false
	battle._process(0.2)
	pool._process(2.0)
	check(game.sim.frontier.active["clock"] == clock and pool.active_count() == 1, "focus loss freezes frontier time and bursts")
	battle.focused = true
	battle._process(0.0)
	pool._process(2.0)
	check(pool.active_count() == 0, "frontier resume releases expired bursts")
	var emitter_ids: Array = pool.get_children().map(func(node): return node.get_instance_id())
	for index in 100: battle._burst(Vector3(14, 1, 11), Color.WHITE)
	check(pool.get_children().map(func(node): return node.get_instance_id()) == emitter_ids, "frontier burst storms reuse the fixed emitter pool")
	pool.reset()
	battle._celebrate(true)
	check(pool.active_count() == 3, "frontier victory feedback uses three pooled bursts")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			var directory: String = argument.trim_prefix("--capture-dir=")
			if directory.is_absolute_path() and DirAccess.dir_exists_absolute(directory):
				game.battle_view.paused = true
				for width: int in [390, 1280]:
					DisplayServer.window_set_size(Vector2i(width, 844 if width == 390 else 800))
					await process_frame
					await process_frame
					await RenderingServer.frame_post_draw
					check(root.get_texture().get_image().save_png(directory.path_join("overhaul-frontier-%d.png" % width)) == OK, "native frontier capture succeeds")
	var snapshot: Dictionary = game.sim.export_state()
	game.battle_view._withdraw()
	game._return_from_frontier()
	await process_frame
	check(game.visible and game.hud_root.visible and game.sim.frontier.active.is_empty(), "return restores home camera and controls")
	check(not is_instance_valid(pool), "return frees the frontier emitter pool")
	check(game.sim.restore_state(snapshot), "an interrupted expedition can be restored")
	game._enter_village()
	await process_frame
	check(is_instance_valid(game.battle_view), "Continue resumes a saved expedition instead of stranding the village")
	if is_instance_valid(game.battle_view):
		game.battle_view._withdraw()
		game._return_from_frontier()
	game.queue_free()
	await process_frame
	await process_frame
