extends SceneTree

# The north and west reaches lie at negative tiles. Workplaces there must be worked, units there
# must face what they work on, zoned buildings must rise there, and older saves that wrote
# (-1, -1) for "no stand / no facing" must still read as "none". Also: someone already standing
# at their goal (workers sheltering by the Hall in a raid) is not walking on the spot.

const Sim = preload("res://scripts/game/village_sim.gd")
const Growth = preload("res://scripts/game/village_growth.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run()
	print("REACH_GROUND %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		printerr("FAIL ", text)


func farmer_of(sim) -> Dictionary:
	for u: Dictionary in sim.units:
		if u["type"] == "farmer":
			return u
	return {}


func _run() -> void:
	# A farm in the West Reach is worked.
	var sim = Sim.new()
	sim.expansions.append("west")
	sim._invalidate()
	var stores: Dictionary = sim.resources.duplicate()
	for key in sim.resources.keys():
		sim.resources[key] = 9999.0
	check(sim.build("farm", -6, 5), "a farm goes up in the West Reach")
	sim.resources = stores
	var farm: Dictionary = sim.buildings[-1]
	farm["remaining"] = 0.0
	var farmer: Dictionary = farmer_of(sim)
	check(sim.assign(int(farmer["id"]), int(farm["id"])), "a farmer is posted to it")
	var stand: Vector2 = sim.work_position(farmer, farm)
	check(Sim.has_point(stand) and stand.x < 0.0, "the farm has a work stand on west ground (%s)" % stand)
	var worked: int = 0
	var faced_west: bool = false
	for tick in 1200:
		sim.tick(0.05)
		if farmer["phase"] == "work":
			worked += 1
			faced_west = faced_west or sim.facing_target(farmer).x < 0.0
	check(worked > 0, "the farmer works the west farm")
	check(faced_west, "the farmer faces the crop they work, west of x = 0")

	# Older saves wrote (-1, -1) for "none"; on load that is "none", not a tile in the north-west.
	var state: Dictionary = sim.export_state()
	for u: Dictionary in state["units"]:
		for key: String in ["sx", "sy", "fx", "fy", "rx", "ry"]:
			u[key] = -1.0
	var loaded = Sim.new()
	check(loaded.restore_state(JSON.parse_string(JSON.stringify(state))), "an old-style save loads")
	for u: Dictionary in loaded.units:
		check(not Sim.has_point(loaded._held_stand(u)), "unit %d: an old unset stand stays unset" % int(u["id"]))
		check(loaded.facing_target(u) == loaded.position_of(u), "unit %d: an old unset facing stays unset" % int(u["id"]))

	# A zoned building can rise north-west of the village, where both coordinates are negative.
	var north = Sim.new()
	north.expansions.append("north")
	north._invalidate()
	var tiles: Dictionary = {}
	for y in range(-6, -2):
		for x in range(-6, -2):
			tiles[Vector2i(x, y)] = true
	var spot: Vector2i = Growth.new().find_spot(north, "cottage", tiles)
	check(spot != Growth.NO_SPOT and spot.x < 0 and spot.y < 0, "a cottage finds a spot in the north-west (%s)" % spot)

	# Workers sheltering by the Hall stand still once they are there.
	var shelter = Sim.new()
	var worker: Dictionary = farmer_of(shelter)
	check(shelter.start_raid(), "a raid is called")
	for tick in 400:
		shelter.tick(0.05)
		if not shelter.raid_active and not shelter.raid_warning:
			break
	var hall_goal: Vector2 = shelter._cached_edge_goal(worker, shelter._hall())
	if shelter.raid_active and shelter.position_of(worker).distance_to(hall_goal) < 0.05:
		check(worker["phase"] == "idle", "a sheltering worker at the Hall is not walking on the spot (%s)" % worker["phase"])
	else:
		# Walk them there directly, then one more tick at the goal.
		worker["x"] = hall_goal.x
		worker["y"] = hall_goal.y
		shelter.raid_warning = true
		shelter._unit_tick(worker, 0.05)
		check(worker["phase"] == "idle", "a sheltering worker at the Hall is not walking on the spot (%s)" % worker["phase"])
