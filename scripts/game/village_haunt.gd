extends "res://scripts/game/village_raven.gd"
## Haunted edge layer (wilderness fog recedes with village growth).
##
## The haunt level is derived from state every poll (village level and Town Hall
## tier), so there are no save fields. Level 4 is the wild edge: a dense violet
## mist ring hugging the map and a dark, crowded dead-tree outskirts. As the
## manor grows the level drops, and a slow tween pushes the mist outward, fades
## it, thins the dead trees and lightens the outskirts. Everything is a handful of
## unlit meshes (one mist ring, one ground plane, two multimeshes), with no new
## lights and no new art. Decoration only: it never changes the simulation.

const HAUNT_MAX: int = 4
const POLL_INTERVAL: float = 0.5
const TWEEN_SECONDS: float = 3.5
const MIST_HEIGHT: float = 0.25
const MIST_EDGE: Vector2 = Vector2(40.4, 36.4)   # just outside the largest possible village (four expansion plots)
const MIST_WIDTH: float = 7.0
const MIST_PUSH: float = 0.35                    # ring scale at full haunt .. at none is 1 + this
const TREES_MIN: int = 10
const TREES_MAX: int = 44
const OUTSKIRTS_HAUNT_GROUND: Color = Color("1b1427")
const OUTSKIRTS_RECEDE_GROUND: Color = Color("3d4a35")
const TREE_HAUNT: Color = Color("0d0a12")
const TREE_RECEDE: Color = Color("4a4a3e")
const MIST_COLOR: Color = Color(0.5, 0.34, 0.68)
const MIST_ALPHA: float = 0.85

var _haunt_root: Node3D = null
var _mist: MeshInstance3D = null
var _mist_material: StandardMaterial3D = null
var _ground_material: StandardMaterial3D = null
var _tree_material: StandardMaterial3D = null
var _trunks: MultiMesh = null
var _branches: MultiMesh = null
var _haunt_tween: Tween = null
var _shown_t: float = -1.0    # haunt value currently on screen, 0 (manor grown) .. 1 (wild edge)
var _target_t: float = -1.0
var _poll_clock: float = 0.0


func _ready() -> void:
	super()
	_build_haunt()


func _process(delta: float) -> void:
	super(delta)
	if _haunt_root == null:
		return
	_poll_clock -= delta
	if _poll_clock > 0.0:
		return
	_poll_clock = POLL_INTERVAL
	var wanted: float = float(haunt_level()) / float(HAUNT_MAX)
	if is_equal_approx(wanted, _target_t):
		return
	_target_t = wanted
	if _shown_t < 0.0:
		_apply_haunt(wanted)
		return
	if _haunt_tween != null and _haunt_tween.is_valid():
		_haunt_tween.kill()
	_haunt_tween = create_tween()
	_haunt_tween.tween_method(_apply_haunt, _shown_t, wanted, TWEEN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _exit_tree() -> void:
	super()
	if _haunt_tween != null and _haunt_tween.is_valid():
		_haunt_tween.kill()
	_haunt_tween = null
	if is_instance_valid(_haunt_root):
		_haunt_root.queue_free()
	_haunt_root = null
	_mist = null
	_mist_material = null
	_ground_material = null
	_tree_material = null
	_trunks = null
	_branches = null


# 0 (fully grown manor) .. HAUNT_MAX (the wild edge). Derived from village level
# and Town Hall tier; every three steps of combined growth thins the haunt by one.
func haunt_level() -> int:
	var tier: int = 1
	for b: Dictionary in sim.buildings:
		if b["type"] == "hall":
			tier = int(b["tier"])
			break
	var growth: int = (sim.village_level() - 1) + (tier - 1)
	return clampi(HAUNT_MAX - growth / 3, 0, HAUNT_MAX)


func _build_haunt() -> void:
	_haunt_root = Node3D.new()
	_haunt_root.name = "HauntEdge"
	add_child(_haunt_root)
	_build_outskirts_ground()
	_build_dead_trees()
	_build_mist_ring()


func _build_outskirts_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	_ground_material = StandardMaterial3D.new()
	_ground_material.roughness = 1.0
	_ground_material.albedo_color = OUTSKIRTS_HAUNT_GROUND
	plane.material = _ground_material
	var ground := MeshInstance3D.new()
	ground.name = "OutskirtsGround"
	ground.mesh = plane
	ground.position = Vector3(0, -0.03, 0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_haunt_root.add_child(ground)


func _build_dead_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var trunk_xf: Array[Transform3D] = []
	var branch_xf: Array[Transform3D] = []
	while trunk_xf.size() < TREES_MAX:
		var x: float = rng.randf_range(-52.0, 52.0)
		var z: float = rng.randf_range(-46.0, 46.0)
		if absf(x) < 44.0 and absf(z) < 40.0:
			continue
		var height: float = rng.randf_range(1.6, 2.9)
		var girth: float = rng.randf_range(0.8, 1.2)
		var yaw: float = rng.randf_range(0.0, TAU)
		var base := Basis.from_euler(Vector3(0, yaw, 0))
		var trunk_basis: Basis = base.scaled(Vector3(girth, height / 2.4, girth))
		trunk_xf.append(Transform3D(trunk_basis, Vector3(x, height / 2.0, z)))
		var branch_basis: Basis = base * Basis.from_euler(Vector3(0, rng.randf_range(0.0, TAU), rng.randf_range(0.5, 0.9)))
		branch_xf.append(Transform3D(branch_basis, Vector3(x, height * 0.78, z)))

	_tree_material = StandardMaterial3D.new()
	_tree_material.roughness = 1.0
	_tree_material.albedo_color = TREE_HAUNT

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.07
	trunk_mesh.bottom_radius = 0.13
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	trunk_mesh.material = _tree_material
	_trunks = _multimesh(trunk_mesh, trunk_xf, "DeadTreeTrunks")

	var branch_mesh := BoxMesh.new()
	branch_mesh.size = Vector3(0.9, 0.07, 0.07)
	branch_mesh.material = _tree_material
	_branches = _multimesh(branch_mesh, branch_xf, "DeadTreeBranches")


func _multimesh(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_haunt_root.add_child(node)
	return multi


# One shader-free ring of quads around the map: an opaque inner band fading to
# transparent at the outer edge. Vertex colours carry the falloff, so the whole
# ring is a single draw call.
func _build_mist_ring() -> void:
	var layers: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(MIST_WIDTH * 0.45, 0.45), Vector2(MIST_WIDTH, 0.0)]
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for layer in 2:
		var inner_d: float = layers[layer].x
		var outer_d: float = layers[layer + 1].x
		var inner_a: float = layers[layer].y
		var outer_a: float = layers[layer + 1].y
		for side in 4:
			var p0: Vector3 = _ring_point(inner_d, side)
			var p1: Vector3 = _ring_point(inner_d, side + 1)
			var p2: Vector3 = _ring_point(outer_d, side + 1)
			var p3: Vector3 = _ring_point(outer_d, side)
			var c0 := Color(MIST_COLOR, inner_a)
			var c1 := Color(MIST_COLOR, inner_a)
			var c2 := Color(MIST_COLOR, outer_a)
			var c3 := Color(MIST_COLOR, outer_a)
			verts.append_array([p0, p1, p2, p0, p2, p3])
			colors.append_array([c0, c1, c2, c0, c2, c3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var ring := ArrayMesh.new()
	ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_mist_material = StandardMaterial3D.new()
	_mist_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mist_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mist_material.vertex_color_use_as_albedo = true
	_mist_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mist_material.disable_receive_shadows = true
	_mist_material.albedo_color = Color(1, 1, 1, 0)
	ring.surface_set_material(0, _mist_material)

	_mist = MeshInstance3D.new()
	_mist.name = "HauntMistRing"
	_mist.mesh = ring
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.visible = false
	_haunt_root.add_child(_mist)


# Point on the rectangle of half extents MIST_EDGE grown by distance d, at corner
# index side (0..3, wrapping), lifted to the mist height.
func _ring_point(d: float, side: int) -> Vector3:
	var e: Vector2 = MIST_EDGE + Vector2(d, d)
	var corners: Array[Vector2] = [Vector2(e.x, e.y), Vector2(-e.x, e.y), Vector2(-e.x, -e.y), Vector2(e.x, -e.y)]
	var c: Vector2 = corners[side % 4]
	return Vector3(c.x, MIST_HEIGHT, c.y)


# t: 0 = manor grown (mist far out, faded, sparse trees, light ground),
#    1 = wild edge (mist hugging the map, dense violet, crowded dark trees).
func _apply_haunt(t: float) -> void:
	_shown_t = t
	if _mist == null or not is_instance_valid(_mist):
		return
	_mist.scale = Vector3(1.0 + MIST_PUSH * (1.0 - t), 1.0, 1.0 + MIST_PUSH * (1.0 - t))
	_mist.visible = t > 0.02
	_mist_material.albedo_color.a = MIST_ALPHA * t
	_ground_material.albedo_color = OUTSKIRTS_RECEDE_GROUND.lerp(OUTSKIRTS_HAUNT_GROUND, t)
	_tree_material.albedo_color = TREE_RECEDE.lerp(TREE_HAUNT, t)
	var shown: int = int(round(lerpf(float(TREES_MIN), float(TREES_MAX), t)))
	_trunks.visible_instance_count = shown
	_branches.visible_instance_count = shown
