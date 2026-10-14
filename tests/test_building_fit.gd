extends SceneTree

# Building fit layer (village_building_fit.gd): every non-defense building sits flat, lights come
# from a visible lantern, brazier or glow, the types without their own art get a composition that
# fills the plot, and smoke rises from real chimneys. Never saves; works on a scratch village.

const DEFENSES: Array[String] = ["wall", "stonewall", "gate", "rampart", "tower", "archer_tower",
	"ballista", "bastion", "trap", "fire-trap", "watchfire"]
const BUILT: Array[String] = ["lantern-rows", "shieldwall-yard", "stone-road", "manor-gardens"]

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func _run() -> void:
	root.size = Vector2i(960, 720)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)
	var sim = game.sim
	check(game.get("_fit_on") == true, "the building fit layer is in the chain and on")

	# Lay every non-defense type out on a scratch grid (sim only; nothing is saved).
	for b: Dictionary in sim.buildings.duplicate():
		if str(b["type"]) != "hall":
			sim.buildings.erase(b)
	var types: Array = sim.building_specs.keys()
	types.sort()
	var x: int = 0
	var y: int = 0
	var placed: Array[Dictionary] = []
	for type_name: String in types:
		if type_name in DEFENSES or type_name == "hall":
			continue
		var b: Dictionary = sim._new_building(type_name, x, y, false)
		b["tier"] = (sim.building_specs[type_name]["tiers"] as Array).size()
		sim.buildings.append(b)
		placed.append(b)
		x += 3
		if x > 60:
			x = 0
			y += 3
	sim.revision += 1
	var started: int = Time.get_ticks_msec()
	game._rebuild_buildings()
	var cost: int = Time.get_ticks_msec() - started
	print("rebuild of %d buildings: %d ms" % [placed.size() + 1, cost])

	var lanterns: int = 0
	for b: Dictionary in placed:
		var type_name: String = str(b["type"])
		var view: Dictionary = game.building_views.get(int(b["id"]), {})
		check(view.has("fit"), "%s is dressed" % type_name)
		if view.is_empty():
			continue
		var model: Node3D = view["model"]
		check(is_zero_approx(model.rotation.z), "%s sits flat on its plot" % type_name)
		check(not view.has("windows"), "%s has no floating window dots" % type_name)
		var glow: Node3D = view.get("glow")
		if is_instance_valid(glow):
			check(not glow.is_visible_in_tree(), "%s's floating glow disc is parked" % type_name)
		var lamp: Node3D = view.get("lamp")
		if is_instance_valid(lamp):
			check(model.is_ancestor_of(lamp), "%s's lamp moves with the building" % type_name)
			# On the flame for one source; between them where several (braziers, a row of lanterns,
			# berries) share one light.
			var source: bool = false
			for node in model.find_children("Fit*", "", true, false):
				if node is Node3D and (str(node.name).begins_with("FitFlame") or str(node.name).begins_with("FitBerry") or str(node.name).begins_with("FitLantern") or str(node.name).begins_with("FitForge")):
					if (node as Node3D).global_position.distance_to(lamp.global_position) < 1.5:
						source = true
						break
			check(source, "%s's light comes from something visible" % type_name)
		lanterns += model.find_children("FitLantern", "", true, false).size()
		if type_name in BUILT:
			var shown: int = 0
			for part in model.get_children():
				if part is MeshInstance3D and str(part.name).begins_with("MMR") and (part as MeshInstance3D).visible:
					shown += 1
			check(shown == 0, "%s replaces its stand-in art" % type_name)
			check((model.find_child("BuildingFit", false, false) as Node).find_children("*", "MeshInstance3D", true, false).size() >= 20, "%s is built out to fill its plot" % type_name)
		if type_name in ["pond", "blackwater-weir", "deephole"]:
			check(not model.find_children("FitWater", "", true, false).is_empty(), "%s holds water" % type_name)
	check(lanterns >= 30, "houses and works carry lanterns (%d)" % lanterns)

	# Smoke from real chimneys: the cottage has one, the barracks does not.
	var cottage: Dictionary = {}
	var barracks: Dictionary = {}
	for b: Dictionary in placed:
		if str(b["type"]) == "cottage": cottage = b
		if str(b["type"]) == "barracks": barracks = b
	var cottage_view: Dictionary = game.building_views[int(cottage["id"])]
	check(cottage_view["fit"].get("chimney") != null, "the cottage's chimney is found")
	check(barracks.is_empty() or game.building_views[int(barracks["id"])]["fit"].get("chimney") == null, "the barracks has no chimney to smoke")

	# Probes are cached: a second rebuild of the same kinds is cheaper.
	for b: Dictionary in placed:
		b["x"] = int(b["x"])
	sim.revision += 1
	for id: Variant in game.building_views.keys():
		game.building_views[id]["signature"] = "stale"
	started = Time.get_ticks_msec()
	game._rebuild_buildings()
	var again: int = Time.get_ticks_msec() - started
	print("cached rebuild: %d ms" % again)
	check(again <= cost + 50, "cached rebuild is not slower (%d ms vs %d ms)" % [again, cost])

	print("BUILDING_FIT %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
