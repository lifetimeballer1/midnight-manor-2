extends "res://scripts/game/village_game.gd"

# Moonlit celebrations, layered over the village game so the main script stays
# as it is. A finished build, or an upgrade that lands, sends a gold-and-silver
# flourish up from that building. A village level-up sends a bigger one up from
# the Manor Hall. Everything here is decoration: it reads sim state and never
# changes it, respects the shared effect cap, and quiets down in battery saver.

const CELEBRATE_SILVER := Color("cfd8ea")
const CHECK_INTERVAL: float = 0.25
const BUILD_BATCH_LIMIT: int = 3

var _celebrate_clock: float = 0.0
var _tracked_sim: Object = null
var _last_elapsed: float = 0.0
var _seen_tiers: Dictionary = {}
var _last_level: int = -1


func _process(delta: float) -> void:
	super(delta)
	if not started or is_instance_valid(battle_view):
		return
	_celebrate_clock += delta
	if _celebrate_clock < CHECK_INTERVAL:
		return
	_celebrate_clock = 0.0
	_sync_tracking()
	_check_completions()
	_check_level()


# A new game swaps in a fresh sim. Start tracking that state quietly rather
# than celebrating everything that already stands.
func _sync_tracking() -> void:
	if sim != _tracked_sim or float(sim.elapsed) < _last_elapsed - 0.5:
		_tracked_sim = sim
		_seen_tiers.clear()
		_last_level = -1
	_last_elapsed = float(sim.elapsed)


func _check_completions() -> void:
	var flourishes: int = 0
	var any_new: bool = false
	for b: Dictionary in sim.buildings:
		var id: int = int(b["id"])
		var tier: int = int(b["tier"])
		var finished: bool = float(b["remaining"]) <= 0.0 and float(b["hp"]) > 0.0
		if not _seen_tiers.has(id):
			# First sighting: a finished building is baseline; one still raising celebrates when it lands.
			_seen_tiers[id] = tier if finished else 0
			continue
		if not finished:
			continue
		var seen: int = int(_seen_tiers[id])
		if tier <= seen:
			continue
		_seen_tiers[id] = tier
		var is_new: bool = seen == 0 and tier == 1
		if flourishes < BUILD_BATCH_LIMIT:
			_raise_flourish(b, is_new)
		flourishes += 1
		any_new = any_new or is_new
	if flourishes > 0:
		_chime("confirm" if any_new else "upgrade")


func _check_level() -> void:
	var level: int = sim.village_level()
	if _last_level < 0:
		_last_level = level
		return
	if level > _last_level:
		_level_flourish(level)
	_last_level = level


func _raise_flourish(b: Dictionary, is_new: bool) -> void:
	var at: Vector3 = world_position(sim.center(b), 0.3)
	var spec: Dictionary = sim.building_specs.get(str(b["type"]), {})
	var label_name: String = str(spec.get("name", b["type"]))
	var caption: String = "%s raised" % label_name if is_new else "%s tier %d" % [label_name, int(b["tier"])]
	var lite: bool = low_power or battery_saver
	_impact_burst(at + Vector3(0, 0.5, 0), GOLD, 6 if lite else 12, 1.0, true)
	_impact_burst(at + Vector3(0, 0.5, 0), CELEBRATE_SILVER, 4 if lite else 8, 0.9, true)
	if not lite:
		_sparkle_ring(at, 6, 1.1, 1.8)
	_moon_beam(at, GOLD, 2.4, 1.4)
	_float_label(at + Vector3(0, 2.0, 0), caption, GOLD, 42, 1.4, 1.6)


func _level_flourish(level: int) -> void:
	var hall: Dictionary = sim._hall()
	var anchor: Vector2 = sim.center(hall) if not hall.is_empty() else Vector2(10, 8)
	var at: Vector3 = world_position(anchor, 0.3)
	var lite: bool = low_power or battery_saver
	_impact_burst(at + Vector3(0, 1.2, 0), GOLD, 12 if lite else 30, 1.5, true)
	_impact_burst(at + Vector3(0, 1.2, 0), CELEBRATE_SILVER, 8 if lite else 22, 1.3, true)
	if not lite:
		_sparkle_ring(at, 12, 2.4, 2.6)
	_moon_beam(at, GOLD, 4.0, 2.4)
	_moon_beam(at, CELEBRATE_SILVER, 3.0, 2.0)
	_float_label(at + Vector3(0, 4.2, 0), "Village level %d" % level, GOLD, 96, 1.2, 2.8)
	sim.notice = "The village reaches level %d." % level
	_chime("confirm")
	get_tree().create_timer(0.35).timeout.connect(_chime.bind("collect"))


# A ring of sparks that spread outward and rise, alternating gold and silver.
func _sparkle_ring(at: Vector3, count: int, radius: float, lift: float) -> void:
	for index in count:
		if effect_nodes.size() >= EFFECT_LIMIT:
			return
		var angle: float = TAU * float(index) / float(count)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var tint: Color = GOLD if index % 2 == 0 else CELEBRATE_SILVER
		var spark: MeshInstance3D = _box(Vector3.ONE * 0.16, at + outward * 0.5 + Vector3(0, 0.3, 0), tint)
		_unshade(spark)
		effect_nodes.append(spark)
		var tween: Tween = create_tween()
		tween.tween_property(spark, "position", spark.position + outward * radius + Vector3(0, lift, 0), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(spark, "scale", Vector3.ZERO, 1.2).set_ease(Tween.EASE_IN)
		tween.tween_callback(spark.queue_free)


# A thin column of light that rises and fades above the spot.
func _moon_beam(at: Vector3, tint: Color, height: float, seconds: float) -> void:
	if effect_nodes.size() >= EFFECT_LIMIT:
		return
	var beam: MeshInstance3D = _box(Vector3(0.2, height, 0.2), at + Vector3(0, height * 0.5, 0), tint)
	_unshade(beam)
	var material: StandardMaterial3D = beam.material_override
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.8
	effect_nodes.append(beam)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(beam, "position:y", beam.position.y + height * 0.6, seconds).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.chain().tween_callback(beam.queue_free)


func _float_label(at: Vector3, text: String, tint: Color, font: int, rise: float, seconds: float) -> void:
	if effect_nodes.size() >= EFFECT_LIMIT:
		return
	var label := Label3D.new()
	label.text = text
	label.modulate = tint
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font
	label.pixel_size = 0.014
	label.outline_size = 12
	label.outline_modulate = NAVY
	label.position = at
	add_child(label)
	effect_nodes.append(label)
	var tween: Tween = create_tween()
	tween.tween_property(label, "position:y", at.y + rise, seconds)
	tween.parallel().tween_property(label, "modulate:a", 0.0, seconds)
	tween.tween_callback(label.queue_free)


func _unshade(node: MeshInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = node.material_override
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _chime(kind: String) -> void:
	if sound:
		_play_sfx(kind)
