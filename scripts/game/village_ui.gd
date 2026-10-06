extends Node
class_name VillageUI

# Dark-medieval presentation helpers for the manor: one shared theme, build-card
# categories, cached model thumbnails and the soft ground textures used by the
# living-trail renderer. Nothing here owns simulation state.

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
const INK := Color("17120d")
const NAVY := Color("29241f")
const SLATE := Color("483e30")
const EDGE := Color("8b795a")
const GOLD := Color("d4b275")
const PAPER := Color("e8dcc0")
const BLOOD := Color("8f3b34")

# --- Manor visual language --------------------------------------------------
# 60% dark carved walnut / blackened iron, 25% parchment / leather, 15% antique
# brass. Kept as a small kit so every surface is built the same way.
const WALNUT := Color("241a13")       # carved dark wood container
const WALNUT_LIGHT := Color("3a2b1e") # raised wood face
const IRON := Color("14110e")         # blackened iron
const IRON_EDGE := Color("6b5c46")    # iron rim
const LEATHER := Color("2e2118")      # inset rows
const PARCHMENT := Color("e6d9b8")    # information surfaces
const PARCHMENT_INK := Color("33261a")
const BRASS := Color("c9a44c")        # antique brass / gold accent
const BRASS_SOFT := Color("8f7434")
const RIVET := Color("7d6a4f")        # bolt heads / rivets
const READY := Color("d79a3c")        # amber ready state
const DANGER := Color("8c2f2a")       # deep crimson raid state
const DISABLED := Color("1b1712")     # desaturated dark wood/iron
const POSITIVE := Color("5f7a45")     # restrained green
const SEALED := Color("c9a44c")       # researched / stamped

const CATEGORIES: Array[String] = ["Economy", "Homes", "Defense", "Roads"]
const CATEGORY_TYPES: Dictionary = {
	"Economy": ["farm", "lumber", "timber_yard", "mine", "pond", "sawmill", "stone_quarry"],
	"Homes": ["cottage", "pasture", "storehouse"],
	"Defense": ["barracks", "tower", "archer_tower", "trap", "wall", "stonewall", "gate"],
	"Roads": [],
}

signal thumbnail_ready(asset_key: String)

var cache: Dictionary = {}
var sources: Dictionary = {}
var queue: Array[String] = []
var factories: Dictionary = {}
var busy: bool = false
var rendered: int = 0
var placeholders: int = 0


func style(fill: Color = NAVY, border: Color = EDGE) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill, 0.97)
	box.border_color = border
	box.set_border_width_all(2)
	box.border_width_bottom = 4
	box.shadow_size = 4
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.set_content_margin_all(10)
	box.set_corner_radius_all(4)
	return box


func theme() -> Theme:
	var built := Theme.new()
	built.default_font_size = 15
	built.set_color("font_color", "Label", PAPER)
	built.set_color("font_color", "Button", PAPER)
	built.set_color("font_hover_color", "Button", GOLD)
	built.set_color("font_disabled_color", "Button", Color("6d6a5f"))
	built.set_stylebox("panel", "PanelContainer", style(NAVY))
	built.set_stylebox("panel", "Panel", style(NAVY))
	built.set_color("font_color", "ProgressBar", GOLD)
	for part in ["background", "fill"]:
		var gauge: StyleBoxFlat = style(INK if part == "background" else GOLD, SLATE)
		gauge.set_content_margin_all(0)
		gauge.set_border_width_all(1)
		gauge.shadow_size = 0
		built.set_stylebox(part, "ProgressBar", gauge)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill: Color = NAVY
		if state == "hover":
			fill = SLATE
		elif state == "pressed":
			fill = INK
		elif state == "disabled":
			fill = Color("1d1812")
		built.set_stylebox(state, "Button", style(fill, EDGE if state != "disabled" else Color("55493a")))
	built.set_stylebox("separator", "HSeparator", style(Color("4a3f2e"), Color("4a3f2e")))
	return built


# BRASS RULE: a thin divider that separates panel sections without stealing space.
func rule(parent: Node) -> HSeparator:
	var made := HSeparator.new()
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(made)
	return made


func heading(text: String, parent: Node) -> Label:
	var made := Label.new()
	made.text = text
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	made.add_theme_font_size_override("font_size", 18)
	made.add_theme_color_override("font_color", GOLD)
	parent.add_child(made)
	return made


func body(text: String, parent: Node, size: int = 14) -> Label:
	var made := Label.new()
	made.text = text
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	made.add_theme_font_size_override("font_size", size)
	made.add_theme_color_override("font_color", PAPER)
	parent.add_child(made)
	return made


func button(text: String, action: Callable, parent: Node, minimum: float = 44.0) -> Button:
	var made := Button.new()
	made.text = text
	made.focus_mode = Control.FOCUS_NONE
	made.custom_minimum_size.y = minimum
	made.pressed.connect(action)
	parent.add_child(made)
	return made


func bar(value: float, maximum: float, parent: Node) -> ProgressBar:
	var made := ProgressBar.new()
	made.min_value = 0.0
	made.max_value = maxf(1.0, maximum)
	made.value = clampf(value, 0.0, maxf(1.0, maximum))
	made.show_percentage = false
	made.custom_minimum_size.y = 7
	parent.add_child(made)
	return made


# --- Manor component kit ----------------------------------------------------
# Every screen builds from these, so a panel in the tech tree looks like a panel
# on the mission board without either screen restating the styling.

# MANOR PANEL: carved dark wood with an iron rim and restrained brass corners.
func manor_panel(parent: Node, parchment: bool = false) -> PanelContainer:
	var made := PanelContainer.new()
	made.add_theme_stylebox_override("panel", panel_box(parchment))
	parent.add_child(made)
	return made


func panel_box(parchment: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	if parchment:
		box.bg_color = Color(PARCHMENT, 0.97)
		box.border_color = Color(BRASS_SOFT)
		box.set_border_width_all(2)
		box.border_width_top = 4
		box.shadow_size = 3
		box.shadow_color = Color(0, 0, 0, 0.3)
		box.set_content_margin_all(10)
		box.set_corner_radius_all(2)
		return box
	box.bg_color = Color(WALNUT, 0.96)
	box.border_color = IRON_EDGE
	box.set_border_width_all(2)
	box.border_width_bottom = 5
	box.shadow_size = 5
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_offset = Vector2(0, 2)
	box.set_content_margin_all(10)
	box.set_corner_radius_all(3)
	return box


# NOTICE STRIP: a slim status line for the bottom command bar. Single-line by
# design, so routine notices never become a floating popup.
func notice_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(WALNUT, 0.94)
	box.border_color = IRON_EDGE
	box.set_border_width_all(1)
	box.border_width_top = 2
	box.shadow_size = 0
	box.set_content_margin_all(6)
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	box.set_corner_radius_all(2)
	return box


# Recessed inset row: the manor equivalent of a table row.
func inset_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(LEATHER, 0.85)
	box.border_color = Color(INK, 0.6)
	box.border_width_left = 2
	box.set_content_margin_all(6)
	box.set_corner_radius_all(2)
	return box


# INSET ROW: a recessed container node, ready to receive children.
func inset_row(parent: Node) -> PanelContainer:
	var made := PanelContainer.new()
	made.add_theme_stylebox_override("panel", inset_box())
	parent.add_child(made)
	return made


# COMMAND BUTTON: brown/iron physical button with a pressed state.
func command_button(text: String, action: Callable, parent: Node, minimum: float = 44.0) -> Button:
	var made := Button.new()
	made.text = text
	made.focus_mode = Control.FOCUS_NONE
	made.custom_minimum_size = Vector2(0, minimum)
	made.pressed.connect(action)
	paint_command(made, "normal")
	parent.add_child(made)
	return made


func paint_command(node: Button, state: String = "normal") -> void:
	var fill: Color = WALNUT_LIGHT
	var rim: Color = IRON_EDGE
	match state:
		"hover": fill = WALNUT_LIGHT.lightened(0.12)
		"pressed": fill = INK
		"disabled": fill = DISABLED; rim = Color(IRON_EDGE, 0.5)
		"gold": fill = Color(BRASS_SOFT, 0.85); rim = BRASS
		"ready": fill = Color(READY, 0.32); rim = READY
		"danger": fill = Color(DANGER, 0.85); rim = Color(DANGER.lightened(0.25))
		"done": fill = Color(SEALED, 0.28); rim = SEALED
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = rim
	box.set_border_width_all(2)
	box.border_width_bottom = 4 if state != "pressed" else 1
	box.set_corner_radius_all(3)
	box.shadow_size = 2
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_offset = Vector2(0, 1)
	box.set_content_margin_all(6)
	node.add_theme_stylebox_override(state if state in ["normal", "hover", "pressed", "disabled"] else "normal", box)


# GOLD ACTION BUTTON: the selected or primary action.
func gold_button(text: String, action: Callable, parent: Node, minimum: float = 48.0) -> Button:
	var made := command_button(text, action, parent, minimum)
	paint_command(made, "gold")
	made.add_theme_color_override("font_color", Color("f6ecd2"))
	made.add_theme_color_override("font_hover_color", Color("fff6e2"))
	return made


# CREST BADGE: levels, counts and warning values.
func crest(text: String, parent: Node, tone: String = "iron", size: int = 13) -> Label:
	var made := Label.new()
	made.text = text
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	made.add_theme_font_size_override("font_size", size)
	made.add_theme_color_override("font_color", crest_color(tone))
	made.custom_minimum_size = Vector2(24, 18)
	parent.add_child(made)
	return made


func crest_color(tone: String) -> Color:
	match tone:
		"gold": return BRASS
		"ready": return READY
		"danger": return Color("d2705f")
		"positive": return Color("8aa86a")
		"parchment": return PARCHMENT_INK
	return PAPER


# PORTRAIT MEDALLION: a story character rendered as a struck-metal roundel.
func portrait_medallion(character: String, parent: Node, diameter: float = 44.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(diameter, diameter)
	holder.tooltip_text = character
	parent.add_child(holder)
	var disc := Panel.new()
	disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(WALNUT_LIGHT)
	box.border_color = BRASS
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(diameter * 0.5))
	box.shadow_size = 3
	box.shadow_color = Color(0, 0, 0, 0.45)
	disc.add_theme_stylebox_override("panel", box)
	holder.add_child(disc)
	var initials := Label.new()
	initials.text = _initials(character)
	initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initials.add_theme_font_size_override("font_size", int(diameter * 0.34))
	initials.add_theme_color_override("font_color", BRASS)
	holder.add_child(initials)
	return holder


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


# RESOURCE ROW: icon glyph, amount, and a recessed capacity gauge.
func resource_row(parent: Node, label: String, glyph: String) -> Dictionary:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	parent.add_child(row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	row.add_child(line)
	var icon := Label.new()
	icon.text = glyph
	icon.add_theme_font_size_override("font_size", 13)
	icon.add_theme_color_override("font_color", BRASS_SOFT)
	icon.custom_minimum_size.x = 16
	line.add_child(icon)
	var value := Label.new()
	value.text = label
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", PAPER)
	line.add_child(value)
	return {"row": row, "value": value, "bar": bar(0, 1, row)}


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
	viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-18, -140, 0)
	fill_light.light_energy = 0.45
	fill_light.light_color = Color("9fb4e0")
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
