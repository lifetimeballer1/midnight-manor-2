extends "res://scripts/game/village_assets.gd"

# Idle motion (visual only), over the asset theme layer: a few parts of the building models move.
#
#   * Banner flags sway on their poles: about 0.35 rad either way at ~1.4 Hz, with a small
#     0.08 rad tilt on a second, quicker beat.
#   * Hanging bells swing like a slow pendulum (0.2 rad at ~0.7 Hz) with a slight sideways drift.
#   * Flame glows flicker: the height breathes between about 0.9 and 1.18, the width by +/-4%, and
#     the surface emission pulses by +/-25%. Each flame gets its own copy of its material, so the
#     shared amber material of the other lamps is never changed.
#
# Parts are found by NODE NAME inside the building models under building_layer, so do not rename
# these parts in the Blender source:
#   "banner flag"  -> flag,   pivots on the centre of its mesh bounds
#   "bell"         -> bell,   as the last word of the name ("T04 Bell.001"), never "Bellows";
#                             pivots on the top-centre of its mesh bounds (the hanging hinge)
#   "flame glow"   -> flame,  pivots on the bottom-centre of its mesh bounds (its base)
# Godot may turn the "." of "Bell.001" into "_" on import, so both separators are accepted.
#
# The exporter drops part origins (the parts sit at the model origin with their geometry already in
# building space), so the node origin is never used. Each hinge is taken from mesh.get_aabb() in the
# part's own space, and each part moves as rest * T(hinge) * motion * T(-hinge), so the hinge point
# itself stays put. Every part is driven from its stored rest transform, so nothing accumulates. At
# most MOTION_MAX parts move (MOTION_MAX_LOW on phones, the same check the effects layer uses). The
# motion pauses with the simulation. Launch with --no-motion to freeze every part at its rest pose.

const MOTION_MAX: int = 60
const MOTION_MAX_LOW: int = 24
const MOTION_FLAG_SWAY: float = 0.35           # rad, about the flag pole (local Y)
const MOTION_FLAG_HZ: float = 1.4
const MOTION_FLAG_TILT: float = 0.08           # rad, about local Z
const MOTION_FLAG_TILT_HZ: float = 2.3
const MOTION_BELL_SWING: float = 0.2           # rad, pendulum about local Z
const MOTION_BELL_HZ: float = 0.7
const MOTION_BELL_SIDE: float = 0.06           # rad, slight drift about local X
const MOTION_FLAME_RATE_A: float = 6.3         # rad/s
const MOTION_FLAME_RATE_B: float = 13.0        # rad/s
const MOTION_EMISSION_SWING: float = 0.25

var _motion_on: bool = true
var _motion_clock: float = 0.0
var _motion_parts: Array = []                  # {id, node, kind, phase, hinge: Vector3, rest: Transform3D, mats: Array}
var _motion_bell_re: RegEx = null


func _ready() -> void:
	super()
	_motion_on = "--no-motion" not in OS.get_cmdline_user_args()


func _process(delta: float) -> void:
	super(delta)
	if not _motion_on or sim == null or sim.paused:
		return
	_motion_clock += delta
	motion_apply(_motion_clock)


# The base rebuilds every building model whenever the village changes, so the animated parts are
# collected again from the fresh models.
func _rebuild_buildings() -> void:
	motion_clear()
	super()
	motion_collect(building_layer)


func motion_clear() -> void:
	_motion_parts.clear()


func motion_part_count() -> int:
	return _motion_parts.size()


# Walks a node tree and keeps the mesh parts that have a motion kind, up to the cap.
func motion_collect(node: Node) -> void:
	if _motion_parts.size() >= _motion_cap():
		return
	if node is MeshInstance3D:
		_motion_add(node as MeshInstance3D)
	for child in node.get_children():
		motion_collect(child)


# "flag", "flame", "bell", or "" for a part that does not move.
func motion_kind(part_name: String) -> String:
	var lower: String = part_name.to_lower()
	if lower.contains("banner flag"):
		return "flag"
	if lower.contains("flame glow"):
		return "flame"
	if _motion_bell_re == null:
		_motion_bell_re = RegEx.create_from_string("(^|\\s)bell([._]?\\d+)?$")
	if _motion_bell_re.search(lower) != null:
		return "bell"
	return ""


# The pivot in the part's own space, from its mesh bounds: the centre for a flag, the top-centre
# for a bell (where it hangs) and the bottom-centre for a flame (its base).
func motion_hinge(kind: String, bounds: AABB) -> Vector3:
	var centre: Vector3 = bounds.get_center()
	match kind:
		"bell":
			return Vector3(centre.x, bounds.end.y, centre.z)
		"flame":
			return Vector3(centre.x, bounds.position.y, centre.z)
	return centre


# One update at clock time t: every animated part is set from its rest pose.
func motion_apply(t: float) -> void:
	for entry: Dictionary in _motion_parts:
		var node: Variant = entry["node"]
		if not is_instance_valid(node):
			continue
		var part: MeshInstance3D = node
		var rest: Transform3D = entry["rest"]
		var hinge: Vector3 = entry["hinge"]
		var phase: float = float(entry["phase"])
		var motion := Basis()
		match str(entry["kind"]):
			"flag":
				var sway: float = MOTION_FLAG_SWAY * sin(TAU * MOTION_FLAG_HZ * t + phase)
				var tilt: float = MOTION_FLAG_TILT * sin(TAU * MOTION_FLAG_TILT_HZ * t + phase * 1.7)
				motion = Basis(Vector3.UP, sway) * Basis(Vector3.BACK, tilt)
			"bell":
				var swing: float = MOTION_BELL_SWING * sin(TAU * MOTION_BELL_HZ * t + phase)
				var side: float = MOTION_BELL_SIDE * cos(TAU * MOTION_BELL_HZ * t + phase)
				motion = Basis(Vector3.BACK, swing) * Basis(Vector3.RIGHT, side)
			"flame":
				var a: float = sin(MOTION_FLAME_RATE_A * t + phase)
				var b: float = sin(MOTION_FLAME_RATE_B * t + phase * 1.3)
				# Height 0.90..1.18 (centre 1.04), width and depth +/-4%.
				var scale_xyz := Vector3(1.0 + 0.04 * a, 1.04 + 0.08 * a + 0.06 * b, 1.0 + 0.04 * b)
				motion = Basis.from_scale(scale_xyz)
				var flick: float = 0.6 * a + 0.4 * b
				for mat_entry: Dictionary in entry["mats"]:
					var mat: BaseMaterial3D = mat_entry["mat"]
					mat.emission_energy_multiplier = float(mat_entry["energy"]) * (1.0 + MOTION_EMISSION_SWING * flick)
		part.transform = rest * Transform3D(Basis(), hinge) * Transform3D(motion, Vector3.ZERO) * Transform3D(Basis(), -hinge)


func _motion_cap() -> int:
	return MOTION_MAX_LOW if _sky_is_phone() else MOTION_MAX


func _motion_add(part: MeshInstance3D) -> void:
	var id: int = part.get_instance_id()
	for entry: Dictionary in _motion_parts:
		if int(entry["id"]) == id:
			return
	var kind: String = motion_kind(str(part.name))
	if kind.is_empty() or part.mesh == null:
		return
	var mats: Array = []
	if kind == "flame":
		# Private copies, so only this flame pulses and the shared amber material stays as it was.
		for surface in part.mesh.get_surface_count():
			var source := part.get_active_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var copy := source.duplicate() as BaseMaterial3D
			part.set_surface_override_material(surface, copy)
			mats.append({"mat": copy, "energy": copy.emission_energy_multiplier})
	_motion_parts.append({
		"id": id,
		"node": part,
		"kind": kind,
		"phase": fposmod(float(id % 1009) * 0.6180339, TAU),
		"hinge": motion_hinge(kind, part.mesh.get_aabb()),
		"rest": part.transform,
		"mats": mats,
	})
