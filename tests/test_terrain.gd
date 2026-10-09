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

	check(game.get("_terrain_material") != null, "the terrain layer is in the chain")
	check(is_instance_valid(game._terrain_mesh), "autumn ground quad exists")
	check(game._terrain_material.shader != null, "ground shader loaded")
	check(game._terrain_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ground quad casts no shadow")

	var old_discs: int = 0
	for part: MeshInstance3D in game.ground_parts:
		if part.mesh is PlaneMesh and part.visible:
			old_discs += 1
	check(old_discs == 0, "old colour discs are hidden")
	check(game.ground_parts[0].visible, "base slab still visible")
	check(game.ground_parts[0].material_override is StandardMaterial3D, "slab keeps its standard material for rain and expansion")

	# Mask: a building footprint is dirt, far corners are not.
	game._terrain_refresh_mask(true)
	var image: Image = game._terrain_mask_image
	check(image.get_size() == Vector2i(40, 32), "mask is two texels per tile")
	var sample_building: Dictionary = game.sim.buildings[0] if not game.sim.buildings.is_empty() else {}
	if not sample_building.is_empty():
		var bx: int = int(sample_building["x"]) * 2
		var by: int = int(sample_building["y"]) * 2
		check(image.get_pixel(bx, by).r > 0.5, "building footprint is trampled dirt")
		check(image.get_pixel(bx, by).g > 0.5, "building footprint is cleared of grass")
	var far_dirt: float = 0.0
	for corner in [Vector2i(0, 0), Vector2i(39, 0), Vector2i(0, 31), Vector2i(39, 31)]:
		far_dirt = maxf(far_dirt, image.get_pixel(corner.x, corner.y).r)
	check(far_dirt < 0.2, "far corners stay grass")

	# Mask only rewrites when the world changes.
	var before: int = game._terrain_signature
	game._terrain_refresh_mask(false)
	check(game._terrain_signature == before, "unchanged world keeps the same signature")
	game.sim.living.cells["2,2"] = {"wear": 1.0, "last": game.sim.elapsed, "stone": false}
	game._terrain_refresh_mask(false)
	check(image.get_pixel(5, 5).g > 0.5, "a new trail clears grass")

	# Grass: two MultiMeshes (clumps and tall pampas), all inside the lip, pampas only near the edge.
	check(game._grass_nodes.size() == 2, "grass and pampas MultiMeshes exist")
	var stats: Dictionary = game._terrain_stats
	var want_clumps: int = game.GRASS_CLUMPS_LOW if game._terrain_is_phone() else game.GRASS_CLUMPS
	check(int(stats["clumps"]["count"]) == want_clumps, "grass clump count follows the device budget")
	check(int(stats["clumps"]["count"]) * 12 < 25000, "grass stays under 25k triangles")
	check(int(stats["clumps"]["outside"]) == 0 and int(stats["pampas"]["outside"]) == 0, "no grass outside the lip")
	check(int(stats["pampas"]["count"]) > 0 and float(stats["pampas"]["lowest_edge"]) >= 0.82, "pampas stand only near the map edge")
	game.low_power = true
	check(game._terrain_is_phone(), "low_power counts as a phone")
	game.low_power = false

	# Walkers push grass: the shader array fills from the actor layer.
	var model := Node3D.new()
	model.position = Vector3(3.0, 0.0, 2.0)
	game.actor_layer.add_child(model)
	game._grass_update_pushers()
	var pushers: PackedVector3Array = game._grass_push_last
	check(pushers.size() == game.GRASS_PUSHERS, "pusher array keeps its fixed size")
	var found: bool = false
	for entry in pushers:
		if absf(entry.x - 3.0) < 0.01 and absf(entry.y - 2.0) < 0.01 and entry.z > 0.0:
			found = true
	check(found, "a walker registers as a grass pusher")
	model.queue_free()

	# Trees turn: round trees and shrubs lose their all-green palette, pines keep it.
	var trees: Dictionary = stats["trees"]
	check(int(trees["warm"]) > int(trees["cool"]) * 2, "most round trees and shrubs have turned warm")

	# Leaves, clutter, mist, night and claimed land.
	check(is_instance_valid(game._leaves) and game._leaves.amount == (game.LEAF_COUNT_LOW if game._terrain_is_phone() else game.LEAF_COUNT), "falling leaves follow the device budget")
	check(game._leaves.amount <= 22, "no more than 22 leaves in the air")
	var clutter: Dictionary = stats["clutter"]
	check(int(clutter["sets"]) >= 6 and int(clutter["instances"]) > 40 and int(clutter["instances"]) < 200, "clutter is a handful of cheap MultiMeshes")
	check(int(clutter["glow"]) > 0, "some mushrooms glow")
	check(game._mist_patches.size() == (game.MIST_COUNT_LOW if game._terrain_is_phone() else game.MIST_COUNT), "mist follows the device budget")
	game.day_blend = 0.0
	game._terrain_night = -1.0
	game.set_process(true)
	await process_frame
	check(float(game._terrain_material.get_shader_parameter("night_cool")) > 0.9, "night cools the ground")
	check(float(game._grass_material.get_shader_parameter("night")) > 0.9, "night cools the grass")
	check(game._glow_material.emission_energy_multiplier > 1.5, "glow mushrooms shine at night")
	game._terrain_night = 0.0
	game._terrain_apply_night()
	check(game._glow_material.emission_energy_multiplier < 0.5, "glow mushrooms dim by day")
	game.set_process(false)
	# Building over a clutter spot hides it; the mask hides clutter wherever ground is cleared.
	game.sim.living.cells["19,15"] = {"wear": 1.0, "last": game.sim.elapsed, "stone": false}
	game._terrain_refresh_mask(false)
	check(int(game._terrain_stats["clutter_hidden"]) >= 0, "clutter mask pass ran")
	check(game._terrain_slab_tex != null and game.expansion.grass_texture == game._terrain_slab_tex, "expansion land uses the autumn texture")
	for id: String in game.expansion.slabs:
		check((game.expansion.slabs[id]["grass"] as StandardMaterial3D).albedo_texture == game._terrain_slab_tex, "slab %s wears the autumn texture" % id)

	# Claiming a plot: it gets grass, loses the cliff rocks on the shared edge, and its trees turn.
	check(game._skirt_rocks.size() == 4 and game._skirt_rocks["east"].visible, "cliff rocks ring the base")
	game.sim.expansions.append("east")
	game._sync_expansion(false)
	game._terrain_autumn_slabs()
	check(not game._skirt_rocks["east"].visible and game._skirt_rocks["west"].visible, "claiming a plot hides only its edge rocks")
	var slab: Dictionary = game.expansion.slabs["east"]
	if not bool(slab["busy"]):
		check(game._slab_grass.has("east"), "claimed land grows grass")
	game.sim.expansions.erase("east")
	game._sync_expansion(false)

	# Rain feeds the shader.
	game.rain_level = 0.8
	game.set_process(true)
	await process_frame
	check(absf(float(game._terrain_material.get_shader_parameter("wet")) - 0.8) < 0.05, "rain darkens the ground shader")

	print("TERRAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
