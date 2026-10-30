extends Node

# Juice (The Manor Endures, D2), a child node of the game rather than another layer in the chain.
#   * Phone buzz: a short vibration when a raid hits the village, when a building falls, when a
#     warlord arrives, when a raid ends, and on milestones (a building finished, a Hall level, a new
#     Chronicle act, the Vale united). Android phones buzz; iPhones and desktops ignore it. It can be
#     turned off in Pause, and it never buzzes while the game is paused or in the background.
#   * Pop: a finished build or upgrade squashes and springs back up once.
#   * Emotes: now and then a villager on screen shows a small sign above their head: a note while
#     they work by day, "z" while idle at night, "!" when the horns sound, a heart or a star after a
#     raid is won or a building finishes.
# Everything here reads the game and sim and changes only view nodes. It never touches the sim.

const BUZZ_GAP: float = 0.7          # seconds between two buzzes of the same kind
const HIT_BUZZ_GAP: float = 1.2
const POP_SECONDS: float = 0.7
const EMOTE_EVERY: float = 1.6       # seconds between emotes (phones and low quality: x1.6)
const EMOTE_SECONDS: float = 1.8
const EMOTE_SLOTS: int = 6
const EMOTE_SLOTS_LITE: int = 3
const EMOTE_HEIGHT: float = 2.3
const CHEER_SECONDS: float = 10.0    # how long villagers stay cheerful after a win or a finished build
const EMOTES: Array[String] = ["note", "sleep", "alarm", "heart", "star"]

var game: Node
var buzzes: Array[Dictionary] = []          # for tests: every buzz asked for {kind, ms}
var pops: Dictionary = {}                   # building id -> {root, age}
var emotes: Array[Dictionary] = []          # live emotes {sprite, unit, age}
var shown: Dictionary = {}                  # for tests: emote kind -> times shown
var _last_buzz: Dictionary = {}             # kind -> time (seconds)
var _clock: float = 0.0
var _emote_clock: float = 0.0
var _cheer_until: float = -100.0
var _seen_tiers: Dictionary = {}
var _tracked_sim: Object = null
var _last_level: int = -1
var _last_act: int = -1
var _last_vale: bool = false
var _textures: Dictionary = {}
var _pool: Array[Sprite3D] = []
var _rng := RandomNumberGenerator.new()


func setup(owner_game: Node) -> void:
	game = owner_game
	_rng.seed = 2026
	for kind: String in EMOTES:
		_textures[kind] = ImageTexture.create_from_image(_draw(kind))


func _process(delta: float) -> void:
	if game == null or not game.started or is_instance_valid(game.battle_view):
		return
	_clock += delta
	var sim = game.sim
	_track(sim)
	if sim.paused:
		return
	_tend_pops(delta)
	_tend_emotes(delta)
	_watch_builds(sim)
	_watch_milestones(sim)
	_emote_clock -= delta
	if _emote_clock <= 0.0:
		_emote_clock = EMOTE_EVERY * (1.6 if game._quality_lite() else 1.0) * _rng.randf_range(0.7, 1.3)
		_try_emote(sim)


# --- Phone buzz --------------------------------------------------------------

# Read from the game's event pass, before the list is cleared.
func take_events(events: Array) -> void:
	for event: Dictionary in events:
		match str(event.get("kind", "")):
			"hit":
				# A hit flagged friendly is a raider striking the village.
				if bool(event.get("friendly", false)) and float(event.get("amount", 0.0)) > 0.0:
					buzz("hit", 18, HIT_BUZZ_GAP)
			"destroyed":
				buzz("destroyed", 70)
			"warlord":
				buzz("warlord", 90)
			"raid_result":
				var won: bool = bool(event.get("victory", false))
				buzz("raid_result", 45 if won else 140)
				if won:
					_cheer_until = _clock + CHEER_SECONDS


func buzz(kind: String, ms: int, gap: float = BUZZ_GAP) -> bool:
	if game == null or not bool(game.vibration) or game.sim.paused:
		return false
	if _clock - float(_last_buzz.get(kind, -100.0)) < gap:
		return false
	_last_buzz[kind] = _clock
	buzzes.append({"kind": kind, "ms": ms})
	if buzzes.size() > 40:
		buzzes.pop_front()
	Input.vibrate_handheld(ms)
	return true


# --- Milestones and finished builds ------------------------------------------

# A new game swaps in a fresh sim: start from what stands rather than celebrating all of it.
func _track(sim) -> void:
	if sim == _tracked_sim:
		return
	_tracked_sim = sim
	_seen_tiers.clear()
	_last_level = sim.village_level()
	_last_act = int(sim.chronicle.act)
	_last_vale = bool(sim.vale_united)
	for b: Dictionary in sim.buildings:
		_seen_tiers[int(b["id"])] = int(b["tier"]) if _finished(b) else 0


func _finished(b: Dictionary) -> bool:
	return float(b["remaining"]) <= 0.0 and float(b["hp"]) > 0.0


func _watch_builds(sim) -> void:
	var any: bool = false
	for b: Dictionary in sim.buildings:
		var id: int = int(b["id"])
		if not _seen_tiers.has(id):
			_seen_tiers[id] = int(b["tier"]) if _finished(b) else 0
			continue
		if not _finished(b) or int(b["tier"]) <= int(_seen_tiers[id]):
			continue
		_seen_tiers[id] = int(b["tier"])
		pop(id)
		any = true
	if any:
		buzz("built", 25)
		_cheer_until = _clock + CHEER_SECONDS


func _watch_milestones(sim) -> void:
	var level: int = sim.village_level()
	if level > _last_level:
		buzz("milestone", 60)
	_last_level = level
	var act: int = int(sim.chronicle.act)
	if act > _last_act:
		buzz("milestone", 60)
	_last_act = act
	if bool(sim.vale_united) and not _last_vale:
		buzz("milestone", 120)
	_last_vale = bool(sim.vale_united)


# --- Pop ---------------------------------------------------------------------

func pop(id: int) -> void:
	pops[id] = {"root": null, "age": 0.0}


func _tend_pops(delta: float) -> void:
	for id: int in pops.keys():
		var record: Dictionary = pops[id]
		var view: Dictionary = game.building_views.get(id, {})
		var root: Node3D = view.get("root") as Node3D if not view.is_empty() else null
		if not is_instance_valid(root):
			record["age"] = float(record["age"]) + delta
			if float(record["age"]) > 2.0:
				pops.erase(id)
			continue
		# The view may be rebuilt for the new tier: follow the newest root, settle the old one.
		if record["root"] != root:
			if is_instance_valid(record["root"]):
				(record["root"] as Node3D).scale = Vector3.ONE
			record["root"] = root
			record["age"] = 0.0
		# The selection bounce owns a selected building's scale.
		if int(game.selected_building) == id:
			root.scale = Vector3.ONE
			pops.erase(id)
			continue
		record["age"] = float(record["age"]) + delta
		var t: float = float(record["age"])
		if t >= POP_SECONDS:
			root.scale = Vector3.ONE
			pops.erase(id)
			continue
		root.scale = pop_scale(t)


# Starts squashed, springs taller than full height, then settles.
static func pop_scale(t: float) -> Vector3:
	var wobble: float = exp(-6.0 * t) * cos(16.0 * t)
	return Vector3(1.0 + 0.12 * wobble, 1.0 - 0.25 * wobble, 1.0 + 0.12 * wobble)


# --- Emotes ------------------------------------------------------------------

func emote_for(sim, u: Dictionary) -> String:
	if sim.raid_warning or sim.raid_active:
		return "alarm"
	if _clock < _cheer_until:
		return "star" if _rng.randf() < 0.5 else "heart"
	var phase: String = str(u.get("phase", "idle"))
	var night: bool = float(game.day_blend) < 0.35
	if night:
		return "sleep" if phase == "idle" else ""
	if phase in ["work", "gather", "repair"]:
		return "note"
	if phase == "idle":
		return "heart" if _rng.randf() < 0.3 else "note"
	return ""


func _try_emote(sim) -> void:
	var slots: int = EMOTE_SLOTS_LITE if game._quality_lite() else EMOTE_SLOTS
	if emotes.size() >= slots or game.battery_saver:
		return
	var busy: Dictionary = {}
	for live: Dictionary in emotes:
		busy[int(live["unit"])] = true
	var choices: Array[Dictionary] = []
	for u: Dictionary in sim.units:
		if float(u["hp"]) <= 0.0 or busy.has(int(u["id"])):
			continue
		var spec: Dictionary = sim.troop_specs.get(str(u["type"]), {})
		if str(spec.get("role", "")) == "combat" and not (sim.raid_warning or sim.raid_active):
			continue
		var record: Dictionary = game.actors.get(int(u["id"]), {})
		if record.is_empty() or not is_instance_valid(record["model"]) or not (record["model"] as Node3D).visible:
			continue
		choices.append(u)
	if choices.is_empty():
		return
	var pick: Dictionary = choices[_rng.randi_range(0, choices.size() - 1)]
	var kind: String = emote_for(sim, pick)
	if kind.is_empty():
		return
	show_emote(int(pick["id"]), kind)


func show_emote(unit_id: int, kind: String) -> bool:
	var record: Dictionary = game.actors.get(unit_id, {})
	if record.is_empty() or not is_instance_valid(record["model"]) or not _textures.has(kind):
		return false
	var sprite: Sprite3D = _pool.pop_back() if not _pool.is_empty() else _new_sprite()
	sprite.texture = _textures[kind]
	sprite.visible = true
	sprite.modulate = Color(1, 1, 1, 0)
	emotes.append({"sprite": sprite, "unit": unit_id, "age": 0.0, "kind": kind})
	shown[kind] = int(shown.get(kind, 0)) + 1
	_place(emotes[-1])
	return true


func _new_sprite() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = "Emote"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.render_priority = 4
	sprite.pixel_size = 0.016
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(sprite)
	return sprite


func _tend_emotes(delta: float) -> void:
	for index in range(emotes.size() - 1, -1, -1):
		var live: Dictionary = emotes[index]
		live["age"] = float(live["age"]) + delta
		var record: Dictionary = game.actors.get(int(live["unit"]), {})
		var gone: bool = record.is_empty() or not is_instance_valid(record["model"]) or not (record["model"] as Node3D).visible
		if gone or float(live["age"]) >= EMOTE_SECONDS:
			var sprite: Sprite3D = live["sprite"]
			sprite.visible = false
			_pool.append(sprite)
			emotes.remove_at(index)
			continue
		_place(live)


func _place(live: Dictionary) -> void:
	var record: Dictionary = game.actors.get(int(live["unit"]), {})
	if record.is_empty() or not is_instance_valid(record["model"]):
		return
	var t: float = float(live["age"])
	var sprite: Sprite3D = live["sprite"]
	var grow: float = clampf(t / 0.18, 0.0, 1.0)
	var fade: float = clampf((EMOTE_SECONDS - t) / 0.4, 0.0, 1.0)
	sprite.modulate.a = minf(grow, fade)
	sprite.scale = Vector3.ONE * (0.6 + 0.4 * grow + 0.12 * sin(minf(t, 0.5) * TAU) * (1.0 - clampf(t * 2.0, 0.0, 1.0)))
	sprite.global_position = (record["model"] as Node3D).global_position + Vector3(0.0, EMOTE_HEIGHT + 0.35 * t, 0.0)


# A round speech bubble with a drawn sign, 64x64. Drawn here so no emoji font is needed on the web.
static func _draw(kind: String) -> Image:
	var size: int = 64
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var paper := Color("f6efdf")
	var ink := Color("2c2230")
	var c := Vector2(32.0, 30.0)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var a: float = clampf(27.0 - p.distance_to(c), 0.0, 1.0)
			# A small tail under the bubble.
			if y > 50 and y < 61 and absf(x + 0.5 - 30.0 + (y - 50) * 0.6) < (61 - y) * 0.45:
				a = 1.0
			var edge: float = clampf(p.distance_to(c) - 24.5, 0.0, 1.0)
			var colour: Color = paper.lerp(ink.lightened(0.15), edge * 0.8)
			colour.a = a
			image.set_pixel(x, y, colour)
	var mark: Color = ink
	match kind:
		"heart":
			mark = Color("d8344f")
		"star":
			mark = Color("e0a526")
		"alarm":
			mark = Color("c8281e")
		"sleep":
			mark = Color("3c5aa8")
	for y in size:
		for x in size:
			var u: float = (x + 0.5 - 32.0) / 14.0
			var v: float = (30.0 - (y + 0.5)) / 14.0
			if _inside(kind, u, v):
				image.set_pixel(x, y, mark)
	image.generate_mipmaps()
	return image


static func _inside(kind: String, u: float, v: float) -> bool:
	match kind:
		"heart":
			var hv: float = v + 0.15
			return pow(u * u + hv * hv - 0.55, 3.0) - u * u * hv * hv * hv < 0.0
		"star":
			var angle: float = atan2(v, u) + PI / 2.0
			var r: float = sqrt(u * u + v * v)
			var spike: float = 0.5 + 0.5 * cos(5.0 * angle)
			return r < 0.42 + 0.55 * pow(spike, 3.0)
		"alarm":
			return (absf(u) < 0.16 and v > -0.25 and v < 1.0) or Vector2(u, v + 0.62).length() < 0.2
		"note":
			var head: bool = Vector2((u + 0.25) * 1.2, v + 0.6).length() < 0.3
			var stem: bool = u > -0.02 and u < 0.12 and v > -0.6 and v < 0.95
			var flag: bool = u > 0.0 and u < 0.55 and v > 0.55 and v < 0.95 and v - 0.55 > (u - 0.0) * 0.5 - 0.05
			return head or stem or flag
		"sleep":
			# Two letter Zs, a big one and a small one.
			return _zed(u + 0.25, v + 0.2, 0.42) or _zed(u - 0.5, v - 0.55, 0.24)
	return false


static func _zed(u: float, v: float, s: float) -> bool:
	if absf(u) > s or absf(v) > s:
		return false
	var w: float = s * 0.32
	return v > s - w or v < -s + w or absf(u - v) < w * 0.75
