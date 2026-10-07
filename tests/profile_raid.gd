extends SceneTree

var samples: Dictionary = {}
var draw_calls: Dictionary = {}
var cpu_times: Dictionary = {}
var report_path: String = ""
var capture_directory: String = ""


func _initialize() -> void:
	_run.call_deferred()


func percentile(values: Array, fraction: float) -> float:
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, ceili(sorted.size() * fraction) - 1)])


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report=res://docs/") and not ".." in argument:
			report_path = argument.trim_prefix("--report=")
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
	root.size = Vector2i(1280, 800)
	Engine.max_fps = 60
	var game = load("res://scenes/game.tscn").instantiate()
	game.sim = load("res://tests/raid_profile_sim.gd").new()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.music.set_enabled(false)
	var menu: Node = root.get_node_or_null("DebugMenu")
	if menu != null: menu.set("style", 2)
	var start: int = Time.get_ticks_usec()
	var previous: int = start
	var triggered: bool = false
	var combat_seen: bool = false
	var recovery_started: int = 0
	var peak_effects: int = 0
	var peak_emitters: int = 0
	var largest_frame: Dictionary = {}
	while Time.get_ticks_usec() - start < 28000000:
		await process_frame
		# The fixture owns focus, not a player's session; benchmark time never
		# changes a real save and is not paused by the terminal taking focus.
		game.focused = true
		var now: int = Time.get_ticks_usec()
		var frame_ms: float = float(now - previous) / 1000.0
		previous = now
		if now - start < 1000000: continue
		if not triggered and now - start >= 3000000:
			triggered = game.sim.start_raid()
		var phase: String = "quiet"
		if game.sim.raid_warning: phase = "warning"
		elif game.sim.raid_active:
			phase = "combat"
			combat_seen = true
		elif combat_seen:
			phase = "recovery"
			if recovery_started == 0: recovery_started = now
		if not samples.has(phase):
			samples[phase] = []
			draw_calls[phase] = []
			cpu_times[phase] = []
		samples[phase].append(frame_ms)
		draw_calls[phase].append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		cpu_times[phase].append(1000.0 * Performance.get_monitor(Performance.TIME_PROCESS))
		peak_effects = maxi(peak_effects, game.effect_nodes.size() + game.burst_pool.active_count())
		peak_emitters = maxi(peak_emitters, game.burst_pool.get_child_count())
		if frame_ms > float(largest_frame.get("ms", 0.0)):
			largest_frame = {"ms": frame_ms, "cpu_process_ms": cpu_times[phase].back(), "phase": phase, "enemies": game.sim.enemies.size(), "effects": game.effect_nodes.size() + game.burst_pool.active_count(), "draw_calls": draw_calls[phase].back()}
		if recovery_started > 0 and now - recovery_started >= 2000000: break
	var phases: Dictionary = {}
	for phase: String in samples:
		var values: Array = samples[phase]
		var over_budget: int = 0
		for value: float in values:
			if value > 33.333: over_budget += 1
		phases[phase] = {"frames": values.size(), "median_ms": percentile(values, 0.5), "p95_ms": percentile(values, 0.95), "p99_ms": percentile(values, 0.99), "max_ms": values.max(), "over_33ms_percent": 100.0 * over_budget / values.size(), "peak_draw_calls": draw_calls[phase].max(), "cpu_process_p95_ms": percentile(cpu_times[phase], 0.95)}
	var result: Dictionary = {"renderer": DisplayServer.get_name(), "window": "1280x800", "fps_cap": Engine.max_fps, "scenario": "fresh village, real first Horn raid, no resource/health grants", "combat_seen": combat_seen, "raid_finished": combat_seen and not game.sim.raid_active, "peak_effects": peak_effects, "allocated_burst_emitters": peak_emitters, "worst_tick_ms": game.sim.worst_tick_us / 1000.0, "worst_route_ms": game.sim.worst_route_us / 1000.0, "route_queries": game.sim.route_queries, "largest_frame": largest_frame, "phases": phases, "scope": "instrumented native desktop fixture, no GPU readbacks/file writes during samples, not browser/phone certification"}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(result, "\t"))
	print("RAID_PROFILE ", JSON.stringify(result))
	if DisplayServer.get_name() != "headless" and capture_directory.is_absolute_path() and DirAccess.dir_exists_absolute(capture_directory):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join("raid-profile-recovery.png"))
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if result["raid_finished"] else 1)
