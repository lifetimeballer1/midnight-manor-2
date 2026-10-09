shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// Cloud shadows (and golden sun patches between them) drifting across the whole map, claimed
// land and fogged plots included. One flat quad just above the ground; the world position drives
// a scrolling noise lookup, so it costs two texture taps per pixel and nothing on the CPU.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 wind = vec2(0.006, 0.0035);
uniform vec3 shade_col : source_color = vec3(0.05, 0.07, 0.14);
uniform vec3 sun_col : source_color = vec3(1.0, 0.78, 0.4);
uniform float strength : hint_range(0.0, 1.0) = 0.0;     // 0 at night
uniform float warm : hint_range(0.0, 1.0) = 1.0;         // sunny patches, fewer in rain
uniform float cover : hint_range(0.0, 1.0) = 0.5;
uniform float reach = 52.0;
uniform float detail = 1.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz * 0.021 + wind * TIME;
	float n = texture(noise_tex, p).r;
	if (detail > 0.5) {
		n = n * 0.7 + texture(noise_tex, p * 2.7 + vec2(0.3, 0.7)).r * 0.3;
	}
	float shade = smoothstep(0.62 - cover * 0.2, 0.78 - cover * 0.2, n);
	float clear = 1.0 - smoothstep(0.34, 0.5, n);
	float edge = 1.0 - smoothstep(reach * 0.6, reach, length(wp.xz));
	ALBEDO = mix(sun_col, shade_col, shade);
	ALPHA = (shade * 0.22 + clear * 0.08 * warm) * strength * edge;
}
