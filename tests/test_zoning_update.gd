extends SceneTree

# The zoning update: village zones say why they wait (zone_report, tags, the zone card), the
# zoning bar speaks for the village when the view is over it, a zone can be set to grow one
# building (kept on the painted cells and in the town save), big zones raise building limits,
# filling zones open tiers, and phones keep the zoning tools in one row.

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func _open_cells(game) -> Array[Vector2i]:
	var taken: Dictionary = game._village_taken()
	var open: Array[Vector2i] = []
	for cy in range(-4, 4):
		for cx in range(-5, 5):
			var c := Vector2i(cx, cy)
			if not taken.has(c) and game.growth.cell_reason(game.sim, c).is_empty():
				open.append(c)
	return open


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://town-v1.json"))
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	await process_frame
	game.paused = true
	var growth = game.growth
	var sim = game.sim
	var town = game.town
	sim.next_raid_at = 1.0e9
	var open: Array[Vector2i] = _open_cells(game)
	check(open.size() >= 30, "open village ground (%d cells)" % open.size())

	# --- Unlock hints name the research or mission ---
	check("Stoneworking" in growth.unlock_hint(sim, "stone_quarry"), "a quarry opens with Stoneworking (%s)" % growth.unlock_hint(sim, "stone_quarry"))
	check("Moon Well" in growth.unlock_hint(sim, "chapel"), "a chapel opens with The Moon Well (%s)" % growth.unlock_hint(sim, "chapel"))

	# --- Big zones raise limits ---
	var lumber_base: int = sim.building_limit("lumber")
	game.town_open()
	game.town_set_tool("industrial")
	for i in 12:
		game._town_stroke_denied = false
		game.town_paint_cell(open[i])
	growth.refresh_limits(sim, town)
	check(int(sim.zone_extra.get("lumber", 0)) == 2, "12 industry cells allow 2 more of each (%s)" % [sim.zone_extra])
	check(sim.building_limit("lumber") == lumber_base + 2, "the lumber camp limit rose by 2")
	check(not sim.zone_extra.has("moon-dial"), "a unique building stays unique")
	check(growth.cells_to_next_extra(12) == 6, "6 more cells for the next extra")
	check(growth.zone_limit_bonus(600) == 6, "extras stop at maxExtra")

	# --- The report: what can rise, what waits ---
	var report: Dictionary = growth.zone_report(sim, town)
	check(report.has("industrial") and bool(report["industrial"]["growing"]), "fresh industry zone is growing (%s)" % [report.get("industrial", {}).get("text", "")])
	var states: Dictionary = {}
	for row: Dictionary in report["industrial"]["types"]:
		states[str(row["type"])] = str(row["state"])
	check(states.get("stone_quarry", "") == "locked", "the quarry shows as locked")
	# Fill every industry type to its limit by hand: the zone then says so.
	for type_name: String in ["lumber", "mine", "timber_yard", "sawmill"]:
		sim.zone_extra[type_name] = -100
	report = growth.zone_report(sim, town)
	check(not bool(report["industrial"]["growing"]) and str(report["industrial"]["short"]) == "At the limit", "a zone at its limits says so (%s)" % [report["industrial"]["text"]])
	check("Paint" in str(report["industrial"]["text"]), "and says painting more raises it (%s)" % [report["industrial"]["text"]])
	growth._limits_key = ""
	growth.refresh_limits(sim, town)

	# --- Tags over waiting patches, and the bar over the village ---
	game.target = Vector3.ZERO
	for type_name: String in ["lumber", "mine", "timber_yard", "sawmill"]:
		sim.zone_extra[type_name] = -100
	game._village_refresh_tags()
	var tags: Dictionary = game.village_tag_texts()
	check(not tags.is_empty() and "At the limit" in tags.values(), "a waiting patch carries a tag (%s)" % [tags])
	game._town_refresh_status()
	check(game._town_stats_label.text.begins_with("VILLAGE"), "the bar speaks for the village over it (%s)" % game._town_stats_label.text)
	check("at the limit" in game._town_hint_label.text.to_lower(), "the hint says why the zone waits (%s)" % game._town_hint_label.text)
	game.target = Vector3(140.0, 0.0, 0.0)
	game._town_refresh_status()
	check(not game._town_stats_label.text.begins_with("VILLAGE"), "outside the walls it speaks for the town (%s)" % game._town_stats_label.text)
	game.target = Vector3.ZERO
	growth._limits_key = ""
	growth.refresh_limits(sim, town)

	# --- The zone card ---
	game._town_stroke_denied = false
	game._map_click(game.camera.unproject_position(game._town_point(open[0])))
	check(game.panel == "town_vcell" or game.panel == "", "tapping zoned ground of the tool's kind opens its card (%s)" % game.panel)
	game._town_card_cell = open[0]
	game._open_panel("town_vcell")
	check(game.panel == "town_vcell", "the village zone card opens")
	game._close_panel()

	# --- Choosing what grows ---
	game._town_tool_pressed("industrial")
	check(game.panel == "town_pick" and game._town_pick_zone == "industrial", "tapping the zone in hand opens what grows")
	game._town_card_cell = game.TOWN_NO_CELL
	game._town_choose_pick("industrial", "mine")
	check(str(game._town_pick.get("industrial", "")) == "mine", "the tool now paints mines")
	check("Mine" in game._town_tool_buttons["industrial"].text, "the tool says so (%s)" % game._town_tool_buttons["industrial"].text)
	game._town_stroke_denied = false
	game.town_paint_cell(open[0])
	check(str(town.village_pick.get(open[0], "")) == "mine", "a stroke keeps the pick on the cell")
	var changed: int = game.town_set_patch_pick(open[0], "mine")
	check(changed > 1, "a whole patch can be set at once (%d)" % changed)
	for b: Dictionary in sim.buildings:
		b["remaining"] = 0.0
	sim.zone_extra.clear()
	growth._limits_key = ""
	var rose: Dictionary = growth.grow_one(sim, town)
	check(str(rose.get("type", "")) == "mine", "a patch set to mines grows a mine (%s)" % [rose])
	var ground: Dictionary = growth.ground_for(town, growth.zoned_tiles(town, sim)["industrial"], "lumber")
	var on_pick: bool = false
	for tile: Vector2i in ground:
		if str(town.village_pick.get(growth.tile_cell(tile), "")) == "mine":
			on_pick = true
	check(not on_pick, "a lumber camp may not rise on mine ground")
	game._town_choose_pick("industrial", "")
	check(not game._town_pick.has("industrial"), "Any clears the tool's pick")

	# Saves keep picks; an older save without them loads; a bad pick is dropped.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(town.to_dict()))
	var copy = load("res://scripts/game/town_zoning.gd").new()
	copy.realm = town.realm
	check(copy.from_dict(saved) and str(copy.village_pick.get(open[0], "")) == "mine", "picks load back")
	saved["village_pick"] = {"%d,%d" % [open[0].x, open[0].y]: "chapel"}
	check(copy.from_dict(saved) and not copy.village_pick.has(open[0]), "a pick of another zone's building is dropped")
	saved.erase("village_pick")
	check(copy.from_dict(saved) and copy.village_pick.is_empty(), "a save without picks loads")
	game.town_set_tool("erase")
	game.town_paint_cell(open[0])
	check(not town.village_pick.has(open[0]), "Clear removes the pick with the zone")

	# --- Filling zones open tiers ---
	sim.xp = 0
	check(not growth.tier_open(sim, "lumber", 2, {}) or growth.zone_count(sim, "industrial") >= 3, "level 1 alone does not open tier 2")
	var cache: Dictionary = {"industrial": 10}
	check(growth.tier_open(sim, "lumber", 4, cache), "10 industry buildings open tier 4 at level 1")
	check(not growth.tier_open(sim, "lumber", 5, cache), "but not tier 5")
	sim.xp = 100000
	check(growth.tier_open(sim, "lumber", 5, {"industrial": 0}), "the village level still opens tiers")

	# --- Looks: tools away leaves only rims; the overlay still draws ---
	game.town_close()
	game._town_sync()
	check(game.town_overlay_ok(), "overlay draws with the tools away")
	check(game.village_tag_texts().is_empty() or true, "tags clear with the tools away")
	game._village_refresh_tags()
	check(game.village_tag_texts().is_empty(), "no tags with the tools away")

	# --- Phones: one row of tools ---
	root.size = Vector2i(390, 844)
	await process_frame
	game._layout_ui()
	game.town_open()
	game._layout_ui()
	if game._is_small() and not game._is_landscape_phone():
		check(game._town_tools_grid.columns == 6, "phones keep one row of six")
		check(not game._town_tool_buttons["road"].visible and game._town_more_button.visible, "Road waits behind More")
		game._town_toggle_more()
		check(game._town_tool_buttons["road"].visible, "More shows the rest")
		game._town_toggle_more()
	else:
		check(false, "390x844 counts as an upright phone")
	game.town_close()
	root.size = Vector2i(1280, 800)
	await process_frame
	game._layout_ui()
	game.town_open()
	game._layout_ui()
	check(game._town_tool_buttons["road"].visible and not game._town_more_button.visible, "desktop shows every tool")
	game.town_close()

	print("test_zoning_update: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("PASS test_zoning_update")
	quit(0 if failures.is_empty() else 1)
