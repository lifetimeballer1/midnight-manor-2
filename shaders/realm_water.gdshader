shader_type spatial;
render_mode specular_schlick_ggx, depth_draw_opaque, cull_disabled;

// The realm's river: a ribbon along its line (see _realm_build_water). UV is metres across (x)
// and along (y) the stream; COLOR.r is the water's depth over the ground (0.5 at the shoreline,
// 1 at a metre or more) and COLOR.gb the downstream direction. Clear shallows fading onto the
// bank, dark water in the channel, soft foam where it laps the shore, and streaks and ripples
// carried downstream, fastest mid-channel. No textures, no depth reads: cheap enough for phones.

uniform vec3 deep_col : source_color = vec3(0.07, 0.19, 0.23);
uniform vec3 shallow_col : source_color = vec3(0.22, 0.40, 0.38);
uniform vec3 silt_col : source_color = vec3(0.40, 0.37, 0.27);
uniform vec3 foam_col : source_color = vec3(0.82, 0.86, 0.84);
uniform vec3 sheen_col : source_color = vec3(0.60, 0.68, 0.78);
uniform float flow = 1.0;
uniform float ripple = 0.2;

varying float depth;
varying vec2 downstream;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	depth = COLOR.r * 2.0 - 1.0;
	downstream = COLOR.gb * 2.0 - 1.0;
}

void fragment() {
	vec2 s = UV;
	float t = TIME * flow;
	float mid = 1.0 - smoothstep(0.0, 7.0, abs(s.x));
	float run = t * (0.5 + 0.9 * mid);   // the current, faster mid-channel

	// Streaks of current: noise stretched along the stream, drifting downstream.
	float n1 = vnoise(vec2(s.x * 0.8, s.y * 0.16 - run * 0.5));
	float n2 = vnoise(vec2(s.x * 2.1, s.y * 0.5 - run * 1.2) + 17.0);
	float streak = smoothstep(0.58, 0.92, n1 * 0.6 + n2 * 0.4);

	// Ripples: two wave trains running downstream and a cross chop, as a tilted normal. g is the
	// slope across (x) and along (y) the stream; downstream turns it into world x/z.
	float a1 = s.y * 1.1 - run * 2.6 + s.x * 0.35 + n1 * 3.0;
	float a2 = s.y * 2.3 - run * 3.4 - s.x * 0.8 + n2 * 2.0;
	float a3 = s.x * 1.9 + s.y * 0.7 + t * 1.7;
	vec2 g = vec2(0.35, 1.1) * cos(a1) + vec2(-0.8, 2.3) * cos(a2) * 0.45 + vec2(1.9, 0.7) * cos(a3) * 0.2;
	vec2 along = normalize(downstream + vec2(0.0001));
	vec2 across = vec2(-along.y, along.x);
	vec2 slope = (across * g.x + along * g.y) * ripple * (0.5 + streak);
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float d = clamp(depth, 0.0, 1.0);
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.1, 0.9, d));
	col = mix(silt_col, col, smoothstep(0.0, 0.35, d));
	col = mix(col, sheen_col, streak * 0.14 * (0.3 + mid));

	// Foam laps the banks: a soft broken band at the water's edge and drifting flecks just off it.
	float fn = vnoise(vec2(s.x * 1.3, s.y * 0.7 - run * 0.6) * 1.4);
	float lap = 0.5 + 0.5 * sin(t * 1.3 + s.y * 0.35 + fn * 4.0);   // the band breathes as it laps
	float edge = (1.0 - smoothstep(0.0, 0.12 + 0.1 * lap, d)) * smoothstep(0.25, 0.7, fn + 0.25);
	float flecks = (1.0 - smoothstep(0.0, 0.4, d)) * smoothstep(0.66, 0.88, vnoise(vec2(s.x * 2.6, s.y * 1.1 - run * 1.4)));
	float foam = clamp(edge * 0.8 + flecks * 0.55, 0.0, 1.0);
	col = mix(col, foam_col, foam);

	ALBEDO = col;
	ROUGHNESS = mix(0.16, 0.7, foam);
	SPECULAR = 0.32;
	// The water thins to nothing over the bank, so the shoreline follows the ground, not the mesh.
	ALPHA = clamp(smoothstep(-0.02, 0.22, depth) + foam * 0.5, 0.0, 0.96);
	// A pale sheen at glancing angles, like the sky caught on the surface.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = sheen_col * fresnel * 0.1 * (1.0 - foam);
}
