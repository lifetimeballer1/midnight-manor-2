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


func button(text: String, action: Callable, parent: Node, minimum: float = 36.0) -> Button:
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
