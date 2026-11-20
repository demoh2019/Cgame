shader_type spatial;
// Fish swim cycle without bones: a travelling sine bends the body sideways,
// growing towards the tail (-Z). Phase per instance from INSTANCE_ID.
render_mode cull_disabled, shadows_disabled;

uniform vec3 back_color : source_color = vec3(0.16, 0.2, 0.18);
uniform vec3 belly_color : source_color = vec3(0.62, 0.66, 0.6);

void vertex() {
	float phase = float(INSTANCE_ID) * 1.618;
	float tail = clamp(-VERTEX.z / 0.3, 0.0, 1.0);
	VERTEX.x += sin(TIME * 9.0 + phase - VERTEX.z * 8.0) * 0.05 * (0.25 + tail);
}

void fragment() {
	// Darker back seen from above (countershading), silvery sides catch the sky.
	ALBEDO = mix(belly_color, back_color, clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0));
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
