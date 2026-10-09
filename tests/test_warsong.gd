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


func drum_kinds(game, intensity: float) -> Array:
	game._war_last.clear()
	game._intensity = intensity
	for bar in 2:
		for step in 6:
			game._drum_step(step, bar)
			game._war_last.erase("")
	var kinds: Array = []
	for kind: String in ["taiko_lo", "tom", "rattle", "brass"]:
		if game._war_last.has(kind):
			kinds.append(kind)
	return kinds


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)
	game.sound = true
	game._setup_war_audio()
	game._war_ready = true
	check(game.has_method("_war_hit") and game.has_method("_clash_hit"), "the scene root includes the warsong layer over the clash layer")

	# Every sound renders to real, loud-enough, non-clipping audio.
	for kind: String in game.PREWARM:
		var stream: AudioStreamWAV = game._stream(kind, game._brass_root() if kind == "brass" else 0.0)
		check(stream != null and stream.data.size() > 400, kind + " renders audio")
		var peak: int = 0
		var silent: bool = true
		for i in range(0, stream.data.size() - 1, 2):
			var value: int = absi(stream.data.decode_s16(i))
			peak = maxi(peak, value)
			if value > 600:
				silent = false
		check(not silent, kind + " is not silent")
		check(peak <= 32767, kind + " does not clip")
		check(game.WAR_DB.has(kind), kind + " has a level")

	# Every sound has a kit of real recorded layers, and every file in it loads.
	check(game.KITS.size() == game.WAR_DB.size(), "every sound has a kit")
	for kind: String in game.KITS:
		check(not (game.KITS[kind] as Array).is_empty(), kind + " has layers")
		for layer: Dictionary in game.KITS[kind]:
			for path: String in game._layer_paths(layer):
				check(game._sample(path) != null, "sample loads: " + path.get_file())

	# Playing a kit starts real voices.
	game._war_last.clear()
	game._voice("axe")
	var started_voices: int = 0
	for player: AudioStreamPlayer in game._war_voices:
		if player.playing and player.stream != null:
			started_voices += 1
	check(started_voices >= 1, "an axe blow starts a recorded sample")

	# Weapons map to distinct sounds.
	check(game._weapon_of({"role": "ram"}, true) == "ram", "a ram sounds like a ram")
	check(game._weapon_of({"role": "bombard"}, true) == "bombard", "a bombard booms")
	check(game._weapon_of({"role": "breaker"}, true) == "hammer", "a breaker swings a hammer")
	check(game._weapon_of({"role": "archer"}, true) == "bow", "raider archers twang")
	check(game._weapon_of({"role": "raider", "id": 2}, true) == "axe" and game._weapon_of({"role": "raider", "id": 3}, true) == "sword", "raiders carry axes and swords")
	check(game._weapon_of({"type": "pikewoman"}, false) == "spear", "pikes thrust")
	check(game._weapon_of({"type": "halberdier"}, false) == "halberd", "halberds chop")
	check(game._weapon_of({"type": "longbowman"}, false) == "bow", "longbows twang")
	check(game._weapon_of({"type": "warrior"}, false) == "sword", "warriors ring steel")

	# A melee blow is voiced by its weapon, plus the flesh under it; a rate gap holds a crowd back.
	var fighter: Dictionary = {}
	for u: Dictionary in game.sim.units:
		if float(u["hp"]) > 0.0 and str(u["type"]) != "archer":
			fighter = u
			break
	if not fighter.is_empty():
		var here: Vector2 = game.sim.position_of(fighter)
		var target := here + Vector2(1.0, 0.0)
		fighter["phase"] = "attack"
		fighter["fx"] = target.x
		fighter["fy"] = target.y
		var expected: String = game._weapon_of(fighter, false)
		game._war_last.clear()
		game.sim.events.append({"kind": "hit", "x": target.x, "y": target.y, "amount": 10.0, "friendly": false})
		game._read_war_events()
		check(game._war_last.has(expected), "a melee blow plays its weapon sound (" + expected + ")")
		check(game._war_last.has("flesh"), "a melee blow on a person plays flesh")
		var stamp: int = int(game._war_last[expected])
		game._voice(expected)
		check(int(game._war_last[expected]) == stamp, "a repeat inside its gap is held back")
		game.sim.events.clear()

	# Falls grunt, collapses crash, a lost raid plays funeral drums.
	game._war_last.clear()
	game.sim.events.append({"kind": "fall", "x": 6.0, "y": 6.0, "side": "foe"})
	game.sim.events.append({"kind": "destroyed", "x": 8.0, "y": 8.0})
	game._read_war_events()
	check(game._war_last.has("die_foe") and game._war_last.has("wall_crash"), "falls and collapses are voiced")
	game.sim.events.clear()
	game._war_last.clear()
	game.sim.events.append({"kind": "raid_result", "victory": false})
	game._read_war_events()
	check(game._war_last.has("funeral"), "a lost raid plays funeral drums")
	game.sim.events.clear()

	# The drums are sparse at first, then build.
	var calm: Array = drum_kinds(game, 0.05)
	var mid: Array = drum_kinds(game, 0.6)
	var wild: Array = drum_kinds(game, 0.95)
	check(calm == ["taiko_lo"], "the first dread is a single deep drum")
	check(mid.has("tom") and mid.has("taiko_lo"), "mid intensity gallops on toms")
	check(wild.has("rattle") and wild.has("brass"), "full intensity adds snare and brass")
	check(wild.size() > mid.size() and mid.size() > calm.size(), "the drums build with intensity")

	# The raid ducks the melody and releases it; a slow beat dips pitch and restores it.
	var bus: int = -1
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == "Music":
			bus = i
	check(bus >= 0, "a Music bus exists to duck")
	if bus >= 0:
		game._apply_duck(1.0, true)
		check(AudioServer.get_bus_volume_db(bus) < -3.0, "the melody ducks under the raid drums")
		game._apply_duck(5.0, false)
		check(is_zero_approx(AudioServer.get_bus_volume_db(bus)), "the melody comes back after the raid")
	game._slow_active = true
	game._slow_from = game.FINISH_SCALE
	Engine.time_scale = game.FINISH_SCALE
	game._apply_pitch_dip()
	check(AudioServer.playback_speed_scale < 0.5, "the finisher beat drops the pitch")
	game._slow_active = false
	Engine.time_scale = 1.0
	game._apply_pitch_dip()
	check(is_equal_approx(AudioServer.playback_speed_scale, 1.0), "pitch returns to normal")

	game._release_war_audio()
	print("WARSONG ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
