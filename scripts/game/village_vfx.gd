extends "res://scripts/game/village_roadfx.gd"

# Effects polish (visual only), over the road layer.
#
#   * The box that swelled on raise, upgrade and repair is now a soft dust cloud with a few
#     wood or stone chips, and gold (or leaf-green, for repair) glints.
#   * Footfall depends on what is underfoot: autumn leaves kicked up from grass, tan dust from
#     dirt, pale grit from paved stone, and a small splash in the rain (the base layer skipped
#     footfall in heavy rain entirely).
#   * Finished buildings get a little life: chimney smoke that thickens at night and in rain,
#     forge sparks at the mine and quarry, sawdust at the lumber camps. At most VFX_SITES_MAX
#     emitters (VFX_SITES_LOW on phones), the busiest buildings first.
#   * A gold twinkle where each "+20 Gold" pop appears.
#
# Everything shares the base layer's effect cap (transient poof nodes count toward EFFECT_LIMIT)
# or lives in small fixed pools, so a busy raid cannot flood the scene. Nothing reads or writes
# the simulation. Launch with --no-vfx to compare with the old effects.

const VFX_SITES_MAX: int = 6
const VFX_SITES_LOW: int = 3
const VFX_POLL: float = 1.0
const VFX_LEAF_SLOTS: int = 6
const VFX_GLINT_SLOTS: int = 6
const VFX_DUST := Color("e2d3a8")
const VFX_LEAF_TONES: Array[String] = ["d9741a", "c99a1a", "e0a924", "a8381a"]
const VFX_SITE_KINDS := {
	"hall": {"fx": "smoke", "offset": Vector3(0.9, 2.5, -0.4)},
	"cottage": {"fx": "smoke", "offset": Vector3(0.4, 1.6, -0.2)},
	"bathhouse": {"fx": "smoke", "offset": Vector3(0.4, 1.7, 0.0)},
	"mine": {"fx": "sparks", "offset": Vector3(0.0, 0.7, 0.5)},
	"stone_quarry": {"fx": "sparks", "offset": Vector3(0.0, 0.6, 0.4)},
	"lumber": {"fx": "chips", "offset": Vector3(0.0, 0.5, 0.6)},
	"timber_yard": {"fx": "chips", "offset": Vector3(0.0, 0.5, 0.6)},
	"sawmill": {"fx": "chips", "offset": Vector3(0.0, 0.6, 0.6)},
}
const VFX_PRIORITY: Array[String] = ["hall", "mine", "lumber", "cottage", "sawmill", "stone_quarry", "bathhouse", "timber_yard"]

var _vfx_on: bool = false
var _vfx_dust_mesh: QuadMesh = null
var _vfx_glint_mesh: QuadMesh = null
var _vfx_leaf_mesh: QuadMesh = null
var _vfx_chip_mesh: BoxMesh = null
var _vfx_grow: Curve = null
var _vfx_fade: Gradient = null
var _vfx_leaf_pool: Array[CPUParticles3D] = []
var _vfx_glint_pool: Array[CPUParticles3D] = []
var _vfx_sites: Dictionary = {}               # building id -> CPUParticles3D
var _vfx_clock: float = 0.0
var _vfx_tone: float = -1.0                   # last night-or-rain amount pushed to the chimney smoke
var _vfx_pop_clock: float = 0.0
var _vfx_stats: Dictionary = {"poofs": 0, "leaf_kicks": 0, "splashes": 0, "grit": 0, "dust": 0, "glints": 0}


func _ready() -> void:
	super()
	if "--no-vfx" not in OS.get_cmdline_user_args():
		_vfx_build()


func _process(delta: float) -> void:
	super(delta)
	if not _vfx_on:
		return
	_vfx_pop_clock = maxf(0.0, _vfx_pop_clock - delta)
	_vfx_clock -= delta
	if _vfx_clock <= 0.0:
		_vfx_clock = VFX_POLL
		_vfx_sync_sites()
	var tone: float = clampf(maxf(1.0 - day_blend, rain_level * 0.8), 0.0, 1.0)
	if absf(tone - _vfx_tone) > 0.02:
		_vfx_tone = tone
		for id: Variant in _vfx_sites:
			var site: CPUParticles3D = _vfx_sites[id]
			if is_instance_valid(site) and site.has_meta("smoke"):
				site.color = Color(0.82, 0.78, 0.72, lerpf(0.22, 0.5, tone))


func _vfx_build() -> void:
	var disc: Texture2D = UI.soft_disc_texture()
	_vfx_dust_mesh = QuadMesh.new()
	_vfx_dust_mesh.size = Vector2(0.85, 0.85)
	_vfx_dust_mesh.material = _vfx_material(disc, false)
	_vfx_glint_mesh = QuadMesh.new()
	_vfx_glint_mesh.size = Vector2(0.2, 0.2)
	_vfx_glint_mesh.material = _vfx_material(disc, true)
	_vfx_leaf_mesh = QuadMesh.new()
	_vfx_leaf_mesh.size = Vector2(0.17, 0.11)
	_vfx_leaf_mesh.material = _vfx_material(null, false)
	_vfx_chip_mesh = BoxMesh.new()
	_vfx_chip_mesh.size = Vector3(0.13, 0.08, 0.1)
	var chip_material := StandardMaterial3D.new()
	chip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chip_material.vertex_color_use_as_albedo = true
	_vfx_chip_mesh.material = chip_material
	_vfx_grow = Curve.new()
	_vfx_grow.add_point(Vector2(0.0, 0.45))
	_vfx_grow.add_point(Vector2(1.0, 1.5))
	_vfx_fade = Gradient.new()
	_vfx_fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	_vfx_fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var leaf_tones := Gradient.new()
	leaf_tones.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
	leaf_tones.colors = PackedColorArray([Color(VFX_LEAF_TONES[0]), Color(VFX_LEAF_TONES[1]), Color(VFX_LEAF_TONES[2]), Color(VFX_LEAF_TONES[3])])
	for slot in VFX_LEAF_SLOTS:
		var leaf: CPUParticles3D = _vfx_emitter(_vfx_leaf_mesh, 3, 1.0, true)
		leaf.name = "FootLeaves%d" % slot
		leaf.direction = Vector3.UP
		leaf.spread = 55.0
		leaf.initial_velocity_min = 1.1
		leaf.initial_velocity_max = 2.2
		leaf.gravity = Vector3(0.0, -3.2, 0.0)
		leaf.angular_velocity_min = -420.0
		leaf.angular_velocity_max = 420.0
		leaf.color_initial_ramp = leaf_tones
		leaf.color_ramp = _vfx_fade
		_vfx_leaf_pool.append(leaf)
	for slot in VFX_GLINT_SLOTS:
		var glint: CPUParticles3D = _vfx_emitter(_vfx_glint_mesh, 6, 0.8, true)
		glint.name = "Glint%d" % slot
		glint.direction = Vector3.UP
		glint.spread = 70.0
		glint.initial_velocity_min = 0.8
		glint.initial_velocity_max = 2.0
		glint.gravity = Vector3(0.0, -1.2, 0.0)
		glint.color_ramp = _vfx_fade
		_vfx_glint_pool.append(glint)
	_vfx_on = true


func _vfx_material(texture: Texture2D, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	if texture != null:
		material.albedo_texture = texture
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return material


# A one-shot (or continuous) emitter with the settings every effect here shares.
func _vfx_emitter(mesh: Mesh, amount: int, lifetime: float, pooled: bool, parent: Node = null) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.mesh = mesh
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.local_coords = false
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.emitting = false
	if pooled:
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.visible = false
	(parent if parent != null else self).add_child(emitter)
	return emitter


# Fires the first pooled emitter that is free, at a world position and colour.
func _vfx_fire(pool: Array[CPUParticles3D], at: Vector3, tint: Color, count: int) -> bool:
	for emitter in pool:
		if emitter.emitting:
			continue
		emitter.position = at
		emitter.color = tint
		emitter.amount = maxi(1, count)
		emitter.visible = true
		emitter.restart()
		emitter.emitting = true
		return true
	return false


# Raise / upgrade / repair juice: dust cloud, chips and glints in one transient node that
# counts toward the shared effect cap and clears itself.
func _poof(tile: Vector2i, color: Color) -> void:
	if not _vfx_on:
		super(tile, color)
		return
	if effect_nodes.size() + burst_pool.active_count() >= EFFECT_LIMIT or tile.x < 0:
		return
	var low: bool = _sky_is_phone()
	var cloud := Node3D.new()
	cloud.name = "BuildPoof"
	cloud.position = world_position(Vector2(tile) + Vector2.ONE * 0.5, 0.3)
	add_child(cloud)
	effect_nodes.append(cloud)
	var dust: CPUParticles3D = _vfx_emitter(_vfx_dust_mesh, 8 if low else 14, 0.95, true, cloud)
	dust.visible = true
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(TILE * 0.42, 0.05, TILE * 0.42)
	dust.direction = Vector3.UP
	dust.spread = 75.0
	dust.initial_velocity_min = 0.5
	dust.initial_velocity_max = 1.5
	dust.gravity = Vector3(0.0, 0.25, 0.0)
	dust.damping_min = 0.8
	dust.damping_max = 1.4
	dust.scale_amount_min = 0.9
	dust.scale_amount_max = 1.6
	dust.scale_amount_curve = _vfx_grow
	dust.color = Color(VFX_DUST.lerp(color, 0.2), 0.85)
	dust.color_ramp = _vfx_fade
	dust.emitting = true
	var chips: CPUParticles3D = _vfx_emitter(_vfx_chip_mesh, 3 if low else 7, 0.75, true, cloud)
	chips.visible = true
	chips.direction = Vector3.UP
	chips.spread = 60.0
	chips.initial_velocity_min = 2.6
	chips.initial_velocity_max = 4.6
	chips.gravity = Vector3(0.0, -13.0, 0.0)
	chips.angular_velocity_min = -540.0
	chips.angular_velocity_max = 540.0
	var chip_tones := Gradient.new()
	chip_tones.colors = PackedColorArray([Color("9a7440"), Color("8c8f98")])
	chips.color_initial_ramp = chip_tones
	chips.emitting = true
	var repair: bool = color.g > color.r + 0.1
	var glints: CPUParticles3D = _vfx_emitter(_vfx_glint_mesh, 5 if low else 9, 0.9, true, cloud)
	glints.visible = true
	glints.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	glints.emission_box_extents = Vector3(TILE * 0.3, 0.1, TILE * 0.3)
	glints.direction = Vector3.UP
	glints.spread = 40.0
	glints.initial_velocity_min = 1.0
	glints.initial_velocity_max = 2.4
	glints.gravity = Vector3(0.0, -1.0, 0.0)
	glints.color = Color(0.62, 1.0, 0.55, 0.95) if repair else Color(1.0, 0.86, 0.42, 0.95)
	glints.color_ramp = _vfx_fade
	glints.emitting = true
	var tween: Tween = _effect_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(cloud.queue_free)
	_vfx_stats["poofs"] = int(_vfx_stats["poofs"]) + 1


# What the ground at a point is: paved "road", trampled "dirt", or "grass".
func _vfx_ground_at(at: Vector3) -> String:
	var tile := Vector2i(floori((at.x - MAP_ORIGIN.x) / TILE), floori((at.z - MAP_ORIGIN.z) / TILE))
	var cell: Variant = sim.living.cells.get("%d,%d" % [tile.x, tile.y])
	if cell is Dictionary:
		if bool((cell as Dictionary).get("stone", false)):
			return "road"
		if float((cell as Dictionary).get("wear", 0.0)) > 0.25:
			return "dirt"
	if _terrain_mask_image != null:
		var size: Vector2i = _terrain_mask_image.get_size()
		var mx: int = clampi(int((at.x / TERRAIN_SIZE.x + 0.5) * float(size.x)), 0, size.x - 1)
		var my: int = clampi(int((at.z / TERRAIN_SIZE.y + 0.5) * float(size.y)), 0, size.y - 1)
		if _terrain_mask_image.get_pixel(mx, my).r > 0.45:
			return "dirt"
	return "grass"


# Every stride: leaves off grass, dust off dirt, grit off stone, a splash in the rain.
func _footfall_puff(at: Vector3) -> void:
	if not _vfx_on:
		super(at)
		return
	if _puffs_this_frame >= MAX_PUFFS_PER_FRAME or not _effect_budget_open():
		return
	_puffs_this_frame += 1
	var low: bool = _sky_is_phone()
	if rain_level > HEAVY_RAIN:
		burst_pool.spawn(at + Vector3(0.0, 0.05, 0.0), Color(0.78, 0.86, 0.95), 3, 0.16, false)
		_vfx_stats["splashes"] = int(_vfx_stats["splashes"]) + 1
		return
	match _vfx_ground_at(at):
		"road":
			burst_pool.spawn(at + Vector3(0.0, 0.08, 0.0), Color("b9b5aa"), 2, 0.22, false)
			_vfx_stats["grit"] = int(_vfx_stats["grit"]) + 1
		"dirt":
			burst_pool.spawn(at + Vector3(0.0, 0.08, 0.0), Color("b89a6a"), 2, 0.3, false)
			_vfx_stats["dust"] = int(_vfx_stats["dust"]) + 1
		_:
			_vfx_fire(_vfx_leaf_pool, at + Vector3(0.0, 0.12, 0.0), Color.WHITE, 2 if low else 3)
			_vfx_stats["leaf_kicks"] = int(_vfx_stats["leaf_kicks"]) + 1


# A gold twinkle where each collect pop appears (at most about six a second).
func _spawn_collect_pop(event: Dictionary) -> void:
	super(event)
	if not _vfx_on or _vfx_pop_clock > 0.0:
		return
	_vfx_pop_clock = 0.16
	var at: Vector3 = world_position(Vector2(float(event["x"]), float(event["y"])), 1.5)
	if _vfx_fire(_vfx_glint_pool, at, Color(1.0, 0.86, 0.42, 0.95), 4 if _sky_is_phone() else 6):
		_vfx_stats["glints"] = int(_vfx_stats["glints"]) + 1


# Chimney smoke, forge sparks and sawdust on the finished, standing buildings that are busiest.
func _vfx_sync_sites() -> void:
	var cap: int = VFX_SITES_LOW if _sky_is_phone() else VFX_SITES_MAX
	var wanted: Dictionary = {}
	for kind: String in VFX_PRIORITY:
		for building: Dictionary in sim.buildings:
			if wanted.size() >= cap:
				break
			if str(building["type"]) == kind and float(building["remaining"]) <= 0.0 and float(building["hp"]) > 0.0:
				wanted[int(building["id"])] = building
	for id: Variant in _vfx_sites.keys():
		if not wanted.has(id):
			if is_instance_valid(_vfx_sites[id]):
				(_vfx_sites[id] as Node).queue_free()
			_vfx_sites.erase(id)
	for id: Variant in wanted:
		if not _vfx_sites.has(id):
			_vfx_sites[id] = _vfx_site_make(wanted[id])


func _vfx_site_make(building: Dictionary) -> CPUParticles3D:
	var spec: Dictionary = VFX_SITE_KINDS[str(building["type"])]
	var size: float = float(building["size"])
	var at: Vector3 = world_position(Vector2(float(building["x"]) + size * 0.5, float(building["y"]) + size * 0.5), 0.0) + (spec["offset"] as Vector3)
	var low: bool = _sky_is_phone()
	var site: CPUParticles3D
	match str(spec["fx"]):
		"smoke":
			site = _vfx_emitter(_vfx_dust_mesh, 4 if low else 7, 3.4, false)
			site.set_meta("smoke", true)
			site.direction = Vector3.UP
			site.spread = 14.0
			site.initial_velocity_min = 0.35
			site.initial_velocity_max = 0.6
			site.gravity = Vector3(0.25, 0.22, 0.1)
			site.scale_amount_min = 0.4
			site.scale_amount_max = 0.7
			site.scale_amount_curve = _vfx_grow
			site.color = Color(0.82, 0.78, 0.72, 0.22)
			site.color_ramp = _vfx_fade
		"sparks":
			site = _vfx_emitter(_vfx_glint_mesh, 3 if low else 5, 0.7, false)
			site.direction = Vector3.UP
			site.spread = 50.0
			site.initial_velocity_min = 1.4
			site.initial_velocity_max = 3.0
			site.gravity = Vector3(0.0, -7.0, 0.0)
			site.scale_amount_min = 0.35
			site.scale_amount_max = 0.6
			site.color = Color(1.0, 0.62, 0.22, 0.95)
			site.color_ramp = _vfx_fade
		_:
			site = _vfx_emitter(_vfx_chip_mesh, 2 if low else 3, 0.7, false)
			site.direction = Vector3.UP
			site.spread = 55.0
			site.initial_velocity_min = 1.2
			site.initial_velocity_max = 2.4
			site.gravity = Vector3(0.0, -9.0, 0.0)
			site.angular_velocity_min = -360.0
			site.angular_velocity_max = 360.0
			site.color = Color("c9a468")
	site.name = "Site%d" % int(building["id"])
	site.position = at
	site.emitting = true
	return site
