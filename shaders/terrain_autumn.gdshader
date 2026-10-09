shader_type spatial;
render_mode specular_disabled, cull_back;

// Early-autumn painted ground for the base map (one quad, 40 x 32 world units).
// Phone budget: three fetches of one small cached noise texture, one fetch of a 40x32
// mask, and a single-cell hashed leaf speckle. No loops, no dependent reads.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;   // R = trampled dirt, G = grass kept clear
uniform vec2 map_size = vec2(40.0, 32.0);

uniform vec3 lush_a : source_color = vec3(0.24, 0.37, 0.10);
uniform vec3 lush_b : source_color = vec3(0.34, 0.46, 0.13);
uniform vec3 gold_a : source_color = vec3(0.56, 0.41, 0.08);
uniform vec3 gold_b : source_color = vec3(0.68, 0.47, 0.11);
uniform vec3 dirt_col : source_color = vec3(0.33, 0.21, 0.11);
uniform vec3 leaf_orange : source_color = vec3(0.85, 0.34, 0.05);
uniform vec3 leaf_red : source_color = vec3(0.66, 0.12, 0.06);
uniform vec3 leaf_ochre : source_color = vec3(0.88, 0.58, 0.10);

uniform float autumn : hint_range(0.0, 1.0) = 0.75;     // how far the turn has come
uniform float wet : hint_range(0.0, 1.0) = 0.0;         // rain darkening
uniform float night_cool : hint_range(0.0, 1.0) = 0.0;  // optional moonlit tint

varying vec2 wp;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wp = VERTEX.xz;
}

void fragment() {
	float n_low = texture(noise_tex, wp * 0.022 + vec2(0.13, 0.71)).r;
	float n_mid = texture(noise_tex, wp * 0.085 + vec2(0.57, 0.29)).r;
	float n_fine = texture(noise_tex, wp * 0.55).r;

	// Autumn creeps in from the map edge; big noise keeps the front ragged.
	vec2 q = abs(wp) / (map_size * 0.5);
	float edge = max(q.x, q.y);
	float turn = smoothstep(0.30, 1.05, edge + (n_low - 0.5) * 0.75) * autumn;

	vec3 green = mix(lush_a, lush_b, smoothstep(0.3, 0.7, n_mid));
	vec3 gold = mix(gold_a, gold_b, smoothstep(0.3, 0.7, n_fine));
	vec3 col = mix(green, gold, clamp(turn, 0.0, 1.0));

	// Grass micro-texture and broad light/dark swells.
	col *= 0.90 + 0.20 * n_fine;
	col *= 0.94 + 0.12 * n_low;

	// Trampled dirt around buildings, broken up by noise so edges look organic.
	vec2 muv = clamp(wp / map_size + 0.5, vec2(0.0), vec2(1.0));
	vec4 mask = texture(mask_tex, muv);
	float dirt = smoothstep(0.30, 0.62, mask.r + (n_mid - 0.5) * 0.55);
	col = mix(col, dirt_col * (0.85 + 0.3 * n_fine), dirt * 0.85);

	// Fallen leaves: one hashed leaf per cell, thickest toward the trees at the edge.
	float cell_scale = 2.4;
	vec2 cp = wp * cell_scale;
	vec2 cid = floor(cp);
	vec2 cf = fract(cp) - 0.5;
	float h = hash21(cid);
	float h2 = hash21(cid + 17.3);
	float density = (0.05 + 0.45 * turn) * smoothstep(0.25, 0.75, n_mid + 0.15);
	if (h < density && dirt < 0.5) {
		float ang = h2 * 6.2831;
		vec2 c = vec2(cos(ang), sin(ang));
		vec2 lp = vec2(dot(cf, c), dot(cf, vec2(-c.y, c.x))) * 1.0;
		lp += (vec2(h2, h) - 0.5) * -0.25;
		float leaf = 1.0 - smoothstep(0.55, 1.0, length(lp * vec2(2.6, 5.4)));
		vec3 lc = h2 < 0.38 ? leaf_orange : (h2 < 0.62 ? leaf_ochre : leaf_red);
		col = mix(col, lc * (0.85 + 0.3 * h), leaf);
	}

	col *= 1.0 - 0.38 * wet;
	col = mix(col, col * vec3(0.78, 0.9, 1.15), night_cool * 0.5);

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
