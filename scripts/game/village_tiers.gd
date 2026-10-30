extends RefCounted

# Visual progression: a building should look clearly better each time it levels up. Looks only;
# nothing here reads or changes the simulation beyond a building's type, tier and size.
#
# Two things change with level:
# - Which exported model is shown. Every building has six exported art tiers, but most types only
#   have two or three game tiers, so tiers 4 to 6 (the larger, richer models) were never seen.
#   art_tier() spreads a type's game tiers across the six art tiers: a three-tier cottage shows
#   art 1, 4 and 6.
# - The yard around it, on a six-step ladder (stage()):
#     1 a smaller building on packed earth with rough stakes and a log pile
#     2 a gravel path to the door and a wattle fence
#     3 cobbles inside a stone kerb, flower boxes by the door
#     4 dressed stone kerb, lantern posts at the door
#     5 manor banners at the back corners
#     6 a pale paved court with gold-capped pillars, and a gold finial with a pennant on the roof
#   The building also grows into its plot as it levels (SCALE). The Hall climbs the same ladder
#   with taller banners from stage 2, so the seat of the manor always reads as the grandest.
#
# Defenses keep their own view layer (village_defenses) and are left alone. Open-ground types
# (fields, groves, quarries) keep their own ground and size and get only the props.

const TILE: float = 2.0
const SKIP_TYPES: Array[String] = ["wall", "stonewall", "gate", "rampart", "trap", "fire-trap", "tower",
	"archer_tower", "ballista", "bastion", "watchfire", "stone-road", "city-wall", "dawn-gate", "grand-watchtower"]
const OPEN_TYPES: Array[String] = ["farm", "pasture", "pond", "grove", "whisper-grove", "frostgrove", "manor-gardens",
	"lumber", "timber_yard", "mason_yard", "mine", "stone_quarry", "deephole", "blackwater-weir", "emberglass",
	"cairnfield", "sunken-chapel", "moon-dial", "oathstone", "monument", "market", "market-square", "lantern-rows",
	"shieldwall-yard", "scout_post", "bellcote"]
const SCALE: Array[float] = [0.8, 0.86, 0.91, 0.95, 0.98, 1.0]
# These keep their tier 1 model at every tier: the dressing layer rebuilds it (young wheat, leafy or
# frosted trees), and their higher art tiers are the old bare stakes and dark ball trees.
const FIXED_ART: Array[String] = ["farm", "grove", "frostgrove"]
const ONE_TIER_STAGE: int = 3   # a one-tier building is a finished building: cobbles and kerb

const DIRT := Color("6b5238")
const DIRT_DARK := Color("54402c")
const GRAVEL := Color("8a8274")
const WOOD := Color("7a5a3a")
const WOOD_DARK := Color("54402a")
const LOG := Color("8a6440")
const COBBLE := Color("6f6b64")
const KERB := Color("8c8780")
const DRESSED := Color("b9b0a0")
const PAVE := Color("cbbfa6")
const GOLD := Color("e0b04a")
const BANNER := Color("8e2a2a")
const FLOWERS: Array[Color] = [Color("c94a5a"), Color("e0c050"), Color("d6d0e8")]
const LEAF := Color("4a7430")
const LAMP := Color(1.0, 0.62, 0.26)
const YARD_TINT := Color(0.5, 0.47, 0.43)

static var _yards: Dictionary = {}
static var _lamps: Dictionary = {}
static var _lamp_material: StandardMaterial3D = null
static var _yard_material: StandardMaterial3D = null


static func skipped(type_name: String) -> bool:
	return type_name in SKIP_TYPES


# Which of the six exported art tiers a game tier shows.
static func art_tier(type_name: String, tier: int, max_tier: int) -> int:
	if type_name in FIXED_ART:
		return 1
	if skipped(type_name) or max_tier <= 1:
		return clampi(tier, 1, 6)
	return clampi(1 + roundi(float(tier - 1) * 5.0 / float(max_tier - 1)), 1, 6)


# Where a game tier sits on the six-step yard ladder.
static func stage(tier: int, max_tier: int) -> int:
	if max_tier <= 1:
		return ONE_TIER_STAGE
	return clampi(1 + roundi(float(tier - 1) * 5.0 / float(max_tier - 1)), 1, 6)


# Called once per new building view, after the details and dressing layers.
static func dress(game: Node3D, b: Dictionary, view: Dictionary) -> void:
	var model: Node3D = view.get("model")
	var type_name: String = str(b["type"])
	if not is_instance_valid(model) or skipped(type_name):
		return
	var spec: Dictionary = game.sim.building_specs.get(type_name, {})
	var max_tier: int = maxi(1, (spec.get("tiers", []) as Array).size())
	apply(model, type_name, stage(int(b["tier"]), max_tier), int(b["size"]))


# Dresses one model in place. Also used by tests/capture_tiers.gd, outside the game.
static func apply(model: Node3D, type_name: String, step: int, size: int) -> void:
	if skipped(type_name) or model.has_meta("tier_dressed"):
		return
	model.set_meta("tier_dressed", step)
	var open: bool = type_name in OPEN_TYPES
	var hall: bool = type_name == "hall" or type_name == "manner-citadel"
	# The model's own stone tray: its top is where the yard surface sits.
	var tray_top: float = 0.0
	for part: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := part as MeshInstance3D
		if "ground" in str(mesh_node.name).to_lower() and mesh_node.mesh != null:
			var box: AABB = mesh_node.transform * mesh_node.mesh.get_aabb()
			tray_top = maxf(tray_top, box.end.y)
			if not open:
				mesh_node.hide()
	if not open:
		model.scale *= SCALE[step - 1]
	var s: float = maxf(model.scale.x, 0.001)
	tray_top = clampf(tray_top * s, 0.05, 0.35)
	var holder := Node3D.new()
	holder.name = "TierYard"
	holder.scale = Vector3.ONE / s
	model.add_child(holder)
	var yard := MeshInstance3D.new()
	yard.mesh = _yard(size, step, open, hall, snappedf(tray_top, 0.01))
	yard.material_override = _vertex_material()
	holder.add_child(yard)
	if step >= 4 or (hall and step >= 2):
		var lamps := MeshInstance3D.new()
		lamps.mesh = _lamp_heads(size, step, snappedf(tray_top, 0.01))
		lamps.material_override = _lamp_mat()
		lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(lamps)
	if step >= 6 and not open:
		_finial(model, holder, s, hall)


# --- Yard meshes (cached per size, step, kind) ----------------------------------------------------

static func _vertex_material() -> StandardMaterial3D:
	if _yard_material == null:
		_yard_material = StandardMaterial3D.new()
		_yard_material.vertex_color_use_as_albedo = true
		# Matches the village-wide soot tint on the models (village_details), a little lighter so the
		# yard still reads at night.
		_yard_material.albedo_color = YARD_TINT
		_yard_material.roughness = 0.92
	return _yard_material


static func _lamp_mat() -> StandardMaterial3D:
	if _lamp_material == null:
		_lamp_material = StandardMaterial3D.new()
		_lamp_material.albedo_color = LAMP
		_lamp_material.emission_enabled = true
		_lamp_material.emission = LAMP
		_lamp_material.emission_energy_multiplier = 1.1
	return _lamp_material


static func _block(st: SurfaceTool, size: Vector3, at: Vector3, colour: Color, turn: float = 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	var place := Transform3D(Basis(Vector3.UP, turn), at)
	_part(st, box, place, colour, at.y - size.y * 0.5, at.y + size.y * 0.5)


# Adds one primitive with a gentle top-lit shade (as the dressing layer does).
static func _part(st: SurfaceTool, mesh: PrimitiveMesh, place: Transform3D, colour: Color, low: float, high: float) -> void:
	var arrays: Array = mesh.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for corner in indices.size():
		var index: int = indices[corner]
		var at: Vector3 = place * points[index]
		var shade: float = lerpf(0.8, 1.0, smoothstep(low, high + 0.001, at.y))
		st.set_color(Color(colour.r * shade, colour.g * shade, colour.b * shade))
		st.set_normal((place.basis * normals[index]).normalized())
		st.add_vertex(at)


static func _yard(size: int, step: int, open: bool, hall: bool, top: float) -> ArrayMesh:
	var key: String = "%d|%d|%s|%s|%.2f" % [size, step, open, hall, top]
	if _yards.has(key):
		return _yards[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plot: float = float(size) * TILE
	var half: float = plot * 0.5 - 0.1
	if not open:
		_ground(st, step, half, top)
	_props(st, step, half, top, open, hall, size)
	var mesh: ArrayMesh = st.commit()
	_yards[key] = mesh
	return mesh


# The yard surface that replaces the model's identical stone tray.
static func _ground(st: SurfaceTool, step: int, half: float, top: float) -> void:
	match step:
		1:
			_block(st, Vector3(half * 1.9, top, half * 1.86), Vector3(0, top * 0.5, 0), DIRT, 0.04)
			_block(st, Vector3(half * 1.2, 0.02, half * 0.9), Vector3(-half * 0.2, top + 0.005, half * 0.3), DIRT_DARK, -0.1)
		2:
			_block(st, Vector3(half * 2.0, top, half * 2.0), Vector3(0, top * 0.5, 0), DIRT)
			_block(st, Vector3(0.55, 0.03, half * 0.9), Vector3(0, top + 0.01, half * 0.55), GRAVEL)
		_:
			var surface: Color = COBBLE if step < 6 else PAVE
			var rim: Color = KERB if step == 3 else (DRESSED if step < 6 else GOLD)
			_block(st, Vector3(half * 2.0, top, half * 2.0), Vector3(0, top * 0.5, 0), surface)
			# Cobble seams: a light checker of slightly raised stones.
			var cells: int = maxi(3, int(half * 2.4))
			var cell: float = half * 2.0 / float(cells)
			for i in cells:
				for j in cells:
					if (i + j) % 2 == 0:
						continue
					var at := Vector3(-half + cell * (float(i) + 0.5), top + 0.006, -half + cell * (float(j) + 0.5))
					_block(st, Vector3(cell * 0.9, 0.012, cell * 0.9), at, surface.lightened(0.08))
			var kerb_h: float = 0.08 if step < 6 else 0.1
			var kerb_w: float = 0.14
			for side: Vector3 in [Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				_block(st, Vector3(half * 2.0, top + kerb_h, kerb_w), Vector3(0, (top + kerb_h) * 0.5, side.z * (half - kerb_w * 0.5)), rim if step == 6 else (KERB if step == 3 else DRESSED))
			for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				_block(st, Vector3(kerb_w, top + kerb_h, half * 2.0), Vector3(side.x * (half - kerb_w * 0.5), (top + kerb_h) * 0.5, 0), rim if step == 6 else (KERB if step == 3 else DRESSED))
			if step == 6:
				# Pale stone kerb with a gold inlay along its top.
				for z: float in [half - 0.07, -half + 0.07]:
					_block(st, Vector3(half * 2.0, 0.02, 0.05), Vector3(0, top + kerb_h + 0.01, z), GOLD)
				for x: float in [half - 0.07, -half + 0.07]:
					_block(st, Vector3(0.05, 0.02, half * 2.0), Vector3(x, top + kerb_h + 0.01, 0), GOLD)


static func _props(st: SurfaceTool, step: int, half: float, top: float, open: bool, hall: bool, size: int) -> void:
	var edge: float = half - 0.12
	if not open and step == 1:
		# Rough stakes and a small log pile: a place only just settled.
		for at: Vector2 in [Vector2(-edge, -edge), Vector2(edge, -edge * 0.2), Vector2(-edge * 0.4, edge)]:
			_block(st, Vector3(0.07, 0.45, 0.07), Vector3(at.x, top + 0.2, at.y), WOOD_DARK, at.x)
		for k in 3:
			var log_pos := Vector3(edge - 0.25, top + 0.06 + (0.1 if k == 2 else 0.0), -edge + 0.2 + (0.1 * k if k < 2 else 0.05))
			_block(st, Vector3(0.45, 0.1, 0.1), log_pos, LOG, 0.15)
		if hall:
			# The first night's campfire before the gate.
			for a in 6:
				var ring := Vector3(cos(a * TAU / 6.0) * 0.22, top + 0.04, half * 0.8 + sin(a * TAU / 6.0) * 0.22)
				_block(st, Vector3(0.1, 0.08, 0.1), ring, KERB)
	if not open and step == 2:
		# Wattle fence round the back and sides, open at the door.
		var posts: int = maxi(3, int(half * 2.0 / 0.7))
		for side in 3:
			for p in posts + 1:
				var t: float = -edge + edge * 2.0 * float(p) / float(posts)
				var at: Vector3
				match side:
					0: at = Vector3(t, 0, -edge)
					1: at = Vector3(-edge, 0, t)
					_: at = Vector3(edge, 0, t)
				if side > 0 and t > edge * 0.4:
					continue
				_block(st, Vector3(0.06, 0.42, 0.06), at + Vector3(0, top + 0.19, 0), WOOD_DARK)
			for h: float in [0.16, 0.32]:
				match side:
					0: _block(st, Vector3(edge * 2.0, 0.035, 0.04), Vector3(0, top + h, -edge), WOOD)
					1: _block(st, Vector3(0.04, 0.035, edge * 1.4), Vector3(-edge, top + h, -edge * 0.3), WOOD)
					_: _block(st, Vector3(0.04, 0.035, edge * 1.4), Vector3(edge, top + h, -edge * 0.3), WOOD)
	if step >= 3 and not open:
		# Flower boxes either side of the door.
		for x: float in [-edge + 0.32, edge - 0.32]:
			_block(st, Vector3(0.42, 0.12, 0.16), Vector3(x, top + 0.14, edge - 0.08), WOOD)
			for f in 3:
				_block(st, Vector3(0.1, 0.08, 0.1), Vector3(x - 0.13 + 0.13 * f, top + 0.24, edge - 0.08), FLOWERS[(f + int(x > 0)) % 3])
			_block(st, Vector3(0.38, 0.04, 0.12), Vector3(x, top + 0.21, edge - 0.08), LEAF)
	var lamp_from: int = 2 if hall else 4
	if step >= lamp_from:
		# Lantern posts at the front corners (heads are the emissive mesh).
		for x: float in [-edge, edge]:
			_block(st, Vector3(0.08, 1.0, 0.08), Vector3(x, top + 0.5, edge), WOOD_DARK)
			_block(st, Vector3(0.26, 0.05, 0.05), Vector3(x * 0.94, top + 1.0, edge), WOOD_DARK)
			_block(st, Vector3(0.16, 0.04, 0.16), Vector3(x * 0.9, top + 0.98, edge), Color("3a2c20"))
	var banner_from: int = 2 if hall else 5
	if step >= banner_from:
		var pole: float = 1.7 if not hall else 1.6 + 0.35 * float(step)
		for x: float in [-edge, edge]:
			_block(st, Vector3(0.06, pole, 0.06), Vector3(x, top + pole * 0.5, -edge), WOOD_DARK)
			_block(st, Vector3(0.5, 0.04, 0.04), Vector3(x * 0.9, top + pole - 0.05, -edge), WOOD_DARK)
			var cloth: float = 0.65 if not hall else 0.55 + 0.1 * float(step)
			_block(st, Vector3(0.4, cloth, 0.02), Vector3(x * 0.9, top + pole - 0.08 - cloth * 0.5, -edge + 0.03), BANNER)
			_block(st, Vector3(0.4, 0.06, 0.025), Vector3(x * 0.9, top + pole - 0.08 - cloth, -edge + 0.03), GOLD)
			_block(st, Vector3(0.12, 0.12, 0.025), Vector3(x * 0.9, top + pole - 0.08 - cloth * 0.45, -edge + 0.045), GOLD, 0.0)
			_block(st, Vector3(0.1, 0.1, 0.1), Vector3(x, top + pole + 0.05, -edge), GOLD)
	if step >= 6:
		# Gold-capped pillars at the corners of the court.
		var pillar: float = 0.6 if size < 3 else 0.75
		for at: Vector2 in [Vector2(-edge, -edge), Vector2(edge, -edge), Vector2(-edge, edge), Vector2(edge, edge)]:
			var p := Vector3(at.x, 0, at.y)
			if not open and at.y > 0:
				p.x *= 0.82   # leave room for the lantern posts
			_block(st, Vector3(0.24, pillar, 0.24), p + Vector3(0, top + pillar * 0.5, 0), DRESSED)
			_block(st, Vector3(0.3, 0.06, 0.3), p + Vector3(0, top + pillar + 0.03, 0), GOLD)
			_block(st, Vector3(0.14, 0.12, 0.14), p + Vector3(0, top + pillar + 0.12, 0), GOLD)
	elif open and step >= 4:
		# Open ground: lantern posts already; a pair of stone markers from stage 4.
		for at: Vector2 in [Vector2(-edge, -edge), Vector2(edge, -edge)]:
			_block(st, Vector3(0.2, 0.4, 0.2), Vector3(at.x, top + 0.2, at.y), DRESSED)


static func _lamp_heads(size: int, step: int, top: float) -> ArrayMesh:
	var key: String = "%d|%d|%.2f" % [size, step, top]
	if _lamps.has(key):
		return _lamps[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge: float = float(size) * TILE * 0.5 - 0.22
	for x: float in [-edge, edge]:
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.16, 0.12)
		_part(st, box, Transform3D(Basis(), Vector3(x * 0.9, top + 0.88, edge)), Color.WHITE, 0.0, 0.0)
	var mesh: ArrayMesh = st.commit()
	_lamps[key] = mesh
	return mesh


# A gold finial and pennant on the roof of a stage 6 building.
static func _finial(model: Node3D, holder: Node3D, s: float, hall: bool) -> void:
	var box := AABB()
	var first := true
	for part: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := part as MeshInstance3D
		if not mesh_node.visible or mesh_node.mesh == null or "architecture" not in str(mesh_node.name).to_lower():
			continue
		var b: AABB = mesh_node.transform * mesh_node.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var peak := Vector3(box.get_center().x, box.end.y, box.get_center().z) * s
	var mast: float = 0.7 if not hall else 1.2
	_block(st, Vector3(0.05, mast, 0.05), peak + Vector3(0, mast * 0.5 - 0.1, 0), WOOD_DARK)
	var ball := SphereMesh.new()
	ball.radius = 0.08 if not hall else 0.12
	ball.height = ball.radius * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	_part(st, ball, Transform3D(Basis(), peak + Vector3(0, mast - 0.05, 0)), GOLD, 0.0, 0.0)
	var flag: float = 0.4 if not hall else 0.7
	_block(st, Vector3(flag, flag * 0.45, 0.02), peak + Vector3(flag * 0.5 + 0.03, mast - 0.25, 0), BANNER)
	_block(st, Vector3(flag * 0.5, flag * 0.12, 0.025), peak + Vector3(flag * 0.3, mast - 0.25, 0.005), GOLD)
	var node := MeshInstance3D.new()
	node.name = "TierFinial"
	node.mesh = st.commit()
	node.material_override = _vertex_material()
	holder.add_child(node)
