extends SceneTree

# Farm estates: a connected patch of farm zone is one farm, with one crop house and fields over the
# rest; output, storage and crew grow with its land. Older small farms on one patch fold into it.
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
	test_one_farm_per_patch()
	test_fold_and_switch()
	test_new_land_shares_out()
	print("FARM_ESTATES ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func setup() -> Array:
	var sim = Sim.new()
	sim.next_raid_at = 1.0e9
	var zones: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/zones.json"))
	var growth = Growth.new()
	growth.setup(zones["village"], Vector2i(10, 8), 2)
	return [sim, growth, FakeTown.new()]


# A w x h block of village cells with nothing standing on it, or [] when none is free.
func free_block(sim, growth, w: int, h: int, town = null) -> Array[Vector2i]:
	var taken: Dictionary = {}
	for b: Dictionary in sim.buildings:
		for dy in range(-1, int(b["size"]) + 1):
			for dx in range(-1, int(b["size"]) + 1):
				taken[Vector2i(int(b["x"]) + dx, int(b["y"]) + dy)] = true
	for cy in range(3, -5, -1):
		for cx in range(4, -6, -1):
			var block: Array[Vector2i] = []
			var ok: bool = true
			for y in h:
				for x in w:
					var c := Vector2i(cx - x, cy - y)
					if not growth.cell_reason(sim, c).is_empty():
						ok = false
					if town != null:
						for step: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							if town.village.has(c + step):
								ok = false
					for tile: Vector2i in growth.cell_tiles(c):
						if taken.has(tile):
							ok = false
					block.append(c)
			if ok:
				return block
	return []


func zone(town, cells: Array[Vector2i]) -> void:
	for c: Vector2i in cells:
		town.village[c] = "farming"


func crops_on(sim, growth) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in sim.buildings:
		if growth.is_crop(str(b["type"])):
			out.append(b)
	return out


func test_one_farm_per_patch() -> void:
	var parts: Array = setup()
	var sim = parts[0]
	var growth = parts[1]
	var town = parts[2]
	var block: Array[Vector2i] = free_block(sim, growth, 3, 2)
	check(block.size() == 6, "found open ground for a six-cell farm zone")
	if block.size() != 6:
		return
	zone(town, block)
	var before: int = crops_on(sim, growth).size()
	var rose: Dictionary = growth.grow_one(sim, town)
	check(not rose.is_empty() and growth.is_crop(str(rose.get("type", ""))), "a crop house rises on the new farm zone (%s)" % [rose])
	check(str(rose.get("type", "")) == "farm", "a new estate starts as a wheat farm")
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
	growth.refresh_estates(sim, town)
	for i in 6:
		var more: Dictionary = growth.grow_one(sim, town)
		if not more.is_empty():
			check(not growth.is_crop(str(more["type"])), "no second crop house rises on the same patch (%s)" % str(more["type"]))
		for b: Dictionary in sim.buildings:
			b["remaining"] = 0.0
	check(crops_on(sim, growth).size() == before + 1, "the whole patch keeps one crop house")
	growth.refresh_estates(sim, town)
	var house: Dictionary = sim.get_building(int(rose["id"]))
	var estate: Dictionary = sim.estates.get(int(house["id"]), {})
	var land: int = int(estate.get("tiles", 0))
	check(land >= 16 and land <= 24, "the estate holds the patch's farmable tiles, lanes aside (%d of 24)" % land)
	check((estate.get("fields", []) as Array).size() >= 10, "most of the patch is fields")
	check(str(estate.get("name", "")) == "Farmstead", "an estate of 12 tiles or more is a Farmstead")
	check(sim.crew_cap(house) == ceili(land / 4.0), "it takes one farmhand per four tiles")
	check(is_equal_approx(sim.estate_scale(house), land / 4.0), "it works like a small farm for every four tiles")
	# Output and storage grow with the land.
	var lone: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if b["type"] == "farm" and int(b["id"]) != int(house["id"]):
			lone = b
	for u: Dictionary in sim.units:
		u["hold"] = true
	house["reserve"] = 0.0
	if not lone.is_empty():
		lone["reserve"] = 0.0
	sim.tick(1.0)
	if not lone.is_empty():
		check(float(house["reserve"]) > float(lone["reserve"]) * 4.0, "the estate fills far faster than a lone farm")
	check(sim.reserve_cap(house) > 2000.0, "the estate's barn holds more")
	# Farmhands work the rows.
	for u: Dictionary in sim.units:
		u["hold"] = false
	sim._add_unit("farmer")
	var hand: Dictionary = sim.units.back()
	check(sim.assign(int(hand["id"]), int(house["id"])), "a farmhand joins the estate")
	var stand: Vector2 = sim.work_position(hand, house)
	var on_field: bool = false
	for tile: Vector2i in estate["fields"]:
		if Vector2i(floori(stand.x), floori(stand.y)) == tile:
			on_field = true
	check(on_field, "the farmhand works out on the fields")
	var cap: int = sim.crew_cap(house)
	for i in cap:
		sim._add_unit("farmer")
		sim.assign(int(sim.units.back()["id"]), int(house["id"]))
	check(sim.crew_of(house) == cap, "a full crew of %d fits" % cap)
	sim._add_unit("farmer")
	check(not sim.assign(int(sim.units.back()["id"]), int(house["id"])), "one more is turned away")
	# A second patch elsewhere is its own estate.
	var other: Array[Vector2i] = free_block(sim, growth, 1, 1, town)
	if not other.is_empty():
		zone(town, other)
		var second: Dictionary = growth.grow_one(sim, town)
		var grown: bool = false
		for i in 4:
			if not second.is_empty() and growth.is_crop(str(second["type"])):
				grown = true
				break
			for b: Dictionary in sim.buildings:
				b["remaining"] = 0.0
			second = growth.grow_one(sim, town)
		check(grown, "a separate farm zone gets its own crop house")


func test_fold_and_switch() -> void:
	var parts: Array = setup()
	var sim = parts[0]
	var growth = parts[1]
	var town = parts[2]
	var block: Array[Vector2i] = free_block(sim, growth, 2, 1)
	check(block.size() == 2, "found open ground for a two-cell farm zone")
	if block.size() != 2:
		return
	zone(town, block)
	# An older village grew a small farm on each cell.
	var first_tile: Vector2i = growth.cell_tiles(block[0])[0]
	var second_tile: Vector2i = growth.cell_tiles(block[1])[0]
	var a: Dictionary = sim._new_building("farm", first_tile.x, first_tile.y, false)
	var b: Dictionary = sim._new_building("pond", second_tile.x, second_tile.y, false)
	sim.buildings.append(a)
	sim.buildings.append(b)
	b["reserve"] = 40.0
	sim._add_unit("fisherman")
	var fisher: Dictionary = sim.units.back()
	fisher["workplace"] = int(b["id"])
	var events: Array[Dictionary] = growth.refresh_estates(sim, town)
	check(events.size() == 1 and sim.get_building(int(b["id"])).is_empty(), "the second small farm folds into the first")
	check(float(a["reserve"]) >= 40.0, "its stores move to the estate")
	check(int(fisher["workplace"]) == int(a["id"]) and str(fisher["type"]) == "farmer", "its crew retrain and join the estate")
	check(sim.estates.has(int(a["id"])) and int(sim.estates[int(a["id"])]["tiles"]) == 8, "the two cells are one eight-tile estate")
	check(str(sim.estates[int(a["id"])]["name"]) == "Smallholding", "a small estate is a Smallholding")
	# Switching the crop.
	check(not growth.crop_reason(sim, int(a["id"]), "farm").is_empty(), "an estate cannot switch to the crop it grows")
	var reason: String = growth.crop_reason(sim, int(a["id"]), "pasture")
	if reason.is_empty():
		check(growth.switch_crop(sim, int(a["id"]), "pasture"), "the estate turns to pasture")
		check(str(a["type"]) == "pasture" and float(a["remaining"]) > 0.0 and sim.materials.has_bill(a), "the farmhouse is rebuilt as a pasture from materials")
		check(str(fisher["type"]) == "shepherd", "its farmhands become shepherds")
	else:
		check(reason.length() > 0, "a locked crop says why (%s)" % reason)
	var lone = Sim.new()
	var plain: Dictionary = {}
	for x: Dictionary in lone.buildings:
		if x["type"] == "farm":
			plain = x
	check(not growth.crop_reason(lone, int(plain["id"]), "pasture").is_empty(), "a lone farm off the zone is not an estate")


# A farm zone over a whole bought reach is shared between several farms, none bigger than a Grange's
# limit, so one farmhouse never works hundreds of tiles.
func test_new_land_shares_out() -> void:
	var parts: Array = setup()
	var sim = parts[0]
	var growth = parts[1]
	var town = parts[2]
	for r: String in ["wood", "stone", "gold"]:
		sim.resources[r] = 99999.0
	check(sim.expand("south"), "the south reach is bought")
	var rect: Rect2i = sim.EXPANSION_PLOTS["south"]["rect"]
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			var c: Vector2i = growth.tile_cell(Vector2i(x, y))
			if growth.cell_reason(sim, c).is_empty():
				town.village[c] = "farming"
	for i in 30:
		for b: Dictionary in sim.buildings:
			b["remaining"] = 0.0
			sim.materials.close_site(b)
		growth.grow_one(sim, town)
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
		sim.materials.close_site(b)
	growth.refresh_estates(sim, town)
	var limit: int = growth.estate_max_cells() * 4
	var on_reach: int = 0
	var biggest: int = 0
	for id: int in sim.estates:
		var house: Dictionary = sim.get_building(id)
		if rect.has_point(Vector2i(int(house["x"]), int(house["y"]))):
			on_reach += 1
		biggest = maxi(biggest, int(sim.estates[id]["tiles"]))
	check(on_reach >= 4, "a reach-wide farm zone holds several farms (%d)" % on_reach)
	check(biggest <= limit, "no estate is bigger than %d tiles (biggest %d)" % [limit, biggest])
	for id: int in sim.estates:
		check(sim.estate_scale(sim.get_building(id)) <= limit / 4.0, "an estate works at most like %d small farms" % (limit / 4))
		break
	# Settled estates stay as they are on the next look.
	var before: int = sim.estates.size()
	var folds: Array[Dictionary] = growth.refresh_estates(sim, town)
	check(folds.is_empty() and sim.estates.size() == before, "a settled set of estates stays as it is")
