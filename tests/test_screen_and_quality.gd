extends SceneTree

# Phase 1 phone fixes: a quality setting with a frame-rate readout in Pause, the title card showing
# only one set of controls, and the mission folding to one line on a phone. Fresh village, never saves.

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func settle() -> void:
	for i in 3:
		await process_frame


func _run() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame

	# Title card: no line mixes touch and mouse controls.
	var touch_and_mouse: int = 0
	for label: Node in game.welcome_intro.find_children("*", "Label", true, false):
		var text: String = (label as Label).text
		if text.contains("Pinch") and text.contains("scroll"):
			touch_and_mouse += 1
	check(touch_and_mouse == 0, "title card has no line mixing pinch and scroll controls")

	game._enter_village()
	game._layout_ui()
	await settle()
	game._refresh_hud()
	check(not game.quest_label.text.contains("\n"), "phone mission card is one line (%s)" % game.quest_label.text.c_escape())
	check(game.quest_label.clip_text, "phone mission line trims instead of spilling out of the card")
	check(game.quest_label.get_visible_line_count() == 1, "phone mission line is actually shown")
	check(not game.quest_label.tooltip_text.is_empty(), "full objective stays in the mission tooltip")

	# Quality: auto on this desktop test runner means High.
	check(game.quality == "auto", "quality starts on Auto")
	check(game.quality_level() == "high", "Auto is High off phones")
	game._open_panel("pause")
	await settle()
	check(is_instance_valid(game.quality_button) and game.quality_button.is_visible_in_tree(), "Pause shows the quality button")
	check(is_instance_valid(game.fps_label) and game.fps_label.is_visible_in_tree(), "Pause shows the frame-rate readout")
	for i in 40:
		await process_frame
	check(game.fps_label.text.contains("fps"), "frame-rate readout fills in (%s)" % game.fps_label.text)
	game._cycle_quality()
	check(game.quality == "low", "Auto -> Low")
	check(not game.shadows_on and not game.sun.shadow_enabled, "Low turns shadows off")
	check(is_equal_approx(game.get_viewport().scaling_3d_scale, 0.75), "Low renders the 3D view smaller")
	check(game._quality_lite(), "Low uses the lighter effects")
	game._cycle_quality()
	check(game.quality == "medium" and game.shadows_on, "Low -> Medium brings shadows back")
	check(is_equal_approx(game.get_viewport().scaling_3d_scale, 1.0), "Medium renders at full size")
	check(game._quality_lite(), "Medium uses the lighter effects")
	game._cycle_quality()
	check(game.quality == "high" and not game._quality_lite(), "Medium -> High uses the full effects")
	check(game.quality_button.text == "Quality: High", "button names the level (%s)" % game.quality_button.text)
	game._cycle_quality()
	check(game.quality == "auto", "High -> Auto")
	game._close_panel()

	game.queue_free()
	await process_frame
	print("SCREEN_QUALITY ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
