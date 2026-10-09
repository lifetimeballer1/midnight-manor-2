extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func _run() -> void:
	test_in_world()
	test_locked_plots()
	test_claim_flow()
	test_cost_scaling()
	test_building_in_claimed_plots()
	test_pathing_inside_plot()
	test_raid_spawn_edges()
	test_save_round_trip()
	test_living_cells_in_plots()
	test_legacy_and_invalid_saves()
	print("EXPANSION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


# Gives a sim the Frontier act and a secured region, then claims the plot.
func claim(sim, plot: String, region: String) -> void:
	sim.chronicle.act = 4
	sim.chronicle.set_region(region, "scouted")
	sim.chronicle.set_region(region, "contested")
	sim.chronicle.set_region(region, "secured")
	sim.resources["wood"] = 5000.0
	sim.resources["stone"] = 2000.0
	check(sim.expand(plot), "expand(%s) succeeds once the region is secured and affordable" % plot)


func test_in_world() -> void:
	var sim = Sim.new()
	check(sim.in_world(Vector2i(0, 0)) and sim.in_world(Vector2i(19, 15)), "base corners are in the world")
	check(not sim.in_world(Vector2i(20, 0)) and not sim.in_world(Vector2i(0, 16)), "base edges are exclusive")
	check(not sim.in_world(Vector2i(-1, 0)) and not sim.in_world(Vector2i(0, -1)), "negative tiles are outside before any claim")
	check(sim.world_bounds() == Rect2i(0, 0, 20, 16), "world bounds equal the base before any claim")
	sim.expansions.append("west")
	check(sim.in_world(Vector2i(-1, 0)) and sim.in_world(Vector2i(-6, 15)), "claimed west plot is in the world")
	check(sim.in_world(Vector2i(-10, 0)) and sim.in_world(Vector2i(-10, 15)), "the far west column is in the world")
	check(not sim.in_world(Vector2i(-11, 0)), "tile past the west plot edge is outside")
	check(not sim.in_world(Vector2i(-10, -1)) and not sim.in_world(Vector2i(-1, 16)), "plot corners outside every claimed rect are outside")
	check(not sim.in_world(Vector2i(20, 0)), "unclaimed east plot stays outside")
	check(sim.world_bounds() == Rect2i(-10, 0, 30, 16), "world bounds span base plus west plot")
	sim.expansions.append("north")
	check(sim.in_world(Vector2i(0, -6)) and sim.in_world(Vector2i(19, -1)), "claimed north plot is in the world")
	check(sim.in_world(Vector2i(-10, -10)) and sim.in_world(Vector2i(29, -1)), "north plot far corners are in the world")
	check(not sim.in_world(Vector2i(0, -11)) and not sim.in_world(Vector2i(30, -1)), "north plot edges are exclusive")
	check(sim.world_bounds() == Rect2i(-10, -10, 40, 26), "world bounds span base plus west and north plots")
	sim.expansions.append("east")
	sim.expansions.append("south")
	check(sim.world_bounds() == Rect2i(-10, -10, 40, 36), "all four plots form one 40x36 world")
	check(sim.in_world(Vector2i(29, 25)) and sim.in_world(Vector2i(-10, 25)), "south and east far corners are in the world")
	check(not sim.in_world(Vector2i(30, 25)) and not sim.in_world(Vector2i(0, 26)), "tiles past the 40x36 world are outside")


func test_locked_plots() -> void:
	var sim = Sim.new()
	check(sim.expansion_reason("moon") == "Unknown reach.", "unknown plot ids are refused")
	check(sim.expansion_reason("west") == "The Frontier is not open yet.", "claiming waits for the Frontier act")
	sim.chronicle.act = 4
	check(sim.expansion_reason("west") == "Secure Blackwater Mouth first.", "claiming waits for the region to be secured")
	check(not sim.expand("west") and sim.notice == "Secure Blackwater Mouth first.", "refused expand sets notice to the reason")
	check(sim.expansions.is_empty(), "refused expand claims nothing")
	check(not sim.build("farm", -2, 4) and sim.notice == "Outside the village.", "building in a locked west plot is refused")
	check(sim.build_reason("farm", 22, 4) == "Outside the village.", "building in a locked east plot is refused")


func test_claim_flow() -> void:
	var sim = Sim.new()
	claim(sim, "west", "blackwater-mouth")
	check(sim.expansions.size() == 1 and sim.expansions[0] == "west", "claimed ids are recorded in order")
	check(sim.notice.contains("West Reach"), "successful claim sets a notice naming the plot")
	check(sim.expansion_reason("west") == "Already claimed.", "a claimed plot cannot be claimed again")
	check(not sim.expand("west"), "expand refuses a claimed plot")
	var fresh = Sim.new()
	fresh.chronicle.act = 4
	fresh.chronicle.set_region("whisperwood", "scouted")
	fresh.chronicle.set_region("whisperwood", "contested")
	fresh.chronicle.set_region("whisperwood", "secured")
	fresh.resources["wood"] = 100.0
	fresh.resources["stone"] = 60.0
	check(fresh.expansion_reason("east") == "Needs 250 Wood, 100 Stone.", "unaffordable claims explain the full cost")
	check(not fresh.expand("east") and fresh.expansions.is_empty(), "unaffordable claim spends nothing and claims nothing")
	fresh.resources["wood"] = 250.0
	fresh.resources["stone"] = 100.0
	check(fresh.expansion_reason("east") == "", "affordable secured claim has an empty reason")
	var before: int = fresh.path_revision
	check(fresh.expand("east"), "expand succeeds when allowed")
	check(fresh.path_revision > before, "successful claim bumps path_revision")
	check(fresh.resources["wood"] == 0.0 and fresh.resources["stone"] == 0.0, "successful claim spends the cost")
	var raided = Sim.new()
	raided.chronicle.act = 4
	raided.chronicle.set_region("starwatch-ridge", "scouted")
	raided.chronicle.set_region("starwatch-ridge", "contested")
	raided.chronicle.set_region("starwatch-ridge", "secured")
	raided.resources["wood"] = 5000.0
	raided.resources["stone"] = 2000.0
	raided.raid_warning = true
	check(raided.expansion_reason("north") == "No claiming during a raid.", "claims are refused during a raid warning")


func test_cost_scaling() -> void:
	var sim = Sim.new()
	check(sim.expansion_cost("east") == {"wood": 250, "stone": 100}, "first claim costs 250 Wood and 100 Stone")
	sim.expansions.append("west")
	check(sim.expansion_cost("north") == {"wood": 400, "stone": 160}, "second claim costs 400 Wood and 160 Stone")
	sim.expansions.append("north")
	check(sim.expansion_cost("south") == {"wood": 550, "stone": 220}, "third claim keeps scaling")


func test_building_in_claimed_plots() -> void:
	var sim = Sim.new()
	claim(sim, "west", "blackwater-mouth")
	check(sim.build("farm", -2, 4), "building inside the claimed west plot succeeds")
	check(not sim.building_at(-2, 4).is_empty(), "the west plot building is registered")
	check(sim.build_reason("farm", -2, -2) == "Outside the village.", "a footprint touching the plot corner is refused")
	claim(sim, "north", "starwatch-ridge")
	check(sim.build("wall", 3, -4), "building inside the claimed north plot succeeds: " + sim.notice)
	check(not sim.building_at(3, -4).is_empty(), "the north plot building is registered")
	check(sim.build("wall", -10, -10), "a building on the far north-west corner tile succeeds: " + sim.notice)
	check(not sim.building_at(-10, -10).is_empty(), "the far north-west corner building is registered")
	check(sim.build_reason("farm", 29, -2) == "Outside the village.", "a footprint hanging past the north plot's east edge is refused")

func test_pathing_inside_plot() -> void:
	var sim = Sim.new()
	check(not sim._inside(Vector2i(-3, 10)), "pathing treats an unclaimed plot as outside")
	sim.expansions.append("west")
	check(sim._inside(Vector2i(-3, 10)), "pathing accepts tiles inside the claimed plot")
	var found: Array[Vector2i] = sim.route(Vector2i(-5, 10), Vector2i(-5, 13))
	check(not found.is_empty(), "a route exists between two tiles inside the claimed plot")
	var inside := true
	for tile: Vector2i in found:
		inside = inside and sim.in_world(tile)
	check(inside, "every route step stays inside the world")


func test_raid_spawn_edges() -> void:
	var sim = Sim.new()
	sim.expansions.append("east")
	sim.wave = 4
	sim.enemies.clear()
	sim._spawn_raid()
	var east_edge := false
	for enemy: Dictionary in sim.enemies:
		east_edge = east_edge or is_equal_approx(float(enemy["x"]), 29.5)
	check(east_edge, "raids spawn on the claimed east plot edge")
	var west = Sim.new()
	west.expansions.append("west")
	west.wave = 4
	west.enemies.clear()
	west._spawn_raid()
	var west_edge := false
	for enemy: Dictionary in west.enemies:
		west_edge = west_edge or is_equal_approx(float(enemy["x"]), -9.5)
	check(west_edge, "raids spawn on the claimed west plot edge")
	var base = Sim.new()
	base.wave = 4
	base.enemies.clear()
	base._spawn_raid()
	var base_edge := false
	for enemy: Dictionary in base.enemies:
		base_edge = base_edge or is_equal_approx(float(enemy["x"]), 0.5)
	check(base_edge, "raids keep the base spawn edges when nothing is claimed")
	var full = Sim.new()
	for id: String in ["north", "east", "south", "west"]:
		full.expansions.append(id)
	full.wave = 4
	full.enemies.clear()
	full._spawn_raid()
	var inside := true
	var north_edge := false
	var south_edge := false
	for enemy: Dictionary in full.enemies:
		var point := Vector2(float(enemy["x"]), float(enemy["y"]))
		inside = inside and full.in_world(Vector2i(floori(point.x), floori(point.y)))
		north_edge = north_edge or is_equal_approx(point.y, -9.5)
		south_edge = south_edge or is_equal_approx(point.y, 25.5)
	check(inside, "raids spawn on tiles inside the full 40x36 world")
	check(north_edge and south_edge, "raids reach the north and south edges of a fully claimed world")


func test_save_round_trip() -> void:
	var sim = Sim.new()
	claim(sim, "west", "blackwater-mouth")
	check(sim.build("farm", -2, 4), "a plot building exists before saving")
	check(sim.build("wall", -10, 15), "a building on the far south-west corner exists before saving")
	var state: Dictionary = sim.export_state()
	check(state.get("expansions") == ["west"], "export_state includes the claimed expansions")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(state))
	var loaded = Sim.new()
	check(loaded.restore_state(parsed), "a save with a claimed plot and a building on it loads")
	check(loaded.expansions.size() == 1 and loaded.expansions[0] == "west", "expansions survive a save round-trip")
	check(loaded.in_world(Vector2i(-3, 4)) and not loaded.building_at(-2, 4).is_empty(), "restored plot and its building are present")
	check(loaded.world_bounds() == Rect2i(-10, 0, 30, 16), "restored world bounds match the claimed west plot")
	check(not loaded.building_at(-10, 15).is_empty(), "the far south-west corner building survives a save round-trip")


func test_living_cells_in_plots() -> void:
	var sim = Sim.new()
	claim(sim, "west", "blackwater-mouth")
	sim.elapsed = 160.0
	for i in 160: sim.living.walked(Vector2(-4.0, 5.5), Vector2(-3.0, 5.5), float(i))
	for i in 160: sim.living.walked(Vector2(-9.0, 14.5), Vector2(-8.0, 14.5), float(i))
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	var loaded = Sim.new()
	check(loaded.restore_state(state), "a living trail inside a claimed plot is accepted on load")
	check(float(loaded.living.at(Vector2(-3.5, 5.5)).get("wear", 0.0)) > 0.999, "the claimed-plot trail survives a save round-trip")
	check(float(loaded.living.at(Vector2(-8.5, 14.5)).get("wear", 0.0)) > 0.999, "a trail on the far west column survives a save round-trip")
	var orphan: Dictionary = state.duplicate(true)
	orphan["expansions"] = []
	check(not Sim.new().restore_state(orphan), "a trail on an unclaimed plot rejects the save")


func test_legacy_and_invalid_saves() -> void:
	var sim = Sim.new()
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	legacy.erase("expansions")
	var loaded = Sim.new()
	check(loaded.restore_state(legacy) and loaded.expansions.is_empty(), "a save without the expansions key still loads")
	var unknown: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	unknown["expansions"] = ["moon"]
	check(not Sim.new().restore_state(unknown), "unknown expansion ids reject the save")
	var duplicate: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	duplicate["expansions"] = ["west", "west"]
	check(not Sim.new().restore_state(duplicate), "duplicate expansion ids reject the save")
	var malformed: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	malformed["expansions"] = "west"
	check(not Sim.new().restore_state(malformed), "a non-array expansions value rejects the save")
	var plot_sim = Sim.new()
	claim(plot_sim, "west", "blackwater-mouth")
	plot_sim.build("farm", -2, 4)
	var orphan: Dictionary = JSON.parse_string(JSON.stringify(plot_sim.export_state()))
	orphan.erase("expansions")
	check(not Sim.new().restore_state(orphan), "a building on an unclaimed plot rejects the save")
