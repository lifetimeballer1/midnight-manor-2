extends SceneTree

# Income milestones: 10, 25 and 50 standing buildings/lots of one zone multiply that zone's income
# (x2, x4, x8). The first look after loading is silent; crossing a line later is announced.
const Sim = preload("res://scripts/game/village_sim.gd")
const Town = preload("res://scripts/game/town_zoning.gd")
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
	test_tiers()
	test_sim_boost()
	await test_in_game()
	print("ZONE_MILESTONES ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func test_tiers() -> void:
	var town = Town.new()
	check(town.milestone_counts().map(func(n: Variant) -> int: return int(n)) == [10, 25, 50], "milestones at 10, 25 and 50 (zones.json)")
	check(town.milestone_tier(0) == 0 and town.milestone_tier(9) == 0, "under 10 is no milestone")
	check(town.milestone_tier(10) == 1 and town.milestone_tier(24) == 1, "10 to 24 is the first")
	check(town.milestone_tier(25) == 2 and town.milestone_tier(50) == 3 and town.milestone_tier(400) == 3, "25 and 50 are the next")
	check(town.milestone_multiplier(0) == 1.0 and town.milestone_multiplier(1) == 2.0 and town.milestone_multiplier(3) == 8.0, "each milestone doubles income")


func test_sim_boost() -> void:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	var farm: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if b["type"] == "farm":
			farm = b
	var plain: float = sim.production_rate(farm)
	var away: float = float(sim.offline_earnings(3600.0).get("food", 0.0))
	sim.zone_boost = {"farm": 2.0}
	check(absf(sim.production_rate(farm) - plain * 2.0) < 0.0001, "a boosted building type produces double")
	check(float(sim.offline_earnings(3600.0).get("food", 0.0)) > away, "the boost carries into offline earnings")


func test_in_game() -> void:
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	await process_frame
	var start: Dictionary = game.zone_standing()
	check(start.has("farming") and start.has("industrial"), "every zone is counted")
	var farms_before: int = int(start["farming"])
	game._refresh_milestones(true)
	check(not game.sim.zone_boost.has("farm"), "a starting village has no milestone yet")
	# Stand enough farm-zone buildings to pass the first milestone.
	var template: Dictionary = {}
	for b: Dictionary in game.sim.buildings:
		if b["type"] == "farm":
			template = b
	var added: int = 10 - farms_before
	for i in added:
		var copy: Dictionary = template.duplicate(true)
		copy["id"] = 90000 + i
		game.sim.buildings.append(copy)
	var banners: int = game.sim.chronicle.banners.size()
	game._refresh_milestones(true)
	check(int(game.zone_standing()["farming"]) == 10, "ten farm-zone buildings stand")
	check(float(game.sim.zone_boost.get("farm", 1.0)) == 2.0 and float(game.sim.zone_boost.get("mill", 1.0)) == 2.0, "every farm-zone type earns double")
	check(float(game.town.zone_boost.get("farming", 1.0)) == 2.0, "farm lots outside the walls earn double too")
	check(not game.sim.zone_boost.has("lumber"), "other zones are untouched")
	check(game.sim.chronicle.banners.size() == banners + 1, "crossing a milestone is announced once")
	game._refresh_milestones(true)
	check(game.sim.chronicle.banners.size() == banners + 1, "and not again while it holds")
	check(game.milestone_text("farming").contains("10/25"), "the zoning bar shows the next goal (%s)" % game.milestone_text("farming"))
	game.sim.buildings.resize(game.sim.buildings.size() - added)
	game._refresh_milestones(true)
	check(not game.sim.zone_boost.has("farm"), "losing buildings loses the milestone")
	game.queue_free()
	await process_frame
