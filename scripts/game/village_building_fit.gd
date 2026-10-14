extends "res://scripts/game/village_realm_life.gd"

# Building fit, over the realm layer: how each non-defense building sits in the village (visual
# only, no simulation effect). Walls, gates, towers, siege and traps are dressed by their own layer.
#
#   * Light comes from something you can see. The shared night glow (a soft disc floating in front
#     of the building) and the billboard window dots are retired: houses hang an iron lantern by the
#     door, yards and works get a lantern post, and fire-lit places (monuments, gates, embers) a
#     brazier. The pooled lamp light sits on that flame. The models' own amber windows still glow.
#   * Every type that had no art of its own, or borrowed a smaller sibling's, is built to fill its
#     plot: Lantern Rows, the Shieldwall Yard, the Stone Road Network, the City Wall, the Citadel,
#     the Grand Watchtower, the Monument, the Grand Granary, the Manor Gardens, the Royal Forge
#     Quarter, the Grand Market Square and the Steam Bathhouse.
#   * Small fixes: water in the pond, weir and deephole, a frosted Frostwood Grove, glowing
#     Emberglass, a moonstone on the Moon Dial, a belfry lantern, and the quarry's cut stone kept
#     inside its tile.
#
# Every added part is a child of the building's model, so it hides with the ruins, shakes with
# hits and leans with the model. Launch with --no-building-fit to see the plain models.

const FIT_SKIP: Array[String] = ["wall", "stonewall", "gate", "rampart", "tower", "archer_tower",
	"ballista", "bastion", "trap", "fire-trap", "watchfire"]
# A lantern on a bracket beside the door.
const FIT_DOOR: Array[String] = ["hall", "cottage", "longhouse", "barracks", "storehouse", "chapel",
	"schoolroom", "armory", "workshop", "tannery", "butchery", "scriptorium", "fletcher", "bakery",
	"bathhouse", "grand-granary"]
# A lantern on a post at the front corner of the plot.
const FIT_POST: Array[String] = ["mill", "lumber", "timber_yard", "mine", "stone_quarry", "mason_yard",
	"sawmill", "market", "scout_post", "deephole", "blackwater-weir", "pasture", "smeltery",
	"emberglass", "sunken-chapel", "cairnfield", "bellcote", "moon-dial", "oathstone"]
# Living things: the shared dark soot weathering turned orchards, fields and pasture near-black
# at night; they take a lighter cast so leaves and crops still read green and gold.
const FIT_GREEN: Array[String] = ["grove", "whisper-grove", "farm", "pasture", "cairnfield"]
const FIT_SOOT_OLD := Color("957f68")
const FIT_SOOT_GREEN := Color(0.9, 0.86, 0.76)
const FIT_IRON := Color(0.17, 0.16, 0.17)
const FIT_WOOD := Color("5a4030")
const FIT_WOOD_DARK := Color("3f2b1c")
const FIT_STONE := Color("8a847a")
const FIT_STONE_DARK := Color("625d56")
const FIT_COBBLE := Color("77736b")
const FIT_FLAME := Color(1.0, 0.55, 0.16)
const FIT_FLAME_CORE := Color(1.0, 0.9, 0.6)
const FIT_WATER := Color("1f4250")
const FIT_HEDGE := Color("2f4a26")
const FIT_LAMP_RANGE: float = 4.0
const FIT_LANTERN_SIZE: float = 1.6          # lantern scale, so the cage and flame read at village zoom
# The models are weathered with a warm soot multiply; dressing takes the same cast so it sits in.
const FIT_SOOT := Color(0.66, 0.6, 0.53)

var _fit_on: bool = true
var _fit_mats: Dictionary = {}                  # "html|kind" -> shared material


func _ready() -> void:
	super()
	_fit_on = "--no-building-fit" not in OS.get_cmdline_user_args()


func _rebuild_buildings() -> void:
	super()
	if not _fit_on:
		return
	for b: Dictionary in sim.buildings:
		if str(b["type"]) in FIT_SKIP:
			continue
		var view: Dictionary = building_views.get(int(b["id"]), {})
		if view.is_empty() or view.has("fit"):
			continue
		_fit_dress(b, view)


# Smoke rises from the chimney the model actually has. The art's chimneys are stacked blocks off
# the ridge line whose cap stands higher than the ridge; a model without one (barracks, butchery)
# gets no smoke rather than a puff rising out of its roof.
var _fit_chimneys: Dictionary = {}              # asset key -> Vector3 cap centre (model units), or null


func _fit_chimney(view: Dictionary) -> void:
	var model: Node3D = view["model"]
	var cap: Variant = _fit_chimney_cap(model)
	view["fit"]["chimney"] = cap
	var smoke: Node3D = view.get("smoke")
	if is_instance_valid(smoke):
		if cap == null:
			smoke.queue_free()
			view.erase("smoke")
			details.smoke_count = maxi(0, details.smoke_count - 1)
		else:
			smoke.position = (view["root"] as Node3D).to_local(model.to_global(cap as Vector3)) + Vector3(0, 0.08, 0)


func _fit_chimney_cap(model: Node3D) -> Variant:
	var key: String = str(model.name)
	if _fit_chimneys.has(key):
		return _fit_chimneys[key]
	var ridge: float = 0.0
	var tops: Array[Vector3] = []
	var faces: PackedVector3Array = _fit_model_faces(model, "Architecture")
	for i in range(0, faces.size(), 3):
		var a: Vector3 = faces[i]
		if absf(a.y - faces[i + 1].y) > 0.002 or absf(a.y - faces[i + 2].y) > 0.002 or a.y < 0.9:
			continue
		var centre: Vector3 = (a + faces[i + 1] + faces[i + 2]) / 3.0
		if absf(centre.x) < 0.15:
			ridge = maxf(ridge, a.y)
		else:
			tops.append(centre)
	var best: float = ridge + 0.02
	var cap: Variant = null
	var found: Array[Vector3] = []
	for top: Vector3 in tops:
		if top.y > best + 0.005:
			best = top.y
			found = [top]
		elif absf(top.y - best) <= 0.005 and not found.is_empty():
			found.append(top)
	if not found.is_empty():
		var sum := Vector3.ZERO
		for top: Vector3 in found:
			sum += top
		cap = sum / float(found.size())
	_fit_chimneys[key] = cap
	return cap


# The village effects layer's chimney smoke starts from a fixed offset per type; start it from the
# building's real chimney cap instead, and none for a building without one.
func _vfx_site_make(building: Dictionary) -> CPUParticles3D:
	var site: CPUParticles3D = super(building)
	if not _fit_on or not site.has_meta("smoke"):
		return site
	var view: Dictionary = building_views.get(int(building["id"]), {})
	if view.is_empty() or not view.has("fit"):
		return site
	var cap: Variant = view["fit"].get("chimney")
	if cap == null:
		site.emitting = false
		site.visible = false
	else:
		site.global_position = (view["model"] as Node3D).to_global(cap as Vector3) + Vector3(0, 0.1, 0)
	return site


# Chimney smoke, sparks and sawdust are placed once when a site starts; a moved building would
# leave them puffing on its old plot. Restart any site whose building has moved.
func _vfx_sync_sites() -> void:
	super()
	for id: Variant in _vfx_sites.keys():
		var site: Node3D = _vfx_sites[id]
		var building: Dictionary = sim.get_building(int(id))
		if building.is_empty() or not is_instance_valid(site):
			continue
		var spot := Vector2i(int(building["x"]), int(building["y"]))
		if not site.has_meta("fit_spot"):
			site.set_meta("fit_spot", spot)
		elif site.get_meta("fit_spot") != spot:
			site.queue_free()
			_vfx_sites[id] = _vfx_site_make(building)
			(_vfx_sites[id] as Node3D).set_meta("fit_spot", spot)


func _fit_dress(b: Dictionary, view: Dictionary) -> void:
	var model: Node3D = view["model"]
	if not is_instance_valid(model):
		return
	var type_name: String = str(b["type"])
	var tier: int = int(b["tier"])
	var plot: float = float(b["size"]) * TILE
	# The billboard window dots float off the walls; the models' amber windows are the light.
	for pane: Variant in view.get("windows", []):
		if is_instance_valid(pane):
			(pane as Node).queue_free()
	view.erase("windows")
	var fit := {"type": type_name}
	view["fit"] = fit
	# The seeded lean tipped whole plots, plinth and all, so one edge floated off the ground and
	# the other sank into it. Plinths sit flat; the building keeps its character from its art.
	model.rotation.z = 0.0
	if type_name in FIT_GREEN:
		_fit_lift_soot(model)
	match type_name:
		"lantern-rows": _fit_lantern_rows(view, plot, tier)
		"shieldwall-yard": _fit_shieldwall_yard(view, plot, tier)
		"stone-road": _fit_stone_road(view, plot, tier)
		"city-wall": _fit_city_wall(view, plot, tier)
		"manner-citadel": _fit_citadel(view, plot, tier)
		"grand-watchtower": _fit_grand_watchtower(view, plot)
		"monument": _fit_monument(view, plot, tier)
		"grand-granary": _fit_granary(view, plot)
		"manor-gardens": _fit_gardens(view, plot, tier)
		"forge-quarter": _fit_forge_quarter(view, plot)
		"market-square": _fit_market_square(view, plot, tier)
		"bathhouse": _fit_bathhouse(view, plot)
		"pond", "blackwater-weir", "deephole": _fit_water(view, type_name, plot)
		"frostgrove": _fit_frost(view)
		"emberglass": _fit_embers(view)
		"moon-dial": _fit_moonstone(view)
		"bell-tower": _fit_belfry(view)
		"dawn-gate": _fit_dawn_gate(view, plot)
		"stone_quarry": _fit_quarry_stone(view)
		"forge": _fit_forge_fire(view)
		"market": _fit_market_wares(view, plot, tier)
		"grove", "whisper-grove": _fit_berries(view, type_name)
		"mill", "sawmill": _fit_spinners(view)
	_fit_chimney(view)
	if type_name in FIT_DOOR:
		_fit_door_lantern(view)
	elif type_name in FIT_POST:
		_fit_post_lantern(view, plot)


func _fit_lift_soot(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		if part.mesh != null:
			for surface in part.mesh.get_surface_count():
				var override := part.get_surface_override_material(surface) as BaseMaterial3D
				if override != null and override.albedo_color.is_equal_approx(FIT_SOOT_OLD):
					override.albedo_color = FIT_SOOT_GREEN
	for child in node.get_children():
		_fit_lift_soot(child)


# --- shared parts -------------------------------------------------------------------------------

# A holder under the model that cancels its scale, so dressing is placed in metres from the
# building centre and still hides, shakes and leans with the model.
func _fit_holder(view: Dictionary) -> Node3D:
	var model: Node3D = view["model"]
	var holder: Node3D = view["fit"].get("holder")
	if is_instance_valid(holder):
		return holder
	holder = Node3D.new()
	holder.name = "BuildingFit"
	model.add_child(holder)
	holder.scale = Vector3.ONE / maxf(model.scale.x, 0.001)
	view["fit"]["holder"] = holder
	return holder


# Re-scales the model and keeps the holder in metres.
func _fit_rescale(view: Dictionary, factor: float) -> void:
	var model: Node3D = view["model"]
	model.scale = Vector3.ONE * factor
	var holder: Node3D = view["fit"].get("holder")
	if is_instance_valid(holder):
		holder.scale = Vector3.ONE / factor
	var label: Node3D = view.get("label")
	if is_instance_valid(label):
		var top: float = _fit_bounds(model).end.y * factor
		label.position.y = top + 0.5


# The model's own art bounds (not its ground plate, not added dressing), in model units.
func _fit_bounds(model: Node3D) -> AABB:
	var found := AABB()
	var any: bool = false
	for part in model.get_children():
		if not part is MeshInstance3D or not str(part.name).begins_with("MMR"):
			continue
		var mesh_node := part as MeshInstance3D
		if mesh_node.mesh == null or "ground" in str(mesh_node.name).to_lower():
			continue
		var box: AABB = mesh_node.transform * mesh_node.mesh.get_aabb()
		found = box if not any else found.merge(box)
		any = true
	return found if any else AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))


# Hides the borrowed (or fallback) art so a composition can stand in its place.
func _fit_hide_native(view: Dictionary, keep_ground: bool = false) -> void:
	var model: Node3D = view["model"]
	for part in model.get_children():
		if part is MeshInstance3D and str(part.name).begins_with("MMR"):
			if keep_ground and "ground" in str((part as Node).name).to_lower():
				continue
			(part as MeshInstance3D).visible = false


func _fit_mat(color: Color, kind: String = "") -> StandardMaterial3D:
	var key: String = color.to_html() + "|" + kind
	if _fit_mats.has(key):
		return _fit_mats[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color if kind in ["flame", "glow"] else color * FIT_SOOT
	material.roughness = 0.88
	match kind:
		"flame":
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"glow":
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 1.6
		"water":
			material.roughness = 0.12
			material.metallic = 0.25
			material.metallic_specular = 0.8
	_fit_mats[key] = material
	return material


func _fit_box(parent: Node3D, size: Vector3, at: Vector3, color: Color, kind: String = "", turn: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "FitPart"
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _fit_mat(color, kind)
	node.position = at
	node.rotation.y = turn
	if kind == "flame":
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _fit_cylinder(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, color: Color, kind: String = "", sides: int = 8) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "FitPart"
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	node.mesh = mesh
	node.material_override = _fit_mat(color, kind)
	node.position = at
	if kind == "flame":
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


# A flame you can see: a hot inner tongue inside a taller amber one.
func _fit_flame(parent: Node3D, at: Vector3, height: float, color: Color = FIT_FLAME) -> Node3D:
	var flame := Node3D.new()
	flame.name = "FitFlame"
	parent.add_child(flame)
	flame.position = at
	_fit_cylinder(flame, 0.0, height * 0.32, height, Vector3(0, height * 0.5, 0), color, "flame", 6)
	_fit_cylinder(flame, 0.0, height * 0.18, height * 0.62, Vector3(0, height * 0.31, 0), FIT_FLAME_CORE, "flame", 6)
	return flame


# The building's night lamp, moved onto a flame (made if the building had none). The old floating
# glow disc is parked out of sight; the game's light pool still switches the lamp.
func _fit_light(view: Dictionary, at: Vector3, color: Color = Color("ffc474"), reach: float = FIT_LAMP_RANGE) -> void:
	var holder: Node3D = _fit_holder(view)
	var lamp: OmniLight3D = view.get("lamp")
	if not is_instance_valid(lamp):
		lamp = OmniLight3D.new()
		lamp.light_energy = 0.8
		lamp.visible = night
		view["root"].add_child(lamp)
		view["lamp"] = lamp
	if lamp.get_parent() != holder:
		lamp.reparent(holder, false)
	lamp.light_color = color
	lamp.position = at
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.1
	lamp.shadow_enabled = false
	var glow: MeshInstance3D = view.get("glow")
	if is_instance_valid(glow) and glow.get_parent() == view["root"]:
		var parked := Node3D.new()
		parked.name = "ParkedGlow"
		parked.visible = false
		holder.add_child(parked)
		glow.reparent(parked, false)


# An iron lantern: cage, cap, flame. Its local -Z is the side a bracket reaches back to.
func _fit_lantern(parent: Node3D, at: Vector3, bracket: float = 0.0, turn: float = 0.0, glass: Color = FIT_FLAME) -> Node3D:
	var lantern := Node3D.new()
	lantern.name = "FitLantern"
	parent.add_child(lantern)
	lantern.position = at
	lantern.rotation.y = turn
	if bracket > 0.0:
		var reach: float = bracket / FIT_LANTERN_SIZE
		_fit_box(lantern, Vector3(0.03, 0.03, reach), Vector3(0, 0.13, -reach * 0.5), FIT_IRON)
	_fit_box(lantern, Vector3(0.16, 0.03, 0.16), Vector3(0, 0.1, 0), FIT_IRON)
	_fit_box(lantern, Vector3(0.13, 0.02, 0.13), Vector3(0, -0.1, 0), FIT_IRON)
	for corner: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		_fit_box(lantern, Vector3(0.02, 0.2, 0.02), Vector3(corner.x * 0.06, 0, corner.y * 0.06), FIT_IRON)
	_fit_flame(lantern, Vector3(0, -0.09, 0), 0.15, glass)
	lantern.scale = Vector3.ONE * FIT_LANTERN_SIZE
	for child in lantern.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lantern


# A lantern post: a dark timber post with an arm and a hanging lantern. Returns the flame point.
func _fit_lantern_post(parent: Node3D, foot: Vector3, height: float = 1.45, turn: float = 0.0, glass: Color = FIT_FLAME) -> Vector3:
	var post := Node3D.new()
	post.name = "FitPost"
	parent.add_child(post)
	post.position = foot
	post.rotation.y = turn
	_fit_box(post, Vector3(0.16, 0.06, 0.16), Vector3(0, 0.03, 0), FIT_STONE_DARK)
	_fit_box(post, Vector3(0.08, height, 0.08), Vector3(0, height * 0.5, 0), FIT_WOOD_DARK)
	_fit_box(post, Vector3(0.04, 0.04, 0.3), Vector3(0, height - 0.06, 0.13), FIT_IRON)
	_fit_lantern(post, Vector3(0, height - 0.26, 0.26), 0.0, 0.0, glass)
	return foot + Vector3(0, height - 0.32, 0.26).rotated(Vector3.UP, turn)


# A stone fire bowl. Returns the flame point.
func _fit_brazier(parent: Node3D, foot: Vector3, height: float = 0.55, color: Color = FIT_FLAME) -> Vector3:
	_fit_cylinder(parent, 0.09, 0.13, height, foot + Vector3(0, height * 0.5, 0), FIT_STONE_DARK, "", 6)
	_fit_cylinder(parent, 0.2, 0.11, 0.12, foot + Vector3(0, height + 0.06, 0), FIT_IRON, "", 8)
	_fit_flame(parent, foot + Vector3(0, height + 0.08, 0), 0.34, color)
	return foot + Vector3(0, height + 0.25, 0)


# --- probing the art ------------------------------------------------------------------------------
#
# Dressing is placed against the real geometry (wall faces, roof ridges, canopy tops), found by
# casting rays at a model's triangles. Each model's faces and every answer are cached per asset,
# so a village of sixty buildings probes each kind once.

var _fit_faces: Dictionary = {}                 # "asset|filter" -> PackedVector3Array
var _fit_casts: Dictionary = {}                 # "asset|filter|origin|direction" -> float


func _fit_model_faces(model: Node3D, filter: String) -> PackedVector3Array:
	var key: String = str(model.name) + "|" + filter
	if _fit_faces.has(key):
		return _fit_faces[key]
	var faces := PackedVector3Array()
	for part in model.get_children():
		if not part is MeshInstance3D or not str(part.name).begins_with("MMR") or (part as MeshInstance3D).mesh == null:
			continue
		if not filter.is_empty() and filter not in str(part.name):
			continue
		var local: PackedVector3Array = (part as MeshInstance3D).mesh.get_faces()
		var transform: Transform3D = (part as MeshInstance3D).transform
		for v: Vector3 in local:
			faces.append(transform * v)
	_fit_faces[key] = faces
	return faces


# Distance along direction from origin to the first hit, or -1.0 for a miss.
func _fit_cast(model: Node3D, origin: Vector3, direction: Vector3, filter: String) -> float:
	var key: String = "%s|%s|%s|%s" % [model.name, filter, origin, direction]
	if _fit_casts.has(key):
		return _fit_casts[key]
	var faces: PackedVector3Array = _fit_model_faces(model, filter)
	var best: float = INF
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, faces[i], faces[i + 1], faces[i + 2])
		if hit != null:
			best = minf(best, origin.distance_to(hit as Vector3))
	var result: float = best if best < INF else -1.0
	_fit_casts[key] = result
	return result


# The front (+Z) surface of the walls at (x, y) in model units; eaves above and kerbs below the ray
# are never hit, so a bracket meets the wall itself.
func _fit_wall_z(model: Node3D, x: float, y: float) -> float:
	var hit: float = _fit_cast(model, Vector3(x, y, 5.0), Vector3.FORWARD, "Architecture")
	return 5.0 - hit if hit >= 0.0 else _fit_bounds(model).end.z


# The right-hand (+X) surface at (z, y) in model units.
func _fit_wall_x(model: Node3D, z: float, y: float) -> float:
	var hit: float = _fit_cast(model, Vector3(5.0, y, z), Vector3.LEFT, "Architecture")
	return 5.0 - hit if hit >= 0.0 else _fit_bounds(model).end.x


# The top of the plinth, kerb or ground plate at (x, z) in model units (capped below roofs).
func _fit_surface_y(model: Node3D, x: float, z: float) -> float:
	var hit: float = _fit_cast(model, Vector3(x, 0.4, z), Vector3.DOWN, "")
	return 0.4 - hit if hit >= 0.0 else 0.0


# The top of the model's art (canopies, roofs) at (x, z) in model units.
func _fit_surface_y_any(model: Node3D, x: float, z: float) -> float:
	var hit: float = _fit_cast(model, Vector3(x, 8.0, z), Vector3.DOWN, "Architecture")
	return 8.0 - hit if hit >= 0.0 else 0.0


# --- lighting ------------------------------------------------------------------------------------

# A lantern on the door wall (+Z, the face the camera sees), to the right of the door, its bracket
# reaching back to the wall surface itself (found from the mesh, not the eaves-wide bounds).
func _fit_door_lantern(view: Dictionary) -> void:
	var model: Node3D = view["model"]
	var factor: float = model.scale.x
	var bounds: AABB = view["fit"].get("bounds", _fit_bounds(model))
	var offset: Vector3 = model.position
	var x_model: float = bounds.get_center().x + bounds.size.x * 0.28
	var y_model: float = clampf(bounds.size.y * 0.36, 0.45, 0.8)
	var wall: float = _fit_wall_z(model, x_model, y_model)
	var at := Vector3(x_model * factor, y_model * factor, wall * factor + 0.17) + offset
	# The holder cancels the model's scale and offset, so its space is the plot's, centred.
	_fit_lantern(_fit_holder(view), at, 0.17)
	_fit_light(view, at + Vector3(0, -0.06, 0.12))


# A lantern post on the front corner, between the walls and the edge of the plinth.
func _fit_post_lantern(view: Dictionary, plot: float) -> void:
	var model: Node3D = view["model"]
	var factor: float = model.scale.x
	var bounds: AABB = _fit_bounds(model)
	var edge: float = plot * 0.5 - 0.14
	var x: float = minf(bounds.end.x * factor + 0.12, edge)
	var z: float = minf(bounds.end.z * factor + 0.12, edge)
	var height: float = 1.2 if plot <= TILE else 1.5
	var foot: float = _fit_surface_y(model, x / factor, z / factor) * factor
	var flame: Vector3 = _fit_lantern_post(_fit_holder(view), Vector3(x, foot, z), height, -PI * 0.25)
	_fit_light(view, flame)


# --- compositions --------------------------------------------------------------------------------

# Lantern Rows: a lit promenade. Two rows of lantern posts along a cobbled walk; later tiers add
# posts and swap to pale moon-glass.
func _fit_lantern_rows(view: Dictionary, plot: float, tier: int) -> void:
	_fit_hide_native(view)
	var holder: Node3D = _fit_holder(view)
	var half: float = plot * 0.5 - 0.1
	_fit_box(holder, Vector3(plot - 0.2, 0.06, plot - 0.2), Vector3(0, 0.03, 0), FIT_STONE_DARK)
	_fit_box(holder, Vector3(plot - 0.5, 0.07, 1.3), Vector3(0, 0.05, 0), FIT_COBBLE)
	for k in 7:
		_fit_box(holder, Vector3(0.36, 0.03, 0.26), Vector3(-1.5 + k * 0.5, 0.095, -0.25 + (k % 2) * 0.5), FIT_STONE)
	# Grass verges with low box hedges behind the posts.
	for z: float in [-half + 0.32, half - 0.32]:
		_fit_box(holder, Vector3(plot - 0.4, 0.05, 0.5), Vector3(0, 0.05, z), Color("4a5a2e"))
		_fit_box(holder, Vector3(plot - 0.6, 0.28, 0.2), Vector3(0, 0.17, z + signf(z) * 0.12), FIT_HEDGE)
	var posts: int = 3 if tier <= 1 else 4
	var glass: Color = FIT_FLAME if tier < 3 else Color(0.62, 0.8, 1.0)
	var span: float = plot - 1.0
	var middle := Vector3.ZERO
	for row: float in [-0.85, 0.85]:
		for k in posts:
			var x: float = -span * 0.5 + span * float(k) / float(posts - 1)
			var flame: Vector3 = _fit_lantern_post(holder, Vector3(x, 0.08, row), 1.45, 0.0 if row < 0 else PI, glass)
			middle += flame
	middle /= float(posts * 2)
	_fit_light(view, middle + Vector3(0, 0.2, 0), Color("ffc474") if tier < 3 else Color("b9d4ff"), 4.2)
	view["fit"]["bounds"] = AABB(Vector3(-1, 0, -1), Vector3(2, 0.8, 2))


# Shieldwall Yard: a training ground. Packed earth inside a rail fence, a rack of spears and round
# shields, two straw dummies and a standing shield wall.
func _fit_shieldwall_yard(view: Dictionary, plot: float, tier: int) -> void:
	_fit_hide_native(view)
	var holder: Node3D = _fit_holder(view)
	var half: float = plot * 0.5 - 0.12
	_fit_box(holder, Vector3(plot - 0.2, 0.06, plot - 0.2), Vector3(0, 0.03, 0), Color("7a6248"))
	_fit_box(holder, Vector3(plot - 0.7, 0.02, plot - 0.7), Vector3(0, 0.065, 0), Color("8c7354"))
	# Rail fence on the back and left edges.
	for k in 5:
		var t: float = -half + (2.0 * half) * float(k) / 4.0
		_fit_box(holder, Vector3(0.09, 0.62, 0.09), Vector3(t, 0.31, -half), FIT_WOOD_DARK)
		_fit_box(holder, Vector3(0.09, 0.62, 0.09), Vector3(-half, 0.31, t), FIT_WOOD_DARK)
	for y: float in [0.28, 0.5]:
		_fit_box(holder, Vector3(2.0 * half, 0.05, 0.05), Vector3(0, y, -half), FIT_WOOD)
		_fit_box(holder, Vector3(0.05, 0.05, 2.0 * half), Vector3(-half, y, 0), FIT_WOOD)
	# Weapon rack against the back fence: spears and round shields.
	var rack := Vector3(0.45, 0, -half + 0.28)
	for x: float in [-0.55, 0.55]:
		_fit_box(holder, Vector3(0.08, 0.95, 0.08), rack + Vector3(x, 0.475, 0), FIT_WOOD_DARK)
	_fit_box(holder, Vector3(1.2, 0.07, 0.1), rack + Vector3(0, 0.82, 0), FIT_WOOD)
	_fit_box(holder, Vector3(1.2, 0.07, 0.1), rack + Vector3(0, 0.3, 0), FIT_WOOD)
	for k in 5:
		var spear: MeshInstance3D = _fit_box(holder, Vector3(0.03, 1.25, 0.03), rack + Vector3(-0.42 + k * 0.21, 0.66, 0.05), FIT_WOOD)
		spear.rotation.x = -0.1
		_fit_cylinder(holder, 0.0, 0.035, 0.12, rack + Vector3(-0.42 + k * 0.21, 1.32, 0.12), Color("b5b2aa"), "", 4)
	var colours: Array[Color] = [Color("8a2a24"), Color("c8a14a"), Color("2d4a6a")]
	# The shield wall: overlapping round shields braced on the yard, facing the camera.
	var shields: int = 4 if tier <= 1 else 5
	for k in shields:
		var shield := _fit_cylinder(holder, 0.26, 0.26, 0.05, Vector3(-0.85 + k * 0.42, 0.34, 0.75), colours[k % 3], "", 10)
		shield.rotation.x = PI * 0.5 - 0.18
		_fit_cylinder(holder, 0.07, 0.07, 0.07, Vector3(-0.85 + k * 0.42, 0.34, 0.79), Color("a39a88"), "", 8).rotation.x = PI * 0.5 - 0.18
	# Two straw dummies.
	for spot: Vector3 in [Vector3(-0.85, 0, -0.35), Vector3(0.95, 0, 0.05)]:
		_fit_box(holder, Vector3(0.07, 1.1, 0.07), spot + Vector3(0, 0.55, 0), FIT_WOOD_DARK)
		_fit_box(holder, Vector3(0.62, 0.07, 0.07), spot + Vector3(0, 0.82, 0), FIT_WOOD)
		_fit_box(holder, Vector3(0.3, 0.42, 0.24), spot + Vector3(0, 0.72, 0), Color("c9a75e"))
		_fit_box(holder, Vector3(0.2, 0.2, 0.2), spot + Vector3(0, 1.08, 0), Color("d6b871"))
	var flame: Vector3 = _fit_lantern_post(holder, Vector3(half - 0.1, 0.06, half - 0.1), 1.5, -PI * 0.25)
	_fit_light(view, flame)
	view["fit"]["bounds"] = AABB(Vector3(-1, 0, -1), Vector3(2, 0.7, 2))


# Stone Road Network: a paved crossroads with kerbs, a milestone and street lamps.
func _fit_stone_road(view: Dictionary, plot: float, tier: int) -> void:
	_fit_hide_native(view)
	var holder: Node3D = _fit_holder(view)
	_fit_box(holder, Vector3(plot - 0.15, 0.05, plot - 0.15), Vector3(0, 0.025, 0), Color("4f5a36"))
	_fit_box(holder, Vector3(plot - 0.15, 0.07, 1.2), Vector3(0, 0.04, 0), FIT_COBBLE)
	_fit_box(holder, Vector3(1.2, 0.07, plot - 0.15), Vector3(0, 0.04, 0), FIT_COBBLE)
	# Setts in a staggered course, so the paving reads at village zoom.
	for i in 6:
		for j in 2:
			_fit_box(holder, Vector3(0.26, 0.025, 0.22), Vector3(-1.55 + i * 0.62, 0.085, -0.3 + j * 0.6 + (i % 2) * 0.12), FIT_STONE)
			_fit_box(holder, Vector3(0.22, 0.025, 0.26), Vector3(-0.3 + j * 0.6 + (i % 2) * 0.12, 0.085, -1.55 + i * 0.62), FIT_STONE)
	# Kerbstones on the four inner corners.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_fit_box(holder, Vector3(1.25, 0.1, 0.1), Vector3(sx * 1.25, 0.05, sz * 0.66), FIT_STONE_DARK)
			_fit_box(holder, Vector3(0.1, 0.1, 1.25), Vector3(sx * 0.66, 0.05, sz * 1.25), FIT_STONE_DARK)
	# The milestone on the back corner and lamps on the others.
	var stone := Vector3(-1.25, 0.05, -1.25)
	_fit_box(holder, Vector3(0.36, 0.08, 0.36), stone + Vector3(0, 0.04, 0), FIT_STONE_DARK)
	_fit_box(holder, Vector3(0.26, 0.7, 0.2), stone + Vector3(0, 0.43, 0), FIT_STONE)
	_fit_cylinder(holder, 0.13, 0.13, 0.2, stone + Vector3(0, 0.78, 0), FIT_STONE, "", 8).rotation.x = PI * 0.5
	var corners: Array[Vector3] = [Vector3(1.25, 0.05, 1.25)]
	if tier >= 2:
		corners.append(Vector3(1.25, 0.05, -1.25))
	if tier >= 3:
		corners.append(Vector3(-1.25, 0.05, 1.25))
	var light := Vector3.ZERO
	for corner: Vector3 in corners:
		light = _fit_lantern_post(holder, corner, 1.45, atan2(-corner.x, -corner.z) + PI)
	_fit_light(view, light)
	view["fit"]["bounds"] = AABB(Vector3(-1, 0, -1), Vector3(2, 0.6, 2))


# City Wall Project: a corner of the great wall. A tower at the back corner, stone wall runs along
# the back and left edges, and a brazier in the yard they guard.
func _fit_city_wall(view: Dictionary, plot: float, tier: int) -> void:
	_fit_hide_native(view)
	var holder: Node3D = _fit_holder(view)
	var cell: float = plot * 0.5
	var wall_key: String = model_asset("stonewall", tier)
	var tower_key: String = model_asset("archer_tower", tier)
	_fit_box(holder, Vector3(plot - 0.12, 0.06, plot - 0.12), Vector3(0, 0.03, 0), FIT_STONE_DARK)
	_fit_box(holder, Vector3(cell - 0.2, 0.03, cell - 0.2), Vector3(cell * 0.5, 0.075, cell * 0.5), Color("7a6248"))
	_fit_place(holder, tower_key, Vector3(-cell * 0.5, 0.06, -cell * 0.5), cell, 0.0)
	_fit_place(holder, wall_key, Vector3(cell * 0.5, 0.06, -cell * 0.5), cell, 0.0, 1.06)
	_fit_place(holder, wall_key, Vector3(-cell * 0.5, 0.06, cell * 0.5), cell, PI * 0.5, 1.06)
	var flame: Vector3 = _fit_brazier(holder, Vector3(cell * 0.55, 0.06, cell * 0.55), 0.5)
	_fit_light(view, flame)
	view["fit"]["bounds"] = AABB(Vector3(-1, 0, -1), Vector3(2, 1.6, 2))


# One borrowed model placed inside a composition, scaled to a cell, its ground plate hidden so
# plates never fight. stretch widens it along its run so neighbouring pieces meet.
func _fit_place(holder: Node3D, key: String, at: Vector3, cell: float, turn: float, stretch: float = 1.0) -> Node3D:
	var piece: Node3D = _model(key)
	piece.name = "FitPiece"
	holder.add_child(piece)
	var dims: Array = catalog[key]["dimensions_m"] if catalog.has(key) else [1.3, 1.0, 1.3]
	var factor: float = (cell - 0.05) / maxf(float(dims[0]), float(dims[2]))
	piece.scale = Vector3(factor * stretch, factor, factor)
	piece.position = at
	piece.rotation.y = turn
	for part in piece.find_children("*", "MeshInstance3D", true, false):
		if "ground" in str((part as Node).name).to_lower():
			(part as MeshInstance3D).visible = false
	return piece


# The Manner Citadel: the hall grown into a keep behind a curtain wall: two stone towers on the
# front corners, wall runs and the gate between them, banners on the towers.
func _fit_citadel(view: Dictionary, plot: float, tier: int) -> void:
	var model: Node3D = view["model"]
	_fit_rescale(view, 1.95)
	var holder: Node3D = _fit_holder(view)
	var factor: float = model.scale.x
	var bounds: AABB = _fit_bounds(model)
	model.position.z = -0.55
	holder.position.z = 0.55 / factor
	_fit_box(holder, Vector3(plot - 0.15, 0.05, plot - 0.15), Vector3(0, 0.025, 0), FIT_STONE_DARK)
	var cell: float = 1.25
	var front: float = plot * 0.5 - cell * 0.5 - 0.05
	var tower_key: String = model_asset("archer_tower", clampi(tier + 1, 1, 6))
	var wall_key: String = model_asset("stonewall", clampi(tier, 1, 6))
	for side: float in [-1.0, 1.0]:
		_fit_place(holder, tower_key, Vector3(side * (plot * 0.5 - cell * 0.5 - 0.05), 0.05, front), cell + 0.2, 0.0)
		_fit_place(holder, wall_key, Vector3(side * cell, 0.05, front), cell, 0.0, 1.1)
		_fit_banner(holder, Vector3(side * (plot * 0.5 - 0.25), 0.05, front + 0.55), 2.2, Color("7c1f1f"))
	var gate: Node3D = _fit_place(holder, model_asset("gate", clampi(tier, 1, 6)), Vector3(0, 0.05, front), cell, 0.0, 1.0)
	view["fit"]["bounds"] = bounds
	var flame: Vector3 = _fit_brazier(holder, Vector3(0.85, 0.05, front - 0.9), 0.5)
	_fit_brazier(holder, Vector3(-0.85, 0.05, front - 0.9), 0.5)
	_fit_light(view, flame)
	view["fit"]["lit"] = true


func _fit_banner(holder: Node3D, foot: Vector3, height: float, color: Color) -> void:
	_fit_box(holder, Vector3(0.06, height, 0.06), foot + Vector3(0, height * 0.5, 0), FIT_WOOD_DARK)
	_fit_box(holder, Vector3(0.36, 0.04, 0.04), foot + Vector3(0.16, height - 0.05, 0), FIT_WOOD_DARK)
	_fit_box(holder, Vector3(0.3, 0.62, 0.02), foot + Vector3(0.18, height - 0.4, 0), color)
	_fit_box(holder, Vector3(0.12, 0.12, 0.025), foot + Vector3(0.18, height - 0.38, 0.005), Color("c8a14a"))


# Grand Watchtower: the watchtower raised to fill its plot, with a signal brazier at its foot.
func _fit_grand_watchtower(view: Dictionary, plot: float) -> void:
	var model: Node3D = view["model"]
	var dims: Array = [1.3, 2.42, 1.3]
	_fit_rescale(view, (plot - 0.9) / float(dims[0]))
	var holder: Node3D = _fit_holder(view)
	_fit_box(holder, Vector3(plot - 0.15, 0.06, plot - 0.15), Vector3(0, 0.03, 0), FIT_STONE_DARK)
	var flame: Vector3 = _fit_brazier(holder, Vector3(plot * 0.5 - 0.35, 0.06, plot * 0.5 - 0.35), 0.6)
	_fit_brazier(holder, Vector3(-(plot * 0.5 - 0.35), 0.06, plot * 0.5 - 0.35), 0.6)
	_fit_light(view, flame)


# Monument of the Manner: the oathstone raised on a broad stepped dais with four fire bowls.
func _fit_monument(view: Dictionary, plot: float, tier: int) -> void:
	var model: Node3D = view["model"]
	_fit_rescale(view, (plot - 1.5) / 1.3)
	var holder: Node3D = _fit_holder(view)
	_fit_box(holder, Vector3(plot - 0.15, 0.08, plot - 0.15), Vector3(0, 0.04, 0), FIT_STONE_DARK)
	_fit_box(holder, Vector3(plot - 0.55, 0.06, plot - 0.55), Vector3(0, 0.11, 0), FIT_STONE)
	model.position.y = 0.14
	var corner: float = plot * 0.5 - 0.32
	var flame := Vector3.ZERO
	var bowls: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1)]
	if tier >= 2:
		bowls.append_array([Vector2(1, -1), Vector2(-1, -1)])
	for spot: Vector2 in bowls:
		var at: Vector3 = _fit_brazier(holder, Vector3(spot.x * corner, 0.08, spot.y * corner), 0.5)
		if spot == Vector2(1, 1):
			flame = at
	_fit_light(view, flame)


# Grand Granary: the storehouse with a tall round grain silo beside it and sacks at the door.
func _fit_granary(view: Dictionary, plot: float) -> void:
	var model: Node3D = view["model"]
	_fit_rescale(view, model.scale.x * 0.8)
	var factor: float = model.scale.x
	model.position = Vector3(-0.38, 0, -0.38)
	var holder: Node3D = _fit_holder(view)
	holder.position = Vector3(0.38, 0, 0.38) / factor
	var bounds: AABB = _fit_bounds(model)
	_fit_box(holder, Vector3(plot - 0.15, 0.05, plot - 0.15), Vector3(0, 0.025, 0), FIT_STONE_DARK)
	var silo := Vector3(1.28, 0.05, 1.28)
	_fit_cylinder(holder, 0.5, 0.52, 0.16, silo + Vector3(0, 0.08, 0), FIT_STONE, "", 10)
	_fit_cylinder(holder, 0.46, 0.46, 2.1, silo + Vector3(0, 1.21, 0), Color("b49a72"), "", 10)
	for y: float in [0.55, 1.2, 1.85]:
		_fit_cylinder(holder, 0.475, 0.475, 0.06, silo + Vector3(0, y, 0), FIT_WOOD_DARK, "", 10)
	_fit_cylinder(holder, 0.0, 0.6, 0.6, silo + Vector3(0, 2.56, 0), Color("6e3a26"), "", 10)
	for k in 3:
		_fit_box(holder, Vector3(0.24, 0.26, 0.2), Vector3(-1.45 + k * 0.27, 0.18, 1.5), Color("c9b07a"), "", k * 0.4)
	view["fit"]["bounds"] = bounds


# Manor Gardens: a formal garden. Hedged beds round a gravel cross, a fountain at the heart,
# clipped topiary at the corners.
func _fit_gardens(view: Dictionary, plot: float, tier: int) -> void:
	_fit_hide_native(view)
	var holder: Node3D = _fit_holder(view)
	var half: float = plot * 0.5 - 0.1
	_fit_box(holder, Vector3(plot - 0.2, 0.06, plot - 0.2), Vector3(0, 0.03, 0), FIT_STONE_DARK)
	_fit_box(holder, Vector3(plot - 0.4, 0.04, plot - 0.4), Vector3(0, 0.07, 0), Color("4d6a2f"))
	_fit_box(holder, Vector3(plot - 0.4, 0.05, 0.55), Vector3(0, 0.085, 0), Color("b8ab8e"))
	_fit_box(holder, Vector3(0.55, 0.05, plot - 0.4), Vector3(0, 0.085, 0), Color("b8ab8e"))
	var flowers: Array[Color] = [Color("b03a48"), Color("d8b24a"), Color("8a5cb0"), Color("e0dcd0")]
	var quarter: float = (half + 0.28) * 0.5
	for k in 4:
		var sx: float = -1.0 if k % 2 == 0 else 1.0
		var sz: float = -1.0 if k < 2 else 1.0
		var bed := Vector3(sx * quarter, 0.09, sz * quarter)
		var span: float = half - 0.38
		# Low hedge frame and a flower bed inside it.
		_fit_box(holder, Vector3(span, 0.2, 0.12), bed + Vector3(0, 0.1, sz * span * 0.5), FIT_HEDGE)
		_fit_box(holder, Vector3(0.12, 0.2, span), bed + Vector3(sx * span * 0.5, 0.1, 0), FIT_HEDGE)
		_fit_box(holder, Vector3(span - 0.2, 0.08, span - 0.2), bed + Vector3(0, 0.04, 0), Color("3c2a1e"))
		for f in 6:
			var fx: float = (float(f % 3) - 1.0) * (span - 0.4) * 0.45
			var fz: float = (float(f / 3) - 0.5) * (span - 0.4) * 0.6
			_fit_box(holder, Vector3(0.12, 0.1, 0.12), bed + Vector3(fx, 0.13, fz), flowers[(k + f) % 4])
		# Clipped topiary cone in the outer corner.
		var cone := bed + Vector3(sx * span * 0.38, 0.1, sz * span * 0.38)
		_fit_cylinder(holder, 0.0, 0.2 + 0.03 * tier, 0.55 + 0.12 * tier, cone + Vector3(0, 0.3 + 0.06 * tier, 0), Color("365a2a"), "", 7)
	# The fountain.
	_fit_cylinder(holder, 0.5, 0.52, 0.22, Vector3(0, 0.2, 0), FIT_STONE, "", 12)
	_fit_cylinder(holder, 0.43, 0.43, 0.04, Vector3(0, 0.3, 0), FIT_WATER, "water", 12)
	_fit_cylinder(holder, 0.08, 0.1, 0.5, Vector3(0, 0.5, 0), FIT_STONE, "", 8)
	_fit_cylinder(holder, 0.2, 0.12, 0.08, Vector3(0, 0.76, 0), FIT_STONE, "", 10)
	_fit_cylinder(holder, 0.16, 0.16, 0.03, Vector3(0, 0.8, 0), FIT_WATER, "water", 10)
	var flame: Vector3 = _fit_lantern_post(holder, Vector3(half - 0.12, 0.09, half - 0.12), 1.4, -PI * 0.25)
	_fit_light(view, flame)
	view["fit"]["bounds"] = AABB(Vector3(-1, 0, -1), Vector3(2, 0.5, 2))


# Royal Forge Quarter: the forge pushed back behind a working yard: anvil, quench trough, a coal
# heap and royal banners, the forge light on the yard.
func _fit_forge_quarter(view: Dictionary, plot: float) -> void:
	var model: Node3D = view["model"]
	_fit_rescale(view, model.scale.x * 0.8)
	var factor: float = model.scale.x
	model.position = Vector3(0, 0, -0.4)
	var holder: Node3D = _fit_holder(view)
	holder.position = Vector3(0, 0, 0.4) / factor
	_fit_box(holder, Vector3(plot - 0.15, 0.05, plot - 0.15), Vector3(0, 0.025, 0), FIT_STONE_DARK)
	var yard_z: float = plot * 0.5 - 0.42
	_fit_box(holder, Vector3(0.22, 0.32, 0.18), Vector3(-0.6, 0.21, yard_z), FIT_STONE_DARK)
	_fit_box(holder, Vector3(0.42, 0.12, 0.16), Vector3(-0.6, 0.43, yard_z), FIT_IRON)
	_fit_box(holder, Vector3(0.62, 0.22, 0.28), Vector3(0.25, 0.16, yard_z), FIT_WOOD_DARK)
	_fit_box(holder, Vector3(0.54, 0.02, 0.2), Vector3(0.25, 0.27, yard_z), FIT_WATER, "water")
	_fit_cylinder(holder, 0.05, 0.3, 0.26, Vector3(1.05, 0.18, yard_z), Color("26221f"), "", 7)
	for side: float in [-1.0, 1.0]:
		_fit_banner(holder, Vector3(side * (plot * 0.5 - 0.2), 0.05, plot * 0.5 - 0.2), 2.0, Color("7c1f1f"))
	var lamp: OmniLight3D = view.get("lamp")
	if is_instance_valid(lamp):
		var flame: Vector3 = _fit_brazier(holder, Vector3(1.05, 0.05, yard_z - 0.5), 0.35, Color(1.0, 0.45, 0.14))
		_fit_light(view, flame, Color(1.0, 0.5, 0.2))
		lamp.set_meta("forge", true)


# Grand Market Square: the market under festival strings of lanterns between four corner poles.
func _fit_market_square(view: Dictionary, plot: float, tier: int) -> void:
	var model: Node3D = view["model"]
	_fit_rescale(view, model.scale.x * 0.82)
	var holder: Node3D = _fit_holder(view)
	_fit_box(holder, Vector3(plot - 0.15, 0.05, plot - 0.15), Vector3(0, 0.025, 0), FIT_COBBLE)
	var corner: float = plot * 0.5 - 0.22
	var poles: Array[Vector3] = []
	for spot: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var foot := Vector3(spot.x * corner, 0.05, spot.y * corner)
		_fit_box(holder, Vector3(0.1, 2.3, 0.1), foot + Vector3(0, 1.15, 0), FIT_WOOD_DARK)
		poles.append(foot + Vector3(0, 2.2, 0))
	var colours: Array[Color] = [Color("b03a30"), Color("d8b24a"), Color("3a6a8a"), Color("e6dccb")]
	var light := Vector3.ZERO
	for k in 4:
		var a: Vector3 = poles[k]
		var b: Vector3 = poles[(k + 1) % 4]
		var drops: int = 6
		for r in 8:
			var r0: float = float(r) / 8.0
			var r1: float = float(r + 1) / 8.0
			var p0: Vector3 = a.lerp(b, r0) - Vector3(0, 0.35 * sin(r0 * PI), 0)
			var p1: Vector3 = a.lerp(b, r1) - Vector3(0, 0.35 * sin(r1 * PI), 0)
			var rope := _fit_box(holder, Vector3(0.015, 0.015, p0.distance_to(p1)), (p0 + p1) * 0.5, FIT_WOOD_DARK)
			rope.basis = Basis.looking_at(p1 - p0, Vector3.UP)
		for d in drops:
			var t: float = (float(d) + 0.5) / float(drops)
			var at: Vector3 = a.lerp(b, t) - Vector3(0, 0.35 * sin(t * PI), 0)
			if d % 2 == 0 and (k < 2 or tier >= 2):
				_fit_lantern(holder, at - Vector3(0, 0.16, 0), 0.0, 0.0).scale = Vector3.ONE * 1.15
				# The light hangs on the string lantern nearest the middle of the camera-side run.
				if k == 1 and d == 2:
					light = at - Vector3(0, 0.25, 0)
			else:
				var flag := _fit_box(holder, Vector3(0.16, 0.18, 0.015), at - Vector3(0, 0.1, 0), colours[(k + d) % 4])
				flag.rotation.y = atan2(b.x - a.x, b.z - a.z) + PI * 0.5
	_fit_light(view, light, Color("ffc474"), 5.0)


# Moonberry Grove: clusters of pale moonberries on the canopies that hold a soft light at night.
# Whisper Grove: will-o'-wisp lights caught among its pines. The canopy tops are found by casting
# down onto the trees, so the berries sit on the leaves.
func _fit_berries(view: Dictionary, type_name: String) -> void:
	var model: Node3D = view["model"]
	_fit_leaves(model)
	var holder: Node3D = _fit_holder(view)
	var factor: float = model.scale.x
	var colour := Color(0.72, 0.84, 1.0) if type_name == "grove" else Color(0.6, 1.0, 0.75)
	var material: StandardMaterial3D = _fit_mat(colour, "glow")
	var mesh := SphereMesh.new()
	mesh.radius = 0.08 if type_name == "grove" else 0.06
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(type_name)
	var placed: int = 0
	var lit := Vector3.ZERO
	for cell in 49:
		if placed >= (20 if type_name == "grove" else 10):
			break
		# A jittered 7x7 grid (the same for every grove of a kind, so the probes are cached).
		var x: float = -0.75 + (float(cell % 7) + rng.randf_range(0.2, 0.8)) * (1.5 / 7.0)
		var z: float = -0.75 + (float(cell / 7) + rng.randf_range(0.2, 0.8)) * (1.5 / 7.0)
		if rng.randf() < 0.35:
			continue
		var y: float = _fit_surface_y_any(model, x, z)
		if y < 0.55:
			continue
		var berry := MeshInstance3D.new()
		berry.name = "FitBerry"
		berry.mesh = mesh
		berry.material_override = material
		berry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var drop: float = 0.0 if type_name == "grove" else rng.randf_range(0.05, 0.25)
		berry.position = Vector3(x, y - drop / factor, z) * factor + Vector3(0, 0.02, 0)
		holder.add_child(berry)
		lit += berry.position
		placed += 1
	if placed > 0:
		_fit_light(view, lit / float(placed), colour, 3.0)


# The groves' canopies use the shared atlas's near-black swatch, which reads as holes in the night
# village. They get their own copy of the atlas with the darkest swatches turned to deep leaf green.
var _fit_leaf_texture: ImageTexture = null


func _fit_leaves(model: Node3D) -> void:
	for part in model.get_children():
		if not part is MeshInstance3D or not str(part.name).begins_with("MMR"):
			continue
		var mesh_node := part as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var active := mesh_node.get_active_material(surface) as BaseMaterial3D
			if active == null or active.albedo_texture == null:
				continue
			if _fit_leaf_texture == null:
				var image: Image = active.albedo_texture.get_image()
				if image == null:
					continue
				image = image.duplicate()
				if image.is_compressed():
					image.decompress()
				image.convert(Image.FORMAT_RGBA8)
				for py in image.get_height():
					for px in image.get_width():
						var c: Color = image.get_pixel(px, py)
						var lum: float = c.r * 0.3 + c.g * 0.55 + c.b * 0.15
						if lum < 0.16:
							image.set_pixel(px, py, Color(0.17, 0.3, 0.2).lerp(c, lum / 0.16 * 0.4))
				_fit_leaf_texture = ImageTexture.create_from_image(image)
			var leaves: BaseMaterial3D = active.duplicate()
			leaves.albedo_texture = _fit_leaf_texture
			mesh_node.set_surface_override_material(surface, leaves)


# Wild Market: the open front of the plaza filled with trade: a laden hand cart, crates of produce,
# barrels and sacks, so the stalls stand in a working market rather than on an empty slab.
func _fit_market_wares(view: Dictionary, plot: float, tier: int) -> void:
	var holder: Node3D = _fit_holder(view)
	var front: float = plot * 0.5 - 0.95
	var produce: Array[Color] = [Color("b8402e"), Color("d9a43a"), Color("7a9a3a"), Color("8a4a8a")]
	# Cobbles laid over the bare slab, a paler course of setts crossing it, so the plaza reads lit.
	var model: Node3D = view["model"]
	var floor_y: float = _fit_surface_y(model, 0.0, front / model.scale.x) * model.scale.x
	var inner: float = plot - 0.9
	_fit_box(holder, Vector3(inner, 0.03, inner), Vector3(0, floor_y + 0.015, 0), FIT_COBBLE)
	for k in 5:
		var along: float = -inner * 0.5 + inner * (float(k) + 0.5) / 5.0
		_fit_box(holder, Vector3(0.34, 0.035, 0.34), Vector3(along, floor_y + 0.02, front + 0.45), FIT_STONE, "", 0.2 * k)
	# The hand cart, its shafts resting on the ground.
	var cart := Vector3(-0.9, floor_y + 0.03, front)
	_fit_box(holder, Vector3(0.9, 0.08, 0.55), cart + Vector3(0, 0.42, 0), FIT_WOOD)
	for side: float in [-1.0, 1.0]:
		_fit_box(holder, Vector3(0.9, 0.16, 0.04), cart + Vector3(0, 0.53, side * 0.26), FIT_WOOD_DARK)
		var wheel := _fit_cylinder(holder, 0.24, 0.24, 0.05, cart + Vector3(0.05, 0.24, side * 0.31), FIT_WOOD_DARK, "", 10)
		wheel.rotation.x = PI * 0.5
		var shaft := _fit_box(holder, Vector3(0.7, 0.04, 0.04), cart + Vector3(0.72, 0.2, side * 0.2), FIT_WOOD_DARK)
		shaft.rotation.z = 0.5
	for k in 6:
		_fit_box(holder, Vector3(0.16, 0.12, 0.16), cart + Vector3(-0.3 + (k % 3) * 0.28, 0.52, -0.12 + (k / 3) * 0.24), produce[k % 4])
	# Crates of produce and a stack of barrels by the right-hand stall.
	for k in 3:
		var crate := Vector3(0.35 + k * 0.42, floor_y + 0.03, front + 0.1)
		_fit_box(holder, Vector3(0.36, 0.24, 0.3), crate + Vector3(0, 0.12, 0), FIT_WOOD, "", k * 0.12)
		_fit_box(holder, Vector3(0.3, 0.06, 0.24), crate + Vector3(0, 0.26, 0), produce[(k + 1) % 4], "", k * 0.12)
	for k in 2:
		_fit_cylinder(holder, 0.15, 0.15, 0.36, Vector3(1.0 + k * 0.32, floor_y + 0.21, front - 0.45), FIT_WOOD, "", 8)
	_fit_cylinder(holder, 0.15, 0.15, 0.36, Vector3(1.16, floor_y + 0.57, front - 0.45), FIT_WOOD, "", 8)
	for k in 3:
		_fit_box(holder, Vector3(0.22, 0.26, 0.18), Vector3(-0.1 + k * 0.2, floor_y + 0.16, front - 0.5), Color("c9b07a"), "", k * 0.5)


# Steam Bathhouse: the bath hall set back behind a steaming wooden tub, steam lifting off its roof.
func _fit_bathhouse(view: Dictionary, plot: float) -> void:
	var model: Node3D = view["model"]
	_fit_rescale(view, model.scale.x * 0.84)
	var factor: float = model.scale.x
	model.position = Vector3(-0.25, 0, -0.3)
	var holder: Node3D = _fit_holder(view)
	holder.position = Vector3(0.25, 0, 0.3) / factor
	var bounds: AABB = _fit_bounds(model)
	_fit_box(holder, Vector3(plot - 0.15, 0.05, plot - 0.15), Vector3(0, 0.025, 0), FIT_STONE_DARK)
	var tub := Vector3(1.3, 0.05, 1.3)
	_fit_cylinder(holder, 0.42, 0.38, 0.36, tub + Vector3(0, 0.18, 0), FIT_WOOD, "", 10)
	for y: float in [0.08, 0.3]:
		_fit_cylinder(holder, 0.43, 0.41, 0.035, tub + Vector3(0, y, 0), FIT_IRON, "", 10)
	_fit_cylinder(holder, 0.37, 0.37, 0.02, tub + Vector3(0, 0.34, 0), Color("4c7c86"), "water", 10)
	_fit_steam(holder, tub + Vector3(0, 0.4, 0), 0.32)
	_fit_steam(holder, Vector3(-0.25 + bounds.get_center().x * factor, bounds.end.y * factor * 0.82, -0.3), 0.5)
	view["fit"]["bounds"] = bounds


func _fit_steam(holder: Node3D, at: Vector3, spread: float) -> void:
	var steam := CPUParticles3D.new()
	steam.name = "FitSteam"
	steam.amount = 8
	steam.lifetime = 2.6
	steam.position = at
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	steam.emission_sphere_radius = spread
	steam.direction = Vector3.UP
	steam.spread = 12.0
	steam.gravity = Vector3(0.05, 0.12, 0.0)
	steam.initial_velocity_min = 0.18
	steam.initial_velocity_max = 0.32
	steam.scale_amount_min = 0.7
	steam.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	steam.scale_amount_curve = curve
	var fade := Gradient.new()
	fade.set_color(0, Color(0.92, 0.94, 0.96, 0.32))
	fade.set_color(1, Color(0.92, 0.94, 0.96, 0.0))
	steam.color_ramp = fade
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.32, 0.32)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = UI.soft_disc_texture()
	mesh.material = material
	steam.mesh = mesh
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(steam)


# Pond, weir and deephole: a real water surface over the basin's flat brown disc, with the ripple
# rings floating on it. Disc radius and height are in model units, read from the meshes.
const FIT_WATER_DISC := {"pond": [0.8, 0.37], "blackwater-weir": [0.42, 0.37], "deephole": [0.33, 0.27]}


func _fit_water(view: Dictionary, type_name: String, plot: float) -> void:
	var model: Node3D = view["model"]
	var factor: float = model.scale.x
	var disc: Array = FIT_WATER_DISC[type_name]
	var radius: float = float(disc[0]) * factor
	var level: float = float(disc[1]) * factor
	var water: MeshInstance3D = _fit_cylinder(_fit_holder(view), radius, radius, 0.02, Vector3(0, level, 0), FIT_WATER, "water", 16)
	water.name = "FitWater"
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rings: Node3D = view.get("rings")
	if is_instance_valid(rings):
		# The rings were sized for the whole plot (radius 0.35 x plot); keep them on the water.
		rings.position.y = level + 0.015 - 0.07
		rings.scale = Vector3.ONE * clampf(radius * 0.8 / (0.35 * plot), 0.2, 1.0)


# Frostwood Grove: rime on the boughs. The shared palette is re-made once in frost colours (each
# texel's brightness carried into a pale blue-white), so canopy, trunks and ground all take it.
var _fit_frost_texture: ImageTexture = null


func _fit_frost(view: Dictionary) -> void:
	var model: Node3D = view["model"]
	for part in model.get_children():
		if not part is MeshInstance3D or not str(part.name).begins_with("MMR"):
			continue
		var mesh_node := part as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var base := mesh_node.get_active_material(surface) as BaseMaterial3D
			if base == null or base.albedo_texture == null:
				continue
			if _fit_frost_texture == null:
				var image: Image = base.albedo_texture.get_image()
				if image == null:
					continue
				image = image.duplicate()
				if image.is_compressed():
					image.decompress()
				image.convert(Image.FORMAT_RGBA8)
				for py in image.get_height():
					for px in image.get_width():
						var c: Color = image.get_pixel(px, py)
						var lum: float = c.r * 0.3 + c.g * 0.55 + c.b * 0.15
						var ice := Color(0.42, 0.52, 0.63).lerp(Color(0.84, 0.9, 0.96), clampf(lum * 1.5, 0.0, 1.0))
						image.set_pixel(px, py, c.lerp(ice, 0.62))
				_fit_frost_texture = ImageTexture.create_from_image(image)
			var frost: BaseMaterial3D = base.duplicate()
			frost.albedo_texture = _fit_frost_texture
			frost.albedo_color = Color(0.72, 0.74, 0.78)
			mesh_node.set_surface_override_material(surface, frost)


# Emberglass Mine: ember crystals glowing at the mine mouth, the light coming off them.
func _fit_embers(view: Dictionary) -> void:
	var holder: Node3D = _fit_holder(view)
	var model: Node3D = view["model"]
	var bounds: AABB = _fit_bounds(model)
	var front: float = bounds.end.z * model.scale.x
	var spots: Array[Vector3] = [Vector3(-0.42, 0.06, front + 0.05), Vector3(-0.22, 0.06, front + 0.12), Vector3(0.48, 0.06, front + 0.04)]
	for k in spots.size():
		var crystal := _fit_cylinder(holder, 0.0, 0.07 + 0.02 * (k % 2), 0.3 + 0.08 * (k % 2), spots[k] + Vector3(0, 0.15, 0), Color(1.0, 0.36, 0.14), "glow", 5)
		crystal.rotation.z = (float(k) - 1.0) * 0.3
	_fit_light(view, spots[1] + Vector3(0, 0.35, 0.1), Color(1.0, 0.42, 0.2), 2.6)
	view["fit"]["lit"] = true


# Moon Dial: a moonstone on the dial face that holds a pale light at night.
func _fit_moonstone(view: Dictionary) -> void:
	var holder: Node3D = _fit_holder(view)
	var model: Node3D = view["model"]
	var top: float = _fit_bounds(model).end.y * model.scale.x
	var stone := MeshInstance3D.new()
	stone.name = "FitMoonstone"
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 8
	sphere.rings = 4
	stone.mesh = sphere
	stone.material_override = _fit_mat(Color(0.72, 0.84, 1.0), "glow")
	stone.position = Vector3(0, top + 0.13, 0)
	holder.add_child(stone)
	# A bronze cradle seats the stone on the dial so it does not float.
	_fit_cylinder(holder, 0.09, 0.06, 0.08, Vector3(0, top + 0.04, 0), Color("8a6a3a"), "", 8)


# Bell Tower: a lantern hung in the belfry, so the bell shows at night.
func _fit_belfry(view: Dictionary) -> void:
	var model: Node3D = view["model"]
	var bounds: AABB = _fit_bounds(model)
	var factor: float = model.scale.x
	var at := Vector3(bounds.get_center().x * factor, bounds.end.y * factor * 0.56, bounds.get_center().z * factor + 0.22)
	_fit_lantern(_fit_holder(view), at)
	_fit_light(view, at, Color("ffc474"), 3.8)


# Dawn Gate: fire bowls burning either side of the arch.
func _fit_dawn_gate(view: Dictionary, plot: float) -> void:
	var holder: Node3D = _fit_holder(view)
	var front: float = plot * 0.5 - 0.35
	var flame := Vector3.ZERO
	for side: float in [-1.0, 1.0]:
		flame = _fit_brazier(holder, Vector3(side * 1.05, 0.08, front), 0.6, Color(1.0, 0.68, 0.3))
	_fit_light(view, flame - Vector3(1.05, 0, 0), Color(1.0, 0.72, 0.42), 4.2)


# Emberforge: the forge's red light moves onto its own glowing hearth (the model's emissive part),
# instead of a lamp and glow disc hanging in the air in front of it.
func _fit_forge_fire(view: Dictionary) -> void:
	var model: Node3D = view["model"]
	var hearth := AABB()
	var found: bool = false
	for part in model.get_children():
		if not part is MeshInstance3D or (part as MeshInstance3D).mesh == null:
			continue
		var mesh: Mesh = (part as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null or not material.emission_enabled:
				continue
			var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var at: Vector3 = (part as MeshInstance3D).transform * v
				hearth = AABB(at, Vector3.ZERO) if not found else hearth.expand(at)
				found = true
	if not found:
		return
	var marker := Node3D.new()
	marker.name = "FitForgeFire"
	model.add_child(marker)
	marker.position = hearth.get_center()
	var factor: float = model.scale.x
	var at: Vector3 = model.position + hearth.get_center() * factor + Vector3(0, 0, 0.18)
	_fit_light(view, at, Color(1.0, 0.5, 0.2), 3.6)


# Mill sails, mill water wheel, saw blade and drive wheel were exported with their pivot at the
# building centre (lifted to rest on the ground), so the sails turned buried in the tower's foot and
# the blade inside the shed floor. Each turning part is mounted where it belongs; the details layer
# still spins it about its own axis.
func _fit_spinners(view: Dictionary) -> void:
	var model: Node3D = view["model"]
	for spin: Dictionary in view.get("spinners", []):
		var pivot: Node3D = spin["pivot"]
		if not is_instance_valid(pivot) or pivot.get_parent() != model:
			continue
		var name_key: String = str(pivot.name).to_lower()
		var mount := Node3D.new()
		mount.name = "FitMount"
		model.add_child(mount)
		if "wind rotor" in name_key:
			# The sails' hub high on the tower's door face, clear of the roof posts.
			# The hub stands just clear of the roof's open front, so the sails sweep in front of its
			# posts and eaves, on an axle run out from the tower's door face.
			var face: float = _fit_wall_z(model, 0.0, 1.3)
			var hub: float = _fit_wall_z(model, 0.3, 1.9) + 0.07
			mount.position = Vector3(0.0, 1.3, hub)
			var axle: MeshInstance3D = _fit_box(model, Vector3(0.07, 0.07, hub - face), Vector3(0.0, 1.3, (hub + face) * 0.5), FIT_WOOD_DARK)
			axle.name = "FitAxle"
			axle.material_override = _fit_mat(FIT_WOOD_DARK)
		elif "water wheel" in name_key:
			# In the race along the right-hand (+X) wall, turned to face along it.
			mount.position = Vector3(_fit_wall_x(model, 0.45, 0.1) + 0.08, 0.37, 0.45)
			mount.rotation.y = PI * 0.5
		elif "saw blade" in name_key:
			# Standing in the bench under the header frame.
			mount.position = Vector3(0.0, 0.55, 0.05)
		elif "drive wheel" in name_key:
			mount.position = Vector3(_fit_wall_x(model, -0.45, 0.4) + 0.08, 0.4, -0.45)
			mount.rotation.y = PI * 0.5
		pivot.reparent(mount, false)
		pivot.position = Vector3.ZERO


# Stone Quarry: the cut blocks stacked neatly on the front of the plinth, inside the tile.
func _fit_quarry_stone(view: Dictionary) -> void:
	var root_node: Node3D = view["root"]
	var blocks: Array[MeshInstance3D] = []
	for child in root_node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			if ((child as MeshInstance3D).mesh as BoxMesh).size.is_equal_approx(Vector3(0.36, 0.25, 0.3)):
				blocks.append(child)
	var places: Array[Vector3] = [Vector3(-0.7, 0.1, 0.84), Vector3(-0.44, 0.1, 0.84), Vector3(-0.18, 0.1, 0.84),
		Vector3(-0.57, 0.29, 0.84), Vector3(-0.31, 0.29, 0.84), Vector3(-0.44, 0.48, 0.84)]
	for k in mini(blocks.size(), places.size()):
		blocks[k].scale = Vector3.ONE * 0.72
		blocks[k].position = places[k]
		blocks[k].rotation.y = (float(k) - 2.5) * 0.06
