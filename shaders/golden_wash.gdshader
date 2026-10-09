shader_type canvas_item;
render_mode blend_add;

// Golden-hour wash over the 3D view (below the HUD): a warm bloom on the side the low sun is on,
// with a few slow rays fanning out of it. Purely additive, no textures, no CPU work per frame;
// the layer hides itself outside dawn and dusk.

uniform vec3 tint : source_color = vec3(1.0, 0.56, 0.22);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float sun_x = 0.8;
uniform float aspect = 0.46;
uniform float flash : hint_range(0.0, 1.0) = 0.0;     // lightning: the whole view flickers pale blue

void fragment() {
	vec2 d = vec2((UV.x - sun_x) * aspect * 2.0, UV.y + 0.12);
	float dist = length(d);
	float bloom = exp(-dist * dist * 2.2);
	float ang = atan(d.x, d.y);
	float rays = 0.5 + 0.5 * sin(ang * 13.0 + TIME * 0.22) * sin(ang * 5.0 - TIME * 0.13 + 1.3);
	float reach = smoothstep(1.35, 0.1, dist);
	float strength = bloom * 0.12 + rays * reach * 0.06;
	COLOR = vec4(tint * strength * amount + vec3(0.55, 0.65, 1.0) * flash * 0.2, 1.0);
}
