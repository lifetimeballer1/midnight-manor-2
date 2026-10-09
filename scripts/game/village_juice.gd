extends "res://scripts/game/village_moon.gd"
## Collection feedback layer (float-up icons, HUD tick-up).

# When the player collects from a workplace (the bar's Collect, the inspect Collect or
# Collect-all), a few resource glyphs arc from the building toward its HUD resource chip.
# The chip then counts up as each glyph lands and pulses. Worker deliveries are not
# player collects and get no glyphs. One soft chime plays per player collect action;
# the base layer would otherwise chime once per building, so its chime is muted for
# the frame that carries a flagged batch.
# Everything runs in _process scaled by the sim's pause state, so pausing freezes the
# flight and the count-up. Glyphs come from a fixed pool of Labels (no Tweens are used).

const ICON_LAYER: int = 2
const ICON_SLOTS: int = 24
const ICON_MIN: int = 3
const ICON_MAX: int = 6
const ICON_SECONDS: float = 0.6
const ICON_ARC: float = 64.0
const ICON_HEIGHT: float = 2.4
const COUNTER_EASE: float = 10.0
const PULSE_SECONDS: float = 0.3
const COLLECT_KEY: String = "juice_collect"
const COUNTER_TINT: Color = Color(1.35, 1.3, 1.1)

var _icon_layer: CanvasLayer = null
var _free_slots: Array[Label] = []
var _icon_jobs: Array[Dictionary] = []   # {label, resource, from, to, share, age, delay, duration}
var _counter: Dictionary = {}             # resource -> {shown, goal, final, icons_left, pulse}


func _ready() -> void:
	super()
	_icon_layer = CanvasLayer.new()
	_icon_layer.layer = ICON_LAYER
	add_child(_icon_layer)
	for slot in ICON_SLOTS:
		var label := Label.new()
		label.visible = false
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", GOLD)
		label.add_theme_color_override("font_outline_color", NAVY)
		label.add_theme_constant_override("outline_size", 5)
		_icon_layer.add_child(label)
		_free_slots.append(label)


func _process(delta: float) -> void:
	super(delta)
	if not started:
		return
	var step: float = 0.0 if sim.paused or is_instance_valid(battle_view) else delta
	_tend_icons(step)
	_tend_counters(step)


func _exit_tree() -> void:
	super()
	for job: Dictionary in _icon_jobs:
		var label: Label = job["label"]
		if is_instance_valid(label):
			label.visible = false
	_icon_jobs.clear()
	for resource: String in _counter.keys():
		_restore_counter(resource)
	_counter.clear()
	if is_instance_valid(_icon_layer):
		_icon_layer.queue_free()
	_icon_layer = null
	_free_slots.clear()


# Player collects are flagged synchronously; their events are seen by the next frame.
func _collect_selected() -> void:
	var start: int = sim.events.size()
	super()
	_feedback_for_events(start)


func _collect_all() -> void:
	var start: int = sim.events.size()
	super()
	_feedback_for_events(start)


func _refresh_hud() -> void:
	super()
	for resource: String in _counter.keys():
		_paint_counter(resource, _counter[resource])


# Mutes the base chime for a flagged batch and plays exactly one chime in its place.
func _consume_events() -> void:
	var quiet: bool = false
	for event: Dictionary in sim.events:
		if bool(event.get(COLLECT_KEY, false)):
			event[COLLECT_KEY] = false
			quiet = true
	var was_sound: bool = sound
	if quiet:
		sound = false
	super()
	sound = was_sound
	if quiet:
		_chime("collect")


func _feedback_for_events(start: int) -> void:
	if start > sim.events.size():
		return
	var batch: Array[Dictionary] = []
	for index in range(start, sim.events.size()):
		var event: Dictionary = sim.events[index]
		if str(event.get("kind", "")) == "collect" and int(event.get("amount", 0)) > 0:
			batch.append(event)
	if batch.is_empty():
		return
	for event: Dictionary in batch:
		event[COLLECT_KEY] = true
	_launch_feedback(batch)


func _launch_feedback(batch: Array[Dictionary]) -> void:
	var totals: Dictionary = {}
	for event: Dictionary in batch:
		var resource: String = str(event["resource"])
		totals[resource] = float(totals.get(resource, 0.0)) + float(event["amount"])
	for resource: String in totals.keys():
		if not resource_rows.has(resource):
			totals.erase(resource)
			continue
		var held: float = float(int(sim.resources.get(resource, 0)))
		if _counter.has(resource):
			_counter[resource]["final"] = held
		else:
			var before: float = maxf(0.0, held - float(totals[resource]))
			_counter[resource] = {"shown": before, "goal": before, "final": held, "icons_left": 0, "pulse": 0.0}
	# Pieces are spread over the batch so 3-6 glyphs cover every building (Collect-all may
	# involve many). Any piece that cannot be placed adds its amount to the counter at once.
	var pieces: int = clampi(batch.size() * 2, ICON_MIN, ICON_MAX)
	var counts: Array[int] = []
	counts.resize(batch.size())
	counts.fill(0)
	for index in pieces:
		counts[index % batch.size()] += 1
	var immediate: Dictionary = {}
	for index in batch.size():
		var event: Dictionary = batch[index]
		var resource: String = str(event["resource"])
		var amount: float = float(event["amount"])
		if not totals.has(resource):
			continue
		var count: int = counts[index]
		if count == 0:
			immediate[resource] = float(immediate.get(resource, 0.0)) + amount
			continue
		var share: float = amount / float(count)
		var from: Vector2 = _screen_point(event)
		var to: Vector2 = _counter_anchor(resource)
		for piece in count:
			if from.is_finite() and to.is_finite() and _spawn_icon(resource, from, to, share, piece):
				_counter[resource]["icons_left"] = int(_counter[resource]["icons_left"]) + 1
			else:
				immediate[resource] = float(immediate.get(resource, 0.0)) + share
	for resource: String in totals.keys():
		var c: Dictionary = _counter[resource]
		c["goal"] = minf(float(c["final"]), float(c["goal"]) + float(immediate.get(resource, 0.0)))
		if int(c["icons_left"]) == 0:
			c["goal"] = float(c["final"])
		_paint_counter(resource, c)


func _spawn_icon(resource: String, from: Vector2, to: Vector2, share: float, piece: int) -> bool:
	if _free_slots.is_empty():
		return false
	var label: Label = _free_slots.pop_back()
	label.text = str(RESOURCE_GLYPHS.get(resource, "*"))
	label.visible = false
	label.scale = Vector2.ONE
	label.modulate = Color.WHITE
	_icon_jobs.append({"label": label, "resource": resource, "from": from, "to": to, "share": share,
		"age": 0.0, "delay": float(piece) * 0.07 + randf() * 0.05,
		"duration": ICON_SECONDS + randf() * 0.12})
	return true


func _tend_icons(step: float) -> void:
	var index: int = _icon_jobs.size() - 1
	while index >= 0:
		var job: Dictionary = _icon_jobs[index]
		job["age"] = float(job["age"]) + step
		var elapsed: float = float(job["age"]) - float(job["delay"])
		if elapsed >= 0.0:
			var label: Label = job["label"]
			var t: float = clampf(elapsed / float(job["duration"]), 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - t, 2.0)
			var from: Vector2 = job["from"]
			var to: Vector2 = job["to"]
			label.visible = true
			label.position = from.lerp(to, eased) - Vector2(0.0, sin(t * PI) * ICON_ARC) - Vector2(8.0, 12.0)
			label.scale = Vector2.ONE * (1.0 - 0.35 * t)
			label.modulate.a = 1.0 - maxf(0.0, (t - 0.85) / 0.15)
			if t >= 1.0:
				label.visible = false
				_free_slots.append(label)
				_icon_jobs.remove_at(index)
				_land(job)
		index -= 1


func _land(job: Dictionary) -> void:
	var resource: String = str(job["resource"])
	if not _counter.has(resource):
		return
	var c: Dictionary = _counter[resource]
	c["icons_left"] = maxi(0, int(c["icons_left"]) - 1)
	c["goal"] = minf(float(c["final"]), float(c["goal"]) + float(job["share"]))
	if int(c["icons_left"]) == 0:
		c["goal"] = float(c["final"])
	c["pulse"] = 1.0


func _tend_counters(step: float) -> void:
	for resource: String in _counter.keys():
		var c: Dictionary = _counter[resource]
		var shown: float = float(c["shown"])
		var goal: float = float(c["goal"])
		if step > 0.0:
			shown = lerpf(shown, goal, 1.0 - exp(-COUNTER_EASE * step))
			c["pulse"] = maxf(0.0, float(c["pulse"]) - step / PULSE_SECONDS)
		if absf(goal - shown) < 0.05:
			shown = goal
		c["shown"] = shown
		_paint_counter(resource, c)
		if shown == goal and goal == float(c["final"]) and int(c["icons_left"]) == 0 and float(c["pulse"]) <= 0.0:
			_restore_counter(resource)
			_counter.erase(resource)


func _paint_counter(resource: String, c: Dictionary) -> void:
	var label: Variant = resource_rows.get(resource)
	if not (label is Label) or not is_instance_valid(label):
		return
	var counter_label: Label = label
	counter_label.text = _hud_text(resource, int(roundf(float(c["shown"]))))
	var pulse: float = float(c["pulse"])
	counter_label.pivot_offset = counter_label.size * 0.5
	counter_label.scale = Vector2.ONE * (1.0 + 0.16 * pulse)
	counter_label.modulate = Color.WHITE.lerp(COUNTER_TINT, pulse)


func _restore_counter(resource: String) -> void:
	var label: Variant = resource_rows.get(resource)
	if label is Label and is_instance_valid(label):
		var counter_label: Label = label
		counter_label.scale = Vector2.ONE
		counter_label.modulate = Color.WHITE


# Mirrors the base HUD text formats so a ticking counter reads the same as a static one.
func _hud_text(resource: String, held: int) -> String:
	var glyph: String = str(RESOURCE_GLYPHS.get(resource, "*"))
	if _is_small():
		return "%s %d" % [glyph, held]
	return "%s  %d / %d" % [resource.capitalize(), held, int(sim.storage_cap(resource))]


func _screen_point(event: Dictionary) -> Vector2:
	var at: Vector3 = world_position(Vector2(float(event["x"]), float(event["y"])), ICON_HEIGHT)
	if not at.is_finite() or camera.is_position_behind(at):
		return Vector2.INF
	return camera.unproject_position(at)


func _counter_anchor(resource: String) -> Vector2:
	var label: Variant = resource_rows.get(resource)
	if not (label is Label) or not is_instance_valid(label):
		return Vector2.INF
	var counter_label: Label = label
	if not counter_label.is_visible_in_tree():
		return Vector2.INF
	return counter_label.get_global_rect().get_center()
