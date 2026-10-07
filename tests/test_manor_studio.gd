extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var fixture: String = "user://manor-studio-test-%d.json" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func write_fixture(text: String) -> void:
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	check(file != null, "scratch file opens without touching gameplay data")
	if file != null: file.store_string(text)


func _run() -> void:
	check(ResourceLoader.exists("res://addons/manor_studio/balance_model.gd"), "Manor Studio has an independently testable balance model")
	if failures.is_empty():
		await test_model()
		await test_dock()
		var config := ConfigFile.new()
		check(config.load("res://addons/manor_studio/plugin.cfg") == OK, "editor plugin is registered")
		check(ResourceLoader.exists("res://addons/manor_studio/plugin.gd"), "editor entry point exists")
		if ResourceLoader.exists("res://addons/manor_studio/plugin.gd"):
			check(load("res://addons/manor_studio/plugin.gd").can_instantiate(), "editor entry point parses against the installed Godot API")
		check("res://addons/manor_studio/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", []), "Manor Studio is enabled without replacing existing plugins")
	for suffix: String in ["", ".manor-studio.previous", ".manor-studio.tmp", ".manor-studio.lock"]:
		if FileAccess.file_exists(fixture + suffix) or DirAccess.dir_exists_absolute(fixture + suffix): DirAccess.remove_absolute(fixture + suffix)
	print("MANOR_STUDIO ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func test_model() -> void:
	var Model = load("res://addons/manor_studio/balance_model.gd")
	var model = Model.new()
	check(model.load_file(), "current building data loads")
	check(model.data.has("farm") and model.data.has("hall"), "real building IDs are available")
	check(not model.is_dirty(), "opening the editor does not stage changes")
	var original: String = FileAccess.get_file_as_string("res://data/buildings.json")
	write_fixture(original)
	check(model.load_file(fixture), "isolated persistence fixture loads")
	var fields: Array = model.editable_fields("farm", 0)
	check(fields.any(func(field): return field["path"] == ["cost", "wood"]), "existing resource costs are editable")
	check(fields.any(func(field): return field["path"] == ["tiers", 0, "hp"]), "selected tier stats are editable")
	check(not fields.any(func(field): return field["path"] == ["size"]), "footprint and structural metadata are not editable")
	check(model.set_numeric("farm", ["cost", "wood"], 65.0), "a real resource cost can be staged")
	check(model.set_numeric("farm", ["tiers", 0, "hp"], 180.0), "selected tier HP can be staged")
	check(model.is_dirty(), "staged changes are reported")
	check(FileAccess.get_file_as_string(fixture) == original, "staging never writes the source file")
	check(not model.set_numeric("farm", ["cost", "wood"], -1.0), "negative costs are rejected")
	check(not model.set_numeric("farm", ["rate"], NAN), "NaN is rejected")
	check(not model.set_numeric("farm", ["rate"], INF), "infinity is rejected")
	check(not model.set_numeric("farm", ["tiers", 0, "hp"], 0.0), "zero building HP is rejected")
	check(not model.set_numeric("missing", ["rate"], 1.0), "unknown buildings are rejected")
	check(not model.set_numeric("farm", ["tiers", 99, "hp"], 1.0), "unknown tiers are rejected")
	check(not model.set_numeric("farm", ["size"], 5.0), "edits cannot mutate structural metadata")
	check(model.data["farm"]["cost"]["wood"] == 65.0, "invalid input leaves staged values intact")
	model.discard()
	check(not model.is_dirty() and model.data["farm"]["cost"]["wood"] == 55.0, "discard restores loaded values")
	check(model.save() and FileAccess.get_file_as_string(fixture) == original, "unchanged Apply does not reformat or write JSON")
	model.set_numeric("farm", ["cost", "wood"], 65.0)
	check(model.save(), "validated edits save successfully")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	check(saved["farm"]["cost"]["wood"] == 65.0, "saved edits round-trip through JSON")
	var expected: Dictionary = JSON.parse_string(original)
	expected["farm"]["cost"]["wood"] = 65.0
	check(saved == expected, "all unedited metadata and buildings are preserved")
	check(FileAccess.get_file_as_string(fixture + ".manor-studio.previous") == original, "Apply backs up the exact previous content")
	check(not model.is_dirty(), "successful Apply establishes a new baseline")
	check(not FileAccess.file_exists(fixture + ".manor-studio.tmp"), "successful Apply leaves no staging file")
	model.set_numeric("farm", ["rate"], 3.0)
	var external: String = FileAccess.get_file_as_string(fixture) + "\n"
	write_fixture(external)
	check(not model.save(), "external file changes block Apply")
	check(FileAccess.get_file_as_string(fixture) == external and model.is_dirty(), "conflict preserves external content and staged edits")
	write_fixture("{invalid")
	check(not model.load_file(fixture) and model.data["farm"]["rate"] == 3.0, "invalid reload preserves the working draft")
	write_fixture(original)
	check(model.load_file(fixture), "valid reload recovers after a conflict")
	model.set_numeric("farm", ["rate"], 3.0)
	var stage := FileAccess.open(fixture + ".manor-studio.tmp", FileAccess.WRITE)
	stage.store_string("existing temporary file")
	stage.close()
	check(not model.save(), "existing staging files are not overwritten")
	check(FileAccess.get_file_as_string(fixture) == original, "failed save preserves source data")
	DirAccess.remove_absolute(fixture + ".manor-studio.tmp")
	DirAccess.make_dir_absolute(fixture + ".manor-studio.lock")
	check(not model.save() and FileAccess.get_file_as_string(fixture) == original, "another Studio writer blocks Apply without overwriting source data")
	DirAccess.remove_absolute(fixture + ".manor-studio.lock")
	var precise: Dictionary = JSON.parse_string(original)
	precise["farm"]["studio_metadata"] = {"precision": 123.12345678901234}
	precise["farm"]["tiers"][0]["hp"] = 0.005
	precise["farm"]["rate"] = 0.12345678901234567
	write_fixture(JSON.stringify(precise, "\t", false, true))
	check(model.load_file(fixture), "valid high-precision tuning loads")
	model.set_numeric("farm", ["cost", "wood"], 65.0)
	check(model.save(), "high-precision document saves")
	var roundtrip: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	check(roundtrip["farm"]["studio_metadata"]["precision"] == 123.12345678901234, "Apply preserves untouched high-precision metadata")
	check(FileAccess.get_file_as_string("res://data/buildings.json") == original, "all persistence tests leave real gameplay data unchanged")


func test_dock() -> void:
	check(ResourceLoader.exists("res://addons/manor_studio/dock.gd"), "Manor Studio exposes an editor dock")
	if not ResourceLoader.exists("res://addons/manor_studio/dock.gd"): return
	var dock = load("res://addons/manor_studio/dock.gd").new()
	dock.data_path = fixture
	root.add_child(dock)
	await process_frame
	check(dock.buildings.item_count == dock.model.data.size(), "dock lists every authored building")
	check(dock.get_combined_minimum_size().x <= 360.0, "dock fits a normal narrow editor column")
	var farm_index: int = dock.building_ids.find("farm")
	dock.buildings.select(farm_index)
	dock.buildings.item_selected.emit(farm_index)
	check(dock.tiers.item_count == 3, "building selection exposes its tiers")
	check(dock.editors["tiers.0.hp"].value == 0.005, "controls preserve valid HP below one hundredth")
	check(dock.editors["rate"].value == 0.12345678901234567, "controls preserve full precision instead of quantizing loaded values")
	check(dock.editors["rate"].get_line_edit().text.to_float() == 0.12345678901234567, "displayed numeric text agrees with the loaded value")
	dock.editors["tiers.0.hp"].value = 0.0
	check(dock.editors["tiers.0.hp"].value == 0.005 and dock.model.data["farm"]["tiers"][0]["hp"] == 0.005, "invalid control input restores the displayed staged value")
	dock.editors["tiers.0.hp"].value = 160.0
	var spin: SpinBox = dock.editors["cost.wood"]
	spin.value = 77.0
	check(dock.model.data["farm"]["cost"]["wood"] == 77.0 and not dock.apply_button.disabled, "numeric controls stage actual balance edits")
	dock.tiers.select(1)
	dock.tiers.item_selected.emit(1)
	check(dock.editors["tiers.1.hp"].value == 320.0, "tier changes display the selected tier's HP")
	check(dock.model.data["farm"]["cost"]["wood"] == 77.0, "changing selection preserves staged edits")
	var saves: Array = []
	dock.data_saved.connect(func(): saves.append("saved"))
	dock.editors["tiers.1.hp"].value = 333.0
	dock.apply_button.pressed.emit()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	check(saves == ["saved"] and saved["farm"]["tiers"][1]["hp"] == 333.0, "Apply control persists staged values and signals the editor")
	dock.editors["cost.wood"].value = 88.0
	dock.discard_button.pressed.emit()
	check(not dock.model.is_dirty() and dock.apply_button.disabled, "Discard reloads saved values and updates controls")
	check(dock.model.data["farm"]["cost"]["wood"] == 77.0, "Discard keeps the last applied value")
	var events: Array = []
	dock.open_game_requested.connect(func(): events.append("open"))
	dock.open_button.pressed.emit()
	check(events == ["open"], "Open Game requests editor navigation rather than launching gameplay")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			var directory: String = argument.trim_prefix("--capture-dir=")
			if directory.is_absolute_path() and DirAccess.dir_exists_absolute(directory):
				root.size = Vector2i(480, 820)
				dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				await process_frame
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(directory.path_join("manor-studio-dock.png")) == OK, "native dock fixture capture succeeds")
	dock.queue_free()
	await process_frame
