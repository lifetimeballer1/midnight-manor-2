extends "res://scripts/game/village_dusk.gd"

# Dawn bell: when the sun comes up, the Old Bell rings. A struck-bell tone plays,
# a soft gold flash swells above the Manor Hall with a spray of sparks, and the
# Old Bell's caption floats up while the mentor is on. It rings once a day, on
# the night-to-day turn, and stays quiet if the game loads in daylight.
# Decoration only: it reads the day cycle and never changes the simulation.

var _bell_sim: Object = null
var _bell_seen: bool = false
var _bell_was_night: bool = false
var _bell_stream: AudioStreamWAV = null
var _bell_player: AudioStreamPlayer = null
var _bell_swing_tween: Tween = null


func _process(delta: float) -> void:
	super(delta)
	if not started or is_instance_valid(battle_view):
		return
	if sim != _bell_sim:
		_bell_sim = sim
		_bell_seen = false
	if not _bell_seen:
		# First frame of a game or a loaded save: note the time of day without ringing.
		_bell_seen = true
		_bell_was_night = night
		return
	if _bell_was_night and not night:
		_ring_bell()
	_bell_was_night = night


func _ring_bell() -> void:
	# Anchor to a finished Bell Tower when one stands, otherwise to the Manor Hall.
	var tower: Dictionary = _bell_tower()
	var anchor_building: Dictionary = tower if not tower.is_empty() else sim._hall()
	var anchor: Vector2 = sim.center(anchor_building) if not anchor_building.is_empty() else Vector2(10, 8)
	var at: Vector3 = world_position(anchor, 0.0)
	_swing_bell()
	_bell_flash(at + Vector3(0, 3.2, 0))
	_sparkle_ring(at, 10, 3.2, 2.6)
	_impact_burst(at + Vector3(0, 2.6, 0), GOLD, 18, 1.2, true)
	if mentor_enabled:
		_float_label(at + Vector3(0, 4.6, 0), "The Old Bell rings", GOLD, 56, 1.2, 2.6)
	if sound:
		_play_bell()


# The first finished Bell Tower in the village, or an empty dictionary when none stands.
func _bell_tower() -> Dictionary:
	if sim == null:
		return {}
	for b: Dictionary in sim.buildings:
		if str(b["type"]).begins_with("bell") and float(b["hp"]) > 0.0 and float(b.get("remaining", 0.0)) <= 0.0:
			return b
	return {}


# A brief decaying pendulum sway on the bell tower's model (the tower has no separate
# bell node, so the whole model leans). Null-safe: no tower built means no sway.
func _swing_bell() -> void:
	var tower: Dictionary = _bell_tower()
	if tower.is_empty():
		return
	var view: Dictionary = building_views.get(int(tower["id"]), {})
	var model: Node3D = view.get("model")
	if not is_instance_valid(model):
		return
	# Remember the seeded lean so the sway swings around it rather than replacing it.
	if not model.has_meta("bell_base_z"):
		model.set_meta("bell_base_z", model.rotation.z)
	var base: float = float(model.get_meta("bell_base_z"))
	if _bell_swing_tween != null and _bell_swing_tween.is_valid():
		_bell_swing_tween.kill()
	model.rotation.z = base
	_bell_swing_tween = create_tween()
	var steps: Array = [[3.0, 0.1], [-2.2, 0.2], [1.2, 0.18], [0.0, 0.22]]
	for step: Array in steps:
		_bell_swing_tween.tween_property(model, "rotation:z", base + deg_to_rad(float(step[0])), float(step[1])).set_ease(Tween.EASE_IN_OUT)


# A soft gold flash that swells above the hall and fades out in about two seconds.
func _bell_flash(at: Vector3) -> void:
	if effect_nodes.size() >= EFFECT_LIMIT:
		return
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.disable_receive_shadows = true
	flash_material.albedo_texture = _street_halo_texture()
	flash_material.albedo_color = Color(1.0, 0.84, 0.5, 0.9)
	quad.material = flash_material
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.position = at
	add_child(flash)
	effect_nodes.append(flash)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 5.0, 2.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash_material, "albedo_color:a", 0.0, 2.0)
	tween.chain().tween_callback(flash.queue_free)


func _play_bell() -> void:
	if _bell_stream == null:
		_bell_stream = _make_bell_stream()
	if _bell_player == null:
		_bell_player = AudioStreamPlayer.new()
		_bell_player.volume_db = -6.0
		add_child(_bell_player)
	_bell_player.stream = _bell_stream
	_bell_player.play()


# A struck-bell tone built from a few inharmonic partials, each dying away at its
# own rate, so it rings bright and settles into a warm hum.
func _make_bell_stream() -> AudioStreamWAV:
	var rate: int = 22050
	var count: int = int(rate * 1.8)
	# Each partial: frequency in Hz, loudness, and how fast it dies away.
	var partials: Array = [[523.0, 0.55, 1.4], [1171.0, 0.28, 2.2], [1568.0, 0.18, 3.1], [2093.0, 0.1, 4.0]]
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / float(rate)
		var sample: float = 0.0
		for partial: Array in partials:
			sample += float(partial[1]) * sin(TAU * float(partial[0]) * t) * exp(-float(partial[2]) * t)
		data.encode_s16(i * 2, clampi(int(sample * 0.45 * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
