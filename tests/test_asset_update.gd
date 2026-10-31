extends SceneTree

# Asset update (looks and sounds only): the young wheat is wheat plants with seed heads, grass clumps
# are soft seven-blade tufts, the land outside the walls has layered firs and lighter boulders, and the
# interface sound kit renders every kind as a clean, unclipped sound. Each unlocked reach has its own meadow.

const Dressing = preload("res://scripts/game/village_dressing.gd")
var checks: int = 0
var failures: Array[String] = []
var game


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func _vertices(mesh: Mesh) -> int:
	var count: int = 0
	if mesh == null:
		return 0
	for surface in mesh.get_surface_count():
		count += mesh.surface_get_array_len(surface)
	return count


func _run() -> void:
	# Meshes built by the dressing module.
	var plant: ArrayMesh = Dressing.wheat_plant_mesh()
	check(_vertices(plant) > 300, "a wheat plant has stalks, heads and leaves (%d vertices)" % _vertices(plant))
	var plant_box: AABB = plant.get_aabb()
	check(plant_box.position.y > -0.02 and plant_box.end.y > 0.28 and plant_box.end.y < 0.5, "a wheat plant stands about knee high on the ground (%s)" % plant_box)
	var fir: ArrayMesh = Dressing.fir_mesh(true)
	check(_vertices(fir) > _vertices(Dressing.fir_mesh(false)), "the fir's trunk is optional")
	check(fir.get_aabb().end.y > 2.0 and fir.get_aabb().end.y < 2.6, "a fir is about as tall as the old cone pine (%s)" % fir.get_aabb())

	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	await process_frame

	# Young wheat on the tier 1 farm uses the plant mesh, one per spot along the furrows.
	var found: bool = false
	for node: Node in game.find_children("Wheat", "MultiMeshInstance3D", true, false):
		var multi := (node as MultiMeshInstance3D).multimesh
		if multi != null and multi.instance_count == Dressing.WHEAT_ROWS * Dressing.WHEAT_PER_ROW:
			found = true
			check(_vertices(multi.mesh) > 300, "the farm's wheat is wheat plants, not sticks")
			break
	check(found, "a tier 1 farm grows young wheat")

	# Grass clumps: seven blades of five triangles each.
	check(_vertices(game._grass_clump_mesh()) == game.CLUMP_BLADES * 15, "a grass clump is seven curved blades")

	# Interface sounds: every kind renders, has body, and never clips.
	for kind: String in ["click", "confirm", "collect", "upgrade", "repair", "horn", "deny", "chirp"]:
		var stream: AudioStreamWAV = game._sfx_render(kind)
		var frames: int = stream.data.size() / 2
		var peak: int = 0
		for i in frames:
			peak = maxi(peak, absi(stream.data.decode_s16(i * 2)))
		check(frames > 22050 * 0.04, "%s lasts long enough to hear" % kind)
		check(peak > 2000 and peak < 32000, "%s is audible and unclipped (peak %d)" % [kind, peak])
		check(absi(stream.data.decode_s16((frames - 1) * 2)) < 600, "%s ends at rest, without a click" % kind)
		check(game._sfx_render(kind) == stream, "%s is rendered once and cached" % kind)

	# Unlocked land: each reach wears its own era's meadow by claim order, so new land never looks like
	# the land claimed before it, and locked land keeps the plain meadow.
	for resource: String in ["wood", "stone", "gold"]:
		game.sim.resources[resource] = 99999
	var textures: Array = []
	for id: String in ["north", "east", "west", "south"]:
		check(game.land_era(id) == -1, "%s has no era while locked" % id)
		check(game.sim.expand(id), "%s can be claimed" % id)
		game._sync_expansion(false)
		await process_frame
		check(game.land_era(id) == textures.size(), "%s takes era %d" % [id, textures.size()])
		var grass: StandardMaterial3D = game.expansion.slabs[id]["grass"]
		check(not textures.has(grass.albedo_texture), "%s does not share its ground with land claimed before" % id)
		textures.append(grass.albedo_texture)
		check(game._slab_flowers.has(id) and game._slab_flowers[id].multimesh.instance_count > 0, "%s grows its own wildflowers" % id)
	check(game.expansion.slabs["north"]["grass"].albedo_texture == game._terrain_slab_tex, "the first reach keeps the plain autumn meadow")

	game.queue_free()
	await process_frame
	print("ASSET_UPDATE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
