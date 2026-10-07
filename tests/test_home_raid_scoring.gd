extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
const Studio = preload("res://addons/manor_studio/balance_model.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func building(sim, type_name: String) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if b["type"] == type_name: return b
	return {}


func damage(sim, b: Dictionary, amount: float) -> void:
	var before: float = b["hp"]
	b["hp"] = maxf(0.0, before - amount)
	sim.home_raid.hit(sim, b, before - float(b["hp"]))


func _run() -> void:
	var studio = Studio.new()
	check(studio.load_file(), "raid balance audit uses Manor Studio's real building data")
	check(studio.data["farm"]["production"] == "food" and studio.data["hall"]["storage"].has("gold"), "authored resource sites inform raid theft")
	var sim = Sim.new()
	check(sim.get("home_raid") != null, "home raids expose persisted scoring and loot")
	if sim.get("home_raid") != null:
		test_stars(sim)
		test_loot()
		test_resume()
		test_combat()
		await test_report()
	print("HOME_RAID_SCORING ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func test_stars(sim) -> void:
	sim._spawn_raid()
	check(sim.home_raid.active["targets"].size() == 6, "walls do not inflate the destruction denominator")
	damage(sim, building(sim, "wall"), 100000.0)
	check(sim.home_raid.stars() == 0, "destroying a wall earns no destruction star")
	damage(sim, building(sim, "hall"), 100000.0)
	check(sim.home_raid.stars() == 1, "destroying the Hall earns one star")
	damage(sim, building(sim, "tower"), 100000.0)
	damage(sim, building(sim, "barracks"), 100000.0)
	check(sim.home_raid.stars() == 2 and sim.home_raid.summary()["destruction"] == 50, "Hall plus half of scoring buildings earns two stars")
	sim.repair(int(building(sim, "hall")["id"]))
	check(sim.home_raid.stars() == 2, "repairs cannot erase attackers' earned stars")
	sim.buildings.append(sim._new_building("farm", 1, 12, false))
	check(sim.home_raid.summary()["destruction"] == 50, "new buildings cannot dilute the starting destruction denominator")
	for b: Dictionary in sim.buildings: damage(sim, b, 100000.0)
	check(sim.home_raid.stars() == 3, "all starting scoring buildings destroyed earns three stars")
	sim._finish_raid(false)
	check(sim.home_raid.last["stars"] == 3 and sim.home_raid.active.is_empty(), "raid completion preserves its final report")
	var resources: Dictionary = sim.resources.duplicate(true)
	sim._finish_raid(false)
	check(sim.resources == resources, "finished raids cannot settle twice")


func test_loot() -> void:
	var sim = Sim.new()
	sim._spawn_raid()
	var farm: Dictionary = building(sim, "farm")
	damage(sim, farm, float(farm["hp"]) * 0.5)
	check(sim.resources["food"] == 171.0 and sim.resources["gold"] == 210.0, "half damage to the farm steals only its allocated Food share")
	sim.repair(int(farm["id"]))
	for index in 4:
		damage(sim, farm, float(farm["max_hp"]))
		sim.repair(int(farm["id"]))
	check(sim.home_raid.active["loot"]["food"] == 18, "repeated repair and damage cannot multiply one site's loot allowance")
	for b: Dictionary in sim.buildings: damage(sim, b, 100000.0)
	check(sim.home_raid.active["loot"] == {"wood": 64, "food": 36, "gold": 42}, "all sites together steal at most twenty percent of starting stocks")
	check(sim.resources["food"] == 144.0 and sim.resources["gold"] == 168.0, "stolen resources actually leave central stocks")
	var scarce = Sim.new()
	scarce._spawn_raid()
	scarce.resources["food"] = 1.0
	damage(scarce, building(scarce, "farm"), 100000.0)
	check(scarce.resources["food"] == 0.0 and scarce.home_raid.active["loot"]["food"] == 1, "theft never makes a resource balance negative")


func test_resume() -> void:
	var sim = Sim.new()
	sim._spawn_raid()
	damage(sim, building(sim, "farm"), 80.0)
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	var restored = Sim.new()
	check(restored.restore_state(state), "partial raid scoring and loot survive JSON saves")
	check(restored.home_raid.state() == state["home_raid"], "resume preserves the exact theft budget and paid amounts")
	damage(restored, building(restored, "farm"), 100000.0)
	check(restored.home_raid.active["loot"]["food"] == 18, "resume cannot reset a resource site's paid allowance")
	var bad: Dictionary = state.duplicate(true)
	bad["home_raid"]["active"]["loot"]["food"] = 99999
	check(not restored.restore_state(bad), "corrupt over-budget loot is rejected before replacing a village")
	bad = state.duplicate(true)
	bad["home_raid"]["active"] = {}
	check(not restored.restore_state(bad), "tracked active raids cannot discard their paid loot history")
	state.erase("home_raid")
	check(restored.restore_state(state), "existing v4 saves without raid scoring remain loadable")


func test_combat() -> void:
	var sim = Sim.new()
	sim._spawn_raid()
	damage(sim, building(sim, "hall"), 100000.0)
	sim._raid_tick(0.05)
	check(sim.raid_active, "Hall destruction does not immediately end a one-star raid")
	var clean = Sim.new()
	clean._spawn_raid()
	clean.enemies.clear()
	clean._raid_tick(0.05)
	check(clean.home_raid.last["stars"] == 0 and clean.raid_stats["defended"] == 1, "a zero-star defense earns victory and campaign credit")
	var timeout = Sim.new()
	timeout._spawn_raid()
	timeout.home_raid.active["seconds"] = 300.0
	timeout._raid_tick(0.05)
	check(not timeout.raid_active, "a safety timeout prevents endless raids")
	var looter = Sim.new()
	looter._spawn_raid()
	looter.enemies[1]["x"] = 8.2
	looter.enemies[1]["y"] = 9.2
	looter._raid_tick(0.05)
	check(building(looter, "farm")["hp"] < 160.0 and looter.resources["food"] < 180.0, "resource raiders attack a nearby farm and steal real Food rather than only targeting the Hall")


func test_report() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)
	game.sim._spawn_raid()
	damage(game.sim, building(game.sim, "hall"), 100000.0)
	game._refresh_hud()
	check(game.raid_hud.text.contains("1/3") and game.raid_hud.text.contains("16%"), "phone HUD shows live attacker stars and destruction")
	damage(game.sim, building(game.sim, "farm"), 100000.0)
	damage(game.sim, building(game.sim, "tower"), 100000.0)
	game.sim._finish_raid(false)
	game._refresh_hud()
	check(game.panel == "raid_report", "raid completion opens the defense report once")
	var details: Variant = game.get("raid_report_details")
	check(details is Label and details.text.contains("Wood") and details.text.contains("Gold"), "report lists actual stolen resources")
	game._close_panel()
	game._refresh_hud()
	check(game.panel.is_empty(), "dismissing the report prevents repeated automatic popups")
	game._open_panel("raid_report")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=") and DisplayServer.get_name() != "headless":
			var directory: String = argument.trim_prefix("--capture-dir=")
			if directory.is_absolute_path() and DirAccess.dir_exists_absolute(directory):
				for width: int in [390, 1280]:
					DisplayServer.window_set_size(Vector2i(width, 844 if width == 390 else 800))
					await process_frame
					await process_frame
					await RenderingServer.frame_post_draw
					check(root.get_texture().get_image().save_png(directory.path_join("raid-report-%d.png" % width)) == OK, "native defense report capture succeeds")
	game.queue_free()
	await process_frame
	await process_frame
