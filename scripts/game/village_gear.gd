extends RefCounted

# The gear chain (data/gear.json). Pastures and the Butchery give hides beside their food; a staffed
# Tannery cures hides into leather and a staffed Forge beats plate and lumber into arms. Veteran
# troops need that gear to be hired, on top of their recruitCost, so the army reflects the industry
# behind it. Basic warriors and archers still cost only Food and Gold.
# Part-made goods are kept per building as fractions and are not saved (a few seconds of work).

const CONFIG_PATH: String = "res://data/gear.json"

var config: Dictionary = {}
var _work: Dictionary = {}   # "building id/recipe index" or "building id/resource" -> part done


func _init() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			config = parsed


# Food and Gold from troops.json plus any gear this role needs.
func hire_cost(sim, role: String) -> Dictionary:
	var cost: Dictionary = (sim.troop_specs[role].get("recruitCost", {}) as Dictionary).duplicate()
	var gear: Dictionary = config.get("hire", {}).get(role, {})
	for resource: String in gear:
		cost[resource] = int(cost.get(resource, 0)) + int(gear[resource])
	return cost


func needs_gear(role: String) -> bool:
	return config.get("hire", {}).has(role)


# Why the gear for this role is missing, naming what makes it, or "".
func gear_reason(sim, role: String) -> String:
	var gear: Dictionary = config.get("hire", {}).get(role, {})
	var parts: PackedStringArray = []
	for resource: String in gear:
		if float(sim.resources.get(resource, 0.0)) < float(gear[resource]):
			parts.append("%d %s" % [int(gear[resource]), resource.capitalize()])
	if parts.is_empty():
		return ""
	return "Needs %s. %s" % [", ".join(parts), "A staffed Forge makes Arms from Plate and Lumber; a Tannery cures Hides from pastures into Leather."]


func tick(sim, dt: float) -> void:
	if sim.paused or dt <= 0.0 or dt > 1.0:
		return
	var byproducts: Dictionary = config.get("byproducts", {})
	var recipes: Dictionary = config.get("recipes", {})
	for b: Dictionary in sim.buildings:
		var type_name: String = str(b["type"])
		if not byproducts.has(type_name) and not recipes.has(type_name):
			continue
		if float(b["hp"]) <= 0.0 or float(b["remaining"]) > 0.0:
			continue
		var id: int = int(b["id"])
		for resource: String in byproducts.get(type_name, {}):
			var key: String = "%d/%s" % [id, resource]
			var made: float = float(_work.get(key, 0.0)) + float(byproducts[type_name][resource]) * sim.estate_scale(b) * dt
			var whole: int = floori(made)
			if whole > 0:
				sim._bank(resource, float(whole))
				made -= whole
			_work[key] = made
		if not recipes.has(type_name) or sim.crew_of(b) <= 0:
			continue
		var list: Array = recipes[type_name]
		for index in list.size():
			var recipe: Dictionary = list[index]
			var key: String = "%d/%d" % [id, index]
			var done: float = minf(1.0, float(_work.get(key, 0.0)) + float(recipe.get("perSec", 0.0)) * sim.perks.gather_for(b) * dt)
			if done >= 1.0 and sim._affordable(recipe["in"]) and _room(sim, recipe["out"]):
				sim._spend(recipe["in"])
				for resource: String in recipe["out"]:
					sim._bank(resource, float(recipe["out"][resource]))
				done = 0.0
			_work[key] = done


func _room(sim, out: Dictionary) -> bool:
	for resource: String in out:
		if float(sim.resources.get(resource, 0.0)) + float(out[resource]) > sim.storage_cap(resource):
			return false
	return true


# One line for a gear building's card, or "".
func describe(sim, b: Dictionary) -> String:
	var type_name: String = str(b["type"])
	var parts: PackedStringArray = []
	for resource: String in config.get("byproducts", {}).get(type_name, {}):
		parts.append("Also gives %s · %d in store" % [resource.capitalize(), int(sim.resources.get(resource, 0.0))])
	for recipe: Dictionary in config.get("recipes", {}).get(type_name, []):
		var ins: PackedStringArray = []
		for resource: String in recipe["in"]:
			ins.append("%d %s" % [int(recipe["in"][resource]), resource.capitalize()])
		var outs: PackedStringArray = []
		for resource: String in recipe["out"]:
			outs.append("%d %s" % [int(recipe["out"][resource]), resource.capitalize()])
		var line: String = "Makes %s from %s" % [", ".join(outs), ", ".join(ins)]
		if sim.crew_of(b) <= 0:
			line += " · needs a worker"
		parts.append(line)
	return "\n".join(parts)
