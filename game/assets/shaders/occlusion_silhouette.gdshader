shader_type spatial;
// Occluded-character silhouette (Diablo / Path of Exile X-ray): drawn only where
// the character is BEHIND other geometry (inverted depth test), as a soft
// fresnel-rimmed tint, so the hero never disappears behind a building.
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.35, 0.85, 1.0, 0.55);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb * (0.6 + rim);
	ALPHA = tint.a * (0.35 + 0.65 * rim);
}
