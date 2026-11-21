shader_type spatial;
// Lootable body outline: a warm rim glow that breathes, drawn over the body's own materials.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 glow : source_color = vec4(1.0, 0.72, 0.22, 1.0);
uniform float strength = 0.9;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float breathe = 0.65 + 0.35 * sin(TIME * 3.0);
	ALBEDO = glow.rgb * (rim * 1.6 + 0.12) * strength * breathe;
}
