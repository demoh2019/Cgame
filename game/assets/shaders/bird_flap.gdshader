shader_type spatial;
// Wing flap in the vertex shader (no skeleton): vertices are displaced by |x|
// so the two wing tips beat; each instance gets its own phase via INSTANCE_CUSTOM.
render_mode cull_disabled, shadows_disabled;

uniform vec3 body_color : source_color = vec3(0.08, 0.08, 0.09);

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float rate = mix(9.0, 13.0, INSTANCE_CUSTOM.y);
	// Glide now and then: flapping fades out for a while.
	float glide = smoothstep(0.2, 0.6, sin(TIME * 0.7 + phase) * 0.5 + 0.5);
	float flap = sin(TIME * rate + phase) * (1.0 - glide * 0.85);
	float span = abs(VERTEX.x);
	VERTEX.y += flap * span * 0.9;
	VERTEX.x *= 1.0 - abs(flap) * 0.15;
}

void fragment() {
	ALBEDO = body_color;
	ROUGHNESS = 0.9;
}
