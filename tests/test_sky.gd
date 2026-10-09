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


func _set_time(game: Node, pos: float) -> void:
	game.cycle_offset = pos * game.DAY_LENGTH - game.sim.elapsed


func _run() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()

	check(game.get("_sky_material") != null, "the sky layer is in the chain")
	check(is_instance_valid(game._sky_backdrop) and game._sky_backdrop.get_parent() == game.camera, "sky backdrop rides the camera")
	check(game._sky_material.shader != null and game._sky_shadow_material.shader != null and game._sky_birds_material.shader != null, "sky shaders loaded")
	check(game._sky_backdrop.position.z > -game.camera.far and game._sky_backdrop.position.z < -game.camera.far * 0.9, "backdrop sits at the far end of the frustum")
	check(game._sky_shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "cloud shadow quad casts no shadow")

	# Old sky pieces are flat but alive so the dusk and moon layers can keep fading them.
	check(game.stars.scale == Vector3.ZERO and game.moon.scale == Vector3.ZERO, "old stars and moon quad are shrunk")
	var all_clouds_flat: bool = true
	for shade in game.clouds:
		all_clouds_flat = all_clouds_flat and (shade as Node3D).scale == Vector3.ZERO
	check(all_clouds_flat, "old cloud shade quads are shrunk")

	# Day palette, then night palette.
	_set_time(game, 0.70)
	await process_frame
	await process_frame
	var day_hor: Color = game._sky_params["hor_col"]
	check(float(game._sky_params["star_amt"]) < 0.01 and float(game._sky_params["moon_amt"]) < 0.01, "no stars or moon by day")
	check(game._sky_shadow.visible and float(game._sky_shadow_material.get_shader_parameter("strength")) > 0.5, "cloud shadows drift by day")
	check(game._sky_birds.visible, "birds fly by day")
	_set_time(game, 0.0)
	await process_frame
	await process_frame
	var night_hor: Color = game._sky_params["hor_col"]
	check(not game._sky_wash.visible, "no golden wash at night")
	check(float(game._sky_params["star_amt"]) > 0.9, "stars shine at night")
	check(not game._sky_shadow.visible and not game._sky_birds.visible, "no cloud shadows or birds at night")
	check(day_hor.get_luminance() > night_hor.get_luminance() * 3.0, "horizon is much brighter by day")

	# Dusk blazes warm.
	_set_time(game, 0.58)
	await process_frame
	await process_frame
	var dusk_hor: Color = game._sky_params["hor_col"]
	check(dusk_hor.r > dusk_hor.b + 0.15 and float(game._sky_params["glow_amt"]) > 0.2, "dusk horizon glows orange")

	check(game._sky_wash.visible and float(game._sky_wash_material.get_shader_parameter("amount")) > 0.4, "golden wash glows at dusk")
	check(game.sun.light_color.r > game.sun.light_color.b + 0.25, "the dusk sun is golden")
	_set_time(game, 0.70)
	await process_frame
	await process_frame
	check(not game._sky_wash.visible, "no golden wash at midday")
	_set_time(game, 0.58)
	await process_frame
	await process_frame

	# Camera tilt moves the horizon: a low camera shows more sky.
	game.tilt = 0.32
	await process_frame
	var low_horizon: float = float(game._sky_params["horizon"])
	game.tilt = 1.2
	await process_frame
	var high_horizon: float = float(game._sky_params["horizon"])
	check(low_horizon > high_horizon + 0.3, "tilting the camera down lifts the horizon on screen")

	# Rain greys the sky and thickens the cloud.
	_set_time(game, 0.70)
	game.rain_level = 0.0
	await process_frame
	await process_frame
	var dry_cover: float = float(game._sky_params["cover"])
	var dry_sat: float = (game._sky_params["zen_col"] as Color).s
	game.rain_target = 1.0
	game.rain_level = 1.0
	await process_frame
	game.rain_target = 1.0
	game.rain_level = 1.0
	await process_frame
	check(float(game._sky_params["cover"]) > dry_cover + 0.2, "rain thickens the cloud")
	check((game._sky_params["zen_col"] as Color).s < dry_sat, "rain drains the colour from the sky")
	check(not game._sky_birds.visible, "birds shelter in the rain")
	game.rain_level = 0.0

	# Lightning: only in heavy rain, and it flashes the sky and the view.
	game.rain_target = 1.0
	game.rain_level = 1.0
	game._sky_flash_t = 9.0
	game._sky_flash_in = 0.0
	await process_frame
	check(float(game._sky_material.get_shader_parameter("flash")) > 0.5 and game._sky_wash.visible, "lightning flashes in heavy rain")
	game._sky_flash_t = 9.0
	await process_frame
	check(float(game._sky_material.get_shader_parameter("flash")) < 0.01, "the flash dies away")
	game.rain_target = 0.0
	game.rain_level = 0.0
	game._sky_flash_t = 9.0
	game._sky_flash_in = 0.0
	await process_frame
	await process_frame
	check(game._sky_flash_t > 1.0, "no lightning in clear weather")

	# Raid alarm glows along the horizon while a raid lasts.
	game.sim.paused = true
	game.sim.raid_active = true
	for i in 20:
		game.sim.raid_active = true
		await process_frame
	check(game._sky_alarm > 0.0 and float(game._sky_material.get_shader_parameter("alarm")) > 0.0, "a raid lights the horizon")
	game._sky_alarm = 0.0
	game.sim.raid_active = false

	# Blood moon: the sky reddens while the blood raid lasts.
	_set_time(game, 0.0)
	game.sim.paused = true
	game.sim.moon_phase = 4
	game.sim.raid_active = true
	for i in 20:
		game.sim.raid_active = true
		game.sim.moon_phase = 4
		await process_frame
	check(game._sky_blood > 0.0, "a blood-moon raid starts reddening the sky")
	game._sky_blood = 1.0
	game._sky_sig = []
	game.sim.raid_active = true
	game.sim.moon_phase = 4
	await process_frame
	var blood_zen: Color = game._sky_params["zen_col"]
	check(blood_zen.r > blood_zen.b, "the blood moon turns the sky red")
	check(absf(float(game._sky_params["moon_phase"]) - 0.5) < 0.01, "the full moon reaches the shader")
	game.sim.raid_active = false
	game.sim.moon_phase = 0

	# Phone budget.
	var per_flock: int = game.BIRDS_PER_FLOCK_LOW if game._sky_is_phone() else game.BIRDS_PER_FLOCK
	check(int(game._sky_stats["birds"]) == per_flock * 2, "bird count follows the device budget")
	check(int(game._sky_stats["birds"]) <= 14, "no more than 14 birds")
	game.low_power = true
	check(game._sky_is_phone(), "low_power counts as a phone")
	game.low_power = false

	print("SKY ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
