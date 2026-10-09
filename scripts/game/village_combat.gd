extends "res://scripts/game/village_roads.gd"

# Combat looks, layered over the game's own combat handling. Arrows arc through the
# air and turn to face their flight, and raider arrows are dark and red-tipped. A hit
# throws a bright flash, a struck raider flinches, and falls and collapses leave a dust
# cloud. Fallen raiders and fallen units play their death pose and sink into the ground
# instead of vanishing, and damaged raiders show a small health bar. Damage numbers,
# banners and the rest of the game's event handling are untouched: this layer reads
# events before the game consumes them, and takes the shot events over for the arrows.
# Effects still share the decoration cap.

const BAR_HEIGHT: float = 2.4
const BAR_WIDTH: float = 0.9
const SINK_TIME: float = 1.1
const SINK_DEPTH: float = 1.0
const ARROW_WOOD: Color = Color(0.45, 0.31, 0.18)
const ARROW_STEEL: Color = Color(0.8, 0.82, 0.86)
const ARROW_SPARK: Color = Color(1.0, 0.82, 0.45)
const RAIDER_WOOD: Color = Color(0.3, 0.12, 0.1)
const RAIDER_IRON: Color = Color(0.14, 0.13, 0.15)
const RAIDER_SPARK: Color = Color(1.0, 0.36, 0.22)
const DUST: Color = Color(0.66, 0.6, 0.5)

var _enemy_max_hp: Dictionary = {}
var _enemy_bars: Dictionary = {}    # enemy id -> {"root": Node3D, "fill": MeshInstance3D}
var _dying: Array = []              # fallen figures sinking away
var _pulse_base: Dictionary = {}    # model instance id -> scale to settle back to after a flinch

# Raid readability: a blood-red screen-edge veil that tolls with the horn, approach
# arrows at the screen edge, and a short camera jolt when a raider breaks something.
const TOLL_PERIOD: float = 1.2
const VEIL_RATE: float = 1.6          # veil strength change per second (fade in and out)
const VEIL_SHADER: String = """
shader_type canvas_item;
uniform vec4 blood : source_color = vec4(0.46, 0.04, 0.07, 1.0);
uniform float strength = 0.0;
void fragment() {
	float edge = smoothstep(0.3, 0.72, length((UV - vec2(0.5)) * vec2(1.0, 1.15)));
	COLOR = vec4(blood.rgb, edge * strength * 0.6);
}
"""
const ARROW_MAX: int = 4
const ARROW_MARGIN: float = 34.0
const ARROW_BRASS: Color = Color(0.85, 0.66, 0.32)
const ARROW_BLOOD: Color = Color(0.72, 0.1, 0.12)
const MAP_WIDTH: float = 20.0
const MAP_HEIGHT: float = 16.0
const SIDE_ANCHORS: Array[Vector2] = [Vector2(0.5, 8.0), Vector2(19.5, 8.0), Vector2(10.0, 0.5), Vector2(10.0, 15.5)]
const SHAKE_TIME: float = 0.15
const SHAKE_CAP: float = 1.0          # stacked breaks add up to this much jolt, no further
const SHAKE_FRACTION: float = 0.012   # jolt amplitude as a fraction of the camera's size
const BREAK_JOLT: float = 1.0

var _raid_layer: CanvasLayer = null
var _veil: ColorRect = null
var _veil_material: ShaderMaterial = null
var _veil_level: float = 0.0
var _toll_clock: float = 0.0
var _arrows: Array[Polygon2D] = []
var _shake_level: float = 0.0
var _shake_clock: float = 0.0


func _process(delta: float) -> void:
	if started and not is_instance_valid(battle_view):
		_read_combat_events()
		_stash_fallen()
	super(delta)
	_update_raid_read(0.0 if sim.paused else delta)
	if not started or is_instance_valid(battle_view):
		return
	_update_enemy_bars()
	_update_dying(0.0 if sim.paused else delta)


# Reads this frame's events before the game consumes them. Shots become arcing arrows
# and leave the list, so the game does not also draw its straight projectile. Hits,
# falls and collapses add their visuals alongside the game's own.
func _read_combat_events() -> void:
	var kept: Array = []
	for event: Dictionary in sim.events:
		var kind: String = str(event.get("kind", ""))
		if kind == "shot":
			if _effect_budget_open():
				var from_tile := Vector2(float(event["from_x"]), float(event["from_y"]))
				var from_point: Vector3 = world_position(from_tile, 1.8)
				var to_point: Vector3 = world_position(Vector2(float(event["x"]), float(event["y"])), 1.0)
				_launch_arrow(from_point, to_point, _raider_near(from_tile, 0.7))
			continue
		if kind == "hit":
			var tile := Vector2(float(event["x"]), float(event["y"]))
			var friendly: bool = bool(event.get("friendly", false))
			_hit_flash(world_position(tile, 1.2), Color(1.0, 0.5, 0.42) if friendly else Color(1.0, 0.86, 0.5))
			if not friendly:
				_flinch_raider(tile)
		elif kind == "fall":
			_dust_puff(world_position(Vector2(float(event["x"]), float(event["y"])), 0.6), 1.8)
		elif kind == "destroyed":
			_dust_puff(world_position(Vector2(float(event["x"]), float(event["y"])), 1.0), 3.2)
			if sim.raid_active:
				_shake_level = minf(_shake_level + BREAK_JOLT, SHAKE_CAP)
		kept.append(event)
	sim.events.assign(kept)


# Takes fallen raiders, and fallen units, out of the actor list before the game's own
# actor update can free them, so they can play their death pose and sink. Units that
# simply leave the list (going indoors, say) are left for the game to clear as before.
func _stash_fallen() -> void:
	var present: Dictionary = {}
	for u: Dictionary in sim.enemies:
		_note_actor(u, true, present)
	for u: Dictionary in sim.units:
		_note_actor(u, false, present)
	for id in actors.keys():
		if present.has(id):
			continue
		var gone: Dictionary = actors[id]
		if bool(gone.get("enemy", false)) or float(gone.get("hp", 1.0)) <= 0.0:
			actors.erase(id)
			_start_sinking(gone)


# Remembers, for each live actor, whether it is a raider and how much health it has.
func _note_actor(u: Dictionary, enemy: bool, present: Dictionary) -> void:
	var id: int = int(u["id"])
	present[id] = true
	if actors.has(id):
		var record: Dictionary = actors[id]
		record["enemy"] = enemy
		record["hp"] = float(u["hp"])


# A fallen figure plays its death pose once, then sinks into the ground and shrinks.
func _start_sinking(gone: Dictionary) -> void:
	var model: Node3D = gone.get("model")
	if not is_instance_valid(model):
		return
	var player: AnimationPlayer = gone.get("player")
	if player != null and player.has_animation("death") and str(gone.get("clip", "")) != "death":
		player.get_animation("death").loop_mode = Animation.LOOP_NONE
		player.play("death", 0.1)
	_dying.append({"model": model, "time": 0.0, "base_y": model.position.y, "base_scale": model.scale})


func _update_dying(delta: float) -> void:
	for index in range(_dying.size() - 1, -1, -1):
		var fallen: Dictionary = _dying[index]
		var model: Node3D = fallen["model"]
		if not is_instance_valid(model):
			_dying.remove_at(index)
			continue
		fallen["time"] = float(fallen["time"]) + delta
		var t: float = clampf(float(fallen["time"]) / SINK_TIME, 0.0, 1.0)
		var eased: float = t * t * (3.0 - 2.0 * t)
		model.position.y = float(fallen["base_y"]) - SINK_DEPTH * eased
		model.scale = fallen["base_scale"] * (1.0 - 0.3 * eased)
		if t >= 1.0:
			model.queue_free()
			_dying.remove_at(index)


# Mirrors the game's shared cap for decoration.
func _effect_budget_open() -> bool:
	return effect_nodes.size() + burst_pool.active_count() < EFFECT_LIMIT


# True when a raider stands within radius tiles of the given tile.
func _raider_near(tile: Vector2, radius: float) -> bool:
	for u: Dictionary in sim.enemies:
		if sim.position_of(u).distance_to(tile) <= radius:
			return true
	return false


# A quick pop of the nearest raider's model, so a struck raider visibly reacts.
func _flinch_raider(tile: Vector2) -> void:
	var best_id: int = -1
	var best: float = 1.2
	for u: Dictionary in sim.enemies:
		var d: float = sim.position_of(u).distance_to(tile)
		if d < best:
			best = d
			best_id = int(u["id"])
	if best_id < 0 or not actors.has(best_id):
		return
	var model: Node3D = actors[best_id]["model"]
	if not is_instance_valid(model):
		return
	var key: int = model.get_instance_id()
	if not _pulse_base.has(key):
		_pulse_base[key] = model.scale
	var rest: Vector3 = _pulse_base[key]
	var tween: Tween = _effect_tween()
	tween.tween_property(model, "scale", rest * 1.14, 0.06).set_ease(Tween.EASE_OUT)
	tween.tween_property(model, "scale", rest, 0.14).set_ease(Tween.EASE_IN)


# An arrow that rises and falls along an arc, turning to face its flight. Raider
# arrows are dark and red-tipped. On arrival it throws a spark burst and a flash.
func _launch_arrow(from_point: Vector3, to_point: Vector3, raider: bool) -> void:
	if not _effect_budget_open():
		return
	var wood: Color = RAIDER_WOOD if raider else ARROW_WOOD
	var head: Color = RAIDER_IRON if raider else ARROW_STEEL
	var spark: Color = RAIDER_SPARK if raider else ARROW_SPARK
	var distance: float = from_point.distance_to(to_point)
	var arc: float = clampf(0.5 + distance * 0.22, 0.5, 2.2)
	var duration: float = clampf(distance * 0.07, 0.18, 0.5)
	_impact_burst(from_point, DUST, 4, 0.5)
	var arrow := Node3D.new()
	arrow.position = from_point
	add_child(arrow)
	effect_nodes.append(arrow)
	_box(Vector3(0.05, 0.05, 0.42), Vector3.ZERO, wood, arrow)
	_box(Vector3(0.1, 0.1, 0.12), Vector3(0, 0, -0.24), head, arrow)
	var tween: Tween = _effect_tween()
	tween.tween_method(_step_arrow.bind(arrow, from_point, to_point, arc), 0.0, 1.0, duration)
	tween.tween_callback(arrow.queue_free)
	tween.tween_callback(_impact_burst.bind(to_point, spark, 8, 0.9))
	tween.tween_callback(_hit_flash.bind(to_point, spark))


func _step_arrow(t: float, arrow: Node3D, from_point: Vector3, to_point: Vector3, arc: float) -> void:
	if not is_instance_valid(arrow):
		return
	arrow.position = from_point.lerp(to_point, t) + Vector3.UP * sin(PI * t) * arc
	var slope: Vector3 = (to_point - from_point) + Vector3.UP * cos(PI * t) * PI * arc
	if slope.length_squared() < 0.000001:
		return
	# Looking straight up or down has no sensible facing, so keep the last one.
	if absf(slope.normalized().dot(Vector3.UP)) > 0.98:
		return
	arrow.look_at(to_global(arrow.position + slope), Vector3.UP)


# A soft flash that swells and fades in about a fifth of a second.
func _hit_flash(at: Vector3, tint: Color) -> void:
	if not _effect_budget_open():
		return
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.disable_receive_shadows = true
	material.albedo_texture = _street_halo_texture()
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.9)
	quad.material = material
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.position = at
	add_child(flash)
	effect_nodes.append(flash)
	var tween: Tween = _effect_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 1.8, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.18)
	tween.chain().tween_callback(flash.queue_free)


# A dust cloud that spreads across the ground and drifts away.
func _dust_puff(at: Vector3, radius: float) -> void:
	if not _effect_budget_open():
		return
	var puff := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_receive_shadows = true
	material.albedo_texture = _street_halo_texture()
	material.albedo_color = Color(DUST.r, DUST.g, DUST.b, 0.5)
	quad.material = material
	puff.mesh = quad
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	puff.position = at + Vector3(0, 0.05, 0)
	puff.scale = Vector3.ONE * 0.4
	add_child(puff)
	effect_nodes.append(puff)
	var tween: Tween = _effect_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * radius, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.9)
	tween.chain().tween_callback(puff.queue_free)
	_impact_burst(at + Vector3(0, 0.2, 0), DUST, 10, 1.2, true)


# Shows a health bar above each raider that has taken damage. Bars are removed when
# the raider is gone, and hidden while the raider is at full health or down.
func _update_enemy_bars() -> void:
	var alive: Dictionary = {}
	for u: Dictionary in sim.enemies:
		var id: int = int(u["id"])
		alive[id] = true
		var hp: float = float(u["hp"])
		var max_hp: float = maxf(float(_enemy_max_hp.get(id, hp)), hp)
		_enemy_max_hp[id] = max_hp
		var show: bool = hp > 0.0 and hp < max_hp and actors.has(id)
		var bar: Dictionary = _enemy_bars.get(id, {})
		if not show:
			if not bar.is_empty() and is_instance_valid(bar["root"]):
				(bar["root"] as Node3D).visible = false
			continue
		if bar.is_empty() or not is_instance_valid(bar["root"]):
			bar = _make_bar()
			_enemy_bars[id] = bar
		var root: Node3D = bar["root"]
		var model: Node3D = actors[id]["model"]
		root.position = model.position + Vector3(0, BAR_HEIGHT, 0)
		root.visible = true
		var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		var fill: MeshInstance3D = bar["fill"]
		fill.scale.x = maxf(ratio, 0.001)
		fill.position.x = -BAR_WIDTH * 0.5 * (1.0 - ratio)
	for id: Variant in _enemy_bars.keys():
		if not alive.has(id):
			var old: Dictionary = _enemy_bars[id]
			if is_instance_valid(old["root"]):
				(old["root"] as Node3D).queue_free()
			_enemy_bars.erase(id)
	for id: Variant in _enemy_max_hp.keys():
		if not alive.has(id):
			_enemy_max_hp.erase(id)


func _make_bar() -> Dictionary:
	var root := Node3D.new()
	var back := MeshInstance3D.new()
	var back_quad := QuadMesh.new()
	back_quad.size = Vector2(BAR_WIDTH, 0.12)
	back_quad.material = _bar_material(Color(0.06, 0.05, 0.06, 0.85))
	back.mesh = back_quad
	root.add_child(back)
	var fill := MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(BAR_WIDTH, 0.08)
	fill_quad.material = _bar_material(Color(0.86, 0.22, 0.2))
	fill.mesh = fill_quad
	root.add_child(fill)
	actor_layer.add_child(root)
	return {"root": root, "fill": fill}


func _bar_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.disable_receive_shadows = true
	material.albedo_color = colour
	material.render_priority = 3
	return material


# Drives the warning veil, the approach arrows and the break jolt. Runs every frame;
# the veil fades in with the horn and out once the raid ends.
func _update_raid_read(delta: float) -> void:
	var alarm: bool = started and not is_instance_valid(battle_view) and (sim.raid_warning or sim.raid_active)
	_veil_level = move_toward(_veil_level, 1.0 if alarm else 0.0, delta * VEIL_RATE)
	_toll_clock += delta
	if not alarm:
		_shake_level = 0.0
	_update_shake(delta)
	if _veil_level <= 0.001 and not alarm:
		if _raid_layer != null and _raid_layer.visible:
			_raid_layer.visible = false
		return
	_ensure_raid_read()
	_raid_layer.visible = true
	# One toll per TOLL_PERIOD: a sharp swell that decays until the next stroke.
	var toll: float = exp(-6.0 * fmod(_toll_clock, TOLL_PERIOD) / TOLL_PERIOD)
	var weight: float = 1.0 if sim.raid_active else 0.7
	_veil_material.set_shader_parameter("strength", _veil_level * weight * (0.35 + 0.65 * toll))
	_update_arrows(alarm)


func _ensure_raid_read() -> void:
	if _raid_layer != null:
		return
	_raid_layer = CanvasLayer.new()
	_raid_layer.layer = 1
	add_child(_raid_layer)
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VEIL_SHADER
	_veil_material = ShaderMaterial.new()
	_veil_material.shader = shader
	_veil.material = _veil_material
	_raid_layer.add_child(_veil)
	for index in ARROW_MAX:
		var arrow := Polygon2D.new()
		arrow.polygon = PackedVector2Array([Vector2(14, 0), Vector2(-7, -9), Vector2(-3, 0), Vector2(-7, 9)])
		arrow.visible = false
		_raid_layer.add_child(arrow)
		_arrows.append(arrow)


# Where the attackers are coming from: the spawn edge during the horn warning, and the
# edge each live raider group is nearest to once the raid is on. At most one per edge.
func _arrow_targets() -> Array:
	var targets: Array = []
	if sim.raid_active:
		var sums: Dictionary = {}
		for u: Dictionary in sim.enemies:
			var p: Vector2 = sim.position_of(u)
			var gaps: Array[float] = [p.x, MAP_WIDTH - p.x, p.y, MAP_HEIGHT - p.y]
			var side: int = gaps.find(gaps.min())
			var entry: Array = sums.get(side, [Vector2.ZERO, 0])
			entry[0] += p
			entry[1] += 1
			sums[side] = entry
		for side: int in sums:
			var entry: Array = sums[side]
			targets.append({"at": world_position(entry[0] / float(entry[1]), 1.0), "color": ARROW_BLOOD})
	elif sim.raid_warning:
		var wave_number: int = sim.wave + 1
		var count: int = mini(int(sim.world_specs.get("homeRaids", {}).get("maxCount", 8)), wave_number + 1)
		var sides: Array = [0, 1, 2, 3] if count >= 4 else [(wave_number - 1) % 4]
		for side: int in sides:
			targets.append({"at": world_position(SIDE_ANCHORS[side], 1.0), "color": ARROW_BRASS})
	return targets.slice(0, ARROW_MAX)


func _update_arrows(alarm: bool) -> void:
	var targets: Array = _arrow_targets() if alarm else []
	var size: Vector2 = get_viewport().get_visible_rect().size
	var centre: Vector2 = size * 0.5
	var half: Vector2 = centre - Vector2(ARROW_MARGIN, ARROW_MARGIN)
	var shown: int = 0
	for target: Dictionary in targets:
		var at: Vector3 = target["at"]
		var direction: Vector2
		if camera.is_position_behind(at):
			# Projection flips for points behind the camera, so take the direction from camera space.
			var local: Vector3 = camera.global_transform.affine_inverse() * at
			direction = -Vector2(local.x, -local.y)
		else:
			var screen: Vector2 = camera.unproject_position(at)
			if Rect2(Vector2.ZERO, size).has_point(screen):
				continue
			direction = screen - centre
		if direction.length() < 1.0:
			continue
		var scale_to_edge: float = minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
		var arrow: Polygon2D = _arrows[shown]
		arrow.position = centre + direction * scale_to_edge
		arrow.rotation = direction.angle()
		arrow.color = Color(target["color"].r, target["color"].g, target["color"].b, 0.9 * _veil_level)
		arrow.visible = true
		shown += 1
	for index in range(shown, _arrows.size()):
		_arrows[index].visible = false


# A short jolt for the camera. It moves the lens offset only, so the orbit and pan
# (which set the camera's position) are never disturbed, and it is reset when it ends.
func _update_shake(delta: float) -> void:
	if _shake_level > 0.0:
		_shake_level = maxf(0.0, _shake_level - delta / SHAKE_TIME)
		_shake_clock += delta
		var amplitude: float = _shake_level * SHAKE_FRACTION * camera.size
		camera.h_offset = sin(_shake_clock * 75.0) * amplitude
		camera.v_offset = cos(_shake_clock * 61.0) * amplitude
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
