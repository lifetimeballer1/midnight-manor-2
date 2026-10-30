extends Node

# Weather (The Manor Endures, D3), looks only: it never changes the sim, farms or raids.
# A child node of the game rather than another layer in the chain. It runs the weather clock the
# base game used for rain alone: a clear spell of 110 to 220 seconds, then a spell of rain, fog or
# snow for 45 to 90 seconds, then clear again.
#   * Rain is the game's own rain (particles, wet ground, ripples, lightning in the sky layer);
#     this node only says when it falls, through rain_target().
#   * Fog: the haze closes in, greys and softens the light, and the ground mist thickens.
#   * Snow: slow drifting flakes, a whiter, cooler light, and a patchy frost over the ground.
# The moon phase already shows in the sky layer (village_sky.gd) and is not repeated here.
# Phones and low quality get fewer flakes; battery saver keeps the fog and dusting but no flakes.

const KINDS: Array[String] = ["rain", "fog", "snow"]
const WEIGHTS: Array[float] = [0.5, 0.3, 0.2]
const CLEAR_SECONDS := Vector2(110.0, 220.0)
const SPELL_SECONDS := Vector2(45.0, 90.0)
const RAMP_SECONDS: float = 8.0
const FLAKES: int = 420
const FLAKES_LITE: int = 150
const FROST_SIZE := Vector2(96.0, 84.0)
const FROST_ALPHA: float = 0.34
const FOG_DAY := Color("b4bcc0")
const FOG_NIGHT := Color("56607a")
const SNOW_LIGHT := Color("e6eef6")

var game: Node
var kind: String = "clear"                  # the spell now: clear, rain, fog or snow
var strength: float = 1.0                   # how heavy this spell is (0.55..1)
var fog_level: float = 0.0
var snow_level: float = 0.0
var clock: float = 0.0                      # seconds left in this spell
var snow: CPUParticles3D = null
var _snow_material: StandardMaterial3D = null
var frost: MeshInstance3D = null
var _frost_material: StandardMaterial3D = null
var _shaded: Vector2 = Vector2(-1.0, -1.0)  # fog and snow last pushed to the lighting
var _rng := RandomNumberGenerator.new()


func setup(owner_game: Node) -> void:
	game = owner_game
	_rng.randomize()
	clock = _rng.randf_range(CLEAR_SECONDS.x, CLEAR_SECONDS.y)
	_build_snow()
	_build_frost()


func rain_target() -> float:
	return strength if kind == "rain" else 0.0


# Starts a spell now (tests, captures). "clear" ends the current one.
func force(next: String, seconds: float = 60.0, heavy: float = 1.0) -> void:
	kind = next
	strength = heavy
	clock = seconds


func _process(delta: float) -> void:
	if game == null:
		return
	clock -= delta
	if clock <= 0.0:
		if kind == "clear":
			kind = _pick()
			strength = _rng.randf_range(0.55, 1.0)
			clock = _rng.randf_range(SPELL_SECONDS.x, SPELL_SECONDS.y)
		else:
			kind = "clear"
			clock = _rng.randf_range(CLEAR_SECONDS.x, CLEAR_SECONDS.y)
	# A new spell waits for the last one to clear away, so rain never turns straight into snow.
	var wet: bool = float(game.rain_level) > 0.02
	var fog_goal: float = strength if kind == "fog" and snow_level <= 0.01 and not wet else 0.0
	var snow_goal: float = strength if kind == "snow" and fog_level <= 0.01 and not wet else 0.0
	fog_level = move_toward(fog_level, fog_goal, delta / RAMP_SECONDS)
	snow_level = move_toward(snow_level, snow_goal, delta / RAMP_SECONDS)
	_tend_snow()
	var now := Vector2(snappedf(fog_level, 0.01), snappedf(snow_level, 0.01))
	if now != _shaded:
		_shaded = now
		_dust_ground()
		if game.has_method("_apply_lighting"):
			game._apply_lighting()


func _pick() -> String:
	var roll: float = _rng.randf()
	for index in KINDS.size():
		roll -= WEIGHTS[index]
		if roll <= 0.0:
			return KINDS[index]
	return KINDS[0]


# Called at the end of the game's lighting pass (village_polish.gd), so it has the last word.
func shade(environment: Environment, sun: DirectionalLight3D, day: float) -> void:
	var f: float = clampf(fog_level, 0.0, 1.0)
	if f > 0.0:
		environment.fog_depth_begin = lerpf(environment.fog_depth_begin, 16.0, f)
		environment.fog_depth_end = lerpf(environment.fog_depth_end, 140.0, f)
		environment.fog_density = lerpf(environment.fog_density, 0.62, f)
		environment.fog_light_color = environment.fog_light_color.lerp(FOG_NIGHT.lerp(FOG_DAY, day), 0.6 * f)
		sun.light_energy *= 1.0 - 0.35 * f
		environment.ambient_light_energy *= 1.0 + 0.1 * f
	var s: float = clampf(snow_level, 0.0, 1.0)
	if s > 0.0:
		environment.fog_depth_begin = lerpf(environment.fog_depth_begin, 24.0, s)
		environment.fog_density = clampf(environment.fog_density + 0.15 * s, 0.0, 1.0)
		environment.fog_light_color = environment.fog_light_color.lerp(SNOW_LIGHT.darkened(0.6 * (1.0 - day)), 0.4 * s)
		environment.ambient_light_color = environment.ambient_light_color.lerp(SNOW_LIGHT, 0.3 * s)
		environment.ambient_light_energy *= 1.0 + 0.12 * s
		sun.light_color = sun.light_color.lerp(SNOW_LIGHT, 0.3 * s)
		sun.light_energy *= 1.0 - 0.15 * s
	if is_instance_valid(game.mist):
		game.mist.amount = maxi(1, int(game.mist_base) + int(14.0 * float(game.rain_level)) + int(16.0 * f))
		if f > 0.2 and not game.battery_saver:
			game.mist.visible = true


func _dust_ground() -> void:
	if not is_instance_valid(frost):
		return
	var s: float = clampf(snow_level, 0.0, 1.0)
	frost.visible = s > 0.01
	_frost_material.albedo_color = Color(0.94, 0.97, 1.0, FROST_ALPHA * s)


# A patchy frost sheet laid just over the ground: thicker in some places, bare in others.
func _build_frost() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	noise.seed = 1212
	var image: Image = noise.get_seamless_image(128, 128)
	image.convert(Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var n: float = image.get_pixel(x, y).r
			image.set_pixel(x, y, Color(1, 1, 1, 0.35 + 0.65 * smoothstep(0.2, 0.85, n)))
	image.generate_mipmaps()
	_frost_material = StandardMaterial3D.new()
	_frost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frost_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_frost_material.albedo_texture = ImageTexture.create_from_image(image)
	_frost_material.uv1_scale = Vector3(3.0, 2.6, 1.0)
	_frost_material.roughness = 0.9
	_frost_material.albedo_color = Color(0.94, 0.97, 1.0, 0.0)
	var plane := PlaneMesh.new()
	plane.size = FROST_SIZE
	frost = MeshInstance3D.new()
	frost.name = "Frost"
	frost.mesh = plane
	frost.material_override = _frost_material
	frost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frost.position = Vector3(0.0, 0.06, 0.0)
	frost.visible = false
	game.add_child(frost)


func _build_snow() -> void:
	_snow_material = StandardMaterial3D.new()
	_snow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_snow_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_snow_material.billboard_keep_scale = true
	_snow_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_snow_material.disable_receive_shadows = true
	var flake := QuadMesh.new()
	flake.size = Vector2(0.2, 0.2)
	flake.material = _snow_material
	snow = CPUParticles3D.new()
	snow.name = "Snow"
	snow.mesh = flake
	snow.amount = FLAKES_LITE if game._quality_lite() else FLAKES
	snow.lifetime = 5.5
	snow.preprocess = 5.5
	snow.local_coords = false
	snow.position = Vector3(0, 12, 0)
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(34, 0.2, 28)
	snow.direction = Vector3(0.25, -1, 0.1)
	snow.spread = 25.0
	snow.gravity = Vector3(0, -1.2, 0)
	snow.initial_velocity_min = 1.2
	snow.initial_velocity_max = 2.0
	snow.angular_velocity_min = -90.0
	snow.angular_velocity_max = 90.0
	snow.scale_amount_min = 0.6
	snow.scale_amount_max = 1.3
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	snow.emitting = false
	snow.visible = false
	game.add_child(snow)


func _tend_snow() -> void:
	if not is_instance_valid(snow):
		return
	var on: bool = snow_level > 0.02 and not game.battery_saver
	if snow.emitting != on:
		snow.emitting = on
		snow.visible = on
		if on:
			snow.amount = FLAKES_LITE if game._quality_lite() else FLAKES
	if on:
		_snow_material.albedo_color = Color(1.0, 1.0, 1.0, 0.85 * clampf(snow_level, 0.0, 1.0))
