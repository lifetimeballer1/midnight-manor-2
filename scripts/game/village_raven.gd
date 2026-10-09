extends "res://scripts/game/village_juice.gd"
## Raven Messenger layer (mentor/quest toast delivery).

# Mentor advice and Chronicle objective lines (the sim.notice text that quests and
# the mentor produce) are carried by a small procedurally drawn raven. It flies in
# from the left edge, drops a parchment note just above the bottom toast, and flies
# off to the right. While the errand runs the plain toast is hidden so the note is
# the only copy on screen; it is restored afterwards. Raids, frontier battles, and
# lines that arrive while a delivery is still running fall back to the plain toast.
# Nothing here is saved or simulated. Tap the note to dismiss it early.

const UI_THEME = preload("res://scripts/game/village_ui.gd")

const FLY_IN: float = 1.1
const DROP_PAUSE: float = 0.7
const FLY_OUT: float = 0.8
const NOTE_FADE: float = 0.3
const NOTE_HOLD: float = 4.5
const TAP_MIN: float = 44.0
const RAVEN_INK: Color = Color("1c1a21")
const RAVEN_FAR: Color = Color("2b2832")
const LAYER_Z: int = 40

var _raven_seen: String = ""
var _raven_root: Node2D = null
var _raven_bird: Node2D = null
var _raven_near_wing: Node2D = null
var _raven_far_wing: Node2D = null
var _raven_note: PanelContainer = null
var _raven_note_label: Label = null
var _raven_flight: Tween = null
var _raven_flap: Tween = null
var _raven_bob: Tween = null
var _raven_note_fade: Tween = null


func _process(delta: float) -> void:
	super(delta)
	if sim == null:
		return
	if not started:
		_raven_seen = sim.notice
		return
	if sim.notice == _raven_seen:
		return
	_raven_seen = sim.notice
	_deliver(sim.notice)


func _exit_tree() -> void:
	super()
	_kill(_raven_flight)
	_kill(_raven_flap)
	_kill(_raven_bob)
	_kill(_raven_note_fade)
	if is_instance_valid(toast):
		toast.modulate = Color.WHITE


# --- Delivery -----------------------------------------------------------------

func _deliver(text: String) -> void:
	if not _is_messenger_line(text) or _raven_busy() or _raven_blocked():
		return  # the plain toast already shows this line
	if hud_root == null or not is_instance_valid(hud_root) or toast == null or not toast.is_inside_tree():
		return
	var hud_rect: Rect2 = hud_root.get_global_rect()
	var toast_rect: Rect2 = toast.get_global_rect()
	if hud_rect.size.x <= 0.0 or toast_rect.size.x <= 0.0:
		return
	_ensure_nodes()
	var width: float = hud_rect.size.x
	var note_bottom: float = toast_rect.position.y - hud_rect.position.y - 8.0

	_raven_note_label.text = text
	_raven_note.offset_left = 16.0
	_raven_note.offset_right = -16.0
	_raven_note.offset_bottom = note_bottom - hud_rect.size.y
	_raven_note.offset_top = _raven_note.offset_bottom - TAP_MIN
	_raven_note.visible = false
	_raven_note.modulate.a = 0.0

	_raven_root.position = Vector2(-80.0, note_bottom - 110.0)
	_raven_root.visible = true
	toast.modulate = Color(1, 1, 1, 0)

	var perch := Vector2(clampf(width * 0.7, 80.0, width - 80.0), note_bottom - 70.0)
	var away := Vector2(width + 80.0, note_bottom - 130.0)
	_start_flap()
	_raven_flight = create_tween()
	_raven_flight.tween_property(_raven_root, "position", perch, FLY_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_raven_flight.tween_callback(_release_note)
	_raven_flight.tween_interval(DROP_PAUSE)
	_raven_flight.tween_property(_raven_root, "position", away, FLY_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_raven_flight.tween_callback(_stop_raven)
	_raven_flight.tween_interval(NOTE_HOLD)
	_raven_flight.tween_property(_raven_note, "modulate:a", 0.0, NOTE_FADE)
	_raven_flight.tween_callback(_finish)


func _release_note() -> void:
	_raven_note.visible = true
	_kill(_raven_note_fade)
	_raven_note_fade = create_tween()
	_raven_note_fade.tween_property(_raven_note, "modulate:a", 1.0, NOTE_FADE)


func _stop_raven() -> void:
	_kill(_raven_flap)
	_kill(_raven_bob)
	_raven_root.visible = false


func _finish() -> void:
	_stop_raven()
	_kill(_raven_note_fade)
	_raven_note.visible = false
	_raven_note.modulate.a = 1.0
	if is_instance_valid(toast):
		toast.modulate = Color.WHITE


func _dismiss_note() -> void:
	if not _raven_busy():
		return
	_kill(_raven_flight)
	_finish()


func _is_messenger_line(text: String) -> bool:
	if text.is_empty():
		return false
	if text.begins_with("Next / ") or text.begins_with("Act "):
		return true
	return mentor_enabled and text == _mentor_advice()


func _raven_busy() -> bool:
	return _raven_flight != null and _raven_flight.is_valid()


func _raven_blocked() -> bool:
	return sim.raid_active or sim.raid_warning or is_instance_valid(battle_view) or not sim.frontier.active.is_empty()


# --- Procedural nodes ---------------------------------------------------------

func _ensure_nodes() -> void:
	if _raven_root != null and is_instance_valid(_raven_root):
		return
	_raven_root = Node2D.new()
	_raven_root.name = "RavenMessenger"
	_raven_root.z_index = LAYER_Z
	_raven_root.visible = false
	hud_root.add_child(_raven_root)

	_raven_bird = Node2D.new()
	_raven_root.add_child(_raven_bird)
	# Far wing sits behind the body; near wing is drawn over it.
	_raven_far_wing = _wing(Vector2(2.0, -4.0), RAVEN_FAR)
	_raven_bird.add_child(_raven_far_wing)
	_raven_bird.add_child(_polygon(_ellipse(Vector2.ZERO, 16.0, 8.5), RAVEN_INK))
	_raven_bird.add_child(_polygon(PackedVector2Array([
		Vector2(-12.0, -1.0), Vector2(-33.0, -8.0), Vector2(-28.0, 2.0), Vector2(-10.0, 4.0)]), RAVEN_INK))
	_raven_bird.add_child(_polygon(_ellipse(Vector2(14.0, -6.0), 7.0, 6.5), RAVEN_INK))
	_raven_bird.add_child(_polygon(PackedVector2Array([
		Vector2(19.0, -9.0), Vector2(29.0, -5.5), Vector2(19.0, -3.5)]), RAVEN_INK))
	_raven_bird.add_child(_polygon(_ellipse(Vector2(16.0, -7.0), 1.6, 1.6), UI_THEME.BRASS))
	_raven_near_wing = _wing(Vector2(-1.0, -3.0), RAVEN_INK)
	_raven_bird.add_child(_raven_near_wing)

	_raven_note = PanelContainer.new()
	_raven_note.name = "RavenNote"
	_raven_note.z_index = LAYER_Z - 1
	_raven_note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_raven_note.anchor_left = 0.0
	_raven_note.anchor_right = 1.0
	_raven_note.anchor_top = 1.0
	_raven_note.anchor_bottom = 1.0
	if ui != null:
		_raven_note.add_theme_stylebox_override("panel", ui.panel_box())
	_raven_note.visible = false
	hud_root.add_child(_raven_note)
	_raven_note_label = Label.new()
	_raven_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_raven_note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_raven_note_label.add_theme_font_size_override("font_size", 13)
	_raven_note_label.add_theme_color_override("font_color", UI_THEME.PAPER)
	_raven_note_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raven_note.add_child(_raven_note_label)
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.custom_minimum_size = Vector2(0.0, TAP_MIN)
	tap.tooltip_text = "Dismiss note"
	tap.pressed.connect(_dismiss_note)
	_raven_note.add_child(tap)


func _start_flap() -> void:
	_kill(_raven_flap)
	_kill(_raven_bob)
	_raven_flap = _raven_root.create_tween().set_loops()
	_raven_flap.tween_property(_raven_near_wing, "rotation", -0.5, 0.14).set_trans(Tween.TRANS_SINE)
	_raven_flap.parallel().tween_property(_raven_far_wing, "rotation", -0.35, 0.14).set_trans(Tween.TRANS_SINE)
	_raven_flap.tween_property(_raven_near_wing, "rotation", 0.4, 0.14).set_trans(Tween.TRANS_SINE)
	_raven_flap.parallel().tween_property(_raven_far_wing, "rotation", 0.5, 0.14).set_trans(Tween.TRANS_SINE)
	_raven_bob = _raven_root.create_tween().set_loops()
	_raven_bob.tween_property(_raven_bird, "position:y", -4.0, 0.14).set_trans(Tween.TRANS_SINE)
	_raven_bob.tween_property(_raven_bird, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_SINE)


func _wing(pivot: Vector2, colour: Color) -> Node2D:
	var holder := Node2D.new()
	holder.position = pivot
	holder.add_child(_polygon(PackedVector2Array([
		Vector2(4.0, 0.0), Vector2(-2.0, -15.0), Vector2(-14.0, -26.0), Vector2(-21.0, -21.0),
		Vector2(-13.0, -11.0), Vector2(-8.0, -4.0), Vector2(-6.0, 2.0)]), colour))
	return holder


func _polygon(points: PackedVector2Array, colour: Color) -> Polygon2D:
	var shape := Polygon2D.new()
	shape.polygon = points
	shape.color = colour
	return shape


func _ellipse(centre: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		points.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	return points


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
