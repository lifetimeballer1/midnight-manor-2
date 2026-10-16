extends RefCounted

# The village meal (data/world.json townMeal). Once a day the village eats from the best it has:
# bread first (breadPerVillager each, and a fully bread-fed village is Well fed until the next
# meal), then plain food (foodPerVillager each). Fighters eat soldierAppetite times as much.
# A meal with spare feast supplies turns into a Feast: a morale lift and faster newcomers for a day.
# Missed meals add up: after starveIdle missed meals in a row the village works at half pace, and
# after starveLeave each further missed meal sends one villager away (they leave, they never die).

const SOLDIER_APPETITE: float = 2.0
const STARVE_IDLE: int = 2
const STARVE_LEAVE: int = 5
const FEAST_PER: int = 5          # one feast supply for every this many villagers
const FEAST_MORALE: float = 15.0

var hunger: float = 0.0
var morale: float = 70.0
var meal_clock: float = 0.0
var missed: int = 0               # meals missed in a row
var fed: String = "fed"           # how the last meal went: fed, well_fed, feast, short


func appetite(sim, u: Dictionary) -> float:
	return SOLDIER_APPETITE if str(sim.troop_specs[u["type"]].get("role", "")) == "combat" else 1.0


# Food-equivalent shares the whole village eats in one meal.
func shares(sim) -> float:
	var total: float = 0.0
	for u: Dictionary in sim.units:
		total += appetite(sim, u)
	return total


func demand(sim) -> float:
	return float(sim.world_specs["townMeal"]["foodPerVillager"]) * shares(sim)


func tick(sim, dt: float) -> void:
	if sim.paused or not is_finite(dt) or dt <= 0.0 or dt > 1.0:
		return
	var meal: Dictionary = sim.world_specs["townMeal"]
	var food_need: float = demand(sim)
	meal_clock += dt
	if meal_clock >= float(meal["secondsPerDay"]):
		meal_clock -= float(meal["secondsPerDay"])
		_eat(sim, meal)
	if float(sim.resources.get("food", 0.0)) >= food_need or fed in ["well_fed", "feast"]:
		hunger = maxf(0.0, hunger - dt * 0.5)
	var housed: float = minf(1.0, float(sim.beds()) / maxf(1.0, float(sim.units.size())))
	var target: float = clampf(70.0 - hunger * 0.5 - (1.0 - housed) * 25.0, 0.0, 70.0)
	if fed == "feast":
		target = minf(100.0, target + FEAST_MORALE)
	morale = move_toward(morale, target, dt * 0.2)


func _eat(sim, meal: Dictionary) -> void:
	var portions: float = shares(sim)
	if portions <= 0.0:
		fed = "fed"
		missed = 0
		return
	var per_bread: float = float(meal.get("breadPerVillager", 1))
	var per_food: float = float(meal["foodPerVillager"])
	# Bread first, whole portions only; the rest from plain food.
	var bread_portions: float = minf(portions, floorf(float(sim.resources.get("bread", 0.0)) / maxf(0.001, per_bread)))
	sim.resources["bread"] = maxf(0.0, float(sim.resources.get("bread", 0.0)) - bread_portions * per_bread)
	var food_need: float = (portions - bread_portions) * per_food
	var paid: float = minf(food_need, float(sim.resources.get("food", 0.0)))
	sim.resources["food"] = maxf(0.0, float(sim.resources.get("food", 0.0)) - paid)
	if paid < food_need:
		var short: float = (food_need - paid) / maxf(1.0, portions * per_food)
		hunger = minf(100.0, hunger + 25.0 * short)
		missed += 1
		fed = "short"
		_starve(sim)
		return
	missed = 0
	fed = "well_fed" if bread_portions >= portions else "fed"
	var feast_need: int = ceili(float(sim.units.size()) / FEAST_PER)
	if fed == "well_fed" and float(sim.resources.get("feast-supplies", 0.0)) >= feast_need:
		sim.resources["feast-supplies"] = float(sim.resources["feast-supplies"]) - feast_need
		fed = "feast"
		sim.notice = "A feast in the Hall / the village is merry tonight."


func _starve(sim) -> void:
	if missed < STARVE_IDLE:
		sim.notice = "Food shortage. Another missed meal and villagers stop working."
		return
	if missed < STARVE_LEAVE:
		sim.notice = "The village is starving and works at half pace. Bring in food or bread."
		return
	# Someone gives up and leaves: a gatherer or crafter first, a fighter last.
	var leaving: int = -1
	for i in sim.units.size():
		var u: Dictionary = sim.units[i]
		if str(sim.troop_specs[u["type"]].get("role", "")) != "combat":
			leaving = i
	if leaving < 0 and sim.units.size() > 1:
		leaving = sim.units.size() - 1
	if leaving >= 0 and sim.units.size() > 1:
		var gone: Dictionary = sim.units[leaving]
		sim.units.remove_at(leaving)
		sim.revision += 1
		sim.notice = "Starving, a %s leaves the village." % str(sim.troop_specs[gone["type"]].get("name", gone["type"])).to_lower()
	else:
		sim.notice = "The village is starving. Bring in food or bread."


func starving() -> bool:
	return missed >= STARVE_IDLE


func well_fed() -> bool:
	return fed in ["well_fed", "feast"]


# The authored townMeal.wellFed bonus for one effect ("gather", "xp", "heal"), or 0.
func fed_bonus(sim, effect: String) -> float:
	if not well_fed():
		return 0.0
	return float(sim.world_specs["townMeal"].get("wellFed", {}).get("effects", {}).get(effect, 0.0))


# Newcomers arrive faster in a well-fed village (townMeal.wellFed.growth), faster still after a feast.
func growth_multiplier(sim) -> float:
	if not well_fed():
		return 1.0
	var growth: float = float(sim.world_specs["townMeal"].get("wellFed", {}).get("growth", 0.0))
	return 1.0 + growth * (2.0 if fed == "feast" else 1.0)


func production_multiplier() -> float:
	var base: float = clampf(1.0 - hunger * 0.002 - maxf(0.0, 70.0 - morale) * 0.001, 0.75, 1.0)
	return base * (0.5 if starving() else 1.0)


func summary(sim) -> String:
	var status: String = "Fed"
	if starving():
		status = "Starving"
	elif hunger > 0.0:
		status = "Food shortage"
	elif sim.units.size() > sim.beds():
		status = "More homes needed"
	elif fed == "feast":
		status = "Feasting"
	elif fed == "well_fed":
		status = "Well fed"
	elif float(sim.resources.get("food", 0.0)) < demand(sim) and float(sim.resources.get("bread", 0.0)) < float(sim.units.size()):
		status = "Food running low"
	return "%s · %d morale · %d of %d beds" % [status, int(morale), sim.units.size(), sim.beds()]


func state() -> Dictionary:
	return {"hunger": hunger, "morale": morale, "meal_clock": meal_clock, "missed": missed, "fed": fed}


func valid(data: Variant, meal_seconds: float) -> bool:
	if not data is Dictionary:
		return false
	for field: String in ["hunger", "morale", "meal_clock"]:
		var value: Variant = data.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
			return false
	if data.has("missed") and (not (data["missed"] is int or data["missed"] is float) or float(data["missed"]) < 0.0 or float(data["missed"]) > 1000.0):
		return false
	if data.has("fed") and str(data["fed"]) not in ["fed", "well_fed", "feast", "short"]:
		return false
	return float(data["hunger"]) <= 100.0 and float(data["morale"]) <= 100.0 and float(data["meal_clock"]) < meal_seconds


func restore(data: Dictionary) -> void:
	hunger = float(data["hunger"])
	morale = float(data["morale"])
	meal_clock = float(data["meal_clock"])
	missed = int(data.get("missed", 0))
	fed = str(data.get("fed", "fed"))
