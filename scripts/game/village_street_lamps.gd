extends "res://scripts/game/village_celebrations.gd"

# Street lamps: paved stone roads get iron lamp posts with a soft warm halo.
# The halo fades in through dusk and out at dawn, on the same day cycle as the
# rest of the village. The lamps are glowing shapes rather than real lights, so
# they stay cheap on phones. Decoration only: it reads the road network and
# never changes it.
#
# Lamplighter: at dusk one idle villager's lantern walks a nearest-neighbour
# route through the lamps and each lamp swells up as it is reached. At dawn the
# lamps go out in a stagger. If no villager is idle, or the chosen one is
# reassigned or removed, the remaining lamps light themselves with a short
# stagger instead. The lantern is a view-only token; villager positions and save
# data are never touched.

const STREET_CHECK: float = 0.5
const STREET_LIMIT: int = 24
const STREET_IRON := Color("2c2620")
const STREET_CAP := Color("1d1a17")
const STREET_FLAME := Color("ffb060")
const LAMP_GLOW_MAX: float = 0.96     # full-night lantern emission (was 2.4; about 40%)
const LAMP_HALO_ALPHA: float = 0.45   # warm halo strength at full night (was 0.65)
const LAMP_WALK_SPEED: float = 2.5   # tiles per second for the lantern
const LAMP_FADE_IN: float = 0.6
const LAMP_FADE_OUT: float = 0.8
const LAMP_STAGGER: float = 0.12
const LANTERN_HEIGHT: float = 0.6

var _street_clock: float = 0.0
var _street_sim: Object = null
var _street_revision: int = -1
var _street_lamps: Array[Dictionary] = []
var _street_halo_tex: Texture2D = null
var _street_dark: bool = false
var _lamplighter_id: int = -1
var _lamplighter_tween: Tween = null
var _lamplighter_token: MeshInstance3D = null


func _process(delta: float) -> void:
	super(delta)
	if not started or is_instance_valid(battle_view):
		return
	_street_clock += delta
	if _street_clock < STREET_CHECK:
		return
	_street_clock = 0.0
	_sync_street_lamps()


func _exit_tree() -> void:
	super()
	_cancel_lamplighter()
	for lamp: Dictionary in _street_lamps:
		_kill_lamp_tween(lamp)


func _sync_street_lamps() -> void:
	if sim != _street_sim:
		_street_sim = sim
		_street_revision = -1
		_clear_street_lamps()
	if sim.living.revision != _street_revision:
		_street_revision = sim.living.revision
		_rebuild_street_lamps()
	# 1.0 at full night, 0.0 in full day, following the dusk and dawn blends.
	var strength: float = _street_strength()
	var dark: bool = strength > 0.01
	if dark and not _street_dark:
		_street_dark = true
		_begin_lamplighter()
	elif not dark and _street_dark:
		_street_dark = false
		_douse_street_lamps()
	elif dark:
		if _lamplighter_id >= 0 and not _lamplighter_still_idle():
			_cancel_lamplighter()
		if _lamplighter_id < 0:
			_light_unlit_street_lamps()
	for lamp: Dictionary in _street_lamps:
		_glow_street_lamp(lamp, strength * float(lamp["level"]))


func _street_strength() -> float:
	return clampf(1.0 - float(day_blend), 0.0, 1.0)


# Lamps stand every third paved tile along a road, so they space out evenly on
# straight runs and never crowd a junction.
func _rebuild_street_lamps() -> void:
	_clear_street_lamps()
	for id: Variant in sim.living.cells.keys():
		if _street_lamps.size() >= STREET_LIMIT:
			break
		var parts: PackedStringArray = str(id).split(",")
		if parts.size() != 2:
			continue
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		if (tile.x + tile.y) % 3 != 0 or not _is_paved(tile):
			continue
		_street_lamps.append(_make_street_lamp(tile))


func _is_paved(tile: Vector2i) -> bool:
	var cell: Dictionary = sim.living.cells.get("%d,%d" % [tile.x, tile.y], {})
	return bool(cell.get("stone", false))


func _make_street_lamp(tile: Vector2i) -> Dictionary:
	# Stand the lamp just inside the road's edge, so it never sits in the path.
	var runs_east_west: bool = _is_paved(tile + Vector2i(1, 0)) or _is_paved(tile + Vector2i(-1, 0))
	var edge: Vector2 = Vector2(0.5, 0.14) if runs_east_west else Vector2(0.14, 0.5)
	var ground: Vector3 = world_position(Vector2(tile) + edge, 0.03)

	# Dark iron post, a squat dark cap over the lantern, and a small amber lantern core.
	var post_node: MeshInstance3D = _lamp_part(BoxMesh.new(), ground + Vector3(0, 0.55, 0), STREET_IRON, Vector3(0.07, 1.1, 0.07))
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.02
	cap_mesh.bottom_radius = 0.13
	cap_mesh.height = 0.08
	cap_mesh.radial_segments = 4
	var cap_node: MeshInstance3D = _lamp_part(cap_mesh, ground + Vector3(0, 1.33, 0), STREET_CAP)
	cap_node.rotation.y = PI * 0.25

	var orb_node: MeshInstance3D = _lamp_part(BoxMesh.new(), ground + Vector3(0, 1.2, 0), STREET_FLAME, Vector3(0.14, 0.18, 0.14))
	var orb_material: StandardMaterial3D = orb_node.material_override
	orb_material.emission_enabled = true
	orb_material.emission = STREET_FLAME
	orb_material.emission_energy_multiplier = 0.0

	var halo_node := MeshInstance3D.new()
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2(1.2, 1.2)
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.disable_receive_shadows = true
	halo_material.albedo_texture = _street_halo_texture()
	halo_material.albedo_color = Color(1.0, 0.66, 0.32, 0.0)
	halo_quad.material = halo_material
	halo_node.mesh = halo_quad
	halo_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo_node.position = ground + Vector3(0, 1.2, 0)
	add_child(halo_node)

	return {"post": post_node, "cap": cap_node, "orb": orb_node, "halo": halo_node, "orb_material": orb_material, "halo_material": halo_material,
		"tile": Vector2(tile) + edge, "foot": ground + Vector3(0, LANTERN_HEIGHT, 0), "level": 0.0, "lit": false, "tween": null}


# One unshadowed iron or lantern piece of a street lamp. A BoxMesh takes its size from size.
func _lamp_part(mesh: PrimitiveMesh, at: Vector3, color: Color, size: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	if mesh is BoxMesh and size != Vector3.ZERO:
		(mesh as BoxMesh).size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _glow_street_lamp(lamp: Dictionary, strength: float) -> void:
	var orb_material: StandardMaterial3D = lamp["orb_material"]
	orb_material.emission_energy_multiplier = LAMP_GLOW_MAX * strength
	var halo_material: StandardMaterial3D = lamp["halo_material"]
	halo_material.albedo_color.a = LAMP_HALO_ALPHA * strength
	var halo_node: MeshInstance3D = lamp["halo"]
	halo_node.visible = strength > 0.02


func _clear_street_lamps() -> void:
	_cancel_lamplighter()
	for lamp: Dictionary in _street_lamps:
		_kill_lamp_tween(lamp)
		for part: String in ["post", "cap", "orb", "halo"]:
			if is_instance_valid(lamp[part]):
				lamp[part].queue_free()
	_street_lamps.clear()


func _street_halo_texture() -> Texture2D:
	if _street_halo_tex == null:
		_street_halo_tex = UI.soft_disc_texture()
	return _street_halo_tex


# --- Lamplighter ------------------------------------------------------------

func _begin_lamplighter() -> void:
	_cancel_lamplighter()
	var walker: Dictionary = _idle_villager()
	if walker.is_empty():
		_light_unlit_street_lamps()
		return
	var route: Array = _lamp_route(Vector2(float(walker["x"]), float(walker["y"])))
	if route.is_empty():
		return
	_lamplighter_id = int(walker["id"])
	_lamplighter_token = _make_lantern(world_position(Vector2(float(walker["x"]), float(walker["y"])), LANTERN_HEIGHT))
	_lamplighter_tween = create_tween()
	var here: Vector3 = _lamplighter_token.position
	for lamp: Dictionary in route:
		var foot: Vector3 = lamp["foot"]
		var duration: float = maxf(0.2, here.distance_to(foot) / (LAMP_WALK_SPEED * maxf(0.01, _tile_scale())))
		_lamplighter_tween.tween_property(_lamplighter_token, "position", foot, duration)
		_lamplighter_tween.tween_callback(_light_reached_lamp.bind(lamp))
		here = foot
	_lamplighter_tween.tween_callback(_finish_lamplighter)


# World units per tile, so the walk speed is in tiles however the map is scaled.
func _tile_scale() -> float:
	return world_position(Vector2(1, 0)).distance_to(world_position(Vector2.ZERO))


func _idle_villager() -> Dictionary:
	for unit: Dictionary in sim.units:
		if str(unit.get("phase", "")) == "idle" and _is_villager(unit):
			return unit
	return {}


func _is_villager(unit: Dictionary) -> bool:
	var spec: Dictionary = sim.troop_specs.get(str(unit.get("type", "")), {})
	return str(spec.get("role", "")) != "" and str(spec.get("role", "")) != "combat"


func _find_unit(id: int) -> Dictionary:
	for unit: Dictionary in sim.units:
		if int(unit.get("id", -1)) == id:
			return unit
	return {}


func _lamplighter_still_idle() -> bool:
	var unit: Dictionary = _find_unit(_lamplighter_id)
	return not unit.is_empty() and str(unit.get("phase", "")) == "idle"


# Nearest-neighbour order from the villager's position through the unlit lamps.
func _lamp_route(start: Vector2) -> Array:
	var pending: Array = []
	for lamp: Dictionary in _street_lamps:
		if not bool(lamp["lit"]):
			pending.append(lamp)
	var route: Array = []
	var here: Vector2 = start
	while not pending.is_empty():
		var best_index: int = 0
		var best_distance: float = INF
		for i in pending.size():
			var tile: Vector2 = pending[i]["tile"]
			var distance: float = here.distance_squared_to(tile)
			if distance < best_distance:
				best_distance = distance
				best_index = i
		var next: Dictionary = pending.pop_at(best_index)
		route.append(next)
		here = next["tile"]
	return route


func _make_lantern(at: Vector3) -> MeshInstance3D:
	var token := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	token.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = STREET_FLAME
	material.emission_enabled = true
	material.emission = STREET_FLAME
	material.emission_energy_multiplier = 2.0
	token.material_override = material
	token.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	token.position = at
	add_child(token)
	return token


func _light_reached_lamp(lamp: Dictionary) -> void:
	_fade_street_lamp(lamp, 1.0, 0.0, LAMP_FADE_IN)


# Lamps that nobody walks to light themselves in order, a short stagger apart.
func _light_unlit_street_lamps() -> void:
	var index: int = 0
	for lamp: Dictionary in _street_lamps:
		if bool(lamp["lit"]):
			continue
		_fade_street_lamp(lamp, 1.0, index * LAMP_STAGGER, LAMP_FADE_IN)
		index += 1


func _douse_street_lamps() -> void:
	_cancel_lamplighter()
	var index: int = 0
	for lamp: Dictionary in _street_lamps:
		if not bool(lamp["lit"]) and float(lamp["level"]) <= 0.0:
			continue
		_fade_street_lamp(lamp, 0.0, index * LAMP_STAGGER, LAMP_FADE_OUT)
		index += 1


func _finish_lamplighter() -> void:
	if is_instance_valid(_lamplighter_token):
		_lamplighter_token.queue_free()
	_lamplighter_token = null
	_lamplighter_tween = null
	_lamplighter_id = -1


# Stops the walk and removes the lantern. Lamp states are left as they are.
func _cancel_lamplighter() -> void:
	if _lamplighter_tween != null and _lamplighter_tween.is_valid():
		_lamplighter_tween.kill()
	_lamplighter_tween = null
	if is_instance_valid(_lamplighter_token):
		_lamplighter_token.queue_free()
	_lamplighter_token = null
	_lamplighter_id = -1


func _fade_street_lamp(lamp: Dictionary, target: float, delay: float, duration: float) -> void:
	lamp["lit"] = target > 0.5
	_kill_lamp_tween(lamp)
	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(_set_street_lamp_level.bind(lamp), float(lamp["level"]), target, duration)
	lamp["tween"] = tween


func _set_street_lamp_level(value: float, lamp: Dictionary) -> void:
	lamp["level"] = value
	_glow_street_lamp(lamp, _street_strength() * value)


func _kill_lamp_tween(lamp: Dictionary) -> void:
	var tween: Tween = lamp.get("tween")
	if tween != null and tween.is_valid():
		tween.kill()
	lamp["tween"] = null
