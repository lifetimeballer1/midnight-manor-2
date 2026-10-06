extends Node3D

var warnings: Array[Label3D] = []
var smoke_count: int = 0


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


func attach(game, b: Dictionary, view: Dictionary) -> void:
	var root_node: Node3D = view["root"]
	var native: Array[MeshInstance3D] = []
	meshes(view["model"], native)
	var type_name: String = b["type"]
	if type_name in ["wall", "stonewall", "gate"]:
		for part in native:
			if "ground" in str(part.name).to_lower(): part.hide()
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
			var color := Color("625345") if type_name != "stonewall" else Color("77786e")
			for height in [0.45, 1.15]:
				var size := Vector3(1.03, 0.2, 0.18) if direction.x != 0 else Vector3(0.18, 0.2, 1.03)
				box(joins, size, at + Vector3(0, height, 0), color)
		view["joins"] = joins
		if type_name == "gate":
			for part in native:
				if "lift" in str(part.name).to_lower():
					view["gate_mesh"] = part
					view["gate_base"] = part.position.y
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
	var scaffold := Node3D.new()
	scaffold.name = "Scaffolding"
	root_node.add_child(scaffold)
	var reach: float = float(b["size"]) - 0.12
	for x in [-reach, reach]:
		for z in [-reach, reach]: box(scaffold, Vector3(0.1, 2.4, 0.1), Vector3(x, 1.2, z), Color("82694b"))
	for z in [-reach, reach]:
		box(scaffold, Vector3(reach * 2 + 0.1, 0.12, 0.12), Vector3(0, 0.8, z), Color("ad9366"))
		box(scaffold, Vector3(reach * 2 + 0.1, 0.12, 0.12), Vector3(0, 1.8, z), Color("ad9366"))
	var bar: MeshInstance3D = box(scaffold, Vector3(1.8, 0.12, 0.16), Vector3(0, 2.55, 0), Color("dbb864"))
	view["scaffold"] = scaffold
	view["progress"] = bar
	view["previous_hp"] = float(b["hp"])
	view["danger_until"] = 0.0
	view["danger_label_active"] = false
	var damage := Node3D.new()
	damage.name = "BattleDamage"
	root_node.add_child(damage)
	var scar_a: MeshInstance3D = box(damage, Vector3(0.08, 0.95, 0.08), Vector3(-0.34, 0.62, 0.38), Color("302820"))
	scar_a.rotation.z = 0.62
	var scar_b: MeshInstance3D = box(damage, Vector3(0.07, 0.72, 0.07), Vector3(0.28, 0.52, 0.42), Color("433128"))
	scar_b.rotation.z = -0.48
	var scar_c: MeshInstance3D = box(damage, Vector3(0.10, 0.55, 0.10), Vector3(0.02, 0.36, -0.46), Color("241f1a"))
	scar_c.rotation.x = 0.35
	damage.visible = false
	view["damage"] = damage
	if type_name in ["hall", "cottage", "barracks"] and smoke_count < 8:
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
		material.albedo_color = Color(0.65, 0.68, 0.71, 0.23)
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
	for side in warnings.size():
		warnings[side].visible = (game.sim.raid_warning or game.sim.raid_active) and (count >= 4 or side == (wave - 1) % 4)
		warnings[side].text = ["WEST", "EAST", "NORTH", "SOUTH"][side] + (" / RAID" if game.sim.raid_active else " / %.0fs" % maxf(0, game.sim.next_raid_at - game.sim.elapsed))
	for b: Dictionary in game.sim.buildings:
		var view: Dictionary = game.building_views.get(int(b["id"]), {})
		if view.is_empty(): continue
		view["scaffold"].visible = b["remaining"] > 0 and b["hp"] > 0
		var duration: float = float(game.sim.building_specs[b["type"]]["buildSeconds"])
		view["progress"].scale.x = maxf(0.03, 1 - float(b["remaining"]) / maxf(0.1, duration))
		if float(b["hp"]) < float(view["previous_hp"]): view["danger_until"] = game.sim.elapsed + 2
		view["previous_hp"] = float(b["hp"])
		var hp_ratio: float = float(b["hp"]) / maxf(1.0, float(b["max_hp"]))
		if view.has("damage"):
			var damage: Node3D = view["damage"]
			damage.visible = b["hp"] > 0 and hp_ratio < 0.75
			if damage.visible:
				var scars: Array[Node] = damage.get_children()
				if scars.size() > 0: scars[0].visible = hp_ratio < 0.75
				if scars.size() > 1: scars[1].visible = hp_ratio < 0.50
				if scars.size() > 2: scars[2].visible = hp_ratio < 0.30
		if float(view["danger_until"]) > game.sim.elapsed and b["hp"] > 0:
			view["label"].text = "UNDER ATTACK"
			view["label_text"] = "UNDER ATTACK"
			view["danger_label_active"] = true
			view["label"].modulate = Color("ff8270")
		elif bool(view.get("danger_label_active", false)):
			# village_game may already have restored the normal text this frame;
			# track the alert state separately so the gold colour is always restored.
			view["danger_label_active"] = false
			view["label"].modulate = Color("d4b275")
		if view.has("gate_mesh"):
			var part: MeshInstance3D = view["gate_mesh"]
			var wanted: float = float(view["gate_base"]) + (0.65 if b.get("gate_open", true) else 0.0)
			part.position.y = move_toward(part.position.y, wanted, dt * 1.6) if not game.sim.paused else part.position.y
		if view.has("smoke"):
			var smoke: CPUParticles3D = view["smoke"]
			var damaged_smoke: bool = b["hp"] > 0 and hp_ratio < 0.45
			smoke.emitting = b["hp"] > 0 and b["remaining"] <= 0 and not game.sim.paused and (damaged_smoke or b["type"] in ["hall", "cottage", "barracks"])
