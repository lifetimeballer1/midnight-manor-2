extends SceneTree

# Visual progression (village_tiers), looks only: each level of a building shows a richer model and
# a better yard, the Hall leads the ladder, defenses are left to their own layer, and every
# building model shares one colour palette.

const Tiers = preload("res://scripts/game/village_tiers.gd")
const Rank = preload("res://scripts/game/village_rank.gd")
const Sim = preload("res://scripts/game/village_sim.gd")
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


func _yard_vertices(model: Node3D) -> int:
	var count: int = 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.get_parent().name == "TierYard" and mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				count += mesh_node.mesh.surface_get_array_len(surface)
	return count


func _run() -> void:
	# Art tiers spread across all six exported models, top tier always shows the richest one.
	check(Tiers.art_tier("cottage", 1, 3) == 1 and Tiers.art_tier("cottage", 2, 3) == 4 and Tiers.art_tier("cottage", 3, 3) == 6, "a three-tier cottage shows art 1, 4, 6")
	check(Tiers.art_tier("chapel", 2, 2) == 6, "a two-tier building's top tier shows art 6")
	check(Tiers.art_tier("manner-citadel", 4, 4) == 6, "a four-tier building's top tier shows art 6")
	check(Tiers.art_tier("archer_tower", 2, 4) == 2, "defenses keep their own tier mapping")
	check(Tiers.art_tier("farm", 3, 3) == 1, "the farm keeps its dressed tier 1 model (young wheat)")
	check(Tiers.stage(1, 3) == 1 and Tiers.stage(3, 3) == 6, "the yard ladder runs from bare earth to the gold court")
	check(Tiers.stage(1, 1) == Tiers.ONE_TIER_STAGE, "a one-tier building gets a settled yard")
	for max_tier in range(2, 5):
		var last: int = 0
		for tier in range(1, max_tier + 1):
			var now: int = Tiers.stage(tier, max_tier)
			check(now > last, "each level climbs the ladder (%d of %d)" % [tier, max_tier])
			last = now

	# Village ranks: Camp to Manor from building levels; each rank lifts output a little.
	check(Rank.index_for(0) == 0 and Rank.index_for(9) == 0 and Rank.index_for(10) == 1, "10 levels make a Hamlet")
	check(Rank.index_for(75) == Rank.RANKS.size() - 1 and Rank.index_for(9999) == Rank.RANKS.size() - 1, "Manor is the top rank")
	var sim = Sim.new()
	sim.rank.refresh(sim)
	var start_levels: int = sim.rank.levels
	check(sim.rank.title() == "Camp" and is_equal_approx(sim.rank.multiplier(), 1.0), "a new village is a Camp with no bonus (%d levels)" % start_levels)
	var worker: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if sim.building_specs[b["type"]].get("production") != null and worker.is_empty():
			worker = b
	var plain_rate: float = sim.production_rate(worker)
	var walls_before: int = sim.rank.levels
	for b: Dictionary in sim.buildings:
		if b["type"] == "wall": b["tier"] = 3
	sim.rank.refresh(sim)
	check(sim.rank.levels == walls_before, "walls do not count toward rank")
	for b: Dictionary in sim.buildings:
		if b["type"] == "hall": b["tier"] = 3
		elif not Tiers.skipped(str(b["type"])): b["tier"] = (sim.building_specs[b["type"]]["tiers"] as Array).size()
	sim.rank.refresh(sim)
	check(sim.rank.index >= 1, "raising every building lifts the rank (%d levels, %s)" % [sim.rank.levels, sim.rank.title()])
	var raised: float = sim.production_rate(worker)
	var tier_part: float = float(sim.building_specs[worker["type"]]["tiers"][int(worker["tier"]) - 1]["rateMultiplier"]) / float(sim.building_specs[worker["type"]]["tiers"][0]["rateMultiplier"])
	check(is_equal_approx(raised, plain_rate * tier_part * sim.rank.multiplier()), "workplace output carries the rank bonus")
	var ranked: int = sim.rank.index
	for b: Dictionary in sim.buildings:
		if b["type"] != "hall": b["hp"] = 0.0
	sim.rank.refresh(sim)
	check(sim.rank.index == ranked, "ruins still count: a lost raid never demotes the village")
	var copy = Sim.new()
	check(copy.restore_state(sim.export_state()) and copy.rank.index == ranked, "a loaded save arrives at its earned rank at once")

	# One shared palette for every building model.
	var reference: PackedByteArray = FileAccess.get_file_as_bytes("res://art/cottage_t1/cottage_t1_MMR Shared Color Palette 64.png")
	var odd: Array[String] = []
	for dir_name: String in DirAccess.get_directories_at("res://art"):
		if dir_name.begins_with("char_"):
			continue
		var path: String = "res://art/%s/%s_MMR Shared Color Palette 64.png" % [dir_name, dir_name]
		if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) != reference:
			odd.append(dir_name)
	check(odd.is_empty(), "every building uses the shared palette (odd: %s)" % ", ".join(odd))

	# The real village: the yard grows with level, the building grows into its plot.
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.paused = true
	await process_frame
	var hall: Dictionary = {}
	var cottage: Dictionary = {}
	for b: Dictionary in game.sim.buildings:
		if b["type"] == "hall": hall = b
		if b["type"] == "barracks" and cottage.is_empty(): cottage = b
	check(not hall.is_empty() and not cottage.is_empty(), "the starting village has a Hall and barracks")
	var sizes: Array[float] = []
	var yards: Array[int] = []
	for tier in range(1, 4):
		cottage["tier"] = tier
		game.sim.revision += 1
		game._rebuild_buildings()
		var view: Dictionary = game.building_views[int(cottage["id"])]
		var model: Node3D = view["model"]
		check(game._building_asset(cottage) == "barracks_t%d" % Tiers.art_tier("barracks", tier, 3), "barracks level %d shows its spread model" % tier)
		check(model.find_child("TierYard", true, false) != null, "barracks level %d has a yard" % tier)
		sizes.append(model.scale.x)
		yards.append(_yard_vertices(model))
	check(sizes[0] < sizes[1] and sizes[1] < sizes[2], "the barracks grow into its plot as it levels")
	check(yards[0] < yards[2], "the top-level yard has more to it than the first")
	hall["tier"] = 3
	game.sim.revision += 1
	game._rebuild_buildings()
	var hall_model: Node3D = game.building_views[int(hall["id"])]["model"]
	check(hall_model.find_child("TierFinial", true, false) != null, "the top-tier Hall flies a pennant on its roof")
	game.sim.rank.refresh(game.sim)
	game._refresh_hud()
	check(game.sim.rank.title().to_upper() in game.title_label.text, "the HUD title carries the rank (%s)" % game.title_label.text)
	check("building levels" in game.title_label.tooltip_text, "hovering the title explains the rank")
	# Defenses are left alone.
	for b: Dictionary in game.sim.buildings:
		if Tiers.skipped(str(b["type"])) and game.building_views.has(int(b["id"])):
			var m: Node3D = game.building_views[int(b["id"])]["model"]
			check(m.find_child("TierYard", true, false) == null, "%s has no tier yard" % b["type"])
			break
	# Looks only: the sim never sees any of this.
	check(not cottage.has("stage") and not cottage.has("art"), "nothing is written into the building record")
	game.queue_free()
	await process_frame
	print("VISUAL_PROGRESSION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
