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


func fixture():
	var sim = Sim.new()
	sim.buildings.clear()
	sim.units.clear()
	sim.resources["wood"] = 5000
	sim.xp = 10000
	sim.chronicle.grant("wall", "test")
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]
	sim.build_row("wall", tiles)
	for wall: Dictionary in sim.buildings:
		wall["remaining"] = 0.0
	return sim


func _run() -> void:
	var sim = fixture()
	var id: int = int(sim.buildings[0]["id"])
	sim.buildings[2]["tier"] = 2
	check(sim.wall_row(id).size() == 2, "a different wall level ends the upgrade row")
	check(sim.wall_row(int(sim.buildings[2]["id"])).size() == 1, "a mixed-level row cannot be upgraded together")
	check(sim.upgrade_wall_row(id), "the matching-level portion upgrades together")
	check(int(sim.buildings[3]["tier"]) == 1 and float(sim.buildings[2]["remaining"]) == 0.0, "row upgrade leaves walls beyond the level boundary unchanged")
	sim = fixture()
	for index: int in sim.buildings.size():
		sim.buildings[index]["x"] = 1
		sim.buildings[index]["y"] = index + 1
	check(sim.wall_row(int(sim.buildings[1]["id"])).size() == 4, "vertical rows are discovered from a middle segment")
	sim.buildings[2]["type"] = "stonewall"
	check(sim.wall_row(int(sim.buildings[0]["id"])).size() == 2, "a different wall type ends the row even at the same level")

	for blocked: String in ["resources", "construction", "ruin", "maximum", "village level"]:
		sim = fixture()
		id = int(sim.buildings[0]["id"])
		match blocked:
			"resources": sim.resources["wood"] = 95
			"construction": sim.buildings[2]["remaining"] = 1.0
			"ruin": sim.buildings[2]["hp"] = 0.0
			"maximum":
				for wall: Dictionary in sim.buildings: wall["tier"] = 3
			"village level":
				sim.building_specs = sim.building_specs.duplicate(true)
				sim.building_specs["wall"]["tierGates"] = {"2": 100}
		var before: Dictionary = sim.export_state().duplicate(true)
		check(not sim.upgrade_wall_row_reason(id).is_empty(), blocked + " blocks the whole-row preview")
		check(not sim.upgrade_wall_row(id), blocked + " rejects the whole-row command")
		check(sim.export_state() == before, blocked + " leaves resources and every wall unchanged")

	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)
	game.sim = fixture()
	game.selected_building = int(game.sim.buildings[1]["id"])
	game._rebuild_buildings()
	game._open_panel("building")
	var before: Dictionary = game.sim.export_state().duplicate(true)
	game.row_upgrade_button.pressed.emit()
	check(game.panel == "wall_row_upgrade", "Upgrade Row opens an explicit confirmation panel")
	check(game.sim.export_state() == before, "opening row confirmation spends nothing and upgrades nothing")
	var preview: Variant = game.get("wall_row_preview")
	check(preview is Dictionary and preview.get("cost", {}) == {"wood": 96}, "preview quotes the complete four-wall upgrade cost")
	var markers: Variant = game.get("wall_row_marker")
	check(markers is MultiMeshInstance3D and markers.visible and markers.multimesh.instance_count == 4, "confirmation highlights every affected wall")
	var details: Variant = game.get("wall_row_details")
	check(details is Label and details.text.contains("96 Wood") and details.text.contains("1") and details.text.contains("2"), "confirmation displays cost and current/next levels")
	if game.panel == "wall_row_upgrade":
		var elapsed: float = game.sim.elapsed
		game._process(0.2)
		check(game.sim.paused and game.sim.elapsed == elapsed, "row confirmation pauses the simulation")
		game._refresh_hud()
		await capture(game)
		game.wall_row_cancel_button.pressed.emit()
		check(game.panel == "building" and game.sim.export_state() == before, "Cancel returns to the inspector without spending or upgrading")
		check(not game.wall_row_marker.visible and game.wall_row_preview.is_empty(), "Cancel clears the row preview and highlight")
		game._process(0.1)
		check(not game.sim.paused and game.sim.elapsed > elapsed, "cancelling resumes an otherwise active village")
		game._upgrade_wall_row()
		game.sim.resources["wood"] = 95
		before = game.sim.export_state().duplicate(true)
		game.wall_row_confirm_button.pressed.emit()
		check(game.sim.export_state() == before, "confirmation revalidates affordability without partial upgrades")
		game.sim.resources["wood"] = 5000
		game._upgrade_wall_row()
		game.sim.buildings[3]["tier"] = 2
		before = game.sim.export_state().duplicate(true)
		game.wall_row_confirm_button.pressed.emit()
		check(game.sim.export_state() == before, "a row changed since preview is rejected instead of silently upgrading a shorter row")
		game.sim.buildings[3]["tier"] = 1
		game._upgrade_wall_row()
		game.sim.building_specs = game.sim.building_specs.duplicate(true)
		game.sim.building_specs["wall"]["cost"]["wood"] = 13
		before = game.sim.export_state().duplicate(true)
		game.wall_row_confirm_button.pressed.emit()
		check(game.sim.export_state() == before, "a price changed since preview is rejected without spending")
		game.sim.building_specs["wall"]["cost"]["wood"] = 12
		game._upgrade_wall_row()
		game._close_panel()
		check(game.wall_row_preview.is_empty() and not game.wall_row_marker.visible, "closing the panel discards the pending row upgrade")
		game.paused = true
		game._upgrade_wall_row()
		game.wall_row_cancel_button.pressed.emit()
		game._process(0.1)
		check(game.paused and game.sim.paused, "cancelling does not undo an existing pause")
		game.paused = false
		game._upgrade_wall_row()
		game.wall_row_confirm_button.pressed.emit()
		check(game.sim.resources["wood"] == 4904, "Confirm charges the displayed cost exactly once")
		var upgraded: bool = true
		for wall: Dictionary in game.sim.buildings:
			upgraded = upgraded and int(wall["tier"]) == 2 and float(wall["remaining"]) > 0.0
		check(upgraded, "Confirm starts every matching wall's next-level construction")
		before = game.sim.export_state().duplicate(true)
		game.wall_row_confirm_button.pressed.emit()
		check(game.sim.export_state() == before, "a repeated confirmation cannot charge or upgrade twice")
	game.free()
	await process_frame
	print("WALL_ROWS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func capture(game) -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			var directory: String = argument.trim_prefix("--capture-dir=")
			if not directory.is_absolute_path() or not DirAccess.dir_exists_absolute(directory):
				check(false, "capture directory exists")
				return
			for width: int in [390, 1280]:
				DisplayServer.window_set_size(Vector2i(width, 844 if width == 390 else 800))
				game.target = game.world_position(Vector2(3.0, 1.5)) + Vector3(0, 0, 8)
				game.zoom = 16.0
				game.yaw = 0.0
				game.tilt = 0.85
				game._layout_ui()
				await process_frame
				await process_frame
				game._camera_update()
				await RenderingServer.frame_post_draw
				for button: Button in [game.wall_row_confirm_button, game.wall_row_cancel_button]:
					check(button.size.y >= 44 and game.sidebar.get_global_rect().encloses(button.get_global_rect()), "row confirmation controls fit the sheet with 44px touch targets")
				check(root.get_texture().get_image().save_png(directory.path_join("wall-row-upgrade-%d.png" % width)) == OK, "native row confirmation capture succeeds")
