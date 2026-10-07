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


func test_research_accumulation() -> void:
	var sim = Sim.new()
	for second in 2000:
		sim.living.tick(sim, 1.0)
	check(sim.living.insight >= 190.0, "a living hall can accumulate the most expensive research cost")
	for id: String in sim.chronicle.nodes():
		check(float(sim.chronicle.node(id)["insight"]) <= sim.living.insight, "normal Insight storage can fund " + id)
	check(sim.living.valid(sim.living.state()), "naturally accumulated late-game Insight remains saveable")


func test_upgrade_objective() -> void:
	var sim = Sim.new()
	var pasture: Dictionary = sim._new_building("pasture", 1, 1, false)
	pasture["tier"] = 2
	sim.buildings.append(pasture)
	var objective: Dictionary = {"kind": "upgrade", "types": ["pasture"], "level": 2, "count": 1}
	check(sim._objective_target(objective) == 1.0, "one requested upgrade means one qualifying building, not two")
	check(sim._objective_value(objective) >= sim._objective_target(objective), "one tier-two pasture satisfies its upgrade objective")


func test_bonus_isolation() -> void:
	var sim = Sim.new()
	sim.chronicle.grant("aura:moon-orchard", "research:moon_orchards")
	check(is_equal_approx(sim.chronicle.bonus("growth"), 0.05), "Moon Orchards grants its food bonus using the authored aura key")
	check(sim.chronicle.bonus("heal") == 0.0 and sim.chronicle.bonus("repair") == 0.0, "food research does not change healing or repairs")
	sim.chronicle.grant("aura:triage", "research:field_medicine")
	check(sim.chronicle.bonus("heal") > 0.0, "Field Medicine grants recovery")
	check(is_equal_approx(sim.chronicle.bonus("growth"), 0.05), "medicine does not increase food production")
	sim.chronicle.grant("command:school-lessons", "research:schooling")
	check(is_equal_approx(sim.chronicle.bonus("school-lessons"), 0.15), "schooling discounts training only")
	check(sim.chronicle.bonus("unknown") == 0.0, "unknown bonus category grants nothing")
	var hall: Dictionary = sim._hall()
	hall["hp"] = float(hall["max_hp"]) - 150.0
	sim.resources["wood"] = 10
	sim.chronicle.grant("aura:repair-rationing", "research:tool_standardization")
	check(sim.repair(int(hall["id"])) and hall["hp"] == hall["max_hp"] and sim.resources["wood"] > 0, "repair research restores the same damage using less timber")


func test_optional_paid_once() -> void:
	var sim = Sim.new()
	var quest: Dictionary = {"id": "the-first-horn", "optional": [{"id": "foundation-once", "kind": "no_buildings_destroyed", "reward": {"insight": 7, "reputation": 3}}]}
	var record: Dictionary = {"optional": {}, "started_at": 0.0}
	sim._award_optionals(quest, record)
	check(sim.living.insight == 7.0 and sim.chronicle.reputation == 3, "optional Insight and reputation are paid exactly once")
	sim._award_optionals(quest, record)
	check(sim.living.insight == 7.0 and sim.chronicle.reputation == 3, "sealed optional challenge cannot pay again")


func test_advanced_resource_save() -> void:
	var sim = Sim.new()
	sim.resources["rations"] = 12.0
	sim.pending_rewards["feast-supplies"] = 3.0
	sim.gathered["rations"] = 20.0
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	var restored = Sim.new()
	check(restored.restore_state(state), "authored advanced resources survive JSON save validation")
	check(restored.resources.get("rations", 0) == 12.0 and restored.pending_rewards.get("feast-supplies", 0) == 3.0, "advanced stocks and deferred rewards survive reload")
	state["resources"]["not-a-resource"] = 1
	check(not restored.restore_state(state), "unknown resource ids are still rejected")
	check(restored.resources.get("rations", 0) == 12.0, "rejected restore leaves existing stocks untouched")


func test_legacy_campaign_migration() -> void:
	var sim = Sim.new()
	for quest: Dictionary in sim.quests:
		if int(quest["act"]) == 1:
			sim.completed_quests.append(str(quest["id"]))
	sim.living.discoveries.append("stoneworking")
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	state["version"] = 2
	state.erase("chronicle")
	var restored = Sim.new()
	check(restored.restore_state(state), "a legacy campaign with completed opening act loads")
	check(restored.chronicle.act == 2, "migration preserves the act derived from completed missions")
	check(restored.chronicle.is_unlocked("stone_quarry"), "migration reconstructs earned research unlocks")
	check(restored.completed_quests.size() == sim.completed_quests.size(), "migration never discards finished missions")
	state["version"] = 1
	state["living"] = {}
	check(not restored.restore_state(state), "malformed optional v1 Living data is rejected without crashing migration")


func test_panels() -> void:
	root.size = Vector2i(390, 844)
	var scene: PackedScene = load("res://scenes/game.tscn")
	var game = scene.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	var ruins: Node = game.find_child("HauntedOutskirts", false, false)
	check(ruins != null, "haunted landmarks frame the village wilderness")
	if ruins != null:
		for landmark: Node3D in ruins.get_children():
			check(absf(landmark.position.x) > 20.0 or absf(landmark.position.z) > 16.0, "ruins stay outside the playable building footprint")
	game._enter_village()
	var first: Dictionary = game.sim.units[0]
	var second: Dictionary = game.sim.units[1]
	var original_first: Vector2 = game.sim.position_of(first)
	var original_second: Vector2 = game.sim.position_of(second)
	first["x"] = 4.0
	first["y"] = 4.0
	second["x"] = 4.1
	second["y"] = 4.0
	game._update_actors(0.0)
	game._map_click(game.camera.unproject_position(game.world_position(game.sim.position_of(second), 0.8)))
	check(game.selected_unit == int(second["id"]), "clustered villagers select the closest rendered body rather than the first in the array")
	first["x"] = original_first.x
	first["y"] = original_first.y
	second["x"] = original_second.x
	second["y"] = original_second.y
	game._update_actors(0.0)
	game.selected_unit = -1
	game._map_click(game.camera.unproject_position(game.world_position(original_first, 0.8)) + Vector2(0, -25))
	check(game.selected_unit >= 0, "phone picking tolerates a near-body tap beyond the old 18-pixel radius")
	game.selected_building = int(game.sim.buildings[0]["id"])
	game._open_panel("building")
	check(game.sidebar.visible, "selected building exposes its inspector")
	game._open_pause()
	game._toggle_more()
	game._process(0.05)
	check(not game.paused and not game.sim.paused, "leaving Pause through More resumes the simulation")
	game.sim.xp = 100
	game.sim.living.insight = 19.0
	game.tech_branch = "Construction"
	game._open_panel("tech")
	var blocked_before: bool = _has_text(game.side_content, "Requires 20 Insight.")
	game.sim.living.insight = 20.0
	game._refresh_hud()
	check(blocked_before and not _has_text(game.side_content, "Requires 20 Insight."), "open Chart updates affordability without being reopened")
	game._begin_research("stoneworking")
	game.sim.living.remaining = 42.0
	game._refresh_hud()
	check(_has_text(game.side_content, "42s"), "open Chart updates its active countdown")
	game._open_panel("quests")
	check(_has_text(game.side_content, "1/2"), "opening Chronicle displays the current farm count")
	game.sim.buildings.append(game.sim._new_building("farm", 1, 1, false))
	game._refresh_hud()
	check(_has_text(game.side_content, "2/2"), "open Chronicle updates objective progress without being reopened")
	game._save_now()
	check(game.sim.notice.contains("disabled"), "save-isolated sessions explain why manual saving is disabled")
	game.save_blocked = true
	game.no_save = false
	game._save_now()
	check(game.sim.notice.contains("blocked"), "corrupt-save protection gives explicit manual-save feedback")
	game.no_save = true
	game.save_blocked = false
	check(game.has_method("_request_new_game") and game.has_method("_confirm_new_game"), "new-game reset has an explicit confirmation flow")
	if game.has_method("_request_new_game") and game.has_method("_confirm_new_game"):
		game.sim.xp = 580
		game._request_new_game()
		check(game.sim.xp == 580 and game.reset_dialog.visible, "requesting a new game does not reset progress before confirmation")
		game._cancel_new_game()
		check(game.sim.xp == 580, "cancelling a new game retains progress")
		game._request_new_game()
		game._confirm_new_game()
		check(game.sim.xp == 0 and game.sim.buildings.size() == 9 and game.sim.units.size() == 5, "confirmed new game resets to the real starting village")
		check(game.banner_left == 0.0 and not game.banner_panel.visible, "new game clears previous-village story banners")
		var fixture: String = "user://overhaul-reset-test.json"
		game.save_path = fixture
		game.no_save = false
		game.sim.xp = 580
		game._request_new_game()
		game._confirm_new_game()
		check(game.sim.xp == 0, "confirmed disk-backed reset succeeds")
		check(game.sim.save_game(fixture) and game.sim.save_game(fixture), "later saves still succeed after reset")
		var previous = Sim.new()
		check(previous.load_game(fixture + ".previous") and previous.xp == 580, "new-game recovery archive survives subsequent save rotation")
		game.no_save = true
		for suffix: String in ["", ".bak", ".tmp", ".previous", ".previous.bak", ".previous.tmp"]:
			if FileAccess.file_exists(fixture + suffix):
				DirAccess.remove_absolute(fixture + suffix)
	check(game.has_method("_toggle_mentor"), "optional mentor is available")
	if game.has_method("_toggle_mentor"):
		var before: bool = game.mentor_enabled
		game._toggle_mentor()
		check(game.mentor_enabled != before, "mentor guidance can be dismissed")
		game._toggle_mentor()
		check(game.mentor_enabled == before, "mentor guidance can be restored")
	check(_all_touch_targets(game.side_content), "sidebar commands meet the 44-pixel minimum")
	game._open_panel("people")
	check(game.hire_buttons.has("diver"), "People exposes campaign specialists, not just the original eight professions")
	var offer: Dictionary = game.sim.chronicle.board_offer()[0]
	game._accept_contract(str(offer["id"]))
	var goal: Dictionary = offer["template"]["objective"]
	if goal["kind"] == "gather":
		for building: Dictionary in game.sim.buildings:
			if str(game.sim.building_specs[building["type"]].get("production", "")) == goal["resource"]:
				building["reserve"] = float(goal["amount"])
				game.sim.collect(int(building["id"]))
				break
		game.sim._quest_tick()
		game._refresh_hud()
		check(_has_button(game.side_content, "Claim"), "open Board changes a completed real contract into a claim action")
	game.sim.chronicle.banners.clear()
	game.banner_left = 0.0
	game.sim.chronicle.queue_banner("Old Bell", "The lamps welcome you home.")
	game._open_panel("tech")
	game._refresh_hud()
	await process_frame
	await process_frame
	game._layout_ui()
	check(game.banner_label.size.x > 150.0, "story text receives horizontal space instead of wrapping one letter per line")
	check(game.sidebar.get_combined_minimum_size().x <= 390.0 - 32.0, "phone Chart fits the available horizontal budget")
	check(game.bottom.get_combined_minimum_size().x <= 390.0 - 32.0, "phone command bar fits without hiding buttons")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			var directory: String = argument.trim_prefix("--capture-dir=")
			if directory.is_absolute_path() and DirAccess.dir_exists_absolute(directory):
				await _capture_panels(game, directory)
	game.queue_free()
	await process_frame
	await process_frame


func _has_text(node: Node, fragment: String) -> bool:
	if node is Label and node.visible and fragment in node.text:
		return true
	for child in node.get_children():
		if _has_text(child, fragment):
			return true
	return false


func _all_touch_targets(node: Node) -> bool:
	if node is Button and node.custom_minimum_size.y < 44.0:
		return false
	for child in node.get_children():
		if not _all_touch_targets(child):
			return false
	return true


func _has_button(node: Node, caption: String) -> bool:
	if node is Button and node.text == caption and not node.disabled: return true
	for child in node.get_children():
		if _has_button(child, caption): return true
	return false


func _capture_panels(game, directory: String) -> void:
	game.paused = true
	for width: int in [390, 1280]:
		DisplayServer.window_set_size(Vector2i(width, 844 if width == 390 else 800))
		await process_frame
		game.selected_building = int(game.sim.buildings[0]["id"])
		game._open_panel("building")
		game._refresh_hud()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("overhaul-inspector-%d.png" % width)) == OK, "native inspector capture succeeds")
	DisplayServer.window_set_size(Vector2i(390, 844))
	for panel: String in ["tech", "needs", "build"]:
		game._open_panel(panel)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("overhaul-%s-390.png" % panel)) == OK, "native phone " + panel + " capture succeeds")
	game._close_panel()
	game.banner_panel.hide()
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join("overhaul-village-1280.png")) == OK, "native village overview capture succeeds")
	# Live raid capture: real warning-to-combat so projectiles, impact bursts,
	# alarm braziers and the warning UI render in the shot.
	game._test_raid()
	game.paused = false
	game.sim.paused = false
	for i in 80:
		game.sim.paused = false
		game.sim.tick(0.05)
	for e: Dictionary in game.sim.enemies:
		e["hp"] = 5000.0
		e["max_hp"] = 5000.0
	for i in 700:
		game.sim.paused = false
		game.sim.tick(0.05)
	check(game.sim.raid_active and not game.sim.enemies.is_empty(), "capture raid reaches live combat")
	await process_frame
	check(game.effect_nodes.size() + game.burst_pool.active_count() > 0, "live raid combat spawns pooled impact effects")
	for width: int in [390, 1280]:
		DisplayServer.window_set_size(Vector2i(width, 844 if width == 390 else 800))
		await process_frame
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("overhaul-raid-%d.png" % width)) == OK, "native raid capture succeeds")
	# Night raid finale: pin the sky to deep night deterministically (elapsed-based
	# cycle would otherwise pick the mood). Bursts fire through the real impact
	# pipeline at the live fight, staged for camera.
	game.cycle_offset = 0.0 - game.sim.elapsed
	game.day_blend = 0.0
	game.last_blend = 0.0
	game.night = true
	game._apply_lighting()
	if not game.sim.enemies.is_empty():
		var foe: Dictionary = game.sim.enemies[0]
		var at: Vector3 = game.world_position(game.sim.position_of(foe), 1.2)
		game._impact_burst(at)
		game._impact_burst(at, Color("9aa0ad"), 16, 1.6)
	for width: int in [390, 1280]:
		DisplayServer.window_set_size(Vector2i(width, 844 if width == 390 else 800))
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("overhaul-raid-night-%d.png" % width)) == OK, "native night raid capture succeeds")


func _run() -> void:
	var preset := ConfigFile.new()
	check(preset.load("res://export_presets.cfg") == OK, "web export configuration is readable")
	var filters: PackedStringArray = str(preset.get_value("preset.0", "include_filter", "")).split(",")
	for path: String in ["data/buildings.json", "data/world.json", "data/troops.json", "data/quests.json", "data/chronicle.json", "data/living_village.json", "data/workplaces.json", "data/music.json", "art/catalog.json"]:
		var included: bool = false
		for filter: String in filters:
			if path.match(filter.strip_edges()): included = true
		check(included, "export filters include runtime data " + path)
	test_research_accumulation()
	test_upgrade_objective()
	test_bonus_isolation()
	test_optional_paid_once()
	test_advanced_resource_save()
	test_legacy_campaign_migration()
	await test_panels()
	print("OVERHAUL_FOUNDATION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
