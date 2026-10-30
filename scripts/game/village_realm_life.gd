extends "res://scripts/game/village_realm.gd"

# Realm life, over the realm layer: neighbours that act, outposts that take land, and raids.
#
#   * Neighbours: each settlement's mood (friendly / wary / hostile, or sworn once beaten) follows
#     border pressure and what the manor does. It shows on its banner. Friendly neighbours send
#     traders who walk to the manor's edge and leave a little Gold; hostile ones send scouts, grow
#     faster and overrun outposts their land swallows.
#   * Tap a settlement (or its land) out in the realm for its card: people, mood, defence, and the
#     two things the manor can do: send gifts or raid it.
#   * Tap wild land near the manor's own to found an outpost. Its claim joins the manor's, so the
#     border moves out, and land a neighbour claimed more weakly changes hands.
#   * Fishing: jetties along the river land Food for the manor while they stand on its land. Tap one
#     for its card; an outpost on a wild bank brings it in.
#   * Raid: the manor's fighters (the village's own warriors and archers, never removed from it)
#     march out as a column you can watch. Their combined levels against the settlement's people
#     decide it. A win brings loot and shrinks the neighbour; beaten down small enough it swears to
#     the manor and its land becomes yours.
#
# Everything the realm decides lives in realm_map.gd and its own save. The only village changes are
# the costs paid on the cards (outpost, gifts, raid supplies) and the Gold/Food that traders and
# raids bring back, all through the simulation's own spend/bank rules (bank respects storage).
#
# Phone budget: at most REALM_TRAVELLERS travelling models and REALM_WARBAND marchers at once;
# outposts are a model and a banner each (at most six).

const REALM_TRAVELLERS: int = 4
const REALM_WARBAND: int = 4
const REALM_TRAVEL_SPEED: float = 2.4
const REALM_TAP_SITE: float = 18.0            # metres from a settlement centre that count as tapping it
const REALM_TAP_OUTPOST: float = 7.0
const REALM_TAP_FISH: float = 6.0
const REALM_EDGE: float = 44.0                # where travellers stop, just past the village plots
const REALM_FIGHTER_MODELS: Array[String] = ["char_warrior", "char_archer", "char_halberdier", "char_pikewoman"]

var _realm_outpost_views: Dictionary = {}     # outpost id -> Node3D
var _realm_travellers: Array[Dictionary] = []  # {model, player, path: Array[Vector3], leg, arrive: Callable}
var _realm_warband: Array[Dictionary] = []     # {model, player, offset: Vector3}
var _realm_card_site: String = ""
var _realm_card_point: Vector2 = Vector2.ZERO
var _realm_card_outpost: int = -1
var _realm_card_fish: int = -1


func _ready() -> void:
	super()
	if realm == null:
		return
	_realm_sync_outposts()


func _process(delta: float) -> void:
	super(delta)
	if realm == null:
		return
	for event: Dictionary in realm.take_events():
		_realm_event(event)
	_vale_check()
	_realm_sync_outposts()
	var moving: float = delta if started and not sim.paused else 0.0
	_realm_move_travellers(moving)
	_realm_move_warband(moving)


# --- Events -------------------------------------------------------------------------------------

func _realm_event(event: Dictionary) -> void:
	var site: Dictionary = realm.settlement(str(event.get("site", "")))
	var name: String = str(site.get("name", "A neighbour"))
	match str(event["kind"]):
		"attitude":
			sim.notice = "%s is now %s." % [name, event["attitude"]]
		"trader":
			_realm_send_traveller(site, "char_haggler", _realm_trader_arrives.bind(name))
		"scout":
			_realm_send_traveller(site, "char_scout", func() -> void: sim.notice = "A scout from %s is watching the manor's border." % name)
		"outpost_lost":
			sim.notice = "%s overran one of the manor's outposts." % name
		"raid_won":
			var loot: Dictionary = event["loot"]
			var gained: Array[String] = []
			for resource: String in loot:
				var banked: int = sim._bank(resource, float(loot[resource]))
				if banked > 0:
					gained.append("+%d %s" % [banked, resource.capitalize()])
			sim.notice = "Victory at %s! %s." % [name, " ".join(PackedStringArray(gained)) if not gained.is_empty() else "Stores are full"]
			if bool(event.get("sworn", false)):
				sim.notice += " %s swears to the manor; its land is yours." % name
		"sworn":
			sim.notice = "%s swears to the manor. Its land is yours, and every workplace yields %d%% more." % [name, int(Sim.VALE_BONUS * 100.0)]
		"raid_lost":
			sim.notice = "The warband was beaten back at %s." % name
		"catch":
			var food: int = sim._bank("food", float(event["loot"]["food"]))
			if food > 0:
				sim.notice = "The manor's fishers land +%d Food from %d spot%s on the river." % [food, int(event["spots"]), "" if int(event["spots"]) == 1 else "s"]
	_realm_refresh_card()


func _realm_trader_arrives(name: String) -> void:
	var gained: Array[String] = []
	for resource: String in RealmMap.TRADER_GIFT:
		var banked: int = sim._bank(resource, float(RealmMap.TRADER_GIFT[resource]))
		if banked > 0:
			gained.append("%d %s" % [banked, resource.capitalize()])
	sim.notice = "A trader from %s arrives%s." % [name, (" with " + ", ".join(PackedStringArray(gained))) if not gained.is_empty() else ""]


# --- Travellers ---------------------------------------------------------------------------------

func _realm_send_traveller(site: Dictionary, asset: String, arrive: Callable) -> void:
	if site.is_empty() or _realm_travellers.size() >= REALM_TRAVELLERS or not _asset_exists(asset):
		arrive.call()
		return
	var from: Vector2 = site["centre"]
	var edge: Vector2 = from.normalized() * REALM_EDGE
	var body: Node3D = _model(asset)
	_realm_root.add_child(body)
	var path: Array[Vector3] = [_realm_ground_point(from), _realm_ground_point(edge), _realm_ground_point(from)]
	body.position = path[0]
	_realm_travellers.append({"model": body, "player": _find_player_cached(asset, body), "path": path, "leg": 1, "arrive": arrive, "clip": ""})


func _realm_ground_point(at: Vector2) -> Vector3:
	return Vector3(at.x, realm_walk_y(at.x, at.y), at.y)


# Out to the manor's edge (the arrival fires there), then home again.
func _realm_move_travellers(delta: float) -> void:
	for index in range(_realm_travellers.size() - 1, -1, -1):
		var record: Dictionary = _realm_travellers[index]
		var body: Node3D = record["model"]
		var player: AnimationPlayer = record["player"]
		if player != null:
			player.speed_scale = 0.0 if delta <= 0.0 else 1.0
			if record["clip"] != "walk" and player.has_animation("walk"):
				player.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
				player.play("walk", 0.15)
				record["clip"] = "walk"
		if delta <= 0.0:
			continue
		var path: Array[Vector3] = record["path"]
		var goal: Vector3 = path[int(record["leg"])]
		var travel := Vector3(goal.x - body.position.x, 0, goal.z - body.position.z)
		if travel.length() < 0.3:
			if int(record["leg"]) == 1:
				(record["arrive"] as Callable).call()
			record["leg"] = int(record["leg"]) + 1
			if int(record["leg"]) >= path.size():
				body.queue_free()
				_realm_travellers.remove_at(index)
			continue
		body.position += travel.limit_length(REALM_TRAVEL_SPEED * delta)
		body.position.y = realm_walk_y(body.position.x, body.position.z)
		body.rotation.y = rotate_toward(body.rotation.y, atan2(travel.x, travel.z), 8.0 * delta)


func realm_traveller_count() -> int:
	return _realm_travellers.size()


# --- Warband ------------------------------------------------------------------------------------

func _realm_move_warband(delta: float) -> void:
	if realm.raid.is_empty():
		for marcher: Dictionary in _realm_warband:
			(marcher["model"] as Node3D).queue_free()
		_realm_warband.clear()
		return
	var site: Dictionary = realm.settlement(str(realm.raid["site"]))
	var start: Vector2 = realm.raid["start"]
	var target: Vector2 = site["centre"]
	var heading: Vector2 = (target - start).normalized()
	if _realm_warband.is_empty():
		var count: int = mini(int(realm.raid.get("fighters", REALM_WARBAND)), REALM_WARBAND)
		for index in count:
			var asset: String = REALM_FIGHTER_MODELS[index % REALM_FIGHTER_MODELS.size()]
			if not _asset_exists(asset):
				continue
			var body: Node3D = _model(asset)
			_realm_root.add_child(body)
			# A short column, two abreast.
			var side := Vector2(-heading.y, heading.x) * (0.7 if index % 2 == 0 else -0.7)
			var back: Vector2 = -heading * 1.3 * float(index / 2)
			_realm_warband.append({"model": body, "player": _find_player_cached(asset, body), "offset": side + back, "clip": ""})
	var at: Vector2 = start.lerp(target, realm.raid_progress())
	for marcher: Dictionary in _realm_warband:
		var body: Node3D = marcher["model"]
		var spot: Vector2 = at + (marcher["offset"] as Vector2)
		body.position = _realm_ground_point(spot)
		body.rotation.y = atan2(heading.x, heading.y)
		var player: AnimationPlayer = marcher["player"]
		if player != null:
			player.speed_scale = 0.0 if delta <= 0.0 else 1.2
			if marcher["clip"] != "walk" and player.has_animation("walk"):
				player.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
				player.play("walk", 0.15)
				marcher["clip"] = "walk"


func realm_warband_count() -> int:
	return _realm_warband.size()


# The village's own fighters ride out on paper; they never leave the village's defence.
func realm_fighters() -> Dictionary:
	var count: int = 0
	var strength: int = 0
	for u: Dictionary in sim.units:
		if str(sim.troop_specs.get(str(u["type"]), {}).get("role", "")) == "combat" and float(u.get("hp", 1)) > 0:
			count += 1
			strength += maxi(1, int(u.get("level", 1)))
	return {"count": count, "strength": strength}


# --- Outposts -----------------------------------------------------------------------------------

func _realm_sync_outposts() -> void:
	var present: Array[int] = []
	for outpost: Dictionary in realm.outposts:
		var id: int = int(outpost["id"])
		present.append(id)
		if _realm_outpost_views.has(id):
			continue
		var pos: Vector2 = outpost["pos"]
		# The tower stands level on a footing or stilts; the footing is placed in world space.
		var base := Node3D.new()
		base.name = "Outpost_%d" % id
		_realm_root.add_child(base)
		var top: float = _realm_footing(base, pos, 0.0, TILE * 0.8)
		var root := Node3D.new()
		root.position = Vector3(pos.x, top, pos.y)
		base.add_child(root)
		var key: String = model_asset("tower", 1)
		if _asset_exists(key):
			var model: Node3D = _model(key)
			root.add_child(model)
			var dims: Array = catalog[key]["dimensions_m"] if catalog.has(key) else [2.0, 2.0, 2.0]
			model.scale = Vector3.ONE * minf(1.6, (TILE * 1.4) / maxf(float(dims[0]), float(dims[2])))
		root.add_child(_ao_disc(TILE * 1.8))
		var pole := _box(Vector3(0.18, 5.0, 0.18), Vector3(1.4, 2.5, 0), Color("2b2d33"), root)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flag := _box(Vector3(1.5, 0.9, 0.06), Vector3(2.2, 4.4, 0), RealmMap.HOME_COLOR, root)
		var flag_material := flag.material_override as StandardMaterial3D
		flag_material.emission_enabled = true
		flag_material.emission = RealmMap.HOME_COLOR.darkened(0.4)
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_realm_outpost_views[id] = base
	for id: int in _realm_outpost_views.keys():
		if id not in present:
			(_realm_outpost_views[id] as Node3D).queue_free()
			_realm_outpost_views.erase(id)


func realm_outpost_views() -> int:
	return _realm_outpost_views.size()


# --- Taps and cards -----------------------------------------------------------------------------

# Taps inside the village (and on its locked plots) behave exactly as before. A tap out in the
# realm opens the card for whatever is there.
func _map_click(screen: Vector2) -> void:
	if realm == null or _placement_active():
		super(screen)
		return
	var point: Vector2 = pick_ground(screen)
	var tile := Vector2i(floori(point.x), floori(point.y))
	if point == Vector2(-1, -1) or sim.in_world(tile) or not expansion.plot_at(point, Sim.EXPANSION_PLOTS, sim.expansions).is_empty():
		super(screen)
		return
	var world: Vector3 = world_position(point)
	if not realm_tap(Vector2(world.x, world.z)):
		super(screen)


# Opens the realm card for a point in world metres. Returns false when nothing of the realm is there.
func realm_tap(at: Vector2) -> bool:
	if absf(at.x) > RealmMap.HALF or absf(at.y) > RealmMap.HALF:
		return false
	_realm_card_site = ""
	_realm_card_outpost = -1
	_realm_card_fish = -1
	_realm_card_point = at
	for outpost: Dictionary in realm.outposts:
		if (outpost["pos"] as Vector2).distance_to(at) <= REALM_TAP_OUTPOST:
			_realm_card_outpost = int(outpost["id"])
			_open_panel("realm_outpost")
			return true
	for spot: Dictionary in realm.fishing_spots:
		var jetty: Vector2 = (spot["pos"] as Vector2) + (spot["dir"] as Vector2) * 2.5
		if jetty.distance_to(at) <= REALM_TAP_FISH:
			_realm_card_fish = int(spot["id"])
			_open_panel("realm_fish")
			return true
	for site: Dictionary in realm.settlements:
		if (site["centre"] as Vector2).distance_to(at) <= REALM_TAP_SITE:
			_realm_card_site = str(site["id"])
			_open_panel("realm_site")
			return true
	var owner: String = realm.owner_at(at.x, at.y)
	if owner != "" and owner != "home":
		_realm_card_site = owner
		_open_panel("realm_site")
		return true
	_open_panel("realm_land")
	return true


func _open_panel(which: String) -> void:
	super(which)
	if realm == null or not which.begins_with("realm_"):
		return
	match which:
		"realm_site":
			_realm_site_card()
		"realm_land":
			_realm_land_card()
		"realm_fish":
			_realm_fish_card()
		"realm_outpost":
			ui.heading("MANOR OUTPOST", side_content)
			ui.rule(side_content)
			ui.body("A watch tower flying the manor's colours. Its land counts as the manor's. A hostile neighbour whose land swallows it will take it.", side_content)
			ui.body("Outposts: %d of %d" % [realm.outposts.size(), RealmMap.OUTPOST_MAX], side_content, 12)
	_layout_ui()


func _realm_refresh_card() -> void:
	if panel.begins_with("realm_") and sidebar.visible:
		_open_panel(panel)


func _realm_site_card() -> void:
	var site: Dictionary = realm.settlement(_realm_card_site)
	if site.is_empty():
		_close_panel()
		return
	var mood: String = realm.attitude(site)
	ui.heading(str(site["name"]).to_upper(), side_content)
	ui.rule(side_content)
	ui.body("%d people · %s\nLand reaches %d m · Defence %d" % [int(site["pop"]), mood.capitalize(), int(realm.claim_radius(site)), int(realm.defence_of(site))], side_content)
	if mood == "sworn":
		ui.body("Sworn to the manor. Its land is yours, and it keeps growing under your banner.", side_content, 12)
		return
	var hint: Dictionary = {
		"friendly": "Friendly. Their traders bring Gold to the manor's edge.",
		"wary": "Wary. Pressing borders will sour them; gifts will warm them.",
		"hostile": "Hostile. They spread faster, send scouts, and will overrun outposts in their way.",
	}
	ui.body(str(hint.get(mood, "")), side_content, 12)
	var swear_why: String = realm.swear_reason(str(site["id"]))
	var swear_cost: Dictionary = realm.swear_cost(site)
	if swear_why.is_empty() and not sim._affordable(swear_cost):
		swear_why = "Not enough for the oath feast: " + _cost_text(swear_cost)
	var swear_button: Button = ui.gold_button("Ask to Swear  ·  " + _cost_text(swear_cost), _realm_swear.bind(str(site["id"])), side_content)
	swear_button.disabled = not swear_why.is_empty()
	swear_button.tooltip_text = swear_why
	ui.body(swear_why if not swear_why.is_empty() else "Their goodwill is high enough to swear them to the manor without a fight.", side_content, 12)
	var gift: Button = ui.command_button("Send Gifts  ·  " + _cost_text(RealmMap.GIFT_COST), _realm_gift.bind(str(site["id"])), side_content)
	gift.disabled = not sim._affordable(RealmMap.GIFT_COST)
	var fighters: Dictionary = realm_fighters()
	var reason: String = realm.raid_reason(str(site["id"]), int(fighters["count"]))
	if reason.is_empty() and not sim._affordable(RealmMap.RAID_COST):
		reason = "Not enough supplies: " + _cost_text(RealmMap.RAID_COST)
	var raid_button: Button = ui.gold_button("Raid  ·  " + _cost_text(RealmMap.RAID_COST), _realm_raid.bind(str(site["id"])), side_content)
	raid_button.disabled = not reason.is_empty()
	raid_button.tooltip_text = reason
	ui.body(reason if not reason.is_empty() else "%d fighters, strength %d. Your fighters still guard the village." % [int(fighters["count"]), int(fighters["strength"])], side_content, 12)


func _realm_land_card() -> void:
	var at: Vector2 = _realm_card_point
	var owner: String = realm.owner_at(at.x, at.y)
	ui.heading("YOUR LAND" if owner == "home" else "WILD LAND", side_content)
	ui.rule(side_content)
	ui.body("An outpost here claims the land around it for the manor and pushes the border out.", side_content)
	var reason: String = realm.outpost_reason(at)
	if reason.is_empty() and not sim._affordable(RealmMap.OUTPOST_COST):
		reason = "Not enough: " + _cost_text(RealmMap.OUTPOST_COST)
	var button: Button = ui.gold_button("Found Outpost  ·  " + _cost_text(RealmMap.OUTPOST_COST), _realm_found_outpost, side_content)
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason
	ui.body(reason if not reason.is_empty() else "Outposts: %d of %d" % [realm.outposts.size(), RealmMap.OUTPOST_MAX], side_content, 12)


# A fishing spot: who fishes it, and how the manor can take it.
func _realm_fish_card() -> void:
	var spot: Dictionary = realm.fishing_spot(_realm_card_fish)
	if spot.is_empty():
		_close_panel()
		return
	var pos: Vector2 = spot["pos"]
	var owner: String = realm.owner_at(pos.x, pos.y)
	ui.heading("FISHING SPOT", side_content)
	ui.rule(side_content)
	if owner == "home":
		ui.body("The manor's fishers work this jetty. It lands %d Food every minute of play." % RealmMap.FISH_FOOD, side_content)
		ui.body("River spots held: %d of %d" % [realm.home_fishing_spots(), realm.fishing_spots.size()], side_content, 12)
		return
	if owner != "":
		ui.body("%s fishes here. Take this bank for the manor (an outpost or a sworn neighbour) and it lands %d Food a minute." % [realm.settlement(owner).get("name", "A neighbour"), RealmMap.FISH_FOOD], side_content)
	else:
		ui.body("An empty jetty on wild river bank. Found an outpost to bring it into the manor's land; its fishers land %d Food a minute." % RealmMap.FISH_FOOD, side_content)
	# The outpost goes on the dry bank behind the jetty.
	_realm_card_point = pos - (spot["dir"] as Vector2) * 4.0
	var reason: String = realm.outpost_reason(_realm_card_point)
	if reason.is_empty() and not sim._affordable(RealmMap.OUTPOST_COST):
		reason = "Not enough: " + _cost_text(RealmMap.OUTPOST_COST)
	var button: Button = ui.gold_button("Found Outpost  ·  " + _cost_text(RealmMap.OUTPOST_COST), _realm_found_outpost, side_content)
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason
	ui.body(reason if not reason.is_empty() else "Outposts: %d of %d" % [realm.outposts.size(), RealmMap.OUTPOST_MAX], side_content, 12)


func _realm_gift(id: String) -> void:
	if not sim._spend(RealmMap.GIFT_COST):
		return
	realm.send_gift(id)
	sim.notice = "Gifts sent to %s." % realm.settlement(id).get("name", "")
	_realm_refresh_card()
	_refresh_hud()


func _realm_swear(id: String) -> void:
	var site: Dictionary = realm.settlement(id)
	if site.is_empty() or not realm.swear_reason(id).is_empty() or not sim._spend(realm.swear_cost(site)):
		return
	realm.swear(id)
	_realm_refresh_card()
	_refresh_hud()


# Act XI, Unite the Vale: keeps the sim's count of sworn rivals and marks the day the last one swears.
func _vale_check() -> void:
	sim.vale_sworn = realm.sworn_count()
	if sim.vale_united or realm.settlements.is_empty() or sim.vale_sworn < realm.settlements.size():
		return
	if legacy.vale:
		sim.vale_united = true   # united in an earlier village: the act is not paid twice
		return
	sim.vale_united = true
	sim._reward({"gold": 2000, "wood": 1500, "food": 1500})
	sim.chronicle.queue_banner("Old Bell", "Act XI is written: every banner in the Vale flies the manor's colour. The Vale is united.")
	sim.notice = "The Vale is united! +2,000 Gold, +1,500 Wood, +1,500 Food."
	if sound:
		_play_sfx("upgrade")


func _build_vale() -> void:
	ui.heading("ACT XI · UNITE THE VALE", side_content)
	ui.body("Bring all five rival settlements to swear to the manor, by gifts or by war. Each sworn rival adds %d%% to every workplace's output, for good." % int(Sim.VALE_BONUS * 100.0), side_content)
	ui.rule(side_content)
	for site: Dictionary in realm.settlements:
		var mood: String = realm.attitude(site)
		var line: String = "Sworn" if mood == "sworn" else "%s · goodwill %d of %d" % [mood.capitalize(), int(float(site["relation"])), int(RealmMap.SWEAR_AT)]
		ui.body("%s: %s" % [str(site["name"]), line], side_content)
	ui.rule(side_content)
	_label("Sworn: %d of %d" % [realm.sworn_count(), realm.settlements.size()], side_content, true)
	if sim.vale_united:
		ui.body("The Vale is united. Manor Renewal is open in More.", side_content, 12)
	else:
		ui.body("Tap a settlement in the realm to send gifts, ask it to swear, or raid it.", side_content, 12)


func _realm_raid(id: String) -> void:
	var fighters: Dictionary = realm_fighters()
	if not realm.raid_reason(id, int(fighters["count"])).is_empty() or not sim._spend(RealmMap.RAID_COST):
		return
	realm.start_raid(id, int(fighters["count"]), int(fighters["strength"]))
	sim.notice = "The warband marches on %s." % realm.settlement(id).get("name", "")
	_close_panel()
	_refresh_hud()


func _realm_found_outpost() -> void:
	if not realm.outpost_reason(_realm_card_point).is_empty() or not sim._spend(RealmMap.OUTPOST_COST):
		return
	realm.found_outpost(_realm_card_point)
	_realm_sync_outposts()
	sim.notice = "An outpost rises. The manor's border moves out."
	_close_panel()
	_refresh_hud()
