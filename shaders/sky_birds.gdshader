shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;

// A few flocks of high birds crossing the map. Each instance sits at its place in the flock; the
// shader carries the whole flock along a straight line, bobs it, and flaps the wing tips, so the
// CPU never touches the birds after they are built. Instance COLOR: r = flock phase, g = flap rate.

uniform vec2 heading = vec2(0.9, 0.43);
uniform float speed = 2.6;
uniform float lane = 150.0;                 // length of the flight path before a flock loops
uniform vec3 ink : source_color = vec3(0.07, 0.06, 0.05);
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	vec2 fwd = normalize(heading);
	vec2 side = vec2(-fwd.y, fwd.x);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = COLOR.r;
	float travel = mod(TIME * speed + phase * lane, lane) - lane * 0.5;
	float flap = sin(TIME * 7.5 * COLOR.g + phase * 40.0 + origin.x);
	vec3 v = VERTEX;
	float tip = smoothstep(0.08, 0.5, abs(v.x));
	v.y += tip * flap * 0.2;
	v.x *= 1.0 - tip * 0.28 * abs(flap);
	vec3 wpos = origin + vec3(fwd.x, 0.0, fwd.y) * travel + vec3(0.0, sin(TIME * 0.8 + phase * 9.0) * 0.35, 0.0);
	wpos += vec3(side.x, 0.0, side.y) * v.x + vec3(fwd.x, 0.0, fwd.y) * v.z + vec3(0.0, v.y, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
}

void fragment() {
	ALBEDO = ink;
	ALPHA = 0.9 * strength;
}
