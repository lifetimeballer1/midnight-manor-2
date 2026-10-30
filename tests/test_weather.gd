extends SceneTree

# Weather (The Manor Endures, D3), looks only: the weather clock brings rain, fog and snow in turn,
# each one changes only the view (haze, light, flakes, a pale dusting), never the sim, and a new
# spell waits for the last one to clear.

const Weather = preload("res://scripts/game/manor_weather.gd")
var checks: int = 0
var failures: Array[String] = []
var game


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func settle(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func ramp(weather, seconds: float) -> void:
	# Runs the weather clock faster than real time.
	for i in int(seconds * 10.0):
		weather._process(0.1)
		game._update_weather(0.1)


func _run() -> void:
	root.size = Vector2i(390, 844)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	var weather = game.weather
	check(weather != null and weather.get_parent() == game, "weather is a child node of the game")
	game._enter_village()
	game.paused = false
	game.focused = true
	game.sim.next_raid_at = 1.0e9
	await settle(0.3)
	check(weather.kind == "clear" and weather.clock > 100.0, "a village opens under a clear sky")

	# The clock picks rain, fog and snow over many spells.
	var seen: Dictionary = {}
	var probe = Weather.new()
	for i in 200:
		seen[probe._pick()] = true
	probe.free()
	check(seen.has("rain") and seen.has("fog") and seen.has("snow"), "all three kinds of weather come (%s)" % [seen.keys()])

	var plain_density: float = game.environment.fog_density
	var plain_begin: float = game.environment.fog_depth_begin
	var sim_before: Dictionary = JSON.parse_string(JSON.stringify(game.sim.export_state()))

	# Rain: the game's own rain falls when the weather says so.
	weather.force("rain", 30.0, 1.0)
	ramp(weather, 10.0)
	check(game.rain_level > 0.9 and game.rain.emitting, "rain falls (%.2f)" % game.rain_level)
	weather.force("fog", 30.0, 1.0)
	ramp(weather, 3.0)
	check(weather.fog_level < 0.01, "fog waits for the rain to clear")
	ramp(weather, 20.0)
	check(game.rain_level < 0.02 and weather.fog_level > 0.9, "then the fog rolls in (%.2f)" % weather.fog_level)
	game._apply_lighting()
	check(game.environment.fog_depth_begin < plain_begin - 20.0 and game.environment.fog_density > plain_density, "fog closes in the haze (begin %.1f, density %.2f)" % [game.environment.fog_depth_begin, game.environment.fog_density])

	# Snow.
	weather.force("snow", 30.0, 1.0)
	ramp(weather, 20.0)
	check(weather.fog_level < 0.01 and weather.snow_level > 0.9, "snow follows once the fog lifts")
	var flakes_on: bool = weather.snow.emitting and weather.snow.visible
	check(flakes_on, "snowflakes fall")
	check(weather.frost.visible and weather._frost_material.albedo_color.a > 0.25, "snow lays a frost on the ground")
	weather.force("clear", 200.0)
	ramp(weather, 10.0)
	check(not weather.snow.emitting and weather.snow_level < 0.01, "the snow stops")
	check(not weather.frost.visible, "the frost melts away")
	game._apply_lighting()
	check(absf(game.environment.fog_depth_begin - plain_begin) < 0.5, "a clear sky brings the haze back")

	# Looks only: the sim never sees the weather.
	var sim_after: Dictionary = JSON.parse_string(JSON.stringify(game.sim.export_state()))
	check(sim_after["resources"] == sim_before["resources"] and sim_after["buildings"].size() == sim_before["buildings"].size(), "weather does not touch the village")

	# Phones and low quality get fewer flakes; battery saver gets none.
	game.quality = "low"
	weather.force("snow", 30.0)
	weather.snow.emitting = false
	ramp(weather, 10.0)
	check(weather.snow.amount == Weather.FLAKES_LITE, "low quality has fewer flakes")
	game.battery_saver = true
	ramp(weather, 0.2)
	check(not weather.snow.emitting, "battery saver has no flakes")
	game.battery_saver = false
	game.queue_free()
	await process_frame
	print("WEATHER ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
