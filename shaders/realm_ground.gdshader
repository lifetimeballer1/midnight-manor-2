shader_type spatial;
render_mode specular_disabled, cull_back;

// The realm's ground: the baked vertex colours (biome, slope, hillshade, owners) brought to life
// with painted detail from world position, so open country never reads as a flat wash: broad
// light and dark swells, grassy grain, leaf litter on the woodland floor (COLOR.a says how
// wooded), stones on the steeper slopes and a sprinkle of wildflowers in the meadows.
// Phone budget: four fetches of one small tiling noise texture and two hashed speckle cells.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float water_y = -1.3;
uniform vec3 leaf_orange : source_color = vec3(0.80, 0.36, 0.08);
uniform vec3 leaf_red : source_color = vec3(0.60, 0.14, 0.07);
uniform vec3 leaf_ochre : source_color = vec3(0.82, 0.58, 0.14);
uniform vec3 stone_col : source_color = vec3(0.50, 0.48, 0.44);

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

varying vec3 wp;
varying float up;
varying float wood;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	VERTEX.y = lowered(VERTEX);
	wp = VERTEX;
	up = NORMAL.y;
	wood = COLOR.a;
}

void fragment() {
	vec2 p = wp.xz;
	float n_low = texture(noise_tex, p * 0.0093 + vec2(0.31, 0.77)).r;
	float n_mid = texture(noise_tex, p * 0.047 + vec2(0.57, 0.29)).r;
	float n_fine = texture(noise_tex, p * 0.29).r;
	float n_grain = texture(noise_tex, p * 1.37 + vec2(0.11, 0.43)).r;
	vec3 col = COLOR.rgb;
	float dry = smoothstep(water_y + 0.15, water_y + 0.6, wp.y);

	// Broad swells of lighter and darker grass, a shift between fresh and sun-dried patches,
	// and a fine grain like blades seen from above.
	col *= 0.88 + 0.24 * n_mid;
	col = mix(col, col * vec3(1.12, 1.05, 0.78), smoothstep(0.45, 0.8, n_low) * 0.6 * dry);
	col = mix(col, col * vec3(0.86, 1.04, 0.92), smoothstep(0.5, 0.2, n_low) * 0.5 * dry);
	col *= 0.93 + 0.1 * n_fine;
	col *= 0.92 + 0.16 * n_grain;

	// Stones break through on the steeper slopes.
	float steep = 1.0 - smoothstep(0.86, 0.97, up);
	col = mix(col, stone_col * (0.75 + 0.4 * n_grain), steep * smoothstep(0.55, 0.75, n_fine) * 0.7 * dry);

	// Hashed speckles: one per cell, a leaf on the woodland floor or a flower in the meadow.
	vec2 cp = p * 1.6;
	vec2 cid = floor(cp);
	vec2 cf = fract(cp) - 0.5;
	float h = hash21(cid);
	float h2 = hash21(cid + 17.3);
	// The haunted ground around the manor stays bare: no speckles on the darkest earth.
	float lit = smoothstep(0.11, 0.19, dot(COLOR.rgb, vec3(0.3, 0.55, 0.15)));
	float leaves = lit * wood * smoothstep(0.2, 0.7, n_mid + 0.2) * 0.75 * dry;
	float flowers = lit * (1.0 - wood) * (1.0 - steep) * smoothstep(0.55, 0.8, n_low + n_fine * 0.3) * 0.16 * dry;
	if (h < leaves) {
		float ang = h2 * 6.2831;
		vec2 c = vec2(cos(ang), sin(ang));
		vec2 lp = vec2(dot(cf, c), dot(cf, vec2(-c.y, c.x))) + (vec2(h2, h) - 0.5) * 0.3;
		float leaf = 1.0 - smoothstep(0.5, 1.0, length(lp * vec2(3.0, 6.0)));
		vec3 lc = h2 < 0.38 ? leaf_orange : (h2 < 0.62 ? leaf_ochre : leaf_red);
		col = mix(col, lc * (0.7 + 0.3 * h), leaf * 0.85);
	} else if (h > 1.0 - flowers) {
		vec2 fp = cf + (vec2(h2, h) - 0.5) * 0.5;
		float bloom = 1.0 - smoothstep(0.06, 0.13, length(fp));
		vec3 fc = h2 < 0.4 ? vec3(0.9, 0.86, 0.72) : (h2 < 0.7 ? vec3(0.62, 0.5, 0.8) : vec3(0.95, 0.75, 0.25));
		col = mix(col, fc, bloom * 0.9);
	}

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
