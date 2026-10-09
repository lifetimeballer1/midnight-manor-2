extends "res://scripts/game/village_warsong.gd"

# Terrain layer (visual only), over the warsong layer: early-autumn ground.
#
# The old slab keeps its plain material (rain, expansion and the lip code all read it), so
# the painted ground is one extra quad just above it. Its shader (shaders/terrain_autumn.gdshader)
# turns the grass from lush green in the village to wheat gold toward the map edge, scatters
# fallen leaves, and trampled dirt gathers around buildings. The old soft colour discs and cone
# tufts are hidden, because they would tint the new ground.
#
# Phone budget: the shader reads one 256px noise texture (cached, built natively once) and a 40x32
# mask that is rewritten only when buildings or trails change (polled twice a second, at most
# 1280 pixels). Nothing here touches the simulation or the save data.

const TERRAIN_SHADER: String = "res://shaders/terrain_autumn.gdshader"
const TERRAIN_SIZE := Vector2(40.0, 32.0)
const TERRAIN_MASK := Vector2i(40, 32)            # two texels per tile
const TERRAIN_LIFT: float = 0.003
const TERRAIN_POLL: float = 0.5
const TERRAIN_LIP_COLOR := Color("8a8a4c")        # base lip, warmed from the old green
const GRASS_SHADER: String = "res://shaders/grass_blades.gdshader"
const GRASS_CLUMPS: int = 1500                     # phones get the _LOW counts
const GRASS_CLUMPS_LOW: int = 800
const GRASS_TALL: int = 130
const GRASS_TALL_LOW: int = 70
const GRASS_REACH := Vector2(19.2, 15.2)           # clumps stay inside the lip
const GRASS_PUSHERS: int = 12
const GRASS_PUSH_RADIUS: float = 0.85
const GRASS_PUSH_POLL: float = 0.12
const LEAF_COUNT: int = 22                          # falling leaves; phones get LEAF_COUNT_LOW
const LEAF_COUNT_LOW: int = 12
const MIST_COUNT: int = 9                           # ground mist patches; phones get MIST_COUNT_LOW
const MIST_COUNT_LOW: int = 5
const SLAB_TINT := Color(0.8, 0.79, 0.74)
const SLAB_GRASS_CLUMPS: int = 420                 # per claimed plot; phones get half
const CLUTTER_CLEAR: float = 0.3                    # mask value above which clutter is hidden
const TREE_FALL_TONES: Array[String] = ["7f8a22", "9a8a1c", "c99a1a", "e0a924", "d9741a", "e8861e", "a8381a", "c14a1c", "8e2a14"]

var _terrain_mesh: MeshInstance3D = null
var _terrain_material: ShaderMaterial = null
var _terrain_mask_image: Image = null
var _terrain_mask_texture: ImageTexture = null
var _terrain_signature: int = -1
var _terrain_clock: float = 0.0
var _terrain_wet: float = -1.0
var _terrain_noise: Image = null
var _grass_material: ShaderMaterial = null
var _grass_nodes: Array[MultiMeshInstance3D] = []
var _grass_push_clock: float = 0.0
var _grass_push_last: PackedVector3Array = PackedVector3Array()
var _terrain_night: float = -1.0
var _terrain_time: float = 0.0
var _terrain_slab_tex: ImageTexture = null
var _leaves: CPUParticles3D = null
var _leaf_gust_clock: float = 0.0
var _mist_root: Node3D = null
var _mist_patches: Array[Dictionary] = []
var _clutter_sets: Array[Dictionary] = []    # {"multi", "xforms", "pos"} - hidden where the mask says ground is cleared
var _glow_material: StandardMaterial3D = null
var _grass_mesh: ArrayMesh = null
var _slab_grass: Dictionary = {}              # plot id -> MultiMeshInstance3D of grass on claimed land
var _skirt_rocks: Dictionary = {}             # base edge name -> rocks along that cliff face
var _terrain_stats: Dictionary = {}          # placement facts recorded at build time (headless cannot read MultiMeshes back)


func _ready() -> void:
	super()
	if "--no-terrain" not in OS.get_cmdline_user_args():
		_terrain_build()


func _process(delta: float) -> void:
	super(delta)
	if _terrain_material == null:
		return
	if absf(rain_level - _terrain_wet) > 0.004:
		_terrain_wet = rain_level
		_terrain_material.set_shader_parameter("wet", rain_level)
		if _grass_material != null:
			_grass_material.set_shader_parameter("wet", rain_level)
	var night: float = 1.0 - clampf(day_blend, 0.0, 1.0)
	if absf(night - _terrain_night) > 0.01:
		_terrain_night = night
		_terrain_apply_night()
	if not sim.paused:
		_terrain_time += delta
	_leaf_tick(delta)
	_mist_tick()
	_grass_push_clock -= delta
	if _grass_push_clock <= 0.0 and _grass_material != null:
		_grass_push_clock = GRASS_PUSH_POLL
		_grass_update_pushers()
	_terrain_clock -= delta
	if _terrain_clock <= 0.0:
		_terrain_clock = TERRAIN_POLL
		_terrain_refresh_mask(false)
		_terrain_autumn_slabs()


func _terrain_build() -> void:
	_terrain_hide_old_ground()
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.045
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.seed = 11
	var noise_image: Image = noise.get_seamless_image(256, 256)
	noise_image.adjust_bcs(1.0, 1.35, 1.0)
	var noise_texture := ImageTexture.create_from_image(noise_image)
	_terrain_mask_image = Image.create(TERRAIN_MASK.x, TERRAIN_MASK.y, false, Image.FORMAT_RG8)
	_terrain_mask_texture = ImageTexture.create_from_image(_terrain_mask_image)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = load(TERRAIN_SHADER)
	_terrain_material.set_shader_parameter("noise_tex", noise_texture)
	_terrain_material.set_shader_parameter("mask_tex", _terrain_mask_texture)
	_terrain_material.set_shader_parameter("map_size", TERRAIN_SIZE)
	var plane := PlaneMesh.new()
	plane.size = TERRAIN_SIZE
	_terrain_mesh = MeshInstance3D.new()
	_terrain_mesh.name = "AutumnGround"
	_terrain_mesh.mesh = plane
	_terrain_mesh.material_override = _terrain_material
	_terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_terrain_mesh.position = Vector3(0.0, TERRAIN_LIFT, 0.0)
	add_child(_terrain_mesh)
	_terrain_refresh_mask(true)
	_terrain_noise = noise_image
	_grass_build()
	_terrain_recolor_trees()
	_leaves_build()
	_clutter_build()
	_mist_build()
	_slab_build()
	_skirt_build()
	_terrain_apply_night()


# The 34 colour discs and the 40 cone tufts were the old ground dressing.
func _terrain_hide_old_ground() -> void:
	for part: MeshInstance3D in ground_parts:
		if is_instance_valid(part) and part.mesh is PlaneMesh:
			part.visible = false
	for child: Node in get_children():
		var multi := child as MultiMeshInstance3D
		if multi != null and multi.multimesh != null and multi.multimesh.mesh is CylinderMesh and multi.multimesh.instance_count == 40:
			multi.visible = false
	for index: int in [2, 3, 4, 5]:
		if index < ground_parts.size() and is_instance_valid(ground_parts[index]):
			var lip := ground_parts[index].material_override as StandardMaterial3D
			if lip != null:
				lip.albedo_color = TERRAIN_LIP_COLOR


func _terrain_signature_now() -> int:
	var value: int = sim.buildings.size() * 7919 + sim.living.revision * 31 + sim.living.cells.size() * 104729
	for b: Dictionary in sim.buildings:
		value = (value * 31 + int(b["x"]) * 53 + int(b["y"]) * 17 + int(b["size"])) & 0x7fffffff
	return value


# R = trampled dirt (footprints plus a soft apron), G = ground kept clear of grass (adds roads).
func _terrain_refresh_mask(force: bool) -> void:
	var signature: int = _terrain_signature_now()
	if not force and signature == _terrain_signature:
		return
	_terrain_signature = signature
	var w: int = TERRAIN_MASK.x
	var h: int = TERRAIN_MASK.y
	var foot := PackedFloat32Array()
	foot.resize(w * h)
	for b: Dictionary in sim.buildings:
		var size: int = int(b["size"])
		for tx in size:
			for ty in size:
				_terrain_stamp(foot, int(b["x"]) + tx, int(b["y"]) + ty, 1.0)
	var apron := _terrain_dilate(foot, 0.7)
	apron = _terrain_dilate(apron, 0.7)
	var clear := foot.duplicate()
	for id: Variant in sim.living.cells.keys():
		var parts: PackedStringArray = str(id).split(",")
		if parts.size() == 2:
			_terrain_stamp(clear, int(parts[0]), int(parts[1]), 1.0)
	clear = _terrain_dilate(clear, 0.8)
	for y in h:
		for x in w:
			var i: int = y * w + x
			_terrain_mask_image.set_pixel(x, y, Color(clampf(maxf(foot[i], apron[i]) * 0.9, 0.0, 1.0), clampf(maxf(clear[i], apron[i]), 0.0, 1.0), 0.0))
	_terrain_mask_texture.update(_terrain_mask_image)
	_clutter_apply_mask()


func _terrain_stamp(field: PackedFloat32Array, tile_x: int, tile_y: int, value: float) -> void:
	for dx in 2:
		for dy in 2:
			var x: int = tile_x * 2 + dx
			var y: int = tile_y * 2 + dy
			if x >= 0 and y >= 0 and x < TERRAIN_MASK.x and y < TERRAIN_MASK.y:
				field[y * TERRAIN_MASK.x + x] = maxf(field[y * TERRAIN_MASK.x + x], value)


func _terrain_dilate(field: PackedFloat32Array, falloff: float) -> PackedFloat32Array:
	var w: int = TERRAIN_MASK.x
	var h: int = TERRAIN_MASK.y
	var out := field.duplicate()
	for y in h:
		for x in w:
			var best: float = field[y * w + x]
			if x > 0: best = maxf(best, field[y * w + x - 1] * falloff)
			if x < w - 1: best = maxf(best, field[y * w + x + 1] * falloff)
			if y > 0: best = maxf(best, field[(y - 1) * w + x] * falloff)
			if y < h - 1: best = maxf(best, field[(y + 1) * w + x] * falloff)
			out[y * w + x] = best
	return out


func _terrain_is_phone() -> bool:
	return low_power or battery_saver or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


# Same large-scale noise the ground shader reads (wp * 0.022 + offset), so blade tint follows the ground.
func _terrain_noise_at(x: float, z: float) -> float:
	var size: int = _terrain_noise.get_width()
	var u: float = fposmod(x * 0.022 + 0.13, 1.0)
	var v: float = fposmod(z * 0.022 + 0.71, 1.0)
	return _terrain_noise.get_pixel(int(u * size) % size, int(v * size) % size).r


# One clump = four blades (3 triangles each); UV.y holds the height fraction the shader bends by.
func _grass_clump_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var half_width: float = 0.04
	for blade in 4:
		var spin := Basis(Vector3.UP, blade * (TAU / 4.0) + 0.4)
		var root: Vector3 = spin * Vector3(0.0, 0.0, 0.07)
		var lean: Vector3 = spin * Vector3(0.0, 0.0, 0.10)
		var side: Vector3 = spin * Vector3(half_width, 0.0, 0.0)
		var base_l: Vector3 = root - side
		var base_r: Vector3 = root + side
		var mid_c: Vector3 = root + Vector3(0.0, 0.55, 0.0) + lean * 0.35
		var mid_l: Vector3 = mid_c - side * 0.7
		var mid_r: Vector3 = mid_c + side * 0.7
		var tip_p: Vector3 = root + Vector3(0.0, 1.0, 0.0) + lean
		var tris: Array = [
			[base_l, base_r, mid_l, 0.0, 0.0, 0.55],
			[base_r, mid_r, mid_l, 0.0, 0.55, 0.55],
			[mid_l, mid_r, tip_p, 0.55, 0.55, 1.0]]
		for tri: Array in tris:
			for k in 3:
				verts.append(tri[k])
				uvs.append(Vector2(0.0, float(tri[3 + k])))
				normals.append(Vector3.UP)
				colors.append(Color.WHITE)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _grass_tip_color(rng: RandomNumberGenerator, turn: float, tall: bool) -> Color:
	var pick: float = rng.randf()
	var hex: String
	if tall:
		hex = "d9c27a" if pick < 0.7 else "c9a24a"
	elif pick < turn * 0.78:
		hex = "d3a02a" if rng.randf() < 0.7 else "b8741f"
	elif pick > 0.965:
		hex = "9a4a1c"
	else:
		hex = "88a02e" if rng.randf() < 0.6 else "6f9226"
	return Color(hex).darkened(rng.randf_range(0.0, 0.18)).srgb_to_linear()


func _grass_build() -> void:
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = load(GRASS_SHADER)
	_grass_material.set_shader_parameter("mask_tex", _terrain_mask_texture)
	_grass_material.set_shader_parameter("map_size", TERRAIN_SIZE)
	_grass_push_last.resize(GRASS_PUSHERS)
	_grass_material.set_shader_parameter("pushers", _grass_push_last)
	var phone: bool = _terrain_is_phone()
	var mesh: ArrayMesh = _grass_clump_mesh()
	_grass_mesh = mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 313
	for tall: bool in [false, true]:
		var want: int = (GRASS_TALL_LOW if phone else GRASS_TALL) if tall else (GRASS_CLUMPS_LOW if phone else GRASS_CLUMPS)
		var xforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		var guard: int = 0
		var outside: int = 0
		var lowest_edge: float = 9.0
		while xforms.size() < want and guard < want * 12:
			guard += 1
			var x: float = rng.randf_range(-GRASS_REACH.x, GRASS_REACH.x)
			var z: float = rng.randf_range(-GRASS_REACH.y, GRASS_REACH.y)
			var edge: float = maxf(absf(x) / 20.0, absf(z) / 16.0)
			if tall and edge < 0.82:
				continue
			var turn: float = clampf(smoothstep(0.30, 1.05, edge + (_terrain_noise_at(x, z) - 0.5) * 0.75), 0.0, 1.0)
			var height: float = rng.randf_range(0.85, 1.35) if tall else rng.randf_range(0.34, 0.62)
			var width: float = rng.randf_range(1.0, 1.5) * (1.7 if tall else 1.0)
			var spin := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
			var scaled: Basis = spin * Basis.from_scale(Vector3(width, height, width))
			xforms.append(Transform3D(scaled, Vector3(x, TERRAIN_LIFT, z)))
			lowest_edge = minf(lowest_edge, edge)
			if absf(x) > GRASS_REACH.x or absf(z) > GRASS_REACH.y:
				outside += 1
			colors.append(_grass_tip_color(rng, turn, tall))
		var node: MultiMeshInstance3D = _add_multimesh(mesh, _grass_material, xforms, colors, self, false)
		node.name = "AutumnPampas" if tall else "AutumnGrass"
		_terrain_stats["pampas" if tall else "clumps"] = {"count": xforms.size(), "outside": outside, "lowest_edge": lowest_edge}
		node.extra_cull_margin = 1.5
		_grass_nodes.append(node)


# Walkers (villagers and raiders alike) flatten the blades around their feet.
func _grass_update_pushers() -> void:
	var list := PackedVector3Array()
	list.resize(GRASS_PUSHERS)
	var count: int = 0
	for actor: Node in actor_layer.get_children():
		var model := actor as Node3D
		if model == null or not model.visible or count >= GRASS_PUSHERS:
			continue
		list[count] = Vector3(model.position.x, model.position.z, GRASS_PUSH_RADIUS)
		count += 1
	if list != _grass_push_last:
		_grass_push_last = list
		_grass_material.set_shader_parameter("pushers", list)


# Round trees and shrubs turn: calm gold near the village, hotter oranges and crimson toward the far edge.
func _terrain_recolor_trees() -> void:
	var scenery: Node = get_node_or_null("Scenery")
	if scenery == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var warm: int = 0
	var cool: int = 0
	for child: Node in scenery.get_children():
		var multi := child as MultiMeshInstance3D
		if multi == null or multi.multimesh == null or not multi.multimesh.use_colors:
			continue
		var sphere := multi.multimesh.mesh as SphereMesh
		if sphere == null or sphere.radius < 0.4 or sphere.radius > 0.9:
			continue                                   # pines stay evergreen, rocks stay rocks
		var shrub: bool = sphere.radius < 0.6
		for index in multi.multimesh.instance_count:
			var origin: Vector3 = multi.multimesh.get_instance_transform(index).origin
			var far: float = clampf((maxf(absf(origin.x) / 41.5, absf(origin.z) / 37.5) - 1.0) / 0.25, 0.0, 1.0)
			var color: Color = _terrain_fall_color(rng, far, shrub)
			multi.multimesh.set_instance_color(index, color)
			if color.r > color.g:
				warm += 1
			else:
				cool += 1
	_terrain_stats["trees"] = {"warm": warm, "cool": cool}


# Calm gold near the village, hotter oranges and crimson toward the far edge. Returns a linear colour for instance tints.
func _terrain_fall_color(rng: RandomNumberGenerator, far: float, shrub: bool) -> Color:
	var tone: int
	var roll: float = rng.randf()
	if roll < 0.18 * (1.0 - far):
		tone = rng.randi_range(0, 1)                 # still olive, just starting to turn
	elif roll < 0.55:
		tone = rng.randi_range(2, 3)                 # gold
	elif roll < 0.8 - 0.12 * far:
		tone = rng.randi_range(4, 5)                 # orange
	else:
		tone = rng.randi_range(6, 8)                 # rust and crimson
	if shrub and rng.randf() < 0.35:
		tone = rng.randi_range(0, 1)
	return Color(TREE_FALL_TONES[tone]).darkened(rng.randf_range(0.0, 0.14)).srgb_to_linear()


func _terrain_apply_night() -> void:
	var night: float = maxf(_terrain_night, 0.0)
	if _terrain_material != null:
		_terrain_material.set_shader_parameter("night_cool", night)
	if _grass_material != null:
		_grass_material.set_shader_parameter("night", night)
	if _glow_material != null:
		_glow_material.emission_energy_multiplier = 0.15 + 1.9 * night
	for patch: Dictionary in _mist_patches:
		var material := (patch["node"] as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color.a = float(patch["alpha"]) * (0.55 + 0.75 * night)


# --- falling leaves ---------------------------------------------------------

func _leaves_build() -> void:
	_leaves = CPUParticles3D.new()
	_leaves.name = "FallingLeaves"
	_leaves.amount = LEAF_COUNT_LOW if _terrain_is_phone() else LEAF_COUNT
	_leaves.lifetime = 7.0
	_leaves.preprocess = 6.0
	_leaves.local_coords = false
	_leaves.position = Vector3(0.0, 4.6, 0.0)
	_leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_leaves.emission_box_extents = Vector3(21.0, 0.4, 17.0)
	_leaves.direction = Vector3(0.7, -0.2, 0.4)
	_leaves.spread = 40.0
	_leaves.initial_velocity_min = 0.3
	_leaves.initial_velocity_max = 0.9
	_leaves.gravity = Vector3(0.12, -0.5, 0.07)
	_leaves.damping_min = 0.15
	_leaves.damping_max = 0.45
	_leaves.tangential_accel_min = -0.5
	_leaves.tangential_accel_max = 0.5
	_leaves.particle_flag_rotate_y = true
	_leaves.angle_min = 0.0
	_leaves.angle_max = 360.0
	_leaves.angular_velocity_min = -160.0
	_leaves.angular_velocity_max = 160.0
	_leaves.scale_amount_min = 0.8
	_leaves.scale_amount_max = 1.5
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.12, 1.0))
	fade.add_point(Vector2(0.82, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	_leaves.scale_amount_curve = fade
	var tones := Gradient.new()
	tones.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	tones.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75])
	tones.colors = PackedColorArray([Color("d9741a").srgb_to_linear(), Color("c99a1a").srgb_to_linear(), Color("b02e17").srgb_to_linear(), Color("e0a924").srgb_to_linear()])
	_leaves.color_initial_ramp = tones
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.12)
	quad.orientation = PlaneMesh.FACE_Y
	_leaves.mesh = quad
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = UI.soft_disc_texture()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	_leaves.material_override = material
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_leaves)


# The same big gust that sweeps the grass shoves the leaves along; rain and pause calm them.
func _leaf_tick(delta: float) -> void:
	if _leaves == null:
		return
	var speed: float = 0.0001 if sim.paused else 1.0
	if not is_equal_approx(_leaves.speed_scale, speed):
		_leaves.speed_scale = speed
	var want_on: bool = rain_level < 0.6
	if _leaves.emitting != want_on:
		_leaves.emitting = want_on
	_leaf_gust_clock -= delta
	if _leaf_gust_clock <= 0.0:
		_leaf_gust_clock = 0.25
		var big: float = smoothstep(0.62, 1.0, 0.5 + 0.5 * sin(_terrain_time * 0.31))
		_leaves.gravity = Vector3(0.12 + 0.9 * big, -0.5 + 0.2 * big, 0.07 + 0.5 * big)


# --- ground clutter ---------------------------------------------------------

func _clutter_spot(rng: RandomNumberGenerator, min_edge: float) -> Vector3:
	for attempt in 40:
		var x: float = rng.randf_range(-GRASS_REACH.x, GRASS_REACH.x)
		var z: float = rng.randf_range(-GRASS_REACH.y, GRASS_REACH.y)
		var edge: float = maxf(absf(x) / 20.0, absf(z) / 16.0)
		if edge < min_edge:
			continue
		var cleared: float = _terrain_mask_image.get_pixel(clampi(int(x + 20.0), 0, TERRAIN_MASK.x - 1), clampi(int(z + 16.0), 0, TERRAIN_MASK.y - 1)).g
		if cleared > CLUTTER_CLEAR:
			continue
		return Vector3(x, TERRAIN_LIFT, z)
	return Vector3(INF, 0.0, 0.0)


func _clutter_add(mesh: Mesh, material: Material, xforms: Array[Transform3D], colors: Array[Color], node_name: String) -> void:
	if xforms.is_empty():
		return
	var node: MultiMeshInstance3D = _add_multimesh(mesh, material, xforms, colors, self, false)
	node.name = node_name
	var positions := PackedVector2Array()
	for xform: Transform3D in xforms:
		positions.append(Vector2(xform.origin.x, xform.origin.z))
	_clutter_sets.append({"multi": node.multimesh, "xforms": xforms, "pos": positions})


func _clutter_baked(mesh: Mesh, at: Transform3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(mesh, 0, at)
	return st.commit()


func _clutter_build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var lit := StandardMaterial3D.new()
	lit.vertex_color_use_as_albedo = true
	lit.roughness = 1.0
	var stem_material := StandardMaterial3D.new()
	stem_material.albedo_color = Color("d8caa4")
	stem_material.roughness = 0.9
	_glow_material = StandardMaterial3D.new()
	_glow_material.albedo_color = Color("7fd6bc")
	_glow_material.roughness = 0.7
	_glow_material.emission_enabled = true
	_glow_material.emission = Color("56e0b4")
	_glow_material.emission_energy_multiplier = 0.15
	# Mushrooms: clusters of two to four, in the dark fringe near the edge; a quarter glow at night.
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.032
	stem_mesh.bottom_radius = 0.05
	stem_mesh.height = 0.15
	stem_mesh.radial_segments = 5
	stem_mesh.rings = 1
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.1
	cap_mesh.height = 0.11
	cap_mesh.radial_segments = 7
	cap_mesh.rings = 3
	var stems_baked: ArrayMesh = _clutter_baked(stem_mesh, Transform3D(Basis(), Vector3(0.0, 0.075, 0.0)))
	var caps_baked: ArrayMesh = _clutter_baked(cap_mesh, Transform3D(Basis(), Vector3(0.0, 0.17, 0.0)))
	var stem_x: Array[Transform3D] = []
	var cap_x: Array[Transform3D] = []
	var cap_c: Array[Color] = []
	var glow_x: Array[Transform3D] = []
	var cap_tones: Array[String] = ["b5482a", "d08a3c", "c9b087", "8a5a3a", "a8381a"]
	for cluster in 12:
		var centre: Vector3 = _clutter_spot(rng, 0.8)
		if is_inf(centre.x):
			continue
		var glows: bool = cluster % 4 == 0
		for k in rng.randi_range(2, 4):
			var offset := Vector3(rng.randf_range(-0.22, 0.22), 0.0, rng.randf_range(-0.22, 0.22))
			var size: float = rng.randf_range(0.7, 1.5)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
			var xform := Transform3D(basis, centre + offset)
			stem_x.append(xform)
			if glows:
				glow_x.append(xform)
			else:
				cap_x.append(xform)
				cap_c.append(Color(cap_tones[rng.randi() % cap_tones.size()]).srgb_to_linear())
	_clutter_add(stems_baked, stem_material, stem_x, [] as Array[Color], "AutumnMushroomStems")
	_clutter_add(caps_baked, lit, cap_x, cap_c, "AutumnMushroomCaps")
	_clutter_add(caps_baked, _glow_material, glow_x, [] as Array[Color], "AutumnGlowCaps")
	# Fallen branches.
	var branch_mesh := BoxMesh.new()
	branch_mesh.size = Vector3(0.75, 0.05, 0.06)
	var branch_x: Array[Transform3D] = []
	var branch_c: Array[Color] = []
	for index in 14:
		var at: Vector3 = _clutter_spot(rng, 0.55)
		if is_inf(at.x):
			continue
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(rng.randf_range(0.7, 1.6), 1.0, 1.0))
		branch_x.append(Transform3D(basis, at + Vector3(0.0, 0.025, 0.0)))
		branch_c.append(Color("4a3524").darkened(rng.randf_range(0.0, 0.3)).srgb_to_linear())
	_clutter_add(branch_mesh, lit, branch_x, branch_c, "AutumnBranches")
	# Acorns and pine cones: tiny specks under the trees.
	var acorn_mesh := SphereMesh.new()
	acorn_mesh.radius = 0.04
	acorn_mesh.height = 0.07
	acorn_mesh.radial_segments = 5
	acorn_mesh.rings = 2
	var acorn_x: Array[Transform3D] = []
	var acorn_c: Array[Color] = []
	for index in 36:
		var at: Vector3 = _clutter_spot(rng, 0.6)
		if is_inf(at.x):
			continue
		acorn_x.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)), at + Vector3(0.0, 0.03, 0.0)))
		acorn_c.append(Color("7a5230").darkened(rng.randf_range(0.0, 0.3)).srgb_to_linear())
	_clutter_add(acorn_mesh, lit, acorn_x, acorn_c, "AutumnAcorns")
	# Pumpkins, a few near the edge, and soft piles of raked leaves.
	var pumpkin_mesh := SphereMesh.new()
	pumpkin_mesh.radius = 0.2
	pumpkin_mesh.height = 0.3
	pumpkin_mesh.radial_segments = 8
	pumpkin_mesh.rings = 4
	var pumpkin_x: Array[Transform3D] = []
	var pumpkin_c: Array[Color] = []
	for index in 6:
		var at: Vector3 = _clutter_spot(rng, 0.7)
		if is_inf(at.x):
			continue
		pumpkin_x.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.8, 1.35)), at + Vector3(0.0, 0.13, 0.0)))
		pumpkin_c.append(Color("e8921c").darkened(rng.randf_range(0.0, 0.2)).srgb_to_linear())
	_clutter_add(pumpkin_mesh, lit, pumpkin_x, pumpkin_c, "AutumnPumpkins")
	var pile_mesh := SphereMesh.new()
	pile_mesh.radius = 0.3
	pile_mesh.height = 0.34
	pile_mesh.radial_segments = 7
	pile_mesh.rings = 3
	var pile_x: Array[Transform3D] = []
	var pile_c: Array[Color] = []
	var pile_tones: Array[String] = ["e0a924", "c99a1a", "d9961a", "d9741a"]
	for index in 7:
		var at: Vector3 = _clutter_spot(rng, 0.55)
		if is_inf(at.x):
			continue
		pile_x.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(rng.randf_range(0.8, 1.5), 1.0, rng.randf_range(0.8, 1.3))), at + Vector3(0.0, 0.02, 0.0)))
		pile_c.append(Color(pile_tones[rng.randi() % pile_tones.size()]).darkened(rng.randf_range(0.0, 0.16)).srgb_to_linear())
	_clutter_add(pile_mesh, lit, pile_x, pile_c, "AutumnLeafPiles")
	var total: int = 0
	for entry: Dictionary in _clutter_sets:
		total += (entry["xforms"] as Array).size()
	_terrain_stats["clutter"] = {"sets": _clutter_sets.size(), "instances": total, "glow": glow_x.size()}


# Anything the player builds or paves over disappears (zero scale); it returns if the ground is cleared again.
func _clutter_apply_mask() -> void:
	if _terrain_mask_image == null:
		return
	var hidden: int = 0
	for entry: Dictionary in _clutter_sets:
		var multi: MultiMesh = entry["multi"]
		var xforms: Array = entry["xforms"]
		var positions: PackedVector2Array = entry["pos"]
		for index in xforms.size():
			var at: Vector2 = positions[index]
			var cleared: float = _terrain_mask_image.get_pixel(clampi(int(at.x + 20.0), 0, TERRAIN_MASK.x - 1), clampi(int(at.y + 16.0), 0, TERRAIN_MASK.y - 1)).g
			if cleared > CLUTTER_CLEAR:
				multi.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), (xforms[index] as Transform3D).origin))
				hidden += 1
			else:
				multi.set_instance_transform(index, xforms[index])
	_terrain_stats["clutter_hidden"] = hidden


# --- ground mist ------------------------------------------------------------

func _mist_build() -> void:
	_mist_root = Node3D.new()
	_mist_root.name = "AutumnMist"
	add_child(_mist_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var fade: Texture2D = UI.soft_disc_texture()
	var count: int = MIST_COUNT_LOW if _terrain_is_phone() else MIST_COUNT
	for index in count:
		var plane := PlaneMesh.new()
		plane.size = Vector2(rng.randf_range(7.0, 10.0), rng.randf_range(4.5, 6.5))
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_texture = fade
		var alpha: float = rng.randf_range(0.10, 0.16)
		material.albedo_color = Color(0.93, 0.85, 0.68, alpha)
		var node := MeshInstance3D.new()
		node.mesh = plane
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var side: float = float(index) / float(count) * TAU + rng.randf_range(-0.3, 0.3)
		var base := Vector3(cos(side) * 15.0, 0.22, sin(side) * 11.5)
		node.position = base
		node.rotation.y = rng.randf_range(0.0, TAU)
		_mist_root.add_child(node)
		_mist_patches.append({"node": node, "base": base, "phase": rng.randf_range(0.0, TAU), "speed": rng.randf_range(0.08, 0.18), "alpha": alpha})


func _mist_tick() -> void:
	for patch: Dictionary in _mist_patches:
		var t: float = _terrain_time * float(patch["speed"]) + float(patch["phase"])
		(patch["node"] as MeshInstance3D).position = (patch["base"] as Vector3) + Vector3(sin(t) * 1.8, 0.0, cos(t * 0.8) * 1.2)


# --- claimed expansion land -------------------------------------------------

# One baked 128px autumn grass texture for the expansion slabs, since they are plain boxes.
func _slab_build() -> void:
	var side: int = 128
	var image := Image.create(side, side, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for y in side:
		for x in side:
			var n: float = _terrain_noise.get_pixel(x * 2, y * 2).r
			var m: float = _terrain_noise.get_pixel((x * 2 + 97) % 256, (y * 2 + 41) % 256).r
			var green: Color = Color("38561a").lerp(Color("55751f"), m)
			var gold: Color = Color("a07a1c").lerp(Color("b88a22"), m)
			var color: Color = green.lerp(gold, smoothstep(0.3, 0.7, n) * 0.75)
			image.set_pixel(x, y, color * (0.9 + 0.2 * m))
	var specks: Array[String] = ["d9741a", "c99a1a", "b02e17"]
	for index in 90:
		var px: int = rng.randi_range(0, side - 2)
		var py: int = rng.randi_range(0, side - 2)
		var leaf := Color(specks[rng.randi() % specks.size()])
		image.set_pixel(px, py, leaf)
		image.set_pixel(px + 1, py, leaf)
	_terrain_slab_tex = ImageTexture.create_from_image(image)
	expansion.grass_texture = _terrain_slab_tex
	expansion.ground_tint = SLAB_TINT
	_terrain_autumn_slabs()


func _terrain_autumn_slabs() -> void:
	if _terrain_slab_tex == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for id: String in expansion.slabs:
		var slab: Dictionary = expansion.slabs[id]
		if bool(slab.get("autumn", false)):
			continue
		slab["autumn"] = true
		var grass := slab["grass"] as StandardMaterial3D
		grass.albedo_texture = _terrain_slab_tex
		if not bool(slab["locked"]) and not bool(slab["busy"]):
			grass.albedo_color = SLAB_TINT
		var group := slab["group"] as Node3D
		for kind_name: String in ["Silhouette1", "Silhouette2"]:
			var tree_node := group.get_node_or_null(kind_name) as MultiMeshInstance3D
			if tree_node == null or tree_node.multimesh == null:
				continue
			for index in tree_node.multimesh.instance_count:
				tree_node.multimesh.set_instance_color(index, _terrain_fall_color(rng, 0.5, kind_name == "Silhouette2"))
	for id: String in expansion.slabs:
		var open_slab: Dictionary = expansion.slabs[id]
		if not bool(open_slab["locked"]) and not bool(open_slab["busy"]) and not _slab_grass.has(id):
			_slab_grow_grass(id)
	for id: String in _slab_grass.keys():
		if not expansion.slabs.has(id) or bool(expansion.slabs[id]["locked"]):
			(_slab_grass[id] as Node).queue_free()
			_slab_grass.erase(id)
	for side: String in _skirt_rocks:
		(_skirt_rocks[side] as Node3D).visible = not (side in sim.expansions)


func _sync_expansion(animate: bool) -> void:
	super(animate)
	_terrain_autumn_slabs()


# The base game tints the ground green when it rains; claimed land is white-textured now, so darken that instead.
func _rain_changed() -> void:
	super()
	if _terrain_slab_tex != null:
		expansion.tint_ground(SLAB_TINT.darkened(0.38 * rain_level))


# --- grass on claimed land and rocks on the cliff skirt ----------------------

# Claimed plots get their own clumps (same mesh, same wind) once the unveil is over.
func _slab_grow_grass(id: String) -> void:
	var plots: Dictionary = Sim.EXPANSION_PLOTS
	if not plots.has(id) or _grass_mesh == null:
		return
	var rect: Rect2 = expansion.world_rect(plots[id]["rect"])
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	var want: int = SLAB_GRASS_CLUMPS / (2 if _terrain_is_phone() else 1)
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for index in want:
		var x: float = rng.randf_range(rect.position.x + 1.0, rect.end.x - 1.0)
		var z: float = rng.randf_range(rect.position.y + 1.0, rect.end.y - 1.0)
		var width: float = rng.randf_range(1.0, 1.5)
		var scaled: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(width, rng.randf_range(0.34, 0.62), width))
		xforms.append(Transform3D(scaled, Vector3(x, TERRAIN_LIFT, z)))
		colors.append(_grass_tip_color(rng, 0.55, false))
	var node: MultiMeshInstance3D = _add_multimesh(_grass_mesh, _grass_material, xforms, colors, self, false)
	node.name = "AutumnGrass_" + id
	node.extra_cull_margin = 1.5
	_slab_grass[id] = node


# Mossy boulders half-buried in the dark cliff face under the base map; they go with the edge when a plot is claimed.
func _skirt_build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.3
	mesh.radial_segments = 5
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	var tones: Array[String] = ["5e5d55", "6f6a5e", "54534d", "4f5a38"]
	var per_side: int = 6 if _terrain_is_phone() else 10
	for side: String in ["west", "east", "north", "south"]:
		var xforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		for index in per_side:
			var along: float = rng.randf_range(-15.0, 15.0)
			var depth: float = rng.randf_range(-0.62, -0.12)
			var out: float = 20.5 if side == "west" or side == "east" else 16.5
			var at: Vector3
			match side:
				"west": at = Vector3(-out, depth, along)
				"east": at = Vector3(out, depth, along)
				"north": at = Vector3(along * 1.25, depth, -out)
				_: at = Vector3(along * 1.25, depth, out)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(rng.randf_range(0.8, 1.7), rng.randf_range(0.6, 1.1), rng.randf_range(0.8, 1.5)))
			xforms.append(Transform3D(basis, at))
			colors.append(Color(tones[rng.randi() % tones.size()]).darkened(rng.randf_range(0.0, 0.2)).srgb_to_linear())
		var holder := Node3D.new()
		holder.name = "SkirtRocks_" + side
		add_child(holder)
		_add_multimesh(mesh, material, xforms, colors, holder, false)
		_skirt_rocks[side] = holder
