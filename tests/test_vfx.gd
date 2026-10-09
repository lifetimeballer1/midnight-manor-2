extends SceneTree

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func _run() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)

	check(game.get("_vfx_on") != null, "the effects layer is in the chain")
	check(game._vfx_on, "effects layer is on")

	# Poof: a soft cloud node that counts toward the shared cap, with dust, chips and glints.
	var before: int = game.effect_nodes.size()
	game._poof(Vector2i(6, 6), Color(0.95, 0.8, 0.4))
	check(game.effect_nodes.size() == before + 1, "a poof is one transient effect node")
	var cloud: Node = game.effect_nodes.back()
	var kinds: Array[String] = []
	for child in cloud.get_children():
		kinds.append(str((child as CPUParticles3D).mesh.get_class()))
	check(cloud.get_child_count() == 3 and kinds.has("QuadMesh") and kinds.has("BoxMesh"), "poof has dust, chips and glints")
	var upgrade_glint: Color = (cloud.get_child(2) as CPUParticles3D).color
	game._poof(Vector2i(7, 6), Color(0.5, 0.85, 0.5))
	var repair_glint: Color = ((game.effect_nodes.back() as Node).get_child(2) as CPUParticles3D).color
	check(upgrade_glint.r > upgrade_glint.g * 0.9 and repair_glint.g > repair_glint.r, "upgrade glints gold, repair glints green")
	game._poof(Vector2i(-1, 0), Color.WHITE)
	check(game.effect_nodes.size() == before + 2, "an off-map poof does nothing")
	for i in 40:
		game._poof(Vector2i(5, 12), Color.WHITE)
	check(game.effect_nodes.size() + game.burst_pool.active_count() <= game.EFFECT_LIMIT, "poofs respect the shared effect cap")

	# Footfall by ground.
	var cells: Dictionary = game.sim.living.cells
	cells["14,3"] = {"wear": 1.0, "last": game.sim.elapsed, "stone": true}
	cells["15,3"] = {"wear": 0.9, "last": game.sim.elapsed, "stone": false}
	var stone_at: Vector3 = game.world_position(Vector2(14.5, 3.5))
	var dirt_at: Vector3 = game.world_position(Vector2(15.5, 3.5))
	var grass_at: Vector3 = game.world_position(Vector2(1.5, 14.5))
	check(game._vfx_ground_at(stone_at) == "road", "paved tile is road")
	check(game._vfx_ground_at(dirt_at) == "dirt", "worn tile is dirt")
	check(game._vfx_ground_at(grass_at) == "grass", "open ground is grass")
	game.rain_level = 0.0
	game.effect_nodes.clear()
	for spot in [stone_at, dirt_at, grass_at]:
		game._puffs_this_frame = 0
		game._footfall_puff(spot)
	check(int(game._vfx_stats["grit"]) == 1 and int(game._vfx_stats["dust"]) == 1 and int(game._vfx_stats["leaf_kicks"]) == 1, "each ground kicks up its own thing")
	var leaves_live: int = 0
	for leaf in game._vfx_leaf_pool:
		if leaf.emitting:
			leaves_live += 1
	check(leaves_live == 1, "grass footfall fires one leaf burst")
	game.rain_level = 0.8
	game._puffs_this_frame = 0
	game._footfall_puff(grass_at)
	check(int(game._vfx_stats["splashes"]) == 1, "footfall splashes in the rain instead of stopping")
	game.rain_level = 0.0

	# Building life: finished buildings only, capped, busiest first, phones get fewer.
	game._vfx_sync_sites()
	var count: int = game._vfx_sites.size()
	check(count > 0 and count <= game.VFX_SITES_MAX, "buildings get a few emitters")
	var hall_id: int = -1
	for building in game.sim.buildings:
		if str(building["type"]) == "hall":
			hall_id = int(building["id"])
	check(hall_id != -1 and game._vfx_sites.has(hall_id) and (game._vfx_sites[hall_id] as CPUParticles3D).has_meta("smoke"), "the hall has a chimney")
	game.low_power = true
	game._vfx_sync_sites()
	check(game._vfx_sites.size() <= game.VFX_SITES_LOW, "phones get fewer site emitters")
	game.low_power = false
	game.sim.buildings[0]["remaining"] = 30.0
	game._vfx_sync_sites()
	var site_ids: Array = game._vfx_sites.keys()
	check(not site_ids.has(int(game.sim.buildings[0]["id"])), "buildings under construction have no emitter")
	game.sim.buildings[0]["remaining"] = 0.0

	# Collect twinkle, throttled.
	game._vfx_pop_clock = 0.0
	var glints_before: int = int(game._vfx_stats["glints"])
	game._spawn_collect_pop({"resource": "gold", "amount": 5, "x": 8.0, "y": 8.0})
	check(int(game._vfx_stats["glints"]) == glints_before + 1, "a collect pop twinkles")
	game._spawn_collect_pop({"resource": "gold", "amount": 5, "x": 8.0, "y": 8.0})
	check(int(game._vfx_stats["glints"]) == glints_before + 1, "twinkles are throttled")

	print("VFX ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
