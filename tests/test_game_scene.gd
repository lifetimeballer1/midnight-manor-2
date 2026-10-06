extends SceneTree

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		printerr("FAIL ", text)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var packed: PackedScene = load("res://scenes/game.tscn")
	var game = packed.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	check(game.building_views.size() == 9 and game.actors.size() == 5, "starting village meshes and five animated actors")
	check(game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "original orthographic village camera feel")
	check(not game.started and game.sim.paused, "welcome pauses village")
	game._enter_village()
	await process_frame
	check(game.started and not game.sim.paused, "enter actually starts village")
	game.music.score = game.music._score_data({"echo": {"seconds": 0.24, "gain": 0.12}})
	game.music._apply_echo()
	var music_bus: int = AudioServer.get_bus_index("Music")
	var echo_delay: AudioEffectDelay = null
	if music_bus >= 0:
		for effect_index in AudioServer.get_bus_effect_count(music_bus):
			var effect: AudioEffect = AudioServer.get_bus_effect(music_bus, effect_index)
			if effect is AudioEffectDelay:
				echo_delay = effect
				break
	check(echo_delay != null and is_equal_approx(echo_delay.tap1_delay_ms, 240.0), "music echo seconds convert to 240ms")
	var picked: Vector2 = game.pick_ground(game.camera.unproject_position(game.world_position(Vector2(1.5, 1.5))))
	check(picked.distance_to(Vector2(1.5, 1.5)) < 0.001, "perspective-independent world picking on Y-up ground")
	game._choose_build("farm")
	game.preview_tile = Vector2i(1, 1)
	game._preview()
	var wood: float = float(game.sim.resources["wood"])
	check(not game.confirm_button.disabled and game.sim.resources["wood"] == wood, "preview presents confirm without spend")
	game._cancel_placement()
	check(game.build_type.is_empty() and game.sim.resources["wood"] == wood, "cancel preserves resources")
	game._choose_build("farm")
	game.preview_tile = Vector2i(1, 1)
	game._confirm_placement()
	check(game.sim.buildings.size() == 10 and game.sim.resources["wood"] == wood - 55, "UI confirmation creates real building and charges exact cost")
	check(game.building_views.size() == 10, "building model updates after confirmed state change")
	game._open_panel("build")
	check(game.build_cards.has("farm") and game.build_cards["farm"].disabled, "shop disables farm at the level-1 cap")
	check(game.build_cards.has("storehouse") and game.build_cards["storehouse"].disabled, "shop reflects minimum village-level locks")
	game._close_panel()
	var attacked: Dictionary = game.sim.buildings[0]
	var attacked_view: Dictionary = game.building_views[int(attacked["id"])]
	attacked_view["danger_until"] = game.sim.elapsed + 1.0
	game.details.update(game, 0.0)
	check(attacked_view["label"].modulate == Color("ff8270"), "attack warning turns building label red")
	game.sim.elapsed += 2.0
	game._update_actors(0.0)
	game.details.update(game, 0.0)
	check(attacked_view["label"].modulate == Color("d4b275"), "attack warning label returns to gold")
	game.selected_building = int(game.sim.buildings[1]["id"])
	game._open_panel("building")
	game.sim.buildings[1]["reserve"] = 0
	game._refresh_inspector()
	check(game.collect_button.disabled, "empty workplace collect action disabled")
	game.sim.buildings[1]["reserve"] = 4
	game._refresh_inspector()
	check(not game.collect_button.disabled, "collect action activates when live reserve fills")
	game._open_panel("people")
	check(game.sidebar.visible and game.side_content.get_child_count() > 10, "people panel contains real recruit and worker controls")
	game._select_unit(int(game.sim.units[0]["id"]))
	game._hold_selected()
	check(game.sim.units[0]["hold"], "selected fighter hold command")
	game._resume_selected()
	check(not game.sim.units[0]["hold"] and game.sim.units[0]["order"].is_empty(), "resume preserves working model")
	game._open_pause()
	await process_frame
	var elapsed: float = game.sim.elapsed
	game._process(1)
	check(game.sim.elapsed == elapsed and game.sim.paused, "pause button stops20Hz clock")
	game._toggle_more()
	game._process(0.1)
	check(not game.paused and not game.sim.paused and game.more_sheet.visible, "opening More from pause resumes the simulation")
	game._toggle_more()
	elapsed = game.sim.elapsed
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._process(1)
	check(game.sim.elapsed == elapsed, "focus loss does not produce offline progress")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._process(0.1)
	check(game.sim.elapsed > elapsed and game.sim.elapsed < elapsed + 0.3, "focus regain resumes without catching up whole hidden second")
	var target: Vector3 = game.target
	game.left_pressed = true
	game.press_point = Vector2(400, 400)
	game.last_pointer = game.press_point
	game._drag_map(Vector2(450, 410))
	check(game.left_dragged and not game.target.is_equal_approx(target), "ordinary left-drag pans without sending orders")
	game.left_pressed = false
	game._toggle_day()
	check(not game.night, "day-night visual control")
	game._test_raid()
	check(game.sim.raid_warning, "defense button starts live simulation wave")
	game._process(0.1)
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "Headless scene/control integration; real desktop rendering checked separately."}
	var file := FileAccess.open("res://docs/game_smoke_verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	game.free()
	await process_frame
	print("GAME_SMOKE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
