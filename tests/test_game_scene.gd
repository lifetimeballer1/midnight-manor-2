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
	game._close_panel()
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
