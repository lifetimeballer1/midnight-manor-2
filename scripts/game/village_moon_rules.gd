# Moon phase rules: pure data and arithmetic with no scene dependencies, so the
# simulation, the village_moon.gd HUD/fog layer and the tests share one source.
# Numbers come from data/moon.json. See village_moon.gd for how it is shown.
extends RefCounted

const CONFIG_PATH: String = "res://data/moon.json"
const PHASE_COUNT: int = 8
const DEFAULTS: Dictionary = {
	"phase_names": ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"],
	"phase_glyphs": ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"],
	"new_moon_phase": 0,
	"blood_moon_phase": 4,
	"new_moon_enemy_multiplier": 0.75,
	"blood_moon_enemy_multiplier": 1.25,
	"blood_moon_loot_multiplier": 2.0,
	"blood_moon_tint": [0.62, 0.1, 0.1],
}

static var _config: Dictionary = {}


# The tunable numbers, read once from data/moon.json. Missing keys keep their defaults.
static func config() -> Dictionary:
	if _config.is_empty():
		_config = DEFAULTS.duplicate(true)
		if FileAccess.file_exists(CONFIG_PATH):
			var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
			var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
			if parsed is Dictionary:
				for key in parsed:
					_config[key] = parsed[key]
	return _config


# Any saved or computed value folded into 0..7. Non-numbers fall back to the New Moon.
static func clamp_phase(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	return posmod(int(value), PHASE_COUNT)


static func next_phase(phase: int) -> int:
	return posmod(clamp_phase(phase) + 1, PHASE_COUNT)


static func phase_name(phase: int) -> String:
	return str(config()["phase_names"][clamp_phase(phase)])


static func glyph(phase: int) -> String:
	return str(config()["phase_glyphs"][clamp_phase(phase)])


static func is_blood_moon(phase: int) -> bool:
	return clamp_phase(phase) == int(config()["blood_moon_phase"])


static func is_new_moon(phase: int) -> bool:
	return clamp_phase(phase) == int(config()["new_moon_phase"])


# Scales the number of raiders in the wave that the phase brings.
static func enemy_multiplier(phase: int) -> float:
	if is_blood_moon(phase):
		return float(config()["blood_moon_enemy_multiplier"])
	if is_new_moon(phase):
		return float(config()["new_moon_enemy_multiplier"])
	return 1.0


# Scales the defence reward paid when the raid of that phase is held.
static func loot_multiplier(phase: int) -> float:
	return float(config()["blood_moon_loot_multiplier"]) if is_blood_moon(phase) else 1.0


static func blood_tint() -> Color:
	var rgb: Array = config()["blood_moon_tint"]
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
