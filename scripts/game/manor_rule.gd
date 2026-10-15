extends StyleBox

# Ornamental divider: a hairline that fades out at both ends, with a small brass lozenge
# in the middle. Used by HSeparator and under titles.

var color: Color = Color("8a7146")
var thickness: float = 1.0
var lozenge: bool = true


func _draw(item: RID, rect: Rect2) -> void:
	if rect.size.x < 8.0:
		return
	var y: float = rect.position.y + rect.size.y * 0.5
	var a: float = rect.position.x
	var b: float = rect.end.x
	var mid: float = (a + b) * 0.5
	var fade := Color(color, 0.0)
	var points := PackedVector2Array([Vector2(a, y), Vector2(a + (mid - a) * 0.35, y), Vector2(mid, y), Vector2(b - (b - mid) * 0.35, y), Vector2(b, y)])
	var colors := PackedColorArray([fade, color, color, color, fade])
	RenderingServer.canvas_item_add_polyline(item, points, colors, thickness, true)
	if lozenge:
		var r: float = 3.5
		var c := Vector2(mid, y)
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 1.4, 0), c + Vector2(0, r), c + Vector2(-r * 1.4, 0)])
		RenderingServer.canvas_item_add_polygon(item, pts, PackedColorArray([color.lightened(0.15)]))
