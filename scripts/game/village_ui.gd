extends Node
class_name VillageUI

# Dark-medieval presentation helpers for the manor: one shared theme, build-card
# categories, cached model thumbnails and the soft ground textures used by the
# living-trail renderer. Nothing here owns simulation state.

const ResourceIcon = preload("res://scripts/game/resource_icon.gd")
const THUMB_SIZE: int = 96
const THUMB_CACHE_LIMIT: int = 32
const THUMB_RENDER_SIZE: int = 256
# Director-locked UI update (Balanced HUD / Left rail / Compact cards / Both responsive).
const SAFE_MARGIN: float = 24.0
const MIN_HIT: float = 44.0
const RAIL_WIDTH: float = 76.0
const TOP_BAR_H: float = 72.0
const BOTTOM_BAR_H: float = 108.0
const COMPACT_CARD_W: float = 176.0
const COMPACT_CARD_H: float = 212.0
const CARD_THUMB_H: float = 96.0
enum CardState { AVAILABLE, LOCKED, UPGRADEABLE }
# --- Moonlit manor palette ---------------------------------------------------
# Night-ink plates with a faint violet cast, warm parchment type and antique brass trim.
# The village below is warm lamplight on grass, so the chrome stays cool and quiet and the
# brass is saved for edges, titles and the one action that matters on each screen.
const INK := Color("0f0e13")
const NAVY := Color("1b1a21")
const SLATE := Color("2c2a35")
const EDGE := Color("7a6a50")
const GOLD := Color("e2c381")
const PAPER := Color("ece3cd")
const MUTED := Color("a89d88")        # secondary text
const BLOOD := Color("8a302b")

const WALNUT := Color("1b1a21")       # panel plate
const WALNUT_LIGHT := Color("2a2832") # button face
const IRON := Color("121117")
const IRON_EDGE := Color("4d4656")
const LEATHER := Color("23212b")      # inset rows
const PARCHMENT := Color("e7d9b9")    # information surfaces
const PARCHMENT_INK := Color("2e2318")
const BRASS := Color("c9a45a")        # antique brass accent
const BRASS_SOFT := Color("8a7146")
const RIVET := Color("7d6a4f")
const READY := Color("e0a246")        # amber ready state
const DANGER := Color("8a302b")       # oxblood raid state
const DISABLED := Color("19181e")
const POSITIVE := Color("6f8f52")
const SEALED := Color("c9a45a")

const ManorFrame = preload("res://scripts/game/manor_frame.gd")
const ManorRule = preload("res://scripts/game/manor_rule.gd")
const ManorIcons = preload("res://scripts/game/manor_icons.gd")
const BODY_FILE: FontFile = preload("res://ui/fonts/Signika.ttf")
const DISPLAY_FILE: FontFile = preload("res://ui/loading/Cinzel-Bold.ttf")

const CATEGORIES: Array[String] = ["Economy", "Homes", "Defense", "Roads"]
const CATEGORY_TYPES: Dictionary = {
	"Economy": ["farm", "lumber", "timber_yard", "mine", "pond", "grove", "sawmill", "stone_quarry"],
	"Homes": ["cottage", "pasture", "storehouse", "bathhouse"],
	"Defense": ["barracks", "tower", "archer_tower", "trap", "wall", "stonewall", "gate"],
	"Roads": [],
}

const RESOURCE_TINTS: Dictionary = {
	"wood": Color("9a6a3a"),
	"food": Color("6f9150"),
	"gold": BRASS,
	"lumber": Color("b89a68"),
	"stone": Color("8a93a0"),
}

signal thumbnail_ready(asset_key: String)

var cache: Dictionary = {}
var sources: Dictionary = {}
var queue: Array[String] = []
var factories: Dictionary = {}
var busy: bool = false
var rendered: int = 0
var placeholders: int = 0


static var _fonts: Dictionary = {}


# BODY: Signika, a soft humanist sans with a tall x-height, so small phone text stays
# readable. STRONG is the same face heavier, for buttons and numbers. DISPLAY is Cinzel,
# the carved capitals from the loading screen, for titles and the primary action.
static func font(kind: String = "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var made := FontVariation.new()
	match kind:
		"display":
			made.base_font = DISPLAY_FILE
			made.spacing_glyph = 1
		"caps":
			made.base_font = DISPLAY_FILE
		"strong":
			made.base_font = BODY_FILE
			made.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
		_:
			made.base_font = BODY_FILE
			made.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 440}
	made.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	# Glyphs the face lacks fall back to Godot's built-in font instead of drawing boxes.
	made.fallbacks = [ThemeDB.fallback_font]
	_fonts[kind] = made
	return made


static var _separator: RegEx = null


# Display-only tidy for notices written by the simulation: " / " between words reads as a
# separator dot, while a ratio such as "3 / 5" keeps its slash.
# Amounts the player holds or pays, readable at any size: 950, 2,944, 12.4K, 123K, 3.1M, 1.2B.
# Under ten thousand the exact amount shows, so costs and stores still compare to the unit.
static func big_number(value: float) -> String:
	var amount: float = absf(value)
	var minus: String = "-" if value < 0.0 else ""
	if amount >= 1.0e9:
		return minus + _tenths(amount / 1.0e9) + "B"
	if amount >= 1.0e6:
		return minus + _tenths(amount / 1.0e6) + "M"
	if amount >= 1.0e5:
		return minus + "%dK" % int(amount / 1000.0)
	if amount >= 1.0e4:
		return minus + _tenths(amount / 1000.0) + "K"
	var whole: int = int(amount)
	if whole >= 1000:
		return minus + "%d,%03d" % [whole / 1000, whole % 1000]
	return minus + "%d" % whole


# One decimal, rounded down so a store never reads as more than it holds.
static func _tenths(value: float) -> String:
	return ("%.1f" % (floorf(value * 10.0 + 0.0001) / 10.0)).trim_suffix(".0")


static func tidy(text: String) -> String:
	if not text.contains(" / "):
		return text
	if _separator == null:
		_separator = RegEx.create_from_string("(?<!\\d) / | / (?!\\d)")
	return _separator.sub(text, " · ", true)


static func icon(name: String, side: int = 26) -> Texture2D:
	return ManorIcons.texture(name, side)


# FRAME: the one plate every panel and button is cut from.
func frame(fill: Color, rim: Color, cut: float = 7.0, shadow: float = 6.0, margin: float = 10.0) -> ManorFrame:
	var box := ManorFrame.new()
	box.fill = fill
	box.fill_top = fill.lightened(0.07)
	box.rim = rim
	box.cut = cut
	box.shadow = shadow
	box.set_content_margin_all(margin)
	return box


func style(fill: Color = NAVY, border: Color = BRASS_SOFT) -> ManorFrame:
	var box: ManorFrame = frame(Color(fill, 0.97), border, 8.0, 6.0, 12.0)
	box.studs = true
	box.inner = Color(border, 0.22)
	return box


# SEPARATOR RULE: a hairline that fades at both ends, with a brass lozenge in the middle.
func rule_box(color: Color) -> StyleBox:
	var box := ManorRule.new()
	box.color = color
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


# FOCUS RING: a brass outline only, so keyboard focus never hides the button face.
func focus_ring() -> ManorFrame:
	var ring := ManorFrame.new()
	ring.fill = Color(0, 0, 0, 0)
	ring.fill_top = Color(0, 0, 0, 0)
	ring.rim = Color(GOLD, 0.8)
	ring.rim_width = 1.5
	ring.cut = 5.0
	ring.shadow = 0.0
	return ring


func theme() -> Theme:
	var built := Theme.new()
	built.default_font = font("body")
	built.default_font_size = 15
	built.set_font("font", "Button", font("strong"))
	built.set_font("font", "Label", font("body"))
	built.set_color("font_color", "Label", PAPER)
	built.set_color("font_color", "Button", PAPER)
	built.set_color("font_hover_color", "Button", Color("fff4dc"))
	built.set_color("font_pressed_color", "Button", GOLD)
	built.set_color("font_focus_color", "Button", PAPER)
	built.set_color("font_disabled_color", "Button", Color(MUTED, 0.55))
	built.set_color("icon_normal_color", "Button", Color(PAPER, 0.92))
	built.set_color("icon_hover_color", "Button", GOLD)
	built.set_color("icon_pressed_color", "Button", GOLD)
	built.set_color("icon_focus_color", "Button", PAPER)
	built.set_color("icon_disabled_color", "Button", Color(MUTED, 0.45))
	built.set_constant("h_separation", "Button", 6)
	built.set_stylebox("panel", "PanelContainer", style(NAVY))
	built.set_stylebox("panel", "Panel", style(NAVY))
	built.set_color("font_color", "ProgressBar", GOLD)
	# Inset track: a dark recess with a hairline rim, so the empty part still reads as a slot.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.9)
	track.border_color = Color(IRON_EDGE, 0.9)
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	track.set_content_margin_all(0)
	built.set_stylebox("background", "ProgressBar", track)
	built.set_stylebox("fill", "ProgressBar", gauge_fill(BRASS))
	# Buttons: resting, brighter rim on hover, sunk face on press, hollow when disabled.
	built.set_stylebox("normal", "Button", command_box(WALNUT_LIGHT, BRASS_SOFT))
	built.set_stylebox("hover", "Button", command_box(WALNUT_LIGHT.lightened(0.08), BRASS))
	built.set_stylebox("pressed", "Button", command_box(INK, BRASS_SOFT, 1, true))
	built.set_stylebox("disabled", "Button", command_box(DISABLED, Color(IRON_EDGE, 0.7), 0))
	built.set_stylebox("focus", "Button", focus_ring())
	built.set_stylebox("separator", "HSeparator", rule_box(Color(BRASS_SOFT, 0.75)))
	built.set_constant("separation", "HSeparator", 10)
	# Thin brass scroll thumbs instead of the grey defaults.
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(BRASS_SOFT, 0.75)
	grabber.set_corner_radius_all(3)
	grabber.content_margin_left = 3
	grabber.content_margin_right = 3
	var grabber_hot := grabber.duplicate()
	grabber_hot.bg_color = BRASS
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(INK, 0.45)
	groove.set_corner_radius_all(3)
	groove.content_margin_left = 3
	groove.content_margin_right = 3
	built.set_stylebox("grabber", "VScrollBar", grabber)
	built.set_stylebox("grabber_highlight", "VScrollBar", grabber_hot)
	built.set_stylebox("grabber_pressed", "VScrollBar", grabber_hot)
	built.set_stylebox("scroll", "VScrollBar", groove)
	built.set_color("font_color", "TooltipLabel", PAPER)
	built.set_stylebox("panel", "TooltipPanel", frame(Color(INK, 0.97), BRASS_SOFT, 4.0, 3.0, 8.0))
	return built


# BRASS RULE: a thin divider that separates panel sections without stealing space.
func rule(parent: Node) -> HSeparator:
	var made := HSeparator.new()
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(made)
	return made


# TITLE: carved Cinzel capitals in brass.
func heading(text: String, parent: Node) -> Label:
	var made := Label.new()
	made.text = text
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Cinzel's figures read as Roman letters (a "1" looks like an "I"), so a title that carries
	# a number is set in the heavy body face instead.
	var numbered: bool = RegEx.create_from_string("\\d").search(text) != null
	made.add_theme_font_override("font", font("strong" if numbered else "display"))
	made.add_theme_font_size_override("font_size", 20)
	made.add_theme_color_override("font_color", GOLD)
	made.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	made.add_theme_constant_override("shadow_offset_y", 1)
	made.add_theme_constant_override("shadow_offset_x", 0)
	made.set_meta("heading", true)
	parent.add_child(made)
	return made


# KICKER: the small spaced capitals above a group of controls.
func kicker(text: String, parent: Node) -> Label:
	var made := Label.new()
	made.text = text
	made.add_theme_font_override("font", font("display"))
	made.add_theme_font_size_override("font_size", 11)
	made.add_theme_color_override("font_color", Color(BRASS, 0.85))
	parent.add_child(made)
	return made


func body(text: String, parent: Node, size: int = 14) -> Label:
	var made := Label.new()
	made.text = text
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	made.add_theme_font_size_override("font_size", size)
	made.add_theme_color_override("font_color", PAPER if size >= 14 else Color(PAPER, 0.82))
	parent.add_child(made)
	return made


func button(text: String, action: Callable, parent: Node, minimum: float = 44.0) -> Button:
	var made := Button.new()
	made.text = text
	made.focus_mode = Control.FOCUS_ALL
	made.custom_minimum_size.y = maxf(MIN_HIT, minimum)
	made.pressed.connect(action)
	parent.add_child(made)
	return made


# GAUGE: brass by default. A resource passes its own tint and capacity=true, and the
# fill turns READY amber when value reaches maximum. Repaints on every value change.
func bar(value: float, maximum: float, parent: Node, tint: Color = BRASS, capacity: bool = false) -> ProgressBar:
	var made := ProgressBar.new()
	made.min_value = 0.0
	made.max_value = maxf(1.0, maximum)
	made.value = clampf(value, 0.0, maxf(1.0, maximum))
	made.show_percentage = false
	made.custom_minimum_size.y = 6
	made.set_meta("gauge_tint", tint)
	made.set_meta("gauge_capacity", capacity)
	made.value_changed.connect(func(_amount: float) -> void: paint_bar(made))
	made.changed.connect(func() -> void: paint_bar(made))
	paint_bar(made)
	parent.add_child(made)
	return made


# Repaints a gauge's fill from its current state. Lit fills get a 3px minimum sliver
# so any value above zero stays visible on a bar that is nearly empty.
func paint_bar(made: ProgressBar) -> void:
	var tint: Color = made.get_meta("gauge_tint", BRASS)
	var at_capacity: bool = bool(made.get_meta("gauge_capacity", false)) and made.value >= made.max_value
	var lit: bool = made.value > made.min_value
	var fill: StyleBoxFlat = gauge_fill(READY if at_capacity else tint, lit)
	if not lit:
		fill.bg_color = Color(0, 0, 0, 0)
		fill.border_width_top = 0
	made.add_theme_stylebox_override("fill", fill)


# GAUGE FILL: flat tint with a 1px lighter top edge (StyleBoxFlat cannot vary colour per side).
func gauge_fill(tint: Color, sliver: bool = false) -> StyleBoxFlat:
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.border_color = tint.lightened(0.35)
	fill.border_width_top = 1
	fill.set_corner_radius_all(2)
	fill.set_content_margin_all(0)
	if sliver:
		fill.expand_margin_left = 3.0
	return fill


# --- Manor component kit ----------------------------------------------------
# Every screen builds from these, so a panel in the tech tree looks like a panel
# on the mission board without either screen restating the styling.

# MANOR PANEL: a night-ink plate with a brass rim and studded corners.
func manor_panel(parent: Node, parchment: bool = false) -> PanelContainer:
	var made := PanelContainer.new()
	made.add_theme_stylebox_override("panel", panel_box(parchment))
	parent.add_child(made)
	return made


func panel_box(parchment: bool = false) -> ManorFrame:
	if parchment:
		var paper: ManorFrame = frame(Color(PARCHMENT, 0.98), BRASS_SOFT, 6.0, 5.0, 10.0)
		paper.fill_top = Color(PARCHMENT, 0.98).lightened(0.05)
		paper.inner = Color(BRASS_SOFT, 0.35)
		return paper
	var box: ManorFrame = frame(Color(WALNUT, 0.95), BRASS_SOFT, 9.0, 7.0, 12.0)
	box.inner = Color(BRASS, 0.16)
	box.inner_inset = 4.0
	box.studs = true
	return box


# SHEET PANEL: the big menu sheets get a brass crown on the top rim.
func sheet_box() -> ManorFrame:
	var box: ManorFrame = panel_box()
	box.crown = true
	box.content_margin_top = 14
	return box


# NOTICE STRIP: a slim status line for the bottom command bar. Single-line by
# design, so routine notices never become a floating popup.
func notice_box() -> ManorFrame:
	var box: ManorFrame = frame(Color(INK, 0.88), Color(IRON_EDGE, 0.9), 4.0, 0.0, 6.0)
	box.rim_width = 1.0
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


# Recessed inset row: the manor equivalent of a table row. On a parchment sheet the row is
# a slightly darker leaf of the same paper, so dark ink stays readable on it.
func inset_box(paper: bool = false) -> ManorFrame:
	if paper:
		var leaf: ManorFrame = frame(PARCHMENT.darkened(0.08), Color(BRASS_SOFT, 0.7), 5.0, 0.0, 8.0)
		leaf.fill_top = PARCHMENT.darkened(0.04)
		leaf.rim_width = 1.0
		return leaf
	var box: ManorFrame = frame(Color(LEATHER, 0.9), Color(IRON_EDGE, 0.55), 5.0, 0.0, 8.0)
	box.fill_top = Color(LEATHER, 0.9).darkened(0.15)
	box.rim_width = 1.0
	return box


# INSET ROW: a recessed container node, ready to receive children.
func inset_row(parent: Node, paper: bool = false) -> PanelContainer:
	var made := PanelContainer.new()
	made.add_theme_stylebox_override("panel", inset_box(paper))
	parent.add_child(made)
	return made


# COMMAND BUTTON: a clipped plate with a brass edge and a pressed state.
func command_button(text: String, action: Callable, parent: Node, minimum: float = 44.0) -> Button:
	var made := Button.new()
	made.text = text
	made.focus_mode = Control.FOCUS_ALL
	made.custom_minimum_size = Vector2(0, maxf(MIN_HIT, minimum))
	if action.is_valid():
		made.pressed.connect(action)
	paint_command(made, "normal")
	parent.add_child(made)
	return made


func paint_command(node: Button, state: String = "normal") -> void:
	var fill: Color = WALNUT_LIGHT
	var rim: Color = BRASS_SOFT
	var glow := Color(0, 0, 0, 0)
	match state:
		"hover": fill = WALNUT_LIGHT.lightened(0.1)
		"pressed": fill = INK; rim = BRASS
		"disabled": fill = DISABLED; rim = Color(IRON_EDGE, 0.7)
		"gold": fill = Color("9c7a3c"); rim = GOLD
		"ready": fill = Color("3a2d1c"); rim = READY; glow = Color(READY, 0.5)
		"danger": fill = Color("5a2421"); rim = Color("c0594d")
		"done": fill = Color("2b2a22"); rim = SEALED
		"active": fill = Color("2f2a2a"); rim = GOLD; glow = Color(GOLD, 0.4)
	if state == "disabled":
		node.add_theme_stylebox_override("disabled", command_box(fill, rim, 0))
		return
	# Live states get all three faces, so hover and press always read differently.
	var normal: ManorFrame = command_box(fill, rim)
	normal.glow = glow
	node.add_theme_stylebox_override("normal", normal)
	var hover: ManorFrame = command_box(fill.lightened(0.12), rim.lightened(0.2))
	hover.glow = glow
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", command_box(fill.darkened(0.3), rim, 1, true))
	var ink: bool = state == "gold"
	node.add_theme_color_override("font_color", Color("1d150c") if ink else PAPER)
	node.add_theme_color_override("font_hover_color", Color("120c06") if ink else Color("fff4dc"))
	node.add_theme_color_override("font_pressed_color", Color("fff4dc") if ink else GOLD)
	node.add_theme_color_override("font_focus_color", Color("1d150c") if ink else PAPER)
	node.add_theme_color_override("icon_normal_color", Color("1d150c") if ink else Color(PAPER, 0.92))
	node.add_theme_color_override("icon_hover_color", Color("120c06") if ink else GOLD)


# BUTTON FACE: one physical command-button state. A pressed face sinks 1px by moving
# its padding from the bottom to the top, so the label travels with the button.
func command_box(fill: Color, rim: Color, lip: int = 4, sink: bool = false) -> ManorFrame:
	var box: ManorFrame = frame(fill, rim, 5.0, 3.0 if lip > 1 else 0.0, 6.0)
	box.rim_width = 1.25
	box.lip = 3.0 if lip > 1 else 0.0
	box.shadow_alpha = 0.5
	box.content_margin_left = 10
	box.content_margin_right = 10
	if sink:
		box.fill_top = fill
		box.content_margin_top = 7
		box.content_margin_bottom = 5
	return box


# GOLD ACTION BUTTON: the selected or primary action, a brass plate with carved letters.
func gold_button(text: String, action: Callable, parent: Node, minimum: float = 48.0) -> Button:
	var made := command_button(text, action, parent, minimum)
	paint_command(made, "gold")
	# Short commands are carved in Cinzel; long ones that carry a price stay in the body face
	# so they fit a phone-width sheet.
	if text.length() <= 20:
		made.add_theme_font_override("font", font("display"))
		made.add_theme_font_size_override("font_size", 16)
	else:
		made.add_theme_font_size_override("font_size", 16)
	return made


# MENU BACKDROP: a dim veil for a modal menu. Add it before the menu panel so the
# panel draws on top; STOP blocks clicks from reaching the village underneath.
func menu_backdrop(parent: Node) -> ColorRect:
	var veil := ColorRect.new()
	veil.color = Color(0.03, 0.02, 0.06, 0.55)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(veil)
	return veil


# TITLE RULE: a thin brass line under a menu or panel title.
func title_rule(parent: Node) -> HSeparator:
	var made := HSeparator.new()
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	made.custom_minimum_size.y = 8
	made.add_theme_stylebox_override("separator", rule_box(BRASS))
	parent.add_child(made)
	return made


# CREST BADGE: levels, counts and warning values.
func crest(text: String, parent: Node, tone: String = "iron", size: int = 13) -> Label:
	var made := Label.new()
	made.text = text
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	made.add_theme_font_override("font", font("strong"))
	made.add_theme_font_size_override("font_size", size)
	var ink: Color = crest_color(tone)
	made.add_theme_color_override("font_color", ink)
	# A small stamped tag: the tone's colour as a faint wash inside a hairline rim.
	var tag: ManorFrame = frame(Color(ink, 0.1), Color(ink, 0.45), 3.0, 0.0, 0.0)
	tag.fill_top = Color(ink, 0.14)
	tag.rim_width = 1.0
	tag.content_margin_left = 6
	tag.content_margin_right = 6
	tag.content_margin_top = 1
	tag.content_margin_bottom = 1
	made.add_theme_stylebox_override("normal", tag)
	made.custom_minimum_size = Vector2(24, 18)
	parent.add_child(made)
	return made


func crest_color(tone: String) -> Color:
	match tone:
		"gold": return BRASS
		"ready": return READY
		"danger": return Color("d2705f")
		"positive": return Color("8fb070")
		"parchment": return PARCHMENT_INK
	return PAPER


# PORTRAIT MEDALLION: a story character rendered as a struck-metal roundel.
func portrait_medallion(character: String, parent: Node, diameter: float = 44.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(diameter, diameter)
	# Stay round inside taller rows instead of stretching into an oval.
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.tooltip_text = character
	parent.add_child(holder)
	var disc := Panel.new()
	disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("2a2733")
	box.border_color = BRASS
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(diameter * 0.5))
	box.corner_detail = 16
	box.anti_aliasing = true
	box.shadow_size = 4
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_offset = Vector2(0, 1)
	disc.add_theme_stylebox_override("panel", box)
	holder.add_child(disc)
	var initials := Label.new()
	initials.text = _initials(character)
	initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initials.add_theme_font_override("font", font("display"))
	initials.add_theme_font_size_override("font_size", int(diameter * 0.36))
	initials.add_theme_color_override("font_color", GOLD)
	holder.add_child(initials)
	return holder

# SEAL: a struck brass roundel carrying a short value (the act numeral). Returns its label.
func seal(text: String, parent: Node, diameter: float = 38.0) -> Label:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(diameter, diameter)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := StyleBoxFlat.new()
	box.bg_color = Color("2a2530")
	box.border_color = BRASS
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(diameter * 0.5))
	box.corner_detail = 16
	box.shadow_size = 4
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_offset = Vector2(0, 1)
	holder.add_theme_stylebox_override("panel", box)
	parent.add_child(holder)
	var ring := Panel.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.offset_left = 4
	ring.offset_top = 4
	ring.offset_right = -4
	ring.offset_bottom = -4
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_ring := StyleBoxFlat.new()
	inner_ring.draw_center = false
	inner_ring.border_color = Color(BRASS, 0.35)
	inner_ring.set_border_width_all(1)
	inner_ring.set_corner_radius_all(int(diameter * 0.5) - 4)
	inner_ring.corner_detail = 16
	ring.add_theme_stylebox_override("panel", inner_ring)
	holder.add_child(ring)
	var made := Label.new()
	made.text = text
	made.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	made.mouse_filter = Control.MOUSE_FILTER_PASS
	made.add_theme_font_override("font", font("display"))
	made.add_theme_font_size_override("font_size", int(diameter * 0.42))
	made.add_theme_color_override("font_color", GOLD)
	holder.add_child(made)
	return made


func _initials(character: String) -> String:
	var words := PackedStringArray(character.split(" "))
	var letters: String = ""
	for word in words:
		if not word.is_empty():
			letters += word.substr(0, 1)
		if letters.length() >= 2:
			break
	return letters.to_upper() if not letters.is_empty() else "?"


# MISSION BANNER frame: portrait medallion plus a parchment message plate.
func mission_banner(character: String, message: String, parent: Node) -> PanelContainer:
	var made := manor_panel(parent, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	made.add_child(row)
	portrait_medallion(character, row, 40.0)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	if not character.is_empty():
		var who := Label.new()
		who.text = character
		who.add_theme_font_size_override("font_size", 12)
		who.add_theme_color_override("font_color", BRASS_SOFT)
		column.add_child(who)
	var says := Label.new()
	says.text = message
	says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	says.add_theme_font_size_override("font_size", 14)
	says.add_theme_color_override("font_color", PARCHMENT_INK)
	column.add_child(says)
	return made


# RESOURCE ROW: icon glyph, amount, and a recessed capacity gauge tinted by resource key
# ("wood", "food", "gold", "lumber", "stone"). The gauge turns READY amber at capacity.
func resource_row(parent: Node, label: String, glyph: String, key: String = "") -> Dictionary:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	row.add_child(line)
	if RESOURCE_TINTS.has(key):
		line.add_child(ResourceIcon.make(key, 22.0))
	else:
		var icon := Label.new()
		icon.text = glyph
		icon.add_theme_font_size_override("font_size", 13)
		icon.add_theme_color_override("font_color", BRASS_SOFT)
		icon.custom_minimum_size.x = 16
		line.add_child(icon)
	var value := Label.new()
	value.text = label
	value.add_theme_font_override("font", font("strong"))
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", PAPER)
	line.add_child(value)
	var tint: Color = RESOURCE_TINTS.get(key, BRASS)
	return {"row": row, "value": value, "bar": bar(0, 1, row, tint, true)}


# PARAGRAPH on parchment, for story and mission text.
func parchment_text(text: String, parent: Node, size: int = 14) -> Label:
	var made := Label.new()
	made.text = text
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	made.add_theme_font_size_override("font_size", size)
	made.add_theme_color_override("font_color", PARCHMENT_INK)
	parent.add_child(made)
	return made


func chip(text: String, parent: Node) -> Label:
	# Balanced-HUD resource chip: 15px PAPER, tabular numbers, 44px hit via parent.
	var made := Label.new()
	made.text = text
	made.add_theme_font_size_override("font_size", 15)
	made.add_theme_color_override("font_color", PAPER)
	parent.add_child(made)
	return made


func timer_pill(text: String, parent: Node, active: bool = false) -> Label:
	var made := Label.new()
	made.text = text
	made.add_theme_font_size_override("font_size", 12)
	made.add_theme_color_override("font_color", GOLD if active else PAPER)
	parent.add_child(made)
	return made


func card_state_of(locked: bool, upgrade_cost: float = 0.0) -> int:
	if locked:
		return CardState.LOCKED
	if upgrade_cost > 0.0:
		return CardState.UPGRADEABLE
	return CardState.AVAILABLE


func categories_of(type_name: String) -> String:
	for category in CATEGORIES:
		if type_name in CATEGORY_TYPES[category]:
			return category
	return ""


# --- thumbnails -------------------------------------------------------------
# One real SubViewport render per asset, cached. Cards always get an instant
# placeholder and are upgraded in place when the cached render lands.

func texture(asset_key: String, factory: Callable) -> Texture2D:
	sources[asset_key] = asset_key
	if cache.has(asset_key):
		return cache[asset_key]
	var placeholder: Texture2D = _placeholder()
	cache[asset_key] = placeholder
	if cache.size() > THUMB_CACHE_LIMIT:
		cache.clear()
		cache[asset_key] = placeholder
	if not queue.has(asset_key) and queue.size() < THUMB_CACHE_LIMIT:
		factories[asset_key] = factory
		queue.append(asset_key)
	return placeholder


func _process(_delta: float) -> void:
	if busy or queue.is_empty():
		return
	var asset_key: String = queue.pop_front()
	var factory: Callable = factories.get(asset_key, Callable())
	factories.erase(asset_key)
	_render(asset_key, factory)


func _render(asset_key: String, factory: Callable) -> void:
	if not factory.is_valid() or DisplayServer.get_name() == "headless":
		placeholders += 1
		return
	busy = true
	var holder: Node3D = factory.call(asset_key)
	if holder == null:
		busy = false
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(THUMB_SIZE, THUMB_SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	viewport.add_child(holder)
	var bounds: AABB = _bounds(holder)
	var extent: float = maxf(bounds.size.x, bounds.size.z)
	if extent > 0.001:
		extent = maxf(extent, bounds.size.y)
	var focus: Vector3 = bounds.get_center()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(0.4, extent * 1.25)
	camera.near = 0.01
	camera.far = 40.0
	viewport.add_child(camera)
	camera.position = focus + Vector3(0.9, 0.85, 1.1).normalized() * 6.0
	camera.look_at(focus, Vector3.UP)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52, 34, 0)
	key_light.light_energy = 1.35
	key_light.light_color = Color("fff0d2")
	key_light.shadow_enabled = false
	viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-18, -140, 0)
	fill_light.light_energy = 0.45
	fill_light.light_color = Color("9fb4e0")
	fill_light.shadow_enabled = false
	viewport.add_child(fill_light)
	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-20, 115, 0)
	rim_light.light_energy = 0.9
	rim_light.light_color = Color("ffd9a0")
	rim_light.shadow_enabled = false
	viewport.add_child(rim_light)
	await get_tree().process_frame
	await get_tree().process_frame
	var shot: Texture2D = null
	var image: Image = viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		shot = ImageTexture.create_from_image(image)
	viewport.queue_free()
	if shot != null:
		cache[asset_key] = shot
		rendered += 1
	else:
		placeholders += 1
	busy = false
	thumbnail_ready.emit(asset_key)


func _bounds(node: Node) -> AABB:
	var total := AABB()
	var started := false
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D:
			var box: AABB = (current as MeshInstance3D).get_aabb()
			var relative: Transform3D = (node as Node3D).global_transform.affine_inverse() * (current as Node3D).global_transform
			var local: AABB = relative * box
			total = total.merge(local) if started else local
			started = true
		pending.append_array(current.get_children())
	return total


func _placeholder() -> Texture2D:
	var side := 24
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in side:
		for x in side:
			var edge: bool = x < 2 or y < 2 or x >= side - 2 or y >= side - 2
			var inside: bool = absf(float(x) - 11.5) + absf(float(y) - 11.5) < 7.0
			if edge:
				image.set_pixel(x, y, Color(EDGE.r, EDGE.g, EDGE.b, 0.85))
			elif inside:
				image.set_pixel(x, y, Color(0.55, 0.5, 0.4, 0.8))
	return ImageTexture.create_from_image(image)


# --- ground textures --------------------------------------------------------

static func soft_disc_texture() -> ImageTexture:
	var side := 48
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var centre := Vector2(side * 0.5 - 0.5, side * 0.5 - 0.5)
	var reach := side * 0.5
	for y in side:
		for x in side:
			var falloff: float = Vector2(x, y).distance_to(centre) / reach
			var alpha: float = clampf(1.0 - pow(clampf(falloff, 0.0, 1.0), 2.2), 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)


static func cobble_texture() -> ImageTexture:
	var side := 64
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	var stones: Array[Vector2] = []
	for row in 4:
		for column in 4:
			stones.append(Vector2(column * 16 + 8, row * 16 + 8) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)))
	for y in side:
		for x in side:
			var first: float = INF
			var second: float = INF
			var index: int = 0
			for i in stones.size():
				var d: float = Vector2(x, y).distance_squared_to(stones[i])
				if d < first:
					second = first
					first = d
					index = i
				elif d < second: second = d
			var shade: float = 0.58 + (index % 5) * 0.035 - minf(first / 2000, 0.04)
			if second - first < 12: shade = 0.35
			image.set_pixel(x, y, Color(shade, shade * 0.98, shade * 0.92, 1))
	return ImageTexture.create_from_image(image)
