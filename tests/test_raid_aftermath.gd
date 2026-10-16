extends SceneTree

# Raid aftermath: raiders trample estate fields (no yield until farmhands replant), fallen stone
# buildings leave rubble builders salvage, and fallen fighters come round at the Chapel.
const Sim = preload("res://scripts/game/village_sim.gd")
const Growth = preload("res://scripts/game/village_growth.gd")
var checks: int = 0
var failures: Array[String] = []


class FakeTown:
	var village: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func _run() -> void:
	test_trample_and_replant()
	test_rubble_and_salvage()
	test_chapel_recovery()
	test_saves()
	print("RAID_AFTERMATH ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	return sim


# A wheat estate on the east reach, finished, with its fields worked out.
func estate(sim) -> Dictionary:
	for r: String in ["wood", "stone", "gold"]:
		sim.resources[r] = 9999.0
	sim.expand("east")
	var zones: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/zones.json"))
	var growth = Growth.new()
	growth.setup(zones["village"], Vector2i(10, 8), 2)
	var town := FakeTown.new()
	for c: Vector2i in [Vector2i(5, -2), Vector2i(6, -2), Vector2i(5, -1), Vector2i(6, -1)]:
		town.village[c] = "farming"
	var house: Dictionary = growth.grow_one(sim, town)
	var b: Dictionary = sim.get_building(int(house.get("id", -1)))
	if not b.is_empty():
		b["remaining"] = 0.0
		sim.materials.close_site(b)
	growth.refresh_estates(sim, town)
	return b


func test_trample_and_replant() -> void:
	var sim = fresh()
	var house: Dictionary = estate(sim)
	check(not house.is_empty() and sim.estates.has(int(house["id"])), "an estate stands on the reach")
	if house.is_empty():
		return
	var fields: Array = sim.estates[int(house["id"])]["fields"]
	var full: float = sim.estate_scale(house)
	sim.aftermath.begin_raid()
	for i in 4:
		sim.aftermath.trample(sim, fields[i])
	sim.aftermath.trample(sim, fields[0])
	sim.aftermath.trample(sim, Vector2i(2, 2))
	check(sim.aftermath.trampled.size() == 4, "raiders trample field tiles, once each, and nothing off the fields")
	check(sim.estate_scale(house) < full, "trampled fields grow nothing")
	check(sim.aftermath.raid_summary().begins_with("4 field tiles trampled"), "the raid's end names the trampled fields")
	# No farmhands, no replanting; two farmhands replant two tiles every three seconds.
	for u: Dictionary in sim.units:
		u["hold"] = true
	sim.aftermath.tick(sim, 6.0)
	check(sim.aftermath.trampled.size() == 4, "nobody replants an estate with no farmhands")
	for i in 2:
		sim._add_unit("farmer")
		sim.units.back()["workplace"] = int(house["id"])
	sim.raid_active = true
	sim.aftermath.tick(sim, 3.0)
	check(sim.aftermath.trampled.size() == 4, "no replanting while the raid is on")
	sim.raid_active = false
	sim.aftermath.tick(sim, 3.0)
	check(sim.aftermath.trampled.size() == 2, "two farmhands replant two tiles in three seconds")
	sim.aftermath.tick(sim, 3.0)
	check(sim.aftermath.trampled.is_empty() and is_equal_approx(sim.estate_scale(house), full), "replanted, the estate yields in full again")
	# A raider walking the fields in a real raid tramples them.
	var raider: Dictionary = {"id": 9001, "x": float(fields[5].x) + 0.5, "y": float(fields[5].y) + 0.5}
	sim.aftermath.trample(sim, sim.tile_of(raider))
	check(sim.aftermath.trampled.has(fields[5]), "a raider's tile on a field is trampled")


func test_rubble_and_salvage() -> void:
	var sim = fresh()
	sim.living.discoveries.append("stoneworking")
	var wall: Dictionary = sim._new_building("stonewall", 15, 13, false)
	sim.buildings.append(wall)
	var cottage: Dictionary = sim._new_building("cottage", 12, 3, false)
	sim.buildings.append(cottage)
	sim.aftermath.begin_raid()
	sim.aftermath.fell(sim, cottage)
	check(sim.aftermath.rubble.is_empty(), "a wooden building leaves no stone rubble")
	wall["hp"] = 0.0
	sim.aftermath.fell(sim, wall)
	check(sim.aftermath.rubble.size() == 1 and int(sim.aftermath.rubble[0]["stone"]) > 0, "a fallen stone wall leaves rubble")
	var pile: int = int(sim.aftermath.rubble[0]["stone"])
	check(sim.aftermath.raid_summary().contains("salvage %d Stone" % pile), "the raid's end names the stone to salvage")
	var stone: float = float(sim.resources["stone"])
	var t: float = 0.0
	while t < 120.0 and not sim.aftermath.rubble.is_empty():
		sim.tick(0.25)
		t += 0.25
	for i in 120:
		sim.tick(0.25)
	check(sim.aftermath.rubble.is_empty(), "the builder clears the rubble")
	check(float(sim.resources["stone"]) >= stone + pile - 0.5, "its stone reaches the stores (%d -> %d)" % [stone, sim.resources["stone"]])
	var wood: Dictionary = sim._new_building("wall", 16, 13, false)
	sim.aftermath.fell(sim, wood)
	var before = fresh()
	before.aftermath.fell(before, before._new_building("stonewall", 15, 13, false))
	check(before.aftermath.rubble.is_empty(), "before Stoneworking a fallen wall leaves no stone")


func test_chapel_recovery() -> void:
	var sim = fresh()
	check(sim.aftermath.recovery_spot(sim).x < 0.0, "with no Chapel the fallen come round by the Hall")
	var chapel: Dictionary = sim._new_building("chapel", 14, 2, false)
	sim.buildings.append(chapel)
	var spot: Vector2 = sim.aftermath.recovery_spot(sim)
	check(spot.x >= 0.0 and spot.distance_to(sim.center(chapel)) < 3.0, "the fallen come round beside the Chapel")
	var warrior: Dictionary = {}
	for u: Dictionary in sim.units:
		if str(u["type"]) == "warrior":
			warrior = u
	warrior["hp"] = 0.0
	sim.raid_active = true
	sim._finish_raid(true)
	check(float(warrior["hp"]) > 0.0 and Vector2(float(warrior["x"]), float(warrior["y"])).distance_to(sim.center(chapel)) < 3.0, "after the raid the wounded warrior rests at the Chapel")


func test_saves() -> void:
	var sim = fresh()
	sim.aftermath.trampled[Vector2i(22, 4)] = true
	sim.aftermath.rubble.append({"x": 15.5, "y": 13.5, "stone": 7})
	var state: Variant = JSON.parse_string(JSON.stringify(sim.export_state()))
	var loaded = Sim.new()
	check(loaded.restore_state(state), "a save with raid marks loads")
	check(loaded.aftermath.trampled.has(Vector2i(22, 4)) and int(loaded.aftermath.rubble[0]["stone"]) == 7, "trampled fields and rubble survive a save")
	state["aftermath"]["rubble"][0]["stone"] = -3
	check(not Sim.new().restore_state(state), "negative rubble is refused")
	var old: Variant = JSON.parse_string(JSON.stringify(sim.export_state()))
	old.erase("aftermath")
	var older = Sim.new()
	check(older.restore_state(old) and older.aftermath.trampled.is_empty(), "older saves without raid marks still load")
