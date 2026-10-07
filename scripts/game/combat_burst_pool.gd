extends Node3D

const CAPACITY: int = 12
var entries: Array[Dictionary] = []
var dropped: int = 0
var paused: bool = false:
	set(value):
		paused = value
		for entry: Dictionary in entries:
			entry["node"].speed_scale = 0.0 if value else 1.0


func _ready() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in 32:
		for y in 32:
			var radius: float = Vector2(x - 15.5, y - 15.5).length() / 15.5
			image.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0.0, 1.0 - radius), 1.5)))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = ImageTexture.create_from_image(image)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = material
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	for slot in CAPACITY:
		var emitter := CPUParticles3D.new()
		emitter.name = "Burst%d" % slot
		emitter.emitting = false
		emitter.visible = false
		emitter.mesh = mesh
		emitter.color_ramp = fade
		emitter.local_coords = false
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(emitter)
		entries.append({"node": emitter, "remaining": 0.0})


func spawn(at: Vector3, tint: Color = Color("d4b275"), count: int = 8, size: float = 1.0, rise: bool = false) -> CPUParticles3D:
	if not at.is_finite() or not is_finite(size) or size <= 0.0 or paused:
		return null
	for entry: Dictionary in entries:
		if float(entry["remaining"]) > 0.0:
			continue
		var emitter: CPUParticles3D = entry["node"]
		emitter.amount = clampi(count, 1, 24)
		emitter.lifetime = 0.9 if rise else 0.6
		emitter.direction = Vector3.UP
		emitter.spread = 45.0 if rise else 55.0
		emitter.initial_velocity_min = 1.2 if rise else 2.5
		emitter.initial_velocity_max = 2.2 if rise else 5.0
		emitter.gravity = Vector3(0, 1.5, 0) if rise else Vector3(0, -9, 0)
		emitter.scale_amount_min = 0.14 * minf(size, 4.0)
		emitter.scale_amount_max = 0.28 * minf(size, 4.0)
		emitter.color = tint
		emitter.position = at
		emitter.speed_scale = 1.0
		emitter.visible = true
		entry["remaining"] = emitter.lifetime + 0.25
		emitter.restart()
		emitter.emitting = true
		return emitter
	dropped += 1
	return null


func active_count() -> int:
	var count: int = 0
	for entry: Dictionary in entries:
		if float(entry["remaining"]) > 0.0: count += 1
	return count


func _process(delta: float) -> void:
	if paused: return
	for entry: Dictionary in entries:
		if float(entry["remaining"]) <= 0.0: continue
		entry["remaining"] = maxf(0.0, float(entry["remaining"]) - delta)
		if entry["remaining"] == 0.0:
			entry["node"].emitting = false
			entry["node"].visible = false


func reset() -> void:
	for entry: Dictionary in entries:
		entry["remaining"] = 0.0
		entry["node"].emitting = false
		entry["node"].visible = false
		entry["node"].speed_scale = 0.0 if paused else 1.0
