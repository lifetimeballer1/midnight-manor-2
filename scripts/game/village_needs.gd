extends RefCounted

var hunger: float = 0.0
var morale: float = 70.0
var meal_clock: float = 0.0


func tick(sim, dt: float) -> void:
	if sim.paused or not is_finite(dt) or dt <= 0.0 or dt > 1.0:
		return
	var meal: Dictionary = sim.world_specs["townMeal"]
	var demand: float = float(meal["foodPerVillager"]) * sim.units.size()
	meal_clock += dt
	if meal_clock >= float(meal["secondsPerDay"]):
		meal_clock -= float(meal["secondsPerDay"])
		var paid: float = minf(demand, float(sim.resources.get("food", 0.0)))
		sim.resources["food"] = maxf(0.0, float(sim.resources.get("food", 0.0)) - paid)
		if paid < demand:
			hunger = minf(100.0, hunger + 25.0 * (1.0 - paid / maxf(1.0, demand)))
			sim.notice = "Food shortage. Collect from farms and restore the village meal."
	if float(sim.resources.get("food", 0.0)) >= demand:
		hunger = maxf(0.0, hunger - dt * 0.5)
	var housed: float = minf(1.0, float(sim.beds()) / maxf(1.0, float(sim.units.size())))
	var target: float = clampf(70.0 - hunger * 0.5 - (1.0 - housed) * 25.0, 0.0, 70.0)
	morale = move_toward(morale, target, dt * 0.2)


func production_multiplier() -> float:
	return clampf(1.0 - hunger * 0.002 - maxf(0.0, 70.0 - morale) * 0.001, 0.75, 1.0)


func summary(sim) -> String:
	var status: String = "Fed"
	if hunger > 0.0:
		status = "Food shortage"
	elif sim.units.size() > sim.beds():
		status = "More homes needed"
	elif float(sim.resources.get("food", 0.0)) < float(sim.world_specs["townMeal"]["foodPerVillager"]) * sim.units.size():
		status = "Food running low"
	return "%s / %d morale / %d of %d beds" % [status, int(morale), sim.units.size(), sim.beds()]


func state() -> Dictionary:
	return {"hunger": hunger, "morale": morale, "meal_clock": meal_clock}


func valid(data: Variant, meal_seconds: float) -> bool:
	if not data is Dictionary:
		return false
	for field: String in ["hunger", "morale", "meal_clock"]:
		var value: Variant = data.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
			return false
	return float(data["hunger"]) <= 100.0 and float(data["morale"]) <= 100.0 and float(data["meal_clock"]) < meal_seconds


func restore(data: Dictionary) -> void:
	hunger = float(data["hunger"])
	morale = float(data["morale"])
	meal_clock = float(data["meal_clock"])
