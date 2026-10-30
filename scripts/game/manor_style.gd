extends Node

# Manor style (The Manor Endures, C2): a renewed manor flies its line's banner beside the Manor
# Hall. Each renewal gives the banner a new colour (silver, violet, teal, crimson, gold, then round
# again) and adds a Moon Seal star to it, up to five. A first village has no banner.
# A child node of the game. It reads game.legacy and the Hall's view, and adds only view nodes.

const COLOURS: Array[Color] = [Color("8fa6d8"), Color("7a5aa8"), Color("2f7d7a"), Color("a8323e"), Color("c99a2e")]
const POLE_HEIGHT: float = 5.2
const CLOTH := Vector2(1.5, 2.1)

var game: Node
var banner: Node3D = null
var cloth: MeshInstance3D = null
var _root: Node3D = null
var _style: int = -1
var _clock: float = 0.0


func setup(owner_game: Node) -> void:
	game = owner_game


static func colour_for(renewals: int) -> Color:
	return COLOURS[(maxi(renewals, 1) - 1) % COLOURS.size()]


func _process(delta: float) -> void:
	if game == null or game.legacy == null:
		return
	var renewals: int = int(game.legacy.renewals)
	var hall: Dictionary = game.sim._hall()
	var view: Dictionary = {} if hall.is_empty() else game.building_views.get(int(hall["id"]), {})
	var root: Node3D = view.get("root") as Node3D if not view.is_empty() else null
	var standing: bool = not hall.is_empty() and float(hall["hp"]) > 0.0 and float(hall.get("remaining", 0.0)) <= 0.0
	if renewals <= 0 or not is_instance_valid(root) or not standing:
		_drop()
		return
	if root != _root or renewals != _style:
		_drop()
		_build(root, renewals, int(hall["size"]))
	_clock += delta
	if is_instance_valid(cloth):
		cloth.rotation.y = 0.18 * sin(_clock * 1.7) + 0.06 * sin(_clock * 4.3)


func _drop() -> void:
	if is_instance_valid(banner):
		banner.queue_free()
	banner = null
	cloth = null
	_root = null
	_style = -1


func _build(root: Node3D, renewals: int, size: int) -> void:
	_root = root
	_style = renewals
	banner = Node3D.new()
	banner.name = "ManorBanner"
	var reach: float = float(size) * float(game.TILE) * 0.46
	banner.position = Vector3(reach, 0.0, reach)
	root.add_child(banner)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("4a3426")
	wood.roughness = 0.9
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.09
	pole.height = POLE_HEIGHT
	pole.radial_segments = 8
	var pole_node := MeshInstance3D.new()
	pole_node.mesh = pole
	pole_node.material_override = wood
	pole_node.position.y = POLE_HEIGHT * 0.5
	banner.add_child(pole_node)
	var finial := SphereMesh.new()
	finial.radius = 0.16
	finial.height = 0.32
	var finial_mat := StandardMaterial3D.new()
	finial_mat.albedo_color = Color("d9c27a")
	finial_mat.metallic = 0.7
	finial_mat.roughness = 0.35
	var finial_node := MeshInstance3D.new()
	finial_node.mesh = finial
	finial_node.material_override = finial_mat
	finial_node.position.y = POLE_HEIGHT + 0.12
	banner.add_child(finial_node)
	# The cloth hangs from a pivot at the pole so it can sway.
	var quad := QuadMesh.new()
	quad.size = CLOTH
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_texture = ImageTexture.create_from_image(emblem(renewals))
	cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth_mat.roughness = 0.85
	cloth_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	cloth = MeshInstance3D.new()
	cloth.name = "Cloth"
	cloth.position = Vector3(0.0, POLE_HEIGHT - 0.25, 0.0)
	banner.add_child(cloth)
	var hang := MeshInstance3D.new()
	hang.mesh = quad
	hang.material_override = cloth_mat
	hang.position = Vector3(CLOTH.x * 0.5 + 0.08, -CLOTH.y * 0.5, 0.0)
	cloth.add_child(hang)


# The banner cloth: the line's colour, a silver crescent, one Moon Seal star per renewal (up to five),
# and a swallowtail cut at the bottom. 96x128.
static func emblem(renewals: int) -> Image:
	var w: int = 96
	var h: int = 128
	var base: Color = colour_for(renewals)
	var trim := Color("e8dcb0")
	var silver := Color("eef2fa")
	var image := Image.create(w, h, true, Image.FORMAT_RGBA8)
	var stars: int = clampi(renewals, 1, 5)
	for y in h:
		for x in w:
			var colour: Color = base.darkened(0.12 * float(y) / float(h))
			# Swallowtail: a notch cut up into the bottom edge.
			var notch: float = 22.0 - absf(float(x) - 48.0) * 0.6
			if y > h - 1 - notch:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if x < 5 or x > w - 6 or y < 5:
				colour = trim
			var p := Vector2(x + 0.5, y + 0.5)
			# Crescent: a disc with a smaller disc bitten out of it.
			if p.distance_to(Vector2(48.0, 50.0)) < 24.0 and p.distance_to(Vector2(58.0, 44.0)) > 20.0:
				colour = silver
			for i in stars:
				var sx: float = 48.0 + (float(i) - float(stars - 1) * 0.5) * 15.0
				if _star(p - Vector2(sx, 92.0), 6.5):
					colour = trim
			image.set_pixel(x, y, colour)
	image.generate_mipmaps()
	return image


static func _star(d: Vector2, r: float) -> bool:
	var angle: float = atan2(d.y, d.x) + PI / 2.0
	var spike: float = 0.5 + 0.5 * cos(5.0 * angle)
	return d.length() < r * (0.45 + 0.55 * pow(spike, 2.0))
