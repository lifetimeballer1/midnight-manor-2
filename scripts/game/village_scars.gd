extends "res://scripts/game/village_footfall.gd"
## Damage and ruin layer (visual only).
##
## Damaged buildings (hp below 60 percent but above zero) breathe dark grey smoke,
## thicker and more opaque as hp drops; below 30 percent a few orange embers join
## it. Building hp is polled about four times a second, and at most SCAR_SMOKE_MAX
## pooled CPUParticles3D emitters are alive at once, prioritising the lowest hp.
## When a building's hp falls from above zero to zero it gets a chunky debris burst
## and a lingering low dust cloud. The first poll (and any new sim object) only
## seeds the previous hp, so a loaded save never replays old destruction. Smoke and
## effects freeze while the simulation is paused. Decoration only: it never changes
## the simulation.

const SCAR_POLL_INTERVAL: float = 0.25
const SCAR_DAMAGED: float = 0.6
const SCAR_EMBER: float = 0.3
const SCAR_SMOKE_MAX: int = 8
const SCAR_SMOKE_HEIGHT: float = 2.2     # fallback emitter height when a building view is missing
const SCAR_SMOKE_LIFT: float = 0.2       # emitter sits this far above the building top
const SCAR_SMOKE_SIDE: float = 0.5      # emitter steps this far screen-right of the status label
const SCAR_SMOKE_COLOR: Color = Color(0.12, 0.12, 0.13)
const SCAR_DUST_SECONDS: float = 1.5
const SCAR_DUST_MAX: int = 6
const SCAR_DEBRIS_COLOR: Color = Color("6b5140")
const SCAR_EMBER_COLOR: Color = Color(1.0, 0.45, 0.12)
const SCAR_FADE_PAD: float = 0.2

var _scar_clock: float = 0.0
var _scar_sim: Variant = null            # sim instance last seeded; a new sim reseeds silently
var _scar_prev_hp: Dictionary = {}       # building id -> hp at the previous poll
var _scar_smoke: Dictionary = {}         # building id -> active smoke CPUParticles3D
var _scar_spare: Array = []              # idle pooled smoke emitters (hidden)
var _scar_fade: Array = []               # {"node", "left", "recycle"} emitters winding down
var _scar_paused: bool = false


func _process(delta: float) -> void:
	super(delta)
	var frozen: bool = bool(sim.paused)
	if frozen != _scar_paused:
		_scar_paused = frozen
		_scar_apply_speed()
	if not frozen:
		_scar_age(delta)
	_scar_clock -= delta
	if _scar_clock > 0.0:
		return
	_scar_clock = SCAR_POLL_INTERVAL
	_scar_poll()


func _scar_poll() -> void:
	if sim != _scar_sim:
		_scar_reset()
		_scar_sim = sim
	var alive: Dictionary = {}
	var damaged: Array = []
	for b: Dictionary in sim.buildings:
		var id: int = int(b["id"])
		var hp: float = float(b["hp"])
		var max_hp: float = maxf(float(b["max_hp"]), 1.0)
		alive[id] = true
		var previous: float = float(_scar_prev_hp.get(id, hp))
		_scar_prev_hp[id] = hp
		if previous > 0.0 and hp <= 0.0:
			_scar_destroyed(b)
		if hp > 0.0 and hp / max_hp < SCAR_DAMAGED:
			damaged.append({"ratio": hp / max_hp, "b": b})
	for id in _scar_prev_hp.keys():
		if not alive.has(id):
			_scar_prev_hp.erase(id)

	damaged.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["ratio"]) < float(y["ratio"]))
	var wanted: Dictionary = {}
	for item: Dictionary in damaged.slice(0, SCAR_SMOKE_MAX):
		var b: Dictionary = item["b"]
		var id: int = int(b["id"])
		wanted[id] = true
		var node: CPUParticles3D = _scar_smoke.get(id, null)
		if node == null:
			node = _scar_acquire()
			_scar_smoke[id] = node
		_scar_tune(node, b, float(item["ratio"]))

	for id in _scar_smoke.keys():
		if not wanted.has(id):
			_scar_release(_scar_smoke[id])
			_scar_smoke.erase(id)


func _scar_tune(node: CPUParticles3D, b: Dictionary, ratio: float) -> void:
	var severity: float = clampf(1.0 - ratio / SCAR_DAMAGED, 0.0, 1.0)
	var amount: int = 10 + int(round(10.0 * severity))
	if node.amount != amount:
		node.amount = amount
	node.position = _scar_smoke_origin(b)
	var mesh := node.mesh as SphereMesh
	var material := mesh.material as StandardMaterial3D
	material.albedo_color = Color(SCAR_SMOKE_COLOR, 0.6 + 0.3 * severity)
	var want_embers: bool = ratio < SCAR_EMBER
	var embers: CPUParticles3D = node.get_node_or_null("ScarEmbers")
	if want_embers and embers == null:
		embers = _scar_make_embers()
		node.add_child(embers)
		_scar_set_speed(embers, _scar_speed())
	if embers != null:
		embers.emitting = want_embers


func _scar_smoke_origin(b: Dictionary) -> Vector3:
	# The building's Label3D sits half a unit above the model top (village_game.gd), so
	# its height is the roof line. Emit from just above it or the smoke hides inside the roof.
	var view: Dictionary = building_views.get(int(b["id"]), {})
	if view.has("label") and is_instance_valid(view["label"]):
		var label: Label3D = view["label"]
		# Step screen-right so the plume rises beside the status text, not through it.
		var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
		var local: Vector3 = to_local(label.global_position + right * SCAR_SMOKE_SIDE)
		return Vector3(local.x, local.y - 0.5 + SCAR_SMOKE_LIFT, local.z)
	return world_position(sim.center(b), SCAR_SMOKE_HEIGHT)


func _scar_acquire() -> CPUParticles3D:
	var node: CPUParticles3D = _scar_spare.pop_back() if not _scar_spare.is_empty() else _scar_make_smoke()
	node.visible = true
	node.emitting = true
	_scar_set_speed(node, _scar_speed())
	return node


func _scar_release(node: CPUParticles3D) -> void:
	node.emitting = false
	var embers: CPUParticles3D = node.get_node_or_null("ScarEmbers")
	if embers != null:
		embers.emitting = false
	_scar_fade.append({"node": node, "left": node.lifetime + SCAR_FADE_PAD, "recycle": true})


func _scar_destroyed(b: Dictionary) -> void:
	var center: Vector2 = sim.center(b)
	var debris := _scar_make_debris()
	add_child(debris)
	debris.position = world_position(center, 0.8)
	debris.emitting = true
	_scar_set_speed(debris, _scar_speed())
	_scar_fade.append({"node": debris, "left": debris.lifetime + SCAR_FADE_PAD, "recycle": false})
	if _scar_one_shot_count() < SCAR_DUST_MAX:
		var dust := _scar_make_dust()
		add_child(dust)
		dust.position = world_position(center, 0.3)
		dust.emitting = true
		_scar_set_speed(dust, _scar_speed())
		_scar_fade.append({"node": dust, "left": SCAR_DUST_SECONDS, "recycle": false})


func _scar_age(delta: float) -> void:
	var i: int = _scar_fade.size() - 1
	while i >= 0:
		var entry: Dictionary = _scar_fade[i]
		entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) <= 0.0:
			_scar_fade.remove_at(i)
			var node: Node = entry["node"]
			if not is_instance_valid(node):
				pass
			elif bool(entry["recycle"]):
				node.visible = false
				_scar_spare.append(node)
			else:
				node.queue_free()
		i -= 1


func _scar_one_shot_count() -> int:
	var count: int = 0
	for entry: Dictionary in _scar_fade:
		if not bool(entry["recycle"]):
			count += 1
	return count


func _scar_apply_speed() -> void:
	var rate: float = _scar_speed()
	for node: CPUParticles3D in _scar_smoke.values():
		_scar_set_speed(node, rate)
	for entry: Dictionary in _scar_fade:
		var node: CPUParticles3D = entry["node"]
		if is_instance_valid(node):
			_scar_set_speed(node, rate)


func _scar_set_speed(node: CPUParticles3D, rate: float) -> void:
	node.speed_scale = rate
	var embers: CPUParticles3D = node.get_node_or_null("ScarEmbers")
	if embers != null:
		embers.speed_scale = rate


func _scar_speed() -> float:
	return 0.0 if sim.paused else 1.0


func _scar_reset() -> void:
	for node: Node in _scar_smoke.values():
		_scar_free(node)
	for node: Node in _scar_spare:
		_scar_free(node)
	for entry: Dictionary in _scar_fade:
		_scar_free(entry["node"])
	_scar_smoke.clear()
	_scar_spare.clear()
	_scar_fade.clear()
	_scar_prev_hp.clear()


func _scar_free(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _scar_make_smoke() -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.name = "ScarSmoke"
	smoke.amount = 12
	smoke.lifetime = 3.6
	smoke.direction = Vector3.UP
	smoke.spread = 22
	smoke.gravity = Vector3(0.05, 0.12, 0)
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.5
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.4
	# Puffs start at 0.6 world units across and grow to 1.2 over their lifetime.
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 1.15
	var growth := Curve.new()
	growth.max_value = 2.0
	growth.clear_points()
	growth.add_point(Vector2(0.0, 1.0))
	growth.add_point(Vector2(1.0, 2.0))
	smoke.scale_amount_curve = growth
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Draw before other transparents so the building's status label stays readable.
	material.render_priority = -1
	mesh.material = material
	smoke.mesh = mesh
	add_child(smoke)
	return smoke


func _scar_make_embers() -> CPUParticles3D:
	var embers := CPUParticles3D.new()
	embers.name = "ScarEmbers"
	embers.amount = 4
	embers.lifetime = 1.1
	embers.direction = Vector3.UP
	embers.spread = 35
	embers.gravity = Vector3(0, 0.5, 0)
	embers.initial_velocity_min = 0.4
	embers.initial_velocity_max = 0.9
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(0.25, 0.1, 0.25)
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 4
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = SCAR_EMBER_COLOR
	mesh.material = material
	embers.mesh = mesh
	return embers


func _scar_make_debris() -> CPUParticles3D:
	var debris := CPUParticles3D.new()
	debris.name = "ScarDebris"
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = 14
	debris.lifetime = 0.9
	debris.direction = Vector3.UP
	debris.spread = 55
	debris.gravity = Vector3(0, -9.0, 0)
	debris.initial_velocity_min = 2.0
	debris.initial_velocity_max = 4.2
	debris.angular_velocity_min = -360.0
	debris.angular_velocity_max = 360.0
	debris.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	debris.emission_box_extents = Vector3(0.6, 0.3, 0.6)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.12, 0.16)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = SCAR_DEBRIS_COLOR
	mesh.material = material
	debris.mesh = mesh
	return debris


func _scar_make_dust() -> CPUParticles3D:
	var dust := CPUParticles3D.new()
	dust.name = "ScarDust"
	dust.one_shot = true
	dust.explosiveness = 0.0
	dust.amount = 10
	dust.lifetime = SCAR_DUST_SECONDS * 0.5
	dust.direction = Vector3.UP
	dust.spread = 80
	dust.gravity = Vector3(0, 0.15, 0)
	dust.initial_velocity_min = 0.5
	dust.initial_velocity_max = 1.1
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.3
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.8
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.7))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	dust.color_ramp = fade
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.46, 0.44, 0.42)
	mesh.material = material
	dust.mesh = mesh
	return dust
