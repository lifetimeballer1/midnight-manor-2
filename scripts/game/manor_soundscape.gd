extends Node

# The village's soundscape (The Manor Endures, D1), a child node of the game rather than another
# layer in its script chain. It only listens: it reads the game and sim and never changes them.
#   * Day and night beds (birds, crickets) cross-fade with the sky; an owl calls now and then at night.
#   * Work near the camera is heard: hammers at forges, axes at lumber camps, creaks at mills, water
#     at ponds and weirs, from staffed, standing workplaces only, louder the closer they are.
#   * A short fanfare when a building finishes, war drums while a raid is on.
#   * Everything follows the game's Sound switch and drops while the village is paused.
# The beds, owl, water, fanfare and drums are synthesised by scripts/audio/make_soundscape.py.

const BEDS_DB: float = -20.0
const DRUMS_DB: float = -11.0
const WATER_DB: float = -22.0
const SILENT_DB: float = -60.0
const PAUSED_DROP_DB: float = 10.0
const HEAR_TILES: float = 14.0
const FADE_DB_PER_SECOND: float = 30.0

const WORK_SOUNDS: Dictionary = {
	"forge": ["res://audio/combat/impactMetal_light_000.ogg", "res://audio/combat/impactMetal_light_002.ogg"],
	"smeltery": ["res://audio/combat/impactMetal_medium_001.ogg"],
	"armory": ["res://audio/combat/impactMetal_light_003.ogg"],
	"workshop": ["res://audio/combat/impactMetal_light_001.ogg"],
	"lumber": ["res://audio/combat/chop.ogg"],
	"timber_yard": ["res://audio/combat/chop.ogg"],
	"sawmill": ["res://audio/combat/creak2.ogg"],
	"mill": ["res://audio/combat/creak1.ogg", "res://audio/combat/creak3.ogg"],
	"bakery": ["res://audio/combat/creak1.ogg"],
}
const WATER_TYPES: Array[String] = ["pond", "blackwater-weir", "deephole"]

var game: Node
var day_bed := AudioStreamPlayer.new()
var night_bed := AudioStreamPlayer.new()
var drums := AudioStreamPlayer.new()
var water := AudioStreamPlayer.new()
var shots: Array[AudioStreamPlayer] = []
var _shot_index: int = 0
var _streams: Dictionary = {}
var _work_clock: float = 2.0
var _owl_clock: float = 20.0
var _fanfare_cooldown: float = 0.0
var _rising: Dictionary = {}     # building id -> true while it is still being built
var _primed: bool = false
var _last_heard: String = ""     # for tests: the last one-shot played


func setup(owner_game: Node) -> void:
	game = owner_game
	for pair: Array in [[day_bed, "day"], [night_bed, "night"], [drums, "war_drums"], [water, "water"]]:
		var player: AudioStreamPlayer = pair[0]
		player.bus = "SFX"
		player.stream = _looped("res://audio/ambience/%s.ogg" % str(pair[1]))
		player.volume_db = SILENT_DB
		add_child(player)
	for i in 3:
		var shot := AudioStreamPlayer.new()
		shot.bus = "SFX"
		add_child(shot)
		shots.append(shot)


func _looped(path: String) -> AudioStream:
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	return stream


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path)
	return _streams[path]


func _audible() -> bool:
	return game != null and bool(game.sound) and bool(game.started) and not is_instance_valid(game.battle_view)


func _fade(player: AudioStreamPlayer, want_db: float, delta: float) -> void:
	player.volume_db = move_toward(player.volume_db, want_db, FADE_DB_PER_SECOND * delta)
	var should_play: bool = want_db > SILENT_DB + 1.0 or player.volume_db > SILENT_DB + 1.0
	if should_play and not player.playing:
		player.play()
	elif not should_play and player.playing:
		player.stop()


func _process(delta: float) -> void:
	if game == null:
		return
	var sim = game.sim
	var on: bool = _audible()
	var drop: float = PAUSED_DROP_DB if sim.paused else 0.0
	var daylight: float = clampf(float(game.day_blend), 0.0, 1.0)
	_fade(day_bed, _mix(BEDS_DB - drop, daylight) if on else SILENT_DB, delta)
	_fade(night_bed, _mix(BEDS_DB - drop, 1.0 - daylight) if on else SILENT_DB, delta)
	_fade(drums, DRUMS_DB - drop if on and sim.raid_active else SILENT_DB, delta)
	var near_water: float = _nearest(WATER_TYPES)
	_fade(water, WATER_DB - drop - near_water * 1.6 if on and near_water < HEAR_TILES else SILENT_DB, delta)
	_watch_builds(sim, on)
	if not on or sim.paused:
		return
	_fanfare_cooldown = maxf(0.0, _fanfare_cooldown - delta)
	_work_clock -= delta
	if _work_clock <= 0.0:
		_work_clock = randf_range(1.6, 3.6)
		_play_work(sim, daylight)
	if daylight < 0.4:
		_owl_clock -= delta
		if _owl_clock <= 0.0:
			_owl_clock = randf_range(18.0, 40.0)
			_shot("res://audio/ambience/owl.ogg", -21.0, randf_range(0.94, 1.04))


# A bed's level for a 0..1 share of the sky (a smooth curve, so dusk mixes both).
func _mix(full_db: float, share: float) -> float:
	if share <= 0.02:
		return SILENT_DB
	return full_db + linear_to_db(clampf(share, 0.02, 1.0))


# Tiles from the camera's focus to the nearest standing building of these types (INF when none).
func _nearest(types: Array) -> float:
	var best: float = INF
	var focus: Vector3 = game.target
	for b: Dictionary in game.sim.buildings:
		if str(b["type"]) not in types or float(b["hp"]) <= 0.0 or float(b["remaining"]) > 0.0:
			continue
		var at: Vector3 = game.world_position(game.sim.center(b), 0.0)
		best = minf(best, Vector2(at.x - focus.x, at.z - focus.z).length() / float(game.TILE))
	return best


func _staffed(sim, b: Dictionary) -> bool:
	for u: Dictionary in sim.units:
		if int(u["workplace"]) == int(b["id"]) and float(u["hp"]) > 0.0 and str(u.get("phase", "")) == "work":
			return true
	return false


func _play_work(sim, daylight: float) -> void:
	if sim.raid_active or sim.raid_warning:
		return
	var heard: Array[Dictionary] = []
	var focus: Vector3 = game.target
	for b: Dictionary in sim.buildings:
		if not WORK_SOUNDS.has(str(b["type"])) or float(b["hp"]) <= 0.0 or float(b["remaining"]) > 0.0:
			continue
		var at: Vector3 = game.world_position(sim.center(b), 0.0)
		var tiles: float = Vector2(at.x - focus.x, at.z - focus.z).length() / float(game.TILE)
		if tiles <= HEAR_TILES and _staffed(sim, b):
			heard.append({"b": b, "tiles": tiles})
	if heard.is_empty():
		return
	var pick: Dictionary = heard[randi() % heard.size()]
	var options: Array = WORK_SOUNDS[str(pick["b"]["type"])]
	var level: float = -16.0 - float(pick["tiles"]) * 1.2 - (4.0 if daylight < 0.4 else 0.0)
	_shot(str(options[randi() % options.size()]), level, randf_range(0.92, 1.06))


# A fanfare when a building finishes (not on the first look, so loading a village is quiet).
func _watch_builds(sim, on: bool) -> void:
	var finished: bool = false
	var seen: Dictionary = {}
	for b: Dictionary in sim.buildings:
		var id: int = int(b["id"])
		var building: bool = float(b["remaining"]) > 0.0
		if building:
			seen[id] = true
		elif _rising.has(id) and float(b["hp"]) > 0.0:
			finished = true
	_rising = seen
	if not _primed:
		_primed = true
		return
	if finished and on and _fanfare_cooldown <= 0.0:
		_fanfare_cooldown = 3.0
		_shot("res://audio/ambience/fanfare.ogg", -14.0, 1.0)


func _shot(path: String, volume_db: float, pitch: float) -> void:
	var player: AudioStreamPlayer = shots[_shot_index % shots.size()]
	_shot_index += 1
	player.stream = _stream(path)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	_last_heard = path
