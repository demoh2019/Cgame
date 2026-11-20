shader_type spatial;
// Loot beam (Diablo IV / Borderlands): a tall additive light column that fades
// upwards and at its edges, with slow rising streaks and a gentle pulse.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.7, 0.2, 1.0);

void fragment() {
	float height = 1.0 - UV.y; // 0 bottom .. 1 top
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	edge = edge * edge;
	float fade = pow(1.0 - height, 1.6);
	float streaks = 0.75 + 0.25 * sin(height * 18.0 - TIME * 3.0 + UV.x * 6.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2);
	ALBEDO = beam_color.rgb * (edge * fade * streaks * pulse * 2.2 * beam_color.a);
}
