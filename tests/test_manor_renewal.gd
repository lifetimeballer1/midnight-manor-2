extends SceneTree

# Manor Renewal (The Manor Endures, C2): opens after the Vale is united, pays Moon Seals that are kept
# in their own file and lift every later village's output, starts a fresh village, asks twice before
# it acts, and does not pay Act XI's reward twice.
const Sim = preload("res://scripts/game/village_sim.gd")
const Legacy = preload("res://scripts/game/manor_legacy.gd")
const SCRATCH: String = "user://test-legacy.json"
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
	test_rules()
	test_file()
	await test_renewal()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	print("MANOR_RENEWAL ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func test_rules() -> void:
	var legacy = Legacy.new()
	var sim = Sim.new()
	check(not legacy.reason(sim).is_empty(), "renewal waits for the Vale to be united")
	sim.vale_united = true
	check(legacy.reason(sim).is_empty(), "a united Vale opens renewal")
	var paid: int = legacy.seals_for(sim)
	check(paid >= 5, "a first renewal pays a handful of Moon Seals (%d)" % paid)
	check(legacy.record(sim) == paid and legacy.seals == paid and legacy.renewals == 1 and legacy.vale, "a renewal is recorded")
	var next = Sim.new()
	check(not legacy.reason(next).is_empty(), "a later renewal waits for the new Hall to grow")
	var hall: Dictionary = next._hall()
	hall["tier"] = Legacy.LATER_HALL_TIER
	check(legacy.reason(next).is_empty(), "a grown Hall opens the next renewal, no second Vale needed")
	var farm: Dictionary = {}
	for b: Dictionary in next.buildings:
		if str(b["type"]) == "farm":
			farm = b
	var plain: float = next.production_rate(farm)
	next.legacy_bonus = legacy.multiplier()
	check(absf(next.production_rate(farm) - plain * (1.0 + Legacy.SEAL_BONUS * paid)) < 0.0001, "Moon Seals lift output")


func test_file() -> void:
	var legacy = Legacy.new()
	legacy.seals = 12
	legacy.renewals = 2
	legacy.vale = true
	check(legacy.save_to(SCRATCH), "the legacy file writes")
	var again = Legacy.new()
	again.load_from(SCRATCH)
	check(again.seals == 12 and again.renewals == 2 and again.vale, "Moon Seals survive in their own file")
	var junk = Legacy.new()
	junk.from_dict({"seals": "lots", "vale": 3})
	check(junk.seals == 0 and not junk.vale, "a damaged legacy file is read as empty")


func test_renewal() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.sim.resources["gold"] = 5000.0
	game.sim.xp = 99999
	game._open_panel("renewal")
	game._renew_manor()
	check(game.legacy.renewals == 0, "renewal is closed before the Vale is united")
	game.sim.vale_united = true
	var old = game.sim
	game._renew_manor()
	check(game.sim == old and game.renew_armed, "the first tap only asks again")
	game._renew_manor()
	check(game.sim != old, "the second tap starts a fresh village")
	check(game.legacy.renewals == 1 and game.legacy.seals > 0, "Moon Seals are kept")
	check(float(game.sim.resources.get("gold", 0.0)) < 5000.0 and game.sim.xp < 99999, "the new village starts fresh")
	check(game.sim.legacy_bonus > 1.0, "the new village gets the Moon Seal bonus")
	# The realm stays sworn: the new village counts the Vale united without paying the act again.
	for site: Dictionary in game.realm.settlements:
		site["vassal"] = true
	var gold: float = float(game.sim.pending_rewards.get("gold", 0.0))
	game._vale_check()
	check(game.sim.vale_united and float(game.sim.pending_rewards.get("gold", 0.0)) == gold, "a renewed village keeps the Vale without a second reward")
	game.queue_free()
	await process_frame
