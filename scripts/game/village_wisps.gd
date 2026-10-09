extends "res://scripts/game/village_combat.gd"

# Lingering wisps: a raider that falls during a home raid sometimes leaves a pale
# blue-white wisp behind. Wisps bob and drift in place, can be tapped for a small
# Insight reward (with a float-up and a soft chime), and fade away at dawn or after
# their lifetime. They are transient: never saved, never part of the simulation, and
# nothing is granted during frontier battles. Tuning lives in data/wisps.json.
# Pooling mirrors scripts/game/combat_burst_pool.gd: fixed slots, reused, capped.

const CONFIG_PATH: String = "res://data/wisps.json"
const SLOT_COUNT: int = 12
const FALL_KEY: String = "wisp_checked"
const FADE_SECONDS: float = 1.2
const WISP_HEIGHT: float = 1.1
const WISP_COLOUR: Color = Color(0.78, 0.9, 1.0)

var wisp_chance: float = 0.25
var wisp_lifetime: float = 90.0
var wisp_insight: int = 3
var wisp_tap_radius: float = 22.0
var wisp_dropped: int = 0

var _wisp_slots: Array[Dictionary] = []   # {node, material, active, fading, age, fade, base, phase}
var _wisp_sim: Object = null
var _wisp_was_night: bool = true


func _ready() -> void:
	super()
	_load_wisp_config()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 10
	mesh.rings = 5
	for slot in SLOT_COUNT:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(WISP_COLOUR, 0.0)
		material.emission_enabled = true
		material.emission = WISP_COLOUR
		material.emission_energy_multiplier = 2.2
		material.disable_receive_shadows = true
		var node := MeshInstance3D.new()
		node.name = "Wisp%d" % slot
		node.mesh = mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		add_child(node)
		_wisp_slots.append({"node": node, "material": material, "active": false, "fading": false,
			"age": 0.0, "fade": 0.0, "base": Vector3.ZERO, "phase": 0.0})
	_wisp_was_night = night


func _process(delta: float) -> void:
	if sim != _wisp_sim:
		_wisp_sim = sim
		_retire_all()
	super(delta)
	if not started:
		return
	if night != _wisp_was_night:
		# Dawn (night turning to day) fades every wisp out.
		if not night:
			_fade_all()
		_wisp_was_night = night
	_tend_wisps(0.0 if sim.paused or is_instance_valid(battle_view) else delta)


# Runs once per frame before the game consumes this frame's sim events, so raider
# falls from home raids can be seen here. Each event is checked only once.
func _consume_events() -> void:
	if started and not is_instance_valid(battle_view):
		for event: Dictionary in sim.events:
			if str(event.get("kind", "")) != "fall" or str(event.get("side", "")) != "foe":
				continue
			if bool(event.get(FALL_KEY, false)):
				continue
			event[FALL_KEY] = true
			if randf() < wisp_chance:
				_spawn_wisp(world_position(Vector2(float(event["x"]), float(event["y"])), WISP_HEIGHT))
	super()


# Taps on a wisp collect it; any other tap falls through to the game's own handling.
func _map_click(screen: Vector2) -> void:
	if _collect_wisp_at(screen):
		return
	super(screen)


func _load_wisp_config() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary:
		return
	var config: Dictionary = parsed
	wisp_chance = clampf(float(config.get("chance", wisp_chance)), 0.0, 1.0)
	wisp_lifetime = maxf(1.0, float(config.get("lifetime_seconds", wisp_lifetime)))
	wisp_insight = maxi(0, int(config.get("insight_reward", wisp_insight)))
	wisp_tap_radius = clampf(float(config.get("tap_radius_px", wisp_tap_radius)), 8.0, 40.0)


func _spawn_wisp(at: Vector3) -> void:
	if not at.is_finite():
		return
	for slot: Dictionary in _wisp_slots:
		if bool(slot["active"]):
			continue
		slot["active"] = true
		slot["fading"] = false
		slot["age"] = 0.0
		slot["fade"] = 0.0
		slot["base"] = at
		slot["phase"] = randf() * TAU
		(slot["material"] as StandardMaterial3D).albedo_color.a = 0.0
		var node: MeshInstance3D = slot["node"]
		node.position = at
		node.visible = true
		return
	wisp_dropped += 1


func _tend_wisps(delta: float) -> void:
	for slot: Dictionary in _wisp_slots:
		if not bool(slot["active"]):
			continue
		if bool(slot["fading"]):
			slot["fade"] = float(slot["fade"]) + delta
			if float(slot["fade"]) >= FADE_SECONDS:
				_retire(slot)
				continue
		else:
			slot["age"] = float(slot["age"]) + delta
			if float(slot["age"]) >= wisp_lifetime:
				slot["fading"] = true
				slot["fade"] = 0.0
		var age: float = float(slot["age"])
		var phase: float = float(slot["phase"])
		var base: Vector3 = slot["base"]
		var drift := Vector3(sin(age * 0.35 + phase) * 0.35, 0.0, cos(age * 0.27 + phase * 1.3) * 0.3)
		var bob := Vector3(0.0, sin(age * 2.1 + phase) * 0.12, 0.0)
		var node: MeshInstance3D = slot["node"]
		node.position = base + drift + bob
		var alpha: float = 0.9 * (0.75 + 0.25 * sin(age * 3.0 + phase))
		if bool(slot["fading"]):
			alpha *= clampf(1.0 - float(slot["fade"]) / FADE_SECONDS, 0.0, 1.0)
		(slot["material"] as StandardMaterial3D).albedo_color.a = alpha


func _collect_wisp_at(screen: Vector2) -> bool:
	if not started or is_instance_valid(battle_view):
		return false
	var chosen: Dictionary = {}
	var nearest: float = wisp_tap_radius
	for slot: Dictionary in _wisp_slots:
		if not bool(slot["active"]) or bool(slot["fading"]):
			continue
		var node: MeshInstance3D = slot["node"]
		if camera.is_position_behind(node.global_position):
			continue
		var gap: float = camera.unproject_position(node.global_position).distance_to(screen)
		if gap <= nearest:
			nearest = gap
			chosen = slot
	if chosen.is_empty():
		return false
	var at: Vector3 = (chosen["node"] as MeshInstance3D).position + Vector3(0, 0.5, 0)
	_retire(chosen)
	_reward_wisp(at)
	return true


func _reward_wisp(at: Vector3) -> void:
	var living = sim.living
	var cap: float = float(living.config["research"]["insight_cap"])
	living.insight = minf(cap, float(living.insight) + float(wisp_insight))
	_float_label(at, "+%d Insight" % wisp_insight, Color("cfe8ff"), 44, 1.0, 1.4)
	_chime("collect")


func _fade_all() -> void:
	for slot: Dictionary in _wisp_slots:
		if bool(slot["active"]) and not bool(slot["fading"]):
			slot["fading"] = true
			slot["fade"] = 0.0


func _retire_all() -> void:
	for slot: Dictionary in _wisp_slots:
		_retire(slot)


func _retire(slot: Dictionary) -> void:
	slot["active"] = false
	slot["fading"] = false
	var node: MeshInstance3D = slot["node"]
	node.visible = false
