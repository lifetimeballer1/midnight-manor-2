extends "res://scripts/game/village_terrain.gd"

# Sky layer (visual only), over the terrain layer.
#
# The camera is orthographic, so a normal sky dome never reads: this layer swaps the procedural sky
# for a screen-space shader (shaders/sky_autumn.gdshader) with a horizon that rises as the player
# tilts the camera. Top-down the village floats over a sea of drifting cloud; tilted low you get the
# autumn sky above it: gold horizon, dusk blaze, a starry night with a shaded, phased moon.
# A second flat quad (shaders/cloud_shadow.gdshader) drifts cloud shadows and sunny patches over
# the whole map, which is the part of the sky you see from the default top-down view.
#
# It reads day_blend, rain_level, the moon phase and the blood moon, and never writes to the
# simulation. The base game's own stars, moon quad and cloud shadows are shrunk to nothing, not
# hidden, because the dusk and moon layers keep fading them. Launch with --no-sky to compare.

const SKY_SHADER: String = "res://shaders/sky_autumn.gdshader"
const SHADOW_SHADER: String = "res://shaders/cloud_shadow.gdshader"
const SKY_NIGHT := {"zen": "070c1f", "hor": "1d2a55", "low": "0b1330", "lit": "5a6a98", "shade": "151d3c"}
const SKY_DAY := {"zen": "4a8cb4", "hor": "f8e0a8", "low": "ecd9a6", "lit": "fff6e0", "shade": "d3c3a0"}
const SKY_DUSK := {"zen": "4b3c70", "hor": "ff9a48", "low": "a85c4c", "lit": "ffb872", "shade": "5e3a58", "glow": "ff7a2a"}
const SKY_RAIN := Color("7d858c")
const WASH_SHADER: String = "res://shaders/golden_wash.gdshader"
const GOLDEN_SUN := Color("ff9a52")        # sun colour at the middle of dawn and dusk
const GOLDEN_AMBIENT := Color("e0a69a")
const SKY_SHADOW_SIZE := Vector2(130.0, 120.0)
const BIRD_SHADER: String = "res://shaders/sky_birds.gdshader"
const BIRDS_PER_FLOCK: int = 7                    # phones get BIRDS_PER_FLOCK_LOW
const BIRDS_PER_FLOCK_LOW: int = 5
const BIRD_HEADING := Vector2(0.9, 0.43)

var _sky_material: ShaderMaterial = null
var _sky_backdrop: MeshInstance3D = null
var _sky_wash: CanvasLayer = null
var _sky_wash_material: ShaderMaterial = null
var _sky_shadow: MeshInstance3D = null
var _sky_shadow_material: ShaderMaterial = null
var _sky_noise: ImageTexture = null
var _sky_birds: MultiMeshInstance3D = null
var _sky_birds_material: ShaderMaterial = null
var _sky_stats: Dictionary = {}                # facts recorded at build time (headless cannot read MultiMeshes back)
var _sky_sig: Array = []
var _sky_blood: float = 0.0
var _sky_alarm: float = 0.0
var _sky_flash_in: float = 6.0                 # seconds until the next lightning strike
var _sky_flash_t: float = 9.0                  # seconds since the last one (over 1.0 = idle)
var _sky_flash: float = 0.0
var _sky_params: Dictionary = {}               # last values pushed to the shader (the tests read these)


func _ready() -> void:
	super()
	if "--no-sky" not in OS.get_cmdline_user_args():
		_sky_build()


func _process(delta: float) -> void:
	super(delta)
	if _sky_material == null:
		return
	var blood_target: float = 1.0 if (sim.raid_active and Rules.is_blood_moon(Rules.clamp_phase(sim.moon_phase))) else 0.0
	_sky_blood = move_toward(_sky_blood, blood_target, delta * 0.5)
	_sky_shrink_old()
	_sky_weather_tick(delta)
	_sky_update(false)


# Lightning in heavy rain (random every 7 to 18 s, a double flicker) and the raid alarm glow.
# Both are single uniforms, set directly so a flash does not rebuild the whole palette.
func _sky_weather_tick(delta: float) -> void:
	_sky_alarm = move_toward(_sky_alarm, 1.0 if sim.raid_active else 0.0, delta * 0.4)
	if rain_level > 0.6 and _sky_flash_t > 1.0:
		_sky_flash_in -= delta
		if _sky_flash_in <= 0.0:
			_sky_flash_t = 0.0
			_sky_flash_in = randf_range(7.0, 18.0)
	var flash: float = 0.0
	if _sky_flash_t <= 1.0:
		_sky_flash_t += delta
		var t: float = _sky_flash_t
		flash = maxf(exp(-t * 14.0), 0.7 * exp(-maxf(t - 0.18, 0.0) * 16.0) * (1.0 if t > 0.18 else 0.0))
		flash *= clampf(rain_level, 0.0, 1.0)
	_sky_flash = flash
	_sky_material.set_shader_parameter("flash", flash)
	_sky_material.set_shader_parameter("alarm", _sky_alarm)
	_sky_wash_material.set_shader_parameter("flash", flash)
	_sky_wash.visible = flash > 0.01 or float(_sky_wash_material.get_shader_parameter("amount")) > 0.01


func _sky_is_phone() -> bool:
	return low_power or battery_saver or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _sky_build() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.seed = 4242
	var image: Image = noise.get_seamless_image(128, 128)
	image.adjust_bcs(1.0, 1.5, 1.0)
	image.generate_mipmaps()
	_sky_noise = ImageTexture.create_from_image(image)
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = load(SKY_SHADER)
	_sky_material.set_shader_parameter("noise_tex", _sky_noise)
	_sky_material.set_shader_parameter("detail", 0.0 if _sky_is_phone() else 1.0)
	# The sky is a quad at the far end of the camera frustum, painted in screen space (see the shader).
	var backdrop := QuadMesh.new()
	backdrop.size = Vector2(4000.0, 4000.0)
	_sky_backdrop = MeshInstance3D.new()
	_sky_backdrop.name = "SkyBackdrop"
	_sky_backdrop.mesh = backdrop
	_sky_backdrop.material_override = _sky_material
	_sky_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky_backdrop.extra_cull_margin = 16384.0
	_sky_backdrop.position = Vector3(0.0, 0.0, -(camera.far - 12.0))
	camera.add_child(_sky_backdrop)
	var quad := PlaneMesh.new()
	quad.size = SKY_SHADOW_SIZE
	_sky_shadow_material = ShaderMaterial.new()
	_sky_shadow_material.shader = load(SHADOW_SHADER)
	_sky_shadow_material.set_shader_parameter("noise_tex", _sky_noise)
	_sky_shadow_material.set_shader_parameter("detail", 0.0 if _sky_is_phone() else 1.0)
	_sky_shadow = MeshInstance3D.new()
	_sky_shadow.name = "CloudShadows"
	_sky_shadow.mesh = quad
	_sky_shadow.material_override = _sky_shadow_material
	_sky_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky_shadow.position = Vector3(0.0, 0.07, 0.0)
	add_child(_sky_shadow)
	_sky_wash_build()
	_sky_birds_build()
	_sky_shrink_old()
	_sky_update(true)


# A warm additive wash with slow rays, in a canvas layer under the HUD and over the 3D view.
func _sky_wash_build() -> void:
	_sky_wash_material = ShaderMaterial.new()
	_sky_wash_material.shader = load(WASH_SHADER)
	var rect := ColorRect.new()
	rect.name = "Wash"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _sky_wash_material
	_sky_wash = CanvasLayer.new()
	_sky_wash.name = "SkyWash"
	_sky_wash.layer = -1
	_sky_wash.visible = false
	_sky_wash.add_child(rect)
	add_child(_sky_wash)


# How golden the light is: 0 in full day or night, about 0.9 in the middle of dawn and dusk.
func _sky_golden(b: float) -> float:
	return maxf(0.0, 1.0 - pow(absf(b - 0.38) / 0.38, 2.0)) * 0.9


# Two V-shaped flocks of dark birds far above the village. All motion is in the vertex shader.
func _sky_birds_build() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri: Array in [
		[Vector3(0.0, 0.0, 0.2), Vector3(-0.06, 0.0, -0.12), Vector3(0.06, 0.0, -0.12)],
		[Vector3(-0.05, 0.0, 0.06), Vector3(-0.5, 0.0, -0.1), Vector3(-0.05, 0.0, -0.1)],
		[Vector3(0.05, 0.0, 0.06), Vector3(0.05, 0.0, -0.1), Vector3(0.5, 0.0, -0.1)],
	]:
		for corner: Vector3 in tri:
			tool.add_vertex(corner * 1.7)
	var mesh: ArrayMesh = tool.commit()
	var per_flock: int = BIRDS_PER_FLOCK_LOW if _sky_is_phone() else BIRDS_PER_FLOCK
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = per_flock * 2
	var fwd: Vector2 = BIRD_HEADING.normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var flocks: Array = [[-14.0, 9.5, 0.0], [16.0, 11.5, 0.55]]    # lateral offset, height, phase
	for flock_index in 2:
		var flock: Array = flocks[flock_index]
		for i in per_flock:
			var row: int = (i + 1) / 2
			var arm: float = 0.0 if i == 0 else (1.0 if i % 2 == 1 else -1.0)
			var lateral: float = float(flock[0]) + arm * row * 1.15 + rng.randf_range(-0.2, 0.2)
			var back: float = -row * 1.0 + rng.randf_range(-0.2, 0.2)
			var at: Vector2 = side * lateral + fwd * back
			multi.set_instance_transform(flock_index * per_flock + i, Transform3D(Basis(), Vector3(at.x, float(flock[1]) + rng.randf_range(-0.3, 0.3), at.y)))
			multi.set_instance_color(flock_index * per_flock + i, Color(float(flock[2]), rng.randf_range(0.85, 1.2), 0.0, 1.0))
	_sky_birds_material = ShaderMaterial.new()
	_sky_birds_material.shader = load(BIRD_SHADER)
	_sky_birds_material.set_shader_parameter("heading", BIRD_HEADING)
	_sky_birds = MultiMeshInstance3D.new()
	_sky_birds.name = "SkyBirds"
	_sky_birds.multimesh = multi
	_sky_birds.material_override = _sky_birds_material
	_sky_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky_birds.custom_aabb = AABB(Vector3(-120.0, 0.0, -120.0), Vector3(240.0, 24.0, 240.0))
	add_child(_sky_birds)
	_sky_stats["birds"] = multi.instance_count
	_sky_stats["flocks"] = 2


# The old star plane, moon, halo and cloud-shade quads: still alive (other layers fade them), but flat.
func _sky_shrink_old() -> void:
	var olds: Array = [stars, moon]
	if is_instance_valid(moon) and moon.has_meta("halo"):
		olds.append(moon.get_meta("halo"))
	olds.append_array(clouds)
	for node in olds:
		if is_instance_valid(node) and node is Node3D and (node as Node3D).scale != Vector3.ZERO:
			(node as Node3D).scale = Vector3.ZERO


func _sky_pick(key: String, b: float, kind: float) -> Color:
	var base: Color = Color(SKY_NIGHT[key]).lerp(Color(SKY_DAY[key]), b)
	return base.lerp(Color(SKY_DUSK[key]), kind)


# The base game's dawn and dusk light is a muddy mix of the night and day colours. Warm it up
# at the middle of the ramp, and tint the shadows' fill and the fog toward the sky's horizon.
func _apply_lighting() -> void:
	super()
	if _sky_material == null:
		return
	var b: float = clampf(day_blend, 0.0, 1.0)
	var dry: float = 1.0 - 0.6 * clampf(rain_level, 0.0, 1.0)
	# Daylight haze leans cream instead of pale blue, so the autumn palette is not washed grey.
	environment.fog_light_color = environment.fog_light_color.lerp(Color("eadcb8"), 0.45 * b * dry)
	environment.ambient_light_color = environment.ambient_light_color.lerp(Color("ffe8c4"), 0.25 * b * dry)
	var gold: float = _sky_golden(b) * dry
	if gold <= 0.0:
		return
	sun.light_color = sun.light_color.lerp(GOLDEN_SUN, gold * 0.85)
	sun.light_energy *= 1.0 + 0.3 * gold
	environment.ambient_light_color = environment.ambient_light_color.lerp(GOLDEN_AMBIENT, gold * 0.4)
	environment.fog_light_color = environment.fog_light_color.lerp(Color(SKY_DUSK["hor"]), gold * 0.35)


# Pushes the day cycle, weather and camera to the shaders, but only when something moved.
func _sky_update(force: bool) -> void:
	var b: float = clampf(day_blend, 0.0, 1.0)
	var kind: float = _sky_golden(b)
	var phase: int = Rules.clamp_phase(sim.moon_phase)
	var sig: Array = [snappedf(b, 0.004), snappedf(rain_level, 0.01), snappedf(yaw, 0.003), snappedf(tilt, 0.003), snappedf(_sky_blood, 0.01), phase, snappedf(target.x, 0.05), snappedf(target.z, 0.05)]
	if not force and sig == _sky_sig:
		return
	_sky_sig = sig
	var rain: float = clampf(rain_level, 0.0, 1.0)
	var zen: Color = _sky_pick("zen", b, kind)
	var hor: Color = _sky_pick("hor", b, kind)
	var low: Color = _sky_pick("low", b, kind)
	var lit: Color = _sky_pick("lit", b, kind)
	var shade: Color = _sky_pick("shade", b, kind)
	var grey: float = rain * 0.65
	for pair: Array in [[zen, 0], [hor, 1], [low, 2], [lit, 3], [shade, 4]]:
		var c: Color = pair[0]
		var lum: float = c.get_luminance()
		var wet: Color = Color(lum, lum, lum).lerp(SKY_RAIN * (0.45 + 0.55 * b), 0.35).darkened(0.12 * rain)
		pair[0] = c.lerp(wet, grey)
		match int(pair[1]):
			0: zen = pair[0]
			1: hor = pair[0]
			2: low = pair[0]
			3: lit = pair[0]
			4: shade = pair[0]
	var tint: Color = Rules.blood_tint()
	zen = zen.lerp(tint.darkened(0.5), 0.55 * _sky_blood)
	hor = hor.lerp(tint, 0.5 * _sky_blood)
	low = low.lerp(tint.darkened(0.45), 0.5 * _sky_blood)
	var moon_col: Color = Color(0.93, 0.95, 1.0).lerp(Color(1.0, 0.42, 0.34), _sky_blood)
	# The horizon rises as the camera tilts down toward the village: low tilt shows a wide sky.
	var horizon: float = 0.5 - (tilt - 0.32) * 0.6
	var glow_y: float = clampf(horizon, -0.1, 0.85)
	var glow_x: float = 0.5 + 0.35 * sin(yaw + 0.6)
	var night_s: float = clampf(1.0 - b * 2.2, 0.0, 1.0) * (1.0 - rain)
	var params: Dictionary = {
		"horizon": horizon,
		"zen_col": zen, "hor_col": hor, "low_col": low,
		"cloud_lit": lit, "cloud_shade": shade,
		"glow_col": Color(SKY_DUSK["glow"]).lerp(tint, 0.6 * _sky_blood),
		"glow_amt": kind * (1.0 - rain * 0.7),
		"glow_pos": Vector2(glow_x, glow_y),
		"cover": 0.42 + 0.4 * rain,
		"pan": Vector2(target.x, target.z),
		"star_amt": night_s,
		"moon_amt": night_s,
		"moon_pos": Vector2(0.5 + 0.28 * sin(yaw + 2.2), clampf(horizon - 0.17, 0.04, 0.9)),
		"moon_phase": float(phase) / float(Rules.PHASE_COUNT),
		"moon_col": moon_col,
	}
	for key: String in params:
		_sky_material.set_shader_parameter(key, params[key])
	_sky_params = params
	# Day sun patches and cloud shadows; none at night, damper and greyer in the rain.
	var day_s: float = clampf((b - 0.15) / 0.5, 0.0, 1.0)
	var shadow_strength: float = day_s * (1.0 - 0.35 * rain)
	_sky_shadow_material.set_shader_parameter("strength", shadow_strength)
	_sky_shadow_material.set_shader_parameter("warm", (1.0 - rain) * (0.6 + 0.4 * kind * 1.1))
	_sky_shadow_material.set_shader_parameter("cover", 0.4 + 0.5 * rain)
	_sky_shadow_material.set_shader_parameter("sun_col", Color("ffc766").lerp(Color("ff8f3a"), kind))
	_sky_shadow_material.set_shader_parameter("shade_col", Color("2a2142").lerp(Color("3a1c38"), kind))
	_sky_shadow.visible = shadow_strength > 0.01
	var wash: float = kind * (1.0 - 0.6 * rain)
	_sky_wash_material.set_shader_parameter("amount", wash)
	_sky_wash_material.set_shader_parameter("sun_x", glow_x)
	_sky_wash_material.set_shader_parameter("aspect", float(get_viewport().get_visible_rect().size.x) / maxf(float(get_viewport().get_visible_rect().size.y), 1.0))
	_sky_wash.visible = wash > 0.01 or _sky_flash > 0.01
	var bird_strength: float = smoothstep(0.12, 0.5, b) * (1.0 - rain)
	_sky_birds_material.set_shader_parameter("strength", bird_strength)
	_sky_birds.visible = bird_strength > 0.01
