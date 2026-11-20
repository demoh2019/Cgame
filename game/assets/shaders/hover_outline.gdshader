shader_type spatial;
// Inverted-hull hover outline (UE custom-depth outline / Diablo & PoE target
// highlight) as a material_overlay: back faces pushed out along the normal in
// view space so the rim width stays constant on screen at any zoom.
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float width = 0.025;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Scale with distance so the outline is a fixed fraction of the screen.
	view_pos.xyz += view_n * width * max(-view_pos.z, 1.0) * 0.08;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	ALBEDO = outline_color.rgb * 1.6;
	ALPHA = outline_color.a;
}
