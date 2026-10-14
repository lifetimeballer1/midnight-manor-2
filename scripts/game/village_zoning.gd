extends "res://scripts/game/village_polish.gd"

# The town outside the walls: city-builder zoning over the realm layer (model: town_zoning.gd).
#
#   * Zone (bottom bar) opens the zoning tools: Homes, Farms, Industry, Civic, Road and Clear, a
#     1x1 or 3x3 brush, and a Move toggle so one finger can pan on phones (two fingers always do).
#     Tap or drag to paint 4 m cells on the manor's land outside the village and its reaches.
#   * Roads start at the village edge (gold squares while the Road tool is out) or beside an
#     outpost and cost Wood per cell. Zones beside a connected road grow lots on their own when the
#     town wants them; the demand bars show what it wants.
#   * Lots go up as scaffolds, then pop into the zone's art; meeting needs (food, safety, nearby
#     farms, homes, civic buildings, townsfolk) moves them up a level into finer art. Tap a lot for
#     its card: what it is, what it sends the manor, and what its next level needs.
#   * Townsfolk walk the roads. Trees and rocks give way where roads and lots go.
#   * Dragging the Road (or Pave) tool plans a straight run with its cost shown before anything is
#     spent; letting go lays it. Pave turns a road to cobbles for Stone, which speeds the lots
#     beside it and lets the finest homes and halls rise.
#   * The town is never fenced in: a tap on wild ground past its border offers to buy it (a parcel
#     about the size of a few lots, each a little dearer than the last); a tap on a neighbour's land
#     offers to take it by force (a raid that breaks them swears them, and their land, to the manor)
#     or to win them over with gifts. With the tools out, buyable ground shows a gold grid.
#   * With the tools out, each lot held back shows what it needs; a lot cut off from the manor
#     shows it at any time. Income rises off the lots as it arrives, and the town's title (Hamlet,
#     Village...) heads the zoning bar.
#   * The village itself is zoned too, from the first day (village_growth.gd): paint Homes, Farms,
#     Industry or Civic on open village ground and the village's own cottages, farms, lumber camps,
#     mines and chapels rise there free, then grow a tier on their own as the village levels up.
#     The Build menu keeps only what is bought: walls, towers, traps, the gate and the barracks
#     (plus the Great Works). A Raise button for a zoned building opens its zone instead.
#
# Painting never knocks down a lot by accident: zone and road strokes skip built lots, only Clear
# removes them. The village simulation's rules and save format are untouched (zoned buildings are
# ordinary building records); the town banks its income through the simulation's spend/bank rules
# and saves to TOWN_SAVE_PATH on its own, village zones included.
#
# Phone budget: zone colours, the grid and all roads are one mesh each, rebuilt only when the town
# changes; each lot is one footing/yard mesh plus its model; at most TOWN_WALKERS townsfolk
# (TOWN_WALKERS_LOW on phones), only animated near the camera.

const Town = preload("res://scripts/game/town_zoning.gd")
const Growth = preload("res://scripts/game/village_growth.gd")

const TOWN_SAVE_PATH: String = "user://town-v1.json"
const TOWN_SAVE_SECONDS: float = 10.0
const TOWN_TOOLS: Array[String] = ["housing", "farming", "industrial", "civic", "road", "pave", "erase"]
const TOWN_TOOL_NAMES: Dictionary = {"housing": "Homes", "farming": "Farms", "industrial": "Industry", "civic": "Civic", "road": "Road", "pave": "Pave", "erase": "Clear"}
const TOWN_LINE_TOOLS: Array[String] = ["road", "pave"]   # dragging these plans a straight run first
const TOWN_LOT_FIT: float = 3.3             # metres a lot's building spans
const TOWN_LIFT: float = 0.045              # zone colours and roads sit just above the ground
const TOWN_GRID_REACH: float = 72.0         # the paint grid shows this far from the view's centre
const TOWN_WALKERS: int = 6
const TOWN_WALKERS_LOW: int = 3
const TOWN_WALK_SPEED: float = 1.15
const TOWN_LABELS: int = 14               # floating level names and income at once
const TOWN_BADGES: int = 24               # need badges over lots at once, nearest the view first
const TOWN_BADGE_SECONDS: float = 0.6
const TOWN_OPEN_ZOOM: float = 70.0
const TOWN_ERASE_COLOR := Color("d0574a")
const TOWN_DENY_COLOR := Color("b0473d")
const TOWN_ROAD_VERGE := Color("3b3026")
const TOWN_ROAD_BED := Color("665640")
const TOWN_ROAD_RUT := Color("4e4133")
const TOWN_SCAFFOLD := Color("5c4430")
const TOWN_PAVE_COLOR := Color("a3a7ad")
const TOWN_PAVE_VERGE := Color("3f3b36")
const TOWN_PAVE_BED := Color("4e4a44")
const TOWN_PAVE_SETTS: Array[Color] = [Color("5d5851"), Color("54504a"), Color("645f57")]
const TOWN_SAFE_COLOR := Color("6f9be8")
const TOWN_RESOURCE_COLORS: Dictionary = {"gold": Color("f2c75c"), "food": Color("e3c14b"), "wood": Color("c9935a"), "stone": Color("c3c7cc")}
const TOWN_NO_CELL := Vector2i(-9999, -9999)

var town = null
var growth = null                           # village_growth.gd: free buildings on zoned village ground
var _zoning_move: bool = false              # a Move of a zoned building uses the ordinary placement
var town_bar: VBoxContainer = null
var _town_button: Button = null
var _town_root: Node3D = null
var _town_overlay: MeshInstance3D = null
var _town_grid: MeshInstance3D = null
var _town_roads: MeshInstance3D = null
var _town_cursor: MeshInstance3D = null
var _town_overlay_material: StandardMaterial3D = null
var _town_lamp_material: StandardMaterial3D = null
var _town_glow_material: StandardMaterial3D = null
var _town_road_material: StandardMaterial3D = null
var _town_lot_views: Dictionary = {}        # Vector2i -> {root, holder, state, asset, scaffold}
var _town_tool: String = "housing"
var _town_brush: int = 1
var _town_active: bool = false
var _town_pan: bool = false
var _town_stroke: bool = false
var _town_stroke_last: Vector2i = TOWN_NO_CELL
var _town_stroke_denied: bool = false
var _town_stroke_count: int = 0
var _town_drawn_revision: int = -1
var _town_drawn_mode: String = ""
var _town_grid_focus := Vector2(INF, INF)
var _town_grid_revision: int = -1
var _town_save_clock: float = 0.0
var _town_tool_buttons: Dictionary = {}
var _town_brush_button: Button = null
var _town_tools_grid: GridContainer = null
var _town_pan_button: Button = null
var _town_stats_label: Label = null
var _town_hint_label: Label = null
var _town_demand_bars: Dictionary = {}
var _town_card_cell: Vector2i = TOWN_NO_CELL
var _town_walkers: Array[Dictionary] = []
var _town_labels: Array[Node3D] = []
var _town_clear_revision: int = -1
var _town_clear_clock: float = 0.0
var _town_click_clock: float = 0.0
var _town_cursor_cell: Vector2i = TOWN_NO_CELL
var _town_time: float = 0.0
var _town_plan: Array[Vector2i] = []        # a planned road or paving run while the drag lasts
var _town_plan_start: Vector2i = TOWN_NO_CELL
var _town_ghost: MeshInstance3D = null
var _town_ghost_label: Label3D = null
var _town_badges: Dictionary = {}           # Vector2i -> Label3D
var _town_badge_clock: float = 0.0


func _ready() -> void:
	super()
	if realm == null:
		return
	town = Town.new()
	town.realm = realm
	town.height_at = _town_ground_y
	if not no_save and FileAccess.file_exists(TOWN_SAVE_PATH):
		town.from_dict(JSON.parse_string(FileAccess.get_file_as_string(TOWN_SAVE_PATH)))
	growth = Growth.new()
	growth.setup(town.village_spec(), Vector2i(roundi(-MAP_ORIGIN.x / TILE), roundi(-MAP_ORIGIN.z / TILE)), roundi(town.cell / TILE))
	_town_root = Node3D.new()
	_town_root.name = "Town"
	add_child(_town_root)
	_town_build_nodes()
	_town_build_ui()
	_town_sync()


func _process(delta: float) -> void:
	super(delta)
	if town == null:
		return
	var active: bool = started and not sim.paused
	if active:
		_town_advance(delta)
		_town_save_clock += delta
		if _town_save_clock >= TOWN_SAVE_SECONDS:
			_town_save_clock = 0.0
			town_save()
	_town_time += delta
	_town_click_clock = maxf(_town_click_clock - delta, 0.0)
	_town_sync()
	_town_animate(delta, active)
	_town_walk(delta if active else 0.0)
	_town_clear_clock -= delta
	if _town_clear_clock <= 0.0 and _town_clear_revision != town.revision:
		_town_clear_clock = 0.3
		_town_clear_scenery()
	if _town_active:
		var focus := Vector2(target.x, target.z)
		if focus.distance_to(_town_grid_focus) > 12.0 or _town_grid_revision != town.revision:
			_town_build_grid()
	_town_badge_clock -= delta
	if _town_badge_clock <= 0.0:
		_town_badge_clock = TOWN_BADGE_SECONDS
		_town_refresh_badges()


func _notification(what: int) -> void:
	super(what)
	if town != null and what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		town_save()


func town_save() -> bool:
	if town == null or no_save or save_blocked:
		return false
	var file := FileAccess.open(TOWN_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(town.to_dict()))
	return true


# Ground height where the town stands: the realm's drawn ground, or the outskirts' flat haunted
# ground around the village (it lies over the realm ground there).
func _town_ground_y(x: float, z: float) -> float:
	var y: float = realm_surface_y(x, z)
	if absf(x) < REALM_HAUNT_BOX.x and absf(z) < REALM_HAUNT_BOX.y:
		y = maxf(y, -0.03)
	return y


func _town_point(c: Vector2i, lift: float = 0.0) -> Vector3:
	var at: Vector2 = town.cell_centre(c)
	return Vector3(at.x, _town_ground_y(at.x, at.y) + lift, at.y)


# --- Time and events ----------------------------------------------------------------------------

func _town_advance(dt: float) -> void:
	town.village_food = float(sim.resources.get("food", 0.0))
	town.tick(dt)
	for event: Dictionary in town.take_events():
		_town_event(event)
	for event: Dictionary in growth.tick(sim, town, dt):
		_village_grew(event)


# A building rose (or grew a tier) on zoned village ground.
func _village_grew(event: Dictionary) -> void:
	var b: Dictionary = sim.get_building(int(event["id"]))
	if b.is_empty():
		return
	var tile := Vector2i(int(b["x"]), int(b["y"]))
	var size: int = int(b["size"])
	var at: Vector3 = world_position(Vector2(tile) + Vector2.ONE * size * 0.5, 0.4)
	var colour: Color = town.zone_color(growth.zone_of(str(b["type"])))
	_impact_burst(at, colour, 10 if str(event["kind"]) == "rose" else 14, 1.0, true)
	if camera.is_position_in_frustum(at):
		_play_sfx("confirm" if str(event["kind"]) == "rose" else "upgrade")
	_refresh_hud()


func _town_event(event: Dictionary) -> void:
	match str(event["kind"]):
		"grew":
			_town_sync()
			var view: Dictionary = _town_lot_views.get(event["cell"], {})
			if not view.is_empty():
				_town_pop(view, false)
			var zone_name: String = str(town.zone_spec(str(event["zone"])).get("short", "Lot"))
			if _town_on_screen(event["cell"]):
				_play_sfx("confirm")
			if town.stats()["lots"] <= 3:
				sim.notice = "The town grows: new %s outside the walls." % zone_name.to_lower()
		"levelled":
			_town_sync()
			var view: Dictionary = _town_lot_views.get(event["cell"], {})
			if not view.is_empty():
				_town_pop(view, true)
			var level_name: String = str(town.level_spec(str(event["zone"]), int(event["level"])).get("name", ""))
			_town_label(event["cell"], "Level %d: %s" % [int(event["level"]), level_name])
			if _town_on_screen(event["cell"]):
				_play_sfx("upgrade")
		"cleared":
			_impact_burst(_town_point(event["cell"], 0.5), Color("9a8a70"), 8, 1.0, true)
		"income":
			var gained: Array[String] = []
			var income: Dictionary = event["income"]
			for resource: String in income:
				var banked: int = sim._bank(resource, float(income[resource]))
				if banked > 0:
					gained.append("+%d %s" % [banked, resource.capitalize()])
			if not gained.is_empty():
				sim.notice = "The town sends %s." % ", ".join(PackedStringArray(gained))
				_town_income_floaters()
			_refresh_hud()
		"title":
			var won: Array[String] = []
			var reward: Dictionary = event.get("reward", {})
			for resource: String in reward:
				var banked: int = sim._bank(resource, float(reward[resource]))
				if banked > 0:
					won.append("+%d %s" % [banked, resource.capitalize()])
			var line: String = "The town outside the walls is now a %s." % str(event["name"])
			if not won.is_empty():
				line += " The folk send %s." % ", ".join(PackedStringArray(won))
			sim.notice = line
			_play_sfx("upgrade")
			var heart: Vector2i = _town_heart()
			if heart != TOWN_NO_CELL:
				_town_float(heart, str(event["name"]).to_upper(), UI.GOLD, 5.0, 84)
				_impact_burst(_town_point(heart, 2.0), UI.GOLD, 18, 1.6, true)
			_refresh_hud()
	if panel.begins_with("town_") and sidebar.visible:
		_open_panel(panel)


# --- Zoning in the village ------------------------------------------------------------------------

func _zone_grown(type_name: String) -> bool:
	return growth != null and (growth.grows(type_name) or type_name == "hall")


func _build_catalog_note() -> void:
	if growth == null:
		return
	ui.body("Homes, farms, industry and civic buildings are not bought: zone open ground and they rise there free, then grow on their own. Here you buy defences and troops.", side_content, 13)
	ui.gold_button("Zone the Village", _zone_for.bind(""), side_content)


# A Raise button for a zoned building opens its zone instead, and that building rises first.
func _choose_build(type_name: String) -> void:
	if not _zoning_move and growth != null and growth.grows(type_name):
		_zone_for(type_name)
		return
	super(type_name)


func _move_selected() -> void:
	_zoning_move = true
	super()
	_zoning_move = false


func _zone_for(type_name: String) -> void:
	if town == null:
		return
	_close_panel()
	if not _town_active:
		town_open()
	var zone: String = growth.zone_of(type_name)
	if zone.is_empty():
		town_set_tool(_town_tool if _town_tool in town.village_zone_ids() else "housing")
		sim.notice = "Paint Homes, Farms, Industry or Civic on open village ground. Buildings rise there free."
	else:
		if type_name not in growth.wishes:
			growth.wishes.append(type_name)
		town_set_tool(zone)
		sim.notice = "Paint %s on open village ground: the next one there is a %s, free." % [str(TOWN_TOOL_NAMES.get(zone, zone)), str(sim.building_specs[type_name]["name"])]
	_refresh_hud()


# Village tiles taken by standing buildings (zone colours stay faint under them).
func _village_taken() -> Dictionary:
	var taken: Dictionary = {}
	for b: Dictionary in sim.buildings:
		if float(b["hp"]) <= 0.0:
			continue
		for dy in int(b["size"]):
			for dx in int(b["size"]):
				taken[growth.tile_cell(Vector2i(int(b["x"]) + dx, int(b["y"]) + dy))] = true
	return taken


func _town_on_screen(c: Vector2i) -> bool:
	var at: Vector3 = _town_point(c)
	if not camera.is_position_in_frustum(at):
		return false
	return Vector2(at.x, at.z).distance_to(Vector2(target.x, target.z)) < realm_view_reach()


# --- Painting -----------------------------------------------------------------------------------

func town_active() -> bool:
	return _town_active


func town_toggle() -> void:
	if _town_active:
		town_close()
	else:
		town_open()


func town_open() -> void:
	if town == null or _town_active:
		return
	if _placement_active():
		_cancel_placement()
	_close_panel()
	more_sheet.hide()
	_paint_more()
	selected_building = -1
	selected_unit = -1
	_update_marker()
	_town_active = true
	nav.hide()
	town_bar.show()
	_town_refresh_bar()
	_town_drawn_mode = ""
	_town_build_grid()
	_town_cursor.visible = false
	_town_badge_clock = 0.0
	if zoom < TOWN_OPEN_ZOOM:
		var tween := create_tween()
		tween.tween_method(func(value: float) -> void:
			zoom = value
			_camera_update(), zoom, minf(TOWN_OPEN_ZOOM, zoom_max), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_play_sfx("click")
	_layout_ui()


func town_close() -> void:
	if not _town_active:
		return
	_town_active = false
	_town_stroke = false
	_town_clear_plan()
	town_bar.hide()
	nav.show()
	_town_cursor.visible = false
	_town_grid.visible = false
	_town_drawn_mode = ""
	_town_badge_clock = 0.0
	if panel.begins_with("town_"):
		_close_panel()
	town_save()
	_layout_ui()


func town_set_tool(tool: String) -> void:
	if tool not in TOWN_TOOLS:
		return
	_town_tool = tool
	_town_drawn_mode = ""
	_town_grid_revision = -1
	_town_refresh_bar()


func _town_toggle_brush() -> void:
	_town_brush = 3 if _town_brush == 1 else 1
	_town_refresh_bar()


func _town_toggle_pan() -> void:
	_town_pan = not _town_pan
	_town_refresh_bar()


# Paints one cell (or the brush around it) with the current tool. Returns true when anything changed.
func town_paint_cell(c: Vector2i) -> bool:
	var changed: bool = false
	var reach: int = 1 if _town_brush == 3 else 0
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			if _town_paint_one(c + Vector2i(dx, dz), dx == 0 and dz == 0):
				changed = true
	if changed and _town_click_clock <= 0.0:
		_town_click_clock = 0.06
		_play_sfx("click")
	return changed


func _town_paint_one(c: Vector2i, centre: bool) -> bool:
	match _town_tool:
		"erase":
			return town.erase(c)
		"road":
			if town.lots.has(c) or not town.road_reason(c).is_empty():
				if centre and not town.lots.has(c) and not town.roads.has(c):
					_town_deny(town.road_reason(c))
				return false
			var cost: Dictionary = town.road_cost()
			if not sim._spend(cost):
				_town_deny("Roads cost %s a stretch. Not enough in store." % _cost_text(cost))
				return false
			town.paint_road(c)
			_refresh_hud()
			return true
		"pave":
			if not town.pave_reason(c).is_empty():
				if centre and not town.paved.has(c):
					_town_deny(town.pave_reason(c))
				return false
			var cost: Dictionary = town.pave_cost()
			if not sim._spend(cost):
				_town_deny("Paving costs %s a stretch. Not enough in store." % _cost_text(cost))
				return false
			town.pave(c)
			_refresh_hud()
			return true
	if town.in_village(c):
		return _village_paint_one(c, centre)
	if town.lots.has(c) or str(town.zones.get(c, "")) == _town_tool:
		return false
	var reason: String = town.paint_zone(c, _town_tool)
	if not reason.is_empty():
		if centre and reason != "A road runs here.":
			_town_deny(reason)
		return false
	return true


# Zoning village ground: free, and the village's own buildings rise on it (village_growth.gd).
func _village_paint_one(c: Vector2i, centre: bool) -> bool:
	if str(town.village.get(c, "")) == _town_tool:
		return false
	var reason: String = growth.cell_reason(sim, c)
	if reason.is_empty() and _town_tool not in town.village_zone_ids():
		reason = "That zone is for the land outside the walls."
	if not reason.is_empty():
		if centre:
			_town_deny(reason)
		return false
	town.paint_village(c, _town_tool)
	# Something rises soon after the first strokes, not a whole cycle later.
	growth.grow_clock = maxf(growth.grow_clock, float(town.village_spec().get("growSeconds", 5.0)) - 1.5)
	return true


func _town_deny(reason: String) -> void:
	if _town_stroke_denied or reason.is_empty():
		return
	_town_stroke_denied = true
	sim.notice = reason
	_play_sfx("deny")


func _town_stroke_to(c: Vector2i) -> void:
	if _town_stroke_last == TOWN_NO_CELL:
		town_paint_cell(c)
	else:
		# Every cell along the drag, so fast strokes leave no gaps.
		var steps: int = maxi(absi(c.x - _town_stroke_last.x), absi(c.y - _town_stroke_last.y))
		for i in range(1, steps + 1):
			var t: float = float(i) / float(steps)
			var at := Vector2i(roundi(lerpf(_town_stroke_last.x, c.x, t)), roundi(lerpf(_town_stroke_last.y, c.y, t)))
			town_paint_cell(at)
	_town_stroke_last = c
	_town_stroke_count += 1
	_town_place_cursor(c)


# Ground under a screen point, in world metres, following the hills (the village's pick_ground
# assumes flat ground at height 0).
func town_pick(screen: Vector2) -> Vector2:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	if absf(direction.y) < 0.0001:
		return Vector2(INF, INF)
	var height: float = -0.03
	var point := Vector3.ZERO
	for i in 5:
		var t: float = (height - origin.y) / direction.y
		point = origin + direction * t
		height = _town_ground_y(point.x, point.z) if realm != null else 0.0
	return Vector2(point.x, point.z)


func _map_click(screen: Vector2) -> void:
	if town == null or _placement_active():
		super(screen)
		return
	var at: Vector2 = town_pick(screen)
	if not is_finite(at.x):
		super(screen)
		return
	var c: Vector2i = town.cell_of(at)
	if _town_active:
		_town_stroke_denied = false
		# A tap on a built lot shows its card; painting over it takes the Clear tool.
		if town.lots.has(c) and _town_tool != "erase":
			town_inspect(c)
			return
		# Ground past the border: buy it, or see how to take it from whoever holds it.
		if _town_tool != "erase" and _town_land_for_taking(c):
			_town_card_cell = c
			_open_panel("town_land")
			return
		town_paint_cell(c)
		_town_place_cursor(c)
		town_save()
		return
	if not town.in_village(c) and (town.lots.has(c) or town.zones.has(c)):
		town_inspect(c)
		return
	super(screen)


func _drag_map(pointer: Vector2) -> void:
	if not _town_active or _town_pan or not left_pressed or town == null:
		super(pointer)
		return
	if not _town_stroke:
		if pointer.distance_to(press_point) <= _touch_slop():
			return
		_town_stroke = true
		_town_stroke_last = TOWN_NO_CELL
		_town_stroke_denied = false
		_town_stroke_count = 0
		var start: Vector2 = town_pick(press_point)
		_town_plan_start = town.cell_of(start) if is_finite(start.x) else TOWN_NO_CELL
		if is_finite(start.x) and _town_tool not in TOWN_LINE_TOOLS:
			_town_stroke_to(town.cell_of(start))
	left_dragged = true
	var at: Vector2 = town_pick(pointer)
	if is_finite(at.x):
		if _town_tool in TOWN_LINE_TOOLS:
			if _town_plan_start != TOWN_NO_CELL:
				town_plan(_town_plan_start, town.cell_of(at))
				_town_place_cursor(town.cell_of(at))
		else:
			_town_stroke_to(town.cell_of(at))
	last_pointer = pointer


func _input(event: InputEvent) -> void:
	super(event)
	if not _town_active:
		return
	var released: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) \
			or (event is InputEventScreenTouch and not event.pressed)
	if released and _town_stroke:
		_town_stroke = false
		_town_stroke_last = TOWN_NO_CELL
		if not _town_plan.is_empty():
			town_commit_plan()
		town_save()


func _unhandled_input(event: InputEvent) -> void:
	if _town_active and event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if sidebar.visible:
			_close_panel()
		else:
			town_close()
		return
	super(event)
	if _town_active and event is InputEventMouseMotion and not touch_mode:
		var at: Vector2 = town_pick(event.position)
		if is_finite(at.x):
			_town_place_cursor(town.cell_of(at))


func _town_place_cursor(c: Vector2i) -> void:
	if not _town_active:
		return
	_town_cursor_cell = c
	var ok: bool
	match _town_tool:
		"erase":
			ok = town.lots.has(c) or town.zones.has(c) or town.roads.has(c)
		"road":
			ok = town.road_reason(c).is_empty() and not town.lots.has(c)
		"pave":
			ok = town.pave_reason(c).is_empty()
		_:
			ok = town.can_build(c) and not town.roads.has(c)
	var tint: Color = _town_tool_color(_town_tool) if ok else TOWN_DENY_COLOR
	var size: float = town.cell * float(_town_brush)
	_town_cursor.visible = true
	_town_cursor.position = _town_point(c, TOWN_LIFT + 0.05)
	_town_cursor.scale = Vector3(size, 1.0, size)
	(_town_cursor.material_override as StandardMaterial3D).albedo_color = Color(tint, 0.55)


func _town_tool_color(tool: String) -> Color:
	if tool == "erase":
		return TOWN_ERASE_COLOR
	if tool == "pave":
		return TOWN_PAVE_COLOR
	return town.zone_color(tool)


# --- Road runs ----------------------------------------------------------------------------------

# A straight run of cells from one cell to another: along the longer way first, then across.
func town_plan_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [from]
	var at: Vector2i = from
	var delta: Vector2i = to - from
	var first: Vector2i = Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
	var second: Vector2i = Vector2i(0, signi(delta.y)) if first.x != 0 else Vector2i(signi(delta.x), 0)
	while (at - from) * first.abs() != delta * first.abs():
		at += first
		cells.append(at)
	while at != to and second != Vector2i.ZERO:
		at += second
		cells.append(at)
	return cells


# What laying (or paving) one cell of a run would do: "new", "have" (already done, free) or "no".
func _town_plan_state(c: Vector2i) -> String:
	if _town_tool == "pave":
		if town.paved.has(c):
			return "have"
		return "new" if town.pave_reason(c).is_empty() else "no"
	if town.roads.has(c):
		return "have"
	return "new" if town.road_reason(c).is_empty() and not town.lots.has(c) else "no"


func _town_plan_cost(count: int) -> Dictionary:
	var each: Dictionary = town.pave_cost() if _town_tool == "pave" else town.road_cost()
	var total: Dictionary = {}
	for resource: String in each:
		total[resource] = int(each[resource]) * count
	return total


# Plans a run and draws it: the cells it would lay, those it can't, and what it costs.
func town_plan(from: Vector2i, to: Vector2i) -> void:
	_town_plan = town_plan_line(from, to)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fresh: int = 0
	var tint: Color = _town_tool_color(_town_tool)
	for c: Vector2i in _town_plan:
		var state: String = _town_plan_state(c)
		var colour: Color = Color(tint, 0.62) if state == "new" else (Color(1, 1, 1, 0.14) if state == "have" else Color(TOWN_DENY_COLOR, 0.6))
		_town_cell_quad(tool, c, Vector2(0.3, 0.3), Vector2(3.7, 3.7), colour, 0.06)
		if state == "new":
			fresh += 1
	_town_ghost.mesh = tool.commit()
	_town_ghost.visible = true
	var cost: Dictionary = _town_plan_cost(fresh)
	var afford: bool = sim._affordable(cost)
	var noun: String = ("%d to pave" % fresh) if _town_tool == "pave" else ("%d stretch%s of road" % [fresh, "" if fresh == 1 else "es"])
	_town_ghost_label.text = ("%s  ·  %s" % [noun, _cost_text(cost)]) if fresh > 0 else ("Nothing to pave here" if _town_tool == "pave" else "Nothing to lay here")
	if fresh > 0 and not afford:
		_town_ghost_label.text += "  ·  not enough"
	_town_ghost_label.modulate = UI.PAPER if afford and fresh > 0 else Color("f0a08f")
	_town_ghost_label.position = _town_point(_town_plan[_town_plan.size() - 1], 2.6)
	_town_ghost_label.visible = true


# Lays the planned run in order, as far as the stores allow. Returns how many cells were laid.
func town_commit_plan() -> int:
	var laid: int = 0
	var short: bool = false
	var each: Dictionary = town.pave_cost() if _town_tool == "pave" else town.road_cost()
	for c: Vector2i in _town_plan:
		if _town_plan_state(c) != "new":
			continue
		if not sim._spend(each):
			short = true
			break
		if _town_tool == "pave":
			town.pave(c)
		else:
			town.paint_road(c)
		laid += 1
	var noun: String = "paved %d stretch%s" % [laid, "" if laid == 1 else "es"] if _town_tool == "pave" else "laid %d stretch%s of road" % [laid, "" if laid == 1 else "es"]
	if laid > 0:
		sim.notice = ("%s%s." % [noun.capitalize(), (", then the stores ran dry" if short else "")])
		_play_sfx("confirm")
		_refresh_hud()
	elif short:
		_town_stroke_denied = false
		_town_deny("Not enough in store: %s a stretch." % _cost_text(each))
	_town_clear_plan()
	return laid


func _town_clear_plan() -> void:
	_town_plan.clear()
	_town_plan_start = TOWN_NO_CELL
	if _town_ghost != null:
		_town_ghost.visible = false
		_town_ghost_label.visible = false


# --- Cards --------------------------------------------------------------------------------------

func town_inspect(c: Vector2i) -> void:
	_town_card_cell = c
	_open_panel("town_lot" if town.lots.has(c) else "town_cell")


func _open_panel(which: String) -> void:
	super(which)
	if town == null or not which.begins_with("town_"):
		return
	var c: Vector2i = _town_card_cell
	if which == "town_land" and _town_land_for_taking(c):
		_town_land_card(c)
	elif which == "town_lot" and town.lots.has(c):
		_town_lot_card(c)
	elif which == "town_cell" and town.zones.has(c):
		_town_cell_card(c)
	else:
		_close_panel()
		return
	_layout_ui()


func _town_lot_card(c: Vector2i) -> void:
	var lot: Dictionary = town.lots[c]
	var zone: String = str(lot["zone"])
	var spec: Dictionary = town.zone_spec(zone)
	var level: int = int(lot["level"])
	var info: Dictionary = town.level_spec(zone, level)
	ui.heading(str(info.get("name", spec.get("name", "Lot"))).to_upper(), side_content)
	ui.rule(side_content)
	var lines: Array[String] = ["%s / level %d of %d" % [str(spec.get("name", zone)), level, town.max_level(zone)]]
	if not town.built(lot):
		lines.append("Under construction.")
	var cut_off: bool = town.built(lot) and not town.has_access(c)
	if int(info.get("residents", 0)) > 0:
		lines.append("%d townsfolk live here" % int(info["residents"]))
	if int(info.get("jobs", 0)) > 0:
		lines.append("%d jobs" % int(info["jobs"]))
	var income: Dictionary = info.get("income", {})
	if not income.is_empty():
		lines.append("Sends %s a minute" % ("nothing while cut off" if cut_off else _cost_text(income)))
	ui.body("\n".join(PackedStringArray(lines)), side_content)
	if cut_off:
		var warning: Label = ui.body("Cut off: no road from here reaches the manor or an outpost. Join it up and it works again.", side_content, 12)
		warning.add_theme_color_override("font_color", Color("f0a08f"))
	ui.body(str(spec.get("blurb", "")), side_content, 12)
	var needs: Array[Dictionary] = town.next_needs(c)
	if needs.is_empty():
		ui.body("At its finest. Nothing more it needs.", side_content, 12)
	else:
		var next: Dictionary = town.level_spec(zone, level + 1)
		ui.heading("NEXT: %s" % str(next.get("name", "")).to_upper(), side_content)
		# One line per need, green when met; plain marks the web build's font has (no tick glyphs).
		for need: Dictionary in needs:
			var met: bool = bool(need["met"])
			var row: Label = ui.body(("+  " if met else "-  ") + str(need["label"]), side_content, 13)
			row.add_theme_color_override("font_color", Color("9fd88f") if met else Color("e9a58f"))
		ui.bar(float(lot["progress"]), float(next.get("seconds", 60.0)), side_content, town.zone_color(zone))
		for note: Dictionary in town.pace(c)["notes"]:
			var line: Label = ui.body(str(note["label"]), side_content, 12)
			line.add_theme_color_override("font_color", Color("9fd88f") if bool(note["good"]) else Color("e9a58f"))
	ui.command_button("Clear Lot", _town_clear_lot.bind(c), side_content)


func _town_cell_card(c: Vector2i) -> void:
	var zone: String = str(town.zones[c])
	var spec: Dictionary = town.zone_spec(zone)
	ui.heading(("%s ZONE" % str(spec.get("name", zone))).to_upper(), side_content)
	ui.rule(side_content)
	ui.body(str(spec.get("blurb", "")), side_content)
	var why: String
	if not town.has_access(c):
		why = "Waiting for a road (the dotted cells). Zones grow only beside a road that leads back to the manor or an outpost."
	elif float(town.demand().get(zone, 0.0)) <= town.DEMAND_GROW:
		why = "Waiting for demand. The town does not want more %s yet." % str(spec.get("short", zone)).to_lower()
	else:
		why = "Ready. Something will rise here soon."
	ui.body(why, side_content, 12)
	ui.command_button("Unzone", _town_unzone.bind(c), side_content)


# Ground the town could have but does not hold yet: wild, or a neighbour's (not the river, slopes,
# the village or the realm's edge).
func _town_land_for_taking(c: Vector2i) -> bool:
	if town.in_village(c) or not town._ground_reason(c).is_empty():
		return false
	return town.land_owner(c) != "home"


func _town_land_card(c: Vector2i) -> void:
	var owner: String = town.land_owner(c)
	var centre: Vector2 = town.cell_centre(c)
	if owner == "":
		ui.heading("WILD LAND", side_content)
		ui.rule(side_content)
		ui.body("Nobody holds this ground. Buy it and the land about %d m around this spot becomes the manor's, ready to zone." % int(RealmMap.DEED_RADIUS), side_content)
		var cost: Dictionary = realm.deed_cost()
		var reason: String = realm.deed_reason(centre)
		if reason.is_empty() and not sim._affordable(cost):
			reason = "Not enough in store: " + _cost_text(cost)
		var button: Button = ui.gold_button("Buy Land / " + _cost_text(cost), _town_buy_land.bind(c), side_content)
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
		ui.body(reason if not reason.is_empty() else "Land bought so far: %d parcels. Each costs a little more than the last." % realm.deeds.size(), side_content, 12)
		ui.body("An outpost (from the realm map, with the tools put away) claims a wider ring and can stand farther out.", side_content, 12)
		return
	var site: Dictionary = realm.settlement(owner)
	ui.heading(str(site.get("name", "A neighbour")).to_upper() + "'S LAND", side_content)
	ui.rule(side_content)
	ui.body("%d people / %s / defence %d. Their land is not for sale: take it by force, or win them over." % [int(site.get("pop", 0)), realm.attitude(site).capitalize(), int(realm.defence_of(site))], side_content)
	ui.body("Win raids until they are small enough to break, and they swear to the manor: all their land becomes yours to zone.", side_content, 12)
	var fighters: Dictionary = realm_fighters()
	var reason: String = realm.raid_reason(owner, int(fighters["count"]))
	if reason.is_empty() and not sim._affordable(RealmMap.RAID_COST):
		reason = "Not enough supplies: " + _cost_text(RealmMap.RAID_COST)
	var raid_button: Button = ui.gold_button("Raid / " + _cost_text(RealmMap.RAID_COST), _realm_raid.bind(owner), side_content)
	raid_button.disabled = not reason.is_empty()
	raid_button.tooltip_text = reason
	ui.body(reason if not reason.is_empty() else "%d fighters, strength %d, against defence %d." % [int(fighters["count"]), int(fighters["strength"]), int(realm.defence_of(site))], side_content, 12)
	var gift: Button = ui.command_button("Send Gifts / " + _cost_text(RealmMap.GIFT_COST), _realm_gift.bind(owner), side_content)
	gift.disabled = not sim._affordable(RealmMap.GIFT_COST)


# Buys the wild land around a cell for the town. Returns true when it was bought.
func town_buy_land(c: Vector2i) -> bool:
	var centre: Vector2 = town.cell_centre(c)
	var cost: Dictionary = realm.deed_cost()
	if not realm.deed_reason(centre).is_empty() or not sim._affordable(cost):
		_town_stroke_denied = false
		_town_deny(realm.deed_reason(centre) if not realm.deed_reason(centre).is_empty() else "Not enough in store: " + _cost_text(cost))
		return false
	sim._spend(cost)
	realm.buy_deed(centre)
	sim.notice = "The manor buys the land around this spot. Zone it and build."
	_play_sfx("confirm")
	_impact_burst(_town_point(c, 0.6), UI.GOLD, 16, 1.4, true)
	_town_grid_revision = -1
	_town_drawn_mode = ""
	if has_method("realm_save"):
		call("realm_save")
	_refresh_hud()
	return true


func _town_buy_land(c: Vector2i) -> void:
	town_buy_land(c)
	_close_panel()


func _town_clear_lot(c: Vector2i) -> void:
	town.erase(c)
	_close_panel()
	town_save()


func _town_unzone(c: Vector2i) -> void:
	town.erase(c)
	_close_panel()
	town_save()


# --- UI -----------------------------------------------------------------------------------------

func _town_build_ui() -> void:
	_town_button = ui.command_button("Zone", town_toggle, nav, 56.0)
	_paint_ring(_town_button, UI.SLATE, 56.0)
	_town_button.add_theme_font_size_override("font_size", 13)
	_town_button.tooltip_text = "Zone the village and the land outside the walls"
	nav.move_child(_town_button, more_button.get_index() + 1)
	var dock: Node = nav.get_parent()
	town_bar = VBoxContainer.new()
	town_bar.name = "TownBar"
	town_bar.add_theme_constant_override("separation", 8)
	town_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(town_bar)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	town_bar.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_theme_constant_override("separation", 2)
	head.add_child(titles)
	_town_stats_label = Label.new()
	_town_stats_label.add_theme_font_size_override("font_size", 14)
	_town_stats_label.add_theme_color_override("font_color", UI.GOLD)
	titles.add_child(_town_stats_label)
	_town_hint_label = Label.new()
	_town_hint_label.add_theme_font_size_override("font_size", 12)
	_town_hint_label.add_theme_color_override("font_color", UI.PAPER)
	_town_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_town_hint_label.custom_minimum_size = Vector2(220, 0)   # a width to wrap at before the first layout
	titles.add_child(_town_hint_label)
	# Demand bars: one short column per zone, in its colour.
	var demand := HBoxContainer.new()
	demand.add_theme_constant_override("separation", 6)
	demand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	demand.tooltip_text = "What the town wants"
	head.add_child(demand)
	for zone: String in town.zone_ids():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		column.mouse_filter = Control.MOUSE_FILTER_PASS
		column.tooltip_text = "How much the town wants more %s" % str(town.zone_spec(zone).get("short", zone)).to_lower()
		demand.add_child(column)
		var gauge := ProgressBar.new()
		gauge.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		gauge.show_percentage = false
		gauge.custom_minimum_size = Vector2(14, 34)
		gauge.max_value = 1.0
		gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var back := StyleBoxFlat.new()
		back.bg_color = Color(UI.IRON, 0.8)
		back.border_color = UI.IRON_EDGE
		back.set_border_width_all(1)
		back.set_corner_radius_all(3)
		var fill := StyleBoxFlat.new()
		fill.bg_color = town.zone_color(zone)
		fill.set_corner_radius_all(3)
		gauge.add_theme_stylebox_override("background", back)
		gauge.add_theme_stylebox_override("fill", fill)
		column.add_child(gauge)
		var letter := Label.new()
		letter.text = str(town.zone_spec(zone).get("short", zone)).substr(0, 1)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", 11)
		letter.add_theme_color_override("font_color", town.zone_color(zone))
		column.add_child(letter)
		_town_demand_bars[zone] = gauge
	var tools := GridContainer.new()
	_town_tools_grid = tools
	tools.columns = 10
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	town_bar.add_child(tools)
	for tool: String in TOWN_TOOLS:
		var button: Button = ui.command_button(str(TOWN_TOOL_NAMES[tool]), town_set_tool.bind(tool), tools, 44.0)
		button.custom_minimum_size = Vector2(76, 44)
		button.add_theme_font_size_override("font_size", 13)
		_town_tool_buttons[tool] = button
	_town_brush_button = ui.command_button("Brush 1", _town_toggle_brush, tools, 44.0)
	_town_brush_button.custom_minimum_size = Vector2(76, 44)
	_town_brush_button.add_theme_font_size_override("font_size", 13)
	_town_pan_button = ui.command_button("Move", _town_toggle_pan, tools, 44.0)
	_town_pan_button.custom_minimum_size = Vector2(70, 44)
	_town_pan_button.add_theme_font_size_override("font_size", 13)
	_town_pan_button.tooltip_text = "One finger moves the map instead of painting (two fingers always move it)"
	var done: Button = ui.gold_button("Done", town_close, tools, 44.0)
	done.custom_minimum_size = Vector2(76, 44)
	town_bar.hide()


func _town_refresh_bar() -> void:
	if town_bar == null:
		return
	for tool: String in _town_tool_buttons:
		var button: Button = _town_tool_buttons[tool]
		var tint: Color = _town_tool_color(tool)
		var chosen: bool = tool == _town_tool
		var face := StyleBoxFlat.new()
		face.bg_color = tint.darkened(0.35) if chosen else Color(UI.WALNUT_LIGHT, 0.95)
		face.border_color = tint.lightened(0.25) if chosen else tint.darkened(0.2)
		face.set_border_width_all(3 if chosen else 2)
		face.border_width_bottom = 5 if chosen else 4
		face.set_corner_radius_all(8)
		face.content_margin_left = 8
		face.content_margin_right = 8
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, face)
		button.add_theme_color_override("font_color", UI.PAPER if chosen else tint.lightened(0.35))
		button.add_theme_color_override("font_hover_color", UI.PAPER)
		button.add_theme_color_override("font_pressed_color", UI.PAPER)
	_town_brush_button.text = "Brush %dx%d" % [_town_brush, _town_brush]
	_town_pan_button.text = "Moving" if _town_pan else "Move"
	ui.paint_command(_town_pan_button, "pressed" if _town_pan else "normal")
	_town_refresh_status()


func _town_refresh_status() -> void:
	if town == null:
		return
	if _town_button != null:
		_paint_ring(_town_button, UI.GOLD if _town_active else UI.SLATE, 44.0 if _is_small() else 56.0)
	if town_bar == null or not town_bar.visible:
		return
	var stats: Dictionary = town.stats()
	var small: bool = _is_small()
	var heading: String = ("%s  %d folk / %d jobs / %d lots" if small else "%s  %d townsfolk / %d jobs / %d lots") % [town.title().to_upper(), int(stats["people"]), int(stats["jobs"]), int(stats["lots"])]
	var next: Dictionary = town.next_title()
	if not small and not next.is_empty():
		heading += "   (%s at %d)" % [str(next.get("name", "")), int(next.get("people", 0))]
	if int(stats["cut_off"]) > 0:
		heading += ("  /  %d cut off" % int(stats["cut_off"]))
	_town_stats_label.text = heading
	var wants: Dictionary = town.demand()
	for zone: String in _town_demand_bars:
		(_town_demand_bars[zone] as ProgressBar).value = float(wants.get(zone, 0.0))
	var hint: String
	if town.village.is_empty() and _town_tool in town.village_zone_ids():
		hint = "Paint %s on open village ground and buildings rise there free. Outside the walls, lay a Road first." % str(TOWN_TOOL_NAMES.get(_town_tool, ""))
	elif town.roads.is_empty() and _town_tool in ["road", "pave"]:
		hint = "Lay a Road out from the village edge (the gold squares), then paint zones beside it."
	elif town.roads.is_empty() and town.zones.is_empty():
		hint = "Village zones fill on their own. To grow a town outside the walls, lay a Road from the village edge."
	elif town.zones.is_empty() and town.lots.is_empty():
		hint = "Paint Homes beside the road. Farms and Industry give them work."
	elif _town_tool == "road":
		hint = "Road: %s a stretch. Drag to plan a straight run, let go to lay it. Zones grow only beside roads that reach the manor or an outpost." % _cost_text(town.road_cost())
	elif _town_tool == "pave":
		hint = "Pave: %s a stretch turns a road to cobbles. Lots beside it level faster; the finest homes and halls want one." % _cost_text(town.pave_cost())
	elif _town_tool == "erase":
		hint = "Clear: removes zones, roads and lots."
	else:
		hint = "%s: %s" % [str(town.zone_spec(_town_tool).get("name", "")), str(town.zone_spec(_town_tool).get("blurb", ""))]
	if small and hint.length() > 70:
		hint = hint.substr(0, hint.find(".") + 1)
	if hint != _town_hint_label.text:
		_town_hint_label.text = hint
		# The bar's height follows the hint's wrapped lines; settle the layout once it has wrapped.
		_layout_ui.call_deferred()


func _refresh_hud() -> void:
	super()
	_town_refresh_status()


func _layout_ui() -> void:
	super()
	if town == null or town_bar == null:
		return
	_town_fit_raven_note.call_deferred()
	if _town_button != null:
		_paint_ring(_town_button, UI.GOLD if _town_active else UI.SLATE, 44.0 if _is_small() else 56.0)
		_town_button.add_theme_font_size_override("font_size", 12 if _is_small() else 13)
	if _town_tools_grid != null:
		_town_tools_grid.columns = 5 if _is_small() else 10
		for child: Node in _town_tools_grid.get_children():
			(child as Control).custom_minimum_size.x = 0.0 if _is_small() else 76.0
			(child as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL if _is_small() else Control.SIZE_FILL
	if not _town_active:
		return
	# The zoning bar is taller than the nav it replaces; keep the phone sheet above it.
	var view: Vector2 = get_viewport().get_visible_rect().size
	var safe: float = 16.0 if _is_small() else UI.SAFE_MARGIN
	var bar_h: float = maxf(UI.BOTTOM_BAR_H, bottom.get_combined_minimum_size().y)
	bottom.offset_top = -bar_h - safe
	if _is_small() and sidebar.visible:
		var sheet_h: float = minf(sidebar.size.y, maxf(160.0, view.y - bar_h - safe * 3.0 - 96.0))
		sidebar.position = Vector2(safe, view.y - bar_h - safe - 8.0 - sheet_h)
		sidebar.size.y = sheet_h


# The raven's note is pinned just above the toast when it lands; the zoning bar is taller than the
# nav it replaces (and grows when its hint wraps), so keep a note that is showing above the toast.
func _town_fit_raven_note() -> void:
	if _raven_note == null or not is_instance_valid(_raven_note) or not _raven_note.visible:
		return
	if hud_root == null or not is_instance_valid(hud_root) or not toast.is_inside_tree():
		return
	var hud_rect: Rect2 = hud_root.get_global_rect()
	var toast_rect: Rect2 = toast.get_global_rect()
	if toast_rect.size.y <= 0.0:
		return
	var height: float = maxf(_raven_note.offset_bottom - _raven_note.offset_top, _raven_note.size.y)
	_raven_note.offset_bottom = toast_rect.position.y - hud_rect.position.y - 8.0 - hud_rect.size.y
	_raven_note.offset_top = _raven_note.offset_bottom - height


# --- Views --------------------------------------------------------------------------------------

func _town_build_nodes() -> void:
	_town_overlay_material = StandardMaterial3D.new()
	_town_overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_town_overlay_material.vertex_color_use_as_albedo = true
	_town_overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_town_overlay_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_town_overlay_material.disable_receive_shadows = true
	_town_overlay_material.render_priority = 1
	_town_road_material = StandardMaterial3D.new()
	_town_road_material.vertex_color_use_as_albedo = true
	_town_road_material.roughness = 1.0
	_town_road_material.vertex_color_is_srgb = true
	# Drawn after the haunted edge's ground mist, so the town's roads read clearly through it.
	_town_road_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_town_road_material.render_priority = 1
	_town_overlay = MeshInstance3D.new()
	_town_overlay.name = "TownZones"
	_town_overlay.material_override = _town_overlay_material
	_town_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_town_root.add_child(_town_overlay)
	_town_grid = MeshInstance3D.new()
	_town_grid.name = "TownGrid"
	_town_grid.material_override = _town_overlay_material
	_town_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_town_grid.visible = false
	_town_root.add_child(_town_grid)
	_town_roads = MeshInstance3D.new()
	_town_roads.name = "TownRoads"
	_town_roads.material_override = _town_road_material
	_town_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_town_root.add_child(_town_roads)
	_town_cursor = MeshInstance3D.new()
	_town_cursor.name = "TownCursor"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_town_cursor.mesh = plane
	var cursor_material := StandardMaterial3D.new()
	cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cursor_material.no_depth_test = true
	cursor_material.render_priority = 3
	_town_cursor.material_override = cursor_material
	_town_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_town_cursor.visible = false
	_town_root.add_child(_town_cursor)
	# A planned road run: drawn over everything while the drag lasts, with its cost at the far end.
	_town_ghost = MeshInstance3D.new()
	_town_ghost.name = "TownPlan"
	var ghost_material := StandardMaterial3D.new()
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.vertex_color_use_as_albedo = true
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.no_depth_test = true
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_material.render_priority = 3
	_town_ghost.material_override = ghost_material
	_town_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_town_ghost.visible = false
	_town_root.add_child(_town_ghost)
	_town_ghost_label = _town_text_node(40)
	_town_ghost_label.visible = false
	_town_root.add_child(_town_ghost_label)


# Brings every view in line with the model, once per change.
func _town_sync() -> void:
	if town == null:
		return
	var mode: String = "%s/%s/%d" % [str(_town_active), _town_tool if _town_active else "", sim.revision if not town.village.is_empty() else 0]
	if town.revision == _town_drawn_revision and mode == _town_drawn_mode:
		return
	var roads_changed: bool = town.revision != _town_drawn_revision
	_town_drawn_revision = town.revision
	_town_drawn_mode = mode
	_town_build_overlay()
	if roads_changed:
		_town_build_roads()
		_town_sync_lots()
	_town_refresh_status()


# Zone colours: a soft wash over each zoned cell and a bright rim where the zone ends. While the
# tools are out every zone shows; otherwise only cells still waiting to grow do, faintly.
func _town_build_overlay() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = 0
	for c: Vector2i in town.zones:
		var zone: String = str(town.zones[c])
		var has_lot: bool = town.lots.has(c)
		if has_lot and not _town_active:
			continue
		var tint: Color = town.zone_color(zone)
		var waiting: bool = not has_lot and not town.has_access(c)
		var wash: float = (0.16 if has_lot else 0.34) if _town_active else 0.2
		if waiting:
			wash *= 0.45
		var rim: float = 0.85 if _town_active else 0.45
		_town_cell_quad(tool, c, Vector2(0.15, 0.15), Vector2(3.85, 3.85), Color(tint, wash))
		# No road reaches it yet: four dots, so a stalled zone reads apart from one about to grow.
		if waiting:
			for spot: Vector2 in [Vector2(1.05, 1.05), Vector2(2.45, 1.05), Vector2(1.05, 2.45), Vector2(2.45, 2.45)]:
				_town_cell_quad(tool, c, spot, spot + Vector2(0.5, 0.5), Color(tint.lightened(0.15), rim * 0.8), 0.012)
		for d: Vector2i in town.DIRS:
			if str(town.zones.get(c + d, "")) == zone:
				continue
			var from := Vector2(0.15, 0.15)
			var to := Vector2(3.85, 3.85)
			match d:
				Vector2i(1, 0): from.x = 3.5
				Vector2i(-1, 0): to.x = 0.5
				Vector2i(0, 1): from.y = 3.5
				Vector2i(0, -1): to.y = 0.5
			_town_cell_quad(tool, c, from, to, Color(tint.lightened(0.2), rim), 0.01)
		count += 1
	# The Road tool marks where a road may start: the village edge, beside every reach.
	if _town_active and _town_tool == "road" and town.roads.size() < 3:
		var half: Vector2 = town.VILLAGE_HALF / town.cell
		for x in range(-int(half.x), int(half.x)):
			for c: Vector2i in [Vector2i(x, int(half.y)), Vector2i(x, -int(half.y) - 1)]:
				if town.can_build(c) and not town.roads.has(c):
					_town_cell_quad(tool, c, Vector2(0.6, 0.6), Vector2(3.4, 3.4), Color(UI.GOLD, 0.32 + 0.1 * float(posmod(x, 2))))
		for z in range(-int(half.y), int(half.y)):
			for c: Vector2i in [Vector2i(int(half.x), z), Vector2i(-int(half.x) - 1, z)]:
				if town.can_build(c) and not town.roads.has(c):
					_town_cell_quad(tool, c, Vector2(0.6, 0.6), Vector2(3.4, 3.4), Color(UI.GOLD, 0.32 + 0.1 * float(posmod(z, 2))))
		count += 1
	# Zoned village ground: the same wash, faint under buildings that stand on it already.
	if not town.village.is_empty():
		var taken: Dictionary = _village_taken()
		for c: Vector2i in town.village:
			var zone: String = str(town.village[c])
			var built: bool = taken.has(c)
			if built and not _town_active:
				continue
			var tint: Color = town.zone_color(zone)
			var wash: float = (0.14 if built else 0.34) if _town_active else 0.1
			var rim: float = 0.85 if _town_active else 0.4
			_town_cell_quad(tool, c, Vector2(0.15, 0.15), Vector2(3.85, 3.85), Color(tint, wash))
			for d: Vector2i in town.DIRS:
				if str(town.village.get(c + d, "")) == zone:
					continue
				var from := Vector2(0.15, 0.15)
				var to := Vector2(3.85, 3.85)
				match d:
					Vector2i(1, 0): from.x = 3.5
					Vector2i(-1, 0): to.x = 0.5
					Vector2i(0, 1): from.y = 3.5
					Vector2i(0, -1): to.y = 0.5
				_town_cell_quad(tool, c, from, to, Color(tint.lightened(0.2), rim), 0.01)
			count += 1
	_town_overlay.mesh = tool.commit() if count > 0 else null


# A quad over part of a cell (offsets in metres from its corner), split so it follows the ground.
func _town_cell_quad(tool: SurfaceTool, c: Vector2i, from: Vector2, to: Vector2, colour: Color, extra: float = 0.0) -> void:
	var corner := Vector2(float(c.x) * town.cell, float(c.y) * town.cell)
	var steps: int = 2
	var points: Array[Vector3] = []
	for j in steps + 1:
		for i in steps + 1:
			var p: Vector2 = corner + from + (to - from) * Vector2(float(i) / steps, float(j) / steps)
			points.append(Vector3(p.x, _town_ground_y(p.x, p.y) + TOWN_LIFT + extra, p.y))
	tool.set_color(colour)
	for j in steps:
		for i in steps:
			var a: Vector3 = points[j * (steps + 1) + i]
			var b: Vector3 = points[j * (steps + 1) + i + 1]
			var d: Vector3 = points[(j + 1) * (steps + 1) + i]
			var e: Vector3 = points[(j + 1) * (steps + 1) + i + 1]
			for p: Vector3 in [a, b, e, a, e, d]:
				tool.add_vertex(p)


# The paint grid: a faint outline on every cell the town may use, near the view's centre.
func _town_build_grid() -> void:
	_town_grid_focus = Vector2(target.x, target.z)
	_town_grid_revision = town.revision
	_town_grid.visible = _town_active
	if not _town_active:
		return
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre: Vector2i = town.cell_of(_town_grid_focus)
	var reach: int = int(TOWN_GRID_REACH / town.cell)
	var count: int = 0
	var line := Color(1.0, 0.97, 0.88, 0.16)
	# The Civic tool shows where the town is safe already (walls, outposts, watch posts).
	var show_safe: bool = _town_tool == "civic"
	var sale := Color(UI.GOLD, 0.42)
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c: Vector2i = centre + Vector2i(dx, dz)
			if town.in_village(c):
				# Village ground the manor holds can be zoned: the same faint grid.
				if growth.cell_reason(sim, c).is_empty() and not town.village.has(c):
					_town_cell_quad(tool, c, Vector2(0.0, 0.0), Vector2(4.0, 0.09), line, -0.005)
					_town_cell_quad(tool, c, Vector2(0.0, 0.0), Vector2(0.09, 4.0), line, -0.005)
					count += 1
				continue
			if not town.can_build(c):
				# Wild ground the town could buy shows a faint gold grid.
				if town.buyable(c):
					_town_cell_quad(tool, c, Vector2(0.0, 0.0), Vector2(4.0, 0.14), sale, 0.0)
					_town_cell_quad(tool, c, Vector2(0.0, 0.0), Vector2(0.14, 4.0), sale, 0.0)
					count += 1
				continue
			if town.roads.has(c):
				continue
			if show_safe and town.safe(c):
				_town_cell_quad(tool, c, Vector2(0.0, 0.0), Vector2(4.0, 4.0), Color(TOWN_SAFE_COLOR, 0.11), -0.008)
				count += 1
			if town.lots.has(c):
				continue
			# Two edges per cell (the far edges come from the neighbours), plus the outer ones.
			_town_cell_quad(tool, c, Vector2(0.0, 0.0), Vector2(4.0, 0.09), line, -0.005)
			_town_cell_quad(tool, c, Vector2(0.0, 0.0), Vector2(0.09, 4.0), line, -0.005)
			if not town.can_build(c + Vector2i(0, 1)):
				_town_cell_quad(tool, c, Vector2(0.0, 3.91), Vector2(4.0, 4.0), line, -0.005)
			if not town.can_build(c + Vector2i(1, 0)):
				_town_cell_quad(tool, c, Vector2(3.91, 0.0), Vector2(4.0, 4.0), line, -0.005)
			count += 1
	_town_grid.mesh = tool.commit() if count > 0 else null


# Roads: a dark verge, a packed-earth bed and two wheel ruts, joined toward each neighbouring
# road (and into the village at its edge). Lots get a short path out to their road.
func _town_build_roads() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = town.cell * 0.5
	var count: int = 0
	for c: Vector2i in town.roads:
		var centre: Vector2 = town.cell_centre(c)
		var arms: Array[Vector2i] = []
		for d: Vector2i in town.DIRS:
			if town.roads.has(c + d) or town.in_village(c + d):
				arms.append(d)
		var paved: bool = town.paved.has(c)
		var layers: Array = [[1.45, TOWN_PAVE_VERGE if paved else TOWN_ROAD_VERGE, 0.0], [1.08, TOWN_PAVE_BED if paved else TOWN_ROAD_BED, 0.012]]
		for layer: Array in layers:
			var w: float = layer[0]
			_town_strip(tool, centre + Vector2(-w, -w), centre + Vector2(w, w), layer[1], layer[2])
			for d: Vector2i in arms:
				var dir := Vector2(d)
				var side := Vector2(-dir.y, dir.x)
				var a: Vector2 = centre + dir * w - side * w
				var b: Vector2 = centre + dir * (half + 0.02) + side * w
				_town_strip(tool, a, b, layer[1], layer[2])
		if paved:
			_town_setts(tool, c, centre, arms)
			count += 1
			continue
		# Wheel ruts along each arm.
		for d: Vector2i in arms:
			var dir := Vector2(d)
			var side := Vector2(-dir.y, dir.x)
			for offset: float in [-0.42, 0.42]:
				var a: Vector2 = centre + side * (offset - 0.07) - dir * 0.3
				var b: Vector2 = centre + dir * (half + 0.02) + side * (offset + 0.07)
				_town_strip(tool, a, b, TOWN_ROAD_RUT, 0.02)
		count += 1
	for c: Vector2i in town.lots:
		var d: Vector2i = town.road_side(c)
		if d == Vector2i.ZERO:
			continue
		var centre: Vector2 = town.cell_centre(c)
		var dir := Vector2(d)
		var side := Vector2(-dir.y, dir.x)
		_town_strip(tool, centre + dir * 1.2 - side * 0.38, centre + dir * (half + 0.4) + side * 0.38, TOWN_ROAD_BED.darkened(0.08), 0.008)
		count += 1
	if count == 0:
		_town_roads.mesh = null
		return
	_town_roads.mesh = tool.commit()


# Cobbles on a paved road: rows of setts in slightly different greys over the bed and its arms.
func _town_setts(tool: SurfaceTool, c: Vector2i, centre: Vector2, arms: Array[Vector2i]) -> void:
	var half: float = town.cell * 0.5
	var w: float = 1.0
	var boxes: Array[Rect2] = [Rect2(centre - Vector2(w, w), Vector2(w, w) * 2.0)]
	for d: Vector2i in arms:
		var dir := Vector2(d)
		var side := Vector2(-dir.y, dir.x)
		var a: Vector2 = centre + dir * w - side * w
		var b: Vector2 = centre + dir * half + side * w
		boxes.append(Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs()))
	var size: float = 0.5
	for box: Rect2 in boxes:
		var nx: int = maxi(1, roundi(box.size.x / size))
		var nz: int = maxi(1, roundi(box.size.y / size))
		var step := Vector2(box.size.x / nx, box.size.y / nz)
		for j in nz:
			for i in nx:
				var corner: Vector2 = box.position + Vector2(i, j) * step
				var shade: Color = TOWN_PAVE_SETTS[posmod(i * 7 + j * 3 + c.x * 5 + c.y, TOWN_PAVE_SETTS.size())]
				_town_strip(tool, corner + Vector2(0.04, 0.04), corner + step - Vector2(0.04, 0.04), shade, 0.02)


# An axis-aligned strip between two corners, split into 1 m pieces so it follows the ground.
func _town_strip(tool: SurfaceTool, a: Vector2, b: Vector2, colour: Color, extra: float) -> void:
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var nx: int = maxi(1, ceili((high.x - low.x) / 1.0))
	var nz: int = maxi(1, ceili((high.y - low.y) / 1.0))
	tool.set_color(colour)
	tool.set_normal(Vector3.UP)
	for j in nz:
		for i in nx:
			var p0 := Vector2(lerpf(low.x, high.x, float(i) / nx), lerpf(low.y, high.y, float(j) / nz))
			var p1 := Vector2(lerpf(low.x, high.x, float(i + 1) / nx), lerpf(low.y, high.y, float(j + 1) / nz))
			var v00 := Vector3(p0.x, _town_ground_y(p0.x, p0.y) + TOWN_LIFT + extra, p0.y)
			var v10 := Vector3(p1.x, _town_ground_y(p1.x, p0.y) + TOWN_LIFT + extra, p0.y)
			var v01 := Vector3(p0.x, _town_ground_y(p0.x, p1.y) + TOWN_LIFT + extra, p1.y)
			var v11 := Vector3(p1.x, _town_ground_y(p1.x, p1.y) + TOWN_LIFT + extra, p1.y)
			for v: Vector3 in [v00, v10, v11, v00, v11, v01]:
				tool.add_vertex(v)


# Lot views: a scaffold while building, the zone level's art once built.
func _town_sync_lots() -> void:
	for c: Vector2i in _town_lot_views.keys():
		if not town.lots.has(c):
			(_town_lot_views[c]["root"] as Node3D).queue_free()
			_town_lot_views.erase(c)
	for c: Vector2i in town.lots:
		var lot: Dictionary = town.lots[c]
		var state: String = "done" if town.built(lot) else "build"
		var asset: String = town.lot_asset(lot) if state == "done" else ""
		var facing: Vector2i = town.road_side(c)
		if _town_lot_views.has(c):
			var view: Dictionary = _town_lot_views[c]
			if view["state"] == state and view["asset"] == asset and view["facing"] == facing:
				continue
			(view["root"] as Node3D).queue_free()
		_town_lot_views[c] = _town_lot_view(c, lot, state, asset, facing)


func _town_lot_view(c: Vector2i, lot: Dictionary, state: String, asset: String, facing: Vector2i) -> Dictionary:
	var centre: Vector2 = town.cell_centre(c)
	var root := Node3D.new()
	root.name = "Lot_%d_%d" % [c.x, c.y]
	_town_root.add_child(root)
	var turn: float = atan2(float(facing.x), float(facing.y)) if facing != Vector2i.ZERO else 0.0
	var top: float = _town_footing(root, centre, turn, lot)
	var holder := Node3D.new()
	holder.position = Vector3(centre.x, top, centre.y)
	holder.rotation.y = turn
	root.add_child(holder)
	var scaffold: Node3D = null
	if state == "build":
		scaffold = _town_scaffold()
		holder.add_child(scaffold)
	elif _asset_exists(asset):
		var model: Node3D = _model(asset)
		holder.add_child(model)
		var dims: Array = catalog[asset]["dimensions_m"] if catalog.has(asset) else [2.0, 2.0, 2.0]
		model.scale = Vector3.ONE * minf(1.6, TOWN_LOT_FIT / maxf(maxf(float(dims[0]), float(dims[2])), 0.1))
		holder.add_child(_ao_disc(TOWN_LOT_FIT + 0.6))
		_town_lantern(holder)
	return {"root": root, "holder": holder, "state": state, "asset": asset, "facing": facing, "scaffold": scaffold, "cell": c}


# A lantern on a post at the yard's road corner: a warm point of light in the town at night.
func _town_lantern(holder: Node3D) -> void:
	if _town_lamp_material == null:
		_town_lamp_material = StandardMaterial3D.new()
		_town_lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_town_lamp_material.albedo_color = Color("ffc46e")
	var post: MeshInstance3D = _realm_props([
		[Vector3(0.09, 1.25, 0.09), Transform3D(Basis(), Vector3(1.5, 0.62, 1.5)), Color("2b2520")],
		[Vector3(0.34, 0.06, 0.06), Transform3D(Basis(), Vector3(1.4, 1.22, 1.5)), Color("2b2520")],
	])
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(post)
	var lamp := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.2, 0.16)
	lamp.mesh = box
	lamp.material_override = _town_lamp_material
	lamp.position = Vector3(1.28, 1.08, 1.5)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(lamp)
	# A soft halo that only shows after dark (its shared material follows the time of day).
	if _town_glow_material == null:
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		ramp.colors = PackedColorArray([Color(1, 0.8, 0.5, 0.9), Color(1, 0.7, 0.4, 0.35), Color(1, 0.6, 0.3, 0.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = ramp
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		_town_glow_material = StandardMaterial3D.new()
		_town_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_town_glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_town_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_town_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_town_glow_material.albedo_texture = texture
		_town_glow_material.albedo_color = Color(1, 1, 1, 0)
		_town_glow_material.render_priority = 2
	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	glow.mesh = quad
	glow.material_override = _town_glow_material
	glow.position = lamp.position
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(glow)


# The yard every lot stands in, tinted by its zone, on level ground: flat ground needs nothing,
# a slope gets the realm's stone footing or timber stilts. Returns the level the lot stands at.
func _town_footing(parent: Node3D, centre: Vector2, turn: float, lot: Dictionary) -> float:
	var half: float = 1.75
	var low: float = INF
	var high: float = -INF
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var y: float = _town_ground_y(centre.x + sx * half, centre.y + sz * half)
			low = minf(low, y)
			high = maxf(high, y)
	var top: float = high
	if high - low >= 0.18 and not (absf(centre.x) < REALM_HAUNT_BOX.x and absf(centre.y) < REALM_HAUNT_BOX.y):
		top = _realm_footing(parent, centre, turn, half)
	var tint: Color = town.zone_color(str(lot["zone"]))
	var earth: Color = Color("5a4a35").lerp(tint, 0.18)
	var yard: MeshInstance3D = _realm_props([
		[Vector3(3.7, 0.06, 3.7), Transform3D(Basis(Vector3.UP, turn), Vector3(centre.x, top + 0.01, centre.y)), earth],
		[Vector3(3.3, 0.07, 3.3), Transform3D(Basis(Vector3.UP, turn), Vector3(centre.x, top + 0.015, centre.y)), earth.lightened(0.08)],
	])
	yard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(yard)
	return top + 0.05


# Timber scaffolding: corner posts, two rings of beams, a plank stack and a stone outline.
func _town_scaffold() -> Node3D:
	var parts: Array = []
	var wood: Color = TOWN_SCAFFOLD
	for sx: float in [-1.25, 1.25]:
		for sz: float in [-1.25, 1.25]:
			parts.append([Vector3(0.14, 2.3, 0.14), Transform3D(Basis(), Vector3(sx, 1.15, sz)), wood.darkened(0.15)])
	for y: float in [1.0, 2.15]:
		parts.append([Vector3(2.64, 0.1, 0.1), Transform3D(Basis(), Vector3(0, y, -1.25)), wood])
		parts.append([Vector3(2.64, 0.1, 0.1), Transform3D(Basis(), Vector3(0, y, 1.25)), wood])
		parts.append([Vector3(0.1, 0.1, 2.64), Transform3D(Basis(), Vector3(-1.25, y, 0)), wood])
		parts.append([Vector3(0.1, 0.1, 2.64), Transform3D(Basis(), Vector3(1.25, y, 0)), wood])
	parts.append([Vector3(2.7, 0.12, 2.7), Transform3D(Basis(), Vector3(0, 0.06, 0)), REALM_STONE])
	parts.append([Vector3(2.2, 0.08, 2.2), Transform3D(Basis(), Vector3(0, 1.04, 0)), wood.lightened(0.1)])
	for i in 3:
		parts.append([Vector3(1.4, 0.08, 0.3), Transform3D(Basis(Vector3.UP, 0.1 * i), Vector3(1.9, 0.08 + 0.09 * i, 0.4)), wood.lightened(0.15)])
	var frame: MeshInstance3D = _realm_props(parts)
	var pivot := Node3D.new()
	pivot.add_child(frame)
	return pivot


# The scaffold rises with the work; finished lots settle in with a squash and a puff of dust.
func _town_animate(_delta: float, active: bool) -> void:
	var build_time: float = float(town.specs.get("buildSeconds", 6.0))
	for c: Vector2i in _town_lot_views:
		var view: Dictionary = _town_lot_views[c]
		var scaffold: Node3D = view["scaffold"]
		if scaffold == null or not is_instance_valid(scaffold) or not town.lots.has(c):
			continue
		var done: float = 1.0 - clampf(float(town.lots[c]["build"]) / build_time, 0.0, 1.0)
		scaffold.scale = Vector3(1.0, lerpf(0.25, 1.0, done), 1.0)
		if active:
			scaffold.position.y = absf(sin(_town_time * 9.0 + float(c.x * 3 + c.y))) * 0.03
	if _town_glow_material != null:
		_town_glow_material.albedo_color.a = 1.0 - smoothstep(0.1, 0.5, day_blend)
	if _town_cursor.visible:
		var material := _town_cursor.material_override as StandardMaterial3D
		material.albedo_color.a = 0.42 + 0.16 * sin(_town_time * 5.0)


func _town_pop(view: Dictionary, levelled: bool) -> void:
	var holder: Node3D = view["holder"]
	if not is_instance_valid(holder):
		return
	var c: Vector2i = view["cell"]
	var tint: Color = town.zone_color(str(town.lots[c]["zone"])) if town.lots.has(c) else UI.GOLD
	holder.scale = Vector3(0.7, 0.05, 0.7)
	var tween := create_tween()
	tween.tween_property(holder, "scale", Vector3(1.07, 1.12, 1.07), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var at: Vector3 = holder.global_position + Vector3(0, 0.6, 0)
	_impact_burst(at, Color("cdb898"), 10, 1.3, true)
	if levelled:
		_impact_burst(at + Vector3(0, 1.2, 0), UI.GOLD, 12, 1.0, true)
	else:
		_impact_burst(at + Vector3(0, 0.4, 0), tint, 6, 0.8, true)


# A floating name that rises and fades over a lot that just moved up a level.
func _town_label(c: Vector2i, text: String) -> void:
	_town_float(c, text, UI.GOLD, 3.4, 54)


# Text in the world: billboarded, drawn over the town, dark-outlined to read on any ground. Only
# glyphs the web build's default font has (no stars or ticks).
func _town_text_node(font_size: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = font_size
	label.outline_size = maxi(8, font_size / 4)
	# The same size on screen at any zoom, so a badge stays readable from the town view.
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.outline_modulate = Color(0.08, 0.06, 0.04, 0.9)
	label.render_priority = 4
	label.outline_render_priority = 3
	return label


# Floating text that rises and fades over a cell (level names, income, the town's new title).
func _town_float(c: Vector2i, text: String, colour: Color, height: float, font_size: int, delay: float = 0.0) -> void:
	if text.is_empty() or not started:
		return
	while _town_labels.size() >= TOWN_LABELS:
		var oldest: Node3D = _town_labels.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var label: Label3D = _town_text_node(font_size)
	label.text = text
	label.modulate = Color(colour, 0.0 if delay > 0.0 else 1.0)
	label.position = _town_point(c, height)
	_town_root.add_child(label)
	_town_labels.append(label)
	var tween := create_tween()
	tween.set_parallel(true)
	if delay > 0.0:
		tween.tween_property(label, "modulate:a", 1.0, 0.15).set_delay(delay)
	tween.tween_property(label, "position:y", label.position.y + 2.2, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(delay)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(delay + 1.4)
	var id: int = label.get_instance_id()
	tween.chain().tween_callback(func() -> void:
		var node: Object = instance_from_id(id)
		if node != null:
			_town_labels.erase(node)
			(node as Node).queue_free())


# Income rising off the lots that sent it: the nearest few on screen, each in its resource's colour.
func _town_income_floaters() -> void:
	var focus := Vector2(target.x, target.z)
	var senders: Array[Vector2i] = []
	for c: Vector2i in town.lots:
		var lot: Dictionary = town.lots[c]
		if not town.built(lot) or not town.has_access(c) or not _town_on_screen(c):
			continue
		if (town.level_spec(str(lot["zone"]), int(lot["level"])).get("income", {}) as Dictionary).is_empty():
			continue
		senders.append(c)
	senders.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return town.cell_centre(a).distance_to(focus) < town.cell_centre(b).distance_to(focus))
	for index in mini(senders.size(), TOWN_LABELS - 2):
		var c: Vector2i = senders[index]
		var lot: Dictionary = town.lots[c]
		var income: Dictionary = town.level_spec(str(lot["zone"]), int(lot["level"]))["income"]
		var resource: String = str(income.keys()[0])
		_town_float(c, "+%d %s" % [int(income[resource]), resource.capitalize()], TOWN_RESOURCE_COLORS.get(resource, UI.GOLD), 1.6, 38, 0.06 * index)


# The middle of the built town (the built lot nearest its centre), for town-wide moments.
func _town_heart() -> Vector2i:
	var sum := Vector2.ZERO
	var built: Array[Vector2i] = []
	for c: Vector2i in town.lots:
		if town.built(town.lots[c]):
			built.append(c)
			sum += town.cell_centre(c)
	if built.is_empty():
		return TOWN_NO_CELL
	var middle: Vector2 = sum / float(built.size())
	var best: Vector2i = built[0]
	for c: Vector2i in built:
		if town.cell_centre(c).distance_to(middle) < town.cell_centre(best).distance_to(middle):
			best = c
	return best


# Need badges: with the tools out, each lot held back shows the first thing it needs; a lot cut
# off from the manor says so at any time. Only the lots nearest the view get one.
func _town_refresh_badges() -> void:
	var wanted: Dictionary = {}
	var focus := Vector2(target.x, target.z)
	var reach: float = realm_view_reach()
	var found: Array[Vector2i] = []
	for c: Vector2i in town.lots:
		if not town.built(town.lots[c]) or town.cell_centre(c).distance_to(focus) > reach:
			continue
		var text: String = town.problem(c) if _town_active else ("No road" if not town.has_access(c) else "")
		if text.is_empty():
			continue
		wanted[c] = text
		found.append(c)
	var most: int = TOWN_BADGES / 2 if _realm_phone else TOWN_BADGES
	if found.size() > most:
		found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return town.cell_centre(a).distance_to(focus) < town.cell_centre(b).distance_to(focus))
		for c: Vector2i in found.slice(most):
			wanted.erase(c)
	for c: Vector2i in _town_badges.keys():
		if not wanted.has(c):
			(_town_badges[c] as Node).queue_free()
			_town_badges.erase(c)
	for c: Vector2i in wanted:
		var text: String = str(wanted[c])
		var badge: Label3D = _town_badges.get(c, null)
		if badge == null:
			badge = _town_text_node(30)
			_town_root.add_child(badge)
			_town_badges[c] = badge
		var cut_off: bool = text == "No road"
		badge.text = text if cut_off else "Needs " + (text if text.left(1).is_valid_int() else text.to_lower())
		badge.modulate = Color("f0a08f") if cut_off else Color("f3e6c8")
		badge.position = _town_point(c, 4.4)


func town_badge_texts() -> Dictionary:
	var result: Dictionary = {}
	for c: Vector2i in _town_badges:
		result[c] = (_town_badges[c] as Label3D).text
	return result


# --- Townsfolk ----------------------------------------------------------------------------------

func _town_walk(delta: float) -> void:
	var network: Dictionary = town.network()
	var built: int = 0
	for c: Vector2i in town.lots:
		if town.built(town.lots[c]):
			built += 1
	var wanted: int = 0
	if network.size() >= 2:
		wanted = mini(built / 2 + (1 if built > 0 else 0), TOWN_WALKERS_LOW if _realm_phone else TOWN_WALKERS)
	while _town_walkers.size() > wanted:
		var gone: Dictionary = _town_walkers.pop_back()
		(gone["model"] as Node3D).queue_free()
	if _town_walkers.size() < wanted:
		var asset: String = REALM_WALKER_CLIPS[_town_walkers.size() % REALM_WALKER_CLIPS.size()]
		if _asset_exists(asset):
			var cells: Array = network.keys()
			var start: Vector2i = cells[randi() % cells.size()]
			var body: Node3D = _model(asset)
			_town_root.add_child(body)
			body.position = _town_point(start)
			_town_walkers.append({"model": body, "player": _find_player_cached(asset, body), "path": [], "wait": randf_range(0.0, 2.0), "clip": "", "cell": start, "side": 0.45 if randf() < 0.5 else -0.45})
	var focus := Vector2(target.x, target.z)
	var reach: float = realm_view_reach() + 8.0
	for walker: Dictionary in _town_walkers:
		var body: Node3D = walker["model"]
		var near: bool = Vector2(body.position.x, body.position.z).distance_to(focus) < reach
		body.visible = near
		var player: AnimationPlayer = walker["player"]
		if player != null:
			player.speed_scale = 0.0 if delta <= 0.0 or not near else 1.0
		if delta <= 0.0:
			continue
		var clip: String = "idle"
		var path: Array = walker["path"]
		if not network.has(walker["cell"]):
			if network.is_empty():
				continue
			walker["cell"] = network.keys()[randi() % network.size()]
			body.position = _town_point(walker["cell"])
			path.clear()
		if path.is_empty():
			walker["wait"] = float(walker["wait"]) - delta
			if float(walker["wait"]) <= 0.0:
				walker["path"] = _town_route(walker["cell"], network)
				walker["wait"] = randf_range(1.5, 4.5)
		else:
			var goal_cell: Vector2i = path[0]
			var goal: Vector3 = _town_point(goal_cell)
			var travel := Vector3(goal.x - body.position.x, 0, goal.z - body.position.z)
			# Keep to one side of the road, like people do.
			var heading: Vector3 = travel.normalized() if travel.length() > 0.01 else Vector3.FORWARD
			var lane := Vector3(-heading.z, 0, heading.x) * float(walker["side"])
			travel += lane * 0.15
			if Vector3(goal.x - body.position.x, 0, goal.z - body.position.z).length() < 0.6:
				walker["cell"] = goal_cell
				path.pop_front()
			else:
				body.position += travel.limit_length(TOWN_WALK_SPEED * delta)
				body.position.y = _town_ground_y(body.position.x, body.position.z) + 0.03
				body.rotation.y = rotate_toward(body.rotation.y, atan2(travel.x, travel.z), 8.0 * delta)
				clip = "walk"
		if player != null and near and walker["clip"] != clip and player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			player.play(clip, 0.15)
			walker["clip"] = clip


# A walk along the road network from one cell to a random other one (breadth first).
func _town_route(from: Vector2i, network: Dictionary) -> Array:
	var cells: Array = network.keys()
	if cells.size() < 2:
		return []
	var goal: Vector2i = cells[randi() % cells.size()]
	var came: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if at == goal:
			break
		for d: Vector2i in town.DIRS:
			var next: Vector2i = at + d
			if network.has(next) and not came.has(next):
				came[next] = at
				queue.append(next)
	if not came.has(goal):
		return []
	var path: Array = []
	var step: Vector2i = goal
	while step != from:
		path.push_front(step)
		step = came[step]
	return path


func town_walker_count() -> int:
	return _town_walkers.size()


# --- Clearing the land --------------------------------------------------------------------------

# Trees, shrubs, rocks and grass outside the village give way where a road or lot stands (and
# come back if it is cleared). Instances are hidden, never deleted.
func _town_clear_scenery() -> void:
	_town_clear_revision = town.revision
	var taken: Dictionary = {}
	for c: Vector2i in town.roads:
		taken[c] = true
	for c: Vector2i in town.lots:
		taken[c] = true
	for node: Node in _town_scenery_nodes():
		_town_clear_multimesh(node as MultiMeshInstance3D, taken)


func _town_scenery_nodes() -> Array[Node]:
	var found: Array[Node] = []
	var roots: Array[Node] = []
	for name: String in ["Scenery", "HauntEdge"]:
		var node: Node = get_node_or_null(name)
		if node != null:
			roots.append(node)
	for child: Node in get_children():
		if child is MultiMeshInstance3D and str(child.name).begins_with("Autumn"):
			found.append(child)
		elif str(child.name).begins_with("SkirtRocks") or str(child.name).begins_with("AutumnGrass"):
			roots.append(child)
	if is_instance_valid(_realm_root):
		for child: Node in _realm_root.get_children():
			if child is MultiMeshInstance3D and not str(child.name).begins_with("RealmBorder"):
				found.append(child)
	for root_node: Node in roots:
		for child: Node in root_node.find_children("*", "MultiMeshInstance3D", true, false):
			found.append(child)
		if root_node is MultiMeshInstance3D:
			found.append(root_node)
	return found


func _town_clear_multimesh(node: MultiMeshInstance3D, taken: Dictionary) -> void:
	if not is_instance_valid(node) or node.multimesh == null:
		return
	var multimesh: MultiMesh = node.multimesh
	if multimesh.transform_format != MultiMesh.TRANSFORM_3D or multimesh.instance_count == 0:
		return
	if not multimesh.has_meta("town_original"):
		# Only multimeshes with something outside the village are ever touched.
		var originals: Array[Transform3D] = []
		var cells := PackedVector2Array()
		var any_out: bool = false
		var to_world: Transform3D = node.global_transform
		for index in multimesh.instance_count:
			var xform: Transform3D = multimesh.get_instance_transform(index)
			originals.append(xform)
			var at: Vector3 = to_world * xform.origin
			var c: Vector2i = town.cell_of(Vector2(at.x, at.z))
			cells.append(Vector2(c))
			any_out = any_out or not town.in_village(c)
		multimesh.set_meta("town_original", originals if any_out else [])
		multimesh.set_meta("town_cells", cells)
		multimesh.set_meta("town_hidden", PackedByteArray())
	var originals: Array = multimesh.get_meta("town_original")
	if originals.is_empty() or originals.size() != multimesh.instance_count:
		return
	var cells: PackedVector2Array = multimesh.get_meta("town_cells")
	var hidden: PackedByteArray = multimesh.get_meta("town_hidden")
	if hidden.size() != originals.size():
		hidden.resize(originals.size())
		hidden.fill(0)
	var gone := Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -60, 0))
	for index in originals.size():
		var hide: int = 1 if taken.has(Vector2i(cells[index])) else 0
		if hide != hidden[index]:
			hidden[index] = hide
			multimesh.set_instance_transform(index, gone if hide == 1 else originals[index])
	multimesh.set_meta("town_hidden", hidden)


# --- Test and capture helpers -------------------------------------------------------------------

func town_lot_views() -> int:
	return _town_lot_views.size()


func town_road_mesh_ok() -> bool:
	return town.roads.is_empty() or (_town_roads.mesh != null and _town_roads.mesh.get_surface_count() > 0)


func town_overlay_ok() -> bool:
	return _town_overlay.mesh != null or town.zones.size() == town.lots.size()
