shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Autumn roads, a drop-in for the game's road shader (same uniforms plus a few extras).
// The road map holds trail strength in red and a paved-stone flag in green; both are painted as
// flat strips, so the cross-section is rebuilt here from a ring of taps around each pixel:
//   * trails: pale worn centre, darker packed shoulders (they read as wheel ruts), pebbles,
//     dry grass feathering over the edges, fallen leaves caught along the verge;
//   * stone: sun-bleached warm cobbles with moss in the joints and along the edges;
//   * rain: puddles pool in the dips, mirror the sky and ring with drops; everything darkens.
// Nothing here is read back by the CPU; it only needs the two textures the base already sets.

uniform sampler2D road_map : filter_linear, repeat_disable;
uniform sampler2D cobble_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 map_origin = vec2(0.0, 0.0);
uniform vec2 map_size = vec2(1.0, 1.0);
uniform vec3 dirt_colour : source_color = vec3(0.45, 0.39, 0.30);
uniform vec3 stone_tint : source_color = vec3(0.78, 0.79, 0.78);
uniform float cobble_scale = 0.5;
uniform float wet = 1.0;
uniform float rain_gloss = 0.0;
uniform float detail = 1.0;                      // 1 desktop, 0 phone (fewer taps)
uniform float leaf_amt : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sky_tint : source_color = vec3(0.62, 0.72, 0.8);
uniform vec3 moss_col : source_color = vec3(0.3, 0.36, 0.12);
uniform vec3 grass_col : source_color = vec3(0.56, 0.5, 0.2);

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// How far inside a painted strip this pixel sits: 1 in the middle, 0 at the rim.
float depth_of(vec2 uv, float centre, bool stone_map) {
	vec2 r = vec2(0.2) / map_size;
	float s = 0.0;
	float n = 0.0;
	vec2 offs[8] = vec2[8](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0), vec2(0.7, 0.7), vec2(-0.7, 0.7), vec2(0.7, -0.7), vec2(-0.7, -0.7));
	int count = detail > 0.5 ? 8 : 4;
	for (int i = 0; i < count; i++) {
		vec4 t = texture(road_map, uv + offs[i] * r);
		float v = stone_map ? t.g : t.r;
		s += smoothstep(0.04, 0.2, v);
		n += 1.0;
	}
	return s / n;
}

void fragment() {
	vec2 uv = (world_pos.xz - map_origin) / map_size;
	vec4 road = texture(road_map, uv);
	float grain = value_noise(world_pos.xz * 2.7) * 0.6 + value_noise(world_pos.xz * 7.3) * 0.4;
	float edge = (value_noise(world_pos.xz * 1.9) - 0.5) * 0.5 + (value_noise(world_pos.xz * 6.1) - 0.5) * 0.25;
	float trail = smoothstep(0.06, 0.32, road.r + edge * 0.32);
	float stone = smoothstep(0.38, 0.62, road.g + edge * 0.32);

	// Dirt: pale worn centre, darker packed shoulders, pebbles, a feathered dry-grass verge.
	float tdepth = depth_of(uv, road.r, false);
	vec3 dirt = dirt_colour * (0.82 + 0.36 * grain);
	dirt = mix(dirt, dirt * 1.22 + vec3(0.03, 0.025, 0.0), smoothstep(0.88, 1.0, tdepth) * 0.75);
	float shoulder = smoothstep(0.45, 0.72, tdepth) * (1.0 - smoothstep(0.78, 0.96, tdepth));
	dirt *= 1.0 - 0.3 * shoulder;
	vec2 pc = floor(world_pos.xz * 11.0);
	float peb = step(0.955, hash2(pc)) * smoothstep(0.42, 0.0, length(fract(world_pos.xz * 11.0) - 0.5));
	dirt = mix(dirt, dirt * 1.5 + 0.05, peb * 0.8);
	float verge = (1.0 - smoothstep(0.1, 0.62, tdepth)) * trail;
	float blades = step(0.55, value_noise(world_pos.xz * 24.0 + 3.0));
	dirt = mix(dirt, grass_col * (0.75 + 0.5 * grain), verge * (0.28 + 0.4 * blades));

	// Leaves lodge along the verge and a few lie in the road.
	vec2 lc = world_pos.xz * 3.4;
	vec2 lcell = floor(lc);
	vec2 lf = fract(lc) - 0.5 + (vec2(hash2(lcell + 4.1), hash2(lcell + 8.7)) - 0.5) * 0.4;
	float lh = hash2(lcell);
	float leaf_chance = (0.05 + 0.5 * verge) * leaf_amt;
	float leaf = step(1.0 - leaf_chance * 0.55, lh) * smoothstep(0.2, 0.08, length(lf * vec2(0.8, 1.25)));
	vec3 leaf_col = mix(vec3(0.82, 0.38, 0.06), vec3(0.78, 0.55, 0.08), hash2(lcell + 2.2));
	leaf_col = mix(leaf_col, vec3(0.6, 0.16, 0.06), step(0.82, hash2(lcell + 6.6)));
	dirt = mix(dirt, leaf_col * (0.85 + 0.3 * grain), leaf * trail * 0.9);

	// Stone: warm bleached cobbles, moss in the joints and along the rim.
	vec3 cobble_raw = texture(cobble_tex, world_pos.xz * cobble_scale).rgb;
	float lum = dot(cobble_raw, vec3(0.3, 0.59, 0.11));
	float joint = 1.0 - smoothstep(0.28, 0.5, lum);
	float sdepth = depth_of(uv, road.g, true);
	float moss_mask = clamp(joint * 0.8 + (1.0 - smoothstep(0.2, 0.8, sdepth)) * 0.55, 0.0, 1.0) * (0.45 + 0.55 * value_noise(world_pos.xz * 3.1));
	vec3 cobble = cobble_raw * stone_tint * (0.92 + 0.2 * grain);
	cobble = mix(cobble, moss_col * (0.8 + 0.5 * grain), clamp(moss_mask, 0.0, 1.0) * 0.6);
	cobble = mix(cobble, cobble * 1.0 + vec3(0.45, 0.2, 0.0) * leaf * 0.5, leaf * leaf_amt * 0.6);

	vec3 base = mix(dirt, cobble, stone) * wet;

	// Rain: puddles gather in noise dips, mirror the sky, and ring with drops.
	float rain = clamp(rain_gloss, 0.0, 1.0);
	float dip = value_noise(world_pos.xz * 1.15) * 0.65 + value_noise(world_pos.xz * 3.7) * 0.35;
	float puddle = smoothstep(0.5, 0.58, dip) * smoothstep(0.25, 0.7, rain) * max(trail * 0.9, stone * 0.7);
	puddle *= mix(1.0, 0.0, smoothstep(0.55, 0.0, mix(tdepth, sdepth, stone)));
	float rings = 0.0;
	if (puddle > 0.02 && rain > 0.3) {
		vec2 rc = world_pos.xz * 2.3;
		vec2 rcell = floor(rc);
		vec2 rp = fract(rc) - 0.5 + (vec2(hash2(rcell + 1.3), hash2(rcell + 5.9)) - 0.5) * 0.4;
		float t = fract(TIME * 0.8 + hash2(rcell + 9.1));
		float ring = abs(length(rp) - t * 0.42);
		rings = smoothstep(0.035, 0.0, ring) * (1.0 - t) * step(0.45, hash2(rcell + 3.3));
	}
	base = mix(base, base * 0.55 + sky_tint * 0.32, puddle * 0.85);
	base += vec3(0.5, 0.58, 0.65) * rings * puddle * 0.5;

	float alpha = max(trail * (0.5 + 0.5 * road.r), stone);
	alpha = clamp(alpha + puddle * 0.2 * step(0.01, alpha), 0.0, 1.0);
	float gloss = clamp(rain * max(trail, stone) * 0.55 + puddle, 0.0, 1.0);
	ALBEDO = base;
	ALPHA = alpha;
	ROUGHNESS = mix(0.95, 0.3, gloss) * (1.0 - 0.8 * puddle);
	SPECULAR = mix(0.3, 0.6, gloss) + 0.4 * puddle;
}
