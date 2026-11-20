shader_type spatial;
// Fast, deep bat wingbeats (no skeleton): wing tips (|x|) swing through a
// large arc with a slight forward cup. Per-instance phase from INSTANCE_ID.
render_mode cull_disabled, shadows_disabled, unshaded;

void vertex() {
	float phase = float(INSTANCE_ID) * 2.399;
	float beat = sin(TIME * 16.0 + phase);
	float span = abs(VERTEX.x);
	VERTEX.y += beat * span * 1.3;
	VERTEX.z += abs(beat) * span * 0.25;
}

void fragment() {
	// Near-black silhouettes read best against dusk skies and moonlit ground.
	ALBEDO = vec3(0.025, 0.02, 0.03);
}
