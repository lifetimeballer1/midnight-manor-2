extends SceneTree

# Scratch QA capture for visual progression. Not a regression test. For every building type, one
# image: the top row is each game tier as it looked before (art tier = game tier, the model's own
# tray), the bottom row is the same tiers with village_tiers (spread art tiers + the yard ladder).
# Run WITHOUT --headless:
#   godot --path . --resolution 1600x700 --script res://tests/capture_tiers.gd -- --capture-dir=<abs> [--only=cottage,hall] [--night]

const Tiers = preload("res://scripts/game/village_tiers.gd")
const COUSINS := {"stone_quarry": "mine", "bathhouse": "cottage", "forge-quarter": "forge", "manner-citadel": "manor_hall",
	"grand-granary": "storehouse", "manor-gardens": "grove", "market-square": "market", "monument": "oathstone", "hall": "manor_hall"}
const TILE := 2.0
var directory := ""
var only: PackedStringArray = []
var night := false


func _initialize() -> void:
	_run.call_deferred()


func _asset(type_name: String, art: int) -> String:
	var stem: String = COUSINS.get(type_name, type_name)
	var path := "res://art/%s_t%d/%s_t%d.glb" % [stem, art, stem, art]
	if ResourceLoader.exists(path):
		return path
	path = "res://art/%s_t1/%s_t1.glb" % [stem, stem]
	return path if ResourceLoader.exists(path) else ""


func _place(row: Node3D, path: String, size: int, x: float, z: float) -> Node3D:
	var holder := Node3D.new()
	row.add_child(holder)
	holder.position = Vector3(x, 0, z)
	var model: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(model)
	var box := AABB()
	var first := true
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var vi := child as MeshInstance3D
		var b: AABB = vi.transform * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
		# The village-wide soot tint (village_details.attach), so colours compare fairly.
		for surface in vi.mesh.get_surface_count():
			var base := vi.get_active_material(surface) as BaseMaterial3D
			if base and not base.emission_enabled:
				var soot: BaseMaterial3D = base.duplicate()
				soot.albedo_color = Color("5c5249")
				vi.set_surface_override_material(surface, soot)
	model.scale = Vector3.ONE * minf(1.6, (float(size) * TILE - 0.15) / maxf(box.size.x, box.size.z))
	return model


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): directory = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		elif argument == "--night": night = true
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1600, 700)
	var specs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1a2230") if night else Color("9fb6c8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("5a6a90") if night else Color("e0e4ea")
	env.environment.ambient_light_energy = 0.5 if night else 1.0
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.35 if night else 2.2
	sun.light_color = Color("9fb0e0") if night else Color("fff1d8")
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 60)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("4d6232")
	plane.material = gm
	ground.mesh = plane
	stage.add_child(ground)
	var cam := Camera3D.new()
	stage.add_child(cam)
	var names: Array = specs.keys()
	names.sort()
	for type_name: String in names:
		if not only.is_empty() and not only.has(type_name): continue
		if Tiers.skipped(type_name) or _asset(type_name, 1).is_empty(): continue
		var size: int = int(specs[type_name].get("size", 2))
		var max_tier: int = maxi(1, (specs[type_name].get("tiers", []) as Array).size())
		var row := Node3D.new()
		stage.add_child(row)
		var spacing: float = float(size) * TILE + 1.4
		var depth: float = float(size) * TILE * 1.6 + 3.0
		for tier: int in range(1, max_tier + 1):
			var x: float = (float(tier) - (float(max_tier) + 1.0) * 0.5) * spacing
			_place(row, _asset(type_name, tier), size, x, -depth * 0.5)
			var after := _place(row, _asset(type_name, Tiers.art_tier(type_name, tier, max_tier)), size, x, depth * 0.5)
			Tiers.apply(after, type_name, Tiers.stage(tier, max_tier), size)
			var label := Label3D.new()
			label.text = "Lv %d" % tier
			label.font_size = 56
			label.pixel_size = 0.01
			label.outline_size = 10
			label.position = Vector3(x, 0.05, depth * 0.5 + float(size) * TILE * 0.5 + 0.45)
			label.rotation_degrees.x = -70
			row.add_child(label)
		var span: float = maxf(float(max_tier) * spacing, depth * 2.2)
		cam.fov = 32
		var dist: float = span * 0.62 / tan(deg_to_rad(cam.fov * 0.5)) / (1600.0 / 700.0) + float(size) * 1.6
		cam.position = Vector3(0, dist * 0.62, dist * 0.82)
		cam.look_at(Vector3(0, 0.4, 0.2))
		for i: int in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("%s%s.png" % [type_name, "_night" if night else ""]))
		print("CAPTURED ", type_name)
		row.queue_free()
		await process_frame
	print("CAPTURE DONE")
	quit(0)
