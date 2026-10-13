extends "res://scripts/game/village_polish.gd"

# Defense layer (visual only): walls, gates, towers and traps look and move like defenses.
#
# Look
#   * Wall runs read as one wall. A straight piece is stretched to the full tile so it meets
#     its neighbours; corners, ends and junctions grow an arm of the same model toward each
#     neighbour, so a palisade turns a corner as a palisade instead of two grey rails. Earthen
#     ramparts join the same family. The old flat connector rails are hidden.
#   * Defenses get a lighter weathering than the soot every building shares, so timber and
#     stone read at night.
#   * Watchtowers and archer towers are manned: a small archer stands on the platform, idles,
#     turns to its target and draws when the tower fires (capped; fewer on phones).
# Animation
#   * Firing: towers kick, ballistas and bastions recoil away from their target. Tower arrows
#     leave from the tower top; a ballista throws a heavy bolt, a bastion a smoking iron ball.
#     Traps no longer shoot arrows: spikes snap up out of the plate, and fire traps roar.
#   * Hit: a struck defense shudders and sheds chips of its own material.
#   * Damage: below half health a defense slowly leans and settles into the ground.
#   * Destruction: the model topples and sinks in a cloud of chips, then a rubble pile marks
#     the ruin until it is repaired.
#   * Gates bump and puff dust as the lift opens or drops.
#
# Only view nodes move: each defense model is wrapped in its own pivot, so these motions never
# fight the selection bounce on the view root or the per-frame scale reset on the model. Sim,
# saves and the event list are untouched apart from a private mark so an event is read once.
# Transients share EFFECT_LIMIT. Launch with --no-defense-fx to compare with the old look.

const DEF_WALLS: Array[String] = ["wall", "stonewall", "gate", "rampart"]
const DEF_TOWERS: Array[String] = ["tower", "archer_tower"]
const DEF_SHOOTERS: Array[String] = ["tower", "archer_tower", "ballista", "bastion", "watchfire"]
const DEF_TRAPS: Array[String] = ["trap", "fire-trap"]
const DEF_STONE: Array[String] = ["stonewall", "archer_tower", "ballista", "bastion", "watchfire"]
const DEF_SOOT := Color("957f68")            # the shared weathering every building gets
const DEF_LIFT := Color("b9a389")            # lighter weathering for defenses
const DEF_LIFT_EARTH := Color(1.5, 1.3, 1.1)  # the dark log-and-earth ramparts need more to read
const DEF_LANTERN_REACH: float = 0.5        # metres from the axis: just off a tower face
const DEF_LANTERN_POST: float = 0.66        # metres along a gate to its post
const DEF_HALO: float = 0.3                  # halo quad size, against the shared 1.7 m disc
const DEF_SENTRY_MAX: int = 12
const DEF_SENTRY_LOW: int = 5
const DEF_SENTRY_SCALE: float = 0.42
const DEF_SENTRY_REACH: float = 0.2          # model units from the tower axis to the parapet
const DEF_SENTRY_ATTACK: float = 0.7          # seconds the draw pose holds before idling again
const DEF_KICK_TIME: float = 0.28
const DEF_SHAKE_TIME: float = 0.32
const DEF_SNAP_TIME: float = 0.42
const DEF_LEAN_MAX: float = 0.075             # rad, at zero health
const DEF_SINK_MAX: float = 0.12
const DEF_POLL: float = 0.25
const DEF_FALL_TIME: float = 0.75
const DEF_WOOD := Color("3f2b1c")
const DEF_STONE_CHIP := Color("4d4842")
const DEF_EARTH := Color("3a2d20")
const DEF_IRON := Color(0.16, 0.15, 0.16)
const DEF_FLAME := Color(1.0, 0.55, 0.18)

var _def_on: bool = true
var _def: Dictionary = {}                    # building id -> dressing/animation state
var _def_poll: float = 0.0
var _def_sentries: int = 0
var _def_rubble_mats: Dictionary = {}        # colour html -> shared material
var _def_rubble_mesh: BoxMesh = null


func _ready() -> void:
	super()
	_def_on = "--no-defense-fx" not in OS.get_cmdline_user_args()


# Wall-family joins include ramparts, so a piece rebuilds when a rampart beside it rises or falls.
func _view_signature(b: Dictionary) -> String:
	if not _def_on or str(b["type"]) not in DEF_WALLS:
		return super(b)
	return super(b) + "|%d" % _def_mask(b)


func _def_mask(b: Dictionary) -> int:
	var mask: int = 0
	for direction: Vector2i in _def_neighbours(b):
		mask |= (1 if direction.x == 1 else 2) if direction.x != 0 else (4 if direction.y == 1 else 8)
	return mask


func _def_neighbours(b: Dictionary) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for other: Dictionary in sim.buildings:
		if str(other["type"]) not in DEF_WALLS or float(other["hp"]) <= 0.0:
			continue
		var direction := Vector2i(int(other["x"]) - int(b["x"]), int(other["y"]) - int(b["y"]))
		if absi(direction.x) + absi(direction.y) == 1:
			found.append(direction)
	return found


func _rebuild_buildings() -> void:
	super()
	if not _def_on:
		return
	for id: Variant in _def.keys():
		var state: Dictionary = _def[id]
		if not building_views.has(id) or not is_same(building_views[id].get("def"), state):
			if bool(state.get("sentry_counted", false)):
				_def_sentries -= 1
			_def.erase(id)
	for b: Dictionary in sim.buildings:
		var type_name: String = str(b["type"])
		if type_name not in DEF_WALLS and type_name not in DEF_SHOOTERS and type_name not in DEF_TRAPS:
			continue
		var view: Dictionary = building_views.get(int(b["id"]), {})
		if view.is_empty() or view.has("def"):
			continue
		_def_dress(b, view)


func _def_dress(b: Dictionary, view: Dictionary) -> void:
	var root_node: Node3D = view["root"]
	var model: Node3D = view["model"]
	if not is_instance_valid(root_node) or not is_instance_valid(model):
		return
	var type_name: String = str(b["type"])
	var pivot := Node3D.new()
	pivot.name = "DefensePivot"
	root_node.add_child(pivot)
	model.reparent(pivot, false)
	_def_lighten(model, DEF_LIFT_EARTH if type_name == "rampart" else DEF_LIFT)
	var key: String = _building_asset(b)
	var dims: Array = catalog[key]["dimensions_m"] if catalog.has(key) else [1.0, 1.0, 1.0]
	var factor: float = model.scale.x
	var state: Dictionary = {"pivot": pivot, "model": model, "type": type_name, "top": float(dims[1]) * factor,
		"kick": 0.0, "shake": 0.0, "snap": 0.0, "lean": 0.0, "lean_goal": 0.0, "aim": Vector3.ZERO,
		"lean_axis": Vector3(cos(float(b["id"]) * 2.3), 0.0, sin(float(b["id"]) * 2.3)),
		"gate_open": bool(b.get("gate_open", true)), "ruined": false, "rubble": null}
	# The night lamp and its glow move with the defense and go dark when it falls.
	var lights := Node3D.new()
	lights.name = "DefenseLights"
	pivot.add_child(lights)
	for key_name: String in ["lamp", "glow"]:
		var light: Node3D = view.get(key_name)
		if is_instance_valid(light):
			light.reparent(lights, false)
	state["lights"] = lights
	if type_name in DEF_WALLS:
		_def_dress_wall(b, view, state, _def_body_length(model) * factor)
	if is_instance_valid(view.get("glow")):
		_def_hang_lantern(state, view, type_name, model)
	if type_name in DEF_TOWERS:
		_def_add_sentry(state, model, factor)
	view["def"] = state
	_def[int(b["id"])] = state


# The shared night glow is a 1.7 m soft disc floating in front of the building, which reads as a
# blob on a slim tower or gate. Defenses hang a real lantern on a bracket instead: an iron cage
# with a hot core, a tight halo around the flame and the lamp's light falling off on the ground.
func _def_hang_lantern(state: Dictionary, view: Dictionary, type_name: String, model: Node3D) -> void:
	var glow: MeshInstance3D = view["glow"]
	var lamp: OmniLight3D = view.get("lamp")
	var mount := Vector3(0.0, 1.15, DEF_LANTERN_REACH)
	var wall := Vector3(0.0, 1.15, DEF_LANTERN_REACH - 0.2)
	if type_name == "gate":
		# On the gate post, out of the way of the lift.
		mount = Vector3(DEF_LANTERN_POST, 1.25, 0.28).rotated(Vector3.UP, model.rotation.y)
		wall = Vector3(DEF_LANTERN_POST, 1.25, 0.08).rotated(Vector3.UP, model.rotation.y)
	var lantern := Node3D.new()
	lantern.name = "DefenseLantern"
	(state["lights"] as Node3D).add_child(lantern)
	lantern.position = mount
	lantern.look_at_from_position(mount, mount + (mount - wall).normalized() * Vector3(1, 0, 1) + Vector3(0, 0, 0.0001), Vector3.UP)
	_box(Vector3(0.04, 0.04, 0.24), Vector3(0, 0.16, 0.12), DEF_IRON, lantern)          # bracket arm
	_box(Vector3(0.17, 0.03, 0.17), Vector3(0, 0.1, 0), DEF_IRON, lantern)              # cap
	_box(Vector3(0.14, 0.02, 0.14), Vector3(0, -0.1, 0), DEF_IRON, lantern)             # base
	for corner: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		_box(Vector3(0.02, 0.2, 0.02), Vector3(corner.x * 0.065, 0, corner.y * 0.065), DEF_IRON, lantern)
	var core: MeshInstance3D = _box(Vector3(0.08, 0.13, 0.08), Vector3.ZERO, DEF_FLAME, lantern)
	var hot := core.material_override as StandardMaterial3D
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.78, 0.42)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in lantern.get_children():
		(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The glow becomes a small halo on the flame; the lamp sits just in front so its light
	# pools on the wall and ground below instead of hanging in the air.
	glow.position = mount
	if glow.mesh is QuadMesh:
		(glow.mesh as QuadMesh).size = Vector2.ONE * DEF_HALO
	if is_instance_valid(lamp):
		lamp.position = mount + Vector3(0, -0.05, 0)
		lamp.omni_range = 3.0
		lamp.omni_attenuation = 1.6
	state["lantern_core"] = core
	state["glow"] = glow


# Defenses keep their soot override but take the lighter defense weathering.
func _def_lighten(node: Node, lift: Color) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		if part.mesh != null:
			for surface in part.mesh.get_surface_count():
				var override := part.get_surface_override_material(surface) as BaseMaterial3D
				if override != null and override.albedo_color.is_equal_approx(DEF_SOOT):
					override.albedo_color = lift
	for child in node.get_children():
		_def_lighten(child, lift)


func _def_dress_wall(b: Dictionary, view: Dictionary, state: Dictionary, length: float) -> void:
	var model: Node3D = state["model"]
	var pivot: Node3D = state["pivot"]
	var neighbours: Array[Vector2i] = _def_neighbours(b)
	if view.has("joins") and is_instance_valid(view["joins"]):
		(view["joins"] as Node3D).visible = false
	if neighbours.is_empty() or length <= 0.01:
		return
	if str(b["type"]) == "rampart":
		for part: MeshInstance3D in _def_parts(model):
			if "ground" in str(part.name).to_lower():
				part.hide()
	var on_x: Array[int] = []
	var on_z: Array[int] = []
	for direction: Vector2i in neighbours:
		if direction.x != 0:
			on_x.append(direction.x)
		else:
			on_z.append(direction.y)
	var outward: Vector2 = Vector2(float(b["x"]) + 0.5, float(b["y"]) + 0.5) - _def_keep()
	if str(b["type"]) == "gate":
		# A gate stays one piece, stretched along its run so it meets the wall either side.
		var gate_on_x: bool = not on_x.is_empty()
		_def_place_run(model, gate_on_x, [-1, 1] if (on_x if gate_on_x else on_z).size() > 0 else [], outward, length, false)
		return
	# The model carries the main run; a second run (corner, junction) is a copy of the model.
	# Each run reaches the edge on a side with a neighbour and keeps its own length on an open
	# side, so corner fences overlap instead of leaving a notch. Fences face away from the keep.
	var main_on_x: bool = not on_x.is_empty()
	_def_place_run(model, main_on_x, on_x if main_on_x else on_z, outward, length, false)
	if main_on_x and not on_z.is_empty():
		var arms := Node3D.new()
		arms.name = "WallArms"
		pivot.add_child(arms)
		var arm: Node3D = model.duplicate() as Node3D
		arms.add_child(arm)
		_def_place_run(arm, false, on_z, outward, length, true)
		state["arms"] = arms


# Points a wall run along X or Z with its fence side outward, and stretches it to span from
# the open end (its own half length) or the tile edge (toward a neighbour) to the other side.
func _def_place_run(node: Node3D, along_x: bool, sides: Array, outward: Vector2, length: float, lowered: bool) -> void:
	if along_x:
		node.rotation.y = 0.0 if outward.y <= 0.0 else PI
	else:
		node.rotation.y = PI / 2.0 if outward.x <= 0.0 else -PI / 2.0
	var half: float = length * 0.5
	var low: float = -TILE * 0.505 if sides.has(-1) else -half
	var high: float = TILE * 0.505 if sides.has(1) else half
	_def_stretch(node, (high - low) / length)
	var axis: Vector3 = Vector3.RIGHT if along_x else Vector3.BACK
	node.position = axis * ((low + high) * 0.5) + (Vector3.DOWN * 0.012 if lowered else Vector3.ZERO)


# Where the walls are guarding: the Manor Hall, or the map centre without one.
func _def_keep() -> Vector2:
	for b: Dictionary in sim.buildings:
		if str(b["type"]) == "hall":
			return sim.center(b)
	return Vector2(10.0, 8.0)


# Length along local X of the model body, without the wider ground plate.
func _def_body_length(model: Node3D) -> float:
	var length: float = 0.0
	for part: MeshInstance3D in _def_parts(model):
		if part.mesh != null and "ground" not in str(part.name).to_lower():
			length = maxf(length, part.mesh.get_aabb().size.x)
	return length


func _def_stretch(model: Node3D, along: float) -> void:
	for part: MeshInstance3D in _def_parts(model):
		if part.mesh == null:
			continue
		var centre: float = part.mesh.get_aabb().get_center().x
		part.scale.x = along
		part.position.x = -centre * (along - 1.0)


func _def_parts(model: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	details.meshes(model, found)
	return found


func _def_add_sentry(state: Dictionary, model: Node3D, factor: float) -> void:
	if _def_sentries >= (DEF_SENTRY_LOW if _sky_is_phone() else DEF_SENTRY_MAX):
		return
	var platform: float = -1.0
	for part: MeshInstance3D in _def_parts(model):
		if part.mesh != null and "roof supports" in str(part.name).to_lower():
			platform = part.mesh.get_aabb().position.y + part.position.y
	if platform <= 0.0:
		return
	var sentry: Node3D = _model("char_archer")
	(state["pivot"] as Node3D).add_child(sentry)
	sentry.scale = Vector3.ONE * DEF_SENTRY_SCALE
	state["sentry_base"] = Vector3(0.0, platform * factor - 0.02, 0.0)
	state["sentry_reach"] = DEF_SENTRY_REACH * factor
	_def_face(state, sentry, fmod(float(state["lean_axis"].x) * 7.0, TAU))
	var player: AnimationPlayer = _find_player_cached("char_archer", sentry)
	if player != null and player.has_animation("idle"):
		player.play("idle")
		player.seek(randf() * 1.5, true)
	state["sentry"] = sentry
	state["player"] = player
	state["sentry_attack"] = 0.0
	state["sentry_counted"] = true
	_def_sentries += 1


# The sentry steps to the parapet on the side it faces, clear of the roof over the platform.
func _def_face(state: Dictionary, sentry: Node3D, yaw: float) -> void:
	sentry.rotation.y = yaw
	sentry.position = Vector3(state["sentry_base"]) + Vector3(sin(yaw), 0.0, cos(yaw)) * float(state["sentry_reach"])


# ---------------------------------------------------------------- events


func _read_combat_events() -> void:
	if _def_on:
		for event: Dictionary in sim.events:
			if event.has("_def"):
				continue
			event["_def"] = true
			match str(event.get("kind", "")):
				"shot":
					_def_on_shot(event)
				"hit":
					if bool(event.get("friendly", false)):
						_def_on_hit(Vector2(float(event["x"]), float(event["y"])))
				"destroyed":
					_def_on_ruin(Vector2(float(event["x"]), float(event["y"])))
	super()


func _def_at(tile: Vector2) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if _def.has(int(b["id"])) and sim.center(b).distance_to(tile) < 0.2:
			return b
	return {}


func _def_on_shot(event: Dictionary) -> void:
	var from_tile := Vector2(float(event["from_x"]), float(event["from_y"]))
	if _raider_near(from_tile, 0.7):
		return
	var b: Dictionary = _def_at(from_tile)
	if b.is_empty() or float(b["hp"]) <= 0.0:
		return
	var state: Dictionary = _def[int(b["id"])]
	var target: Vector3 = world_position(Vector2(float(event["x"]), float(event["y"])))
	var aim: Vector3 = target - world_position(from_tile)
	aim.y = 0.0
	state["aim"] = aim.normalized() if aim.length() > 0.01 else Vector3.ZERO
	var type_name: String = str(state["type"])
	if type_name in DEF_TRAPS:
		state["snap"] = 1.0
		var at: Vector3 = world_position(from_tile, 0.3)
		if type_name == "fire-trap":
			_impact_burst(at, DEF_FLAME, 14, 1.1, true)
			_hit_flash(at + Vector3.UP * 0.4, DEF_FLAME)
		else:
			_impact_burst(at, Color(0.85, 0.86, 0.9), 6, 0.6)
			_impact_burst(at, DUST, 6, 0.9, true)
		return
	state["kick"] = 1.0
	if state.has("sentry") and is_instance_valid(state["sentry"]):
		var sentry: Node3D = state["sentry"]
		if aim.length() > 0.01:
			_def_face(state, sentry, atan2(aim.x, aim.z))
		var player: AnimationPlayer = state.get("player")
		if player != null and player.has_animation("attack"):
			player.play("attack", 0.08)
			state["sentry_attack"] = DEF_SENTRY_ATTACK


func _def_on_hit(tile: Vector2) -> void:
	var b: Dictionary = _def_at(tile)
	if b.is_empty():
		return
	var state: Dictionary = _def[int(b["id"])]
	state["shake"] = 1.0
	if _effect_budget_open():
		_impact_burst(world_position(tile, minf(1.2, float(state["top"]) * 0.5)), _def_chip(str(state["type"])), 6, 0.8)


func _def_chip(type_name: String) -> Color:
	if type_name == "rampart":
		return DEF_EARTH
	return DEF_STONE_CHIP if type_name in DEF_STONE else DEF_WOOD


# The model is hidden by the game the moment health reaches zero, so a copy topples in its place.
func _def_on_ruin(tile: Vector2) -> void:
	var b: Dictionary = _def_at(tile)
	if b.is_empty():
		return
	var state: Dictionary = _def[int(b["id"])]
	var model: Node3D = state["model"]
	_impact_burst(world_position(tile, 0.6), _def_chip(str(state["type"])), 12, 1.3, true)
	if not _effect_budget_open() or not is_instance_valid(model):
		return
	var fall: Node3D = model.duplicate() as Node3D
	add_child(fall)
	effect_nodes.append(fall)
	fall.global_transform = model.global_transform
	fall.visible = true
	var lean: Vector3 = state["lean_axis"]
	var start: Transform3D = fall.global_transform
	var tween: Tween = _effect_tween()
	tween.tween_method(_def_step_fall.bind(fall, start, lean, float(state["top"])), 0.0, 1.0, DEF_FALL_TIME) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(fall.queue_free)


func _def_step_fall(t: float, fall: Node3D, start: Transform3D, axis: Vector3, height: float) -> void:
	if not is_instance_valid(fall):
		return
	var tip: Basis = Basis(axis.normalized(), 0.55 * t)
	var squash: Basis = Basis.from_scale(Vector3(1.0 + 0.15 * t, 1.0 - 0.7 * t, 1.0 + 0.15 * t))
	fall.global_transform = Transform3D(tip * squash * start.basis, start.origin - Vector3.UP * height * 0.35 * t)


# ---------------------------------------------------------------- projectiles


# Arrows from a defense leave its top; ballistas and bastions fire their own shot; traps none.
func _launch_arrow(from_point: Vector3, to_point: Vector3, raider: bool) -> void:
	if not _def_on or raider:
		super(from_point, to_point, raider)
		return
	var b: Dictionary = _def_at(_def_tile(from_point))
	if b.is_empty():
		super(from_point, to_point, raider)
		return
	var state: Dictionary = _def[int(b["id"])]
	var muzzle: Vector3 = Vector3(from_point.x, _def_muzzle(state), from_point.z)
	match str(state["type"]):
		"trap", "fire-trap":
			return
		"ballista":
			_def_bolt(muzzle, to_point)
		"bastion":
			_def_cannon(muzzle, to_point)
		_:
			super(muzzle, to_point, raider)


func _muzzle_flash(event: Dictionary) -> void:
	if not _def_on or not event.has("from_x"):
		super(event)
		return
	var from_tile := Vector2(float(event["from_x"]), float(event["from_y"]))
	var b: Dictionary = {} if _raider_near(from_tile, 0.7) else _def_at(from_tile)
	if b.is_empty():
		super(event)
		return
	var state: Dictionary = _def[int(b["id"])]
	if str(state["type"]) in DEF_TRAPS or not _effect_budget_open():
		return
	var at: Vector3 = world_position(from_tile, _def_muzzle(state))
	if str(state["type"]) == "bastion":
		burst_pool.spawn(at, Color(0.55, 0.52, 0.5), 10, 1.4, true)
	burst_pool.spawn(at, ARROW_SPARK, MUZZLE_COUNT + 2, MUZZLE_SIZE, false)


func _def_tile(point: Vector3) -> Vector2:
	var local: Vector3 = point - world_position(Vector2.ZERO)
	return Vector2(local.x / TILE, local.z / TILE)


func _def_muzzle(state: Dictionary) -> float:
	match str(state["type"]):
		"watchfire":
			return 0.9
		"trap", "fire-trap":
			return 0.4
	return maxf(1.0, float(state["top"]) * 0.82)


func _def_bolt(from_point: Vector3, to_point: Vector3) -> void:
	if not _effect_budget_open():
		return
	var bolt := Node3D.new()
	bolt.position = from_point
	add_child(bolt)
	effect_nodes.append(bolt)
	_box(Vector3(0.09, 0.09, 0.95), Vector3.ZERO, ARROW_WOOD.darkened(0.2), bolt)
	_box(Vector3(0.16, 0.16, 0.2), Vector3(0, 0, -0.5), ARROW_STEEL, bolt)
	_box(Vector3(0.3, 0.03, 0.16), Vector3(0, 0, 0.4), Color(0.75, 0.7, 0.6), bolt)
	var distance: float = from_point.distance_to(to_point)
	var tween: Tween = _effect_tween()
	tween.tween_method(_step_arrow.bind(bolt, from_point, to_point, clampf(distance * 0.05, 0.1, 0.5)), 0.0, 1.0, clampf(distance * 0.045, 0.12, 0.32))
	tween.tween_callback(bolt.queue_free)
	tween.tween_callback(_impact_burst.bind(to_point, ARROW_SPARK, 10, 1.1))
	tween.tween_callback(_dust_puff.bind(to_point, 1.4))


func _def_cannon(from_point: Vector3, to_point: Vector3) -> void:
	if not _effect_budget_open():
		return
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	sphere.radial_segments = 10
	sphere.rings = 5
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = DEF_IRON
	material.metallic = 0.6
	material.roughness = 0.5
	ball.material_override = material
	ball.position = from_point
	add_child(ball)
	effect_nodes.append(ball)
	var distance: float = from_point.distance_to(to_point)
	var tween: Tween = _effect_tween()
	tween.tween_method(_step_arrow.bind(ball, from_point, to_point, clampf(0.8 + distance * 0.15, 0.8, 2.0)), 0.0, 1.0, clampf(distance * 0.08, 0.3, 0.55))
	tween.tween_callback(ball.queue_free)
	tween.tween_callback(_impact_burst.bind(to_point, Color(1.0, 0.6, 0.3), 12, 1.3))
	tween.tween_callback(_dust_puff.bind(to_point, 2.4))


# ---------------------------------------------------------------- per frame


func _update_actors(delta: float) -> void:
	super(delta)
	if not _def_on or _def.is_empty():
		return
	var step: float = 0.0 if sim.paused else delta
	_def_poll -= delta
	var poll: bool = _def_poll <= 0.0
	if poll:
		_def_poll = DEF_POLL
	for id: Variant in _def.keys():
		var state: Dictionary = _def[id]
		var pivot: Node3D = state["pivot"]
		if not is_instance_valid(pivot):
			continue
		if poll:
			_def_poll_state(int(id), state)
		var lean: float = float(state["lean"])
		var goal: float = float(state["lean_goal"])
		if not is_equal_approx(lean, goal):
			lean = move_toward(lean, goal, step * 0.08)
			state["lean"] = lean
		if state.has("lantern_core"):
			# The core is lit only while the lamp is, and breathes with the shared flicker.
			var halo: MeshInstance3D = state["glow"]
			var core: MeshInstance3D = state["lantern_core"]
			if is_instance_valid(halo) and is_instance_valid(core):
				core.visible = halo.visible
				if halo.visible:
					core.scale = Vector3(1.0, halo.scale.y * 1.6 - 0.6, 1.0)
		var kick: float = float(state["kick"])
		var shake: float = float(state["shake"])
		var snap: float = float(state["snap"])
		if state.has("sentry_attack") and float(state["sentry_attack"]) > 0.0:
			state["sentry_attack"] = float(state["sentry_attack"]) - step
			if float(state["sentry_attack"]) <= 0.0:
				var player: AnimationPlayer = state.get("player")
				if player != null and player.has_animation("idle"):
					player.play("idle", 0.2)
		if state.has("player") and state["player"] != null:
			(state["player"] as AnimationPlayer).speed_scale = 0.0 if sim.paused else 1.0
		if kick <= 0.0 and shake <= 0.0 and snap <= 0.0 and lean <= 0.0:
			if bool(state.get("moved", false)):
				pivot.transform = Transform3D.IDENTITY
				state["moved"] = false
			continue
		state["kick"] = maxf(0.0, kick - step / DEF_KICK_TIME)
		state["shake"] = maxf(0.0, shake - step / DEF_SHAKE_TIME)
		state["snap"] = maxf(0.0, snap - step / DEF_SNAP_TIME)
		pivot.transform = _def_pose(state, kick, shake, snap, lean)
		state["moved"] = true


func _def_pose(state: Dictionary, kick: float, shake: float, snap: float, lean: float) -> Transform3D:
	var basis := Basis()
	var origin := Vector3.ZERO
	if lean > 0.0:
		basis = Basis(state["lean_axis"], DEF_LEAN_MAX * lean) * basis
		origin.y -= DEF_SINK_MAX * lean
	if kick > 0.0:
		# Fast out, eased back: k peaks at the shot and settles.
		var k: float = kick * kick
		var aim: Vector3 = state["aim"]
		var heavy: bool = str(state["type"]) in ["ballista", "bastion"]
		basis = basis * Basis.from_scale(Vector3(1.0 + 0.025 * k, 1.0 - (0.05 if heavy else 0.035) * k, 1.0 + 0.025 * k))
		if aim.length() > 0.01:
			var tilt_axis: Vector3 = Vector3.UP.cross(aim).normalized()
			basis = Basis(tilt_axis, -(0.06 if heavy else 0.025) * k) * basis
			origin -= aim * (0.12 if heavy else 0.04) * k
	if shake > 0.0:
		var wobble: float = sin(shake * 38.0) * shake
		var axis: Vector3 = state["lean_axis"]
		basis = Basis(axis, 0.03 * wobble) * basis
		origin += Vector3(axis.z, 0.0, -axis.x) * 0.05 * wobble
	if snap > 0.0:
		# Spikes punch up past the plate, then sink back.
		var s: float = sin(PI * (1.0 - snap)) * (1.0 if snap > 0.5 else snap * 2.0)
		basis = basis * Basis.from_scale(Vector3(1.0 + 0.05 * s, 1.0 + 0.6 * s, 1.0 + 0.05 * s))
	return Transform3D(basis, origin)


func _def_poll_state(id: int, state: Dictionary) -> void:
	var b: Dictionary = sim.get_building(id)
	if b.is_empty():
		return
	var hp: float = float(b["hp"])
	var ratio: float = clampf(hp / maxf(1.0, float(b["max_hp"])), 0.0, 1.0)
	state["lean_goal"] = 0.0 if hp <= 0.0 or ratio >= 0.5 else (0.5 - ratio) * 2.0
	if hp <= 0.0:
		state["lean"] = 0.0
	var ruined: bool = hp <= 0.0
	if ruined != bool(state["ruined"]):
		state["ruined"] = ruined
		if state.has("arms") and is_instance_valid(state["arms"]):
			(state["arms"] as Node3D).visible = not ruined
		if state.has("sentry") and is_instance_valid(state["sentry"]):
			(state["sentry"] as Node3D).visible = not ruined
		(state["lights"] as Node3D).visible = not ruined
		if ruined:
			state["rubble"] = _def_rubble(state)
		elif state["rubble"] != null and is_instance_valid(state["rubble"]):
			(state["rubble"] as Node3D).queue_free()
			state["rubble"] = null
	if str(state["type"]) == "gate" and not ruined:
		var open: bool = bool(b.get("gate_open", true))
		if open != bool(state["gate_open"]):
			state["gate_open"] = open
			state["shake"] = 0.6
			var root_node: Node3D = (state["pivot"] as Node3D).get_parent()
			if root_node != null and _effect_budget_open():
				_impact_burst(root_node.global_position + Vector3.UP * 0.2, DUST, 8, 1.0, true)


# A low pile of chunks in the defense's own material, under the view root so it never leans.
func _def_rubble(state: Dictionary) -> Node3D:
	var root_node: Node3D = (state["pivot"] as Node3D).get_parent()
	if root_node == null:
		return null
	if _def_rubble_mesh == null:
		_def_rubble_mesh = BoxMesh.new()
		_def_rubble_mesh.size = Vector3.ONE
	var pile := Node3D.new()
	pile.name = "DefenseRubble"
	root_node.add_child(pile)
	var colour: Color = _def_chip(str(state["type"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(state["lean_axis"]))
	var chunks: int = 7 if str(state["type"]) in DEF_SHOOTERS else 5
	for i in chunks:
		var chunk := MeshInstance3D.new()
		chunk.mesh = _def_rubble_mesh
		chunk.material_override = _def_rubble_material(colour.darkened(0.12 * float(rng.randi_range(0, 2))))
		var size := Vector3(rng.randf_range(0.25, 0.55), rng.randf_range(0.12, 0.3), rng.randf_range(0.2, 0.45))
		if colour == DEF_WOOD and i % 2 == 0:
			size = Vector3(rng.randf_range(0.7, 1.1), 0.1, 0.12)   # broken stakes and planks
		chunk.scale = size
		chunk.position = Vector3(rng.randf_range(-0.55, 0.55), size.y * 0.4, rng.randf_range(-0.55, 0.55))
		chunk.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, TAU), rng.randf_range(-0.3, 0.3))
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pile.add_child(chunk)
	return pile


func _def_rubble_material(colour: Color) -> StandardMaterial3D:
	var key: String = colour.to_html(false)
	if not _def_rubble_mats.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.95
		_def_rubble_mats[key] = material
	return _def_rubble_mats[key]
