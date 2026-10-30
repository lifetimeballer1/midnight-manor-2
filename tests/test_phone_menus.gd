extends SceneTree

# Every menu opens into a sheet that fits the screen on a phone and on desktop: inside the window,
# clear of the resource counts and the bottom buttons, with a Close button that is always in view and
# a full-size touch target. Fresh village, never saves.

const MENUS: Array[String] = ["build", "people", "quests", "tech", "frontier", "board", "doctrine", "needs", "mentor", "raid_report", "pause", "stewards", "daily", "drill", "vale", "renewal"]
var checks: int = 0
var failures: Array[String] = []
var game


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


func sheet_fits(sheet: Control, label: String) -> void:
	var screen := Rect2(Vector2.ZERO, game.get_viewport().get_visible_rect().size)
	var rect: Rect2 = sheet.get_global_rect()
	check(screen.encloses(rect), "%s sheet stays on screen (%s in %s)" % [label, rect, screen.size])
	check(not rect.intersects(game.nav.get_global_rect()), "%s sheet leaves the bottom buttons uncovered" % label)
	check(not rect.intersects(game.resource_stack.get_global_rect()), "%s sheet leaves the resource counts uncovered" % label)


func _run() -> void:
	for view: Vector2i in [Vector2i(390, 844), Vector2i(360, 760), Vector2i(1280, 800)]:
		root.size = view
		game = load("res://scenes/game.tscn").instantiate()
		game.no_save = true
		root.add_child(game)
		await process_frame
		game._enter_village()
		game._layout_ui()
		await settle()
		var tag: String = "%dx%d" % [view.x, view.y]
		var tall: float = 0.0
		for which: String in MENUS:
			game._open_panel(which)
			await settle()
			game.side_scroll.scroll_vertical = 100000
			await settle()
			sheet_fits(game.sidebar, "%s %s" % [tag, which])
			var close: Button = game.sheet_close_button
			check(close.is_visible_in_tree() and game.sidebar.get_global_rect().encloses(close.get_global_rect()), "%s %s keeps Close in view when scrolled" % [tag, which])
			check(close.size.y >= 44.0, "%s Close is a full-size touch target" % tag)
			tall = maxf(tall, game.sidebar.size.y)
			game._close_panel()
		var view_h: float = game.get_viewport().get_visible_rect().size.y
		check(tall >= view_h * 0.45, "%s long menus get more than the old 45%% sheet (%.0f of %.0f)" % [tag, tall, view_h])
		game._toggle_more()
		await settle()
		sheet_fits(game.more_sheet, "%s More" % tag)
		game._toggle_more()
		# The selected building's card stays low on a phone so the building stays in view.
		game._inspect_subject("hall")
		await settle()
		if view.x < 420:
			check(game.sidebar.size.y <= maxf(240.0, view_h * 0.45) + 1.0, "%s building card stays in the lower part of the screen" % tag)
		game._close_panel()
		game.queue_free()
		await process_frame
		await process_frame
	print("PHONE_MENUS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
