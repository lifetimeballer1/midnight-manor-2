extends Node
class_name ManorMusic

# Generative soundtrack ported from Midnight Manor 1 (midnights-manner
# src/music.js + data/music.json): the same 12 themes, scales, chord
# progressions and seeded melodies, resynthesized per note as WAV.
# Pad = triangle, bass/pluck = sine (+octave overtone on pluck), echo via
# a Delay bus effect. Note buffers are cached, so synthesis is one-time.

const MIX_RATE: int = 22050
const PHRASES_PER_SONG: int = 5
const THEME_GAP: float = 0.42
const POOL_SIZE: int = 12
const BUS_NAME: String = "Music"

const DEFAULT_SCALE: Array = [0, 2, 3, 5, 7, 9, 10]
const DEFAULT_PROGRESSION: Array = [[0, 3, 7, 10], [5, 9, 12, 14], [-2, 2, 5, 9], [-5, 0, 2, 5]]

var themes: Array = []
var score: Dictionary = {}
var theme_index: int = 0
var mood: String = "day"
var pending_mood: bool = false
var entered: bool = false
var enabled: bool = false
var playing: bool = false
var calm: bool = false
var phrase: int = 0
var phrases_in_song: int = 0
var last_pitch: int = 31
var players: Array[AudioStreamPlayer] = []
var cache: Dictionary = {}
var pending: Array = []
var clock: float = 0.0
var phrase_end: float = 0.0
var switch_at: float = -1.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_ensure_bus()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_NAME
		add_child(player)
		players.append(player)
	_load_themes()


func _ensure_bus() -> void:
	var bus_index: int = AudioServer.bus_count
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == BUS_NAME:
			bus_index = i
			break
	if bus_index == AudioServer.bus_count:
		AudioServer.add_bus(AudioServer.bus_count)
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_NAME)
		bus_index = AudioServer.bus_count - 1
	var has_delay: bool = false
	for i in AudioServer.get_bus_effect_count(bus_index):
		if AudioServer.get_bus_effect(bus_index, i) is AudioEffectDelay:
			has_delay = true
	if not has_delay:
		var delay := AudioEffectDelay.new()
		delay.tap1_delay_ms = 240.0
		delay.tap1_level_db = -18.0
		delay.tap1_active = true
		delay.tap2_active = false
		delay.dry = 1.0
		AudioServer.add_bus_effect(bus_index, delay)


func _load_themes() -> void:
	if not FileAccess.file_exists("res://data/music.json"):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/music.json"))
	if parsed is Dictionary and parsed.has("themes"):
		themes = (parsed as Dictionary)["themes"]
	if themes.is_empty():
		return
	score = _score_data(themes[0])


static func _bounded(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if value is float or value is int:
		return clampf(float(value), minimum, maximum)
	return fallback


static func _notes(values: Variant, fallback: Array, minimum: int = -24, maximum: int = 24) -> Array:
	var valid: Array = []
	if values is Array:
		for n in (values as Array):
			if n is float or n is int:
				var v: int = int(n)
				if v >= minimum and v <= maximum and not valid.has(v):
					valid.append(v)
	return valid if not valid.is_empty() else fallback.duplicate()


static func _mod12(n: int) -> int:
	return ((n % 12) + 12) % 12


func _score_data(raw: Variant) -> Dictionary:
	var data: Dictionary = raw if raw is Dictionary else {}
	var scale: Array = _notes(data.get("scale"), DEFAULT_SCALE, 0, 11)
	var progression: Array = []
	if data.get("progression") is Array:
		for chord in (data["progression"] as Array):
			var notes: Array = _notes(chord, [], -24, 24)
			if notes.size() >= 3:
				progression.append(notes)
	if progression.is_empty():
		progression = DEFAULT_PROGRESSION
	return {
		"bpm": _bounded(data.get("bpm"), 72.0, 48.0, 96.0),
		"rootHz": _bounded(data.get("rootHz"), 73.416, 40.0, 180.0),
		"bars": int(_bounded(data.get("bars"), 4.0, 1.0, 8.0)),
		"pulsesPerBar": int(_bounded(data.get("pulsesPerBar"), 6.0, 3.0, 8.0)),
		"scale": scale,
		"progression": progression,
		"melodySlots": _notes(data.get("melodySlots"), [0, 2, 5], 0, 7),
		"calmMelodySlots": _notes(data.get("calmMelodySlots"), [0], 0, 7),
		"voices": data.get("voices") if (data.get("voices") is Dictionary) else {},
		"gain": _bounded(data.get("gain"), 0.7, 0.0, 1.0),
		"echo": data.get("echo") if (data.get("echo") is Dictionary) else {},
	}


func _theme_supports(theme: Dictionary, want: String) -> bool:
	var moods: Array = []
	if theme.get("moods") is Array:
		for m in (theme["moods"] as Array):
			if m is String:
				moods.append(m)
	return moods.is_empty() or moods.has(want)


func _voice_level(voice: String, fallback: float) -> float:
	var voices: Dictionary = score.get("voices", {})
	return _bounded(voices.get(voice), fallback, 0.005, 0.2)


static func _pick_tone(chord: Array, scale: Array, phrase_index: int, bar: int, slot: int, previous: int) -> int:
	var tones: Array = []
	for n in chord:
		if scale.has(_mod12(int(n))):
			tones.append(int(n))
	var source: Array = tones if not tones.is_empty() else scale
	var choices: Array = []
	for n in source:
		var pitch: int = int(n) + 24
		while pitch < 22:
			pitch += 12
		while pitch > 34:
			pitch -= 12
		if not choices.has(pitch):
			choices.append(pitch)
	var near: Array = []
	for pitch in choices:
		if pitch != previous and abs(pitch - previous) <= 5:
			near.append(pitch)
	var candidates: Array = near
	if candidates.is_empty():
		var closest: int = 99
		for pitch in choices:
			closest = mini(closest, abs(pitch - previous))
		for pitch in choices:
			if abs(pitch - previous) == closest:
				candidates.append(pitch)
	var tone_seed: int = (int((phrase_index + 1) * 0x9E3779B1) ^ int((bar + 1) * 0x85EBCA6B) ^ int((slot + 1) * 0xC2B2AE35)) & 0xFFFFFFFF
	tone_seed = (tone_seed ^ ((tone_seed << 13) & 0xFFFFFFFF)) & 0xFFFFFFFF
	tone_seed = (tone_seed ^ (tone_seed >> 17)) & 0xFFFFFFFF
	tone_seed = (tone_seed ^ ((tone_seed << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return candidates[tone_seed % candidates.size()]


func _create_phrase(phrase_index: int) -> Dictionary:
	var bpm: float = score["bpm"]
	var pulses: int = score["pulsesPerBar"]
	var pulse_seconds: float = 30.0 / bpm
	var bar_seconds: float = pulse_seconds * float(pulses)
	var notes: Array = []
	var previous: int = last_pitch
	for bar in int(score["bars"]):
		var chord: Array = (score["progression"] as Array)[(phrase_index + bar) % (score["progression"] as Array).size()]
		var time: float = float(bar) * bar_seconds
		for semitone in (chord as Array).slice(0, 3):
			notes.append({"voice": "pad", "semitone": int(semitone) + 12, "at": time, "dur": bar_seconds + 0.22})
		notes.append({"voice": "bass", "semitone": int(chord[0]), "at": time, "dur": bar_seconds * 0.86})
		var slots: Array = (score["calmMelodySlots"] if calm else score["melodySlots"]) as Array
		for slot in slots:
			if int(slot) >= pulses:
				continue
			previous = _pick_tone(chord, score["scale"], phrase_index, bar, int(slot), previous)
			var dur: float = bar_seconds * 0.58 if calm else pulse_seconds * 1.65
			notes.append({"voice": "pluck", "semitone": previous, "at": time + float(slot) * pulse_seconds, "dur": dur})
	return {"duration": bar_seconds * float(score["bars"]), "notes": notes, "lastPitch": previous}


func _tone(voice: String, freq: float, dur: float, level: float) -> AudioStreamWAV:
	var key := "%s_%.1f_%.2f_%.3f" % [voice, freq, dur, level]
	if cache.has(key):
		return cache[key]
	var count: int = maxi(1, int(dur * float(MIX_RATE)))
	var attack: float = 0.65 if voice == "pad" else (0.07 if voice == "bass" else 0.025)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t: float = float(i) / float(MIX_RATE)
		var phase: float = TAU * freq * t
		var sample: float = sin(phase)
		if voice == "pad":
			sample = (2.0 / PI) * asin(clampf(sample, -1.0, 1.0))
		elif voice == "pluck":
			sample = sample + 0.14 * sin(phase * 2.0)
		var env: float = 0.0
		if t < attack:
			env = level * (t / maxf(attack, 0.001))
		elif voice == "pad":
			var sustain: float = maxf(dur - 0.4, attack)
			if t < sustain:
				env = level * lerpf(1.0, 0.82, (t - attack) / maxf(sustain - attack, 0.001))
			else:
				env = 0.82 * level * exp(-(t - sustain) / maxf(dur - sustain, 0.05))
		else:
			env = level * exp(-(t - attack) / maxf(dur - attack, 0.05))
		bytes.encode_s16(i * 2, int(clampf(sample * env, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	cache[key] = stream
	return stream


func pick_theme(force_index: int = -1) -> bool:
	if themes.size() < 2:
		return false
	var next: int = theme_index
	if force_index >= 0 and force_index < themes.size():
		next = force_index
	else:
		var pool: Array = []
		for i in themes.size():
			if _theme_supports(themes[i], mood):
				pool.append(i)
		if pool.is_empty():
			for i in themes.size():
				pool.append(i)
		next = pool[rng.randi_range(0, pool.size() - 1)]
	var changed: bool = next != theme_index
	theme_index = next
	score = _score_data(themes[next])
	phrases_in_song = 0
	return changed


func enter(mood_name: String = "day") -> void:
	entered = true
	mood = mood_name
	pending_mood = false
	pick_theme()
	set_enabled(enabled)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_stop()
	elif entered and not playing:
		play()


func set_mood(mood_name: String) -> void:
	if mood_name == mood:
		return
	mood = mood_name
	if playing and not _theme_supports(score, mood):
		pending_mood = true


func set_calm(value: bool) -> void:
	calm = value


func play() -> void:
	if playing or themes.is_empty():
		return
	if pending_mood:
		pending_mood = false
		pick_theme()
	_apply_echo()
	playing = true
	_schedule_phrase()


func _apply_echo() -> void:
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) != BUS_NAME:
			continue
		for e in AudioServer.get_bus_effect_count(i):
			var effect: AudioEffect = AudioServer.get_bus_effect(i, e)
			if effect is AudioEffectDelay:
				var echo: Dictionary = score.get("echo", {})
				(effect as AudioEffectDelay).tap1_delay_ms = _bounded(echo.get("seconds"), 0.24, 80.0, 500.0) * 1000.0
				(effect as AudioEffectDelay).tap1_level_db = linear_to_db(clampf(_bounded(echo.get("gain"), 0.12, 0.0, 0.3) * 2.0, 0.001, 1.0))


func _schedule_phrase() -> void:
	var data: Dictionary = _create_phrase(phrase)
	phrase += 1
	phrases_in_song += 1
	pending.clear()
	for note in (data["notes"] as Array):
		var freq: float = float(score["rootHz"]) * pow(2.0, float(note["semitone"]) / 12.0)
		var fallback: float = 0.105 if str(note["voice"]) == "pluck" else (0.085 if str(note["voice"]) == "pad" else 0.08)
		pending.append({
			"at": clock + 0.06 + float(note["at"]),
			"stream": _tone(str(note["voice"]), freq, float(note["dur"]), _voice_level(str(note["voice"]), fallback)),
			"gain": float(score["gain"]),
		})
	last_pitch = int(data["lastPitch"])
	phrase_end = clock + 0.06 + float(data["duration"])


func _process(delta: float) -> void:
	if not playing:
		return
	clock += delta
	if switch_at >= 0.0 and clock >= switch_at:
		switch_at = -1.0
		if entered and enabled:
			play()
		return
	var voice_index: int = 0
	var kept: Array = []
	for note in pending:
		if float(note["at"]) <= clock:
			var player: AudioStreamPlayer = players[voice_index % players.size()]
			voice_index += 1
			player.stream = note["stream"]
			player.volume_db = linear_to_db(clampf(float(note["gain"]), 0.001, 1.0))
			player.play()
		else:
			kept.append(note)
	pending = kept
	if clock >= phrase_end and pending.is_empty():
		if phrases_in_song >= PHRASES_PER_SONG and pick_theme():
			_stop()
			switch_at = clock + THEME_GAP
		else:
			_schedule_phrase()


func _stop() -> void:
	pending.clear()
	phrase_end = 0.0
	switch_at = -1.0
	for player in players:
		player.stop()
	playing = false


func stop() -> void:
	entered = false
	enabled = false
	_stop()
