shader_type spatial;
// Animated volumetric-looking flame on crossed quads (Unreal Niagara / Unity VFX Graph
// style "flipbook-less" fire): scrolling value noise erodes a teardrop mask, HDR
// emission (> 1) drives the existing bloom, so flames glow without extra lights.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity = 3.2;
uniform float seed = 0.0;

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	uv.y = 1.0 - uv.y; // 0 bottom, 1 top
	float t = TIME + seed * 13.0;
	float n = n2(vec2(uv.x * 4.0, uv.y * 3.0 - t * 2.6)) * 0.6
		+ n2(vec2(uv.x * 9.0 + 3.0, uv.y * 7.0 - t * 4.1)) * 0.4;
	float x = (uv.x - 0.5) * 2.0;
	x += (n - 0.5) * 0.5 * uv.y; // flames lick sideways higher up
	float width = mix(0.85, 0.05, pow(uv.y, 0.8));
	float shape = 1.0 - smoothstep(width * 0.6, width, abs(x));
	shape *= smoothstep(0.0, 0.08, uv.y);
	float fire = clamp(shape - uv.y * (0.55 + n * 0.6), 0.0, 1.0);
	fire = smoothstep(0.02, 0.5, fire);
	// Blackbody-ish gradient: white-yellow core -> orange -> deep red tips.
	vec3 col = mix(vec3(1.0, 0.18, 0.02), vec3(1.0, 0.55, 0.12), smoothstep(0.1, 0.5, fire));
	col = mix(col, vec3(1.0, 0.92, 0.7), smoothstep(0.6, 1.0, fire));
	ALBEDO = col * fire * intensity;
}
