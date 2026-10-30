extends SceneTree

# Unite the Vale (The Manor Endures, Act XI): a neighbour warmed by gifts can be asked to swear,
# each sworn rival lifts all output, the last one to swear ends Act XI with a reward, and the act
# is saved. War still swears a beaten settlement, as before.
const Sim = preload("res://scripts/game/village_sim.gd")
const RealmMap = preload("res://scripts/game/realm_map.gd")
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
	test_swearing()
	test_bonus_and_save()
	await test_finale()
	print("UNITE_VALE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func test_swearing() -> void:
	var realm = RealmMap.new()
	realm.generate(7)
	check(realm.settlements.size() == 5, "the Vale holds five rivals")
	var site: Dictionary = realm.settlements[0]
	var id: String = str(site["id"])
	site["relation"] = 60.0
	check(not realm.swear_reason(id).is_empty() and not realm.swear(id), "a lukewarm neighbour will not swear")
	while float(site["relation"]) < RealmMap.SWEAR_AT:
		realm.send_gift(id)
	check(realm.swear_reason(id).is_empty(), "gifts warm a neighbour enough to swear")
	check(realm.swear(id) and bool(site["vassal"]), "asking a warm neighbour swears it")
	check(realm.sworn_count() == 1, "the sworn count goes up")
	var sworn_event: bool = false
	for event: Dictionary in realm.take_events():
		if str(event["kind"]) == "sworn":
			sworn_event = true
	check(sworn_event, "swearing tells the realm layer")
	check(not realm.swear_reason(id).is_empty(), "a sworn neighbour cannot swear twice")
	var cost: Dictionary = realm.swear_cost(realm.settlements[1])
	check(int(cost.get("gold", 0)) > 0 and int(cost.get("food", 0)) > 0, "swearing asks for an oath feast")


func test_bonus_and_save() -> void:
	var sim = Sim.new()
	var farm: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if str(b["type"]) == "farm":
			farm = b
	var plain: float = sim.production_rate(farm)
	sim.vale_sworn = 3
	check(absf(sim.production_rate(farm) - plain * (1.0 + 3.0 * Sim.VALE_BONUS)) < 0.0001, "three sworn rivals lift output by 15%")
	sim.vale_united = true
	var copy = Sim.new()
	check(copy.restore_state(JSON.parse_string(JSON.stringify(sim.export_state()))) and copy.vale_united, "a united Vale survives a reload")
	var old: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	old.erase("vale_united")
	var older = Sim.new()
	check(older.restore_state(old) and not older.vale_united, "a save from before Act XI loads with the Vale not yet united")


func test_finale() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	check(game.realm != null, "the game has a realm")
	game._open_panel("vale")
	await process_frame
	var joined: String = ""
	for node: Node in game.sidebar.find_children("*", "", true, false):
		if node is Label or node is Button:
			joined += str(node.text) + " | "
	check(joined.contains("UNITE THE VALE") and joined.contains("Sworn: 0 of 5"), "the Vale card shows the act and the count")
	game._close_panel()
	for r: String in ["gold", "wood", "food"]:
		game.sim.resources[r] = 0.0
	for site: Dictionary in game.realm.settlements:
		site["relation"] = 95.0
		game.sim.resources["gold"] = 100000.0
		game.sim.resources["food"] = 100000.0
		game._realm_swear(str(site["id"]))
	for i in 3:
		await process_frame
	check(game.realm.sworn_count() == 5, "all five rivals swear")
	check(game.sim.vale_sworn == 5, "the sim knows how many rivals are sworn")
	check(game.sim.vale_united, "the last oath unites the Vale")
	check(float(game.sim.pending_rewards.get("gold", 0.0)) > 0.0 or float(game.sim.resources.get("wood", 0.0)) > 0.0, "uniting the Vale pays a reward")
	game.queue_free()
	await process_frame
