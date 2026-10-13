extends "res://scripts/game/village_motion.gd"

# The Realm (visual + light state), over the idle motion layer: the open world around the manor.
#
# The home village, its look and its controls are unchanged. Around it now lies a 512 m square realm
# (realm_map.gd) of hills, woods and lakes with five rival settlements. Pan and zoom out to find them:
# their banners stand above the trees, their land is tinted in their colour with a brighter border
# line, and up close their halls and cottages (the same delivered building models) have people
# walking between them. Each neighbour grows over active play time; more people means more cottages
# and a wider claim, so borders creep toward the manor's own land, which widens as plots are claimed.
#
# Phone budget (gl_compatibility, single-threaded web):
#   * terrain: one indexed mesh, 4 m cells (8 m on phones), ~33k triangles, one draw call;
#     a second flat quad is the water;
#   * trees: one MultiMesh per 64 m chunk and shape, streamed around the camera, capped at
#     REALM_TREE_CHUNKS (REALM_TREE_CHUNKS_LOW on phones), built a few per poll so panning never hitches;
#   * settlements: only the REALM_SITES_LOADED nearest the camera get models and walkers; the rest
#     are a banner pole and their territory tint;
#   * growth is a handful of numbers advanced with the village clock (paused time adds nothing).
#
# Nothing here changes the village simulation or its save. Realm growth is saved separately to
# REALM_SAVE_PATH and only when the village itself may save. Launch with --no-realm to leave it out,
# and --realm-view=x,z,zoom (capture only) to frame a shot.

const RealmMap = preload("res://scripts/game/realm_map.gd")

const REALM_SEED: int = 7
const REALM_PAN: float = 236.0
const REALM_ZOOM_MAX: float = 130.0
const REALM_FAR: float = 460.0
const REALM_NEAR_BACK: float = 240.0
const REALM_GRID: float = 4.0
const REALM_GRID_LOW: float = 8.0
const REALM_POLL: float = 0.25
const REALM_TREE_CHUNKS: int = 36
const REALM_TREE_CHUNKS_LOW: int = 16
const REALM_TREE_BUILDS_PER_POLL: int = 3
const REALM_GRASS_ZOOM: float = 55.0        # tufts only show from this close; further they're specks
const REALM_GRASS_CHUNKS: int = 9
const REALM_GRASS_CHUNKS_LOW: int = 4
const REALM_GRASS_TUFTS: int = 1400         # tries per 64 m chunk; meadows keep most of them
const REALM_GRASS_TUFTS_LOW: int = 520
const REALM_SITES_LOADED: int = 3
const REALM_SITES_LOADED_LOW: int = 2
const REALM_WALKERS: int = 6
const REALM_WALKERS_LOW: int = 3
const REALM_WALK_SPEED: float = 1.1
const REALM_SAVE_PATH: String = "user://realm-v1.json"
const REALM_SAVE_SECONDS: float = 10.0
const REALM_TINT: float = 0.12             # territory wash over the ground colour
const REALM_BORDER_TINT: float = 0.6       # where two owners meet
const REALM_HAUNT_BOX := Vector2(56.0, 52.0)  # half size of the haunted ground, just past its dead trees
const REALM_FISHERS: int = 3
const REALM_FISHERS_LOW: int = 2
const REALM_HILLSHADE := Vector3(-0.5, 0.78, -0.38)   # unit vector: a high light from the far left
const REALM_WOOD := Color("6b5238")
const REALM_WOOD_DARK := Color("4a3826")
const REALM_STONE := Color("6b6457")
const REALM_WALKER_CLIPS: Array[String] = ["char_farmer", "char_lumberjack", "char_forager", "char_builder", "char_shepherd", "char_miller"]

var realm = null
var _realm_root: Node3D = null
var _realm_ground: MeshInstance3D = null
var _realm_ground_revision: int = -1
var _realm_side: int = 0
var _realm_step: float = 4.0
var _realm_heights := PackedFloat32Array()
var _realm_vertices := PackedVector3Array()
var _realm_normals := PackedVector3Array()
var _realm_base_colors := PackedColorArray()
var _realm_haunt_weight := PackedFloat32Array()
var _realm_indices := PackedInt32Array()
var _realm_haunt_color := Color.BLACK
var _realm_tree_meshes: Array[Mesh] = []
var _realm_tree_material: ShaderMaterial = null
var _realm_trees: Dictionary = {}          # Vector2i chunk -> Array[MultiMeshInstance3D]
var _realm_grass: Dictionary = {}          # Vector2i chunk -> MultiMeshInstance3D
var _realm_sites: Dictionary = {}          # settlement id -> {root, pop_shown, walkers: Array[Dictionary]}
var _realm_banners: Dictionary = {}        # settlement id -> {root, label}
var _realm_clock: float = 0.0
var _realm_save_clock: float = 0.0
var _realm_phone: bool = false
var _realm_prop_material: StandardMaterial3D = null
var _realm_fishers: Dictionary = {}        # fishing spot id -> {root, model, player, bobber, ripple, clip}
var _realm_fish_time: float = 0.0


func _ready() -> void:
	super()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--no-realm" in args:
		return
	realm = RealmMap.new()
	var loaded: bool = false
	if not no_save and FileAccess.file_exists(REALM_SAVE_PATH):
		loaded = realm.from_dict(JSON.parse_string(FileAccess.get_file_as_string(REALM_SAVE_PATH)))
	if not loaded:
		realm.generate(REALM_SEED)
	realm.set_home_plots(sim.expansions.size())
	_realm_phone = _terrain_is_phone()
	pan_limit = Vector2(REALM_PAN, REALM_PAN)
	zoom_max = REALM_ZOOM_MAX
	camera.far = REALM_FAR
	# Orthographic: a near plane behind the camera keeps tall ground near the screen's bottom edge
	# from being clipped away (the camera sits only 60 m from its target).
	camera.near = -REALM_NEAR_BACK
	# The sky layer paints its backdrop just inside the far plane; keep it there.
	if is_instance_valid(_sky_backdrop):
		_sky_backdrop.position.z = -(camera.far - 12.0)
	_realm_root = Node3D.new()
	_realm_root.name = "Realm"
	add_child(_realm_root)
	_realm_trim_haunt()
	_realm_build_water()
	_realm_build_ground()
	_realm_build_outskirts()
	_realm_build_river_works()
	_realm_build_tree_meshes()
	_realm_build_border_forest()
	_realm_build_banners()
	_camera_update()
	for arg in args:
		if arg.begins_with("--realm-view="):
			var parts: PackedStringArray = arg.trim_prefix("--realm-view=").split(",")
			if parts.size() >= 3:
				target = Vector3(float(parts[0]), 0.0, float(parts[1]))
				target.y = maxf(realm_surface_y(target.x, target.z), 0.0)   # frame hills on centre
				zoom = clampf(float(parts[2]), 12.0, zoom_max)
				if parts.size() == 5:   # optional yaw,tilt in degrees, within the player's own limits
					yaw = deg_to_rad(float(parts[3]))
					tilt = clampf(deg_to_rad(float(parts[4])), 0.3, 1.25)
				_camera_update()
	realm_stream(true)


# The scenery mountains on the camera's side of the view would stand between it and the realm
# (the projection is orthographic, so nothing hides them); the ground and tree shaders lower the
# ones behind the view's focus to foothills, around the focus and facing set here.
func _camera_update() -> void:
	super()
	var focus := Vector4(target.x, target.z, -sin(yaw), -cos(yaw))
	for material: ShaderMaterial in [_realm_ground_material(), _realm_tree_material]:
		if material != null:
			material.set_shader_parameter("focus", focus)


func _realm_ground_material() -> ShaderMaterial:
	return _realm_ground.material_override as ShaderMaterial if is_instance_valid(_realm_ground) else null


func _process(delta: float) -> void:
	super(delta)
	if realm == null:
		return
	var active: bool = started and not sim.paused
	if active:
		realm.set_home_plots(sim.expansions.size())
		realm.advance(delta)
		_realm_save_clock += delta
		if _realm_save_clock >= REALM_SAVE_SECONDS:
			_realm_save_clock = 0.0
			realm_save()
	_realm_walk(delta if active else 0.0)
	_realm_animate_fishers(delta if active else 0.0)
	_realm_clock += delta
	if _realm_clock >= REALM_POLL:
		_realm_clock = 0.0
		realm_stream(false)


func _notification(what: int) -> void:
	super(what)
	if realm != null and what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		realm_save()


func realm_save() -> bool:
	if realm == null or no_save or save_blocked:
		return false
	var file := FileAccess.open(REALM_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(realm.to_dict()))
	return true


# Everything that follows the camera: ground tint after border changes, nearby tree chunks and the
# nearest settlements. `force` builds every wanted chunk at once (startup and captures).
func realm_stream(force: bool) -> void:
	if realm == null:
		return
	var haunt: Color = _realm_haunt_now()
	var haunt_moved: bool = absf(haunt.r - _realm_haunt_color.r) + absf(haunt.g - _realm_haunt_color.g) + absf(haunt.b - _realm_haunt_color.b) > 0.03
	if realm.revision != _realm_ground_revision or haunt_moved:
		_realm_paint_ground()
	var reach: float = realm_view_reach()
	var focus := Vector2(target.x, target.z)
	_realm_stream_trees(focus, reach, force)
	_realm_stream_grass(focus, reach, force)
	_realm_stream_sites(focus, reach + 10.0)
	_realm_stream_fishers(focus, reach + 10.0)


# Ground distance from the camera target to the farthest visible point, roughly. Orthographic, so
# it follows the zoom and the window shape, not the camera distance.
func realm_view_reach() -> float:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = view.x / maxf(view.y, 1.0)
	var height: float = camera.size
	return maxf(height * ratio, height / maxf(sin(tilt), 0.3)) * 0.6 + 16.0


# --- Ground and water ---------------------------------------------------------------------------

# Heights, normals and base colours never change, so they are built once; owners and the haunt
# tint are repainted from this cache when borders move or the haunted edge recedes.
func _realm_build_ground() -> void:
	var step: float = REALM_GRID_LOW if _realm_phone else REALM_GRID
	_realm_step = step
	var cells: int = int(RealmMap.HALF * 2.0 / step)
	var side: int = cells + 1
	_realm_side = side
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	_realm_vertices.resize(side * side)
	_realm_base_colors.resize(side * side)
	_realm_haunt_weight.resize(side * side)
	for gz in side:
		for gx in side:
			var x: float = -RealmMap.HALF + float(gx) * step
			var z: float = -RealmMap.HALF + float(gz) * step
			var index: int = gz * side + gx
			heights[index] = realm.height_at(x, z)
			_realm_vertices[index] = Vector3(x, heights[index], z)
			var box: float = maxf(absf(x) / REALM_HAUNT_BOX.x, absf(z) / REALM_HAUNT_BOX.y)
			_realm_haunt_weight[index] = 1.0 - smoothstep(1.0, 1.5, box)
	_realm_heights = heights
	_realm_normals.resize(side * side)
	for gz in side:
		for gx in side:
			var left: float = heights[gz * side + maxi(gx - 1, 0)]
			var right: float = heights[gz * side + mini(gx + 1, cells)]
			var up: float = heights[maxi(gz - 1, 0) * side + gx]
			var down: float = heights[mini(gz + 1, cells) * side + gx]
			var normal := Vector3(left - right, step * 2.0, up - down).normalized()
			_realm_normals[gz * side + gx] = normal
			# Slope (rise over run) shades steeper ground toward bare earth and stone.
			var slope: float = sqrt(maxf(1.0 - normal.y * normal.y, 0.0)) / maxf(normal.y, 0.05)
			var colour: Color = realm.ground_color(-RealmMap.HALF + float(gx) * step, -RealmMap.HALF + float(gz) * step, slope)
			# Baked relief: hollows a shade darker, crests a shade lighter, so hills read from above
			# whichever way the sun has turned.
			var bend: float = clampf((left + right + up + down - 4.0 * heights[gz * side + gx]) / (step * step) * 4.0, -1.0, 1.0)
			colour = colour.darkened(maxf(bend, 0.0) * 0.3 + minf(slope, 0.4) * 0.2)
			# A soft hillshade from a fixed high light, as on a painted map: slopes facing it warm
			# up, slopes facing away cool down, so the hills read from straight above too.
			var facing: float = normal.dot(REALM_HILLSHADE) - REALM_HILLSHADE.y
			if facing > 0.0:
				colour = colour.lerp(Color("e0c27a"), minf(facing * 0.9, 0.22))
			else:
				colour = colour.lerp(Color("1d2030"), minf(-facing * 1.1, 0.3))
			colour = colour.lightened(maxf(-bend, 0.0) * 0.16)
			colour.a = _realm_wooded(-RealmMap.HALF + float(gx) * step, -RealmMap.HALF + float(gz) * step)
			_realm_base_colors[gz * side + gx] = colour
	# The outskirts slab already covers the middle; quads wholly inside it are left out.
	_realm_indices.clear()
	for gz in cells:
		for gx in cells:
			var x0: float = -RealmMap.HALF + float(gx) * step
			var z0: float = -RealmMap.HALF + float(gz) * step
			if x0 >= -36.0 and x0 + step <= 36.0 and z0 >= -32.0 and z0 + step <= 32.0:
				continue
			var a: int = gz * side + gx
			_realm_indices.append_array([a, a + 1, a + side, a + 1, a + side + 1, a + side])
	_realm_ground = MeshInstance3D.new()
	_realm_ground.name = "RealmGround"
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/realm_ground.gdshader")
	material.set_shader_parameter("noise_tex", _realm_noise_texture())
	material.set_shader_parameter("water_y", RealmMap.WATER_Y)
	_realm_ground.material_override = material
	_realm_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_realm_root.add_child(_realm_ground)
	_realm_paint_ground()


# Past the playable edge the country runs on to the horizon: square rings from the realm's edge
# out to OUTER_HALF, foothills rising into mountains (rock, then snow on the tallest peaks) with
# the river's valley cutting through. The first ring shares the ground mesh's edge vertices, so the
# two meet without a crack; the rings spread out with distance, where the haze hides the detail.
func _realm_build_outskirts() -> void:
	var per_side: int = int(RealmMap.HALF * 2.0 / _realm_step)   # matches the ground's edge vertices
	var around: int = per_side * 4
	var radii: Array[float] = []
	var r: float = RealmMap.HALF
	while r < RealmMap.OUTER_HALF:
		radii.append(r)
		r += _realm_step * (1.0 + (r - RealmMap.HALF) * 0.035)
	radii.append(RealmMap.OUTER_HALF)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	for ring in radii.size():
		var radius: float = radii[ring]
		var probe: float = maxf(_realm_step, (radii[mini(ring + 1, radii.size() - 1)] - radii[maxi(ring - 1, 0)]) * 0.5)
		for i in around:
			var p: Vector2 = _realm_square_point(radius, float(i) / float(around))
			var y: float = realm.height_at(p.x, p.y)
			var dx: float = realm.height_at(p.x + probe, p.y) - realm.height_at(p.x - probe, p.y)
			var dz: float = realm.height_at(p.x, p.y + probe) - realm.height_at(p.x, p.y - probe)
			var normal := Vector3(-dx, probe * 2.0, -dz).normalized()
			var slope: float = sqrt(maxf(1.0 - normal.y * normal.y, 0.0)) / maxf(normal.y, 0.05)
			vertices.append(Vector3(p.x, y, p.y))
			normals.append(normal)
			colors.append(_realm_outskirt_color(p, y, slope, normal))
	var indices := PackedInt32Array()
	for ring in radii.size() - 1:
		var inner: int = ring * around
		var outer: int = inner + around
		for i in around:
			var j: int = (i + 1) % around
			indices.append_array([inner + i, outer + i, inner + j, inner + j, outer + i, outer + j])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = "RealmOutskirts"
	node.mesh = mesh
	node.material_override = _realm_ground.material_override
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_realm_root.add_child(node)


# A point on the square of half-size radius, t in 0..1 once around (anticlockwise from the -x,-z
# corner), so every ring has the same vertex count and neighbouring rings stitch index to index.
func _realm_square_point(radius: float, t: float) -> Vector2:
	var s: float = t * 4.0
	var side: int = mini(int(s), 3)
	var f: float = (s - float(side)) * 2.0 - 1.0
	match side:
		0:
			return Vector2(f * radius, -radius)
		1:
			return Vector2(radius, f * radius)
		2:
			return Vector2(-f * radius, radius)
	return Vector2(-radius, -f * radius)


func _realm_outskirt_color(p: Vector2, y: float, slope: float, normal: Vector3) -> Color:
	var colour: Color = realm.ground_color(p.x, p.y, slope)
	var h: float = y - RealmMap.BASE_Y
	# Dark woods clothe the foothills, bare rock the mountainsides, snow the tallest peaks; all of
	# it eases in away from the edge so the seam with the realm's own ground never shows.
	var away: float = smoothstep(RealmMap.HALF + 4.0, RealmMap.HALF + 90.0, maxf(absf(p.x), absf(p.y)))
	colour = colour.lerp(Color("2c3b25"), smoothstep(3.0, 9.0, h) * (1.0 - smoothstep(22.0, 34.0, h)) * 0.7 * away)
	colour = colour.lerp(Color("6b6862"), (smoothstep(20.0, 36.0, h) * 0.85 + smoothstep(0.5, 0.9, slope) * 0.3) * away)
	colour = colour.lerp(Color("dfe3ea"), smoothstep(52.0, 66.0, h + normal.y * 6.0) * away)
	var facing: float = normal.dot(REALM_HILLSHADE) - REALM_HILLSHADE.y
	if facing > 0.0:
		colour = colour.lerp(Color("e0c27a"), minf(facing * 0.9, 0.22))
	else:
		colour = colour.lerp(Color("1d2030"), minf(-facing * 1.1, 0.35))
	colour.a = _realm_wooded(p.x, p.y)
	return colour


# How wooded the ground is, 0..1, for leaf litter in the ground shader (COLOR.a).
func _realm_wooded(x: float, z: float) -> float:
	return smoothstep(0.02, 0.3, realm.woodland(x, z))


# A small tiling noise for the ground's painted detail.
func _realm_noise_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = realm.seed_value + 5
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var image: Image = noise.get_seamless_image(128, 128)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# Territory wash (brighter where two owners meet) and the haunted edge's own colour near home.
func _realm_paint_ground() -> void:
	_realm_ground_revision = realm.revision
	_realm_haunt_color = _realm_haunt_now()
	var side: int = _realm_side
	var last: int = side - 1
	var owners: Array[String] = realm.owners_at(_realm_vertices)
	var colors := PackedColorArray()
	colors.resize(side * side)
	for gz in side:
		for gx in side:
			var index: int = gz * side + gx
			var base: Color = _realm_base_colors[index]
			var colour: Color = base.lerp(_realm_haunt_color, _realm_haunt_weight[index])
			var owner: String = owners[index]
			if owner != "":
				var border: bool = false
				for other: int in [gz * side + maxi(gx - 1, 0), gz * side + mini(gx + 1, last), maxi(gz - 1, 0) * side + gx, mini(gz + 1, last) * side + gx]:
					if owners[other] != owner:
						border = true
				colour = colour.lerp(realm.owner_color(owner), REALM_BORDER_TINT if border else REALM_TINT)
			colour.a = base.a
			colors[index] = colour
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _realm_vertices
	arrays[Mesh.ARRAY_NORMAL] = _realm_normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _realm_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_realm_ground.mesh = mesh


# The haunted edge layer owns the dark ground right around the village and lightens it as the
# manor grows. The realm keeps that look: its plane is trimmed to the outskirts, and the realm
# ground under and beyond it starts in the same colour and fades into open country.
func _realm_trim_haunt() -> void:
	if not is_instance_valid(_haunt_root):
		return
	var plane: MeshInstance3D = _haunt_root.get_node_or_null("OutskirtsGround")
	if plane != null and plane.mesh is PlaneMesh:
		(plane.mesh as PlaneMesh).size = REALM_HAUNT_BOX * 2.0


func _realm_haunt_now() -> Color:
	return _ground_material.albedo_color if _ground_material != null else OUTSKIRTS_RECEDE_GROUND


# Ground Y of the drawn terrain at (x, z): the same triangles as the mesh, so anything set on the
# ground (buildings, stilts, trees, people) meets it exactly rather than the smoother true height.
func realm_surface_y(x: float, z: float) -> float:
	if _realm_heights.is_empty():
		return realm.height_at(x, z)
	var side: int = _realm_side
	var fx: float = (x + RealmMap.HALF) / _realm_step
	var fz: float = (z + RealmMap.HALF) / _realm_step
	var gx: int = clampi(floori(fx), 0, side - 2)
	var gz: int = clampi(floori(fz), 0, side - 2)
	var tx: float = clampf(fx - float(gx), 0.0, 1.0)
	var tz: float = clampf(fz - float(gz), 0.0, 1.0)
	var a: float = _realm_heights[gz * side + gx]
	var b: float = _realm_heights[gz * side + gx + 1]
	var c: float = _realm_heights[(gz + 1) * side + gx]
	var d: float = _realm_heights[(gz + 1) * side + gx + 1]
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


# Where people stand: bridge decks over the river, else the drawn ground, wading at most knee deep.
func realm_walk_y(x: float, z: float) -> float:
	var deck: float = realm.bridge_deck_at(x, z)
	if not is_nan(deck):
		return deck
	return maxf(realm_surface_y(x, z), RealmMap.WATER_Y - 0.4)


# The river as a ribbon that follows its line, from one side of the scenery ring to the other.
# Each vertex carries how deep the water is over the ground there (COLOR.r: 0.5 at the shoreline,
# 1 at a metre or more), which way the stream runs (COLOR.gb) and its place along and across the
# stream (UV in metres), so the shader
# can shade deep and shallow water, ring the banks with foam and run the current downstream.
func _realm_build_water() -> void:
	var across: PackedFloat32Array = [-9.0, -7.5, -6.0, -4.5, -3.0, -1.5, 0.0, 1.5, 3.0, 4.5, 6.0, 7.5, 9.0]
	if _realm_phone:
		across = [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]
	var columns: int = across.size()
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var rows: int = 0
	var along: float = 0.0
	var last := Vector2.INF
	var count: int = realm.river_samples()
	for index in count:
		var p: Vector2 = realm.river_point(index)
		if maxf(absf(p.x), absf(p.y)) > RealmMap.OUTER_HALF + 20.0:
			continue
		var ahead: Vector2 = realm.river_point(mini(index + 1, count - 1)) - realm.river_point(maxi(index - 1, 0))
		var flow: Vector2 = ahead.normalized()
		var normal := Vector2(-flow.y, flow.x)
		if last != Vector2.INF:
			along += p.distance_to(last)
		last = p
		for offset: float in across:
			var q: Vector2 = p + normal * offset
			var depth: float = RealmMap.WATER_Y - realm.height_at(q.x, q.y)
			vertices.append(Vector3(q.x, RealmMap.WATER_Y, q.y))
			colors.append(Color(clampf(depth, -1.0, 1.0) * 0.5 + 0.5, flow.x * 0.5 + 0.5, flow.y * 0.5 + 0.5))
			uvs.append(Vector2(offset, along))
		rows += 1
	var indices := PackedInt32Array()
	for row in rows - 1:
		for column in columns - 1:
			var a: int = row * columns + column
			indices.append_array([a, a + columns, a + 1, a + 1, a + columns, a + columns + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var water := MeshInstance3D.new()
	water.name = "RealmWater"
	water.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/realm_water.gdshader")
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_realm_root.add_child(water)


# --- Trees --------------------------------------------------------------------------------------

# The realm's tree shapes, each baked into one vertex-coloured mesh so a chunk costs one draw call
# per shape: a layered pine, a lumpy broadleaf crown, reeds, a boulder, a meadow bush and a slim
# poplar. Foliage is white shaded dark at the bottom to full at the top (the instance colour
# carries the autumn tone), with a little per-facet variation so crowns read as painted, not
# flat; trunks are dark brown. Indexed by the "kind" from RealmMap.trees_in_chunk.
func _realm_build_tree_meshes() -> void:
	var trunk := BoxMesh.new()
	trunk.size = Vector3(0.24, 1.0, 0.24)
	var bark := Color(0.3, 0.22, 0.17)
	var pine := SurfaceTool.new()
	pine.begin(Mesh.PRIMITIVE_TRIANGLES)
	_realm_tree_part(pine, trunk, Transform3D(Basis(), Vector3(0, 0.5, 0)), bark, 0.0, 1.0)
	for tier in 4:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.0 - tier * 0.2
		cone.height = 0.95 - tier * 0.1
		cone.radial_segments = 7
		cone.rings = 1
		var turn := Basis(Vector3.UP, tier * 0.45)
		_realm_tree_part(pine, cone, Transform3D(turn, Vector3(0, 0.98 + tier * 0.42, 0)), Color.WHITE, 0.45, 2.5)
	var round := SurfaceTool.new()
	round.begin(Mesh.PRIMITIVE_TRIANGLES)
	_realm_tree_part(round, trunk, Transform3D(Basis(), Vector3(0, 0.5, 0)), bark, 0.0, 1.0)
	# Phones get three coarser lobes: the realm draws thousands of these.
	var lobes: Array[Vector4] = [Vector4(0, 1.55, 0, 0.78), Vector4(0.42, 1.3, 0.18, 0.52), Vector4(-0.36, 1.32, 0.3, 0.5), Vector4(-0.12, 1.95, -0.22, 0.48)]
	if _realm_phone:
		lobes.resize(3)
	for lobe: Vector4 in lobes:
		var crown := SphereMesh.new()
		crown.radius = lobe.w
		crown.height = lobe.w * 1.8
		crown.radial_segments = 5 if _realm_phone else 7
		crown.rings = 3
		_realm_tree_part(round, crown, Transform3D(Basis(), Vector3(lobe.x, lobe.y, lobe.z)), Color.WHITE, 0.75, 2.4)
	# Reeds: a clump of thin blades, all tinted by the instance colour.
	var reeds := SurfaceTool.new()
	reeds.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 7:
		var stalk := CylinderMesh.new()
		stalk.top_radius = 0.0
		stalk.bottom_radius = 0.07
		stalk.height = 1.0 + float(blade % 3) * 0.3
		stalk.radial_segments = 4
		stalk.rings = 1
		var spot := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(blade) / 7.0) * (0.18 + 0.12 * float(blade % 2))
		var lean := Basis(Vector3(spot.z, 0, -spot.x).normalized(), 0.22)
		_realm_tree_part(reeds, stalk, Transform3D(lean, spot + Vector3(0, stalk.height * 0.5, 0)), Color.WHITE, 0.0, 1.5)
	# A boulder: a squashed low-poly sphere with a smaller stone at its foot.
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := SphereMesh.new()
	stone.radius = 0.7
	stone.height = 0.9
	stone.radial_segments = 6
	stone.rings = 3
	_realm_tree_part(rock, stone, Transform3D(Basis().scaled(Vector3(1.0, 0.8, 0.85)), Vector3(0, 0.22, 0)), Color.WHITE, -0.2, 0.7)
	_realm_tree_part(rock, stone, Transform3D(Basis(Vector3.UP, 0.8).scaled(Vector3(0.45, 0.4, 0.4)), Vector3(0.7, 0.05, 0.35)), Color.WHITE, -0.2, 0.7)
	# A meadow bush: three low clumps.
	var bush := SurfaceTool.new()
	bush.begin(Mesh.PRIMITIVE_TRIANGLES)
	for clump: Vector4 in [Vector4(0, 0.32, 0, 0.5), Vector4(0.45, 0.26, 0.2, 0.36), Vector4(-0.3, 0.24, 0.32, 0.34)]:
		var ball := SphereMesh.new()
		ball.radius = clump.w
		ball.height = clump.w * 1.7
		ball.radial_segments = 6
		ball.rings = 3
		_realm_tree_part(bush, ball, Transform3D(Basis(), Vector3(clump.x, clump.y, clump.z)), Color.WHITE, -0.1, 0.8)
	# A slim poplar: a tall narrow crown on a short trunk.
	var poplar := SurfaceTool.new()
	poplar.begin(Mesh.PRIMITIVE_TRIANGLES)
	_realm_tree_part(poplar, trunk, Transform3D(Basis(), Vector3(0, 0.5, 0)), bark, 0.0, 1.0)
	var spire := SphereMesh.new()
	spire.radius = 0.5
	spire.height = 2.7
	spire.radial_segments = 7
	spire.rings = 5
	_realm_tree_part(poplar, spire, Transform3D(Basis(), Vector3(0, 2.0, 0)), Color.WHITE, 0.7, 3.3)
	_realm_tree_meshes = [pine.commit(), round.commit(), reeds.commit(), rock.commit(), bush.commit(), poplar.commit()]
	_realm_tree_material = ShaderMaterial.new()
	_realm_tree_material.shader = preload("res://shaders/realm_trees.gdshader")


# Adds one primitive to a tree mesh: colour shaded from 60% at height low to full at height high,
# times a small per-triangle variation so the facets catch the light differently.
func _realm_tree_part(tool: SurfaceTool, mesh: PrimitiveMesh, place: Transform3D, colour: Color, low: float, high: float) -> void:
	var arrays: Array = mesh.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for corner in indices.size():
		var index: int = indices[corner]
		var at: Vector3 = place * points[index]
		var facet: int = corner / 3
		var vary: float = 0.94 + 0.12 * fposmod(sin(float(facet) * 12.9898 + at.y * 4.1) * 43758.5453, 1.0)
		var shade: float = lerpf(0.6, 1.0, smoothstep(low, high, at.y)) * vary
		tool.set_color(Color(minf(colour.r * shade, 1.0), minf(colour.g * shade, 1.0), minf(colour.b * shade, 1.0)))
		tool.set_normal((place.basis * normals[index]).normalized())
		tool.add_vertex(at)


func _realm_stream_trees(focus: Vector2, reach: float, force: bool) -> void:
	var cap: int = REALM_TREE_CHUNKS_LOW if _realm_phone else REALM_TREE_CHUNKS
	var wanted: Array[Vector2i] = []
	var span: int = ceili(reach / RealmMap.TREE_CHUNK) + 1
	var middle: Vector2i = realm.chunk_of(focus.x, focus.y)
	var last: int = realm.chunk_count() - 1
	for cz in range(maxi(middle.y - span, 0), mini(middle.y + span, last) + 1):
		for cx in range(maxi(middle.x - span, 0), mini(middle.x + span, last) + 1):
			var chunk := Vector2i(cx, cz)
			if realm.chunk_centre(chunk).distance_to(focus) <= reach + RealmMap.TREE_CHUNK * 0.71:
				wanted.append(chunk)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return realm.chunk_centre(a).distance_squared_to(focus) < realm.chunk_centre(b).distance_squared_to(focus))
	if wanted.size() > cap:
		wanted.resize(cap)
	for chunk: Vector2i in _realm_trees.keys():
		if chunk not in wanted:
			for node: Node in _realm_trees[chunk]:
				node.queue_free()
			_realm_trees.erase(chunk)
	var built: int = 0
	for chunk: Vector2i in wanted:
		if _realm_trees.has(chunk):
			continue
		if not force and built >= REALM_TREE_BUILDS_PER_POLL:
			break
		_realm_trees[chunk] = _realm_build_chunk(chunk)
		built += 1


func _realm_build_chunk(chunk: Vector2i) -> Array:
	var trees: Array[Dictionary] = realm.trees_in_chunk(chunk, 0.6 if _realm_phone else 1.0)
	var nodes: Array = []
	for shape in _realm_tree_meshes.size():
		var picked: Array[Dictionary] = []
		for tree: Dictionary in trees:
			if int(tree.get("kind", 1 if bool(tree["round"]) else 0)) == shape:
				picked.append(tree)
		if picked.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _realm_tree_meshes[shape]
		multimesh.instance_count = picked.size()
		for index in picked.size():
			var tree: Dictionary = picked[index]
			var basis := Basis(Vector3.UP, float(tree["turn"])).scaled(Vector3.ONE * float(tree["scale"]))
			var at: Vector3 = tree["pos"]
			at.y = realm_surface_y(at.x, at.z) - 0.05
			multimesh.set_instance_transform(index, Transform3D(basis, at))
			var tone := Color(TREE_FALL_TONES[int(tree["tone"])])
			if shape == 0:
				tone = Color("2b4a2e").lerp(tone, 0.25)
			elif shape == 2:
				tone = Color("6f7a3a").lerp(Color("8f7a45"), float(int(tree["tone"]) % 3) * 0.35)
			elif shape == 3:
				tone = Color("6e695c").lerp(Color("57524a"), float(int(tree["tone"]) % 3) * 0.4)
			elif shape == 4:
				tone = Color("5d6b2c").lerp(tone, 0.45)
			elif shape == 5:
				tone = Color("c9a02a").lerp(tone, 0.35)
			multimesh.set_instance_color(index, tone.darkened(0.12))
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		node.material_override = _realm_tree_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _realm_phone else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_realm_root.add_child(node)
		nodes.append(node)
	return nodes


# Woods on the foothills past the playable edge: fixed scenery, never streamed. Pines climb the
# slopes, broadleaf trees keep to the lower ground; one MultiMesh per shape and side of the realm
# so the sides behind the camera are culled.
func _realm_build_border_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = realm.seed_value * 7919 + 41
	var tries: int = 2600 if _realm_phone else 6500
	var groups: Dictionary = {}   # Vector2i(shape, side) -> Array[Transform3D, Color]
	for attempt in tries:
		var reach: float = RealmMap.HALF + 3.0 + pow(rng.randf(), 1.6) * 190.0
		var p: Vector2 = _realm_square_point(reach, rng.randf())
		p += Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		if maxf(absf(p.x), absf(p.y)) < RealmMap.HALF + 2.0:
			continue
		var y: float = realm.height_at(p.x, p.y)
		var h: float = y - RealmMap.BASE_Y
		if h > 34.0 or realm.river_distance(p.x, p.y) < RealmMap.RIVER_HALF + RealmMap.RIVER_BANK + 3.0:
			continue
		var thick: float = 0.55 + realm.woodland(p.x * 1.4, p.y * 1.4) * 0.6 - smoothstep(24.0, 34.0, h) * 0.5
		# Just past the edge the woods follow the realm's own (forest thick, meadow sparse), so no
		# line shows where the streamed trees stop and the scenery begins.
		var own: float = 1.0 if realm.biome_at(p.x, p.y) == "forest" else 0.12
		thick = lerpf(own, thick, smoothstep(RealmMap.HALF + 10.0, RealmMap.HALF + 70.0, maxf(absf(p.x), absf(p.y))))
		if rng.randf() > thick:
			continue
		var shape: int = 0 if h > 9.0 or rng.randf() < 0.55 else 1
		var side: int = 0 if absf(p.x) > absf(p.y) and p.x > 0.0 else (1 if absf(p.x) > absf(p.y) else (2 if p.y > 0.0 else 3))
		var size: float = rng.randf_range(1.1, 2.0) * (1.0 + smoothstep(0.0, 8.0, h) * 0.3)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		var tone := Color(TREE_FALL_TONES[rng.randi() % TREE_FALL_TONES.size()])
		if shape == 0:
			tone = Color("24402a").lerp(tone, 0.2)
		var key := Vector2i(shape, side)
		if not groups.has(key):
			groups[key] = []
		groups[key].append([Transform3D(basis, Vector3(p.x, y - 0.35, p.y)), tone.darkened(0.2)])
	for key: Vector2i in groups:
		var picked: Array = groups[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _realm_tree_meshes[key.x]
		multimesh.instance_count = picked.size()
		for index in picked.size():
			multimesh.set_instance_transform(index, picked[index][0])
			multimesh.set_instance_color(index, picked[index][1])
		var node := MultiMeshInstance3D.new()
		node.name = "BorderForest_%d_%d" % [key.x, key.y]
		node.multimesh = multimesh
		node.material_override = _realm_tree_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_realm_root.add_child(node)


# Grass tufts close up: the village's swaying grass clumps (same shader and wind), scattered
# over the nearest chunks only while the camera is near enough to see them. Meadows and wheat get
# the most, woods and stony ground fewer, water and shore none.
func _realm_stream_grass(focus: Vector2, reach: float, force: bool) -> void:
	var wanted: Array[Vector2i] = []
	if _grass_material != null and zoom <= REALM_GRASS_ZOOM:
		var span: int = ceili(reach / RealmMap.TREE_CHUNK) + 1
		var middle: Vector2i = realm.chunk_of(focus.x, focus.y)
		var last: int = realm.chunk_count() - 1
		for cz in range(maxi(middle.y - span, 0), mini(middle.y + span, last) + 1):
			for cx in range(maxi(middle.x - span, 0), mini(middle.x + span, last) + 1):
				var chunk := Vector2i(cx, cz)
				if realm.chunk_centre(chunk).distance_to(focus) <= reach + RealmMap.TREE_CHUNK * 0.71:
					wanted.append(chunk)
		wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return realm.chunk_centre(a).distance_squared_to(focus) < realm.chunk_centre(b).distance_squared_to(focus))
		var cap: int = REALM_GRASS_CHUNKS_LOW if _realm_phone else REALM_GRASS_CHUNKS
		if wanted.size() > cap:
			wanted.resize(cap)
	for chunk: Vector2i in _realm_grass.keys():
		if chunk not in wanted:
			(_realm_grass[chunk] as Node).queue_free()
			_realm_grass.erase(chunk)
	var built: int = 0
	for chunk: Vector2i in wanted:
		if _realm_grass.has(chunk):
			continue
		if not force and built >= 2:
			break
		_realm_grass[chunk] = _realm_build_grass(chunk)
		built += 1


func _realm_build_grass(chunk: Vector2i) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = realm.seed_value * 6131 + chunk.x * 977 + chunk.y * 61
	var corner: Vector2 = realm.chunk_centre(chunk) - Vector2.ONE * RealmMap.TREE_CHUNK * 0.5
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for attempt in (REALM_GRASS_TUFTS_LOW if _realm_phone else REALM_GRASS_TUFTS):
		var x: float = corner.x + rng.randf() * RealmMap.TREE_CHUNK
		var z: float = corner.y + rng.randf() * RealmMap.TREE_CHUNK
		var keep: float = rng.randf()
		var tall: bool = rng.randf() < 0.18
		var spin := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var height: float = rng.randf_range(0.9, 1.5) if tall else rng.randf_range(0.5, 0.85)
		var width: float = rng.randf_range(1.6, 2.4) * (1.5 if tall else 1.0)
		var colour: Color = _grass_tip_color(rng, 0.65, tall)
		if absf(x) < RealmMap.SCENERY_CLEAR.x and absf(z) < RealmMap.SCENERY_CLEAR.y:
			continue
		var y: float = realm_surface_y(x, z)
		if y < RealmMap.WATER_Y + 0.3:
			continue
		var chance: float = {"meadow": 0.9, "wheat": 0.8, "forest": 0.35, "rocky": 0.25}.get(realm.biome_at(x, z), 0.0)
		if keep >= chance:
			continue
		xforms.append(Transform3D(spin * Basis.from_scale(Vector3(width, height, width)), Vector3(x, y - 0.03, z)))
		colors.append(colour)
	var node: MultiMeshInstance3D = _add_multimesh(_grass_clump_mesh(), _grass_material, xforms, colors, _realm_root, false)
	node.name = "RealmGrass"
	return node


func realm_grass_chunks_loaded() -> int:
	return _realm_grass.size()


func realm_tree_chunks_loaded() -> int:
	return _realm_trees.size()


# --- Settlements --------------------------------------------------------------------------------

# Every settlement always shows a tall banner in its colour, so it can be spotted from afar.
func _realm_build_banners() -> void:
	for site: Dictionary in realm.settlements:
		var centre: Vector2 = site["centre"]
		var root := Node3D.new()
		root.name = "Banner_%s" % site["id"]
		root.position = Vector3(centre.x + 3.2, realm_surface_y(centre.x + 3.2, centre.y + 3.2) - 0.1, centre.y + 3.2)
		_realm_root.add_child(root)
		var pole := _box(Vector3(0.22, 7.0, 0.22), Vector3(0, 3.5, 0), Color("2b2d33"), root)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flag := _box(Vector3(2.2, 1.3, 0.08), Vector3(1.2, 6.2, 0), site["color"], root)
		var flag_material := flag.material_override as StandardMaterial3D
		flag_material.emission_enabled = true
		flag_material.emission = (site["color"] as Color).darkened(0.35)
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.pixel_size = 0.0016
		label.font_size = 30
		label.outline_size = 8
		label.no_depth_test = true
		label.modulate = PAPER
		label.outline_modulate = Color(0.05, 0.06, 0.09, 0.9)
		label.position = Vector3(0, 8.0, 0)
		root.add_child(label)
		_realm_banners[site["id"]] = {"root": root, "label": label, "flag": flag_material}
		_realm_label(site)


func _realm_label(site: Dictionary) -> void:
	var banner: Dictionary = _realm_banners.get(site["id"], {})
	if banner.is_empty():
		return
	(banner["label"] as Label3D).text = "%s / %s\n%d people" % [site["name"], realm.attitude(site), int(site["pop"])]
	# A settlement sworn to the manor flies the manor's colour.
	var colour: Color = RealmMap.HOME_COLOR if bool(site.get("vassal", false)) else site["color"]
	var flag: StandardMaterial3D = banner["flag"]
	if flag.albedo_color != colour:
		flag.albedo_color = colour
		flag.emission = colour.darkened(0.35)


func _realm_stream_sites(focus: Vector2, reach: float) -> void:
	var cap: int = REALM_SITES_LOADED_LOW if _realm_phone else REALM_SITES_LOADED
	var near: Array[Dictionary] = []
	for site: Dictionary in realm.settlements:
		if (site["centre"] as Vector2).distance_to(focus) <= reach:
			near.append(site)
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["centre"] as Vector2).distance_squared_to(focus) < (b["centre"] as Vector2).distance_squared_to(focus))
	if near.size() > cap:
		near.resize(cap)
	var keep: Array[String] = []
	for site: Dictionary in near:
		keep.append(str(site["id"]))
	for id: String in _realm_sites.keys():
		if id not in keep:
			(_realm_sites[id]["root"] as Node3D).queue_free()
			_realm_sites.erase(id)
	for site: Dictionary in realm.settlements:
		_realm_label(site)
	for site: Dictionary in near:
		var view: Dictionary = _realm_sites.get(str(site["id"]), {})
		# Growth is shown by rebuilding the settlement when its building count changes.
		if not view.is_empty() and int(view["layout_size"]) == realm.layout(site).size():
			continue
		if not view.is_empty():
			(view["root"] as Node3D).queue_free()
		_realm_sites[str(site["id"])] = _realm_build_site(site)


func _realm_build_site(site: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Settlement_%s" % site["id"]
	_realm_root.add_child(root)
	var tier: int = realm.tier_of(site)
	var plan: Array[Dictionary] = realm.layout(site)
	var doors: Array[Vector3] = []
	for entry: Dictionary in plan:
		var key: String = model_asset(str(entry["type"]), tier)
		if not _asset_exists(key):
			continue
		var pos: Vector2 = entry["pos"]
		var holder := Node3D.new()
		# On a slope the building stands on a stone footing or timber stilts, never half buried.
		var top: float = _realm_footing(root, pos, float(entry["facing"]), float(entry["size"]) * TILE * 0.5)
		holder.position = Vector3(pos.x, top, pos.y)
		holder.rotation.y = float(entry["facing"])
		root.add_child(holder)
		var model: Node3D = _model(key)
		holder.add_child(model)
		var dims: Array = catalog[key]["dimensions_m"] if catalog.has(key) else [2.0, 2.0, 2.0]
		model.scale = Vector3.ONE * minf(1.6, (float(entry["size"]) * TILE - 0.15) / maxf(float(dims[0]), float(dims[2])))
		holder.add_child(_ao_disc(float(entry["size"]) * TILE + 0.9))
		doors.append(holder.position + holder.basis * Vector3(0, 0, float(entry["size"]) * 1.2))
	var walkers: Array[Dictionary] = []
	var count: int = mini(int(site["pop"]) / 2, REALM_WALKERS_LOW if _realm_phone else REALM_WALKERS)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(site["id"])) + 5
	for index in count:
		if doors.size() < 2:
			break
		var asset: String = REALM_WALKER_CLIPS[index % REALM_WALKER_CLIPS.size()]
		if not _asset_exists(asset):
			continue
		var body: Node3D = _model(asset)
		root.add_child(body)
		var start: Vector3 = doors[rng.randi() % doors.size()]
		body.position = Vector3(start.x, realm_walk_y(start.x, start.z), start.z)
		var record := {"model": body, "player": _find_player_cached(asset, body), "to": start, "wait": rng.randf_range(0.0, 3.0), "clip": "", "doors": doors, "rng_seed": rng.randi()}
		walkers.append(record)
	return {"root": root, "layout_size": plan.size(), "walkers": walkers}


# People stroll between doors, pause a moment, then pick another. Paused time freezes them.
func _realm_walk(delta: float) -> void:
	for view: Dictionary in _realm_sites.values():
		for walker: Dictionary in view["walkers"]:
			var body: Node3D = walker["model"]
			var player: AnimationPlayer = walker["player"]
			if player != null:
				player.speed_scale = 0.0 if delta <= 0.0 else 1.0
			if delta <= 0.0:
				continue
			var clip: String = "idle"
			if float(walker["wait"]) > 0.0:
				walker["wait"] = float(walker["wait"]) - delta
				if float(walker["wait"]) <= 0.0:
					var doors: Array[Vector3] = walker["doors"]
					walker["rng_seed"] = (int(walker["rng_seed"]) * 1103515245 + 12345) & 0x7fffffff
					walker["to"] = doors[int(walker["rng_seed"]) % doors.size()] + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
			else:
				var goal: Vector3 = walker["to"]
				var travel := Vector3(goal.x - body.position.x, 0, goal.z - body.position.z)
				if travel.length() < 0.15:
					walker["wait"] = randf_range(1.5, 5.0)
				else:
					var stride: Vector3 = travel.limit_length(REALM_WALK_SPEED * delta)
					body.position += stride
					body.position.y = realm_walk_y(body.position.x, body.position.z)
					body.rotation.y = rotate_toward(body.rotation.y, atan2(travel.x, travel.z), 8.0 * delta)
					clip = "walk"
			if player != null and walker["clip"] != clip and player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				player.play(clip, 0.15)
				walker["clip"] = clip


func realm_sites_loaded() -> Array:
	return _realm_sites.keys()


func realm_walker_count() -> int:
	var total: int = 0
	for view: Dictionary in _realm_sites.values():
		total += (view["walkers"] as Array).size()
	return total



# --- Footings, bridges and fishing --------------------------------------------------------------

# Boxes baked into one vertex-coloured mesh (one draw call): each part is [size, Transform3D, Color]
# in the parent's space.
func _realm_props(parts: Array) -> MeshInstance3D:
	if _realm_prop_material == null:
		_realm_prop_material = StandardMaterial3D.new()
		_realm_prop_material.vertex_color_use_as_albedo = true
		_realm_prop_material.roughness = 0.92
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Array in parts:
		var box := BoxMesh.new()
		box.size = part[0]
		var arrays: Array = box.surface_get_arrays(0)
		var xform: Transform3D = part[1]
		var base: int = points.size()
		for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			points.append(xform * point)
			colors.append(part[2])
		for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			normals.append((xform.basis * normal).normalized())
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(base + index)
	var merged: Array = []
	merged.resize(Mesh.ARRAY_MAX)
	merged[Mesh.ARRAY_VERTEX] = points
	merged[Mesh.ARRAY_NORMAL] = normals
	merged[Mesh.ARRAY_COLOR] = colors
	merged[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _realm_prop_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _realm_phone else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


# Sets a square footprint (half size `half`, turned by `facing`) level on any ground: a stone
# footing where the ground falls a little, timber stilts with a deck and rails where it falls more.
# Adds the footing under `parent` (in world space) and returns the level the building stands at.
func _realm_footing(parent: Node3D, centre: Vector2, facing: float, half: float) -> float:
	var turn := Basis(Vector3.UP, facing)
	var corners: Array[Vector3] = []
	var low: float = INF
	var top: float = realm_surface_y(centre.x, centre.y)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var offset: Vector3 = turn * Vector3(sx * half, 0, sz * half)
			var y: float = realm_surface_y(centre.x + offset.x, centre.y + offset.z)
			corners.append(Vector3(centre.x + offset.x, y, centre.y + offset.z))
			low = minf(low, y)
			top = maxf(top, y)
	top += 0.04
	var fall: float = top - low
	if fall < 0.18:
		return top - 0.04
	var parts: Array = []
	var middle := Vector3(centre.x, 0, centre.y)
	if fall < 0.75:
		# Stone footing: one block down into the ground, a shade darker cap where the building sits.
		var depth: float = fall + 0.35
		parts.append([Vector3(half * 2.0 + 0.3, depth, half * 2.0 + 0.3), Transform3D(turn, middle + Vector3(0, top - depth * 0.5, 0)), REALM_STONE])
		parts.append([Vector3(half * 2.0 + 0.42, 0.12, half * 2.0 + 0.42), Transform3D(turn, middle + Vector3(0, top - 0.06, 0)), REALM_STONE.darkened(0.18)])
	else:
		# Stilts: a timber deck on posts at the corners and edge middles, railed between them.
		parts.append([Vector3(half * 2.0 + 0.36, 0.2, half * 2.0 + 0.36), Transform3D(turn, middle + Vector3(0, top - 0.1, 0)), REALM_WOOD])
		for sx: float in [-1.0, 0.0, 1.0]:
			for sz: float in [-1.0, 0.0, 1.0]:
				if sx == 0.0 and sz == 0.0:
					continue
				var offset: Vector3 = turn * Vector3(sx * (half + 0.05), 0, sz * (half + 0.05))
				var ground: float = realm_surface_y(centre.x + offset.x, centre.y + offset.z)
				var height: float = top - 0.2 - ground + 0.3
				if height <= 0.35:
					continue
				parts.append([Vector3(0.24, height, 0.24), Transform3D(turn, Vector3(middle.x + offset.x, ground - 0.3 + height * 0.5, middle.z + offset.z)), REALM_WOOD_DARK])
		# A cross rail on each side, halfway down the tallest posts.
		var rail_y: float = (top - 0.2 + low) * 0.5
		for side in 4:
			var along: Vector3 = turn * (Vector3.RIGHT if side % 2 == 0 else Vector3.BACK)
			var out: Vector3 = turn * (Vector3.BACK if side % 2 == 0 else Vector3.RIGHT) * (half + 0.05) * (1.0 if side < 2 else -1.0)
			var spot: Vector3 = middle + out
			var ground: float = realm_surface_y(spot.x, spot.z)
			if top - 0.2 - ground < 0.9:
				continue
			var rail_basis := Basis(Vector3.UP, facing + (0.0 if side % 2 == 0 else PI * 0.5))
			parts.append([Vector3(half * 2.0 + 0.1, 0.12, 0.12), Transform3D(rail_basis, Vector3(spot.x, maxf(rail_y, ground + 0.4), spot.z)), REALM_WOOD_DARK])
			# A diagonal brace from the rail up to the deck corner, like a real timber frame.
			var rise: float = top - 0.2 - maxf(rail_y, ground + 0.4)
			if rise > 0.35:
				var run: float = half
				var brace_basis := rail_basis * Basis(Vector3.BACK, atan2(rise, run))
				var mid_y: float = maxf(rail_y, ground + 0.4) + rise * 0.5
				var shift: Vector3 = (rail_basis * Vector3.RIGHT) * (half * 0.5)
				parts.append([Vector3(sqrt(rise * rise + run * run), 0.1, 0.1), Transform3D(brace_basis, Vector3(spot.x, mid_y, spot.z) + shift), REALM_WOOD_DARK])
	parent.add_child(_realm_props(parts))
	return top


# Bridges where the manor's roads cross the river, and a jetty at every fishing spot. A handful of
# one-draw-call meshes, built once.
func _realm_build_river_works() -> void:
	for bridge: Dictionary in realm.bridges:
		_realm_root.add_child(_realm_bridge(bridge))
	for spot: Dictionary in realm.fishing_spots:
		var jetty: MeshInstance3D = _realm_jetty(spot)
		jetty.name = "Jetty_%d" % int(spot["id"])
		_realm_root.add_child(jetty)


func _realm_bridge(bridge: Dictionary) -> MeshInstance3D:
	var dir: Vector2 = bridge["dir"]
	var centre: Vector2 = bridge["pos"]
	var length: float = float(bridge["length"])
	var yaw: float = atan2(dir.x, dir.y)
	var parts: Array = []
	var planks: int = maxi(6, ceili(length / 0.9))
	var plank: float = length / float(planks)
	var half_width: float = RealmMap.BRIDGE_WIDTH * 0.5
	for index in planks:
		var along: float = -length * 0.5 + (float(index) + 0.5) * plank
		var y0: float = _realm_deck_y(bridge, along - plank * 0.5)
		var y1: float = _realm_deck_y(bridge, along + plank * 0.5)
		var pitch: float = -atan2(y1 - y0, plank)
		var at: Vector2 = centre + dir * along
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var tone: Color = REALM_WOOD.lerp(REALM_WOOD_DARK, 0.35 if index % 3 == 1 else 0.0)
		parts.append([Vector3(RealmMap.BRIDGE_WIDTH, 0.14, plank * 0.94), Transform3D(basis, Vector3(at.x, (y0 + y1) * 0.5 - 0.07, at.y)), tone])
		# Rails along both sides.
		for side: float in [-1.0, 1.0]:
			var edge: Vector3 = Basis(Vector3.UP, yaw) * Vector3(side * (half_width - 0.06), 0, 0)
			parts.append([Vector3(0.1, 0.1, plank), Transform3D(basis, Vector3(at.x + edge.x, (y0 + y1) * 0.5 + 0.62, at.y + edge.z)), REALM_WOOD_DARK])
			if index % 2 == 0:
				parts.append([Vector3(0.12, 0.7, 0.12), Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x + edge.x, y0 + 0.3, at.y + edge.z)), REALM_WOOD_DARK])
	# Piles down into the river bed every few metres.
	var piles: int = maxi(2, int(length / 4.5))
	for index in piles:
		var along: float = -length * 0.5 + length * (float(index) + 0.5) / float(piles)
		var at: Vector2 = centre + dir * along
		var deck: float = _realm_deck_y(bridge, along)
		var bed: float = realm_surface_y(at.x, at.y) - 0.3
		for side: float in [-1.0, 1.0]:
			var edge: Vector3 = Basis(Vector3.UP, yaw) * Vector3(side * (half_width - 0.15), 0, 0)
			parts.append([Vector3(0.26, deck - bed, 0.26), Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x + edge.x, (deck + bed) * 0.5 - 0.1, at.y + edge.z)), REALM_WOOD_DARK.darkened(0.15)])
	var node: MeshInstance3D = _realm_props(parts)
	node.name = "Bridge"
	return node


func _realm_deck_y(bridge: Dictionary, along: float) -> float:
	var dir: Vector2 = bridge["dir"]
	var at: Vector2 = (bridge["pos"] as Vector2) + dir * clampf(along, -float(bridge["length"]) * 0.5 + 0.01, float(bridge["length"]) * 0.5 - 0.01)
	var deck: float = realm.bridge_deck_at(at.x, at.y)
	return deck if not is_nan(deck) else RealmMap.WATER_Y + 0.5


# A short plank jetty from the bank out over the water, on two pairs of posts.
func _realm_jetty(spot: Dictionary) -> MeshInstance3D:
	var dir: Vector2 = spot["dir"]
	var start: Vector2 = spot["pos"]
	var yaw: float = atan2(dir.x, dir.y)
	var deck: float = maxf(realm_surface_y(start.x, start.y), RealmMap.WATER_Y + 0.35) + 0.08
	var reach: float = 4.6
	var parts: Array = []
	var planks: int = 6
	for index in planks:
		var along: float = (float(index) + 0.5) * reach / float(planks)
		var at: Vector2 = start + dir * along
		var tone: Color = REALM_WOOD.lerp(REALM_WOOD_DARK, 0.3 if index % 2 == 1 else 0.0)
		parts.append([Vector3(1.5, 0.12, reach / float(planks) * 0.92), Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, deck, at.y)), tone])
	for along: float in [reach * 0.45, reach - 0.2]:
		var at: Vector2 = start + dir * along
		var bed: float = realm_surface_y(at.x, at.y) - 0.3
		for side: float in [-1.0, 1.0]:
			var edge: Vector3 = Basis(Vector3.UP, yaw) * Vector3(side * 0.66, 0, 0)
			parts.append([Vector3(0.2, deck + 0.35 - bed, 0.2), Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x + edge.x, (deck + 0.35 + bed) * 0.5, at.y + edge.z)), REALM_WOOD_DARK])
	return _realm_props(parts)


# Someone fishes from every jetty on held land (the manor's or a neighbour's); wild banks stand
# empty. Only the nearest few get a figure, a bobbing float and a ripple.
func _realm_stream_fishers(focus: Vector2, reach: float) -> void:
	var cap: int = REALM_FISHERS_LOW if _realm_phone else REALM_FISHERS
	var near: Array[Dictionary] = []
	for spot: Dictionary in realm.fishing_spots:
		var pos: Vector2 = spot["pos"]
		if pos.distance_to(focus) <= reach and realm.owner_at(pos.x, pos.y) != "":
			near.append(spot)
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector2).distance_squared_to(focus) < (b["pos"] as Vector2).distance_squared_to(focus))
	if near.size() > cap:
		near.resize(cap)
	var keep: Array[int] = []
	for spot: Dictionary in near:
		keep.append(int(spot["id"]))
	for id: int in _realm_fishers.keys():
		if id not in keep:
			(_realm_fishers[id]["root"] as Node3D).queue_free()
			_realm_fishers.erase(id)
	for spot: Dictionary in near:
		var id: int = int(spot["id"])
		if not _realm_fishers.has(id):
			_realm_fishers[id] = _realm_build_fisher(spot)


func _realm_build_fisher(spot: Dictionary) -> Dictionary:
	var dir: Vector2 = spot["dir"]
	var start: Vector2 = spot["pos"]
	var root := Node3D.new()
	root.name = "Fisher_%d" % int(spot["id"])
	_realm_root.add_child(root)
	var deck: float = maxf(realm_surface_y(start.x, start.y), RealmMap.WATER_Y + 0.35) + 0.14
	var stand: Vector2 = start + dir * 3.9
	var record: Dictionary = {"root": root, "model": null, "player": null, "clip": ""}
	if _asset_exists("char_fisherman"):
		var body: Node3D = _model("char_fisherman")
		body.position = Vector3(stand.x, deck, stand.y)
		body.rotation.y = atan2(dir.x, dir.y)
		root.add_child(body)
		record["model"] = body
		record["player"] = _find_player_cached("char_fisherman", body)
	var cast: Vector2 = start + dir * 7.4
	var bobber := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.09
	ball.height = 0.18
	ball.radial_segments = 6
	ball.rings = 3
	bobber.mesh = ball
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("c0442e")
	red.emission_enabled = true
	red.emission = Color("5a1a10")
	bobber.material_override = red
	bobber.position = Vector3(cast.x, RealmMap.WATER_Y + 0.04, cast.y)
	bobber.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bobber)
	var ripple := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.5
	ring.rings = 12
	ring.ring_segments = 3
	ripple.mesh = ring
	var foam := StandardMaterial3D.new()
	foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.albedo_color = Color(0.75, 0.85, 0.85, 0.5)
	ripple.material_override = foam
	ripple.position = Vector3(cast.x, RealmMap.WATER_Y + 0.02, cast.y)
	ripple.scale = Vector3(1.0, 0.15, 1.0)
	ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ripple)
	record["bobber"] = bobber
	record["ripple"] = ripple
	return record


# The float bobs and a ripple spreads from it; the fisher reels. Paused time freezes them.
func _realm_animate_fishers(delta: float) -> void:
	_realm_fish_time += delta
	for record: Dictionary in _realm_fishers.values():
		var player: AnimationPlayer = record["player"]
		if player != null:
			player.speed_scale = 0.0 if delta <= 0.0 else 1.0
			if record["clip"] != "work" and player.has_animation("work"):
				player.get_animation("work").loop_mode = Animation.LOOP_LINEAR
				player.play("work", 0.2)
				record["clip"] = "work"
		if delta <= 0.0:
			continue
		var bobber: Node3D = record["bobber"]
		bobber.position.y = RealmMap.WATER_Y + 0.04 + sin(_realm_fish_time * 2.6 + bobber.position.x) * 0.035
		var ripple: MeshInstance3D = record["ripple"]
		var grow: float = fmod(_realm_fish_time * 0.45 + bobber.position.z * 0.1, 1.0)
		ripple.scale = Vector3(0.4 + grow * 1.6, 0.15, 0.4 + grow * 1.6)
		(ripple.material_override as StandardMaterial3D).albedo_color.a = 0.5 * (1.0 - grow)


func realm_fishers_loaded() -> int:
	return _realm_fishers.size()
