shader_type spatial;
// Screen-space heat haze above fires (Unreal "Refraction" / Unity HDRP distortion):
// refracts the already-rendered scene with rising noise, faded at the quad edges.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float strength = 0.006;

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	// Camera-facing billboard keeps the haze visible from every angle.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec2 off = vec2(n2(vec2(uv.x * 6.0, uv.y * 4.0 + t * 2.2)), n2(vec2(uv.x * 6.0 + 5.2, uv.y * 4.0 + t * 1.7))) - 0.5;
	float mask = smoothstep(0.0, 0.3, uv.x) * smoothstep(1.0, 0.7, uv.x) * smoothstep(0.0, 0.25, uv.y) * smoothstep(1.0, 0.6, uv.y);
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off * strength * mask * 2.0, 0.0).rgb;
	ALPHA = mask;
}
