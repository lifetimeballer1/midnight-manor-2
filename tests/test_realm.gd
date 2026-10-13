extends SceneTree

# The Realm (realm_map.gd + village_realm.gd): the open world around the manor. Generation is
# deterministic, settlements sit on dry land in the realm, claims resolve by strength, growth only
# follows active time, the realm save round-trips and rejects junk, and the scene layer streams
# trees and settlements within its phone caps without touching the village.

const RealmMap = preload("res://scripts/game/realm_map.gd")

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
	_data_checks()
	await _scene_checks()
	print("test_realm: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("PASS test_realm")
	quit(0 if failures.is_empty() else 1)


func _data_checks() -> void:
	var a = RealmMap.new()
	a.generate(7)
	var b = RealmMap.new()
	b.generate(7)
	check(a.settlements.size() == RealmMap.FACTIONS.size(), "five rival settlements")
	check(RealmMap.REALM_TILES == 256 and is_equal_approx(RealmMap.HALF * 2.0, RealmMap.REALM_TILES * RealmMap.TILE), "realm is 256 x 256 tiles")
	var same: bool = true
	for index in a.settlements.size():
		same = same and (a.settlements[index]["centre"] as Vector2).is_equal_approx(b.settlements[index]["centre"])
	check(same, "same seed, same world")
	var nearest: float = INF
	for site: Dictionary in a.settlements:
		var centre: Vector2 = site["centre"]
		nearest = minf(nearest, centre.length())
		check(absf(centre.x) < RealmMap.HALF - 30.0 and absf(centre.y) < RealmMap.HALF - 30.0, "%s sits inside the realm" % site["name"])
		check(centre.length() > 80.0, "%s stays clear of the village and its plots" % site["name"])
		check(not a.is_water(centre.x, centre.y), "%s is on dry land" % site["name"])
		check(a.owner_at(centre.x, centre.y) == site["id"], "%s owns its own centre" % site["name"])
	# The batched owner lookup used by the ground repaint agrees with the single-point rule.
	var probes := PackedVector3Array()
	for pz in range(-250, 251, 10):
		for px in range(-250, 251, 10):
			probes.append(Vector3(px, 0.0, pz))
	var batched: Array[String] = a.owners_at(probes)
	var agree: bool = true
	for index in probes.size():
		agree = agree and batched[index] == a.owner_at(probes[index].x, probes[index].z)
	check(agree, "batched owner lookup matches owner_at everywhere")
	check(nearest < 130.0, "the nearest neighbour is close enough to find from home (%.0f m)" % nearest)
	check(a.owner_at(0.0, 0.0) == "home", "the manor owns the middle")
	check(is_equal_approx(a.height_at(0.0, 0.0), RealmMap.BASE_Y), "the ground around home stays flat")

	# Claims grow with plots and resolve by strength.
	var radius_before: float = a.home_radius()
	var revision: int = a.revision
	a.set_home_plots(2)
	check(a.home_radius() > radius_before and a.revision > revision, "claimed plots widen the manor's land")

	# Growth follows active time only and widens the claim and the settlement.
	var site: Dictionary = a.settlements[0]
	var pop: int = int(site["pop"])
	var claim: float = a.claim_radius(site)
	var buildings: int = a.layout(site).size()
	check(not a.advance(RealmMap.GROWTH_SECONDS * 0.5), "half a growth step adds nobody")
	check(a.advance(RealmMap.GROWTH_SECONDS * 20.0), "time adds settlers")
	check(int(site["pop"]) >= mini(pop + 20, RealmMap.POP_CAP), "at least one settler per growth step (pop %d)" % int(site["pop"]))
	check(a.claim_radius(site) > claim, "more people claim more land")
	check(a.layout(site).size() > buildings, "more people build more cottages")
	a.advance(RealmMap.GROWTH_SECONDS * 200.0)
	check(int(site["pop"]) == RealmMap.POP_CAP, "population stops at the cap")

	# Save round trip and junk.
	var saved: Dictionary = a.to_dict()
	var c = RealmMap.new()
	check(c.from_dict(JSON.parse_string(JSON.stringify(saved))), "realm save loads")
	check(int(c.settlements[0]["pop"]) == RealmMap.POP_CAP, "growth survives the save")
	check((c.settlements[1]["centre"] as Vector2).is_equal_approx(a.settlements[1]["centre"]), "the world regenerates from its seed")
	check(not c.from_dict({"version": 99}), "unknown versions are refused")
	check(not c.from_dict("nonsense"), "junk is refused")
	check(not c.from_dict({"version": 1, "seed": "x"}), "a bad seed is refused")

	# Trees: deterministic, never on water, around settlements or over the outskirts trees.
	var total: int = 0
	var clean: bool = true
	for cz in a.chunk_count():
		for cx in a.chunk_count():
			for tree: Dictionary in a.trees_in_chunk(Vector2i(cx, cz)):
				total += 1
				var pos: Vector3 = tree["pos"]
				if a.is_water(pos.x, pos.z) or (absf(pos.x) < RealmMap.SCENERY_CLEAR.x and absf(pos.z) < RealmMap.SCENERY_CLEAR.y):
					clean = false
	check(clean, "no realm tree on water or over the outskirts trees")
	check(total > 500 and total < 8000, "a phone-sized forest (%d trees)" % total)
	check(a.trees_in_chunk(Vector2i(3, 4)).size() == b.trees_in_chunk(Vector2i(3, 4)).size(), "trees are deterministic")
	check(a.trees_in_chunk(Vector2i(3, 4), 0.5).size() <= a.trees_in_chunk(Vector2i(3, 4)).size(), "phone density thins trees")


func _scene_checks() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)

	var in_chain: bool = false
	var layer: Script = game.get_script()
	while layer != null:
		if layer.resource_path == "res://scripts/game/village_realm.gd":
			in_chain = true
		layer = layer.get_base_script()
	check(in_chain, "the realm layer is in the scene root's script chain")
	check(game.realm != null, "the realm exists")
	check(game.pan_limit.x > 200.0 and game.pan_limit.y > 200.0, "the camera can pan out to the realm")
	check(game.zoom_max > 90.0, "the camera can zoom out over the realm")
	check(is_instance_valid(game._realm_ground) and game._realm_ground.mesh != null, "realm ground is built")
	check(game._realm_ground.mesh.get_surface_count() == 1, "realm ground is one draw call")
	var haunt_plane: MeshInstance3D = game._haunt_root.get_node_or_null("OutskirtsGround")
	check(haunt_plane != null and (haunt_plane.mesh as PlaneMesh).size.x < 200.0, "the haunted ground is trimmed to the outskirts")

	# At home only home-area chunks load; no settlement is close enough to load.
	game.target = Vector3.ZERO
	game.zoom = 31.0
	game._camera_update()
	game.realm_stream(true)
	var cap: int = game.REALM_TREE_CHUNKS_LOW if game._realm_phone else game.REALM_TREE_CHUNKS
	check(game.realm_tree_chunks_loaded() <= cap, "tree chunks stay within the cap at home")
	check(game.realm_sites_loaded().is_empty(), "no settlement models load while looking at home")

	# Fly to the nearest settlement: it loads with walking people, within the phone caps.
	var site: Dictionary = game.realm.settlements[0]
	var centre: Vector2 = site["centre"]
	game.target = Vector3(centre.x, 0.0, centre.y)
	game._camera_update()
	game.realm_stream(true)
	check(str(site["id"]) in game.realm_sites_loaded(), "the settlement under the camera loads")
	var site_cap: int = game.REALM_SITES_LOADED_LOW if game._realm_phone else game.REALM_SITES_LOADED
	check(game.realm_sites_loaded().size() <= site_cap, "settlements stay within the cap")
	check(game.realm_walker_count() > 0, "its people are out walking")
	check(game.realm_tree_chunks_loaded() <= cap, "tree chunks stay within the cap away from home")

	# Zoomed all the way out, the caps still hold.
	game.zoom = game.zoom_max
	game._camera_update()
	game.realm_stream(true)
	check(game.realm_tree_chunks_loaded() <= cap, "tree chunks stay within the cap fully zoomed out")

	# Growth repaints the borders; the village simulation is untouched by the realm.
	var resources: Dictionary = game.sim.resources.duplicate()
	var revision: int = game.realm.revision
	game.realm.advance(RealmMap.GROWTH_SECONDS * 3.0)
	game.realm_stream(false)
	check(game._realm_ground_revision == game.realm.revision and game.realm.revision > revision, "border changes repaint the ground")
	check(game.sim.resources == resources, "the realm never touches village resources")
	check(not game.realm_save(), "no realm save in a no-save session")
	game.queue_free()
	await process_frame
