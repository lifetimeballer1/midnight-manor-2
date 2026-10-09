extends Node3D

# GLB-space units (scaled with the model). Gate arch authored 0.476 high; wall
# arches sit on a 0.05 slab that is hidden for walls, so they are dropped to 0.
const GATE_FLOAT_FIX: float = 0.476
const WALL_BASE_FIX: float = 0.05
# Open gate lift rises just above its own 0.55 height, clear of the opening.
const GATE_RAISE: float = 0.6
const SPIN_SPEEDS := {"wind rotor": 0.5, "water wheel": 0.9, "saw blade": 12.0, "drive wheel": 1.6}

var warnings: Array[Label3D] = []
var smoke_count: int = 0
var warning_clock: float = 0.0


func box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


func meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): meshes(child, result)


## Re-parents a mesh under a pivot at its own AABB centre so it can spin in place.
func _pivot(part: MeshInstance3D) -> Node3D:
	var center: Vector3 = part.mesh.get_aabb().get_center()
	var pivot := Node3D.new()
	pivot.name = str(part.name) + "Pivot"
	part.get_parent().add_child(pivot)
	pivot.transform = part.transform * Transform3D(Basis(), center)
	part.reparent(pivot, false)
	part.transform = Transform3D(Basis(), -center)
	return pivot


func attach(game, b: Dictionary, view: Dictionary) -> void:
	var root_node: Node3D = view["root"]
	var native: Array[MeshInstance3D] = []
	meshes(view["model"], native)
	if not view["model"].has_meta("soot_tinted"):
		view["model"].set_meta("soot_tinted", true)
		for part in native:
			if part.mesh == null: continue
			for surface in part.mesh.get_surface_count():
				var base := part.get_active_material(surface) as BaseMaterial3D
				if base and not base.emission_enabled:
					var soot: BaseMaterial3D = base.duplicate()
					soot.albedo_color = Color("5c5249")
					part.set_surface_override_material(surface, soot)
	var type_name: String = b["type"]
	if type_name in ["wall", "stonewall", "gate"]:
		for part in native:
			if "ground" in str(part.name).to_lower(): part.hide()
		if not view["model"].has_meta("base_fixed"):
			view["model"].set_meta("base_fixed", true)
			var sink: float = GATE_FLOAT_FIX if type_name == "gate" else WALL_BASE_FIX
			for part in native:
				if "lift" not in str(part.name).to_lower(): part.position.y -= sink
		var neighbours: Array[Vector2i] = []
		for other: Dictionary in game.sim.buildings:
			if other["type"] not in ["wall", "stonewall", "gate"] or other["hp"] <= 0: continue
			var direction := Vector2i(int(other["x"]) - int(b["x"]), int(other["y"]) - int(b["y"]))
			if absi(direction.x) + absi(direction.y) == 1: neighbours.append(direction)
		var vertical: bool = neighbours.has(Vector2i(0, 1)) or neighbours.has(Vector2i(0, -1))
		if vertical and not (neighbours.has(Vector2i(1, 0)) or neighbours.has(Vector2i(-1, 0))):
			view["model"].rotation.y = PI / 2
		var joins := Node3D.new()
		joins.name = "WallConnections"
		root_node.add_child(joins)
		for direction in neighbours:
			var at := Vector3(direction.x * 0.5, 0, direction.y * 0.5)
			var color := Color("3b342e") if type_name != "stonewall" else Color("4a4d47")
			for height in [0.45, 1.15]:
				var size := Vector3(1.03, 0.2, 0.18) if direction.x != 0 else Vector3(0.18, 0.2, 1.03)
				box(joins, size, at + Vector3(0, height, 0), color)
		view["joins"] = joins
	for part in native:
		if "lift gate" in str(part.name).to_lower():
			view["gate_mesh"] = part
			view["gate_base"] = part.position.y
	if type_name == "forge":
		var glows: Array = []
		for part in native:
			if part.mesh == null: continue
			for surface in part.mesh.get_surface_count():
				var base := part.get_active_material(surface) as BaseMaterial3D
				if base and base.emission_enabled:
					var lit: BaseMaterial3D = base.duplicate()
					part.set_surface_override_material(surface, lit)
					glows.append({"mat": lit, "base": base.emission_energy_multiplier})
		view["forge_glows"] = glows
	var spin_speeds: Dictionary = {}
	if type_name == "mill": spin_speeds = {"wind rotor": SPIN_SPEEDS["wind rotor"], "water wheel": SPIN_SPEEDS["water wheel"]}
	elif type_name == "sawmill": spin_speeds = {"saw blade": SPIN_SPEEDS["saw blade"], "drive wheel": SPIN_SPEEDS["drive wheel"]}
	if not spin_speeds.is_empty():
		var spinners: Array = []
		for part in native:
			if part.mesh == null: continue
			var part_key: String = str(part.name).to_lower()
			for key in spin_speeds:
				if key in part_key:
					spinners.append({"pivot": _pivot(part), "speed": spin_speeds[key]})
		view["spinners"] = spinners
	if type_name == "stone_quarry":
		for part in native:
			for surface in part.mesh.get_surface_count():
				var material: Material = part.get_active_material(surface)
				if material is BaseMaterial3D:
					var tinted: BaseMaterial3D = material.duplicate()
					tinted.albedo_color = Color("b0b4ad")
					part.set_surface_override_material(surface, tinted)
		for index in 6:
			var block: MeshInstance3D = box(root_node, Vector3(0.36, 0.25, 0.3), Vector3(-1.1 + (index % 3) * 0.4, 0.125, 0.8 + floori(index / 3.0) * 0.35), Color("909588"))
			block.rotation.y = index * 0.23
	if type_name in ["pond", "deephole", "blackwater-weir"]:
		var rings := Node3D.new()
		rings.name = "Ripples"
		root_node.add_child(rings)
		var radius: float = 0.7 * float(b["size"])
		for k in 2:
			var ring := MeshInstance3D.new()
			var band := TorusMesh.new()
			band.inner_radius = radius * 0.9
			band.outer_radius = radius
			band.rings = 24
			band.ring_segments = 8
			ring.mesh = band
			var ripple := StandardMaterial3D.new()
			ripple.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ripple.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ripple.albedo_color = Color(0.75, 0.86, 0.95, 0.55)
			ripple.disable_receive_shadows = true
			ring.material_override = ripple
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.position = Vector3(0, 0.07, 0)
			rings.add_child(ring)
			var swell := rings.create_tween().set_loops()
			if k == 1:
				swell.tween_interval(1.3)
			swell.set_parallel(true)
			swell.tween_property(ring, "scale", Vector3.ONE * 1.5, 2.6).from(Vector3.ONE * 0.6)
			swell.tween_property(ripple, "albedo_color:a", 0.0, 2.6).from(0.55)
		view["rings"] = rings
	var scaffold := Node3D.new()
	scaffold.name = "Scaffolding"
	root_node.add_child(scaffold)
	var reach: float = float(b["size"]) - 0.12
	for x in [-reach, reach]:
		for z in [-reach, reach]: box(scaffold, Vector3(0.1, 2.4, 0.1), Vector3(x, 1.2, z), Color("4e4339"))
	for z in [-reach, reach]:
		box(scaffold, Vector3(reach * 2 + 0.1, 0.12, 0.12), Vector3(0, 0.8, z), Color("6b5b3f"))
		box(scaffold, Vector3(reach * 2 + 0.1, 0.12, 0.12), Vector3(0, 1.8, z), Color("6b5b3f"))
	var bar: MeshInstance3D = box(scaffold, Vector3(1.8, 0.12, 0.16), Vector3(0, 2.55, 0), Color("dbb864"))
	view["scaffold"] = scaffold
	view["progress"] = bar
	view["previous_hp"] = float(b["hp"])
	view["danger_until"] = 0.0
	view["constructing"] = float(b.get("remaining", 0.0)) > 0.0
	if type_name in ["hall", "cottage", "barracks", "bathhouse", "butchery", "forge", "bakery"] and smoke_count < 14:
		var smoke := CPUParticles3D.new()
		smoke.name = "ChimneySmoke"
		smoke.amount = 9
		smoke.lifetime = 4.2
		smoke.position = Vector3(0.5, view["label"].position.y - 0.4, -0.35)
		smoke.direction = Vector3.UP
		smoke.spread = 14
		smoke.gravity = Vector3(0.035, 0.08, 0)
		smoke.initial_velocity_min = 0.2
		smoke.initial_velocity_max = 0.35
		var mesh := SphereMesh.new()
		mesh.radius = 0.09
		mesh.height = 0.18
		mesh.radial_segments = 6
		mesh.rings = 3
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.2, 0.19, 0.18, 0.3)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = material
		smoke.mesh = mesh
		root_node.add_child(smoke)
		view["smoke"] = smoke
		smoke_count += 1


func setup_warnings(game) -> void:
	var points: Array[Vector2] = [Vector2(0.8, 8), Vector2(19.2, 8), Vector2(10, 0.8), Vector2(10, 15.2)]
	for point in points:
		var label := Label3D.new()
		label.font_size = 38
		label.pixel_size = 0.016
		label.modulate = Color("ffaf77")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = game.world_position(point, 2.2)
		add_child(label)
		warnings.append(label)


func update(game, dt: float) -> void:
	var wave: int = game.sim.wave if game.sim.raid_active else game.sim.wave + 1
	var count: int = mini(8, wave + 1)
	# Label3D text writes regenerate the text texture in the Compatibility
	# renderer, so the countdown refreshes at 4 Hz and only on real changes.
	warning_clock += dt
	var refresh: bool = warning_clock >= 0.25
	if refresh:
		warning_clock = 0.0
	for side in warnings.size():
		warnings[side].visible = (game.sim.raid_warning or game.sim.raid_active) and (count >= 4 or side == (wave - 1) % 4)
		if refresh:
			var text: String = ["WEST", "EAST", "NORTH", "SOUTH"][side] + (" / RAID" if game.sim.raid_active else " / %.0fs" % maxf(0, game.sim.next_raid_at - game.sim.elapsed))
			if warnings[side].text != text:
				warnings[side].text = text
	for b: Dictionary in game.sim.buildings:
		var view: Dictionary = game.building_views.get(int(b["id"]), {})
		if view.is_empty(): continue
		view["scaffold"].visible = b["remaining"] > 0 and b["hp"] > 0
		if view.has("rings"):
			(view["rings"] as Node3D).visible = b["hp"] > 0 and b["remaining"] <= 0
		if view.has("windows"):
			var lit: bool = b["hp"] > 0 and b["remaining"] <= 0 and game.night
			for w in (view["windows"] as Array):
				(w as MeshInstance3D).visible = lit
		if bool(view.get("constructing", false)) and b["remaining"] <= 0 and b["hp"] > 0:
			view["constructing"] = false
			game._poof(Vector2i(int(b["x"]), int(b["y"])), Color(0.95, 0.82, 0.45))
			game._play_sfx("upgrade")
		var duration: float = float(game.sim.building_specs[b["type"]]["buildSeconds"])
		view["progress"].scale.x = maxf(0.03, 1 - float(b["remaining"]) / maxf(0.1, duration))
		if float(b["hp"]) < float(view["previous_hp"]): view["danger_until"] = game.sim.elapsed + 2
		view["previous_hp"] = float(b["hp"])
		if float(view["danger_until"]) > game.sim.elapsed and b["hp"] > 0:
			if str(view.get("label_text", "")) != "UNDER ATTACK":
				view["label_text"] = "UNDER ATTACK"
				view["label"].text = "UNDER ATTACK"
				view["label"].modulate = Color("ff8270")
		elif str(view.get("label_text", "")) == "UNDER ATTACK":
			view["label_text"] = "###"
			view["label"].modulate = Color("d4b275")
		if view.has("gate_mesh"):
			var part: MeshInstance3D = view["gate_mesh"]
			var wanted: float = float(view["gate_base"]) + (GATE_RAISE if b.get("gate_open", true) else 0.0)
			part.position.y = move_toward(part.position.y, wanted, dt * 1.6) if not game.sim.paused else part.position.y
		if view.has("spinners") and b["hp"] > 0 and b["remaining"] <= 0 and not game.sim.paused:
			for spin: Dictionary in (view["spinners"] as Array):
				(spin["pivot"] as Node3D).rotate_z(float(spin["speed"]) * dt)
		if view.has("forge_glows") and b["hp"] > 0 and not game.sim.paused:
			var glow_t: float = Time.get_ticks_msec() / 1000.0
			var glow_phase: float = float(b["id"]) * 1.7
			for glow: Dictionary in (view["forge_glows"] as Array):
				(glow["mat"] as BaseMaterial3D).emission_energy_multiplier = float(glow["base"]) * (0.9 + 0.08 * sin(glow_t * 7.3 + glow_phase) + 0.04 * sin(glow_t * 17.9 + glow_phase * 2.3))
		if view.has("smoke"):
			var smoke: CPUParticles3D = view["smoke"]
			smoke.emitting = b["hp"] > 0 and b["remaining"] <= 0 and not game.sim.paused
