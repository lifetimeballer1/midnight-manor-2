extends SceneTree

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
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	var cells: Dictionary = game.sim.living.cells
	for x in range(4, 12):
		cells["%d,9" % x] = {"wear": 1.0, "last": game.sim.elapsed, "stone": x > 6}
	game.sim.living.revision += 1
	await process_frame
	await process_frame

	check(is_instance_valid(game._road_overlay) and game._road_overlay.visible, "the road map draws")
	check(game._road_material.shader.resource_path.ends_with("road_autumn.gdshader"), "roads use the autumn shader")
	check(game._road_material.get_shader_parameter("cobble_tex") != null, "cobble texture survives the shader swap")
	var stone: Color = game._road_material.get_shader_parameter("stone_tint")
	check(stone.r > stone.b, "stone is tinted warm, not grey-blue")
	check(absf(game.ROAD_WIDTH - 1.3) < 0.001, "paved road is a little wider")
	check(float(game._road_material.get_shader_parameter("detail")) == (0.0 if game._sky_is_phone() else 1.0), "road detail follows the device budget")
	check(game._road_overlay.mesh is PlaneMesh and (game._road_overlay.mesh as PlaneMesh).size.x > 0.0, "road overlay is sized to the network")
	game.rain_level = 0.9
	game.rain_target = 0.9
	await process_frame
	check(float(game._road_material.get_shader_parameter("rain_gloss")) > 0.5, "rain still feeds the road shader")

	print("ROADFX ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
