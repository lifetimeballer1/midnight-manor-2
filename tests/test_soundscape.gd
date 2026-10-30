extends SceneTree

# The soundscape (The Manor Endures, D1): day and night beds follow the sky, drums play during a raid,
# a fanfare greets a finished building, work near the camera is heard, and the Sound switch silences
# all of it. Fresh village, never saves. Runs on the dummy audio driver, so it checks what plays.

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


# Moves the sky to noon or midnight (village_game._day_blend reads elapsed + cycle_offset).
func day(noon: bool) -> void:
	var pos: float = 0.7 if noon else 0.2
	game.cycle_offset = pos * game.DAY_LENGTH - fmod(game.sim.elapsed, game.DAY_LENGTH)


func _run() -> void:
	for path: String in ["day", "night", "owl", "water", "fanfare", "war_drums"]:
		check(ResourceLoader.exists("res://audio/ambience/%s.ogg" % path), "%s sound is imported" % path)
	root.size = Vector2i(390, 844)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	var scape = game.soundscape
	check(scape != null and scape.get_parent() == game, "the soundscape is a child node of the game")
	check(not scape.day_bed.playing and not scape.night_bed.playing, "the title screen is quiet")
	game.sound = true
	game._enter_village()
	game.paused = false
	game.focused = true
	day(true)
	await settle(1.6)
	check(scape.day_bed.playing and scape.day_bed.volume_db > -30.0, "daytime birds play (%.1f dB)" % scape.day_bed.volume_db)
	check(not scape.night_bed.playing or scape.night_bed.volume_db < -50.0, "crickets are silent at noon")
	day(false)
	await settle(1.6)
	check(scape.night_bed.playing and scape.night_bed.volume_db > -30.0, "crickets play at night (%.1f dB)" % scape.night_bed.volume_db)
	check(not scape.day_bed.playing or scape.day_bed.volume_db < -50.0, "birds rest at night")
	day(true)

	# A raid brings the drums.
	game.sim.completed_quests.append("the-first-horn")
	game.sim.start_raid()
	var waited: int = 0
	while not game.sim.raid_active and waited < 400:
		await process_frame
		waited += 1
	await settle(2.5)
	check(game.sim.raid_active, "the called raid arrives")
	check(scape.drums.playing and scape.drums.volume_db > -20.0, "war drums play during a raid (%.1f dB)" % scape.drums.volume_db)
	game.sim.enemies.clear()
	game.sim._finish_raid(true)
	await settle(2.4)
	check(not scape.drums.playing, "the drums stop when the raid ends")

	# A building that finishes gets a fanfare.
	var site: Dictionary = {}
	for b: Dictionary in game.sim.buildings:
		if str(b["type"]) != "hall":
			site = b
			break
	site["remaining"] = 5.0
	await settle(0.2)
	site["remaining"] = 0.0
	await settle(0.2)
	check(str(scape._last_heard).ends_with("fanfare.ogg"), "a finished building gets a fanfare (%s)" % scape._last_heard)

	# Work near the camera is heard.
	var lumber: Dictionary = {}
	for b: Dictionary in game.sim.buildings:
		if str(b["type"]) == "lumber" and float(b["hp"]) > 0.0:
			lumber = b
	if not lumber.is_empty():
		for u: Dictionary in game.sim.units:
			if int(u["workplace"]) == int(lumber["id"]):
				u["phase"] = "work"
		game.target = game.world_position(game.sim.center(lumber), 0.0)
		scape._last_heard = ""
		scape._work_clock = 0.0
		scape._play_work(game.sim, 1.0)
		check(str(scape._last_heard).ends_with("chop.ogg") or not scape._staffed(game.sim, lumber), "a working lumber camp is heard near the camera (%s)" % scape._last_heard)

	# The Sound switch silences everything.
	game._toggle_sound()
	await settle(2.4)
	check(not game.sound, "sound is off")
	check(not scape.day_bed.playing and not scape.night_bed.playing and not scape.drums.playing, "Sound off silences the beds and drums")
	game.queue_free()
	await process_frame
	print("SOUNDSCAPE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
