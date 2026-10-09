extends "res://scripts/game/village_raid_pace.gd"

# Road looks: worn trails and paved stone are drawn from one soft road map instead
# of a square per tile. Trails are narrow strips along the tile centres, a little
# wider than an NPC's feet; paved roads are wider. Strips join at junctions, trail
# edges blend into the grass, and the cobbles run on across tiles. Rain darkens the
# roads and gives them a sheen. The wear and paving data are unchanged; only the
# drawing is.

# Widths in world units. PATH_WIDTH is meant to sit a little wider than an NPC's
# feet; change it here if the paths look too thin or too wide.
const PATH_WIDTH: float = 0.5
const ROAD_WIDTH: float = 1.3

const ROAD_SHADER: String = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D road_map : filter_linear, repeat_disable;
uniform sampler2D cobble_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 map_origin = vec2(0.0, 0.0);
uniform vec2 map_size = vec2(1.0, 1.0);
uniform vec3 dirt_colour : source_color = vec3(0.45, 0.39, 0.30);
uniform vec3 stone_tint : source_color = vec3(0.78, 0.79, 0.78);
uniform float cobble_scale = 0.5;
uniform float wet = 1.0;
uniform float rain_gloss = 0.0;

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz - map_origin) / map_size;
	vec4 road = texture(road_map, uv);
	float grain = value_noise(world_pos.xz * 2.7) * 0.6 + value_noise(world_pos.xz * 7.3) * 0.4;
	// Two octaves of low-frequency wobble wear the trail and stone edges into
	// irregular banks instead of ruler-straight cuts.
	float edge = (value_noise(world_pos.xz * 1.9) - 0.5) * 0.5 + (value_noise(world_pos.xz * 6.1) - 0.5) * 0.25;
	float trail = smoothstep(0.06, 0.32, road.r + edge * 0.32);
	float stone = smoothstep(0.38, 0.62, road.g + edge * 0.32);
	vec3 dirt = dirt_colour * (0.82 + 0.36 * grain) * wet * (1.0 - 0.12 * road.r);
	vec3 cobble = texture(cobble_tex, world_pos.xz * cobble_scale).rgb * stone_tint * wet;
	float alpha = max(trail * (0.5 + 0.5 * road.r), stone);
	float gloss = rain_gloss * max(trail, stone);
	ALBEDO = mix(dirt, cobble, stone);
	ALPHA = clamp(alpha, 0.0, 1.0);
	ROUGHNESS = mix(0.95, 0.3, gloss);
	SPECULAR = mix(0.3, 0.6, gloss);
}
"""

var _road_overlay: MeshInstance3D = null
var _road_material: ShaderMaterial = null
var _road_texture: ImageTexture = null


func _process(delta: float) -> void:
	super(delta)
	if is_instance_valid(_road_material):
		_road_material.set_shader_parameter("wet", 1.0 - 0.38 * rain_level)
		_road_material.set_shader_parameter("rain_gloss", clampf(rain_level, 0.0, 1.0))


# Replaces the game's per-tile road meshes. It runs at the same moments the game
# rebuilt them: when the living system changes a trail or paving stage.
func _update_roads() -> void:
	if road_revision == sim.living.revision:
		return
	# The base keeps the cached dirt and stone meshes current (the contract the
	# scene and tests read). The road map draws the roads, so those meshes stay hidden.
	super()
	road_dirt.visible = false
	road_stone.visible = false
	_rebuild_road_map()


func _rebuild_road_map() -> void:
	var cells: Dictionary = sim.living.cells
	road_cells = cells.size()
	var faint: float = maxf(sim.living.faint_threshold(), 0.0001)
	# Each worn tile: its trail strength and whether it is paved.
	var tiles: Dictionary = {}
	var min_x: int = 1 << 30
	var min_y: int = 1 << 30
	var max_x: int = -(1 << 30)
	var max_y: int = -(1 << 30)
	for id: Variant in cells.keys():
		var parts: PackedStringArray = str(id).split(",")
		if parts.size() != 2:
			continue
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var cell: Dictionary = cells[id]
		var wear: float = clampf(float(cell.get("wear", 0.0)), 0.0, 1.0)
		var strength: float = clampf(wear / faint, 0.0, 1.0)
		var alpha: float = (0.16 + 0.6 * clampf(wear * 1.15, 0.0, 1.0)) * (0.45 + 0.55 * strength)
		tiles[tile] = {"alpha": alpha, "stone": bool(cell.get("stone", false))}
		min_x = mini(min_x, tile.x)
		min_y = mini(min_y, tile.y)
		max_x = maxi(max_x, tile.x)
		max_y = maxi(max_y, tile.y)
	if tiles.is_empty():
		if is_instance_valid(_road_overlay):
			_road_overlay.visible = false
		return
	# A one-tile margin lets the edges of the road network fade out softly.
	var x0: int = min_x - 1
	var y0: int = min_y - 1
	var x1: int = max_x + 2
	var y1: int = max_y + 2
	var span_tiles: int = maxi(x1 - x0, y1 - y0)
	var ppt: int = clampi(2048 / span_tiles, 8, 24)
	# Map the texture onto the world from its tile corners.
	var origin_world: Vector3 = world_position(Vector2(x0, y0), 0.0)
	var far_world: Vector3 = world_position(Vector2(x1, y1), 0.0)
	var origin := Vector2(origin_world.x, origin_world.z)
	var span := Vector2(far_world.x, far_world.z) - origin
	var tile_world: float = maxf((absf(span.x) / float(x1 - x0) + absf(span.y) / float(y1 - y0)) * 0.5, 0.0001)
	var half_path: float = PATH_WIDTH * 0.5 / tile_world * float(ppt)
	var half_road: float = ROAD_WIDTH * 0.5 / tile_world * float(ppt)
	var image := Image.create((x1 - x0) * ppt, (y1 - y0) * ppt, false, Image.FORMAT_RGBA8)
	# Trails first, then paved roads, which overwrite the trails they run over.
	_paint_network(image, tiles, x0, y0, ppt, half_path, false)
	_paint_network(image, tiles, x0, y0, ppt, half_road, true)
	_road_texture = ImageTexture.create_from_image(image)
	_ensure_road_overlay()
	var plane: PlaneMesh = _road_overlay.mesh as PlaneMesh
	plane.size = Vector2(absf(span.x), absf(span.y))
	_road_overlay.position = Vector3(origin.x + span.x * 0.5, 0.03, origin.y + span.y * 0.5)
	_road_overlay.visible = true
	_road_material.set_shader_parameter("road_map", _road_texture)
	_road_material.set_shader_parameter("map_origin", origin)
	_road_material.set_shader_parameter("map_size", span)


# Paints one surface: trails (paved = false) or paved stone (paved = true). Squares
# at each tile centre make the corners and path ends; bars join neighbours that
# share the surface. Red holds trail strength, green flags paved stone.
func _paint_network(image: Image, tiles: Dictionary, x0: int, y0: int, ppt: int, half: float, paved: bool) -> void:
	var stone_colour := Color(1.0, 1.0, 0.0, 1.0)
	for tile: Vector2i in tiles.keys():
		var info: Dictionary = tiles[tile]
		if bool(info["stone"]) != paved:
			continue
		var cx: float = (float(tile.x - x0) + 0.5) * float(ppt)
		var cy: float = (float(tile.y - y0) + 0.5) * float(ppt)
		var colour: Color = stone_colour if paved else Color(float(info["alpha"]), 0.0, 0.0, 1.0)
		_fill_block(image, cx - half, cx + half, cy - half, cy + half, colour)
	for tile: Vector2i in tiles.keys():
		var info: Dictionary = tiles[tile]
		var cx: float = (float(tile.x - x0) + 0.5) * float(ppt)
		var cy: float = (float(tile.y - y0) + 0.5) * float(ppt)
		for other: Vector2i in [tile + Vector2i(1, 0), tile + Vector2i(0, 1)]:
			if not tiles.has(other):
				continue
			var other_info: Dictionary = tiles[other]
			var both_stone: bool = bool(info["stone"]) and bool(other_info["stone"])
			if paved and not both_stone:
				continue
			if not paved and both_stone:
				continue
			var colour: Color = stone_colour
			if not paved:
				var a: float = 0.0 if bool(info["stone"]) else float(info["alpha"])
				var b: float = 0.0 if bool(other_info["stone"]) else float(other_info["alpha"])
				colour = Color(maxf(a, b), 0.0, 0.0, 1.0)
			var ox: float = (float(other.x - x0) + 0.5) * float(ppt)
			var oy: float = (float(other.y - y0) + 0.5) * float(ppt)
			if other.x != tile.x:
				_fill_block(image, minf(cx, ox), maxf(cx, ox), cy - half, cy + half, colour)
			else:
				_fill_block(image, cx - half, cx + half, minf(cy, oy), maxf(cy, oy), colour)
	_taper_network(image, tiles, x0, y0, ppt, half, paved)


# Trails and stone fade out where nobody walks beyond them instead of ending
# in blunt square cuts: every side of a tile with no matching neighbour tapers
# inward, so dead ends narrow to a point and corners round off.
func _taper_network(image: Image, tiles: Dictionary, x0: int, y0: int, ppt: int, half: float, paved: bool) -> void:
	for tile: Vector2i in tiles.keys():
		var info: Dictionary = tiles[tile]
		if bool(info["stone"]) != paved:
			continue
		var open: Array[Vector2] = []
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var other: Vector2i = tile + direction
			if not tiles.has(other) or bool(tiles[other]["stone"]) != bool(info["stone"]):
				open.append(Vector2(direction))
		if open.is_empty():
			continue
		# A tip fades deeper than the sides of a straight run.
		var depth: float = half * (0.3 if open.size() <= 2 else 0.7 if open.size() == 3 else 0.85)
		var cx: float = (float(tile.x - x0) + 0.5) * float(ppt)
		var cy: float = (float(tile.y - y0) + 0.5) * float(ppt)
		for side: Vector2 in open:
			_taper_side(image, cx, cy, half, depth, side, paved)


# Fades one side of the painted tile square inward over `depth` pixels.
func _taper_side(image: Image, cx: float, cy: float, half: float, depth: float, side: Vector2, paved: bool) -> void:
	var band: int = maxi(1, int(round(depth)))
	for step in range(band):
		var ramp: float = float(step) / float(maxi(band - 1, 1))
		if absf(side.x) > 0.5:
			var px: int = clampi(int(round(cx + side.x * (half - float(step)))), 0, image.get_width() - 1)
			for iy in range(maxi(int(floorf(cy - half)), 0), mini(int(ceili(cy + half)), image.get_height())):
				_fade_pixel(image, px, iy, ramp, paved)
		else:
			var py: int = clampi(int(round(cy + side.y * (half - float(step)))), 0, image.get_height() - 1)
			for ix in range(maxi(int(floorf(cx - half)), 0), mini(int(ceili(cx + half)), image.get_width())):
				_fade_pixel(image, ix, py, ramp, paved)


# Scales a painted pixel's strength by `ramp`; stone fades its cobble flag and
# the trail beneath so its ends run out into grass, not into a dirt band.
func _fade_pixel(image: Image, px: int, py: int, ramp: float, paved: bool) -> void:
	if ramp >= 1.0:
		return
	var colour: Color = image.get_pixel(px, py)
	if paved:
		colour.g *= ramp
	colour.r *= ramp
	image.set_pixel(px, py, colour)


# Paints a pixel block, clipped to the image.
func _fill_block(image: Image, x_min: float, x_max: float, y_min: float, y_max: float, colour: Color) -> void:
	var px: int = clampi(floori(x_min), 0, image.get_width() - 1)
	var py: int = clampi(floori(y_min), 0, image.get_height() - 1)
	var right: int = clampi(ceili(x_max), px + 1, image.get_width())
	var bottom: int = clampi(ceili(y_max), py + 1, image.get_height())
	image.fill_rect(Rect2i(px, py, right - px, bottom - py), colour)


func _ensure_road_overlay() -> void:
	if is_instance_valid(_road_overlay):
		return
	var shader := Shader.new()
	shader.code = ROAD_SHADER
	_road_material = ShaderMaterial.new()
	_road_material.shader = shader
	_road_material.set_shader_parameter("cobble_tex", UI.cobble_texture())
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_road_overlay = MeshInstance3D.new()
	_road_overlay.name = "RoadMap"
	_road_overlay.mesh = plane
	_road_overlay.material_override = _road_material
	_road_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_road_overlay)
