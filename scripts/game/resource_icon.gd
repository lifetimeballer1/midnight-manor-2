extends Control

# Small hand-drawn HUD icons (log, wheat, coin, planks, stone, villager). Drawn with
# vector calls so they stay crisp at any UI scale and need no texture imports.
# Purely cosmetic: the resource rows and collect glyphs use them in place of letters.

const BARK := Color("6e4628")
const WOOD := Color("a8703f")
const RING := Color("e0b47a")
const WHEAT := Color("e2bb57")
const WHEAT_DARK := Color("a8822f")
const COIN := Color("e8c25a")
const COIN_RIM := Color("9a7426")
const COIN_SHINE := Color("fff1b8")
const PLANK := Color("c9925a")
const PLANK_DARK := Color("7d5530")
const STONE := Color("a3a097")
const STONE_DARK := Color("67645d")
const STONE_LIGHT := Color("d2cec3")
const PAPER := Color("e8dcc0")
const OUTLINE := Color(0.06, 0.04, 0.03, 0.85)

var kind: String = "":
	set(value):
		kind = value
		queue_redraw()


static func make(resource: String, side: float = 18.0) -> Control:
	var icon: Control = load("res://scripts/game/resource_icon.gd").new()
	icon.kind = resource
	icon.custom_minimum_size = Vector2(side, side)
	icon.size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if s <= 0.0:
		return
	var o := Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)
	match kind:
		"wood": _log(o, s)
		"food": _wheat(o, s)
		"gold": _coin(o, s)
		"lumber": _planks(o, s)
		"stone": _stone(o, s)
		"souls": _villager(o, s)


func _p(o: Vector2, s: float, x: float, y: float) -> Vector2:
	return o + Vector2(x, y) * s


func _poly(o: Vector2, s: float, pts: Array, fill: Color, edge: Color = OUTLINE, width: float = 1.2) -> void:
	var packed := PackedVector2Array()
	for p: Vector2 in pts:
		packed.append(o + p * s)
	draw_colored_polygon(packed, fill)
	packed.append(packed[0])
	draw_polyline(packed, edge, width, true)


func _log(o: Vector2, s: float) -> void:
	# A log lying on its side, end grain facing the viewer.
	_poly(o, s, [Vector2(0.30, 0.28), Vector2(0.92, 0.28), Vector2(0.92, 0.72), Vector2(0.30, 0.72)], BARK)
	draw_line(_p(o, s, 0.45, 0.42), _p(o, s, 0.86, 0.42), Color(WOOD, 0.8), maxf(1.0, s * 0.06), true)
	draw_line(_p(o, s, 0.40, 0.58), _p(o, s, 0.80, 0.58), Color(WOOD, 0.6), maxf(1.0, s * 0.05), true)
	draw_circle(_p(o, s, 0.30, 0.50), s * 0.25, OUTLINE, true, -1.0, true)
	draw_circle(_p(o, s, 0.30, 0.50), s * 0.215, WOOD, true, -1.0, true)
	draw_arc(_p(o, s, 0.30, 0.50), s * 0.13, 0.0, TAU, 16, RING, maxf(1.0, s * 0.05), true)
	draw_circle(_p(o, s, 0.30, 0.50), s * 0.04, BARK, true, -1.0, true)


func _wheat(o: Vector2, s: float) -> void:
	# Three bound stalks with plump ears.
	var width: float = maxf(1.0, s * 0.07)
	for lean: float in [-0.16, 0.0, 0.16]:
		var top := Vector2(0.5 + lean, 0.12)
		draw_line(_p(o, s, 0.5, 0.92), _p(o, s, top.x, top.y + 0.18), WHEAT_DARK, width, true)
		for k in 3:
			var y: float = top.y + 0.04 + float(k) * 0.12
			for side: float in [-1.0, 1.0]:
				var c := Vector2(top.x + side * 0.055, y + 0.05)
				_ellipse(o + c * s, Vector2(0.05, 0.075) * s, WHEAT, side * 0.5)
		_ellipse(o + Vector2(top.x, top.y) * s, Vector2(0.04, 0.07) * s, WHEAT, 0.0)
	draw_line(_p(o, s, 0.36, 0.66), _p(o, s, 0.64, 0.66), BARK, maxf(1.5, s * 0.1), true)


func _ellipse(c: Vector2, r: Vector2, fill: Color, turn: float) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a: float = TAU * float(k) / 10.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(turn))
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, Color(WHEAT_DARK, 0.9), 1.0, true)


func _coin(o: Vector2, s: float) -> void:
	var c := _p(o, s, 0.5, 0.5)
	draw_circle(c, s * 0.42, OUTLINE, true, -1.0, true)
	draw_circle(c, s * 0.38, COIN_RIM, true, -1.0, true)
	draw_circle(c, s * 0.31, COIN, true, -1.0, true)
	draw_arc(c, s * 0.22, PI * 1.05, PI * 1.6, 8, COIN_SHINE, maxf(1.0, s * 0.07), true)
	# A small crescent moon stamped on the face.
	draw_arc(c + Vector2(s * 0.02, 0.0), s * 0.12, PI * 0.35, PI * 1.65, 12, COIN_RIM, maxf(1.2, s * 0.08), true)


func _planks(o: Vector2, s: float) -> void:
	for k in 3:
		var y: float = 0.22 + float(k) * 0.2
		var shift: float = 0.06 if k == 1 else 0.0
		_poly(o, s, [Vector2(0.1 + shift, y), Vector2(0.9 + shift * 0.5, y), Vector2(0.9 + shift * 0.5, y + 0.17), Vector2(0.1 + shift, y + 0.17)], PLANK)
		draw_line(_p(o, s, 0.25 + shift, y + 0.085), _p(o, s, 0.7, y + 0.085), Color(PLANK_DARK, 0.7), 1.0, true)


func _stone(o: Vector2, s: float) -> void:
	_poly(o, s, [Vector2(0.12, 0.72), Vector2(0.2, 0.4), Vector2(0.42, 0.2), Vector2(0.72, 0.24), Vector2(0.9, 0.5), Vector2(0.84, 0.8), Vector2(0.4, 0.86)], STONE)
	draw_colored_polygon(PackedVector2Array([_p(o, s, 0.22, 0.42), _p(o, s, 0.42, 0.24), _p(o, s, 0.6, 0.3), _p(o, s, 0.38, 0.5)]), STONE_LIGHT)
	draw_colored_polygon(PackedVector2Array([_p(o, s, 0.62, 0.62), _p(o, s, 0.86, 0.52), _p(o, s, 0.82, 0.78), _p(o, s, 0.5, 0.82)]), STONE_DARK)


func _villager(o: Vector2, s: float) -> void:
	draw_circle(_p(o, s, 0.5, 0.3), s * 0.17, PAPER, true, -1.0, true)
	var body := PackedVector2Array()
	for k in 13:
		var a: float = PI + PI * float(k) / 12.0
		body.append(_p(o, s, 0.5 + cos(a) * 0.33, 0.9 + sin(a) * 0.36))
	draw_colored_polygon(body, PAPER)
