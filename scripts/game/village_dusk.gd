extends "res://scripts/game/village_street_lamps.gd"

# Smooth dusk: the whole sky changes gradually instead of snapping at the
# midpoint of the night. The building lamps, their glow, and the lit windows
# fade in through dusk and out at dawn. The stars, moon, fireflies and mist
# fade in with the dark, while the day motes and cloud shadows fade out. The
# game's own flicker and six-lamp budget still decide which lamps are lit; this
# only sets how bright each thing is at each point in the day cycle. Decoration
# only: it never changes the simulation.

const DUSK_PANE_ALPHA: float = 0.85
const DUSK_GLOW_ALPHA: float = 0.5

var _night_lit: bool = false
var _sky_base: Dictionary = {}   # node or material -> colour captured before its first fade


func _process(delta: float) -> void:
	super(delta)
	if not started or is_instance_valid(battle_view):
		return
	var night_s: float = _dusk_strength()
	_fade_sky(night_s, _day_strength())
	if night_s <= 0.01:
		if _night_lit:
			_night_lit = false
			_hide_night_lights()
		return
	_night_lit = true
	if not night:
		# The game only flickers its lamps at night, so keep them burning through the ramp.
		_flicker_lamps()
	_fade_night_lights(night_s)


# 0.0 in full day, 1.0 in full night, easing through dusk and dawn.
func _dusk_strength() -> float:
	return clampf(1.0 - float(day_blend), 0.0, 1.0)


# 1.0 in full day, 0.0 in full night, easing through dawn and dusk.
func _day_strength() -> float:
	return clampf(float(day_blend), 0.0, 1.0)


# Runs every frame after the base game has set its own visibility, so the sky's
# final state each frame is the faded one.
func _fade_sky(night_s: float, day_s: float) -> void:
	var rain_gate: float = 1.0 if rain_level > 0.35 else 0.0
	var mist_s: float = maxf(night_s, rain_gate)
	if is_instance_valid(stars):
		stars.visible = night_s > 0.01
		_tint_material(stars.material_override as StandardMaterial3D, night_s)
	if is_instance_valid(moon):
		moon.visible = night_s > 0.01
		_tint_material(_quad_material(moon), night_s)
		if moon.has_meta("halo") and is_instance_valid(moon.get_meta("halo")):
			var halo_node: MeshInstance3D = moon.get_meta("halo")
			halo_node.visible = night_s > 0.01
			_tint_material(_quad_material(halo_node), night_s)
	# Battery saver hides these in the base layer; the dusk fade only scales
	# them, so honour the base decision instead of re-showing them every frame.
	if is_instance_valid(fireflies):
		fireflies.visible = night_s > 0.01 and not battery_saver
		_tint_particles(fireflies, night_s)
	if is_instance_valid(mist):
		mist.visible = mist_s > 0.01 and not battery_saver
		_tint_particles(mist, mist_s)
	if is_instance_valid(motes):
		motes.visible = day_s > 0.01
		_tint_particles(motes, day_s)
	for shade in clouds:
		if is_instance_valid(shade):
			var shade_node: MeshInstance3D = shade
			shade_node.visible = day_s > 0.01
			_tint_material(_quad_material(shade_node), day_s)


# The material behind a flat sky or window piece, if it has one.
func _quad_material(node: MeshInstance3D) -> StandardMaterial3D:
	var quad: QuadMesh = node.mesh as QuadMesh
	if quad == null:
		return null
	return quad.material as StandardMaterial3D


# Scale a material's colour alpha by factor, relative to its original value.
func _tint_material(material: StandardMaterial3D, factor: float) -> void:
	if material == null:
		return
	var original: Color = _sky_base_color(material, material.albedo_color)
	var wanted := Color(original.r, original.g, original.b, original.a * factor)
	if material.albedo_color != wanted:
		material.albedo_color = wanted


# Scale a particle system's colour alpha by factor, relative to its original value.
func _tint_particles(node: CPUParticles3D, factor: float) -> void:
	var original: Color = _sky_base_color(node, node.color)
	var wanted := Color(original.r, original.g, original.b, original.a * factor)
	if node.color != wanted:
		node.color = wanted


# The colour each sky element had before this add-on touched it, so every fade
# is relative to the game's own look.
func _sky_base_color(key: Object, current: Color) -> Color:
	if not _sky_base.has(key):
		_sky_base[key] = current
	return _sky_base[key]


# Same six-nearest budget as the base game, but lamps may light as soon as the
# dusk ramp begins rather than waiting for the midpoint of the night.
func _update_light_pool() -> void:
	var lit: bool = _dusk_strength() > 0.01
	var scored: Array = []
	for view: Dictionary in building_views.values():
		var lamp: OmniLight3D = view.get("lamp")
		var root_node: Node3D = view.get("root")
		if not is_instance_valid(lamp) or not is_instance_valid(root_node):
			continue
		if not lit:
			lamp.visible = false
			var day_glow: MeshInstance3D = view.get("glow")
			if is_instance_valid(day_glow):
				day_glow.visible = false
			continue
		scored.append([target.distance_squared_to(root_node.global_position), lamp, view.get("glow")])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	for i in scored.size():
		var on: bool = i < 6
		(scored[i][1] as OmniLight3D).visible = on
		var pool_glow: MeshInstance3D = scored[i][2]
		if is_instance_valid(pool_glow):
			pool_glow.visible = on


# The game's own flicker, scaled by the dusk ramp so the lamps brighten and dim
# with the sky rather than snapping to full strength.
func _flicker_lamps() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var raid: bool = sim.raid_active or sim.raid_warning
	var alarm: float = 1.3 if raid else 1.0
	var tempo: float = 11.0 if raid else 6.3
	var strength: float = _dusk_strength()
	for id in building_views:
		var lamp: OmniLight3D = building_views[id].get("lamp")
		if is_instance_valid(lamp) and lamp.visible:
			var phase: float = float(id) * 1.7
			lamp.light_energy = 1.45 * alarm * strength * (0.92 + 0.05 * sin(t * tempo + phase) + 0.03 * sin(t * 13.1 + phase * 2.3))
			var flicker_glow: MeshInstance3D = building_views[id].get("glow")
			if is_instance_valid(flicker_glow) and flicker_glow.visible:
				flicker_glow.scale = Vector3.ONE * (1.0 + 0.06 * sin(t * 6.3 + phase))


func _fade_night_lights(strength: float) -> void:
	for view: Dictionary in building_views.values():
		var glow_node: MeshInstance3D = view.get("glow")
		if is_instance_valid(glow_node):
			_set_quad_alpha(glow_node, DUSK_GLOW_ALPHA * strength)
		var panes: Array = view.get("windows", [])
		for pane: MeshInstance3D in panes:
			if is_instance_valid(pane):
				if not pane.visible:
					pane.visible = true
				_set_quad_alpha(pane, DUSK_PANE_ALPHA * strength)


func _hide_night_lights() -> void:
	for view: Dictionary in building_views.values():
		var lamp: OmniLight3D = view.get("lamp")
		if is_instance_valid(lamp):
			lamp.visible = false
		var glow_node: MeshInstance3D = view.get("glow")
		if is_instance_valid(glow_node):
			glow_node.visible = false
		var panes: Array = view.get("windows", [])
		for pane: MeshInstance3D in panes:
			if is_instance_valid(pane):
				pane.visible = false


func _set_quad_alpha(node: MeshInstance3D, alpha: float) -> void:
	var material: StandardMaterial3D = _quad_material(node)
	if material == null:
		return
	var current: Color = material.albedo_color
	# Steady night/dusk leaves every alpha unchanged, so skip the write.
	if is_equal_approx(current.a, alpha):
		return
	material.albedo_color = Color(current.r, current.g, current.b, alpha)
