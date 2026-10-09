shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Swaying autumn grass clumps. One MultiMesh clump = four tapered blades; every bit of motion
// happens here in the vertex shader, so the CPU does nothing per frame beyond handing over
// up to 12 positions of walkers (twice a tenth of a second at most).
//
// Clumps vanish (scale to nothing) where the terrain mask says the ground is cleared, which
// is how buildings and trails keep their dirt without ever rebuilding the MultiMesh.
// UV.y is the blade height fraction 0..1; COLOR (the instance colour) is the tip tint.

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(40.0, 32.0);
uniform vec3 root_col : source_color = vec3(0.11, 0.14, 0.04);
uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform float wind_power : hint_range(0.0, 2.0) = 1.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 pushers[12];        // x, z, radius of each walker; radius 0 = unused

varying float tip;
varying vec3 tint;

void vertex() {
	vec2 c = MODEL_MATRIX[3].xz;
	float clear = textureLod(mask_tex, clamp(c / map_size + 0.5, vec2(0.0), vec2(1.0)), 0.0).g;
	float keep = 1.0 - smoothstep(0.18, 0.62, clear);
	vec2 beyond = abs(c) - map_size * 0.5;
	if (max(beyond.x, beyond.y) > 0.0) {
		keep = 1.0;                  // claimed expansion land: the mask only covers the base map
	}
	float h = UV.y;
	tip = h;
	tint = COLOR.rgb;

	vec3 v = VERTEX * keep;
	v.y *= 1.0 - 0.28 * wet;

	// Gusts roll across the map along wind_dir; a bigger one sweeps through every ~20 s.
	float ph = dot(c, wind_dir);
	float gust = 0.5 + 0.5 * sin(ph * 0.21 - TIME * 0.95);
	float flutter = 0.5 + 0.5 * sin(ph * 0.9 - TIME * 2.4 + c.x * 0.45);
	float big = smoothstep(0.62, 1.0, 0.5 + 0.5 * sin(TIME * 0.31 + ph * 0.045));
	float sway = (0.07 + 0.16 * gust + 0.07 * flutter + 0.30 * big) * wind_power + 0.10 * wet;
	vec2 d = wind_dir * sway * h * h;
	d += vec2(cos(TIME * 1.7 + c.y * 3.0), sin(TIME * 1.3 + c.x * 3.0)) * 0.025 * h * wind_power;

	// Walkers push the blades away and press them down.
	for (int i = 0; i < 12; i++) {
		vec3 p = pushers[i];
		if (p.z > 0.0) {
			vec2 away = c - p.xy;
			float f = 1.0 - smoothstep(0.0, p.z, length(away));
			d += normalize(away + vec2(0.0001)) * f * 0.42 * h;
			v.y *= 1.0 - 0.45 * f * h;
		}
	}

	// d is a world-space offset; bring it into the clump's local frame (rotated and scaled).
	vec3 m0 = MODEL_MATRIX[0].xyz;
	vec3 m2 = MODEL_MATRIX[2].xyz;
	v.x += dot(vec2(d.x, d.y), vec2(m0.x, m0.z)) / max(dot(m0, m0), 0.0001);
	v.z += dot(vec2(d.x, d.y), vec2(m2.x, m2.z)) / max(dot(m2, m2), 0.0001);
	VERTEX = v;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float t = smoothstep(0.0, 0.5, tip);
	vec3 col = mix(root_col, tint, t);
	col *= 1.0 - 0.38 * wet;
	col = mix(col, col * vec3(0.78, 0.9, 1.15), night * 0.5);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
