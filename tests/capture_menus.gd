extends SceneTree

# Scratch QA capture for every menu at a given window size, plus a layout audit. Not a regression
# test; never loads or writes a player's save (--no-save, fresh village).
# Run WITHOUT --headless (needs a renderer):
#   godot --path <project> --resolution 390x844 --script res://tests/capture_menus.gd -- --no-save --size=390x844 --capture-dir=<abs dir>
# The audit prints AUDIT lines for visible buttons that are smaller than 40px, sit (partly) off
# screen, or overlap another visible button.

const PANELS: Array[String] = ["build", "people", "quests", "tech", "frontier", "board", "doctrine", "needs", "mentor", "raid_report", "pause"]

var directory: String = ""
var view: Vector2i = Vector2i(390, 844)
var game
var problems: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if is_instance_valid(game):
		game.focused = true
	return false


func capture(file_name: String, scope: Node = null) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	audit(file_name, scope)
	if directory.is_empty():
		return
	var image: Image = root.get_texture().get_image()
	image.save_png(directory.path_join("%dx%d-%s.png" % [view.x, view.y, file_name]))


func _visible_buttons(node: Node, out: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is BaseButton:
		out.append(node)
	for child in node.get_children():
		_visible_buttons(child, out)


func _clip_rect(control: Control) -> Rect2:
	# Visible part of a control after the scroll containers above it clip it.
	var rect: Rect2 = control.get_global_rect()
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			rect = rect.intersection((parent as Control).get_global_rect())
		parent = parent.get_parent()
	return rect


func audit(label: String, scope: Node = null) -> void:
	var buttons: Array = []
	_visible_buttons(game if scope == null else scope, buttons)
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var rects: Array = []
	for button: BaseButton in buttons:
		var full: Rect2 = button.get_global_rect()
		var shown: Rect2 = _clip_rect(button)
		if shown.size.x <= 0.5 or shown.size.y <= 0.5:
			continue   # scrolled out of its list
		var name: String = (button as Button).text if button is Button else str(button.name)
		if not screen.encloses(shown.grow(-1.0)):
			problems += 1
			print("AUDIT %s offscreen '%s' %s" % [label, name, shown])
		if full.size.y < 39.5 or full.size.x < 39.5:
			problems += 1
			print("AUDIT %s small '%s' %s" % [label, name, full.size])
		for other: Array in rects:
			var overlap: Rect2 = (other[1] as Rect2).intersection(shown)
			if overlap.size.x > 2.0 and overlap.size.y > 2.0:
				problems += 1
				print("AUDIT %s overlap '%s' x '%s'" % [label, name, other[0]])
		rects.append([name, shown])
	for sheet: Control in [game.sidebar, game.more_sheet]:
		if not sheet.visible:
			continue
		if not screen.encloses(sheet.get_global_rect()):
			problems += 1
			print("AUDIT %s sheet offscreen %s" % [label, sheet.get_global_rect()])
		for hud: Control in [game.resource_stack, game.nav]:
			if hud.is_visible_in_tree() and sheet.get_global_rect().intersects(hud.get_global_rect()):
				problems += 1
				print("AUDIT %s sheet covers %s" % [label, hud.name])
	# Text the web build's default font cannot draw shows as empty boxes there.
	var missing: Array[String] = []
	for node: Node in (game if scope == null else scope).find_children("*", "", true, false):
		if not (node is Label or node is Button) or not (node as CanvasItem).is_visible_in_tree():
			continue
		for ch: String in node.text:
			if ch.unicode_at(0) > 32 and not ThemeDB.fallback_font.has_char(ch.unicode_at(0)) and ch not in missing:
				missing.append(ch)
	if not missing.is_empty():
		problems += 1
		print("AUDIT %s glyphs %s" % [label, "".join(PackedStringArray(missing))])


func _run() -> void:
	print("AUDIT_START")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
		if argument.begins_with("--size="):
			var parts: PackedStringArray = argument.trim_prefix("--size=").split("x")
			view = Vector2i(int(parts[0]), int(parts[1]))
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
	root.size = view
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	await capture("00-title")
	game._enter_village()
	await process_frame
	game._layout_ui()
	await capture("01-village")
	game._toggle_more()
	await capture("02-more")
	game._toggle_more()
	for which: String in PANELS:
		game._open_panel(which)
		game._layout_ui()
		await capture("p-" + which)
		game._close_panel()
	game._inspect_subject("hall")
	game._layout_ui()
	await capture("p-building-hall")
	game._close_panel()
	if not game.sim.units.is_empty():
		game._select_unit(int(game.sim.units[0]["id"]))
		game._layout_ui()
		await capture("p-unit")
		game._close_panel()
	game._inspect_subject("hall")
	game._toggle_more()
	await capture("p-building-more")
	game._toggle_more()
	game._close_panel()
	var site: Dictionary = game.realm.settlements[0]
	game.realm_tap(site["centre"])
	await capture("p-realm-site")
	game._close_panel()
	game.realm_tap(Vector2(game.realm.home_radius() + 14.0, 0.0))
	await capture("p-realm-land")
	game._close_panel()
	game.town_open()
	game._layout_ui()
	await capture("zone")
	game.town_close()
	game._choose_build("tower")
	game._layout_ui()
	await capture("placement")
	game._cancel_placement()
	game.sim.chronicle.act = 4
	game._prepare_expedition("starwatch-ridge")
	game._layout_ui()
	await capture("p-expedition")
	game._start_expedition()
	for i in 20:
		await process_frame
	if is_instance_valid(game.battle_view):
		await capture("battle", root)
		game.battle_view._withdraw()
		await process_frame
		if is_instance_valid(game.battle_view):
			game.battle_view.return_requested.emit()
		for i in 10:
			await process_frame
	if game.sim.start_raid():
		game._refresh_hud()
		var waited: int = Time.get_ticks_msec()
		while not game.sim.raid_active and Time.get_ticks_msec() - waited < 10000:
			await process_frame
		await create_timer(2.0).timeout
		await capture("raid")
		game._open_panel("build")
		await capture("raid-build")
		game._close_panel()
	print("AUDIT_TOTAL ", problems)
	game.queue_free()
	await process_frame
	quit(0)
