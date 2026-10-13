extends "res://scripts/game/village_realm_life.gd"

# Feel layer: small presentation touches with no simulation effect.
#  - A selected building gives a soft squash-and-settle bounce.
#  - HUD buttons dip when pressed and spring back on release.
#  - The HUD clusters fade in one after another when the village opens.
# Only view nodes are animated (building view roots, buttons, HUD panels); sim state,
# saves and layouts are never touched. Every tween is cheap and short.

const SELECT_SQUASH := Vector3(1.07, 0.88, 1.07)
const SELECT_STRETCH := Vector3(0.97, 1.05, 0.97)
const PRESS_SCALE: float = 0.92
const HUD_FADE: float = 0.35
const HUD_STAGGER: float = 0.08

var _polish_selected: int = -1
var _polish_bounce: Tween = null
var _polish_bounce_root: Node3D = null


func _ready() -> void:
	super()
	if is_instance_valid(hud_root):
		_wire_press_juice(hud_root)
	get_tree().node_added.connect(_on_polish_node_added)


func _exit_tree() -> void:
	super()
	if get_tree() != null and get_tree().node_added.is_connected(_on_polish_node_added):
		get_tree().node_added.disconnect(_on_polish_node_added)
	_settle_bounce()


func _process(delta: float) -> void:
	super(delta)
	if selected_building != _polish_selected:
		_polish_selected = selected_building
		if selected_building >= 0 and started:
			_bounce_building(selected_building)


func _enter_village() -> void:
	var opening: bool = not started
	super()
	if opening:
		_fade_in_hud()


# --- Selection bounce ----------------------------------------------------------

func _bounce_building(id: int) -> void:
	var view: Dictionary = building_views.get(id, {})
	var root_node: Node3D = view.get("root") as Node3D
	if not is_instance_valid(root_node):
		return
	_settle_bounce()
	_polish_bounce_root = root_node
	_polish_bounce = create_tween()
	_polish_bounce.tween_property(root_node, "scale", SELECT_SQUASH, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_polish_bounce.tween_property(root_node, "scale", SELECT_STRETCH, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_polish_bounce.tween_property(root_node, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _settle_bounce() -> void:
	if _polish_bounce != null and _polish_bounce.is_valid():
		_polish_bounce.kill()
	_polish_bounce = null
	if is_instance_valid(_polish_bounce_root):
		_polish_bounce_root.scale = Vector3.ONE
	_polish_bounce_root = null


# --- Button press spring -------------------------------------------------------

func _on_polish_node_added(node: Node) -> void:
	if node is BaseButton and is_instance_valid(hud_root) and hud_root.is_ancestor_of(node):
		_wire_button(node)


func _wire_press_juice(from: Node) -> void:
	for child in from.get_children():
		if child is BaseButton:
			_wire_button(child)
		_wire_press_juice(child)


func _wire_button(button: BaseButton) -> void:
	if button.has_meta("press_juice"):
		return
	button.set_meta("press_juice", true)
	button.button_down.connect(_press_button.bind(button, true))
	button.button_up.connect(_press_button.bind(button, false))


func _press_button(button: BaseButton, down: bool) -> void:
	if not is_instance_valid(button):
		return
	button.pivot_offset = button.size * 0.5
	var spring: Tween = button.create_tween()
	if down:
		spring.tween_property(button, "scale", Vector2.ONE * PRESS_SCALE, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		spring.tween_property(button, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- HUD entrance ----------------------------------------------------------------

func _fade_in_hud() -> void:
	var order: Array = [left_dock, resource_stack, bottom]
	for index in order.size():
		var panel: Control = order[index]
		if not is_instance_valid(panel):
			continue
		panel.modulate.a = 0.0
		var fade: Tween = panel.create_tween()
		fade.tween_interval(HUD_STAGGER * float(index))
		fade.tween_property(panel, "modulate:a", 1.0, HUD_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
