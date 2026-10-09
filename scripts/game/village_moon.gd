extends "res://scripts/game/village_wisps.gd"

const Rules = preload("res://scripts/game/village_moon_rules.gd")

# Moon phases. The moon advances one phase for every raid cycle that completes,
# so the phase is a calendar of horns rather than a clock. The phase shows beside
# the horn timer. The Full Moon is the Blood Moon: its raid brings more raiders,
# pays double defence gold, and the fog and moon take on a red tint while it
# rages. The New Moon is a quieter raid. Tunable numbers live in data/moon.json.
# The simulation owns the phase (sim.moon_phase, saved as an optional field) and
# applies the enemy and loot numbers through village_moon_rules.gd; this layer
# only reads the phase for the HUD and the blood-sky tint.

func _process(delta: float) -> void:
	super(delta)
	if not started or is_instance_valid(battle_view):
		return
	var phase: int = Rules.clamp_phase(sim.moon_phase)
	_show_phase(phase)
	_tint_blood_sky(sim.raid_active and Rules.is_blood_moon(phase))


# Appended after the horn timer. The base HUD rewrites its text, so the suffix is
# added again whenever it is missing rather than once.
func _show_phase(phase: int) -> void:
	if raid_hud == null or not is_instance_valid(raid_hud):
		return
	var suffix: String = " / %s %s" % [Rules.glyph(phase), Rules.phase_name(phase)]
	if Rules.is_blood_moon(phase):
		suffix += " (Blood)"
	if not raid_hud.text.ends_with(suffix):
		raid_hud.text += suffix


# The dusk layer rewrites the mist and moon colours each frame from their original
# values, so this tint only lasts while the blood raid does and reverts on its own.
func _tint_blood_sky(active: bool) -> void:
	if not active:
		return
	var tint: Color = Rules.blood_tint()
	if is_instance_valid(mist):
		mist.color = Color(tint.r, tint.g, tint.b, mist.color.a)
	if is_instance_valid(moon):
		var material: StandardMaterial3D = _quad_material(moon)
		if material != null:
			material.albedo_color = Color(tint.r, tint.g, tint.b, material.albedo_color.a)
