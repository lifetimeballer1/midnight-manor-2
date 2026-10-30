extends RefCounted

# Building dressing (visual pass 5): small hand-built touches on a few tier 1 models that read
# badly at a glance. Looks only; nothing here reads or changes the simulation beyond the
# building's type, tier and size.
#
# - Farm, tier 1: the stone tray of bare stakes becomes tilled rows of young wheat behind a low
#   rail fence, with a scarecrow. The wheat greens, then turns gold, then is cut back, on one
#   shared slow cycle.
# - Wall and mine, tier 1: the dark soot tint is lightened so their shapes hold at night; the mine
#   also gets a timber frame, a lantern and an ore cart.
#
# Everything is added under the building's model node (with the model's scale undone), so it
# follows the model when the village hides, shakes or ruins it.

const WHEAT_GREEN := Color("7fae4a")
const WHEAT_GOLD := Color("d9b44a")
const WHEAT_CUT := Color("a88f4c")
const SOIL := Color("6a4a32")
const FURROW := Color("553a26")
const RAIL := Color("8a6a46")
const POST := Color("6e5236")
const STRAW := Color("d9b860")
const SHIRT := Color("8e3a22")
const HAT := Color("3a2a20")
const WEATHERED := Color("b8a890")   # a lighter weathering than the village-wide soot tint
const TIMBER := Color("7a5a3a")
const LANTERN := Color(1.0, 0.72, 0.38)
const ORE := Color("6f6c66")
const GROW_SECONDS: float = 50.0
const RIPE_SECONDS: float = 40.0
const CUT_SECONDS: float = 12.0
const WHEAT_ROWS: int = 6
const WHEAT_PER_ROW: int = 9

static var _wheat_material: StandardMaterial3D = null
static var _wheat_tween: Tween = null


# Called once per new building view, after the details layer has dressed it.
static func dress(game: Node3D, b: Dictionary, view: Dictionary) -> void:
	var model: Node3D = view.get("model")
	if not is_instance_valid(model):
		return
	var key: String = game._building_asset(b)
	match key:
		"farm_t1":
			_dress_farm(game, b, model)
		"wall_t1":
			_lift_soot(model)
		"mine_t1":
			_lift_soot(model)
			_dress_mine(model)


# A holder under the model that cancels the model's scale, so sizes below are in world units.
static func _holder(model: Node3D, name: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = name
	var s: float = maxf(model.scale.x, 0.001)
	holder.scale = Vector3.ONE / s
	model.add_child(holder)
	return holder


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, material: StandardMaterial3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


static func _lift_soot(model: Node3D) -> void:
	for part: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := part as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var tinted := mesh_node.get_surface_override_material(surface) as BaseMaterial3D
			if tinted != null:
				tinted.albedo_color = WEATHERED


# --- Farm -----------------------------------------------------------------------

static func _dress_farm(game: Node3D, b: Dictionary, model: Node3D) -> void:
	for part: Node in model.find_children("*", "MeshInstance3D", true, false):
		var lower: String = str(part.name).to_lower()
		if "architecture" in lower or "dressing" in lower:
			(part as MeshInstance3D).hide()
	var holder := _holder(model, "YoungWheat")
	var half: float = float(b["size"]) * game.TILE * 0.5 - 0.12
	# Tilled bed with raised furrows.
	_box(holder, Vector3(half * 2.0 - 0.1, 0.06, half * 2.0 - 0.1), Vector3(0, 0.03, 0), SOIL)
	var row_gap: float = (half * 2.0 - 0.5) / float(WHEAT_ROWS)
	for r in WHEAT_ROWS:
		var z: float = -half + 0.25 + row_gap * (float(r) + 0.5)
		_box(holder, Vector3(half * 2.0 - 0.45, 0.05, row_gap * 0.45), Vector3(0, 0.075, z), FURROW)
	# Young wheat: one multimesh of slim tufts along the furrows.
	var tuft := BoxMesh.new()
	tuft.size = Vector3(0.07, 1.0, 0.07)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = tuft
	multi.instance_count = WHEAT_ROWS * WHEAT_PER_ROW
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(b["id"])) ^ 0x51ab
	var step: float = (half * 2.0 - 0.6) / float(WHEAT_PER_ROW - 1)
	var i: int = 0
	for r in WHEAT_ROWS:
		var z: float = -half + 0.25 + row_gap * (float(r) + 0.5)
		for k in WHEAT_PER_ROW:
			var x: float = -half + 0.3 + step * float(k) + rng.randf_range(-0.05, 0.05)
			var h: float = rng.randf_range(0.26, 0.38)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)).scaled(Vector3(1.0, h, 1.0))
			multi.set_instance_transform(i, Transform3D(basis, Vector3(x, 0.08 + h * 0.5, z + rng.randf_range(-0.04, 0.04))))
			i += 1
	var wheat := MultiMeshInstance3D.new()
	wheat.name = "Wheat"
	wheat.multimesh = multi
	wheat.material_override = _wheat(game)
	wheat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(wheat)
	# Low rail fence: corner and middle posts, two rails a side, a gap at the front for the gate.
	for side in 4:
		var along := Vector3(1, 0, 0) if side < 2 else Vector3(0, 0, 1)
		var across := Vector3(0, 0, 1) if side < 2 else Vector3(1, 0, 0)
		var sign: float = -1.0 if side % 2 == 0 else 1.0
		var edge: Vector3 = across * sign * half
		for t in [-1.0, 0.0, 1.0]:
			_box(holder, Vector3(0.09, 0.42, 0.09), edge + along * t * half + Vector3(0, 0.21, 0), POST)
		for y in [0.18, 0.34]:
			if side == 1:
				# Front side: rails on either side of a gap.
				for t in [-0.5, 0.5]:
					var rail := Vector3(half * 0.8, 0.05, 0.05) if side < 2 else Vector3(0.05, 0.05, half * 0.8)
					_box(holder, rail, edge + along * t * half * 1.2 + Vector3(0, y, 0), RAIL)
			else:
				var rail := Vector3(half * 2.0, 0.05, 0.05) if side < 2 else Vector3(0.05, 0.05, half * 2.0)
				_box(holder, rail, edge + Vector3(0, y, 0), RAIL)
	# Scarecrow in a back corner.
	var crow := Node3D.new()
	crow.name = "Scarecrow"
	crow.position = Vector3(half * 0.45, 0.0, -half * 0.45)
	crow.rotation.y = 0.5
	holder.add_child(crow)
	_box(crow, Vector3(0.07, 1.0, 0.07), Vector3(0, 0.5, 0), POST)
	_box(crow, Vector3(0.62, 0.06, 0.06), Vector3(0, 0.78, 0), POST)
	_box(crow, Vector3(0.3, 0.3, 0.16), Vector3(0, 0.72, 0), SHIRT)
	_box(crow, Vector3(0.2, 0.2, 0.2), Vector3(0, 1.0, 0), STRAW)
	_box(crow, Vector3(0.32, 0.04, 0.32), Vector3(0, 1.11, 0), HAT)
	_box(crow, Vector3(0.16, 0.1, 0.16), Vector3(0, 1.17, 0), HAT)


# One material for every tier 1 farm, on one slow looping colour cycle: green, gold, cut back.
static func _wheat(game: Node3D) -> StandardMaterial3D:
	if _wheat_material == null:
		_wheat_material = StandardMaterial3D.new()
		_wheat_material.albedo_color = WHEAT_GREEN
		_wheat_material.roughness = 0.85
	if _wheat_tween == null or not _wheat_tween.is_valid():
		_wheat_tween = game.create_tween()
		_wheat_tween.set_loops()
		_wheat_tween.tween_property(_wheat_material, "albedo_color", WHEAT_GOLD, GROW_SECONDS).from(WHEAT_GREEN).set_trans(Tween.TRANS_SINE)
		_wheat_tween.tween_interval(RIPE_SECONDS)
		_wheat_tween.tween_property(_wheat_material, "albedo_color", WHEAT_CUT, 1.5)
		_wheat_tween.tween_interval(CUT_SECONDS)
		_wheat_tween.tween_property(_wheat_material, "albedo_color", WHEAT_GREEN, 3.0)
	return _wheat_material


# --- Wall and mine ----------------------------------------------------------------

static func _dress_mine(model: Node3D) -> void:
	var holder := _holder(model, "MineDressing")
	var front: float = 0.78
	# Timber frame at the adit: two posts and a lintel.
	for x in [-0.36, 0.36]:
		_box(holder, Vector3(0.1, 0.9, 0.1), Vector3(x, 0.45, front), TIMBER)
	_box(holder, Vector3(0.9, 0.1, 0.12), Vector3(0, 0.92, front), TIMBER)
	# A small lantern hanging from the lintel: unshaded, so it reads at night without a light.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = LANTERN
	_box(holder, Vector3(0.1, 0.13, 0.1), Vector3(0.24, 0.78, front + 0.06), LANTERN, glow)
	# Ore cart beside the entrance.
	var cart := Node3D.new()
	cart.name = "OreCart"
	cart.position = Vector3(-0.62, 0.0, front + 0.18)
	cart.rotation.y = 0.35
	holder.add_child(cart)
	_box(cart, Vector3(0.4, 0.2, 0.28), Vector3(0, 0.2, 0), TIMBER)
	_box(cart, Vector3(0.34, 0.08, 0.22), Vector3(0, 0.32, 0), ORE)
	for x in [-0.13, 0.13]:
		for z in [-0.15, 0.15]:
			_box(cart, Vector3(0.09, 0.09, 0.03), Vector3(x, 0.07, z), POST)


# --- Trees and rocks outside the walls ----------------------------------------------------

const BARK := Color(0.42, 0.31, 0.24)

# Adds one primitive to a vertex-coloured mesh, shaded darker toward its base (as the realm's trees are).
static func _part(tool: SurfaceTool, mesh: PrimitiveMesh, place: Transform3D, colour: Color, low: float, high: float) -> void:
	var arrays: Array = mesh.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for corner in indices.size():
		var index: int = indices[corner]
		var at: Vector3 = place * points[index]
		var facet: int = corner / 3
		var vary: float = 0.94 + 0.12 * fposmod(sin(float(facet) * 12.9898 + at.y * 4.1) * 43758.5453, 1.0)
		var shade: float = lerpf(0.62, 1.0, smoothstep(low, high, at.y)) * vary
		tool.set_color(Color(minf(colour.r * shade, 1.0), minf(colour.g * shade, 1.0), minf(colour.b * shade, 1.0)))
		tool.set_normal((place.basis * normals[index]).normalized())
		tool.add_vertex(at)


# A broadleaf (oak-like) tree standing on y 0: a short trunk under four lumpy crown lobes. The
# instance colour carries the autumn tone; the trunk keeps a bark shade.
static func broadleaf_mesh(with_trunk: bool = true, lift: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if with_trunk:
		var trunk := BoxMesh.new()
		trunk.size = Vector3(0.2, 0.9, 0.2)
		_part(st, trunk, Transform3D(Basis(), Vector3(0, 0.45 + lift, 0)), BARK, 0.0, 1.0)
	for lobe: Vector4 in [Vector4(0, 1.3, 0, 0.62), Vector4(0.36, 1.08, 0.14, 0.42), Vector4(-0.3, 1.1, 0.26, 0.4), Vector4(-0.1, 1.62, -0.18, 0.38)]:
		var crown := SphereMesh.new()
		crown.radius = lobe.w
		crown.height = lobe.w * 1.8
		crown.radial_segments = 7
		crown.rings = 3
		_part(st, crown, Transform3D(Basis(), Vector3(lobe.x, lobe.y + lift, lobe.z)), Color.WHITE, 0.6 + lift, 2.0 + lift)
	return st.commit()


# A small cluster of boulders standing on y 0, in place of a single flat stone.
static func rock_cluster_mesh(scale: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := SphereMesh.new()
	stone.radius = 0.3 * scale
	stone.height = 0.42 * scale
	stone.radial_segments = 6
	stone.rings = 3
	for piece: Array in [[Vector3(0, 0.1, 0), Vector3(1.0, 0.9, 0.85), 0.0], [Vector3(0.32, 0.04, 0.16), Vector3(0.55, 0.5, 0.5), 0.8], [Vector3(-0.22, 0.03, 0.26), Vector3(0.42, 0.38, 0.4), 1.9]]:
		var at: Vector3 = piece[0] * scale
		_part(st, stone, Transform3D(Basis(Vector3.UP, piece[2]).scaled(piece[1]), at), Color.WHITE, -0.1, 0.5 * scale)
	return st.commit()


# The scenery ring round the map: its round crowns become lobed broadleaf crowns and its flat
# stones become boulder clusters. The meshes are swapped in place, so the instances (and their
# autumn colours) are kept. Crown instances already sit on top of their trunks, so the crown
# mesh here has no trunk and is centred on the old sphere's middle.
static func reshape_scenery(scenery: Node) -> void:
	if scenery == null:
		return
	for child: Node in scenery.get_children():
		var multi := child as MultiMeshInstance3D
		if multi == null or multi.multimesh == null:
			continue
		var sphere := multi.multimesh.mesh as SphereMesh
		if sphere == null:
			continue
		if sphere.radius > 0.8 and sphere.radius < 0.9:
			multi.multimesh.mesh = broadleaf_mesh(false, -1.3)
		elif sphere.radius < 0.3:
			multi.multimesh.mesh = rock_cluster_mesh(0.9)
