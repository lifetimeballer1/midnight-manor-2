extends RefCounted

const MOSS_META := "atmosphere_moss"
const SLAB_BASE := Color("4d6038")   # the base slab colour set in village_game.gd (rain darkens it at runtime)
const VIGNETTE_NAME := "AtmosphereVignette"
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.6;
uniform vec3 tint = vec3(0.03, 0.05, 0.12);

void fragment() {
	float d = length(SCREEN_UV - vec2(0.5)) * 1.4142;
	COLOR = vec4(tint, smoothstep(0.55, 1.0, d) * strength);
}
"""


# Safe to call once from host's _ready or later; nodes are added deferred.
static func apply(host: Node, env: Environment) -> void:
	if not is_instance_valid(host):
		return
	if is_instance_valid(env):
		_tune_environment(env)
	_add_vignette(host)
	_soften_mist(host)
	_moss_ground(host)
	_soften_moon(host)


# Deep moss: pull the colour toward grey and darken it, about #3a4430 for the base grass.
static func _moss(c: Color) -> Color:
	var lum: float = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var out: Color = Color(lum, lum, lum).lerp(c, 0.65) * 0.72
	out.a = c.a
	return out


# The base slab's albedo is reset on every rain change (village_game.gd), so the moss tint goes into the
# grass texture as a per-channel multiply. The rain darkening then still works on top. The expansion
# slabs share this texture, so claimed land picks up the same tint. Each part is tinted once (meta flag).
static func _moss_ground(host: Node) -> void:
	var raw: Variant = host.get("ground_parts")
	if not (raw is Array) or (raw as Array).is_empty():
		return
	var parts: Array = raw
	var first: Variant = parts[0]
	if is_instance_valid(first) and first is MeshInstance3D:
		var slab_mat: StandardMaterial3D = (first as MeshInstance3D).material_override as StandardMaterial3D
		if slab_mat != null and not slab_mat.has_meta(MOSS_META):
			slab_mat.set_meta(MOSS_META, true)
			var tex: ImageTexture = slab_mat.albedo_texture as ImageTexture
			if tex != null:
				var target: Color = _moss(SLAB_BASE)
				var factor := Color(target.r / SLAB_BASE.r, target.g / SLAB_BASE.g, target.b / SLAB_BASE.b)
				var image: Image = tex.get_image()
				for y in image.get_height():
					for x in image.get_width():
						var px: Color = image.get_pixel(x, y)
						image.set_pixel(x, y, Color(px.r * factor.r, px.g * factor.g, px.b * factor.b, px.a))
				tex.update(image)
	# Edges, soil, pebbles and grass patches: plain albedo, tinted once. Index 0 is the slab above.
	for index in range(1, parts.size()):
		var node: Variant = parts[index]
		if not is_instance_valid(node) or not (node is MeshInstance3D):
			continue
		var part: MeshInstance3D = node
		if part.has_meta(MOSS_META):
			continue
		part.set_meta(MOSS_META, true)
		var mat: StandardMaterial3D = part.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = _moss(mat.albedo_color)


# The moon quad was a hard-edged square (no texture), which read as a pale rectangle in the sky. Give it the
# soft disc: opaque in the middle, a radial alpha fall-off to nothing at the quad edge.
static func _soften_moon(host: Node) -> void:
	var raw: Variant = host.get("moon")
	if not is_instance_valid(raw) or not (raw is MeshInstance3D):
		return
	var node := raw as MeshInstance3D
	if node.has_meta(MOSS_META):
		return
	var quad := node.mesh as QuadMesh
	if quad == null or quad.material == null:
		return
	var mat := quad.material as StandardMaterial3D
	if mat == null:
		return
	node.set_meta(MOSS_META, true)
	mat.albedo_texture = _moon_texture()


static func _moon_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.86, 0.98, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


static func _tune_environment(env: Environment) -> void:
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.82
	env.glow_enabled = true
	env.glow_intensity = 0.26
	env.glow_strength = 0.68
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Only the two finest glow levels: tight bloom on lamps and windows, cheap on phones.
	for level in range(1, 8):
		env.set("glow_levels/%d" % level, 1.0 if level <= 2 else 0.0)


static func _add_vignette(host: Node) -> void:
	if host.get_node_or_null(VIGNETTE_NAME) != null:
		return
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.material = mat
	var layer := CanvasLayer.new()
	layer.name = VIGNETTE_NAME
	# Below the HUD layers, above the 3D world.
	layer.layer = -1
	layer.add_child(shade)
	host.add_child.call_deferred(layer)


static func _soften_mist(host: Node) -> void:
	var raw: Variant = host.get("mist")
	if not is_instance_valid(raw) or not (raw is CPUParticles3D):
		return
	var mist := raw as CPUParticles3D
	var mesh: Mesh = mist.mesh
	if mesh == null:
		return
	var primitive := mesh as PrimitiveMesh
	var array_mesh := mesh as ArrayMesh
	var has_surface := array_mesh != null and array_mesh.get_surface_count() > 0
	var current: Material = null
	if primitive != null:
		current = primitive.material
	elif has_surface:
		current = array_mesh.surface_get_material(0)
	var std := current as StandardMaterial3D
	if current == null:
		std = StandardMaterial3D.new()
		std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		std.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		std.vertex_color_use_as_albedo = true
		if primitive != null:
			primitive.material = std
		elif has_surface:
			array_mesh.surface_set_material(0, std)
		else:
			return
	elif std == null:
		# Non-StandardMaterial3D (e.g. ShaderMaterial): leave it alone.
		return
	if std.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.albedo_texture = _mist_texture()


static func _mist_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.75, 0.82, 1.0, 0.18),
		Color(0.75, 0.82, 1.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

