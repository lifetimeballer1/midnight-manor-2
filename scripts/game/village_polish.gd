extends "res://scripts/game/village_building_fit.gd"

# Feel layer: small presentation touches with no simulation effect.
#  - A selected building gives a soft squash-and-settle bounce.
#  - HUD buttons dip when pressed and spring back on release.
#  - The HUD clusters fade in one after another when the village opens.
#  - Lighting: depth haze that leaves the village clear, and a cool moonlit
#    night key so lamps and windows read as the warm light sources.
# Only view nodes are animated (building view roots, buttons, HUD panels); sim state,
# saves and layouts are never touched. Every tween is cheap and short.

const SELECT_SQUASH := Vector3(1.07, 0.88, 1.07)
const SELECT_STRETCH := Vector3(0.97, 1.05, 0.97)
const PRESS_SCALE: float = 0.92
const HUD_FADE: float = 0.35
const HUD_STAGGER: float = 0.08
# The camera always sits 60 units from its target, so distance fog was a flat
# milky wash over the whole village. Depth fog starts just past the target.
const HAZE_BEGIN: float = 46.0
const HAZE_END: float = 200.0
const HAZE_NIGHT: float = 0.6
const HAZE_DAY: float = 0.42
const MOON_KEY := Color("9db3e6")      # silver-blue moonlight
const MOON_AMBIENT := Color("8790b8")
const MIST_DAY := Color(0.93, 0.85, 0.68)
const MIST_MOON := Color(0.62, 0.69, 0.84)  # ground mist under the moon reads cool, not lamp-warm
const DAY_KEY := Color("fff0d6")       # warm, clean sunlight
const DAY_SKYFILL := Color("aebfd6")   # cool sky bounce in the shadows
const GOLDEN_KEY := Color("ff8c42")    # deeper amber low sun at dawn and dusk
const GOLDEN_SHADE := Color("8f7fa6")  # dusky violet in the shadows against it

var _polish_selected: int = -1
var _polish_bounce: Tween = null
var _polish_bounce_root: Node3D = null


func _ready() -> void:
	super()
	if is_instance_valid(hud_root):
		_wire_press_juice(hud_root)
	bottom.add_theme_stylebox_override("panel", _bottom_scrim())
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


# --- Lighting ------------------------------------------------------------------

func _apply_lighting() -> void:
	super()
	var b: float = clampf(day_blend, 0.0, 1.0)
	var wet: float = clampf(rain_level, 0.0, 1.0)
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = HAZE_BEGIN - 14.0 * wet
	environment.fog_depth_end = HAZE_END
	environment.fog_depth_curve = 1.2
	environment.fog_density = clampf(lerpf(HAZE_NIGHT, HAZE_DAY, b) + 0.2 * wet, 0.0, 1.0)
	# Full night: the key light becomes the moon. Dawn and dusk keep the sky
	# layer's golden sun, so the cool tint fades out before the ramps.
	var moon_w: float = 1.0 - smoothstep(0.0, 0.3, b)
	sun.light_color = sun.light_color.lerp(MOON_KEY, 0.8 * moon_w)
	sun.light_energy *= lerpf(1.0, 0.6, moon_w)
	environment.ambient_light_color = environment.ambient_light_color.lerp(MOON_AMBIENT, 0.65 * moon_w)
	environment.ambient_light_energy *= lerpf(1.0, 0.72, moon_w)
	# Full day: warm key against cool sky-filled shadows gives the forms depth
	# instead of an all-cream wash. Fades out toward the golden ramps.
	var noon: float = smoothstep(0.75, 1.0, b)
	sun.light_color = sun.light_color.lerp(DAY_KEY, 0.6 * noon)
	environment.ambient_light_color = environment.ambient_light_color.lerp(DAY_SKYFILL, 0.55 * noon)
	# Golden hour: richer amber key against violet shade, so dawn and dusk read
	# as their own time of day instead of a dimmer noon.
	var gold: float = _sky_golden(b) * (1.0 - 0.6 * wet)
	sun.light_color = sun.light_color.lerp(GOLDEN_KEY, 0.45 * gold)
	environment.ambient_light_color = environment.ambient_light_color.lerp(GOLDEN_SHADE, 0.4 * gold)
	environment.ambient_light_energy *= 1.0 - 0.15 * gold


# Ground mist is unshaded; at night its daytime cream read as patches of lamp
# light on the grass. Cool it and thin it under the moon.
func _terrain_apply_night() -> void:
	super()
	var dark: float = maxf(_terrain_night, 0.0)
	for patch: Dictionary in _mist_patches:
		var material := (patch["node"] as MeshInstance3D).material_override as StandardMaterial3D
		var tint: Color = MIST_DAY.lerp(MIST_MOON, dark)
		material.albedo_color = Color(tint.r, tint.g, tint.b, material.albedo_color.a * lerpf(1.0, 0.6, dark))


# --- Bottom bar ----------------------------------------------------------------

# The bottom bar was a solid walnut slab the width of the screen, mostly empty
# behind three buttons. A scrim that fades up from the screen edge keeps the
# buttons and notice line readable while the village shows through above them.
func _bottom_scrim() -> StyleBoxTexture:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UI.WALNUT, 0.0))
	gradient.set_color(1, Color(UI.WALNUT, 0.86))
	gradient.add_point(0.45, Color(UI.WALNUT, 0.5))
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(0.5, 0.0)
	fill.fill_to = Vector2(0.5, 1.0)
	fill.width = 4
	fill.height = 64
	var box := StyleBoxTexture.new()
	box.texture = fill
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 6.0
	return box


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
