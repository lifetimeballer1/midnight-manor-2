extends "res://scripts/game/village_defenses.gd"

# Warfare layer (view only), over the defenses layer. It shows the war rules in
# war_rules.gd on screen:
#   * Raiders wear their trade: each role has its own figure, rams carry an iron-capped log
#     they drive into the gate, bombards drag a little mortar that kicks and smokes when it
#     fires, scouts carry a torch, and a warlord is a head taller, crowned, with its band's
#     banner on its back and a red ring at its feet.
#   * Bombard shells arc over the walls and burst where they land. Bastion shells and fire
#     traps throw a ring of blast across the ground they hit. Burning raiders smoke and flicker,
#     and a raider marked by the watchfire carries an ember over its head.
#   * A warlord's arrival is called out and a health bar for it sits at the top of the screen.
#     When it falls the band breaks, with a banner, a horn and a gold burst.
#   * The defense report that opens after a raid now leads with the battle: who fell, who
#     fled, the warlord's fate, defenders downed, spoils, and which defense did the most.
# Nothing here changes the simulation. Events are marked so each is read once.

const WarRules = preload("res://scripts/game/war_rules.gd")

const WF_MODELS: Dictionary = {"raider": "char_warrior", "scout": "char_ranger", "archer": "char_longbowman",
	"breaker": "char_halberdier", "ram": "char_sapper", "bombard": "char_sapper", "warlord": "char_oathsworn"}
const WF_LOG := Color("6b4a2c")
const WF_IRON := Color(0.2, 0.19, 0.21)
const WF_GOLD := Color(1.0, 0.8, 0.32)
const WF_EMBER := Color(1.0, 0.55, 0.16)
const WF_FIRE := Color(1.0, 0.45, 0.12)
const WF_SMOKE := Color(0.42, 0.4, 0.4)
const WF_WARLORD_SCALE: float = 1.5
const WF_BURN_EVERY: float = 0.3
const WF_BURN_MAX: int = 5          # flame puffs per burn pulse, so a crowd cannot flood the pool

var _wf_mats: Dictionary = {}
var _wf_meshes: Dictionary = {}
var _wf_clock: float = 0.0
var _wf_burn_clock: float = 0.0
var _wf_boss: PanelContainer = null
var _wf_boss_name: Label = null
var _wf_boss_bar: ProgressBar = null
var _wf_boss_note: Label = null


# ---------------------------------------------------------------- figures


func _enemy_asset(u: Dictionary) -> String:
	var asset: String = str(WF_MODELS.get(str(u.get("role", "raider")), ""))
	if asset.is_empty() or not ResourceLoader.exists("res://art/%s/%s.glb" % [asset, asset]):
		return super(u)
	return asset


func _enemy_scale(role: String) -> float:
	if role == "warlord":
		return WF_WARLORD_SCALE
	return super(role)


func _wf_material(colour: Color, glow: bool = false) -> StandardMaterial3D:
	var key: String = colour.to_html() + ("g" if glow else "")
	if not _wf_mats.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.8
		if glow:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.emission_enabled = true
			material.emission = colour
		if colour.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_wf_mats[key] = material
	return _wf_mats[key]


func _wf_cylinder(radius: float, height: float, top: float = -1.0) -> CylinderMesh:
	var key: String = "c%.3f/%.3f/%.3f" % [radius, height, top]
	if not _wf_meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = radius
		mesh.top_radius = radius if top < 0.0 else top
		mesh.height = height
		mesh.radial_segments = 10
		mesh.rings = 1
		_wf_meshes[key] = mesh
	return _wf_meshes[key]


func _wf_part(mesh: Mesh, material: Material, parent: Node3D, at: Vector3, rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.position = at
	part.rotation_degrees = rotation_deg
	parent.add_child(part)
	return part


# The figure's height in its own units, from its meshes, so gear sits on the head.
func _wf_height(model: Node3D) -> float:
	var top: float = 0.0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var box: AABB = model.global_transform.affine_inverse() * mesh_node.global_transform * mesh_node.get_aabb()
		top = maxf(top, box.end.y)
	return top if top > 0.5 else 1.7


func _wf_dress(u: Dictionary, model: Node3D) -> void:
	var gear := Node3D.new()
	gear.name = "WarGear"
	model.add_child(gear)
	model.set_meta("wf_gear", gear)
	var head: float = _wf_height(model)
	match str(u.get("role", "raider")):
		"ram":
			var ram := Node3D.new()
			ram.position = Vector3(0.0, 0.8, 0.45)
			gear.add_child(ram)
			_wf_part(_wf_cylinder(0.15, 1.5), _wf_material(WF_LOG), ram, Vector3(0, 0, 0.35), Vector3(90, 0, 0))
			_wf_part(_wf_cylinder(0.19, 0.22, 0.12), _wf_material(WF_IRON), ram, Vector3(0, 0, 1.15), Vector3(90, 0, 0))
			_wf_part(_wf_cylinder(0.17, 0.06), _wf_material(WF_IRON), ram, Vector3(0, 0, -0.1), Vector3(90, 0, 0))
			model.set_meta("wf_ram", ram)
		"bombard":
			var mortar := Node3D.new()
			mortar.position = Vector3(0.45, 0.0, 0.55)
			gear.add_child(mortar)
			var bed := _wf_part(BoxMesh.new(), _wf_material(WF_LOG), mortar, Vector3(0, 0.14, 0))
			bed.scale = Vector3(0.42, 0.2, 0.6)
			for side: float in [-0.25, 0.25]:
				_wf_part(_wf_cylinder(0.16, 0.06), _wf_material(WF_LOG.darkened(0.3)), mortar, Vector3(side, 0.16, 0.0), Vector3(0, 0, 90))
			var barrel := Node3D.new()
			barrel.position = Vector3(0, 0.3, 0.05)
			barrel.rotation_degrees = Vector3(40, 0, 0)
			mortar.add_child(barrel)
			_wf_part(_wf_cylinder(0.15, 0.5, 0.12), _wf_material(WF_IRON), barrel, Vector3(0, 0.2, 0))
			model.set_meta("wf_mortar", barrel)
		"scout":
			var torch := Node3D.new()
			torch.position = Vector3(-0.32, 0.75, 0.2)
			torch.rotation_degrees = Vector3(15, 0, -10)
			gear.add_child(torch)
			_wf_part(_wf_cylinder(0.03, 0.6), _wf_material(WF_LOG), torch, Vector3(0, 0.3, 0))
			var flame := SphereMesh.new()
			flame.radius = 0.09
			flame.height = 0.24
			flame.radial_segments = 8
			flame.rings = 4
			_wf_part(flame, _wf_material(WF_FIRE, true), torch, Vector3(0, 0.66, 0))
		"warlord":
			var crown := Node3D.new()
			crown.position = Vector3(0, head - 0.04, 0)
			gear.add_child(crown)
			# The figures have big blocky heads, so the band sits wide enough to read over the helm.
			_wf_part(_wf_cylinder(0.3, 0.13, 0.33), _wf_material(WF_GOLD, true), crown, Vector3(0, 0.06, 0))
			for index in 6:
				var angle: float = TAU * index / 6.0
				_wf_part(_wf_cylinder(0.06, 0.2, 0.0), _wf_material(WF_GOLD, true), crown, Vector3(cos(angle) * 0.3, 0.22, sin(angle) * 0.3))
			var banner := Node3D.new()
			banner.position = Vector3(-0.18, 0.55, -0.28)
			gear.add_child(banner)
			_wf_part(_wf_cylinder(0.025, 2.1), _wf_material(WF_LOG.darkened(0.2)), banner, Vector3(0, 1.05, 0))
			var flag := QuadMesh.new()
			flag.size = Vector2(0.62, 0.48)
			var tint: Color = sim.faction_color(str(u.get("faction", "thornband")))
			_wf_part(flag, _wf_material(Color(tint.darkened(0.15), 0.98)), banner, Vector3(0.33, 1.78, 0), Vector3(0, 90, 0))
			_wf_part(_wf_cylinder(0.05, 0.05), _wf_material(WF_GOLD, true), banner, Vector3(0, 2.13, 0))
			var ring := TorusMesh.new()
			ring.inner_radius = 0.62
			ring.outer_radius = 0.74
			ring.rings = 24
			ring.ring_segments = 4
			var halo := _wf_part(ring, _wf_material(Color(0.95, 0.18, 0.12, 0.7), true), gear, Vector3(0, 0.05, 0))
			halo.scale = Vector3(1.0, 0.12, 1.0) / WF_WARLORD_SCALE
			model.set_meta("wf_halo", halo)
	var ember := SphereMesh.new()
	ember.radius = 0.11
	ember.height = 0.22
	ember.radial_segments = 6
	ember.rings = 3
	var mark := _wf_part(ember, _wf_material(WF_EMBER, true), gear, Vector3(0, head + 0.45, 0))
	mark.scale = Vector3(1.0, 1.6, 1.0)
	mark.visible = false
	model.set_meta("wf_mark", mark)


func _update_actors(delta: float) -> void:
	super(delta)
	var step: float = 0.0 if sim.paused else delta
	_wf_clock += step
	for u: Dictionary in sim.enemies:
		var record: Dictionary = actors.get(int(u["id"]), {})
		if record.is_empty():
			continue
		var model: Node3D = record["model"]
		if not is_instance_valid(model):
			continue
		if not model.has_meta("wf_gear"):
			_wf_dress(u, model)
		if not model.visible:
			continue
		var alive: bool = float(u["hp"]) > 0.0
		var mark: Node3D = model.get_meta("wf_mark")
		mark.visible = alive and float(u.get("lit", 0.0)) > 0.0
		if mark.visible:
			mark.position.y = _wf_height_of(model) + 0.45 + sin(_wf_clock * 5.0) * 0.06
			mark.rotation.y = _wf_clock * 3.0
		if model.has_meta("wf_ram"):
			var ram: Node3D = model.get_meta("wf_ram")
			var drive: float = maxf(0.0, sin(_wf_clock * TAU)) if alive and str(u.get("phase", "")) == "attack" else 0.0
			ram.position.z = 0.45 + drive * 0.35
		if model.has_meta("wf_mortar"):
			var barrel: Node3D = model.get_meta("wf_mortar")
			var kick: float = float(model.get_meta("wf_kick", 0.0))
			if kick > 0.0:
				kick = maxf(0.0, kick - step * 4.0)
				model.set_meta("wf_kick", kick)
			barrel.position.z = 0.05 - kick * 0.14
			barrel.rotation_degrees.x = 40.0 + kick * 12.0
		if model.has_meta("wf_halo"):
			var halo: MeshInstance3D = model.get_meta("wf_halo")
			halo.visible = alive
			var pulse: float = 1.0 + sin(_wf_clock * 3.2) * 0.08
			halo.scale = Vector3(pulse, 0.12, pulse) / WF_WARLORD_SCALE
	_wf_burn(step)


func _wf_height_of(model: Node3D) -> float:
	if not model.has_meta("wf_head"):
		model.set_meta("wf_head", _wf_height(model))
	return float(model.get_meta("wf_head"))


# Burning raiders smoke and flicker on a slow pulse, a few at a time.
func _wf_burn(step: float) -> void:
	_wf_burn_clock += step
	if _wf_burn_clock < WF_BURN_EVERY:
		return
	_wf_burn_clock = 0.0
	var shown: int = 0
	for u: Dictionary in sim.enemies:
		if shown >= WF_BURN_MAX or not _effect_budget_open():
			return
		if float(u["hp"]) <= 0.0 or float(u.get("burn", 0.0)) <= 0.0:
			continue
		var at: Vector3 = world_position(sim.position_of(u), 0.9)
		burst_pool.spawn(at, WF_FIRE, 4, 0.55, true)
		burst_pool.spawn(at + Vector3.UP * 0.5, WF_SMOKE, 2, 0.6, true)
		shown += 1


# ---------------------------------------------------------------- events


func _read_combat_events() -> void:
	for event: Dictionary in sim.events:
		if event.has("_wf"):
			continue
		event["_wf"] = true
		match str(event.get("kind", "")):
			"lob":
				_wf_lob(event)
			"blast":
				_wf_blast(Vector2(float(event["x"]), float(event["y"])), float(event.get("radius", 1.0)), str(event.get("side", "home")))
			"warlord":
				_wf_warlord_arrives(event)
			"warlord_fall":
				_wf_warlord_falls(event)
	super()


# A bombard's shell: the mortar kicks, smoke rolls off the muzzle, the ball arcs over and
# bursts on the building it was aimed at.
func _wf_lob(event: Dictionary) -> void:
	var from_tile := Vector2(float(event["from_x"]), float(event["from_y"]))
	var to_tile := Vector2(float(event["x"]), float(event["y"]))
	var muzzle: Vector3 = world_position(from_tile, 0.9)
	for u: Dictionary in sim.enemies:
		if sim.position_of(u).distance_to(from_tile) < 0.3 and actors.has(int(u["id"])):
			var model: Node3D = actors[int(u["id"])]["model"]
			if is_instance_valid(model):
				model.set_meta("wf_kick", 1.0)
				if model.has_meta("wf_mortar"):
					muzzle = (model.get_meta("wf_mortar") as Node3D).global_position + Vector3.UP * 0.4
			break
	if has_method("_voice"):
		call("_voice", "bombard", from_tile)
	if not _effect_budget_open():
		return
	burst_pool.spawn(muzzle, WF_SMOKE, 8, 1.1, true)
	burst_pool.spawn(muzzle, WF_EMBER, 5, 0.6, false)
	var target: Vector3 = world_position(to_tile, 0.8)
	_def_cannon(muzzle, target)
	var flight: float = clampf(muzzle.distance_to(target) * 0.08, 0.3, 0.55)
	var tween: Tween = _effect_tween()
	tween.tween_interval(flight)
	tween.tween_callback(_wf_blast.bind(to_tile, 0.9, "foe"))


# A flat ring of blast that races out over the ground and fades, with a puff of fire or smoke.
func _wf_blast(tile: Vector2, radius: float, side: String) -> void:
	if not _effect_budget_open():
		return
	var tint: Color = WF_FIRE if side == "fire" else (Color(1.0, 0.42, 0.3) if side == "foe" else Color(1.0, 0.72, 0.38))
	var at: Vector3 = world_position(tile, 0.15)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 28
	torus.ring_segments = 4
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(tint, 0.9)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = at
	ring.scale = Vector3(0.2, 0.08, 0.2)
	add_child(ring)
	effect_nodes.append(ring)
	var reach: float = maxf(0.6, radius * TILE * 0.9)
	var tween: Tween = _effect_tween()
	tween.tween_property(ring, "scale", Vector3(reach, 0.08, reach), 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, 0.42)
	tween.tween_callback(ring.queue_free)
	burst_pool.spawn(at + Vector3.UP * 0.4, tint, 12 if side == "fire" else 10, 1.2, side == "fire")
	if side != "fire":
		burst_pool.spawn(at + Vector3.UP * 0.6, WF_SMOKE, 6, 1.3, true)
		if sim.raid_active:
			_shake_level = minf(_shake_level + 0.3, SHAKE_CAP)


func _wf_warlord_arrives(event: Dictionary) -> void:
	_show_combat_banner("A WARLORD RIDES", false)
	if has_method("_voice"):
		call("_voice", "brass")
		call("_voice", "riser")


func _wf_warlord_falls(event: Dictionary) -> void:
	var tile := Vector2(float(event["x"]), float(event["y"]))
	_show_combat_banner("THE WARLORD FALLS", true)
	if has_method("_voice"):
		call("_voice", "horn_win")
		call("_voice", "wall_crash", tile)
	_shake_level = minf(_shake_level + 1.0, SHAKE_CAP)
	var at: Vector3 = world_position(tile, 1.2)
	_impact_burst(at, WF_GOLD, 18, 1.8, true)
	_wf_blast(tile, 1.6, "home")


# ---------------------------------------------------------------- warlord bar


func _process(delta: float) -> void:
	super(delta)
	if not started:
		return
	_wf_update_boss()


func _wf_update_boss() -> void:
	var warlord: Dictionary = WarRules.warlord_of(sim) if sim.raid_active and not is_instance_valid(battle_view) else {}
	if warlord.is_empty():
		if _wf_boss != null and is_instance_valid(_wf_boss):
			_wf_boss.hide()
		return
	if _wf_boss == null or not is_instance_valid(_wf_boss):
		_wf_build_boss()
	var title: String = WarRules.current_warlord_name(sim, warlord)
	if _wf_boss_name.text != title:
		_wf_boss_name.text = title
	_wf_boss_bar.max_value = maxf(1.0, float(warlord["max_hp"]))
	_wf_boss_bar.value = float(warlord["hp"])
	var near: int = 0
	for enemy: Dictionary in sim.enemies:
		if bool(enemy.get("rallied", false)) and float(enemy["hp"]) > 0.0:
			near += 1
	var note: String = "%d / %d  -  rallying %d" % [ceili(float(warlord["hp"])), ceili(float(warlord["max_hp"])), near] if near > 0 \
		else "%d / %d  -  bring it down to break the band" % [ceili(float(warlord["hp"])), ceili(float(warlord["max_hp"]))]
	if _wf_boss_note.text != note:
		_wf_boss_note.text = note
	_wf_boss.show()
	_wf_place_boss()


func _wf_build_boss() -> void:
	_wf_boss = PanelContainer.new()
	_wf_boss.add_theme_stylebox_override("panel", ui.panel_box())
	_wf_boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(_wf_boss)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wf_boss.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	var tag := ui.kicker("WARLORD", top)
	tag.add_theme_color_override("font_color", Color("e86a55"))
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wf_boss_name = Label.new()
	_wf_boss_name.add_theme_font_override("font", UI.font("display"))
	_wf_boss_name.add_theme_font_size_override("font_size", 16)
	_wf_boss_name.add_theme_color_override("font_color", UI.GOLD)
	_wf_boss_name.clip_text = true
	_wf_boss_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_wf_boss_name)
	_wf_boss_bar = ui.bar(1.0, 1.0, column, Color("c23a2e"))
	_wf_boss_bar.custom_minimum_size.y = 10
	_wf_boss_note = ui.body("", column, 12)
	_wf_boss_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	_wf_boss_note.clip_text = true


# Between the two HUD corners when there is room (desktop, sideways phones), else just below them.
func _wf_place_boss() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var width: float = minf(380.0, vp.x - 32.0)
	var left_edge: float = left_dock.position.x + left_dock.size.x + 10.0 if left_dock.visible else 16.0
	var right_edge: float = resource_stack.position.x - 10.0 if resource_stack.visible else vp.x - 16.0
	var height: float = _wf_boss.get_combined_minimum_size().y
	var spot := Vector2((vp.x - width) * 0.5, 12.0)
	if right_edge - left_edge >= width:
		spot.x = (left_edge + right_edge - width) * 0.5
	else:
		var below: float = 0.0
		for dock: Control in [left_dock, resource_stack]:
			if dock.visible and dock.modulate.a > 0.01:
				below = maxf(below, dock.position.y + dock.size.y)
		spot.y = below + 8.0
	_wf_boss.size = Vector2(width, height)
	_wf_boss.position = spot.floor()


# ---------------------------------------------------------------- after the battle


# The defense report that opens after a raid leads with the battle itself.
func _build_raid_report() -> void:
	super()
	var war: Dictionary = sim.war_log
	var last: Dictionary = sim.home_raid.last
	if last.is_empty() or not war.has("base") or int(war.get("wave", -1)) != int(last.get("wave", -2)):
		return
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	side_content.add_child(column)
	side_content.move_child(column, mini(3, side_content.get_child_count() - 1))
	var base: Dictionary = war["base"]
	var slain: Dictionary = war.get("slain", {})
	var total: int = 0
	var parts: Array[String] = []
	for role: String in ["warlord", "ram", "bombard", "breaker", "archer", "raider", "scout"]:
		var count: int = int(slain.get(role, 0))
		if count <= 0:
			continue
		total += count
		parts.append("%d %s" % [count, _wf_role_name(role, count)])
	_wf_row(column, "Raiders slain", str(total), ", ".join(PackedStringArray(parts)))
	if int(war.get("routed", 0)) > 0:
		_wf_row(column, "Fled the field", str(int(war["routed"])), "")
	if not str(war.get("warlord", "")).is_empty():
		if bool(war.get("warlord_slain", false)):
			_wf_row(column, "Warlord", "Slain", "%s fell and the band broke. Bounty +%d gold." % [str(war["warlord"]), int(war.get("bounty", 0))], UI.READY)
		else:
			_wf_row(column, "Warlord", "Escaped", "%s lives to ride again." % str(war["warlord"]), Color("e86a55"))
	var downed: int = maxi(0, int(sim.raid_stats.get("defenders_lost", 0)) - int(base.get("defenders_lost", 0)))
	_wf_row(column, "Defenders down", str(downed), "They come round after the raid." if downed > 0 else "")
	if bool(war.get("victory", false)) and float(war.get("spoils", 0.0)) > 0.0:
		_wf_row(column, "Spoils", "+%d gold" % int(float(war["spoils"])), "", UI.READY)
	var best: String = ""
	var best_damage: float = 0.0
	for source: String in war.get("damage_by", {}):
		var amount: float = float(war["damage_by"][source])
		if amount > best_damage:
			best_damage = amount
			best = source
	if not best.is_empty():
		_wf_row(column, "Fiercest defense", _wf_source_name(best), "%d damage dealt." % int(best_damage), UI.GOLD)
	ui.rule(column)


func _wf_row(parent: Node, label: String, value: String, detail: String, tint: Color = UI.PAPER) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var caption := Label.new()
	caption.text = label
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", UI.MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var amount := Label.new()
	amount.text = value
	amount.add_theme_font_override("font", UI.font("strong"))
	amount.add_theme_font_size_override("font_size", 16)
	amount.add_theme_color_override("font_color", tint)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	if not detail.is_empty():
		ui.body(detail, parent, 12)


func _wf_role_name(role: String, count: int) -> String:
	var single: Dictionary = {"warlord": "warlord", "ram": "ram", "bombard": "bombard", "breaker": "breaker",
		"archer": "archer", "raider": "raider", "scout": "scout"}
	var word: String = str(single.get(role, role))
	return word if count == 1 else word + "s"


func _wf_source_name(source: String) -> String:
	if sim.building_specs.has(source):
		return str(sim.building_specs[source].get("name", source.capitalize()))
	if sim.troop_specs.has(source):
		return str(sim.troop_specs[source].get("name", source.capitalize())) + "s"
	return source.capitalize()
