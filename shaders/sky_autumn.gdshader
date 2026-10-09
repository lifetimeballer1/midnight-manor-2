shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled, depth_draw_opaque;

// Autumn sky for an orthographic camera. A sky-dome shader cannot work here (its EYEDIR is
// meaningless under an orthographic view, and the Compatibility renderer feeds it no screen
// coordinates), so the sky is a big quad parked at the far end of the camera frustum and painted
// in screen space: a horizon line (uniform, moved with the camera tilt), a gradient above it, and
// a sea of drifting cloud below it that recedes toward the horizon. Top-down you see mostly the
// cloud sea around the floating village; tilted low you get the autumn sky.
//
// Everything animates from TIME and the uniforms below; the CPU only refreshes the uniforms when
// the day cycle, weather or camera move. Colours arrive already blended for the time of day.
// The world is drawn in front of this quad, so hidden pixels cost nothing.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float horizon = 0.2;                    // screen height of the horizon, 0 = top, 1 = bottom
uniform float detail = 1.0;                     // 1 desktop, 0 phone (fewer texture taps)

uniform vec3 zen_col : source_color = vec3(0.3, 0.5, 0.65);
uniform vec3 hor_col : source_color = vec3(0.95, 0.85, 0.65);
uniform vec3 low_col : source_color = vec3(0.85, 0.8, 0.7);
uniform vec3 glow_col : source_color = vec3(1.0, 0.5, 0.2);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.7, 0.68);
uniform vec2 glow_pos = vec2(0.8, 0.2);
uniform float glow_amt = 0.0;
uniform float cover : hint_range(0.0, 1.0) = 0.5;
uniform vec2 pan = vec2(0.0);
uniform vec2 wind = vec2(0.010, 0.004);

uniform float flash : hint_range(0.0, 1.0) = 0.0;     // lightning
uniform float alarm : hint_range(0.0, 1.0) = 0.0;     // a raid smoulders along the horizon
uniform float star_amt : hint_range(0.0, 1.0) = 0.0;
uniform float moon_amt : hint_range(0.0, 1.0) = 0.0;
uniform vec2 moon_pos = vec2(0.75, 0.1);
uniform float moon_phase : hint_range(0.0, 1.0) = 0.5;   // 0 new, 0.5 full
uniform vec3 moon_col : source_color = vec3(0.93, 0.95, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float e = horizon - uv.y;                       // above the horizon > 0

	// Gradient: zenith to horizon above, horizon haze to deep haze below.
	vec3 up_col = mix(hor_col, zen_col, pow(clamp(e * 1.7, 0.0, 1.0), 0.55));
	vec3 dn_col = mix(hor_col, low_col, smoothstep(0.0, 0.5, -e));
	vec3 col = mix(dn_col, up_col, smoothstep(-0.012, 0.012, e));

	// Low sun (or dawn) bleeding along the horizon.
	vec2 gd = vec2((uv.x - glow_pos.x) * aspect * 0.55, uv.y - glow_pos.y);
	col += glow_col * glow_amt * exp(-dot(gd, gd) * 4.5);

	// Clouds: one plane seen in perspective, above and below the horizon.
	float z = 1.0 / (0.16 + abs(e) * 1.25);
	vec2 p = vec2((uv.x - 0.5) * aspect * z, z) * 0.55 + pan * 0.012 + wind * TIME;
	float n = texture(noise_tex, p).r;
	float dens;
	float lit = 0.6;
	if (detail > 0.5) {
		float n2 = texture(noise_tex, p * 2.6 + vec2(0.37, 0.11) + wind * TIME * 0.5).r;
		float d = n * 0.7 + n2 * 0.3;
		dens = smoothstep(0.62 - cover * 0.5, 0.84 - cover * 0.5, d);
		float ns = texture(noise_tex, p + vec2(0.012, -0.018)).r;
		lit = clamp(0.62 + (n - ns) * 7.0, 0.0, 1.0);
	} else {
		dens = smoothstep(0.62 - cover * 0.5, 0.84 - cover * 0.5, n);
	}
	float far_haze = smoothstep(2.6, 6.2, z);        // distant cloud melts into the horizon
	float high = mix(1.0, 0.7, smoothstep(-0.012, 0.012, e));
	vec3 cc = mix(cloud_shade, cloud_lit, lit);
	col = mix(col, cc, dens * (1.0 - far_haze) * 0.92 * high);

	// Raid alarm: embers glow along the horizon and under the clouds, breathing slowly.
	if (alarm > 0.01) {
		float breathe = 0.78 + 0.22 * sin(TIME * 1.6);
		col += vec3(1.0, 0.24, 0.08) * alarm * breathe * (exp(-abs(e) * 5.0) * 0.38 + dens * 0.09);
	}
	// Lightning lights the cloud from inside.
	col += vec3(0.7, 0.8, 1.0) * flash * (0.22 + dens * 0.55);

	// Stars, thinned out by cloud. Cells of a jittered grid; a few twinkle faster.
	if (star_amt > 0.01) {
		vec2 g = vec2(uv.x * aspect, uv.y) * 46.0;
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = hash21(id);
		float h2 = hash21(id + 17.3);
		vec2 jit = (vec2(hash21(id + 3.1), hash21(id + 9.7)) - 0.5) * 0.6;
		float size = mix(0.05, 0.13, h2 * h2);
		float s = smoothstep(size, 0.0, length(f - jit)) * step(0.84, h);
		float tw = 0.65 + 0.35 * sin(TIME * (1.2 + h2 * 3.0) + h * 40.0);
		col += vec3(0.85, 0.9, 1.0) * s * tw * star_amt * (1.0 - dens * 0.92) * 1.15;
	}

	// Milky Way: a faint diagonal band of dust behind the stars, and now and then a shooting star.
	if (star_amt > 0.2 && detail > 0.5) {
		vec2 ap = vec2(uv.x * aspect, uv.y);
		float across = dot(ap - vec2(0.2, 0.45), normalize(vec2(0.55, 0.83)));
		float band = exp(-across * across * 26.0) * texture(noise_tex, ap * 1.7).r;
		col += vec3(0.42, 0.5, 0.78) * band * 0.34 * star_amt * (1.0 - dens * 0.9);
		float slot = TIME / 17.0;
		float ph = fract(slot) / 0.05;                       // the streak lives for the first 5% of each slot
		if (ph < 1.0) {
			float id = floor(slot);
			vec2 from = vec2(hash21(vec2(id, 1.7)) * aspect * 0.9, hash21(vec2(id, 8.3)) * 0.35);
			vec2 dir = normalize(vec2(0.8, 0.45));
			vec2 head = from + dir * ph * 0.42;
			float along = clamp(dot(ap - head, -dir), 0.0, 0.16);
			float dist = length(ap - head + dir * along);
			float streak = smoothstep(0.0035, 0.0, dist) * (1.0 - along / 0.16) * sin(ph * 3.14159265);
			col += vec3(0.95, 0.97, 1.0) * streak * star_amt * (1.0 - dens);
		}
	}

	// Moon: shaded sphere with a terminator for the phase, ash-lit on the dark side, plus halo.
	if (moon_amt > 0.01) {
		vec2 md = vec2((uv.x - moon_pos.x) * aspect, uv.y - moon_pos.y);
		float r = 0.05;
		float dm = length(md);
		vec2 q = md / r;
		float zz = sqrt(max(1.0 - dot(q, q), 0.0));
		float a = moon_phase * 6.2831853;
		vec3 L = vec3(sin(a), 0.0, -cos(a));
		float sunlit = smoothstep(-0.05, 0.05, dot(vec3(q.x, -q.y, zz), L));
		float maria = mix(0.74, 1.0, texture(noise_tex, q * 0.18 + 0.5).r);
		float body = smoothstep(r, r - 0.004, dm);
		vec3 mc = moon_col * (0.07 + 0.93 * sunlit) * maria;
		float lit_frac = 0.2 + 0.8 * sin(moon_phase * 3.14159265);
		float halo = (exp(-dm * dm * 70.0) * 0.42 + exp(-dm * 4.5) * 0.08) * lit_frac;
		col += moon_col * halo * moon_amt * (1.0 - dens * 0.6);
		col = mix(col, mc, body * moon_amt * (1.0 - dens * 0.85));
	}
	ALBEDO = col;
}
