extends SceneTree

# Autosave on a big village: many worn lanes, and villagers holding work stands in the West and North
# Reaches (negative tile coordinates). Both used to fail the save's own check, so every autosave
# after that point failed. Also: repeated saves stay cheap and correct, and old saves still load.
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
	test_many_lanes()
	test_reach_stands()
	test_repeat_and_reload()
	print("AUTOSAVE_SCALE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func fresh() -> Variant:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	return sim


func scratch(tag: String) -> String:
	return "user://autosave-scale-%s-%d.json" % [tag, Time.get_ticks_usec()]


func clean(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


func test_many_lanes() -> void:
	var sim = fresh()
	for id: String in ["north", "east", "south", "west"]:
		sim.expansions.append(id)
	var laid: int = 0
	for y in range(-10, 26):
		for x in range(-10, 30):
			if laid >= 700 or not sim.in_world(Vector2i(x, y)) or (x + y) % 2 != 0:
				continue
			sim.living.cells[sim.living.key(Vector2i(x, y))] = {"wear": 0.4, "last": sim.elapsed, "stone": false}
			laid += 1
	check(sim.living.cells.size() > 320, "fixture holds more lanes than the old limit")
	var path := scratch("lanes")
	check(sim.save_game(path), "a village with %d worn lane tiles saves" % sim.living.cells.size())
	var loaded = fresh()
	check(loaded.load_game(path) and loaded.living.cells.size() == sim.living.cells.size(), "and loads back with every lane")
	clean(path)


func test_reach_stands() -> void:
	var sim = fresh()
	sim.expansions.append("west")
	sim.expansions.append("north")
	var u: Dictionary = sim.units[0]
	u["sx"] = -3.5     # a stand in the West Reach
	u["sy"] = 6.5
	var v: Dictionary = sim.units[1] if sim.units.size() > 1 else u
	v["sx"] = 4.5      # a stand in the North Reach
	v["sy"] = -2.5
	var path := scratch("stands")
	check(sim.save_game(path), "villagers holding stands in the reaches save")
	var loaded = fresh()
	check(loaded.load_game(path), "and load")
	var half: Dictionary = sim.units[0]
	half["sx"] = -1.0
	half["sy"] = 6.5
	check(not sim._validate_state(JSON.parse_string(JSON.stringify(sim.export_state()))), "a half-set stand is still refused")
	clean(path)


func test_repeat_and_reload() -> void:
	var sim = fresh()
	var path := scratch("repeat")
	check(sim.save_game(path), "first save")
	sim.resources["wood"] = float(sim.resources["wood"]) + 7.0
	check(sim.save_game(path) and sim.save_game(path), "repeated autosaves succeed")
	var loaded = fresh()
	check(loaded.load_game(path) and is_equal_approx(float(loaded.resources["wood"]), float(sim.resources["wood"])), "the latest save is what loads")
	check(FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"), "the backup rotates and no staging file is left")
	# A save changed on disk by something else is checked again before it is replaced.
	var other := FileAccess.open(path, FileAccess.WRITE)
	other.store_string('{"version":9}')
	other.close()
	check(not sim.save_game(path) and FileAccess.get_file_as_string(path) == '{"version":9}', "an unreadable save written by something else is never overwritten")
	clean(path)
