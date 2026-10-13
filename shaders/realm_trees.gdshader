shader_type spatial;
render_mode cull_back;

// Realm trees, reeds, bushes and boulders (MultiMesh). COLOR is the mesh's baked shading times
// the instance's autumn tone. Everything above knee height sways in the wind, more the higher it
// is, in gusts that roll across the realm; boulders and trunks stay put.

uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform float wind_power : hint_range(0.0, 2.0) = 1.0;

// Scenery mountains between the camera and the view's focus would hide the realm: lower them to
// foothills. focus = (x, z) the camera looks at, (x, z) its horizontal facing. Only past the
// realm's edge (edge_from), so the playable ground is never touched.
uniform vec4 focus = vec4(0.0, 0.0, 0.0, -1.0);
uniform float base_y = -0.58;
uniform float edge_from = 256.0;

float lowered(vec3 world) {
	float behind = -dot(world.xz - focus.xy, focus.zw);
	float edge = max(abs(world.x), abs(world.z));
	float f = smoothstep(10.0, 70.0, behind) * smoothstep(edge_from - 4.0, edge_from + 30.0, edge);
	float h = world.y - base_y;
	return mix(world.y, base_y + min(h, 2.5 + h * 0.08), f);
}


void vertex() {
	vec2 c = MODEL_MATRIX[3].xz;
	float h = max(VERTEX.y - 0.55, 0.0);
	float ph = dot(c, wind_dir);
	float gust = 0.5 + 0.5 * sin(ph * 0.05 - TIME * 0.7);
	float sway = (sin(TIME * 1.4 + ph * 0.3 + c.x * 0.7) * 0.6 + sin(TIME * 2.7 + c.y) * 0.25) * (0.35 + gust * 0.65);
	vec2 d = wind_dir * (0.025 + 0.035 * gust + sway * 0.03) * h * h * wind_power;
	// d is a world-space offset; bring it into the instance's local frame (rotated and scaled).
	vec3 m0 = MODEL_MATRIX[0].xyz;
	vec3 m2 = MODEL_MATRIX[2].xyz;
	VERTEX.x += dot(d, m0.xz) / max(dot(m0, m0), 0.0001);
	VERTEX.z += dot(d, m2.xz) / max(dot(m2, m2), 0.0001);
	// Trees on lowered mountainsides go down with the ground.
	vec3 root = MODEL_MATRIX[3].xyz;
	VERTEX.y += (lowered(root) - root.y) / max(length(MODEL_MATRIX[1].xyz), 0.0001);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
}
