extends "res://scripts/game/village_scars.gd"

# Omens layer (visual only), layered over the village so the main script stays as it
# is. During a Blood Moon raid a slow fall of dark-red ash drifts over the map, and it
# fades once the raid ends. Moments the village has earned are marked at the Manor Hall:
# a raid held sends a gold sparkle ring and rising motes, a raid lost sends a low dust
# cloud, a finished research sends a silver ring and beam, and a completed quest sends
# a small gold ring. Raid results are read from the sim's events just before the game
# consumes them. Research and quests are detected by polling the sim about four times a
# second. Each new sim object (a load swaps one in) is seeded silently, so old progress
# never replays. One-shots respect the shared effect budget and battery saver or low
# power lite mode, and none play during frontier battles. Decoration only: it never
# changes the simulation and adds no sim events.

const OmenMoon = preload("res://scripts/game/village_moon_rules.gd")

const OMEN_POLL_INTERVAL: float = 0.25
const OMEN_MAP_CENTRE: Vector2 = Vector2(10.0, 8.0)
const OMEN_EMBER_COUNT: int = 20
const OMEN_EMBER_LITE: int = 10
const OMEN_EMBER_HEIGHT: float = 3.5
const OMEN_EMBER_LIFE: float = 5.0
const OMEN_EMBER_HIDE_PAD: float = 0.5
const OMEN_BLOOD_ASH: Color = Color(0.46, 0.06, 0.08)
const OMEN_VICTORY_RING: int = 10
const OMEN_RESEARCH_RING: int = 8
const OMEN_QUEST_RING: int = 6
const OMEN_DEFEAT_RADIUS: float = 2.6

var _omen_clock: float = 0.0
var _omen_sim: Variant = null            # sim instance last seeded; a new sim reseeds silently
var _omen_research: int = 0              # research discoveries counted at the previous poll
var _omen_quests: int = 0                # completed quests counted at the previous poll
var _omen_ember: CPUParticles3D = null   # the Blood Moon ash emitter, created on first use
var _omen_hide_in: float = 0.0           # seconds until a stopped ash emitter is hidden


func _process(delta: float) -> void:
	super(delta)
	_omen_tend_ember(delta)
	_omen_clock -= delta
	if _omen_clock > 0.0:
		return
	_omen_clock = OMEN_POLL_INTERVAL
	_omen_poll()


# Runs once per frame after the sim has ticked and before the game consumes this
# frame's events. Raid results are only read here, never removed, so the game's own
# banner still shows.
func _consume_events() -> void:
	if started and not _omen_battle():
		for event: Dictionary in sim.events:
			if str(event.get("kind", "")) != "raid_result":
				continue
			if bool(event.get("victory", false)):
				_omen_raid_victory()
			else:
				_omen_raid_defeat()
	super()


func _omen_poll() -> void:
	if sim != _omen_sim:
		_omen_sim = sim
		_omen_research = _omen_research_count()
		_omen_quests = sim.completed_quests.size()
	var blood: bool = started and not _omen_battle() and bool(sim.raid_active) and OmenMoon.is_blood_moon(int(sim.moon_phase))
	_omen_set_ember(blood)

	var research: int = _omen_research_count()
	var quests: int = sim.completed_quests.size()
	if _omen_can_emit():
		if research > _omen_research:
			_omen_research_done()
		if quests > _omen_quests:
			_omen_quest_done()
	# A count that falls (a save restored in place) is simply re-seeded, with no moment.
	_omen_research = research
	_omen_quests = quests


# True while a frontier battle is on screen or pending: no omens play then.
func _omen_battle() -> bool:
	return is_instance_valid(battle_view) or not sim.frontier.active.is_empty()


func _omen_can_emit() -> bool:
	return started and not _omen_battle()


func _omen_lite() -> bool:
	return low_power or battery_saver


func _omen_research_count() -> int:
	return sim.living.discoveries.size()


# The Manor Hall's centre, or the middle of the map if there is no hall.
func _omen_hall_point(height: float) -> Vector3:
	var hall: Dictionary = sim._hall()
	var anchor: Vector2 = sim.center(hall) if not hall.is_empty() else OMEN_MAP_CENTRE
	return world_position(anchor, height)


# Holds the Blood Moon ash going while the raid runs, and lets it fade out after.
func _omen_set_ember(on: bool) -> void:
	if on:
		if _omen_ember == null:
			_omen_ember = _omen_make_ember()
			add_child(_omen_ember)
		var wanted: int = OMEN_EMBER_LITE if _omen_lite() else OMEN_EMBER_COUNT
		if _omen_ember.amount != wanted:
			_omen_ember.amount = wanted
		_omen_ember.visible = true
		_omen_ember.emitting = true
	elif _omen_ember != null and _omen_ember.emitting:
		_omen_ember.emitting = false
		_omen_hide_in = OMEN_EMBER_LIFE + OMEN_EMBER_HIDE_PAD


# Freezes the ash with the simulation and hides it once its last flakes have fallen.
func _omen_tend_ember(delta: float) -> void:
	if _omen_ember == null:
		return
	var rate: float = 0.0 if sim.paused else 1.0
	if _omen_ember.speed_scale != rate:
		_omen_ember.speed_scale = rate
	if not _omen_ember.emitting and _omen_ember.visible:
		_omen_hide_in -= delta * rate
		if _omen_hide_in <= 0.0:
			_omen_ember.visible = false


func _omen_make_ember() -> CPUParticles3D:
	var ember := CPUParticles3D.new()
	ember.name = "BloodMoonAsh"
	ember.amount = OMEN_EMBER_COUNT
	ember.lifetime = OMEN_EMBER_LIFE
	ember.preprocess = OMEN_EMBER_LIFE
	ember.one_shot = false
	ember.explosiveness = 0.0
	ember.direction = Vector3.DOWN
	ember.spread = 25.0
	ember.gravity = Vector3(0.0, -0.22, 0.0)
	ember.initial_velocity_min = 0.1
	ember.initial_velocity_max = 0.3
	ember.angular_velocity_min = -40.0
	ember.angular_velocity_max = 40.0
	ember.scale_amount_min = 0.7
	ember.scale_amount_max = 1.2
	ember.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ember.emission_box_extents = Vector3(10.0 * TILE, 0.3, 8.0 * TILE)
	ember.position = world_position(OMEN_MAP_CENTRE, OMEN_EMBER_HEIGHT)
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	ember.color_ramp = fade
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = OMEN_BLOOD_ASH
	mesh.material = material
	ember.mesh = mesh
	return ember


# A raid held: a gold sparkle ring and rising motes over the Hall, with a short beam.
func _omen_raid_victory() -> void:
	if not _effect_budget_open():
		return
	var lite: bool = _omen_lite()
	var at: Vector3 = _omen_hall_point(0.3)
	if not lite:
		_sparkle_ring(at, OMEN_VICTORY_RING, 2.0, 2.2)
	_impact_burst(at + Vector3(0, 1.0, 0), GOLD, 8 if lite else 16, 1.2, true)
	_moon_beam(at, GOLD, 3.2, 1.8)


# A raid lost: a low dust cloud settles over the Hall.
func _omen_raid_defeat() -> void:
	_dust_puff(_omen_hall_point(0.3), OMEN_DEFEAT_RADIUS)


# Research finished: a silver ring and beam over the Hall.
func _omen_research_done() -> void:
	if not _effect_budget_open():
		return
	var lite: bool = _omen_lite()
	var at: Vector3 = _omen_hall_point(0.3)
	_impact_burst(at + Vector3(0, 1.0, 0), CELEBRATE_SILVER, 8 if lite else 14, 1.0, true)
	if not lite:
		_sparkle_ring(at, OMEN_RESEARCH_RING, 1.6, 1.8)
	_moon_beam(at, CELEBRATE_SILVER, 2.8, 1.5)


# A quest completed: a small gold ring over the Hall. The toast and raven announce it.
func _omen_quest_done() -> void:
	if not _effect_budget_open():
		return
	var lite: bool = _omen_lite()
	var at: Vector3 = _omen_hall_point(0.3)
	if lite:
		_impact_burst(at + Vector3(0, 0.8, 0), GOLD, 4, 0.8, true)
	else:
		_sparkle_ring(at, OMEN_QUEST_RING, 1.1, 1.0)
