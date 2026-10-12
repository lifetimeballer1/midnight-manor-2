shader_type spatial;
render_mode specular_schlick_ggx;

// The realm's river and the sea at its edge: one flat quad. A few crossing sine swells, from the
// world position and time, tilt the normal so the moon and sun glint off moving water and the
// colour shifts between deep and shallow. No textures, no depth reads: cheap enough for phones.

uniform vec3 deep_col : source_color = vec3(0.09, 0.19, 0.24);
uniform vec3 light_col : source_color = vec3(0.22, 0.36, 0.38);
uniform float speed = 1.0;
uniform float swell = 0.16;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float t = TIME * speed;
	// Three swells: (direction * frequency, phase speed).
	vec2 k1 = vec2(0.55, 0.22);
	vec2 k2 = vec2(-0.18, 0.71);
	vec2 k3 = vec2(1.3, 1.1);
	float a1 = dot(p, k1) + t * 1.3;
	float a2 = dot(p, k2) - t * 1.1;
	float a3 = dot(p, k3) + t * 2.2;
	float h = sin(a1) + sin(a2) * 0.8 + sin(a3) * 0.35;
	vec2 grad = cos(a1) * k1 + cos(a2) * k2 * 0.8 + cos(a3) * k3 * 0.35;
	vec3 n = normalize(vec3(-grad.x * swell, 1.0, -grad.y * swell));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(deep_col, light_col, smoothstep(-1.2, 1.8, h) * 0.6);
	ROUGHNESS = 0.14;
	METALLIC = 0.2;
	SPECULAR = 0.6;
}
