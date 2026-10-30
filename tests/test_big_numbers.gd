extends SceneTree

# Big-number polish (The Manor Endures, B4): stores, caps and costs read as 2,944, 12.4K, 3.1M
# instead of long digit strings, on the HUD counters and in cost lines. Fresh village, never saves.
const UI = preload("res://scripts/game/village_ui.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func _run() -> void:
	var cases: Dictionary = {0.0: "0", 950.0: "950", 999.9: "999", 1000.0: "1,000", 2944.0: "2,944", 9999.0: "9,999",
		10000.0: "10K", 12400.0: "12.4K", 99950.0: "99.9K", 123456.0: "123K", 999999.0: "999K",
		1000000.0: "1M", 3100000.0: "3.1M", 1250000000.0: "1.2B", -2500.0: "-2,500"}
	for value: float in cases:
		check(UI.big_number(value) == str(cases[value]), "%s reads %s (got %s)" % [value, cases[value], UI.big_number(value)])
	for view: Vector2i in [Vector2i(390, 844), Vector2i(1280, 800)]:
		root.size = view
		var game = load("res://scenes/game.tscn").instantiate()
		game.no_save = true
		root.add_child(game)
		await process_frame
		game._enter_village()
		game.sim.resources["gold"] = 12400.0
		game._refresh_hud()
		for i in 3:
			await process_frame
		var shown: String = game.resource_rows["gold"].text
		check(shown.contains("12.4K") and not shown.contains("12400"), "%dx%d gold counter reads 12.4K (%s)" % [view.x, view.y, shown])
		check(game._cost_text({"gold": 3100000, "wood": 2944}) == "3.1M Gold + 2,944 Wood", "costs use short numbers (%s)" % game._cost_text({"gold": 3100000, "wood": 2944}))
		game.queue_free()
		await process_frame
	print("BIG_NUMBERS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
