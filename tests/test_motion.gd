extends SceneTree

# Idle motion layer (village_motion.gd): the chain, part discovery by name, hinge-pivoted motion
# from rest (the mesh is offset from its node origin, as the exporter leaves it), no accumulation,
# the cap, and a real bell-tower model.

const FLAG_HINGE := Vector3(1.2, 1.0, -0.5)     # centre of the test mesh bounds
const BELL_HINGE := Vector3(1.2, 1.3, -0.5)     # top-centre
const FLAME_HINGE := Vector3(1.2, 0.7, -0.5)    # bottom-centre
const FLAG_FAR := Vector3(0.9, 0.7, -0.8)       # a bounds corner that should move
const BELL_FAR := Vector3(0.9, 0.7, -0.8)
const FLAME_FAR := Vector3(1.5, 1.3, -0.2)

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		printerr("FAIL ", text)


# A MeshInstance3D at the given position whose geometry sits away from its origin (AABB centre
# near (1.2, 1.0, -0.5)), the way the exporter delivers the parts.
func _part(part_name: String, parent: Node3D, at: Vector3, flame: bool) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0.9, 0.7, -0.8), Vector3(1.5, 0.7, -0.2), Vector3(1.2, 1.3, -0.5)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if flame:
		var glow := StandardMaterial3D.new()
		glow.emission_enabled = true
		glow.emission_energy_multiplier = 2.0
		mesh.surface_set_material(0, glow)
	part.mesh = mesh
	part.position = at
	parent.add_child(part)
	return part


func _same_point(a: Vector3, b: Vector3) -> bool:
	return (a - b).length() < 0.0001


func _run() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game.set_process(false)

	# (1) The motion layer sits in the scene root's script chain.
	var in_chain: bool = false
	var layer: Script = game.get_script()
	while layer != null:
		if layer.resource_path == "res://scripts/game/village_motion.gd":
			in_chain = true
		layer = layer.get_base_script()
	check(in_chain, "the motion layer is in the scene root's script chain")

	# (2) Synthetic flag, bell, flame and a bellows lookalike.
	var holder := Node3D.new()
	root.add_child(holder)
	var flag: MeshInstance3D = _part("MMR | barracks | T03 Banner Flag 2.001", holder, Vector3(0.0, 3.0, 0.0), false)
	var bell: MeshInstance3D = _part("MMR | bell-tower | T04 Bell.001", holder, Vector3(2.0, 4.0, 0.0), false)
	var flame: MeshInstance3D = _part("MMR | watchfire | T04 Flame Glow.001", holder, Vector3(4.0, 0.0, 0.0), true)
	var bellows: MeshInstance3D = _part("MMR | smeltery | T03 Bellows.001", holder, Vector3(6.0, 0.0, 0.0), false)
	var glow_source: StandardMaterial3D = (flame.mesh as ArrayMesh).surface_get_material(0) as StandardMaterial3D

	game.motion_clear()
	game.motion_collect(holder)
	check(game.motion_part_count() == 3, "flag, bell and flame are collected; the bellows lookalike is not (count=%d)" % game.motion_part_count())

	# (3) Classification by name.
	check(game.motion_kind("MMR | smeltery | T03 Bellows.001") == "", "a Bellows part is not a bell")
	check(game.motion_kind("MMR | bell-tower | T04 Bell.001") == "bell", "a Bell.001 part is a bell")
	check(game.motion_kind("MMR | bell-tower | T04 Bell_001") == "bell", "a bell with the sanitised separator is a bell")
	check(game.motion_kind("MMR | bell-tower | T04 Architecture.001") == "", "bell-tower architecture is not a bell")
	check(game.motion_kind("MMR | barracks | T03 Banner Flag 2.001") == "flag", "a banner flag part is a flag")
	check(game.motion_kind("MMR | watchfire | T04 Flame Glow.001") == "flame", "a flame glow part is a flame")

	# Rest poses are captured before any motion; the hinge must stay fixed while the rest moves.
	var flag_rest_t: Transform3D = flag.transform
	var bell_rest_t: Transform3D = bell.transform
	var bellows_rest: Basis = bellows.transform.basis
	game.motion_apply(0.0)
	var flag_0: Basis = flag.transform.basis
	var bell_0: Basis = bell.transform.basis
	var flame_scale_0: Vector3 = flame.transform.basis.get_scale()
	var flame_energy_0: float = (flame.get_surface_override_material(0) as BaseMaterial3D).emission_energy_multiplier
	game.motion_apply(0.37)
	var flag_1: Basis = flag.transform.basis
	var bell_1: Basis = bell.transform.basis
	var flame_scale_1: Vector3 = flame.transform.basis.get_scale()
	var flame_energy_1: float = (flame.get_surface_override_material(0) as BaseMaterial3D).emission_energy_multiplier

	check(not flag_1.is_equal_approx(flag_rest_t.basis), "the flag sways away from its rest pose")
	check(not flag_1.is_equal_approx(flag_0), "the flag basis changes between two times")
	check(not bell_1.is_equal_approx(bell_rest_t.basis), "the bell swings away from its rest pose")
	check(not bell_1.is_equal_approx(bell_0), "the bell basis changes between two times")
	check(absf(flame_scale_1.y - flame_scale_0.y) > 0.001, "the flame height flickers")
	check(flame_scale_1.y >= 0.85 and flame_scale_1.y <= 1.25 and flame_scale_0.y >= 0.85 and flame_scale_0.y <= 1.25, "the flame height stays within 0.85..1.25")
	check(absf(flame_energy_1 - flame_energy_0) > 0.01, "the flame emission pulses")
	check(is_equal_approx(glow_source.emission_energy_multiplier, 2.0), "the original shared amber material keeps energy 2.0")
	check(flame.get_surface_override_material(0) != glow_source, "the flame animates its own material copy")
	check(bellows.transform.basis.is_equal_approx(bellows_rest), "the bellows lookalike does not move")

	# Hinge pivots: the hinge point stays where the rest pose put it, while a far point moves.
	check(_same_point(flag.transform * FLAG_HINGE, flag_rest_t * FLAG_HINGE), "the flag pivots on its bounds centre (hinge fixed)")
	check(not _same_point(flag.transform * FLAG_FAR, flag_rest_t * FLAG_FAR), "the flag's far edge moves")
	check(_same_point(bell.transform * BELL_HINGE, bell_rest_t * BELL_HINGE), "the bell hangs from its top-centre (hinge fixed)")
	check(not _same_point(bell.transform * BELL_FAR, bell_rest_t * BELL_FAR), "the bell's far edge swings")
	check(_same_point(flame.transform * FLAME_HINGE, Transform3D(Basis(), Vector3(4.0, 0.0, 0.0)) * FLAME_HINGE), "the flame is pinned at its base (hinge fixed)")
	check(not _same_point(flame.transform * FLAME_FAR, Transform3D(Basis(), Vector3(4.0, 0.0, 0.0)) * FLAME_FAR), "the flame's top edge moves")

	# (5) No accumulation: t=0 gives the same pose before and after other times.
	game.motion_apply(0.0)
	var snap_a: Array = [flag.transform, bell.transform, flame.transform]
	game.motion_apply(0.37)
	game.motion_apply(0.0)
	var snap_b: Array = [flag.transform, bell.transform, flame.transform]
	var same: bool = true
	for i in 3:
		if not (snap_a[i] as Transform3D).is_equal_approx(snap_b[i] as Transform3D):
			same = false
	check(same, "applying t=0 twice gives identical transforms (no accumulation)")

	# (4) The cap: 100 flags, at most MOTION_MAX collected.
	game.motion_clear()
	var crowd := Node3D.new()
	root.add_child(crowd)
	for i in 100:
		_part("MMR | barracks | T03 Banner Flag %d" % i, crowd, Vector3(float(i) * 0.5, 0.0, 0.0), false)
	game.motion_collect(crowd)
	check(game.motion_part_count() > 0 and game.motion_part_count() <= game.MOTION_MAX, "100 flags are capped at MOTION_MAX (count=%d)" % game.motion_part_count())

	# (6) Real model: the bell tower GLB as shipped. It must carry a bell and a flag part.
	game.motion_clear()
	var packed: PackedScene = load("res://art/bell-tower_t4/bell-tower_t4.glb")
	var model: Node3D = packed.instantiate()
	root.add_child(model)
	var bell_names: Array[String] = []
	var flag_names: Array[String] = []
	var stack: Array = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var kind: String = game.motion_kind(str(node.name))
			if kind == "bell":
				bell_names.append(str(node.name))
			elif kind == "flag":
				flag_names.append(str(node.name))
		stack.append_array(node.get_children())
	print("bell-tower_t4 bell parts: ", bell_names, "  flag parts: ", flag_names)
	check(bell_names.size() >= 1, "bell-tower_t4.glb has at least one classified bell part")
	check(flag_names.size() >= 1, "bell-tower_t4.glb has at least one classified banner flag part")
	game.motion_collect(model)
	check(game.motion_part_count() >= bell_names.size() + flag_names.size(), "the real model's motion parts are collected")
	game.motion_apply(0.5)

	print("MOTION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
