extends Node

# Startup loading screen. Loads the village scene and warms the resource cache
# with the models, shaders and sounds the manor reaches for first, one item at a
# time within a small per-frame budget so the bar and status line stay live
# (also on single-threaded web builds). Then instantiates the game, makes it the
# current scene and fades this overlay out over it.

const GAME_SCENE: String = "res://scenes/game.tscn"
const CATALOG: String = "res://art/catalog.json"
const BG_PORTRAIT: Texture2D = preload("res://ui/loading/background_portrait.jpg")
const BG_LANDSCAPE: Texture2D = preload("res://ui/loading/background_landscape.jpg")
const LOGO: Texture2D = preload("res://ui/loading/logo.png")
const TITLE_FONT: Font = preload("res://ui/loading/Cinzel-Bold.ttf")

const FRAME_BUDGET_MSEC: int = 12
# The bar never fills faster than this, so a fast machine still shows the screen.
const MIN_SECONDS: float = 3.0
const FADE_SECONDS: float = 0.6
const LAYER: int = 120
const GOLD := Color("d4b275")
const PALE_GOLD := Color("f6deaa")
const DIM_TEXT := Color("b2a68e")

var _items: Array[Dictionary] = []
var _held: Array[Resource] = []
var _next: int = 0
var _shown: float = 0.0
var _game_packed: PackedScene
var _handing_over: bool = false

var _layer: CanvasLayer
var _screen: Control
var _bg: TextureRect
var _logo: TextureRect
var _title: Label
var _status: Label
var _bar: LoadingBar


func _ready() -> void:
	# Capture command lines drive the game scene directly.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture"):
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
			return
	_build_ui()
	_plan()


func _plan() -> void:
	# Each stage gets a share of the bar however many files it holds.
	_add_group(["Waking the manor"], [GAME_SCENE], 12.0)
	var shaders: Array[String] = _list("res://shaders/", [".gdshader"])
	_add_group(["Rendering terrain"], shaders, 10.0)
	var buildings: Array[String] = []
	var characters: Array[String] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if parsed is Dictionary:
		for entry: Dictionary in parsed.get("assets", []):
			var asset: String = str(entry.get("asset", ""))
			if entry.get("kind") == "character":
				characters.append(asset)
			elif asset.ends_with("_t1"):
				buildings.append(asset)
	_add_group(buildings.map(func(a: String) -> String: return "Rendering buildings: %s" % _pretty(a.trim_suffix("_t1"))),
		buildings.map(_glb), 34.0)
	_add_group(characters.map(func(a: String) -> String: return "Rendering characters: %s" % _pretty(a.trim_prefix("char_"))),
		characters.map(_glb), 22.0)
	_add_group(["Tuning the sounds"], _list("res://audio/", [".ogg", ".wav", ".mp3"]), 10.0)
	_add_group(["Raising the village"], [""], 12.0)
	var total: float = 0.0
	for item in _items:
		total += item["weight"]
	var running: float = 0.0
	for item in _items:
		running += item["weight"]
		item["end"] = running / total


# labels holds one label per path, or a single label shared by every path.
func _add_group(labels: Array, paths: Array, share: float) -> void:
	var kept: Array[Dictionary] = []
	for i in paths.size():
		var path: String = paths[i]
		if path.is_empty() or ResourceLoader.exists(path):
			kept.append({"label": labels[i] if labels.size() == paths.size() else labels[0], "path": path})
	for item in kept:
		item["weight"] = share / kept.size()
		_items.append(item)


func _glb(asset: String) -> String:
	return "res://art/%s/%s.glb" % [asset, asset]


func _pretty(stem: String) -> String:
	return stem.replace("-", " ").replace("_", " ").capitalize()


func _list(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			out.append_array(_list(dir + entry, exts))
			continue
		for ext: String in exts:
			if entry.ends_with(ext):
				out.append(dir + entry)
	return out


func _process(delta: float) -> void:
	if _items.is_empty() or _handing_over:
		return
	var start: int = Time.get_ticks_msec()
	# Load ahead of the bar, but never into the final step: that one runs at handover.
	while _next < _items.size() - 1 and Time.get_ticks_msec() - start < FRAME_BUDGET_MSEC:
		var path: String = _items[_next]["path"]
		var res: Resource = load(path)
		if res != null:
			_held.append(res)
			if path == GAME_SCENE:
				_game_packed = res as PackedScene
		_next += 1
	var loaded: float = _items[_next - 1]["end"] if _next > 0 else 0.0
	_shown = move_toward(_shown, loaded, delta / MIN_SECONDS)
	_refresh()
	if not _handing_over and _next == _items.size() - 1 and is_equal_approx(_shown, loaded):
		_handing_over = true
		_hand_over.call_deferred()


func _refresh() -> void:
	var label: String = _items[-1]["label"]
	for item in _items:
		if _shown < item["end"]:
			label = item["label"]
			break
	_status.text = label + "..."
	_bar.value = _shown


func _hand_over() -> void:
	_status.text = "Raising the village..."
	# Let the status line reach the screen before the heavy instantiate.
	await get_tree().process_frame
	await get_tree().process_frame
	if _game_packed == null:
		_game_packed = load(GAME_SCENE)
	var game: Node = _game_packed.instantiate()
	var root: Window = get_tree().root
	remove_child(_layer)
	root.add_child(_layer)
	root.add_child(game)
	get_tree().current_scene = game
	_bar.value = 1.0
	_status.text = "Welcome home."
	var tween: Tween = _layer.create_tween()
	tween.tween_interval(0.25)
	tween.tween_property(_screen, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(_layer.queue_free)
	_held.clear()
	queue_free()


# --- presentation -----------------------------------------------------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	add_child(_layer)
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_screen)
	var backdrop := ColorRect.new()
	backdrop.color = Color("070a16")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(backdrop)
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(_bg)
	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screen.add_child(_logo)
	_title = _label(TITLE_FONT, PALE_GOLD)
	_title.text = "Loading..."
	_status = _label(TITLE_FONT, DIM_TEXT)
	_bar = LoadingBar.new()
	_screen.add_child(_bar)
	_screen.resized.connect(_layout)
	_layout()


func _label(font: Font, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 6)
	_screen.add_child(label)
	return label


func _layout() -> void:
	var size: Vector2 = _screen.size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var wide: bool = size.x > size.y
	_bg.texture = BG_LANDSCAPE if wide else BG_PORTRAIT
	var logo_aspect: float = float(LOGO.get_width()) / LOGO.get_height()
	var logo_h: float = minf(size.y * (0.28 if wide else 0.24), size.x * 0.86 / logo_aspect)
	_logo.size = Vector2(logo_h * logo_aspect, logo_h)
	_logo.position = Vector2((size.x - _logo.size.x) * 0.5, size.y * 0.035)
	var unit: float = clampf(minf(size.x, size.y * 0.55) / 390.0, 0.8, 1.6)
	var bar_w: float = minf(size.x * 0.74, 520.0 * unit)
	var bar_h: float = 13.0 * unit
	_bar.size = Vector2(bar_w, bar_h)
	_bar.position = Vector2((size.x - bar_w) * 0.5, size.y * 0.905)
	_title.add_theme_font_size_override("font_size", int(22 * unit))
	_title.size = Vector2(size.x, 30 * unit)
	_title.position = Vector2(0, _bar.position.y - 42 * unit)
	_status.add_theme_font_size_override("font_size", int(12 * unit))
	_status.size = Vector2(size.x, 18 * unit)
	_status.position = Vector2(0, _bar.position.y + bar_h + 12 * unit)


class LoadingBar extends Control:
	# Gold-framed bar with pointed end caps, a warm glowing fill and a bright head.
	var value: float = 0.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var cap: float = h * 0.9
		var pad: float = h * 0.25
		var frame := PackedVector2Array([
			Vector2(-cap, h * 0.5), Vector2(0, -pad), Vector2(w, -pad),
			Vector2(w + cap, h * 0.5), Vector2(w, h + pad), Vector2(0, h + pad)])
		draw_colored_polygon(frame, Color("1a120c"))
		var outline := frame.duplicate()
		outline.append(frame[0])
		draw_polyline(outline, Color("c8a058"), maxf(1.5, h * 0.12), true)
		draw_rect(Rect2(0, 0, w, h), Color("100c0a"))
		var fx: float = w * value
		if fx > 1.0:
			draw_rect(Rect2(0, -h * 0.35, fx, h * 1.7), Color(1.0, 0.7, 0.3, 0.12))
			var top := Color("ffe496")
			var low := Color("be6e1e")
			draw_polygon(
				PackedVector2Array([Vector2(1, 1), Vector2(fx, 1), Vector2(fx, h - 1), Vector2(1, h - 1)]),
				PackedColorArray([top, top, low, low]))
			draw_rect(Rect2(1, 1, fx - 1, h * 0.28), Color(1, 1, 1, 0.22))
			draw_circle(Vector2(fx, h * 0.5), h * 0.62, Color(1.0, 0.85, 0.5, 0.35))
			draw_circle(Vector2(fx, h * 0.5), h * 0.36, Color("fff5d2"))
		var c: float = w * 0.5
		var d: float = h * 0.45
		draw_colored_polygon(PackedVector2Array([
			Vector2(c, -pad - d * 2.2), Vector2(c + d, -pad - d * 1.1),
			Vector2(c, -pad), Vector2(c - d, -pad - d * 1.1)]), Color("d6ac5c"))
