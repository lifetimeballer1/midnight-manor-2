extends RefCounted

# Building with real materials (data/materials.json). Zone-grown sites carry a bill and a stock of
# delivered materials on their building record ("bill", "stock", "work"). Builders haul from the
# central stores to the site, and the site's countdown only moves while a builder stands there and
# the delivered share of the bill covers the work done so far. Repairs of stone-built types take
# Stone once Stoneworking is known. Bought defences carry no bill and keep the old timer.

const CONFIG_PATH: String = "res://data/materials.json"
const MATERIALS: Array[String] = ["wood", "stone", "lumber"]

var config: Dictionary = {}


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	config = parsed if parsed is Dictionary else {}


func stone_known(sim) -> bool:
	return "stoneworking" in sim.living.discoveries


# Stone goes on a bill only once a Stone Quarry stands to supply it; before that it is paid in Wood,
# so a site never waits on stone the village has no way to get.
func stone_supplied(sim) -> bool:
	return stone_known(sim) and sim._has_completed_building("stone_quarry", 1)


# Lumber is asked for once the village has a working Sawmill; before that it is paid in Wood.
func lumber_known(sim) -> bool:
	return sim._has_completed_building("sawmill", 1)


# Materials a zone-grown building needs to rise (tier 1) or move up to `tier`.
func bill_for(sim, type_name: String, tier: int) -> Dictionary:
	var grown: Dictionary = config.get("grown", {})
	var spec: Dictionary = sim.building_specs[type_name]
	var size: int = int(spec.get("size", 1))
	var cost: Dictionary = sim.building_cost(type_name, tier)
	var bill: Dictionary = {}
	var wood: float = float(cost.get("wood", 0.0)) * float(grown.get("woodShare", 0.5))
	var stone: float = float(grown.get("stonePerTile", {}).get(str(tier), 0.0)) * size * size
	if tier >= int(grown.get("lumberFromTier", 99)):
		var lumber: float = maxf(float(cost.get("lumber", 0.0)), float(cost.get("wood", 0.0)) * float(grown.get("lumberShare", 0.0)))
		if lumber > 0.0 and lumber_known(sim):
			bill["lumber"] = ceili(lumber)
		elif lumber > 0.0:
			wood += lumber * float(config.get("woodPerStone", 2))
	if stone > 0.0:
		if stone_supplied(sim):
			bill["stone"] = ceili(stone)
		else:
			wood += stone * float(config.get("woodPerStone", 2))
	if wood > 0.0:
		bill["wood"] = ceili(wood)
	return bill


# Put a bill on a site that is starting to rise or tier up.
func open_site(sim, b: Dictionary, tier: int) -> void:
	b["bill"] = bill_for(sim, str(b["type"]), tier)
	b["stock"] = {}
	b["work"] = float(b["remaining"])


func has_bill(b: Dictionary) -> bool:
	return b.get("bill") is Dictionary and not (b["bill"] as Dictionary).is_empty()


# What is still to be delivered to a site, by material.
func needed(b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not has_bill(b):
		return out
	for resource: String in b["bill"]:
		var short: int = int(b["bill"][resource]) - int((b.get("stock", {}) as Dictionary).get(resource, 0))
		if short > 0:
			out[resource] = short
	return out


func delivered_share(b: Dictionary) -> float:
	if not has_bill(b):
		return 1.0
	var total: float = 0.0
	var got: float = 0.0
	for resource: String in b["bill"]:
		total += float(b["bill"][resource])
		got += minf(float(b["bill"][resource]), float((b.get("stock", {}) as Dictionary).get(resource, 0)))
	return 1.0 if total <= 0.0 else got / total


# Builders standing at this site and working.
func hands(sim, b: Dictionary) -> int:
	var count: int = 0
	for u: Dictionary in sim.units:
		if float(u["hp"]) > 0.0 and int(u.get("site", -1)) == int(b["id"]) and bool(u.get("on_site", false)):
			count += 1
	return count


# How many seconds of work this site does in dt. Billed sites need a builder and delivered materials.
func progress(sim, b: Dictionary, dt: float) -> float:
	if not has_bill(b):
		return dt
	var crew: Dictionary = config.get("builders", {})
	var n: int = mini(hands(sim, b), int(crew.get("maxHands", 3)))
	if n <= 0:
		return 0.0
	var speed: float = 1.0 + float(crew.get("extraHands", 0.6)) * float(n - 1)
	return clampf(dt * speed, 0.0, work_left(b))


# Seconds of work this site can do with what has been delivered so far.
func work_left(b: Dictionary) -> float:
	# A fully stocked site may finish outright: the share sum below can leave a float sliver
	# of work that never gets done, which held builders on a site that looked finished.
	if not has_bill(b) or needed(b).is_empty():
		return float(b["remaining"])
	var total: float = maxf(0.001, float(b.get("work", b["remaining"])))
	return maxf(0.0, total * delivered_share(b) - (total - float(b["remaining"])))


# Whether builders can move this site on now: work is covered by delivered materials, or the stores
# hold something it still needs.
func workable(sim, b: Dictionary) -> bool:
	if work_left(b) > 0.001:
		return true
	var need: Dictionary = needed(b)
	for resource: String in need:
		if float(sim.resources.get(resource, 0.0)) >= 1.0:
			return true
	return false


# A bill that still asks for stone or lumber the village cannot produce and does not hold is
# switched to Wood (woodPerStone each), so older sites and lost quarries or sawmills never stall it.
func settle_bill(sim, b: Dictionary) -> void:
	var need: Dictionary = needed(b)
	for resource: String in ["stone", "lumber"]:
		if not need.has(resource) or float(sim.resources.get(resource, 0.0)) >= 1.0:
			continue
		if (stone_supplied(sim) if resource == "stone" else lumber_known(sim)):
			continue
		var short: int = int(need[resource])
		b["bill"][resource] = int(b["bill"][resource]) - short
		if int(b["bill"][resource]) <= 0:
			b["bill"].erase(resource)
		b["bill"]["wood"] = int(b["bill"].get("wood", 0)) + short * int(config.get("woodPerStone", 2))


# The first material this site is waiting for that the stores cannot supply, as "12 Stone", or "".
func shortage(sim, b: Dictionary) -> String:
	var need: Dictionary = needed(b)
	for resource: String in MATERIALS:
		if need.has(resource) and float(sim.resources.get(resource, 0.0)) < 1.0:
			return "%d %s" % [int(need[resource]), resource.capitalize()]
	return ""


# Take one load for this site from the central stores. Returns {resource, amount} or {}.
func pick_up(sim, b: Dictionary, capacity: int) -> Dictionary:
	var need: Dictionary = needed(b)
	for resource: String in MATERIALS:
		if not need.has(resource):
			continue
		var amount: int = mini(mini(capacity, int(need[resource])), floori(float(sim.resources.get(resource, 0.0))))
		if amount > 0:
			sim.resources[resource] = float(sim.resources[resource]) - amount
			return {"resource": resource, "amount": amount}
	return {}


func drop_off(b: Dictionary, resource: String, amount: int) -> int:
	if not has_bill(b):
		return 0
	var stock: Dictionary = b.get("stock", {})
	var room: int = maxi(0, int(b["bill"].get(resource, 0)) - int(stock.get(resource, 0)))
	var used: int = mini(room, amount)
	stock[resource] = int(stock.get(resource, 0)) + used
	b["stock"] = stock
	return used


func close_site(b: Dictionary) -> void:
	b.erase("bill")
	b.erase("stock")
	b.erase("work")


func haul(sim, u: Dictionary) -> int:
	return int(config.get("builders", {}).get("haul", 20)) + int(sim.perks.total("carry"))


func stone_built(type_name: String) -> bool:
	return type_name in (config.get("repair", {}).get("stoneTypes", []) as Array)


# Materials to restore `hp` points on b, as {wood, stone}.
func repair_cost(sim, b: Dictionary, hp: float, per_unit: float) -> Dictionary:
	var units: int = ceili(hp / per_unit)
	if units <= 0:
		return {}
	if stone_built(str(b["type"])) and stone_known(sim):
		var stone: int = ceili(units * float(config.get("repair", {}).get("stoneShare", 0.5)))
		return {"stone": stone, "wood": maxi(0, units - stone)}
	return {"wood": units}


# The most hp the stores can pay for on b, up to `want`, in whole repair units.
func affordable_hp(sim, b: Dictionary, want: float, per_unit: float) -> float:
	var units: int = ceili(want / per_unit) if want > 0.0 else 0
	while units > 0 and not sim._affordable(repair_cost(sim, b, units * per_unit, per_unit)):
		units -= 1
	return minf(want, units * per_unit)


func valid_site(b: Dictionary) -> bool:
	for key: String in ["bill", "stock"]:
		if not b.has(key):
			continue
		if not b[key] is Dictionary:
			return false
		for resource: Variant in b[key]:
			if str(resource) not in MATERIALS or not (b[key][resource] is int or b[key][resource] is float) or float(b[key][resource]) < 0.0:
				return false
	if b.has("work") and not (b["work"] is int or b["work"] is float):
		return false
	return true
