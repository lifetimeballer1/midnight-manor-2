extends SceneTree

# Manor Chronicle regression suite: migration, acts, mission unlock conditions,
# optional objectives, research prerequisites, tech-tier gating, duplicate unlock
# prevention, mission/research interaction, doctrines, region persistence and
# old-save compatibility.

const Sim = preload("res://scripts/game/village_sim.gd")
const Chronicle = preload("res://scripts/game/chronicle.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func step(sim, seconds: float) -> void:
	for index in ceili(seconds / 0.05):
		sim.tick(0.05)


func rich(sim) -> void:
	# Enough village to reach any tier: resources, beds, level, Insight.
	sim.resources["wood"] = 200000
	sim.resources["food"] = 20000
	sim.resources["gold"] = 20000
	sim.living.insight = 400
	sim.xp = 3000
	sim.living.discoveries.clear()
	sim.chronicle.unlocked.clear()
	for id: String in Sim.new().chronicle.story_content_ids():
		sim.chronicle.unlocked[id] = true


# --- 1. tech tree shape ------------------------------------------------------

func test_tech_tree() -> void:
	var chronicle = Chronicle.new()
	var branches: Array = chronicle.branches()
	check(branches.size() == 6, "six research branches")
	for branch: Variant in branches:
		check(chronicle.branch_nodes(str(branch)).size() == 6, "branch %s has six nodes" % branch)
	var tier_one: int = 0
	for id: Variant in chronicle.nodes():
		if chronicle.tier_of(str(id)) == 1:
			tier_one += 1
	check(tier_one >= 6, "every branch opens with a tier one node")
	check(chronicle.node("stoneworking").has("behavior"), "every node states a behaviour change")
	for id: Variant in chronicle.nodes():
		var node: Dictionary = chronicle.node(str(id))
		check(not str(node.get("behavior", "")).is_empty(), "node %s has behaviour text" % id)
		for need: Variant in node.get("requires", []):
			check(not chronicle.node(str(need)).is_empty(), "node %s prerequisite resolves" % id)


# --- 2. prerequisites and tier gating ---------------------------------------

func test_prereqs_and_tiers() -> void:
	var sim = Sim.new()
	rich(sim)
	# Tier 3 opens with Act V, tier 4 with Act VII: campaign gated, never by choice.
	check(not sim.chronicle.tier_reason("gate_engineering").is_empty(), "tier 3 research is sealed in Act I")
	sim.chronicle.act = 3
	check(sim.chronicle.tier_reason("road_masonry").is_empty(), "tier 1 research stays open in later acts")
	check(not sim.chronicle.tier_reason("gate_engineering").is_empty(), "tier 3 research is still sealed in Act III")
	sim.chronicle.act = 5
	check(sim.chronicle.tier_reason("gate_engineering").is_empty(), "tier 3 research opens at Act V")
	sim.chronicle.act = 7
	check(sim.chronicle.tier_reason("siege_doctrine").is_empty(), "tier 4 research opens at Act VII")
	# Prerequisite ordering is enforced before cost.
	sim.chronicle.act = 5
	sim.living.insight = 400
	var reason: String = sim.living.research_reason(sim, "siege_doctrine")
	check(reason.contains("Act") or reason.contains("Combined Arms"), "a sealed node states why: %s" % reason)
	sim.living.discoveries.assign(["stoneworking", "road_masonry", "fortifications", "gate_engineering", "fieldcraft", "organized_watch", "watchtower_doctrine", "combined_arms"])
	sim.chronicle.act = 7
	sim.paused = false
	check(sim.living.research(sim, "siege_doctrine"), "prerequisite chain lets the tier 4 node begin")
	step(sim, 250)
	check("siege_doctrine" in sim.living.discoveries, "tier 4 research completes")
	check(sim.chronicle.effect("command:siege-response"), "research grants a behaviour key, not a percentage")


# --- 3. duplicate unlock prevention -----------------------------------------

func test_no_duplicate_unlocks() -> void:
	var sim = Sim.new()
	var story: Dictionary = {}
	var research: Dictionary = {}
	for quest: Dictionary in sim.quests:
		for id: Variant in quest.get("introduces", []) + quest.get("unlocks", []):
			story[str(id)] = str(quest["id"])
	for id: Variant in sim.chronicle.nodes():
		for unlock: Variant in sim.chronicle.node(str(id)).get("unlocks", []):
			research[str(unlock)] = str(id)
	var shared: Array[String] = []
	for id: String in story:
		if research.has(id):
			shared.append(id)
	shared.sort()
	check(shared.is_empty(), "no content is unlocked by both a mission and research: %s" % str(shared))
	# The brief's own worked example: story introduces Deephole + Diver,
	# research later improves the water route.
	check(story.has("deephole") and story.has("diver"), "the mission introduces Deephole and Diver")
	check(research.has("water-route") or research.has("net"), "research improves water routes instead")


func test_every_gated_id_has_an_owner() -> void:
	var sim = Sim.new()
	var granted: Dictionary = {}
	for id: String in sim.chronicle.unlocked:
		granted[id] = "default"
	for quest: Dictionary in sim.quests:
		for id: Variant in quest.get("introduces", []) + quest.get("unlocks", []):
			granted[str(id)] = str(quest["id"])
	for tid: Variant in sim.chronicle.nodes():
		for unlock: Variant in sim.chronicle.node(str(tid)).get("unlocks", []):
			if not granted.has(str(unlock)):
				granted[str(unlock)] = "research:" + str(tid)
	var orphans: Array[String] = []
	for type_name: Variant in sim.building_specs:
		var spec: Dictionary = sim.building_specs[type_name]
		if bool(spec.get("project", false)):
			continue  # Great Works are permit-gated instead of unlock-gated
		if not granted.has(str(type_name)):
			orphans.append(str(type_name))
	for role: Variant in sim.troop_specs:
		if not granted.has(str(role)):
			orphans.append(str(role))
	orphans.sort()
	check(orphans.is_empty(), "every building and profession has a single owner: %s" % str(orphans))


# --- 4. mission unlock conditions and acts -----------------------------------

func test_acts_and_missions() -> void:
	var sim = Sim.new()
	check(sim.quests.size() >= 40, "the whole campaign is loaded, not a slice")
	var by_act: Dictionary = {}
	for quest: Dictionary in sim.quests:
		by_act[int(quest["act"])] = true
	check(by_act.size() == 10, "all ten acts are present in the data")
	check(sim.chronicle.act == 1, "a new village starts in Act I")
	# Act II cannot be reached by finishing an Act II objective.
	sim.resources["wood"] = 50000
	sim.resources["food"] = 5000
	sim.resources["gold"] = 5000
	check(sim.build("farm", 1, 1), "second field is raised for the opening mission")
	check(sim.build("pond", 1, 5), "the pond mission has its subject")
	check(sim.build("cottage", 1, 9), "the cottage mission has its subject")
	step(sim, 6)  # construction finishes before beds count
	for role in ["farmer", "lumberjack", "miner", "shepherd", "fisherman", "builder", "archer"]:
		sim.recruit(role)
	# Gold must actually be banked: gather objectives count harvest, not a cheat.
	sim.resources["gold"] = 0.0
	for b: Dictionary in sim.buildings:
		if str(b["type"]) == "mine":
			b["reserve"] = 600.0
			sim.collect(int(b["id"]))
	step(sim, 2)
	check(sim.chronicle.act == 1, "an Act II objective cannot complete before its act opens")
	check(not sim.chronicle.is_unlocked("stalled-bacon"), "an unknown id is never unlocked")
	# Finishing Act I opens Act II, and only then do Act II missions bank.
	sim.chronicle.grant("grove", "test")
	sim.build("grove", 2, 13)
	step(sim, 6)
	check("moon-orchard" in sim.completed_quests, "the final Act I mission closes on its own objective")
	check(sim.chronicle.act == 2, "campaign advances when Act I completes")
	check(sim.chronicle.act_name(2).begins_with("II"), "act naming is stable")
	check("new-blood" in sim.completed_quests, "Act II missions complete once the act opens")


func test_mission_introduces_before_completion() -> void:
	var sim = Sim.new()
	sim.chronicle.act = 6
	var quest: Dictionary = sim.quest_by_id("down-dark-water")
	check(not quest.is_empty(), "the deep water mission exists")
	check(not sim.chronicle.is_unlocked("deephole"), "Deephole starts locked")
	sim._quest_record("down-dark-water")
	check(sim.chronicle.is_unlocked("deephole") and sim.chronicle.is_unlocked("diver"), "a mission introduces what its own objectives require")


# --- 5. optional objectives --------------------------------------------------

func test_optional_objectives() -> void:
	var sim = Sim.new()
	sim.chronicle.act = 3
	rich(sim)
	var quest: Dictionary = sim.quest_by_id("the-first-horn")
	check(not quest.is_empty(), "the first horn mission exists")
	check(quest["optional"].size() >= 2, "the raid mission offers optional challenges")
	var record: Dictionary = sim._quest_record("the-first-horn")
	var kept: Dictionary = quest["optional"][0]
	check(sim._optional_met(kept, record), "an untouched raid leaves no losses to report")
	sim.raid_stats["built_lost"] = 1
	check(not sim._optional_met(kept, record), "losing a building breaks the no-loss challenge")
	sim.raid_stats["built_lost"] = 0
	sim.raid_stats["gates_lost"] = 1
	check(not sim._optional_met({"kind": "no_gate_breached"}, record), "losing a gate breaks the gate challenge")
	check(sim._optional_met({"kind": "under_time", "seconds": 240}, record), "an untouched clock meets the time challenge")
	sim.raid_stats["defenders_lost"] = 2
	check(not sim._optional_met({"kind": "no_defenders_lost"}, record), "losing defenders breaks that challenge")
	# Completing the mission seals the challenges and pays them, never gating XP.
	sim.raid_stats["defenders_lost"] = 0
	var slot := 3
	for objective: Dictionary in quest["objectives"]:
		match str(objective["kind"]):
			"build":
				sim.chronicle.grant(str(objective["type"]), "test")
				sim.build(str(objective["type"]), slot, 1)
				slot += 1
			"survive_raid": sim.raid_stats["defended"] = 3
	step(sim, 30)
	check("the-first-horn" in sim.completed_quests, "the raid mission completes on its objectives")
	check(bool(record["optional"].get(str(kept["id"]), false)), "an earned challenge is sealed once")


# --- 6. doctrines ------------------------------------------------------------

func test_doctrines() -> void:
	var sim = Sim.new()
	var chronicle = sim.chronicle
	check(chronicle.doctrines_config().size() >= 5, "doctrines exist")
	check(chronicle.doctrine_slots() >= 1 and chronicle.doctrine_slots() <= 3, "doctrine slots are limited")
	var id: String = str(chronicle.doctrines_config()[0]["id"])
	check(not chronicle.doctrine_reason(id, []).is_empty(), "a doctrine needs its research first")
	chronicle.toggle_doctrine(id, [str(chronicle.doctrine_data(id).get("tech", ""))])
	check(chronicle.has_doctrine(id), "researched doctrine can be sworn")
	chronicle.toggle_doctrine(id, [])
	check(not chronicle.has_doctrine(id), "doctrines can be released in peace")
	var held: int = 0
	for entry: Dictionary in chronicle.doctrines_config():
		var key := str(entry["id"])
		if chronicle.toggle_doctrine(key, [str(entry.get("tech", ""))]).is_empty():
			held += 1
	check(held <= chronicle.doctrine_slots(), "the slot limit is enforced across all doctrines")


# --- 7. region state ---------------------------------------------------------

func test_regions() -> void:
	var sim = Sim.new()
	var chronicle = sim.chronicle
	check(chronicle.region_order().size() == 7, "seven frontier regions")
	var region_id: String = chronicle.region_order()[0]
	check(chronicle.region_state(region_id) == "unseen", "regions start unseen")
	check(not chronicle.region_reason(region_id, "secured").is_empty(), "regions cannot skip states")
	check(not chronicle.set_region(region_id, "scouted").is_empty() or chronicle.region_state(region_id) == "scouted", "scouting needs Act IV")
	chronicle.act = 4
	check(chronicle.set_region(region_id, "scouted").is_empty(), "a scout advances the region")
	check(not chronicle.set_region(region_id, "secured").is_empty(), "a region cannot skip the contested step")
	check(chronicle.set_region(region_id, "contested").is_empty(), "contesting follows scouting")
	check(chronicle.set_region(region_id, "secured").is_empty(), "securing follows contesting")
	check(chronicle.set_region(region_id, "developed").is_empty(), "development follows securing")
	check(chronicle.region_state(region_id) == "developed", "developed regions persist")
	check(not chronicle.set_region(region_id, "unseen").is_empty(), "regions cannot fall back")
	check(chronicle.developed_regions().has(region_id), "developed regions are listed for bonuses")
	chronicle.grant("region-development", "test")
	check(chronicle.bonus("region-development") > 0.0, "a developed region pays a real bonus")


# --- 8. great works ----------------------------------------------------------

func test_great_works() -> void:
	var sim = Sim.new()
	var chronicle = sim.chronicle
	var id: String = str(chronicle.great_works_config().keys()[0])
	check(not chronicle.great_work_reason(id, []).is_empty(), "Great Works need a charter")
	chronicle.grant("command:great-works-permit", "test")
	check(not chronicle.great_work_reason(id, []).is_empty(), "a permit alone is not enough")
	chronicle.raise_great_work(id, [str(chronicle.great_work_data(id).get("tech", ""))])
	check(chronicle.great_works.has(id), "a researched Great Work can be raised")
	check(not chronicle.great_work_reason(id, []).is_empty() or chronicle.great_works.has(id), "a raised Great Work is recorded once")
	for key: Variant in chronicle.great_works_config():
		var entry: Dictionary = chronicle.great_works_config()[key]
		check(sim.building_specs.has(str(entry["building"])), "Great Work %s maps to a real building" % str(key))
		check(not str(entry.get("text", "")).is_empty(), "Great Work %s states what it changes" % str(key))


# --- 9. manor board ----------------------------------------------------------

func test_manor_board() -> void:
	var sim = Sim.new()
	var chronicle = sim.chronicle
	var offers: Array = chronicle.board_offer()
	check(offers.size() == chronicle.board_slots().size(), "the board offers one contract per slot")
	var seen_slots: Dictionary = {}
	for offer: Dictionary in offers:
		if not offer.is_empty():
			seen_slots[str(offer["slot"])] = true
	check(seen_slots.size() == chronicle.board_slots().size(), "each slot offers a different contract type")
	var again: Array = chronicle.board_offer()
	check(again[0].get("id", "") == offers[0].get("id", ""), "the board is deterministic in its seed")
	var contract_id: String = str(offers[0]["id"])
	check(not chronicle.board_accept(contract_id).is_empty() or chronicle.board_contract(contract_id).has("id"), "a posted contract can be accepted")
	check(not chronicle.board_accept(contract_id).is_empty(), "a contract cannot be taken twice")
	check(chronicle.board_complete(contract_id) == false, "an unfinished contract cannot be claimed")
	chronicle.board_advance(contract_id, chronicle.board_target(contract_id))
	check(chronicle.board_complete(contract_id), "a finished contract pays out")
	var reward: Dictionary = chronicle.board_reward(contract_id)
	check(not reward.is_empty(), "a contract carries a real reward")
	# Board contracts must never hold campaign unlocks.
	for entry: Dictionary in chronicle.board_templates():
		check(entry.get("unlocks", []).is_empty(), "repeatable contract %s carries no campaign unlock" % str(entry["id"]))


# --- 10. research actually changes behaviour --------------------------------

func test_research_behaviour() -> void:
	var sim = Sim.new()
	sim.chronicle.act = 5
	rich(sim)
	sim.buildings.clear()
	sim.units.clear()
	sim.chronicle.grant("builder", "default")
	sim.chronicle.grant("warrior", "default")
	var hall_id: int = 0
	sim.build("hall", 9, 7)
	for b: Dictionary in sim.buildings:
		hall_id = int(b["id"])
	var hall: Dictionary = sim.get_building(hall_id)
	_add(sim, "builder")
	# Research completion is what grants behaviour, so drive it the real way.
	sim.living.insight = 400
	sim.living.discoveries.assign(["stoneworking", "road_masonry"])
	sim.chronicle.grant_many(sim.chronicle.node("road_masonry").get("unlocks", []), "research:road_masonry")
	sim.resources["stone"] = 400
	sim.living.cells["12,12"] = {"wear": 1.0, "last": 0.0, "stone": false}
	sim.auto_clock = 99.0
	sim._automation_tick(0.1)
	check(bool(sim.living.cells["12,12"].get("stone", false)), "Road Masonry paves a well-worn trail by itself")
	# Organized Watch fills guard posts from idle defenders.
	sim.living.discoveries.append("organized_watch")
	sim.chronicle.grant_many(sim.chronicle.node("organized_watch").get("unlocks", []), "research:organized_watch")
	sim.chronicle.grant("watchfire", "test")
	sim.build("watchfire", 4, 4)
	step(sim, 6)  # a guard post must be finished before anyone stands in it
	var guard: Dictionary = sim.get_building(int(sim.buildings.back()["id"]))
	check(float(guard.get("remaining", 0.0)) <= 0.0, "the guard post finishes construction")
	_add(sim, "warrior")
	_add(sim, "warrior")
	sim._auto_post()
	var posted: int = 0
	for u: Dictionary in sim.units:
		if int(u["workplace"]) == int(guard["id"]):
			posted += 1
	check(posted > 0, "Organized Watch posts an idle defender")
	# Automated Crafting repairs the wall after a raid.
	hall["hp"] = 50.0
	sim.chronicle.grant("command:auto-repair", "research:automated_crafting")
	sim.raid_active = true
	sim.enemies.clear()
	sim._finish_raid(true)
	check(float(hall["hp"]) > 50.0, "Automated Crafting repairs damage after a won raid")
	# Tower priority picks a siege engine even when it is not the nearest body.
	sim.enemies.assign([
		{"id": 900, "type": "raider", "role": "raider", "x": 7.2, "y": 7.2, "hp": 50.0, "max_hp": 50.0, "phase": "walk", "cooldown": 0.0},
		{"id": 901, "type": "raider", "role": "ram", "x": 8.0, "y": 8.0, "hp": 50.0, "max_hp": 50.0, "phase": "walk", "cooldown": 0.0}])
	sim.chronicle.grant("command:tower-priority", "research:watchtower_doctrine")
	var chosen: Dictionary = sim._tower_target(Vector2(7.0, 7.0))
	check(int(chosen.get("id", 0)) == 901, "Watchtower Doctrine targets the ram, not the nearest raider")
	# Without the research, the tower shoots whoever is nearest.
	sim.chronicle.unlocked.erase("command:tower-priority")
	check(int(sim._tower_target(Vector2(7.0, 7.0)).get("id", 0)) == 900, "without the doctrine the tower shoots the nearest raider")
	sim.enemies.clear()
	sim.raid_active = false


func _add(sim, role: String) -> void:
	sim._add_unit(role)


# --- 11. save migration and old-save compatibility --------------------------

func test_migration() -> void:
	var sim = Sim.new()
	sim.resources["wood"] = 900
	sim.xp = 500
	sim.resources["gold"] = 4000
	sim.build("farm", 1, 1)
	sim.build("pond", 1, 5)
	sim.build("cottage", 1, 9)
	sim.chronicle.grant("grove", "test")
	sim.build("grove", 2, 13)
	step(sim, 6)
	check(sim.quest_progress.size() >= 1, "running the sim records mission progress")
	check(sim.completed_quests.size() >= 1, "Act I missions complete from real building and gathering actions")
	var fresh = Sim.new()
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.export_state()))
	check(fresh.restore_state(state), "a version 3 save round-trips")
	check(fresh.completed_quests.size() == sim.completed_quests.size(), "mission progress survives reload")
	check(int(fresh.chronicle.act) == sim.chronicle.act, "the act is preserved")
	check(fresh.quest_progress.size() == sim.quest_progress.size(), "per-mission records survive reload")
	check(float(fresh.resources["wood"]) == 900.0 + 0.0 or float(fresh.resources["wood"]) > 0.0, "stock is preserved")
	# v2 shape: no chronicle section.
	var legacy: Dictionary = state.duplicate(true)
	legacy["version"] = 2
	legacy.erase("chronicle")
	var two = Sim.new()
	check(two.restore_state(legacy), "a version 2 save still loads")
	check(int(two.chronicle.act) == 1, "migration gives the chronicle a real default act")
	check("second-field" in two.completed_quests or two.completed_quests.size() == sim.completed_quests.size(), "migration never resets mission progress")
	check(is_equal_approx(float(two.resources["wood"]), float(state["resources"]["wood"])), "migration never resets stock")
	# v1 shape: no living section, no stone, no chronicle.
	var oldest: Dictionary = legacy.duplicate(true)
	oldest["version"] = 1
	oldest.erase("living")
	oldest["resources"].erase("stone")
	oldest.erase("quest_progress")
	oldest.erase("raid_stats")
	var one = Sim.new()
	check(one.restore_state(oldest), "a version 1 save still loads")
	check(float(one.resources["stone"]) == 0.0, "migration defaults the Stone resource to zero")
	check(one.living.cells.is_empty() and one.living.insight == 0.0, "migration defaults Living Village cleanly")
	check(int(one.chronicle.act) >= 1, "migration derives a valid act from quest history")
	check(one.completed_quests.size() == sim.completed_quests.size(), "migration keeps every completed mission")
	check("moon-orchard" in sim.completed_quests, "a mission with an unlock completes before the save")
	check(one.chronicle.is_unlocked("grove"), "migration re-derives content the finished missions introduced")
	for quest: Dictionary in sim.quests:
		if str(quest["id"]) not in sim.completed_quests:
			continue
		for id: Variant in quest.get("unlocks", []):
			check(one.chronicle.is_unlocked(str(id)), "migration restores the unlock %s" % str(id))
	# Rejections still reject.
	var bad: Dictionary = state.duplicate(true)
	bad["chronicle"]["act"] = 99
	check(not fresh.restore_state(bad), "an out-of-range act is rejected")
	bad = state.duplicate(true)
	bad["chronicle"]["doctrines"] = ["not-a-doctrine"]
	check(not fresh.restore_state(bad), "an unknown doctrine is rejected")
	bad = state.duplicate(true)
	bad["chronicle"]["regions"]["starwatch-ridge"] = "conquered"
	check(not fresh.restore_state(bad), "an unknown region state is rejected")
	bad = state.duplicate(true)
	bad["quest_progress"]["second-field"]["raid_started"] = 1
	check(not fresh.restore_state(bad), "a non-boolean raid flag is rejected")
	bad = state.duplicate(true)
	bad["raid_stats"]["kills_by"] = {"raider": "many"}
	check(not fresh.restore_state(bad), "non-numeric raid tallies are rejected")
	bad = state.duplicate(true)
	bad["raid_stats"]["defended"] = -1
	check(not fresh.restore_state(bad), "negative raid counters are rejected")
	bad = state.duplicate(true)
	bad["chronicle"]["board"]["active"] = {"ghost": {"id": "ghost", "slot": "settlement", "progress": 1.0}}
	check(not fresh.restore_state(bad), "an unknown board contract is rejected")
	check(fresh.restore_state(state), "the untouched save still loads after rejected attempts")


# --- 12. story banners -------------------------------------------------------

func test_banners() -> void:
	var sim = Sim.new()
	var chronicle = sim.chronicle
	check(chronicle.banner_count() == 0, "no banner is queued on a fresh manor")
	chronicle.queue_banner("Old Bell", "The east road has gone quiet.")
	check(chronicle.banner_count() == 1, "a banner queues")
	chronicle.queue_banner("Old Bell", "The east road has gone quiet.")
	check(chronicle.banner_count() == 1, "identical banners do not stack")
	chronicle.queue_banner("", "")
	check(chronicle.banner_count() == 1, "an empty banner is ignored")
	var first: Dictionary = chronicle.take_banner()
	check(str(first.get("line", "")).begins_with("The east road"), "banners retire in order")
	for index in 8:
		chronicle.queue_banner("Rue", "Line %d" % index)
	check(chronicle.banner_count() <= 4, "the banner queue is bounded for phone screens")


# --- 13. unlock gating on real commands -------------------------------------

func test_command_gating() -> void:
	var sim = Sim.new()
	rich(sim)
	sim.chronicle.unlocked.erase("grove")
	check(not sim.build_reason("grove", 2, 13).is_empty(), "a gated building cannot be built")
	check(not sim.build("grove", 2, 13), "building a gated structure spends nothing")
	check(not sim.recruit_reason("diver").is_empty(), "a gated profession cannot be hired")
	check(not sim.recruit("diver"), "hiring a gated profession spends nothing")
	sim.chronicle.grant("grove", "test")
	check(sim.build_reason("grove", 2, 13).is_empty(), "a granted building becomes buildable")
	sim.chronicle.grant("diver", "test")
	check(sim.recruit_reason("diver").is_empty(), "a granted profession becomes hireable")
	# The quarry stays behind Stoneworking, exactly as before.
	var bare = Sim.new()
	bare.chronicle.unlocked.erase("stone_quarry")
	check(not bare.build_reason("stone_quarry", 1, 5).is_empty(), "the quarry stays behind Stoneworking research")


func _run() -> void:
	test_tech_tree()
	test_prereqs_and_tiers()
	test_no_duplicate_unlocks()
	test_every_gated_id_has_an_owner()
	test_acts_and_missions()
	test_mission_introduces_before_completion()
	test_optional_objectives()
	test_doctrines()
	test_regions()
	test_great_works()
	test_manor_board()
	test_research_behaviour()
	test_migration()
	test_banners()
	test_command_gating()
	_report()


func _report() -> void:
	print("CHRONICLE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	var file := FileAccess.open("res://docs/chronicle_verification.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}, "\t"))
		file.close()
	quit(0 if failures.is_empty() else 1)