extends SceneTree

# Asset theme. The GLBs ship with the autumn palette already baked in, so by default the runtime
# regrade is OFF (only --legacy-autumn-art turns it on) and only the soot lightening runs. The
# legacy grade is exercised in-process below by setting the same switch the flag sets.

const REAL_PALETTE_ASSETS: Array[String] = [
	"res://art/manor_hall_t1/manor_hall_t1.glb",
	"res://art/mill_t3/mill_t3.glb",
	"res://art/forge_t3/forge_t3.glb",
	"res://art/char_warrior/char_warrior.glb",
]

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)


func _surfaces(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var material := mesh.surface_get_material(s) as StandardMaterial3D
			if material != null and material.albedo_texture != null and material.albedo_texture.get_width() == 64:
				out.append(material)
	for child in node.get_children():
		_surfaces(child, out)


# The first material under the node that carries an albedo texture.
func _first_albedo(node: Node) -> BaseMaterial3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var part := node as MeshInstance3D
		for s in part.mesh.get_surface_count():
			var material := part.get_active_material(s) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				return material
	for child in node.get_children():
		var found := _first_albedo(child)
		if found != null:
			return found
	return null


# The shared palette exactly as the GLB ships it (no runtime grade involved). The file is parsed
# with GLTFDocument rather than load(): load() reads Godot's import cache (.godot/imported), which
# goes stale when a GLB is re-exported and headless runs do not re-import it.
func _real_palette(path: String) -> Image:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var node: Node = doc.generate_scene(state)
	if node == null:
		return null
	var image: Image = null
	var material := _first_albedo(node)
	if material != null:
		image = material.albedo_texture.get_image()
		if image != null:
			image = image.duplicate()
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
	node.free()
	return image


func _near(c: Color, ref: Color) -> bool:
	return absf(c.r - ref.r) <= 0.02 and absf(c.g - ref.g) <= 0.02 and absf(c.b - ref.b) <= 0.02


func _scan_palette(image: Image) -> Dictionary:
	var out: Dictionary = {"blue": 0, "warm": 0, "amber": 0, "first_blue": ""}
	var warm_ref: Array[Color] = [Color("a45f20"), Color("5b3416"), Color("93846a")]
	var amber_ref := Color("ff8625")
	for y in image.get_height():
		for x in image.get_width():
			var c: Color = image.get_pixel(x, y)
			if c.h >= 0.47 and c.h <= 0.72 and c.s > 0.25 and c.v > 0.12:
				out["blue"] += 1
				if str(out["first_blue"]) == "":
					out["first_blue"] = c.to_html(false)
			for ref in warm_ref:
				if _near(c, ref):
					out["warm"] += 1
					break
			if _near(c, amber_ref):
				out["amber"] += 1
	return out


# Counts (dark soot overrides, lightened overrides) under the building layer.
func _soot_counts(game) -> Vector2i:
	var dark: int = 0
	var lightened: int = 0
	var stack: Array = [game.building_layer]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			for s in (n as MeshInstance3D).mesh.get_surface_count():
				var ov := (n as MeshInstance3D).get_surface_override_material(s) as BaseMaterial3D
				if ov != null and ov.albedo_color.is_equal_approx(game.ART_SOOT_OLD):
					dark += 1
				if ov != null and ov.albedo_color.is_equal_approx(game.ART_SOOT):
					lightened += 1
	return Vector2i(dark, lightened)


func _run() -> void:
	root.size = Vector2i(390, 844)
	var game = load("res://scenes/game.tscn").instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	game.set_process(false)

	# Default: the runtime regrade is off, the shipped palette is used as-is, soot lightening runs.
	check(game.get("_art_soot_on") != null and game._art_soot_on, "the soot lightening layer is in the chain and on")
	check(not game._art_on, "the runtime palette regrade is off by default (legacy only)")

	var total: int = 0
	for key: String in game.catalog:
		var node: Node3D = game._model(key)
		total += 1
		node.queue_free()
	check(total >= 300, "all 310 catalogued models were loaded (%d)" % total)
	check(game._art_graded == 0, "no model material is regraded at load by default (%d)" % game._art_graded)
	check(game._art_palette == null, "no runtime palette copy is built by default")

	# Buildings in the village: the dark soot is lightened, with the soot switch on.
	game._rebuild_buildings()
	var soot: Vector2i = _soot_counts(game)
	check(soot.x == 0, "no building keeps the dark soot")
	check(soot.y > 0, "buildings wear the lighter autumn weathering (%d)" % soot.y)

	# The soot switch (--no-autumn-art) turns the lightening off and leaves the dark soot alone.
	game._art_soot_on = false
	game._rebuild_buildings()
	var unlit: Vector2i = _soot_counts(game)
	check(unlit.y == 0 and unlit.x > 0, "with the soot switch off the dark soot is left as it was (%d dark, %d lightened)" % [unlit.x, unlit.y])
	game._art_soot_on = true
	game._rebuild_buildings()

	# The palette the GLBs ship with, read straight from the files.
	for path in REAL_PALETTE_ASSETS:
		var label: String = path.get_file().get_basename()
		var image: Image = _real_palette(path)
		check(image != null, "%s: a textured material with a palette image is found" % label)
		if image == null:
			continue
		var scan: Dictionary = _scan_palette(image)
		check(int(scan["blue"]) == 0, "%s: no blue or teal pixel in the shipped palette (%d found, first %s)" % [label, int(scan["blue"]), str(scan["first_blue"])])
		check(int(scan["warm"]) > 0, "%s: the warm autumn colours are in the shipped palette (%d pixels)" % [label, int(scan["warm"])])
		check(int(scan["amber"]) > 0, "%s: the amber glow ff8625 is still in the shipped palette (%d pixels)" % [label, int(scan["amber"])])
		print("PALETTE ", label, " ", image.get_size(), " blue=", scan["blue"], " warm=", scan["warm"], " amber=", scan["amber"])

	# Legacy grade, in-process: the same switch --legacy-autumn-art sets in _ready().
	game._art_on = true
	var ungraded: Array[String] = []
	for key: String in game.catalog:
		var node: Node3D = game._model(key)
		var surfaces: Array = []
		_surfaces(node, surfaces)
		if surfaces.is_empty():
			ungraded.append(key + " (no palette surface)")
		for material: StandardMaterial3D in surfaces:
			if material.albedo_texture != game._art_palette:
				ungraded.append(key)
		node.queue_free()
	check(game._art_graded > 0, "the legacy switch regrades the materials (%d)" % game._art_graded)
	check(ungraded.is_empty(), "legacy: every model uses the graded palette: %s" % str(ungraded.slice(0, 5)))
	var graded_after: int = game._art_graded
	var again: Node3D = game._model("manor_hall_t1")
	again.queue_free()
	check(game._art_graded == graded_after, "legacy: a model that is already graded is not graded again")

	var image: Image = game._art_palette.get_image()
	check(image.get_size() == Vector2i(64, 64), "legacy: graded palette keeps its 64x64 layout")
	var cold: int = 0
	for y in 64:
		for x in 64:
			var c: Color = image.get_pixel(x, y)
			if c.s > 0.25 and c.v > 0.12 and c.h * 360.0 > 150.0 and c.h * 360.0 < 265.0:
				cold += 1
	check(cold == 0, "legacy: no blue, teal or cyan is left in the graded palette (%d pixels)" % cold)
	check(image.get_pixel(0, 0).is_equal_approx(Color.WHITE), "legacy: plain white cells are untouched")
	var seen: Dictionary = {}
	var worst_shift: float = 0.0
	var dark_ok: bool = true
	for key: String in game.ART_GRADE:
		var before := Color(key)
		var after := Color(str(game.ART_GRADE[key]))
		worst_shift = maxf(worst_shift, absf(after.v - before.v))
		if before.v < 0.2:
			dark_ok = dark_ok and after.v < 0.32
		seen[str(game.ART_GRADE[key])] = true
	check(seen.size() == game.ART_GRADE.size(), "legacy: no two palette colours collapse into one")
	check(worst_shift < 0.4 and dark_ok, "legacy: grading keeps lights light and darks dark so shapes still read (worst %.3f)" % worst_shift)
	var amber: Color = game._art_grade_colour(Color("ff8625"))
	check(amber.is_equal_approx(Color("ff8625")), "legacy: the amber lamp colour is left alone")
	var odd: Color = game._art_grade_colour(Color("2060c0"))
	check(odd.r > Color("2060c0").r and odd.b < Color("2060c0").b, "legacy: an unknown blue is warmed generically")
	game._art_on = false

	print("ASSETS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
