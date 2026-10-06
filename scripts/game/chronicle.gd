extends RefCounted
class_name Chronicle

# All Manor Chronicle progression state in one place: acts, the unified tech
# tree, the unlock registry, frontier region states, doctrines, Great Works and
# the Manor Board. village_sim.gd keeps simulation authority; this module owns
# what the player has *earned*, so exactly one save section needs migrating.

const CONFIG_PATH := "res://data/chronicle.json"
const REGION_ORDER: Array[String] = ["starwatch-ridge", "whisperwood", "ashfall-march", "blackwater-mouth", "southreach", "dawnfields", "pale-coast"]

# Behaviour keys the sim queries. Research grants these, so a tech that only
# carried a percentage would never appear here.
const EFFECTS: Array[String] = [
	"auto-pave", "auto-post", "auto-repair", "wall-row", "gate-brace", "tower-priority",
	"siege-response", "war-plan", "formation", "scout-report", "camp-intel", "outpost-supply",
	"builder-queue", "great-works-permit", "global-craft", "school-lessons", "legacy-oath",
	"town-meal", "long-expedition", "water-route", "supply-ledger", "promotion",
	"moon-orchard", "recovery-bell", "triage", "recovery-drill", "repair-rationing",
	"prestige", "civic-unity", "region-development", "forged-tools", "plate-yield", "standard-tools",
]

var config: Dictionary = {}
var act: int = 1
var unlocked: Dictionary = {}
var unlock_sources: Dictionary = {}
var regions: Dictionary = {}
var doctrines: Array[String] = []
var great_works: Array[String] = []
var reputation: int = 0
var board: Dictionary = {}
var board_seed: int = 1
var board_clock: float = 0.0
var banners: Array[Dictionary] = []


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	config = parsed if parsed is Dictionary else {}
	for region_id: String in REGION_ORDER:
		regions[region_id] = "unseen"
	board = {"active": {}, "done": []}
	_grant_defaults()


# --- configuration accessors ------------------------------------------------

func nodes() -> Dictionary:
	return config.get("tech", {})


func node(id: String) -> Dictionary:
	return nodes().get(id, {})


func branches() -> Array:
	return config.get("branchOrder", [])


func branch_nodes(branch: String) -> Array:
	var out: Array = []
	for id: Variant in nodes():
		if str(node(str(id))["branch"]) == branch:
			out.append(str(id))
	return out


func tier_of(id: String) -> int:
	return int(node(id).get("tier", 1))


func tier_data(tier: int) -> Dictionary:
	for entry: Dictionary in config.get("tiers", []):
		if int(entry["tier"]) == tier:
			return entry
	return {}


func max_tier() -> int:
	var best: int = 1
	for entry: Dictionary in config.get("tiers", []):
		best = maxi(best, int(entry["tier"]))
	return best


func has_config() -> bool:
	return not config.is_empty()


# --- unlock registry --------------------------------------------------------
# Story introduces content (buildings, professions, gear). Research grants
# behaviour keys, commands, doctrines and Great Works. Keeping the two id
# spaces disjoint is what makes duplicate unlocks structurally impossible.

func _grant_defaults() -> void:
	# Content ids that were never gated before stay available from the start.
	for id: String in _free_content():
		unlocked[id] = true
		unlock_sources[id] = "default"


func _free_content() -> Array[String]:
	# stone_quarry is deliberately absent: Stoneworking research introduces it,
	# so it lives in the registry instead of being free.
	return ["hall", "farm", "lumber", "timber_yard", "mine", "cottage", "pond", "pasture",
		"barracks", "tower", "wall", "storehouse", "sawmill",
		"warrior", "archer", "builder", "farmer", "lumberjack", "miner", "fisherman", "shepherd"]


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func grant(id: String, source: String) -> bool:
	if id.is_empty() or unlocked.has(id):
		return false
	unlocked[id] = true
	unlock_sources[id] = source
	return true


func grant_many(ids: Array, source: String) -> Array[String]:
	var fresh: Array[String] = []
	for id: Variant in ids:
		if grant(str(id), source):
			fresh.append(str(id))
	return fresh


func source_of(id: String) -> String:
	return str(unlock_sources.get(id, ""))


func story_content_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in unlocked:
		if not id.begins_with("command:") and not id.begins_with("aura:") \
			and not id.begins_with("doctrine:") and not id.begins_with("greatwork:") \
			and not id.begins_with("variant:") and not id.begins_with("recipe:"):
			out.append(id)
	return out


# --- behaviour effects ------------------------------------------------------

func effect(name: String) -> bool:
	return unlocked.has(name)


func effect_source(name: String) -> String:
	return source_of(name)


func has_doctrine(id: String) -> bool:
	return doctrines.has(id)


func developed_regions() -> Array[String]:
	var out: Array[String] = []
	for region_id: String in regions:
		if str(regions[region_id]) == "developed":
			out.append(region_id)
	return out


func bonus(name: String) -> float:
	# Behaviour is primary; these are supporting numbers only, never a whole reward.
	var total: float = 0.0
	if effect("moon-orchard") or has_doctrine("full-granaries"):
		total += 0.05
	if effect("recovery-bell"):
		total += 0.25
	if effect("triage"):
		total += 0.20
	if effect("recovery-drill"):
		total += 0.25
	if effect("repair-rationing") or has_doctrine("hold-the-line") or has_doctrine("master-craftsmen"):
		total += 0.15
	if effect("plate-yield"):
		total += 0.10
	if effect("forged-tools") or has_doctrine("master-craftsmen"):
		total += 0.10
	if effect("school-lessons"):
		total += 0.15
	if effect("prestige"):
		total += 0.10
	if effect("region-development"):
		total += 0.02 * float(developed_regions().size())
	return total


# --- acts -------------------------------------------------------------------

func acts() -> Array:
	return config.get("acts", [])


func act_count() -> int:
	return maxi(1, acts().size())


func act_data(number: int) -> Dictionary:
	for entry: Dictionary in acts():
		if int(entry["id"].replace("act", "")) == number:
			return entry
	return {}


func act_name(number: int) -> String:
	var data: Dictionary = act_data(number)
	return "%s / %s" % [str(data.get("numeral", "?")), str(data.get("name", "Unwritten"))] if not data.is_empty() else "Unwritten"


func current_tier() -> int:
	return int(act_data(act).get("tier", 1))


func max_act_reached() -> int:
	return act


func can_enter_act(number: int) -> bool:
	return number <= act


func advance_act() -> int:
	if act >= act_count():
		return act
	act += 1
	var data: Dictionary = act_data(act)
	if not data.is_empty():
		queue_banner(str(data.get("banner", {}).get("character", "")), str(data.get("banner", {}).get("line", "")))
	return act


# --- tech tier gating -------------------------------------------------------

func tier_reason(id: String) -> String:
	# Technology tiers are gated by campaign progress, never by a mutually
	# exclusive choice: every node stays reachable eventually.
	var data: Dictionary = node(id)
	if data.is_empty():
		return "Unknown research."
	var tier: int = int(data.get("tier", 1))
	if tier > current_tier():
		var gate: Dictionary = tier_data(tier)
		return "Requires Act %s / %s." % [str(gate.get("minAct", "I")), str(gate.get("name", "a later act"))]
	return ""


func prereq_reason(id: String, discovered: Array) -> String:
	var missing: Array[String] = []
	for need: Variant in node(id).get("requires", []):
		if not (discovered as Array).has(str(need)):
			missing.append(str(node(str(need)).get("name", need)))
	if missing.is_empty():
		return ""
	return "Requires %s." % ", ".join(missing)


# --- frontier regions -------------------------------------------------------

func region_order() -> Array[String]:
	return REGION_ORDER


func region_data(id: String) -> Dictionary:
	return config.get("regions", {}).get(id, {})


func region_state(id: String) -> String:
	return str(regions.get(id, "unseen"))


func region_index(id: String) -> int:
	var states: Array = config.get("regionStates", [])
	return maxi(0, states.find(region_state(id)))


func region_states() -> Array:
	return config.get("regionStates", [])


func region_reason(id: String, target: String) -> String:
	if not region_data(id).has("name"):
		return "Unknown region."
	var states: Array = region_states()
	var wanted: int = states.find(target)
	if wanted < 0:
		return "Unknown region state."
	var current: int = region_index(id)
	if wanted == current:
		return ""
	if wanted < current:
		return "A region cannot fall back."
	if wanted > current + 1:
		return "Requires %s first." % str(states[current + 1]).capitalize()
	if wanted >= 2 and act < 4:
		return "Requires Act IV / Beyond the Lanterns."
	return ""


func set_region(id: String, target: String) -> String:
	var reason: String = region_reason(id, target)
	if not reason.is_empty():
		return reason
	regions[id] = target
	if target == "scouted":
		queue_banner("Fen the wayfinder", str(region_data(id).get("name", id)) + " is on the chart.")
	elif target == "developed":
		queue_banner("Fen the wayfinder", str(region_data(id).get("benefit", "")) + " The region pays its keep now.")
	return ""


# --- doctrines --------------------------------------------------------------

func doctrines_config() -> Array:
	return config.get("doctrines", [])


func doctrine_data(id: String) -> Dictionary:
	for entry: Dictionary in doctrines_config():
		if str(entry["id"]) == id:
			return entry
	return {}


func doctrine_slots() -> int:
	return int(config.get("doctrineSlots", 2))


func doctrine_reason(id: String, researching: Array) -> String:
	var data: Dictionary = doctrine_data(id)
	if data.is_empty():
		return "Unknown doctrine."
	if doctrines.has(id):
		return ""
	if not is_unlocked("doctrine:" + id) and not (researching as Array).has(str(data.get("tech", ""))):
		return "Research %s first." % str(node(str(data.get("tech", ""))).get("name", data.get("tech", "")))
	if doctrines.size() >= doctrine_slots():
		return "All %d doctrine slots are held." % doctrine_slots()
	return ""


func toggle_doctrine(id: String, researching: Array) -> String:
	# The sim blocks switching during an alarm; this only owns the slot rules.
	if doctrines.has(id):
		doctrines.erase(id)
		return ""
	var reason: String = doctrine_reason(id, researching)
	if reason.is_empty():
		doctrines.append(id)
	return reason


# --- great works ------------------------------------------------------------

func great_works_config() -> Dictionary:
	return config.get("greatWorks", {})


func great_work_data(id: String) -> Dictionary:
	return great_works_config().get(id, {})


func great_work_reason(id: String, researching: Array) -> String:
	var data: Dictionary = great_work_data(id)
	if data.is_empty():
		return "Unknown Great Work."
	if great_works.has(id):
		return "Already raised."
	if not is_unlocked(id) and not (researching as Array).has(str(data.get("tech", ""))):
		return "Requires research and a Great Works permit."
	return ""


func raise_great_work(id: String, researching: Array) -> String:
	var reason: String = great_work_reason(id, researching)
	if reason.is_empty():
		great_works.append(id)
		queue_banner("Old Bell", str(great_work_data(id).get("name", id)) + " stands. The Manner will remember it.")
	return reason


# --- story banners ----------------------------------------------------------

func queue_banner(character: String, line: String) -> void:
	if line.is_empty():
		return
	for entry: Dictionary in banners:
		if str(entry["line"]) == line:
			return
	if banners.size() >= 4:
		banners.pop_front()
	banners.append({"character": character, "line": line})


func take_banner() -> Dictionary:
	if banners.is_empty():
		return {}
	return banners.pop_front()


func banner_count() -> int:
	return banners.size()


# --- manor board ------------------------------------------------------------

func board_config() -> Dictionary:
	return config.get("board", {})


func board_slots() -> Array:
	return board_config().get("slots", [])


func board_refresh_seconds() -> float:
	return float(board_config().get("refreshSeconds", 240))


func board_templates() -> Array:
	return board_config().get("templates", [])


func _board_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed
	return rng


func board_offer() -> Array[Dictionary]:
	# Deterministic in board_seed so a reloaded save redraws the same board.
	var rng: RandomNumberGenerator = _board_rng()
	var offers: Array[Dictionary] = []
	var used: Array[String] = []
	for slot: String in board_slots():
		var pool: Array = []
		for entry: Dictionary in board_templates():
			if str(entry["slot"]) == slot and not used.has(str(entry["id"])):
				pool.append(entry)
		if pool.is_empty():
			offers.append({})
			continue
		var picked: Dictionary = pool[rng.randi() % pool.size()]
		used.append(str(picked["id"]))
		offers.append({"id": str(picked["id"]), "slot": slot, "template": picked, "progress": 0.0})
	return offers


func board_contract(id: String) -> Dictionary:
	for entry: Dictionary in board["active"].values():
		if str(entry["id"]) == id:
			return entry
	return {}


func board_active_ids() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in board["active"]:
		out.append(str(id))
	return out


func board_accept(id: String) -> String:
	if board_contract(id).has("id"):
		return "Already on the board."
	for entry: Dictionary in board_offer():
		if entry.is_empty() or str(entry["id"]) != id:
			continue
		board["active"][id] = {"id": id, "slot": str(entry["slot"]), "progress": 0.0}
		return ""
	return "That contract is not posted."


func board_target(id: String) -> float:
	var contract: Dictionary = board_contract(id)
	if contract.is_empty():
		return 0.0
	for entry: Dictionary in board_templates():
		if str(entry["id"]) != id:
			continue
		var objective: Dictionary = entry.get("objective", {})
		return float(objective.get("amount", objective.get("count", 1)))
	return 0.0


func board_advance(id: String, amount: float) -> void:
	var contract: Dictionary = board_contract(id)
	if contract.is_empty():
		return
	contract["progress"] = maxf(0.0, float(contract["progress"]) + amount)


func board_complete(id: String) -> bool:
	var contract: Dictionary = board_contract(id)
	if contract.is_empty():
		return false
	if float(contract["progress"]) < board_target(id):
		return false
	board["active"].erase(id)
	board["done"].append(id)
	return true


func board_reward(id: String) -> Dictionary:
	for entry: Dictionary in board_templates():
		if str(entry["id"]) == id:
			return {"resources": entry.get("reward", {}), "insight": int(entry.get("insight", 0)), "reputation": int(entry.get("reputation", 0))}
	return {}


func board_tick(dt: float) -> bool:
	board_clock += dt
	if board_clock < board_refresh_seconds():
		return false
	board_clock = 0.0
	board_seed += 1
	return true


# --- save -------------------------------------------------------------------

func state() -> Dictionary:
	return {
		"version": 3, "act": act, "unlocked": unlocked.duplicate(), "sources": unlock_sources.duplicate(),
		"regions": regions.duplicate(), "doctrines": doctrines.duplicate(),
		"great_works": great_works.duplicate(), "reputation": reputation,
		"board": {"active": board["active"].duplicate(true), "done": board["done"].duplicate()},
		"board_seed": board_seed, "board_clock": board_clock, "banners": banners.duplicate(true),
	}


func valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var payload: Dictionary = data
	if not _integer(payload.get("version")) or int(payload["version"]) != 3:
		return false
	if not _integer(payload.get("act")) or int(payload["act"]) < 1 or int(payload["act"]) > act_count():
		return false
	for field in ["unlocked", "sources", "regions"]:
		if not payload.get(field) is Dictionary:
			return false
	if payload["unlocked"].size() > 400 or payload["sources"].size() > 400:
		return false
	for id: Variant in payload["unlocked"]:
		if not id is String:
			return false
	for region_id: Variant in payload["regions"]:
		if not region_id is String or str(region_id) not in regions:
			return false
		if str(payload["regions"][region_id]) not in region_states():
			return false
	if not payload.get("doctrines") is Array or not payload.get("great_works") is Array:
		return false
	if payload["doctrines"].size() > doctrine_slots():
		return false
	for id: Variant in payload["doctrines"]:
		if doctrine_data(str(id)).is_empty():
			return false
	for id: Variant in payload["great_works"]:
		if great_work_data(str(id)).is_empty():
			return false
	if not _nonneg(payload.get("reputation")) or not _nonneg(payload.get("board_clock")):
		return false
	if not _integer(payload.get("board_seed")):
		return false
	if not payload.get("board") is Dictionary:
		return false
	var saved_board: Dictionary = payload["board"]
	if not saved_board.get("active") is Dictionary or not saved_board.get("done") is Array:
		return false
	if saved_board["active"].size() > board_slots().size() or saved_board["done"].size() > 64:
		return false
	for id: Variant in saved_board["active"]:
		if not saved_board["active"][id] is Dictionary:
			return false
		var contract: Dictionary = saved_board["active"][id]
		if str(contract.get("id", "")) != str(id):
			return false
		var template: Dictionary = {}
		for entry: Dictionary in board_templates():
			if str(entry["id"]) == str(id):
				template = entry
				break
		if template.is_empty():
			return false
		if not _nonneg(contract.get("progress")) or str(contract.get("slot", "")) != str(template["slot"]):
			return false
		var objective: Dictionary = template.get("objective", {})
		var target: float = float(objective.get("amount", objective.get("count", 1)))
		if float(contract["progress"]) > target:
			return false
	if not payload.get("banners") is Array or payload["banners"].size() > 4:
		return false
	return true


func restore(data: Dictionary) -> void:
	act = int(data["act"])
	unlocked = data["unlocked"].duplicate()
	unlock_sources = data["sources"].duplicate()
	regions = data["regions"].duplicate()
	for region_id: String in REGION_ORDER:
		regions[region_id] = regions.get(region_id, "unseen")
	doctrines.assign(data["doctrines"])
	great_works.assign(data["great_works"])
	reputation = int(data["reputation"])
	board = {"active": data["board"]["active"].duplicate(true), "done": data["board"]["done"].duplicate()}
	board_seed = int(data["board_seed"])
	board_clock = float(data["board_clock"])
	banners.assign(data.get("banners", []))


func _nonneg(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0


func _integer(value: Variant) -> bool:
	return _nonneg(value) and float(value) == floorf(float(value))