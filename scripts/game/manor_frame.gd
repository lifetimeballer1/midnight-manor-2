extends StyleBox

# The manor's one panel and button face, drawn as vectors so it stays crisp at any phone
# scale: a clipped-corner plate with a soft drop shadow, a gentle top-to-bottom shade, a
# brass rim, an optional inner hairline and small brass studs on the clipped corners.

var fill: Color = Color("1b1a21")
var fill_top: Color = Color("24222b")
var rim: Color = Color("8a7146")
var rim_width: float = 1.5
var inner: Color = Color(0, 0, 0, 0)   # inner hairline; transparent = none
var inner_inset: float = 4.0
var cut: float = 7.0                    # clipped-corner size
var shadow: float = 6.0
var shadow_alpha: float = 0.42
var lip: float = 0.0                    # darker band along the bottom edge (button depth)
var studs: bool = false                 # brass studs on the clipped corners
var crown: bool = false                 # a small brass diamond on the top rim (sheet panels)
var glow: Color = Color(0, 0, 0, 0)     # outer glow (ready / selected states)


func _octagon(rect: Rect2, c: float) -> PackedVector2Array:
	c = minf(c, minf(rect.size.x, rect.size.y) * 0.5)
	var a: Vector2 = rect.position
	var b: Vector2 = rect.end
	return PackedVector2Array([
		Vector2(a.x + c, a.y), Vector2(b.x - c, a.y), Vector2(b.x, a.y + c), Vector2(b.x, b.y - c),
		Vector2(b.x - c, b.y), Vector2(a.x + c, b.y), Vector2(a.x, b.y - c), Vector2(a.x, a.y + c),
	])


func _ring(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed


func _draw(item: RID, rect: Rect2) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var rs := RenderingServer
	if shadow > 0.0:
		# Two stacked, offset plates fake a soft blur without a shader.
		for step: int in 3:
			var grow: float = shadow * (0.35 + 0.33 * float(step))
			var shade := Color(0, 0, 0, shadow_alpha * (0.5 - 0.14 * float(step)))
			var plate := _octagon(Rect2(rect.position + Vector2(0, shadow * 0.4), rect.size).grow(grow), cut + grow * 0.6)
			rs.canvas_item_add_polygon(item, plate, PackedColorArray([shade]))
	if glow.a > 0.0:
		for step: int in 3:
			var g: float = 2.0 + 2.5 * float(step)
			rs.canvas_item_add_polyline(item, _ring(_octagon(rect.grow(g), cut + g * 0.6)), PackedColorArray([Color(glow, glow.a * (0.6 - 0.18 * float(step)))]), 2.0, true)
	var body := _octagon(rect, cut)
	var colors := PackedColorArray()
	for p: Vector2 in body:
		colors.append(fill_top.lerp(fill, clampf((p.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
	rs.canvas_item_add_polygon(item, body, colors)
	if lip > 0.0:
		var low := _octagon(rect.grow(-lip * 0.5), maxf(0.0, cut - lip * 0.2))
		rs.canvas_item_add_polyline(item, PackedVector2Array([low[3], low[4], low[5], low[6]]), PackedColorArray([Color(0, 0, 0, 0.32)]), lip, true)
	# A faint lit edge along the top: the plate catches the moonlight.
	var lit := Color(1, 0.96, 0.86, 0.07)
	rs.canvas_item_add_line(item, Vector2(rect.position.x + cut, rect.position.y + rim_width + 0.5), Vector2(rect.end.x - cut, rect.position.y + rim_width + 0.5), lit, 1.0, true)
	if inner.a > 0.0:
		var inset: Rect2 = rect.grow(-inner_inset)
		if inset.size.x > 4.0 and inset.size.y > 4.0:
			rs.canvas_item_add_polyline(item, _ring(_octagon(inset, maxf(1.0, cut - inner_inset * 0.6))), PackedColorArray([inner]), 1.0, true)
	if rim.a > 0.0 and rim_width > 0.0:
		var half: float = rim_width * 0.5
		rs.canvas_item_add_polyline(item, _ring(_octagon(rect.grow(-half), maxf(0.0, cut - half * 0.4))), PackedColorArray([rim]), rim_width, true)
	if studs and cut >= 4.0:
		var r: float = clampf(cut * 0.28, 1.5, 3.0)
		var k: float = cut * 0.5
		for p: Vector2 in [rect.position + Vector2(k, k), Vector2(rect.end.x - k, rect.position.y + k), rect.end - Vector2(k, k), Vector2(rect.position.x + k, rect.end.y - k)]:
			_diamond(item, p, r, rim.lightened(0.25))
	if crown and rect.size.x > 80.0:
		var top := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rim_width * 0.5)
		rs.canvas_item_add_line(item, top - Vector2(22, 0), top + Vector2(22, 0), rim.lightened(0.2), rim_width + 0.5, true)
		_diamond(item, top, 4.5, rim.lightened(0.3))
		_diamond(item, top, 2.0, fill)


func _diamond(item: RID, centre: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array([centre + Vector2(0, -r), centre + Vector2(r, 0), centre + Vector2(0, r), centre + Vector2(-r, 0)])
	RenderingServer.canvas_item_add_polygon(item, pts, PackedColorArray([color]))
	RenderingServer.canvas_item_add_polyline(item, _ring(pts), PackedColorArray([color]), 1.0, true)
