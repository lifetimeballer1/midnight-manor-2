extends "res://scripts/game/village_vfx.gd"

# Asset theme (visual only), over the effects layer: every building tier and every character
# turns to early autumn.
#
# The 310 delivered models (273 building tiers, 37 characters) are painted from ONE shared
# 64x64 colour palette embedded in each GLB, and that palette now ships ALREADY graded: the GLBs
# were re-exported from an autumn-palette Blender source (russet/copper roofs, warm stone, leaf
# and pumpkin colours). So the runtime palette regrade is LEGACY ONLY and OFF by default.
# Launch with --legacy-autumn-art to turn it on in memory (the first time a model loads, every
# model material points at a regraded copy of the shared palette, using ART_GRADE), e.g. to
# compare with the old GLBs. Unknown colours are warmed generically on that legacy path too.
#
# Soot lightening is separate and always on: village_details.gd multiplies every building by a
# dark grey-brown "soot", and the lighter autumn weathering (ART_SOOT) is still a runtime
# multiply applied after each building rebuild. Pass --no-autumn-art to skip it.
#
# Mesh, UVs, rigs, clips and the source .blend are untouched.

const ART_GRADE := {
	# teal and blue roofs, hoods and cloth -> russet / bronze / terracotta
	"143633": "4c2c22", "113645": "5c3126", "568086": "b27a5c",
	"0a2850": "5b3416", "103760": "a45f20",
	# green roofs, moss, ivy, base slabs -> olive-gold and umber
	"162c0e": "2d2511", "152e16": "30270f", "09140c": "17110a", "303c16": "6e591a",
	"384f1b": "a2801e", "25401c": "86701c", "1f2824": "2f2921",
	# grey stone -> warm stone
	"606754": "93846a", "42473c": "675a47", "c8c6aa": "dfcca2",
	# walls, plaster, thatch
	"dac08a": "e3c186", "caad76": "d3ab6c", "e2c893": "f0d59d", "987c48": "a37e3d",
	# oranges, browns and reds: a touch richer
	"ba6333": "c9672d", "d8824a": "e18b3f", "6b2d17": "7b3418", "8d4d17": "9d5617",
	"7c5219": "8b5b1a", "632f11": "6f3612", "5d120d": "6b1911", "7c1e14": "8d2917",
	# near-blacks lean warm
	"0f161a": "1b1713", "2c1e37": "35233b", "090b09": "0b0a08",
}
const ART_MARK: String = "autumn_art"
# village_details.gd multiplies every building by this dark grey-brown "soot" (it also reads as grey
# in daylight). Autumn buildings get a lighter, warmer weathering so the graded roofs show through.
const ART_SOOT_OLD := Color("5c5249")
const ART_SOOT := Color("957f68")

var _art_palette: ImageTexture = null
var _art_on: bool = false         # legacy runtime palette regrade: only with --legacy-autumn-art
var _art_soot_on: bool = true     # soot lightening: off only with --no-autumn-art
var _art_graded: int = 0          # materials switched to the graded palette (the tests read this)


func _ready() -> void:
	_art_on = "--legacy-autumn-art" in OS.get_cmdline_user_args()
	_art_soot_on = "--no-autumn-art" not in OS.get_cmdline_user_args()
	super()


# Every model in the game (village, build-card thumbnails, battles) comes through here.
func _model(asset_name: String) -> Node3D:
	var node: Node3D = super(asset_name)
	if _art_on:
		_art_grade_node(node)
	return node


# The base rebuilds every building model (and the details layer re-sooties them) whenever the
# village changes, so the lighter weathering is applied after each rebuild.
func _rebuild_buildings() -> void:
	super()
	if _art_soot_on:
		_art_lighten_soot(building_layer)


func _art_lighten_soot(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		if part.mesh != null:
			for surface in part.mesh.get_surface_count():
				var override := part.get_surface_override_material(surface) as BaseMaterial3D
				if override != null and override.albedo_color.is_equal_approx(ART_SOOT_OLD):
					override.albedo_color = ART_SOOT
	for child in node.get_children():
		_art_lighten_soot(child)


# Legacy path only (--legacy-autumn-art): the shipped palette is already autumn.
func _art_grade_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface) as StandardMaterial3D
				if material == null or material.has_meta(ART_MARK):
					continue
				var texture: Texture2D = material.albedo_texture
				if texture == null or texture.get_width() != 64 or texture.get_height() != 64:
					continue
				if _art_palette == null:
					_art_palette = _art_grade_palette(texture.get_image())
				material.albedo_texture = _art_palette
				material.set_meta(ART_MARK, true)
				_art_graded += 1
	for child in node.get_children():
		_art_grade_node(child)


# The regraded copy of the shared palette, made once.
func _art_grade_palette(source: Image) -> ImageTexture:
	var image: Image = source.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var colour: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, _art_grade_colour(colour))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _art_grade_colour(colour: Color) -> Color:
	var key: String = colour.to_html(false)
	if ART_GRADE.has(key):
		var graded := Color(str(ART_GRADE[key]))
		graded.a = colour.a
		return graded
	# Unknown colour: leave neutrals and pure white alone, warm everything else.
	if colour.s < 0.12 or colour.v > 0.97:
		return colour
	var warm: Color = Color(colour.r * 1.08 + 0.03, colour.g * 0.98 + 0.01, colour.b * 0.82).clamp()
	var graded: Color = colour.lerp(warm, 0.55)
	graded.a = colour.a
	return graded
