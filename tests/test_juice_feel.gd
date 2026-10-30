extends SceneTree

# Juice (The Manor Endures, D2): the phone buzzes on raid hits, a fallen building, a raid's end and
# milestones (never when Vibration is off or the game is paused), a finished building pops once and
# settles at full size, and villagers on screen show small emotes that fit the moment.

const Feel = preload("res://scripts/game/manor_feel.gd")
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


func kinds(feel) -> Array:
	var out: Array = []
	for b: Dictionary in feel.buzzes:
		out.append(str(b["kind"]))
	return out


func _run() -> void:
	# The pop curve starts squashed, stretches past full height and ends at rest.
	var start: Vector3 = Feel.pop_scale(0.0)
	check(start.y < 0.8 and start.x > 1.1, "a pop starts squashed")
	var tallest: float = 0.0
	for i in 40:
		tallest = maxf(tallest, Feel.pop_scale(i * 0.0175).y)
	check(tallest > 1.08, "a pop springs taller than full height (%.2f)" % tallest)
	check(Feel.pop_scale(0.7).distance_to(Vector3.ONE) < 0.03, "a pop settles")
	for kind: String in Feel.EMOTES:
		var image: Image = Feel._draw(kind)
		var inked: int = 0
		for y in range(8, 52):
			for x in range(8, 56):
				var c: Color = image.get_pixel(x, y)
				if c.a > 0.9 and c.get_luminance() < 0.6:
					inked += 1
		check(inked > 40, "the %s emote has a drawn sign (%d px)" % [kind, inked])

	root.size = Vector2i(390, 844)
	game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	var feel = game.feel
	check(feel != null and feel.get_parent() == game, "juice is a child node of the game")
	check(game.vibration, "vibration is on by default")
	game._enter_village()
	game.paused = false
	game.focused = true
	game.sim.next_raid_at = 1.0e9
	await settle(0.5)

	# Raid hits and a fallen building buzz, through the game's own event pass.
	var hall: Dictionary = game.sim._hall()
	game.sim.events.append({"kind": "hit", "x": 10.0, "y": 8.0, "amount": 12.0, "friendly": true})
	game.sim.events.append({"kind": "hit", "x": 10.0, "y": 8.0, "amount": 12.0, "friendly": true})
	game.sim.events.append({"kind": "destroyed", "x": 10.0, "y": 8.0})
	await settle(0.2)
	check(kinds(feel).count("hit") == 1, "a raid hit buzzes, but not twice in a row (%s)" % [kinds(feel)])
	check(kinds(feel).has("destroyed"), "a fallen building buzzes")
	game.sim.events.append({"kind": "hit", "x": 10.0, "y": 8.0, "amount": 12.0, "friendly": false})
	await settle(0.2)
	check(kinds(feel).count("hit") == 1, "our own hits on raiders do not buzz")
	game.sim.events.append({"kind": "raid_result", "victory": true})
	await settle(0.2)
	check(kinds(feel).has("raid_result"), "the end of a raid buzzes")

	# Milestones buzz.
	feel.buzzes.clear()
	game.sim.chronicle.act += 1
	await settle(0.2)
	check(kinds(feel).has("milestone"), "a new Chronicle act buzzes")

	# A finished building pops once and settles at full size.
	var site: Dictionary = {}
	for b: Dictionary in game.sim.buildings:
		if str(b["type"]) not in ["hall", "wall"] and float(b["hp"]) > 0.0:
			site = b
			break
	var id: int = int(site["id"])
	site["remaining"] = 5.0
	await settle(0.3)
	feel.buzzes.clear()
	site["remaining"] = 0.0
	site["tier"] = int(site["tier"]) + 1
	game.selected_building = -1
	var squashed: bool = false
	var until: int = Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < until:
		await process_frame
		var view: Dictionary = game.building_views.get(id, {})
		if not view.is_empty() and is_instance_valid(view["root"]) and (view["root"] as Node3D).scale.distance_to(Vector3.ONE) > 0.05:
			squashed = true
	check(squashed, "a finished building pops")
	check(kinds(feel).has("built"), "a finished building buzzes")
	await settle(1.0)
	var root_node: Node3D = game.building_views[id]["root"]
	check(root_node.scale.distance_to(Vector3.ONE) < 0.001, "the building settles at full size")
	check(feel.pops.is_empty(), "the pop is done")

	# Emotes fit the moment.
	var villager: Dictionary = {}
	for u: Dictionary in game.sim.units:
		if str(game.sim.troop_specs[str(u["type"])]["role"]) != "combat":
			villager = u
			break
	feel._cheer_until = -100.0
	game.day_blend = 0.9
	villager["phase"] = "work"
	check(feel.emote_for(game.sim, villager) == "note", "a villager at work by day hums")
	game.day_blend = 0.1
	villager["phase"] = "idle"
	check(feel.emote_for(game.sim, villager) == "sleep", "an idle villager at night dozes")
	game.sim.raid_warning = true
	check(feel.emote_for(game.sim, villager) == "alarm", "the horns bring alarm")
	game.sim.raid_warning = false
	feel._cheer_until = feel._clock + 5.0
	check(feel.emote_for(game.sim, villager) in ["heart", "star"], "a won raid or finished build cheers")
	feel._emote_clock = 99.0
	check(feel.show_emote(int(villager["id"]), "heart"), "an emote shows over a villager")
	var live: Dictionary = feel.emotes[-1]
	var sprite: Sprite3D = live["sprite"]
	var model: Node3D = game.actors[int(villager["id"])]["model"]
	await settle(0.3)
	check(sprite.visible and sprite.global_position.y > model.global_position.y + 2.0, "the emote floats above the villager's head")
	await settle(Feel.EMOTE_SECONDS)
	check(not sprite.visible and feel.emotes.size() <= 1, "the emote fades and goes back to the pool")
	feel.emotes.clear()
	feel.shown.clear()
	feel._emote_clock = 0.0
	game.day_blend = 0.9
	await settle(6.0)
	var total: int = 0
	for k: String in feel.shown:
		total += int(feel.shown[k])
	check(total >= 1, "villagers emote on their own (%s)" % [feel.shown])

	# Vibration off, or a paused game, never buzzes.
	game._toggle_vibration()
	check(not game.vibration, "Vibration turns off")
	feel.buzzes.clear()
	game.sim.events.append({"kind": "destroyed", "x": 10.0, "y": 8.0})
	await settle(0.2)
	check(feel.buzzes.is_empty(), "Vibration off means no buzz")
	game._toggle_vibration()
	game.sim.paused = true
	check(not feel.buzz("milestone", 50), "a paused game does not buzz")
	game.queue_free()
	await process_frame
	print("JUICE_FEEL ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
