extends "res://scripts/game/village_clash.gd"

# Warsong layer (audio only), over the clash layer. Until now a raid made no sound beyond
# the horn and the bell. This gives every weapon its own voice and gives raids a drum track.
#
# Weapons: each blow is read from the sim's events just before the game consumes them, the
# fighter who threw it is found, and its weapon picks the sound: swords ring, spears whoosh
# into a thud, halberds chop, raider axes crunch, breakers' hammers boom, rams slam, bows
# twang and their arrows thunk home a moment later (after the flight time), towers crack,
# ballistas thwomp, bombards roar, traps snap, fire traps hiss. Falls get a grunt (low for
# raiders, higher for defenders) and a raider's soul gets a ghostly shimmer to match its wisp.
# Collapses crash. Sounds are small recipes of noise, sweeps and inharmonic ringing partials,
# rendered once and cached, with random pitch so repeats do not sound identical, a gap per
# sound so a melee cannot clip, and a quieter mix for what happens off screen.
#
# Soundtrack: while a raid runs, a drum track plays on the music's own pulse grid. It starts
# as slow dread (one deep taiko a bar), and builds with how many raiders are alive and
# fighting: more hits, then a galloping tom run, then snare rattle and low brass. A rising
# swell opens the raid, the raid theme is forced in at once, the sweet melody ducks under the
# drums, and the finish is a held horn over silence for a win or slow funeral drums for a loss.
# The "Dawn holds" slow beat also drags the pitch of everything down and back.
#
# The sounds themselves are recorded samples (Kenney's CC0 impact and RPG packs, in
# res://audio/combat), stacked in layers and pitched up or down to make each weapon: an axe is
# a real chop over a deep wood thud, a bombard is a plate slam dropped two octaves under a soft
# thud. The bow is a real bow-and-arrow shot (credited in audio/combat/CREDITS.txt). The older synthesised recipes below stay only as a fallback if a sample is missing.
#
# Nothing here touches the simulation, the save data or the event list apart from a private
# mark on each event. Everything respects the Sound toggle and the pause, and is torn down
# when the scene leaves the tree.

const RATE: int = 22050
const BUS: String = "Combat"
const VOICE_COUNT: int = 20
const DEFAULT_GAP_MS: int = 55
const SCREEN_MARGIN: float = 80.0         # pixels past the screen edge before a sound dims
const OFFSCREEN_DB: float = -9.0          # the most an off-screen sound is dimmed
const PITCH_JITTER: float = 0.07

const DRUM_DB: float = -3.0
const DRUM_BPM: float = 96.0              # used only when the music is not playing
const DUCK_DB: float = -5.0               # how far the melody sinks under the drums
const DUCK_RATE: float = 6.0              # dB per second
const INTENSITY_RISE: float = 0.4         # per second
const TIER_EDGES: Array[float] = [0.22, 0.5, 0.78]

const WAR_DB: Dictionary = {
	"sword": -4.0, "spear": -4.0, "halberd": -3.0, "axe": -3.0, "hammer": -2.0, "flesh": -9.0,
	"bow": -6.0, "arrow_hit": -8.0, "tower": -6.0, "ballista": -3.0, "bombard": -1.0, "ram": -1.0,
	"wall_crash": 0.0, "trap": -4.0, "fire": -5.0, "gate": -3.0, "die_foe": -6.0, "die_home": -6.0,
	"soul": -12.0, "taiko_lo": 0.0, "tom": -3.0, "rattle": -6.0, "brass": -7.0, "riser": -5.0,
	"horn_win": -3.0, "funeral": -2.0,
}
const WAR_GAP_MS: Dictionary = {
	"flesh": 80, "arrow_hit": 70, "bow": 90, "tower": 90, "sword": 65, "spear": 65, "axe": 65,
	"die_foe": 110, "die_home": 110, "soul": 160, "wall_crash": 200, "bombard": 250, "ram": 200,
	"taiko_lo": 0, "tom": 0, "rattle": 0, "brass": 0, "riser": 0, "horn_win": 0, "funeral": 0,
}
const PREWARM: Array[String] = [
	"sword", "axe", "flesh", "bow", "arrow_hit", "tower", "spear", "halberd", "hammer", "ram",
	"die_foe", "die_home", "wall_crash", "taiko_lo", "tom", "rattle", "brass", "riser", "ballista",
	"bombard", "trap", "fire", "gate", "soul", "horn_win", "funeral",
]

const SAMPLE_DIR: String = "res://audio/combat/"
const STEADY: Array[String] = ["taiko_lo", "brass", "riser", "horn_win", "funeral"]   # no random pitch

# Each sound is a stack of layers. A layer picks a random file from "set" (name_000..name_004)
# or from "files", plays it at a pitch in "pitch", offset by "db", after "delay" seconds.
const KITS: Dictionary = {
	"sword": [
		{"set": "impactMetal_medium", "pitch": [0.95, 1.15]},
		{"files": ["drawKnife1", "drawKnife2", "drawKnife3"], "pitch": [1.15, 1.3], "db": -8.0},
	],
	"spear": [
		{"files": ["knifeSlice", "knifeSlice2"], "pitch": [0.9, 1.05], "db": -3.0},
		{"set": "impactSoft_medium", "pitch": [0.95, 1.1], "delay": 0.08},
	],
	"halberd": [
		{"files": ["chop"], "pitch": [0.8, 0.9]},
		{"set": "impactMetal_medium", "pitch": [0.65, 0.75], "db": -4.0},
	],
	"axe": [
		{"files": ["chop"], "pitch": [0.92, 1.08]},
		{"set": "impactWood_heavy", "pitch": [0.85, 0.95], "db": -4.0},
	],
	"hammer": [
		{"set": "impactPlate_heavy", "pitch": [0.75, 0.85]},
		{"set": "impactMining", "pitch": [0.65, 0.75], "db": -3.0},
		{"set": "impactSoft_heavy", "pitch": [0.55, 0.65], "db": -2.0},
	],
	"flesh": [{"set": "impactPunch_medium", "pitch": [1.0, 1.2]}],
	"bow": [
		{"files": ["bow_shoot"], "pitch": [0.94, 1.08]},
		{"files": ["knifeSlice2"], "pitch": [1.7, 1.9], "db": -13.0, "delay": 0.06},
	],
	"arrow_hit": [
		{"set": "impactWood_light", "pitch": [1.25, 1.4]},
		{"set": "impactSoft_medium", "pitch": [1.4, 1.6], "db": -6.0},
	],
	"tower": [
		{"set": "impactWood_medium", "pitch": [1.15, 1.3]},
		{"files": ["knifeSlice"], "pitch": [1.5, 1.6], "db": -8.0},
	],
	"ballista": [
		{"set": "impactWood_heavy", "pitch": [0.65, 0.75]},
		{"files": ["creak1", "creak2"], "pitch": [1.0, 1.15], "db": -6.0},
		{"files": ["knifeSlice2"], "pitch": [0.85, 0.95], "db": -6.0, "delay": 0.04},
	],
	"bombard": [
		{"set": "impactPlate_heavy", "pitch": [0.38, 0.44]},
		{"set": "impactSoft_heavy", "pitch": [0.33, 0.38]},
		{"set": "impactMining", "pitch": [0.48, 0.55], "db": -4.0, "delay": 0.05},
	],
	"ram": [
		{"set": "impactWood_heavy", "pitch": [0.48, 0.55]},
		{"set": "impactPlank_medium", "pitch": [0.58, 0.66]},
		{"files": ["creak2", "creak3"], "pitch": [0.75, 0.85], "db": -8.0, "delay": 0.1},
	],
	"wall_crash": [
		# A timber building giving way: it groans, a beam cracks, then heavy timbers fall in a
		# rolling run that climbs in pitch and fades as the pile settles. Wood only.
		{"files": ["creak1", "creak2"], "pitch": [0.72, 0.8], "db": -3.0},
		{"files": ["creak2", "creak3"], "pitch": [0.95, 1.05], "db": -6.0, "delay": 0.1},
		{"set": "impactWood_medium", "pitch": [1.5, 1.6], "delay": 0.22},
		{"set": "impactPlank_medium", "pitch": [1.3, 1.4], "db": -3.0, "delay": 0.27},
		{"set": "impactWood_heavy", "pitch": [0.6, 0.65], "delay": 0.36},
		{"set": "impactSoft_heavy", "pitch": [0.44, 0.48], "db": -2.0, "delay": 0.36},
		{"set": "impactPlank_medium", "pitch": [0.68, 0.74], "db": -2.0, "delay": 0.43},
		{"set": "impactWood_heavy", "pitch": [0.68, 0.74], "db": -3.0, "delay": 0.5},
		{"set": "impactPlank_medium", "pitch": [0.83, 0.9], "db": -4.0, "delay": 0.58},
		{"set": "impactWood_heavy", "pitch": [0.83, 0.9], "db": -6.0, "delay": 0.66},
		{"set": "impactPlank_medium", "pitch": [0.98, 1.05], "db": -7.0, "delay": 0.76},
		{"set": "impactWood_light", "pitch": [1.05, 1.15], "db": -9.0, "delay": 0.88},
		{"set": "impactWood_light", "pitch": [1.25, 1.35], "db": -11.0, "delay": 1.0},
		{"set": "impactWood_light", "pitch": [1.45, 1.55], "db": -13.0, "delay": 1.15},
	],
	"trap": [
		{"files": ["metalLatch"], "pitch": [1.0, 1.1]},
		{"set": "impactMetal_light", "pitch": [1.15, 1.3], "db": -3.0},
	],
	"fire": [
		{"files": ["cloth3", "clothBelt"], "pitch": [0.55, 0.65]},
		{"files": ["knifeSlice"], "pitch": [0.5, 0.6], "db": -4.0},
	],
	"gate": [
		{"files": ["doorClose_2", "doorClose_3"], "pitch": [0.75, 0.85]},
		{"set": "impactWood_heavy", "pitch": [0.65, 0.75], "db": -3.0},
	],
	"die_foe": [
		{"set": "impactSoft_heavy", "pitch": [0.75, 0.85]},
		{"files": ["dropLeather"], "pitch": [0.85, 0.95], "db": -2.0, "delay": 0.04},
	],
	"die_home": [
		{"set": "impactSoft_medium", "pitch": [0.95, 1.05]},
		{"files": ["dropLeather"], "pitch": [1.05, 1.15], "db": -2.0, "delay": 0.04},
	],
	"soul": [
		{"set": "impactBell_heavy", "pitch": [1.55, 1.7], "db": -3.0},
		{"set": "impactBell_heavy", "pitch": [2.3, 2.5], "db": -8.0, "delay": 0.09},
	],
	"taiko_lo": [
		{"set": "impactWood_heavy", "pitch": [0.4, 0.44]},
		{"set": "impactSoft_heavy", "pitch": [0.33, 0.37], "db": -2.0},
	],
	"tom": [
		{"set": "impactWood_medium", "pitch": [0.58, 0.64]},
		{"set": "impactSoft_medium", "pitch": [0.68, 0.74], "db": -4.0},
	],
	"rattle": [
		{"set": "impactTin_medium", "pitch": [1.35, 1.45], "db": -2.0},
		{"set": "impactTin_medium", "pitch": [1.5, 1.6], "db": -4.0, "delay": 0.06},
		{"set": "impactMetal_light", "pitch": [1.6, 1.7], "db": -8.0},
	],
	"brass": [
		{"set": "impactBell_heavy", "pitch": [0.48, 0.52], "db": -2.0},
	],
	"riser": [
		{"set": "impactBell_heavy", "pitch": [0.36, 0.4]},
		{"set": "impactSoft_heavy", "pitch": [0.3, 0.34], "delay": 0.05},
	],
	"horn_win": [
		{"set": "impactBell_heavy", "pitch": [0.74, 0.76]},
		{"set": "impactBell_heavy", "pitch": [0.93, 0.95], "db": -2.0, "delay": 0.35},
		{"set": "impactBell_heavy", "pitch": [1.1, 1.12], "db": -4.0, "delay": 0.7},
	],
	"funeral": [
		{"set": "impactWood_heavy", "pitch": [0.4, 0.44]},
		{"set": "impactWood_heavy", "pitch": [0.4, 0.44], "db": -3.0, "delay": 1.0},
		{"set": "impactWood_heavy", "pitch": [0.4, 0.44], "db": -6.0, "delay": 1.9},
		{"set": "impactBell_heavy", "pitch": [0.44, 0.46], "db": -4.0, "delay": 2.2},
	],
}

var _war_ready: bool = false
var _war_voices: Array[AudioStreamPlayer] = []
var _war_cache: Dictionary = {}           # synthesised fallbacks
var _samples: Dictionary = {}             # file path -> loaded stream, or null when missing
var _war_last: Dictionary = {}             # sound kind -> last start, in ms
var _war_next: int = 0

var _raid_latched: bool = false
var _intensity: float = 0.2
var _last_pulse: int = -1
var _free_pulse_clock: float = 0.0
var _free_pulse_count: int = 0
var _duck_now: float = 0.0


func _process(delta: float) -> void:
	if not _war_ready:
		_war_ready = true
		_setup_war_audio()
		_preload_samples()
		tree_exiting.connect(_release_war_audio)
	var live: bool = started and not is_instance_valid(battle_view)
	if live and not sim.paused:
		_read_war_events()
	super(delta)
	if not live:
		_war_idle(delta)
		return
	_update_war(0.0 if sim.paused else delta)


# ---- setup ------------------------------------------------------------------------

func _setup_war_audio() -> void:
	var bus_index: int = _bus_index(BUS)
	if bus_index < 0:
		AudioServer.add_bus(AudioServer.bus_count)
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, BUS)
		AudioServer.set_bus_send(bus_index, "SFX" if _bus_index("SFX") >= 0 else "Master")
		var room := AudioEffectReverb.new()
		room.room_size = 0.28
		room.damping = 0.65
		room.wet = 0.14
		room.dry = 1.0
		AudioServer.add_bus_effect(bus_index, room)
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -4.0
		AudioServer.add_bus_effect(bus_index, limiter)
	for i in VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_war_voices.append(player)


func _bus_index(bus_name: String) -> int:
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == bus_name:
			return i
	return -1


# Loads every sample once, up front: they are small and decode on demand.
func _preload_samples() -> void:
	for kind: String in KITS:
		for layer: Dictionary in KITS[kind]:
			for path: String in _layer_paths(layer):
				_sample(path)


func _layer_paths(layer: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	if layer.has("set"):
		for i in 5:
			paths.append("%s%s_%03d.ogg" % [SAMPLE_DIR, layer["set"], i])
	else:
		for file: String in layer["files"]:
			paths.append("%s%s.ogg" % [SAMPLE_DIR, file])
	return paths


func _sample(path: String) -> AudioStream:
	if not _samples.has(path):
		_samples[path] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _samples[path]


func _release_war_audio() -> void:
	AudioServer.playback_speed_scale = 1.0
	var music_bus: int = _bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, 0.0)
	for player: AudioStreamPlayer in _war_voices:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_war_cache.clear()
	_samples.clear()


# ---- reading the fight ------------------------------------------------------------

func _read_war_events() -> void:
	for event: Dictionary in sim.events:
		if event.has("war"):
			continue
		event["war"] = true
		var kind: String = str(event.get("kind", ""))
		var tile := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
		if kind == "hit" and event.has("amount"):
			_war_hit(tile, bool(event.get("friendly", false)))
		elif kind == "shot":
			_war_shot(Vector2(float(event.get("from_x", 0.0)), float(event.get("from_y", 0.0))), tile)
		elif kind == "fall":
			var foe: bool = str(event.get("side", "")) == "foe"
			_voice("die_foe" if foe else "die_home", tile)
			if foe:
				get_tree().create_timer(0.18).timeout.connect(_voice.bind("soul", tile))
		elif kind == "destroyed":
			_voice("wall_crash", tile)
		elif kind == "raid_result":
			_war_finish(bool(event.get("victory", false)))


# A blow that landed. Melee blows sound off the weapon that threw them; ranged blows are
# voiced from their shot instead, so an arrow lands after its flight, not at the bow.
func _war_hit(tile: Vector2, friendly: bool) -> void:
	var attacker: Dictionary = _find_attacker(tile, friendly)
	if attacker.is_empty():
		return
	var weapon: String = _weapon_of(attacker, friendly)
	if weapon == "bow" or weapon == "bombard":
		return
	var building: Dictionary = _building_at_tile(tile) if friendly else {}
	if not building.is_empty():
		if str(building.get("type", "")) == "gate":
			_voice("gate", tile)
		_voice("axe" if weapon == "sword" else weapon, tile)
		return
	_voice(weapon, tile)
	_voice("flesh", tile)


# The weapon a fighter carries, as a sound kind. Raiders by role, defenders by troop type.
func _weapon_of(u: Dictionary, enemy: bool) -> String:
	if enemy:
		match str(u.get("role", "raider")):
			"ram": return "ram"
			"bombard": return "bombard"
			"breaker": return "hammer"
			"archer": return "bow"
			"scout": return "sword"
		return "axe" if int(u.get("id", 0)) % 2 == 0 else "sword"
	match str(u.get("type", "")):
		"pikewoman": return "spear"
		"halberdier": return "halberd"
		"archer", "ranger", "longbowman": return "bow"
	return "sword"


func _building_at_tile(tile: Vector2) -> Dictionary:
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) > 0.0 and sim.center(b).distance_to(tile) <= 0.35:
			return b
	return {}


# A shot left from from_tile toward tile. Who fired it picks the sound, and arrows land a
# beat later, after the same flight time the combat layer gives them.
func _war_shot(from_tile: Vector2, tile: Vector2) -> void:
	var kind: String = ""
	for u: Dictionary in sim.enemies:
		if sim.position_of(u).distance_to(from_tile) < 0.6:
			kind = _weapon_of(u, true)
			break
	if kind == "":
		for u: Dictionary in sim.units:
			if sim.position_of(u).distance_to(from_tile) < 0.6:
				kind = _weapon_of(u, false)
				break
	if kind == "":
		var building: Dictionary = {}
		for b: Dictionary in sim.buildings:
			if float(b["hp"]) > 0.0 and sim.center(b).distance_to(from_tile) < 0.5:
				building = b
				break
		match str(building.get("type", "")):
			"ballista": kind = "ballista"
			"trap": kind = "trap"
			"fire-trap": kind = "fire"
			"bastion": kind = "bombard"
			_: kind = "tower"
	if kind == "":
		kind = "bow"
	_voice(kind, from_tile)
	if kind == "bow" or kind == "tower" or kind == "ballista":
		var flight: float = clampf(world_position(from_tile, 0.0).distance_to(world_position(tile, 0.0)) * 0.07, 0.18, 0.5)
		get_tree().create_timer(flight).timeout.connect(_voice.bind("arrow_hit", tile))


# ---- playing ----------------------------------------------------------------------

# Plays one sound: each layer of its kit on a voice of its own, a little random pitch, dimmed
# when it happens off screen, and held to its own gap so a crowd cannot stack it into noise.
func _voice(kind: String, tile: Vector2 = Vector2(-1.0, -1.0), db: float = 0.0, param: float = 0.0) -> void:
	if not sound or _war_voices.is_empty() or not started or is_instance_valid(battle_view):
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_war_last.get(kind, -100000)) < int(WAR_GAP_MS.get(kind, DEFAULT_GAP_MS)):
		return
	_war_last[kind] = now
	var level: float = float(WAR_DB.get(kind, -6.0)) + db + (_screen_db(tile) if tile.x >= 0.0 else 0.0)
	var jitter: float = 0.0 if kind in STEADY else PITCH_JITTER * 0.6
	var played: bool = false
	for layer: Dictionary in KITS.get(kind, []):
		var paths: Array[String] = _layer_paths(layer)
		var stream: AudioStream = _sample(paths[randi() % paths.size()])
		if stream == null:
			continue
		played = true
		var span: Array = layer.get("pitch", [1.0, 1.0])
		var pitch: float = randf_range(float(span[0]), float(span[1])) * (1.0 + randf_range(-jitter, jitter))
		var layer_db: float = level + float(layer.get("db", 0.0))
		var delay: float = float(layer.get("delay", 0.0))
		if delay <= 0.0:
			_play_on_voice(stream, layer_db, pitch)
		else:
			get_tree().create_timer(delay).timeout.connect(_play_on_voice.bind(stream, layer_db, pitch))
	if not played:
		_play_on_voice(_stream(kind, param), level, 1.0)


func _play_on_voice(stream: AudioStream, db: float, pitch: float) -> void:
	if _war_voices.is_empty() or not sound:
		return
	var player: AudioStreamPlayer = _free_voice()
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = pitch
	player.play()


func _free_voice() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _war_voices:
		if not player.playing:
			return player
	_war_next = (_war_next + 1) % _war_voices.size()
	return _war_voices[_war_next]


func _screen_db(tile: Vector2) -> float:
	var screen: Vector2 = camera.unproject_position(world_position(tile, 0.5))
	var view: Rect2 = get_viewport().get_visible_rect().grow(SCREEN_MARGIN)
	if view.has_point(screen):
		return 0.0
	var outside: float = maxf(maxf(view.position.x - screen.x, screen.x - view.end.x), maxf(view.position.y - screen.y, screen.y - view.end.y))
	return -minf(-OFFSCREEN_DB, outside / 160.0 * 3.0)


# ---- the soundtrack ---------------------------------------------------------------

func _update_war(delta: float) -> void:
	var raid: bool = sim.raid_active and sound
	if raid and not _raid_latched:
		_raid_begins()
	elif not raid and _raid_latched:
		_last_pulse = -1
	_raid_latched = raid
	_apply_duck(delta, raid)
	_apply_pitch_dip()
	if not raid or sim.paused:
		return
	_intensity = move_toward(_intensity, _raid_intensity(), delta * INTENSITY_RISE)
	_drum_tick(delta)


# The rising edge of a raid: the raid theme is brought in at once and a swell opens it.
func _raid_begins() -> void:
	_intensity = 0.15
	_last_pulse = -1
	music.mood = "danger"
	music.pending_mood = false
	music.pick_theme()
	_voice("riser")


# How hard the fight is right now, from 0 to 1: more raiders, and more of them swinging.
func _raid_intensity() -> float:
	var alive: int = 0
	var fighting: int = 0
	for u: Dictionary in sim.enemies:
		if float(u["hp"]) > 0.0:
			alive += 1
			if str(u.get("phase", "")) == "attack":
				fighting += 1
	return clampf(0.2 + 0.35 * clampf(float(fighting) / 4.0, 0.0, 1.0) + 0.35 * clampf(float(alive) / 8.0, 0.0, 1.0), 0.0, 1.0)


# Fires a drum step each time the music crosses a pulse, so the drums sit on its grid.
# If the music is silent they keep their own time at the raid tempo.
func _drum_tick(delta: float) -> void:
	var per_bar: int = 6
	var pulse: int = -1
	if music.playing and not music.score.is_empty() and music.phrase_end > 0.0:
		per_bar = int(music.score.get("pulsesPerBar", 6))
		var seconds: float = 30.0 / float(music.score.get("bpm", DRUM_BPM))
		var total: int = int(music.score.get("bars", 4)) * per_bar
		var offset: int = floori((music.clock - (music.phrase_end - seconds * float(total))) / seconds)
		if offset < 0:
			return
		pulse = music.phrase * 1000 + offset
	else:
		_free_pulse_clock += delta
		var free_seconds: float = 30.0 / DRUM_BPM
		if _free_pulse_clock >= free_seconds:
			_free_pulse_clock -= free_seconds
			_free_pulse_count += 1
		pulse = _free_pulse_count
	if pulse == _last_pulse:
		return
	_last_pulse = pulse
	var in_phrase: int = pulse % 1000
	_drum_step(in_phrase % per_bar, floori(float(in_phrase) / float(per_bar)))


func _drum_step(step: int, bar: int) -> void:
	var tier: int = 0
	for edge: float in TIER_EDGES:
		if _intensity >= edge:
			tier += 1
	var lo: float = DRUM_DB
	var roll: bool = tier >= 2 and bar % 4 == 3 and step >= 3
	match tier:
		0:
			if step == 0:
				_voice("taiko_lo", Vector2(-1, -1), lo)
		1:
			if step == 0:
				_voice("taiko_lo", Vector2(-1, -1), lo)
			elif step == 3:
				_voice("taiko_lo", Vector2(-1, -1), lo - 5.0)
			elif step == 5:
				_voice("tom", Vector2(-1, -1), lo - 9.0)
		2:
			if step == 0 or step == 3:
				_voice("taiko_lo", Vector2(-1, -1), lo - (0.0 if step == 0 else 3.0))
			else:
				_voice("tom", Vector2(-1, -1), lo - (6.0 if step != 5 else 3.0))
			if step == 0 and bar % 4 == 0:
				_voice("brass", Vector2(-1, -1), 0.0, _brass_root())
		_:
			if step == 0 or step == 3:
				_voice("taiko_lo", Vector2(-1, -1), lo - (0.0 if step == 0 else 2.0))
			else:
				_voice("tom", Vector2(-1, -1), lo - 5.0)
			if step == 2 or step == 5:
				_voice("rattle", Vector2(-1, -1), lo - 4.0)
			if step == 0 and bar % 2 == 0:
				_voice("brass", Vector2(-1, -1), 0.0, _brass_root())
	if roll:
		_voice("rattle", Vector2(-1, -1), lo - 1.0)


func _brass_root() -> float:
	var root: float = float(music.score.get("rootHz", 65.406)) if not music.score.is_empty() else 65.406
	return roundf(root * 10.0) / 10.0


# The melody sinks under the drums while a raid runs and comes back after.
func _apply_duck(delta: float, raid: bool) -> void:
	var level: float = DUCK_DB if raid else 0.0
	if is_equal_approx(_duck_now, level):
		return
	_duck_now = move_toward(_duck_now, level, DUCK_RATE * maxf(delta, 0.016))
	var bus_index: int = _bus_index("Music")
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, _duck_now)


# While the "Dawn holds" slow beat runs, everything dips in pitch with the time.
func _apply_pitch_dip() -> void:
	var dip: float = Engine.time_scale if _slow_active and _slow_from > STOP_SCALE else 1.0
	if not is_equal_approx(AudioServer.playback_speed_scale, dip):
		AudioServer.playback_speed_scale = dip


func _war_finish(held: bool) -> void:
	if held:
		_voice("horn_win")
	else:
		_voice("funeral")
	_intensity = 0.0
	_last_pulse = -1


# Called when the village is not in view (frontier battle, menus): put the mix back.
func _war_idle(delta: float) -> void:
	_raid_latched = false
	_apply_duck(delta, false)
	if not is_equal_approx(AudioServer.playback_speed_scale, 1.0):
		AudioServer.playback_speed_scale = 1.0


# ---- synthesis --------------------------------------------------------------------

func _stream(kind: String, param: float) -> AudioStreamWAV:
	var key: String = "%s_%d" % [kind, int(param * 10.0)]
	if _war_cache.has(key):
		return _war_cache[key]
	var buf: PackedFloat32Array = _recipe(kind, param)
	var peak: float = 0.0001
	for sample: float in buf:
		peak = maxf(peak, absf(sample))
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(tanh(buf[i] / peak * 1.5) / tanh(1.5), -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	_war_cache[key] = stream
	return stream


func _blank(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(maxi(1, int(seconds * float(RATE))))
	return buf


# Filtered noise: a low-pass sweeping cut0 -> cut1 Hz, an optional high-pass, a fast attack,
# an exponential decay and an optional linear fade over its last rel seconds.
func _noise(buf: PackedFloat32Array, at: float, dur: float, vol: float, decay: float, cut0: float = 9000.0, cut1: float = -1.0, hp: float = 0.0, attack: float = 0.002, rel: float = 0.0) -> void:
	var start: int = int(at * float(RATE))
	var count: int = int(dur * float(RATE))
	var end_cut: float = cut0 if cut1 < 0.0 else cut1
	var low: float = 0.0
	var high: float = 0.0
	var a_hp: float = 1.0 - exp(-TAU * hp / float(RATE)) if hp > 0.0 else 0.0
	var a_lp: float = 1.0 - exp(-TAU * cut0 / float(RATE))
	for i in count:
		var idx: int = start + i
		if idx >= buf.size():
			break
		var t: float = float(i) / float(RATE)
		if end_cut != cut0 and i % 32 == 0:
			a_lp = 1.0 - exp(-TAU * lerpf(cut0, end_cut, float(i) / float(maxi(count - 1, 1))) / float(RATE))
		low += a_lp * ((randf() * 2.0 - 1.0) - low)
		var s: float = low
		if hp > 0.0:
			high += a_hp * (s - high)
			s -= high
		var env: float = minf(t / attack, 1.0) * exp(-t / maxf(decay, 0.004))
		if rel > 0.0:
			env *= clampf((dur - t) / rel, 0.0, 1.0)
		buf[idx] += s * vol * env


# A pitched voice sweeping f0 -> f1 (exponentially): 0 sine, 1 saw, 2 square, 3 triangle.
# cut is an optional low-pass, vib a vibrato depth in semitones.
func _tone(buf: PackedFloat32Array, at: float, dur: float, f0: float, f1: float, vol: float, decay: float, wave: int = 0, attack: float = 0.004, cut: float = 0.0, vib: float = 0.0, rel: float = 0.0) -> void:
	var start: int = int(at * float(RATE))
	var count: int = int(dur * float(RATE))
	var phase: float = 0.0
	var low: float = 0.0
	var a_lp: float = 1.0 - exp(-TAU * cut / float(RATE)) if cut > 0.0 else 1.0
	for i in count:
		var idx: int = start + i
		if idx >= buf.size():
			break
		var t: float = float(i) / float(RATE)
		var u: float = float(i) / float(maxi(count - 1, 1))
		var freq: float = f0 * pow(f1 / f0, u)
		if vib > 0.0:
			freq *= pow(2.0, sin(t * 38.0) * vib / 12.0)
		phase += TAU * freq / float(RATE)
		var s: float
		match wave:
			1: s = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
			2: s = 1.0 if sin(phase) >= 0.0 else -1.0
			3: s = asin(sin(phase)) * 2.0 / PI
			_: s = sin(phase)
		if cut > 0.0:
			low += a_lp * (s - low)
			s = low
		var env: float = minf(t / attack, 1.0) * exp(-t / maxf(decay, 0.004))
		if rel > 0.0:
			env *= clampf((dur - t) / rel, 0.0, 1.0)
		buf[idx] += s * vol * env


# Inharmonic partials, each dying a little faster than the one below: struck metal.
func _ring(buf: PackedFloat32Array, at: float, base: float, ratios: Array, dur: float, vol: float, decay: float) -> void:
	for k in ratios.size():
		_tone(buf, at, dur, base * float(ratios[k]), base * float(ratios[k]), vol / float(k + 1), decay / (1.0 + 0.55 * float(k)), 0, 0.001)


# Scattered short ticks: debris, crackling embers.
func _ticks(buf: PackedFloat32Array, from: float, to: float, count: int, vol: float, cut: float) -> void:
	for i in count:
		_noise(buf, randf_range(from, to), 0.03, vol * randf_range(0.4, 1.0), 0.008, cut, -1.0, 1200.0, 0.0005)


func _recipe(kind: String, param: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array
	match kind:
		"sword":
			buf = _blank(0.45)
			_noise(buf, 0.0, 0.07, 1.0, 0.02, 9000.0, -1.0, 2500.0)
			_ring(buf, 0.0, 1650.0, [1.0, 2.32, 3.87, 5.4], 0.42, 0.5, 0.16)
			_tone(buf, 0.0, 0.05, 220.0, 120.0, 0.7, 0.02)
		"spear":
			buf = _blank(0.34)
			_noise(buf, 0.0, 0.2, 0.6, 0.09, 600.0, 3500.0, 300.0, 0.05)
			_tone(buf, 0.17, 0.1, 140.0, 70.0, 1.0, 0.04)
			_noise(buf, 0.17, 0.06, 0.4, 0.02, 1800.0)
		"halberd":
			buf = _blank(0.45)
			_noise(buf, 0.0, 0.26, 0.7, 0.1, 400.0, 2800.0, 200.0, 0.08)
			_noise(buf, 0.22, 0.1, 1.0, 0.04, 1400.0)
			_tone(buf, 0.22, 0.2, 100.0, 50.0, 1.0, 0.08)
			_ring(buf, 0.22, 520.0, [1.0, 2.7], 0.25, 0.25, 0.1)
		"axe":
			buf = _blank(0.4)
			_noise(buf, 0.0, 0.12, 1.0, 0.04, 2200.0, 500.0)
			_tone(buf, 0.0, 0.3, 75.0, 42.0, 1.0, 0.12)
			_tone(buf, 0.0, 0.05, 320.0, 140.0, 0.4, 0.02, 2)
		"hammer":
			buf = _blank(0.6)
			_tone(buf, 0.0, 0.5, 62.0, 34.0, 1.2, 0.2)
			_noise(buf, 0.0, 0.35, 0.9, 0.12, 700.0, 200.0)
			_ring(buf, 0.0, 340.0, [1.0, 2.1, 3.3], 0.5, 0.35, 0.2)
			_noise(buf, 0.0, 0.02, 0.6, 0.01, 9000.0, -1.0, 3000.0)
		"flesh":
			buf = _blank(0.18)
			_noise(buf, 0.0, 0.07, 1.0, 0.02, 2600.0, 700.0)
			_tone(buf, 0.0, 0.12, 120.0, 60.0, 0.9, 0.05)
		"bow":
			buf = _blank(0.5)
			_tone(buf, 0.0, 0.4, 210.0, 172.0, 0.8, 0.12, 1, 0.002, 1400.0)
			_tone(buf, 0.0, 0.3, 420.0, 344.0, 0.3, 0.08)
			_noise(buf, 0.0, 0.02, 0.5, 0.008, 9000.0, -1.0, 4000.0, 0.0005)
			_noise(buf, 0.02, 0.25, 0.35, 0.1, 1200.0, 4500.0, 800.0, 0.04)
		"arrow_hit":
			buf = _blank(0.22)
			_tone(buf, 0.0, 0.1, 150.0, 70.0, 1.0, 0.04)
			_noise(buf, 0.0, 0.04, 0.7, 0.015, 1800.0)
			_tone(buf, 0.01, 0.12, 520.0, 500.0, 0.2, 0.04, 0, 0.001, 0.0, 0.6)
		"tower":
			buf = _blank(0.45)
			_noise(buf, 0.0, 0.03, 0.8, 0.01, 9000.0, -1.0, 2500.0, 0.0005)
			_tone(buf, 0.0, 0.06, 420.0, 180.0, 0.5, 0.02, 2)
			_tone(buf, 0.0, 0.35, 150.0, 130.0, 0.6, 0.14, 1, 0.002, 900.0)
			_noise(buf, 0.03, 0.2, 0.3, 0.08, 1000.0, 4000.0, 600.0, 0.04)
		"ballista":
			buf = _blank(0.7)
			_tone(buf, 0.0, 0.25, 110.0, 45.0, 1.0, 0.09)
			_tone(buf, 0.0, 0.55, 95.0, 82.0, 0.8, 0.25, 1, 0.002, 700.0)
			_noise(buf, 0.0, 0.03, 0.7, 0.01, 9000.0, -1.0, 2000.0, 0.0005)
			_noise(buf, 0.04, 0.4, 0.45, 0.2, 500.0, 2500.0, 0.0, 0.1)
		"bombard":
			buf = _blank(1.3)
			_tone(buf, 0.0, 1.0, 92.0, 30.0, 1.3, 0.35)
			_noise(buf, 0.0, 0.9, 1.0, 0.3, 900.0, 120.0)
			_noise(buf, 0.0, 0.05, 1.0, 0.015, 9000.0, -1.0, 1500.0, 0.0005)
			_ticks(buf, 0.05, 0.7, 6, 0.25, 3000.0)
		"ram":
			buf = _blank(0.8)
			_tone(buf, 0.0, 0.7, 64.0, 36.0, 1.2, 0.25)
			_noise(buf, 0.0, 0.3, 0.8, 0.1, 450.0, 150.0)
			for k in 3:
				_tone(buf, 0.05 + 0.07 * float(k), 0.05, 260.0 - 35.0 * float(k), 200.0 - 30.0 * float(k), 0.25, 0.02, 2)
			_noise(buf, 0.0, 0.03, 0.5, 0.01, 9000.0, -1.0, 1500.0, 0.0005)
		"wall_crash":
			buf = _blank(1.4)
			_noise(buf, 0.0, 1.2, 0.9, 0.45, 1400.0, 200.0)
			_tone(buf, 0.0, 1.0, 55.0, 28.0, 1.1, 0.4)
			_ring(buf, 0.0, 180.0, [1.0, 1.9], 0.6, 0.2, 0.25)
			_ticks(buf, 0.1, 1.1, 14, 0.25, 2500.0)
		"trap":
			buf = _blank(0.28)
			_noise(buf, 0.0, 0.03, 0.8, 0.01, 9000.0, -1.0, 3000.0, 0.0005)
			_tone(buf, 0.0, 0.05, 950.0, 300.0, 0.4, 0.02, 2)
			_ring(buf, 0.01, 1250.0, [1.0, 2.4, 4.1], 0.2, 0.35, 0.07)
			_tone(buf, 0.0, 0.08, 160.0, 80.0, 0.6, 0.03)
		"fire":
			buf = _blank(0.9)
			_noise(buf, 0.0, 0.8, 0.8, 0.35, 300.0, 2600.0, 0.0, 0.08)
			_ticks(buf, 0.05, 0.8, 12, 0.35, 7000.0)
		"gate":
			buf = _blank(0.7)
			_tone(buf, 0.0, 0.5, 75.0, 45.0, 1.0, 0.15)
			_noise(buf, 0.0, 0.3, 0.7, 0.1, 800.0, 200.0)
			_ring(buf, 0.0, 260.0, [1.0, 2.7, 4.4], 0.5, 0.3, 0.2)
		"die_foe":
			buf = _blank(0.5)
			_tone(buf, 0.0, 0.38, 185.0, 68.0, 1.0, 0.14, 1, 0.02, 900.0)
			_noise(buf, 0.0, 0.25, 0.35, 0.1, 900.0, -1.0, 0.0, 0.03)
			_tone(buf, 0.2, 0.15, 80.0, 45.0, 0.5, 0.06)
		"die_home":
			buf = _blank(0.5)
			_tone(buf, 0.0, 0.34, 300.0, 130.0, 1.0, 0.12, 1, 0.02, 1500.0)
			_noise(buf, 0.0, 0.22, 0.3, 0.1, 1400.0, -1.0, 0.0, 0.03)
			_tone(buf, 0.18, 0.15, 90.0, 50.0, 0.4, 0.06)
		"soul":
			buf = _blank(1.6)
			_tone(buf, 0.0, 1.4, 520.0, 1040.0, 0.5, 0.6, 0, 0.25, 0.0, 0.25, 0.5)
			_tone(buf, 0.1, 1.4, 780.0, 1560.0, 0.35, 0.6, 0, 0.3, 0.0, 0.3, 0.5)
			_tone(buf, 0.2, 1.3, 1040.0, 1300.0, 0.2, 0.5, 0, 0.3, 0.0, 0.2, 0.5)
		"taiko_lo":
			buf = _blank(1.0)
			_tone(buf, 0.0, 0.9, 98.0, 44.0, 1.2, 0.25)
			_noise(buf, 0.0, 0.05, 0.6, 0.02, 1200.0)
			_tone(buf, 0.0, 0.3, 150.0, 80.0, 0.5, 0.08)
		"tom":
			buf = _blank(0.5)
			_tone(buf, 0.0, 0.35, 165.0, 92.0, 1.0, 0.1)
			_noise(buf, 0.0, 0.03, 0.5, 0.012, 2500.0)
		"rattle":
			buf = _blank(0.25)
			_noise(buf, 0.0, 0.2, 0.8, 0.05, 9000.0, -1.0, 1800.0, 0.001)
			_noise(buf, 0.07, 0.15, 0.6, 0.04, 9000.0, -1.0, 1800.0, 0.001)
			_tone(buf, 0.0, 0.06, 190.0, 170.0, 0.3, 0.03)
		"brass":
			var root: float = param if param > 20.0 else 65.4
			buf = _blank(1.3)
			_tone(buf, 0.0, 1.2, root, root, 1.0, 0.5, 1, 0.05, 700.0)
			_tone(buf, 0.0, 1.2, root * 1.009, root * 1.009, 0.6, 0.5, 1, 0.06, 700.0)
			_tone(buf, 0.0, 1.2, root * 1.5, root * 1.5, 0.5, 0.4, 1, 0.06, 900.0)
			_tone(buf, 0.0, 1.0, root * 2.0, root * 2.0, 0.4, 0.35, 1, 0.07, 1200.0)
		"riser":
			buf = _blank(3.2)
			_noise(buf, 0.0, 3.0, 0.9, 99.0, 150.0, 5000.0, 0.0, 2.4, 0.3)
			_tone(buf, 0.0, 3.0, 55.0, 220.0, 0.5, 99.0, 1, 2.2, 600.0, 0.0, 0.4)
			_tone(buf, 2.9, 0.3, 90.0, 45.0, 1.0, 0.12)
		"horn_win":
			buf = _blank(3.2)
			_tone(buf, 0.0, 3.0, 130.8, 130.8, 1.0, 99.0, 1, 0.6, 700.0, 0.06, 1.0)
			_tone(buf, 0.0, 3.0, 196.0, 196.0, 0.7, 99.0, 1, 0.8, 800.0, 0.05, 1.0)
			_tone(buf, 0.0, 3.0, 261.6, 261.6, 0.4, 99.0, 1, 0.9, 900.0, 0.05, 1.0)
			_noise(buf, 0.0, 2.5, 0.08, 99.0, 1500.0, -1.0, 0.0, 0.6, 0.8)
		"funeral":
			buf = _blank(3.0)
			for k in 3:
				var at: float = [0.0, 1.0, 1.9][k]
				_tone(buf, at, 0.9, 98.0, 44.0, 1.2 - 0.25 * float(k), 0.3)
				_noise(buf, at, 0.05, 0.5, 0.02, 1200.0)
		_:
			buf = _blank(0.1)
	return buf
