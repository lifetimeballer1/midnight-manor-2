extends "res://scripts/game/village_omens.gd"

# Clash layer (visual only), layered over the omens. It makes melee read as melee:
# when a fighter lands a blow, that fighter lunges into the target, leans in and
# recovers, and a crescent slash streak flashes between the two. Kills and collapses
# freeze the game for a blink (a subtle hit-stop, well under a tenth of a second) and
# nudge the camera toward the impact. When a raid is held, time eases through a short
# slow beat with the bell tolling and a gold vignette; a lost raid gets a red one.
# Everything is read from the sim's events just before the game consumes them, so the
# simulation, the save data and the event list are untouched apart from a private mark
# on each event so it is never read twice. Effects share the decoration budget, and none
# play during frontier battles. Time is always restored: after every freeze, when the
# battle view opens, and when the scene leaves the tree.

const SWING_TIME: float = 0.3
const SWING_STRIKE: float = 0.22          # fraction of the swing spent driving forward
const SWING_LUNGE: float = 0.38           # tiles the fighter drives into the target
const SWING_LEAN: float = 11.0            # degrees of forward pitch at the deepest point
const SWING_MELEE_REACH: float = 1.9      # a blow from further away is a shot, not a swing
const SWING_MATCH: float = 0.6            # a fighter's aim must land this close to the hit
const SWING_FALLBACK: float = 2.5         # reach for blows on big targets such as walls
const SLASH_SIZE: float = 2.6
const SLASH_TIME: float = 0.17
const SLASH_HEIGHT: float = 1.15
const SLASH_HOME: Color = Color(1.0, 0.9, 0.62)
const SLASH_FOE: Color = Color(1.0, 0.38, 0.32)

const STOP_TIME: float = 0.04             # seconds of freeze on a kill
const STOP_COLLAPSE: float = 0.055
const STOP_SCALE: float = 0.05            # engine speed during the freeze
const STOP_GAP: float = 0.35              # real seconds between freezes, so a melee never stutters

const PUNCH_FRACTION: float = 0.012       # camera nudge as a fraction of the camera's size
const PUNCH_TIME: float = 0.16
const PUNCH_HIT: float = 0.35
const PUNCH_KILL: float = 0.8
const PUNCH_COLLAPSE: float = 1.3

const SOUL_TINT: Color = Color(0.66, 0.5, 1.0)
const SOUL_PALE: Color = Color(0.8, 0.86, 1.0)
const SOUL_RISE: float = 3.2
const SOUL_TIME: float = 1.4
const RING_SIZE: float = 3.2
const RING_TIME: float = 0.4

const NUMBER_MAX: int = 6                 # damage numbers alive at once
const NUMBER_MERGE: float = 0.9           # tiles; blows this close and this soon add into one number
const NUMBER_MERGE_MS: int = 450
const NUMBER_LIFE: float = 0.85
const NUMBER_HOME: Color = Color(1.0, 0.9, 0.6)
const NUMBER_FOE: Color = Color(1.0, 0.36, 0.3)

const KICK_DEGREES: float = 2.4           # how far a struck building rocks
const CHIP_COUNT: int = 3
const CHIP_ROOM: int = 6                  # chips only fly when this many effect slots are free
const TRAIL_LENGTH: float = 1.1

const FINISH_SCALE: float = 0.35         # engine speed at the start of the held-raid beat
const FINISH_TIME: float = 0.8
const VIGNETTE_TIME: float = 1.2
const VIGNETTE_GOLD: Color = Color(1.0, 0.8, 0.42)
const VIGNETTE_BLOOD: Color = Color(0.72, 0.08, 0.1)
const VIGNETTE_SHADER: String = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.42, 1.0);
uniform float level = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = smoothstep(0.3, 1.35, length(p));
	COLOR = vec4(tint.rgb, edge * level * 0.6);
}
"""

var _swings: Dictionary = {}              # actor id -> {"t": seconds, "dir": Vector3}
var _slash_texture: Texture2D = null
var _ring_texture: Texture2D = null
var _numbers: Array[Dictionary] = []      # live damage numbers: label, tile, amount, born, friendly
var _clash_ready: bool = false

var _slow_active: bool = false
var _slow_start_ms: int = 0
var _slow_end_ms: int = 0
var _slow_from: float = 1.0
var _last_stop_ms: int = -10000

var _punch_dir: Vector2 = Vector2.ZERO
var _punch_amp: float = 0.0

var _vignette_layer: CanvasLayer = null
var _vignette_material: ShaderMaterial = null
var _vignette_start_ms: int = -100000
var _vignette_peak: float = 0.0


func _process(delta: float) -> void:
	if not _clash_ready:
		_clash_ready = true
		tree_exiting.connect(func() -> void: Engine.time_scale = 1.0)
	var fighting: bool = started and not is_instance_valid(battle_view)
	if fighting and not sim.paused:
		_read_clash_events()
	super(delta)
	if not fighting:
		_restore_time()
		return
	_update_time_scale()
	_apply_punch(0.0 if sim.paused else delta)
	_update_vignette()


func _update_actors(delta: float) -> void:
	super(delta)
	_apply_swings(0.0 if sim.paused else delta)


# Reads this frame's events before the game consumes them, leaving them in place.
func _read_clash_events() -> void:
	for event: Dictionary in sim.events:
		if event.has("clash"):
			continue
		event["clash"] = true
		var kind: String = str(event.get("kind", ""))
		var tile := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
		if kind == "hit":
			if event.has("amount"):
				_clash_hit(tile, bool(event.get("friendly", false)))
				_damage_number(tile, float(event["amount"]), bool(event.get("friendly", false)))
				if bool(event.get("friendly", false)):
					_building_hit(tile)
		elif kind == "shot":
			_tower_recoil(Vector2(float(event.get("from_x", 0.0)), float(event.get("from_y", 0.0))))
		elif kind == "fall":
			_hit_stop(STOP_TIME)
			_punch_at(tile, PUNCH_KILL)
			_spirit_release(tile, str(event.get("side", "")) == "foe")
		elif kind == "destroyed":
			_hit_stop(STOP_COLLAPSE)
			_punch_at(tile, PUNCH_COLLAPSE)
		elif kind == "raid_result":
			_raid_finish(bool(event.get("victory", false)))


# ---- melee swing -----------------------------------------------------------------

# A blow landed on tile. Friendly means our side took it, so a raider swung it.
func _clash_hit(tile: Vector2, friendly: bool) -> void:
	_punch_at(tile, PUNCH_HIT)
	var attacker: Dictionary = _find_attacker(tile, friendly)
	if attacker.is_empty():
		return
	var from_tile: Vector2 = sim.position_of(attacker)
	if friendly:
		# Raiders with a long reach (archers, bombards) shoot rather than swing.
		if float(sim._role_stats(str(attacker.get("role", "raider"))).get("range", 1.1)) > 1.5:
			return
	elif from_tile.distance_to(tile) > SWING_MELEE_REACH:
		return
	var from_point: Vector3 = world_position(from_tile, 0.0)
	var to_point: Vector3 = world_position(tile, 0.0)
	var dir: Vector3 = to_point - from_point
	dir.y = 0.0
	if dir.length_squared() < 0.0004:
		return
	_swings[int(attacker["id"])] = {"t": 0.0, "dir": dir.normalized()}
	_spawn_slash(from_point, to_point, SLASH_FOE if friendly else SLASH_HOME)


# The fighter whose blow this was: aimed at the struck tile and mid-attack. Archers shoot.
func _find_attacker(tile: Vector2, friendly: bool) -> Dictionary:
	var group: Array = sim.enemies if friendly else sim.units
	var best: Dictionary = {}
	var best_gap: float = INF
	var fallback: Dictionary = {}
	var fallback_gap: float = SWING_FALLBACK
	for u: Dictionary in group:
		if float(u["hp"]) <= 0.0 or str(u.get("phase", "")) != "attack" or str(u.get("type", "")) == "archer":
			continue
		var gap: float = sim.position_of(u).distance_to(tile)
		var aim := Vector2(float(u.get("fx", INF)), float(u.get("fy", INF)))
		if aim.distance_to(tile) <= SWING_MATCH and gap < best_gap:
			best = u
			best_gap = gap
		elif friendly and gap < fallback_gap:
			fallback = u
			fallback_gap = gap
	return best if not best.is_empty() else fallback


# Drives each active swing: out along the blow, a lean into it, then back to rest. It runs
# after the game has set every figure's place for the frame, so the offset never sticks.
func _apply_swings(delta: float) -> void:
	for id: int in _swings.keys():
		var swing: Dictionary = _swings[id]
		var record: Dictionary = actors.get(id, {})
		var model: Node3D = record.get("model")
		if record.is_empty() or not is_instance_valid(model):
			_swings.erase(id)
			continue
		swing["t"] = float(swing["t"]) + delta
		var p: float = clampf(float(swing["t"]) / SWING_TIME, 0.0, 1.0)
		var curve: float
		if p < SWING_STRIKE:
			var s: float = p / SWING_STRIKE
			curve = 1.0 - (1.0 - s) * (1.0 - s)
		else:
			var r: float = (p - SWING_STRIKE) / (1.0 - SWING_STRIKE)
			curve = 1.0 - r * r * (3.0 - 2.0 * r)
		if p >= 1.0:
			model.rotation.x = 0.0
			_swings.erase(id)
			continue
		model.position += (swing["dir"] as Vector3) * SWING_LUNGE * curve
		model.rotation.x = deg_to_rad(SWING_LEAN) * curve


# A crescent that flares between the fighters, turned to sweep along the blow as the
# camera sees it, then swells and fades.
func _spawn_slash(from_point: Vector3, to_point: Vector3, tint: Color) -> void:
	if not _effect_budget_open():
		return
	var cam_basis: Basis = camera.global_basis
	var heading: Vector3 = (to_point - from_point).normalized()
	var angle: float = atan2(heading.dot(cam_basis.y), heading.dot(cam_basis.x))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.disable_receive_shadows = true
	material.albedo_texture = _crescent_texture()
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.95)
	var quad := QuadMesh.new()
	quad.size = Vector2(SLASH_SIZE, SLASH_SIZE)
	quad.material = material
	var slash := MeshInstance3D.new()
	slash.mesh = quad
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slash.position = from_point.lerp(to_point, 0.72) + Vector3.UP * SLASH_HEIGHT
	add_child(slash)
	slash.global_basis = cam_basis.rotated(cam_basis.z, angle + randf_range(-0.35, 0.35))
	slash.scale = Vector3.ONE * 0.6
	effect_nodes.append(slash)
	var tween: Tween = _effect_tween()
	tween.set_parallel(true)
	tween.tween_property(slash, "scale", Vector3.ONE * 1.15, SLASH_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, SLASH_TIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(slash.queue_free)


func _crescent_texture() -> Texture2D:
	if _slash_texture != null:
		return _slash_texture
	var size: int = 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in size:
		for y in size:
			var p := Vector2((x + 0.5) / size * 2.0 - 1.0, (y + 0.5) / size * 2.0 - 1.0)
			var outer: float = clampf((1.0 - p.length()) / 0.14, 0.0, 1.0)
			var inner: float = clampf(((p - Vector2(-0.4, 0.0)).length() - 0.86) / 0.16, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, outer * inner))
	_slash_texture = ImageTexture.create_from_image(image)
	return _slash_texture


# ---- souls, numbers, arrows, buildings -------------------------------------------

# A fallen raider lets go of its soul: a violet wisp that climbs and thins out, with a
# ring that ripples across the ground. A fallen defender gets only a pale ring.
func _spirit_release(tile: Vector2, foe: bool) -> void:
	_shock_ring(world_position(tile, 0.08), SOUL_TINT if foe else SOUL_PALE)
	if not foe or not _effect_budget_open():
		return
	var start: Vector3 = world_position(tile, 1.0)
	var wisp: MeshInstance3D = _glow_quad(_street_halo_texture(), SOUL_TINT, 0.9, true)
	wisp.position = start
	add_child(wisp)
	effect_nodes.append(wisp)
	var material: StandardMaterial3D = wisp.mesh.material
	var drift := Vector3(randf_range(-0.6, 0.6), SOUL_RISE, randf_range(-0.6, 0.6))
	var tween: Tween = _effect_tween()
	tween.set_parallel(true)
	tween.tween_property(wisp, "position", start + drift, SOUL_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(wisp, "scale", Vector3.ONE * 0.35, SOUL_TIME).set_ease(Tween.EASE_IN)
	tween.tween_property(material, "albedo_color:a", 0.0, SOUL_TIME * 0.6).set_delay(SOUL_TIME * 0.4)
	tween.chain().tween_callback(wisp.queue_free)
	_impact_burst(start, SOUL_TINT, 6, 0.7, true)


func _shock_ring(at: Vector3, tint: Color) -> void:
	if not _effect_budget_open():
		return
	var ring: MeshInstance3D = _glow_quad(_ring_tex(), tint, RING_SIZE, false)
	ring.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ring.position = at
	ring.scale = Vector3.ONE * 0.25
	add_child(ring)
	effect_nodes.append(ring)
	var material: StandardMaterial3D = ring.mesh.material
	var tween: Tween = _effect_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE, RING_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, RING_TIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


# An additive soft quad, billboarded or lying flat.
func _glow_quad(texture: Texture2D, tint: Color, size: float, billboard: bool) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.disable_receive_shadows = true
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.9)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	var node := MeshInstance3D.new()
	node.mesh = quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _ring_tex() -> Texture2D:
	if _ring_texture != null:
		return _ring_texture
	var size: int = 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in size:
		for y in size:
			var radius: float = Vector2((x + 0.5) / size * 2.0 - 1.0, (y + 0.5) / size * 2.0 - 1.0).length()
			var band: float = clampf(1.0 - absf(radius - 0.82) / 0.14, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, band * band))
	_ring_texture = ImageTexture.create_from_image(image)
	return _ring_texture


# A small number floats up from each blow. Blows landing close together within a moment
# add into one number, so a melee reads as a running total instead of a swarm.
func _damage_number(tile: Vector2, amount: float, friendly: bool) -> void:
	var now: int = Time.get_ticks_msec()
	for index in range(_numbers.size() - 1, -1, -1):
		var entry: Dictionary = _numbers[index]
		if not is_instance_valid(entry["label"]):
			_numbers.remove_at(index)
			continue
		if bool(entry["friendly"]) == friendly and now - int(entry["born"]) < NUMBER_MERGE_MS and (entry["tile"] as Vector2).distance_to(tile) < NUMBER_MERGE:
			entry["amount"] = float(entry["amount"]) + amount
			(entry["label"] as Label3D).text = str(int(roundf(float(entry["amount"]))))
			return
	if _numbers.size() >= NUMBER_MAX or not _effect_budget_open():
		return
	var label := Label3D.new()
	label.text = str(int(roundf(amount)))
	label.font_size = 44
	label.pixel_size = 0.011
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.03, 0.06, 0.9)
	label.modulate = NUMBER_FOE if friendly else NUMBER_HOME
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	var start: Vector3 = world_position(tile, 1.9) + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	label.position = start
	add_child(label)
	effect_nodes.append(label)
	_numbers.append({"label": label, "tile": tile, "amount": amount, "born": now, "friendly": friendly})
	var tween: Tween = _effect_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start.y + 1.1, NUMBER_LIFE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(NUMBER_LIFE - 0.3)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.3).set_delay(NUMBER_LIFE - 0.3)
	tween.chain().tween_callback(label.queue_free)


# Arrows leave a fading streak behind them. The parent draws the arrow and puts it last
# in the effect list, so the streak rides on that node and is freed with it.
func _launch_arrow(from_point: Vector3, to_point: Vector3, raider: bool) -> void:
	var before: int = effect_nodes.size()
	super(from_point, to_point, raider)
	if effect_nodes.size() <= before:
		return
	var arrow: Node3D = effect_nodes[effect_nodes.size() - 1] as Node3D
	if arrow == null:
		return
	var tint: Color = RAIDER_SPARK if raider else ARROW_SPARK
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.4)
	var box := BoxMesh.new()
	box.size = Vector3(0.035, 0.035, TRAIL_LENGTH)
	box.material = material
	var streak := MeshInstance3D.new()
	streak.mesh = box
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak.position = Vector3(0.0, 0.0, 0.2 + TRAIL_LENGTH * 0.5)
	arrow.add_child(streak)


# A wall, gate or other building taking a raider's blow rocks and throws off chips.
func _building_hit(tile: Vector2) -> void:
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) <= 0.0 or sim.center(b).distance_to(tile) > 0.35:
			continue
		_kick_building(int(b["id"]), 1.0)
		_chips(world_position(tile, 0.9))
		return


# A defence building rocks back a touch when it looses a shot.
func _tower_recoil(from_tile: Vector2) -> void:
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) > 0.0 and sim.center(b).distance_to(from_tile) < 0.35:
			_kick_building(int(b["id"]), 0.4)
			return


func _kick_building(id: int, strength: float) -> void:
	var view: Dictionary = building_views.get(id, {})
	var model: Node3D = view.get("model")
	if not is_instance_valid(model):
		return
	if not model.has_meta("clash_base_z"):
		model.set_meta("clash_base_z", model.rotation.z)
	var base: float = float(model.get_meta("clash_base_z"))
	if model.has_meta("clash_kick"):
		var old: Tween = model.get_meta("clash_kick")
		if old != null and old.is_valid():
			old.kill()
	model.rotation.z = base
	var tween: Tween = _effect_tween()
	model.set_meta("clash_kick", tween)
	var amount: float = deg_to_rad(KICK_DEGREES) * strength * (1.0 if randf() < 0.5 else -1.0)
	for step: Array in [[1.0, 0.05], [-0.55, 0.07], [0.25, 0.07], [0.0, 0.08]]:
		tween.tween_property(model, "rotation:z", base + amount * float(step[0]), float(step[1])).set_ease(Tween.EASE_OUT)


# A few chips of rubble thrown up and out, tumbling down under gravity.
func _chips(at: Vector3) -> void:
	if effect_nodes.size() + burst_pool.active_count() + CHIP_ROOM > EFFECT_LIMIT:
		_impact_burst(at, DUST, 5, 0.8)
		return
	for i in CHIP_COUNT:
		var material := StandardMaterial3D.new()
		material.albedo_color = ARROW_WOOD.lerp(DUST, randf())
		var box := BoxMesh.new()
		box.size = Vector3.ONE * randf_range(0.07, 0.13)
		box.material = material
		var chip := MeshInstance3D.new()
		chip.mesh = box
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chip.position = at
		add_child(chip)
		effect_nodes.append(chip)
		var velocity := Vector3(randf_range(-1.5, 1.5), randf_range(2.2, 3.4), randf_range(-1.5, 1.5))
		var spin := Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
		var tween: Tween = _effect_tween()
		tween.tween_method(_step_chip.bind(chip, at, velocity, spin), 0.0, 0.55, 0.55)
		tween.tween_callback(chip.queue_free)
	_impact_burst(at, DUST, 5, 0.8)


func _step_chip(t: float, chip: Node3D, start: Vector3, velocity: Vector3, spin: Vector3) -> void:
	if is_instance_valid(chip):
		chip.position = start + velocity * t + Vector3.DOWN * 4.9 * t * t
		chip.rotation = spin * t


# ---- hit-stop and time -----------------------------------------------------------

# Freezes the game for a blink. Skipped while a freeze or the finisher beat is running,
# and rate-limited so a big melee reads as a rhythm rather than a stutter.
func _hit_stop(seconds: float) -> void:
	var now: int = Time.get_ticks_msec()
	if _slow_active or float(now - _last_stop_ms) < STOP_GAP * 1000.0:
		return
	_last_stop_ms = now
	_start_slow(seconds, STOP_SCALE)


func _start_slow(seconds: float, from_scale: float) -> void:
	_slow_active = true
	_slow_start_ms = Time.get_ticks_msec()
	_slow_end_ms = _slow_start_ms + int(seconds * 1000.0)
	_slow_from = from_scale
	Engine.time_scale = from_scale


# Holds the freeze, or eases the finisher beat back up to full speed, in real time.
func _update_time_scale() -> void:
	if not _slow_active:
		return
	var now: int = Time.get_ticks_msec()
	if now >= _slow_end_ms or sim.paused:
		_restore_time()
		return
	var t: float = float(now - _slow_start_ms) / float(maxi(1, _slow_end_ms - _slow_start_ms))
	Engine.time_scale = lerpf(_slow_from, 1.0, t * t * (3.0 - 2.0 * t)) if _slow_from > STOP_SCALE else _slow_from


func _restore_time() -> void:
	if _slow_active or Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	_slow_active = false


# ---- camera ----------------------------------------------------------------------

# A small nudge of the lens toward the impact. Offsets only, like the shake, so the
# orbit and pan are never disturbed. A stronger nudge replaces a weaker one in flight.
func _punch_at(tile: Vector2, strength: float) -> void:
	if strength < _punch_amp:
		return
	var screen: Vector2 = camera.unproject_position(world_position(tile, 0.5))
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var toward: Vector2 = screen - centre
	if toward.length_squared() < 4.0:
		toward = Vector2.from_angle(randf() * TAU)
	toward = toward.normalized()
	_punch_dir = Vector2(toward.x, -toward.y)
	_punch_amp = strength


func _apply_punch(delta: float) -> void:
	if _punch_amp <= 0.0:
		return
	_punch_amp = maxf(0.0, _punch_amp - delta / PUNCH_TIME)
	var pull: float = _punch_amp * _punch_amp * PUNCH_FRACTION * camera.size
	camera.h_offset += _punch_dir.x * pull
	camera.v_offset += _punch_dir.y * pull


# ---- the beat when a raid ends ---------------------------------------------------

func _raid_finish(held: bool) -> void:
	if held:
		_start_slow(FINISH_TIME, FINISH_SCALE)
		_last_stop_ms = Time.get_ticks_msec()
		if has_method("_swing_bell"):
			call("_swing_bell")
	_flash_vignette(VIGNETTE_GOLD if held else VIGNETTE_BLOOD, 1.0 if held else 0.7)


func _flash_vignette(tint: Color, peak: float) -> void:
	if _vignette_layer == null:
		_vignette_layer = CanvasLayer.new()
		_vignette_layer.layer = 40
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shader := Shader.new()
		shader.code = VIGNETTE_SHADER
		_vignette_material = ShaderMaterial.new()
		_vignette_material.shader = shader
		rect.material = _vignette_material
		_vignette_layer.add_child(rect)
		add_child(_vignette_layer)
	_vignette_material.set_shader_parameter("tint", tint)
	_vignette_peak = peak
	_vignette_start_ms = Time.get_ticks_msec()
	_vignette_layer.visible = true


# Quick rise, long fall, driven by real time so the slow beat does not stretch it.
func _update_vignette() -> void:
	if _vignette_layer == null or not _vignette_layer.visible:
		return
	var t: float = float(Time.get_ticks_msec() - _vignette_start_ms) / (VIGNETTE_TIME * 1000.0)
	if t >= 1.0:
		_vignette_layer.visible = false
		return
	var level: float = t / 0.14 if t < 0.14 else pow(1.0 - (t - 0.14) / 0.86, 2.0)
	_vignette_material.set_shader_parameter("level", level * _vignette_peak)
