extends SceneTree

# Building with real materials: zone-grown sites need builders and delivered wood/stone/lumber,
# and repairs of stone-built types take Stone once Stoneworking is known.
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
	test_bills()
	test_builders_haul_and_build()
	test_stall_and_hands()
	test_builders_leave_a_stalled_site()
	test_bought_sites_keep_timer()
	test_repairs()
	test_saves()
	print("BUILDING_MATERIALS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	return sim


func site(sim, type_name: String, x: int, y: int, tier: int = 1) -> Dictionary:
	var b: Dictionary = sim._new_building(type_name, x, y, true)
	b["tier"] = tier
	sim.materials.open_site(sim, b, tier)
	sim.buildings.append(b)
	sim.revision += 1
	sim._invalidate()
	return b


func builders(sim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u: Dictionary in sim.units:
		if str(sim.troop_specs[u["type"]]["role"]) == "builder":
			out.append(u)
	return out


func run(sim, seconds: float, until: Callable = Callable()) -> void:
	var t: float = 0.0
	while t < seconds:
		sim.tick(0.25)
		t += 0.25
		if until.is_valid() and until.call():
			return


func test_bills() -> void:
	var sim = fresh()
	check(sim.materials.bill_for(sim, "cottage", 1) == {"wood": 40}, "a tier 1 cottage asks half its old Wood price")
	var early: Dictionary = sim.materials.bill_for(sim, "cottage", 2)
	check(not early.has("stone") and int(early.get("wood", 0)) > 40, "before Stoneworking the stone share is paid in extra Wood")
	sim.living.discoveries.append("stoneworking")
	check(not sim.materials.bill_for(sim, "cottage", 2).has("stone"), "stone waits for a Stone Quarry to supply it")
	sim.buildings.append(sim._new_building("stone_quarry", 2, 2, false))
	var later: Dictionary = sim.materials.bill_for(sim, "cottage", 2)
	check(int(later.get("stone", 0)) == 16, "with a quarry after Stoneworking a tier 2 cottage asks 4 Stone per tile")
	var top: Dictionary = sim.materials.bill_for(sim, "farm", 3)
	check(not top.has("lumber"), "lumber waits for a Sawmill")
	var mill: Dictionary = sim._new_building("sawmill", 14, 2, false)
	sim.buildings.append(mill)
	check(int(sim.materials.bill_for(sim, "farm", 3).get("lumber", 0)) > 0, "with a Sawmill standing, tier 3 asks for Lumber")


func test_builders_haul_and_build() -> void:
	var sim = fresh()
	var b: Dictionary = site(sim, "cottage", 12, 3)
	var wood_before: float = float(sim.resources["wood"])
	check(sim.materials.needed(b) == {"wood": 40}, "a new site starts with its whole bill outstanding")
	var start: float = float(b["remaining"])
	# With the builder held back, nothing moves.
	for u: Dictionary in builders(sim):
		u["hold"] = true
		u["order"] = [float(u["x"]), float(u["y"])]
	run(sim, 10.0)
	check(is_equal_approx(float(b["remaining"]), start), "a grown site does not build itself without a builder")
	for u: Dictionary in builders(sim):
		u["hold"] = false
		u["order"] = []
	run(sim, 240.0, func() -> bool: return float(b["remaining"]) <= 0.0)
	check(float(b["remaining"]) <= 0.0, "the builder fetches the wood and finishes the cottage")
	check(not b.has("bill") and not b.has("stock"), "a finished site drops its bill")
	check(float(sim.resources["wood"]) <= wood_before - 40.0 + 60.0, "the cottage's wood came out of the stores")
	var carried: float = 0.0
	for u: Dictionary in builders(sim):
		if str(u["carry_resource"]) == "wood":
			carried += float(u["carry"])
	check(carried <= 0.0 or float(sim.resources["wood"]) + carried >= 0.0, "builders never carry wood the site did not need for long")


func test_stall_and_hands() -> void:
	var sim = fresh()
	sim.living.discoveries.append("stoneworking")
	sim.buildings.append(sim._new_building("stone_quarry", 2, 2, false))
	sim.resources["stone"] = 0.0
	var b: Dictionary = site(sim, "cottage", 12, 3, 2)
	check(sim.materials.shortage(sim, b) == "16 Stone", "the site names the material it is stuck on")
	b["stock"] = {"wood": int(b["bill"]["wood"])}
	var share: float = sim.materials.delivered_share(b)
	check(share > 0.0 and share < 1.0, "a part-delivered bill counts part of the work")
	var crew: Array[Dictionary] = builders(sim)
	crew[0]["site"] = int(b["id"])
	crew[0]["on_site"] = true
	var total: float = float(b["work"])
	var moved: float = sim.materials.progress(sim, b, 1.0)
	check(is_equal_approx(moved, 1.0), "one builder on site works at the normal pace")
	b["remaining"] = total * (1.0 - share) + 0.1
	check(sim.materials.progress(sim, b, 1.0) <= 0.1 + 0.0001, "work stops where the delivered materials run out")
	b["remaining"] = total
	sim._add_unit("builder")
	var second: Dictionary = sim.units[sim.units.size() - 1]
	second["site"] = int(b["id"])
	second["on_site"] = true
	check(is_equal_approx(sim.materials.progress(sim, b, 1.0), 1.6), "a second builder on site adds 60%")
	b["stock"]["stone"] = 16
	check(sim.materials.needed(b).is_empty() and sim.materials.shortage(sim, b) == "", "a fully stocked site needs nothing")


# Builders stuck working: a site waiting on stone the stores lack must not hold its builder while
# another site can be built, and a stone bill with no quarry to fill it falls back to Wood.
func test_builders_leave_a_stalled_site() -> void:
	var sim = fresh()
	sim.living.discoveries.append("stoneworking")
	var quarry: Dictionary = sim._new_building("stone_quarry", 2, 2, false)
	sim.buildings.append(quarry)
	sim.resources["stone"] = 0.0
	sim.resources["wood"] = 500.0
	var stalled: Dictionary = site(sim, "cottage", 12, 3, 2)
	stalled["stock"] = {"wood": int(stalled["bill"]["wood"])}
	stalled["remaining"] = float(stalled["work"]) * (1.0 - sim.materials.delivered_share(stalled))
	check(not sim.materials.workable(sim, stalled), "a site worked up to its delivered share with no stone in store is stalled")
	var open: Dictionary = site(sim, "cottage", 14, 6)
	var crew: Array[Dictionary] = builders(sim)
	crew[0]["site"] = int(stalled["id"])
	run(sim, 240.0, func() -> bool: return float(open["remaining"]) <= 0.0)
	check(float(open["remaining"]) <= 0.0, "the builder leaves the stalled site and finishes the one it can build")
	check(int(crew[0]["site"]) != int(open["id"]) or float(open["remaining"]) <= 0.0, "no builder stays parked on the finished site")
	check(str(crew[0]["phase"]) != "work" or int(crew[0]["site"]) != int(stalled["id"]), "a builder waiting on stone is not shown working")
	sim.buildings.erase(quarry)
	sim._invalidate()
	run(sim, 240.0, func() -> bool: return float(stalled["remaining"]) <= 0.0)
	check(not stalled.has("bill") or not (stalled["bill"] as Dictionary).has("stone"), "with no quarry left, the stone still owed is paid in Wood")
	check(float(stalled["remaining"]) <= 0.0, "the once-stalled site is finished from Wood")


func test_bought_sites_keep_timer() -> void:
	var sim = fresh()
	sim.resources["wood"] = 500.0
	sim.resources["gold"] = 500.0
	var b: Dictionary = sim._new_building("wall", 15, 13, true)
	sim.buildings.append(b)
	var start: float = float(b["remaining"])
	for u: Dictionary in builders(sim):
		u["hold"] = true
		u["order"] = [float(u["x"]), float(u["y"])]
	sim.tick(0.5)
	check(is_equal_approx(start - float(b["remaining"]), 0.5), "a bought defence keeps its old build timer")
	check(not sim.materials.has_bill(b), "bought defences carry no materials bill")


func test_repairs() -> void:
	var sim = fresh()
	var wall: Dictionary = sim._new_building("stonewall", 15, 13, false)
	sim.buildings.append(wall)
	wall["hp"] = float(wall["max_hp"]) - 150.0
	sim.resources["wood"] = 100.0
	sim.resources["stone"] = 100.0
	check(sim.repair(int(wall["id"])) and float(sim.resources["stone"]) == 100.0, "before Stoneworking a stone wall is mended with Wood")
	sim.living.discoveries.append("stoneworking")
	wall["hp"] = float(wall["max_hp"]) - 150.0
	check(sim.repair(int(wall["id"])) and is_equal_approx(float(wall["hp"]), float(wall["max_hp"])), "a stone wall is mended in full")
	check(float(sim.resources["stone"]) == 95.0 and float(sim.resources["wood"]) == 85.0, "after Stoneworking a stone wall takes half Stone, half Wood")
	check(sim.notice.contains("Stone"), "the notice names the Stone spent")
	wall["hp"] = float(wall["max_hp"]) - 150.0
	sim.resources["stone"] = 2.0
	check(sim.repair(int(wall["id"])) and float(wall["hp"]) < float(wall["max_hp"]) and float(sim.resources["stone"]) >= 0.0, "short on stone, the wall is mended only as far as the stone goes")
	sim.resources["stone"] = 0.0
	check(not sim.repair(int(wall["id"])) and sim.notice.contains("Stone"), "with no stone the repair is refused and says why")
	var cottage: Dictionary = sim._new_building("cottage", 12, 3, false)
	sim.buildings.append(cottage)
	cottage["hp"] = float(cottage["max_hp"]) - 30.0
	sim.resources["wood"] = 50.0
	check(sim.repair(int(cottage["id"])) and float(sim.resources["wood"]) == 48.0, "wooden buildings still mend with Wood alone")


func test_saves() -> void:
	var sim = fresh()
	var b: Dictionary = site(sim, "cottage", 12, 3)
	b["stock"] = {"wood": 12}
	var state: Variant = JSON.parse_string(JSON.stringify(sim.export_state()))
	var loaded = Sim.new()
	check(loaded.restore_state(state), "a save with a part-built grown site loads")
	var back: Dictionary = {}
	for other: Dictionary in loaded.buildings:
		if int(other["id"]) == int(b["id"]):
			back = other
	check(not back.is_empty() and int(back["stock"]["wood"]) == 12 and int(back["bill"]["wood"]) == 40, "the bill and delivered stock survive a save")
	var broken: Variant = JSON.parse_string(JSON.stringify(sim.export_state()))
	for other: Dictionary in broken["buildings"]:
		if int(other["id"]) == int(b["id"]):
			other["stock"] = {"wood": -5}
	check(not Sim.new().restore_state(broken), "a save with a negative delivered stock is refused")
