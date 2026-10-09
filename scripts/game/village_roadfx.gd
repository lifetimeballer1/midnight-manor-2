extends "res://scripts/game/village_sky.gd"

# Road look (visual only), over the sky layer.
#
# village_roads.gd paints every road from one soft map (red = trail strength, green = paved
# stone) through an inline shader. This layer swaps that shader for shaders/road_autumn.gdshader,
# which keeps the same inputs and adds worn centres, packed shoulders that read as wheel ruts,
# pebbles, a dry-grass verge, fallen leaves, warm moss-joined cobbles and rain puddles that ring
# with drops. The road map, the wear data and the base layer's rebuild logic are all untouched.
# Launch with --no-road-fx to compare with the old roads.

const ROAD_AUTUMN_SHADER: String = "res://shaders/road_autumn.gdshader"
const ROAD_AUTUMN_DIRT := Color("7a5c34")        # warmer and a touch lighter than the base dirt
const ROAD_AUTUMN_STONE := Color("e3d6bc")       # bleached warm stone, replaces the grey-blue tint


func _ensure_road_overlay() -> void:
	var fresh: bool = not is_instance_valid(_road_overlay)
	super()
	if not fresh or "--no-road-fx" in OS.get_cmdline_user_args() or _road_material == null:
		return
	_road_material.shader = load(ROAD_AUTUMN_SHADER)
	_road_material.set_shader_parameter("cobble_tex", UI.cobble_texture())
	_road_material.set_shader_parameter("dirt_colour", ROAD_AUTUMN_DIRT)
	_road_material.set_shader_parameter("stone_tint", ROAD_AUTUMN_STONE)
	_road_material.set_shader_parameter("detail", 0.0 if _sky_is_phone() else 1.0)
