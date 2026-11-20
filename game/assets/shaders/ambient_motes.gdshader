shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

// Distant world ambience: vertex-animated, camera-facing quads in ONE MultiMesh.
// No particle simulation, dynamic lighting, shadow maps, texture fetches, or
// per-frame CPU work for individual pollen motes / fireflies.
uniform float firefly_strength : hint_range(0.0, 1.0) = 0.0;
uniform float pollen_strength : hint_range(0.0, 1.0) = 0.0;
uniform float fade_distance : hint_range(8.0, 80.0) = 42.0;
uniform vec2 ambient_wind = vec2(0.0);

varying float mote_alpha;
varying vec3 mote_tint;
varying float mote_light;

void vertex() {
	// Custom data: R = kind (1 firefly, 0 pollen), G = phase,
	// B = pulse speed, A = brightness. Packed by MultiMesh on GL.
	float is_firefly = step(0.5, INSTANCE_CUSTOM.r);
	float phase = INSTANCE_CUSTOM.g * 6.2831853;
	float speed = mix(0.5, 2.1, INSTANCE_CUSTOM.b);
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float drift = TIME * speed + phase;

	// Wind is bounded: every quad remains inside the batch's custom AABB.
	center.xz += vec2(sin(drift * 0.75), cos(drift * 0.6)) * 0.6;
	center.xz += ambient_wind * sin(drift * 0.22) * 0.05;
	center.y += sin(drift * 0.83) * 0.27;

	float distance_to_camera = length(center - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_distance * 0.68,
		fade_distance, distance_to_camera);
	float strength = mix(pollen_strength, firefly_strength, is_firefly);
	// Soft periodic light from fireflies, quieter drifting daytime pollen.
	float pulse = mix(0.68 + 0.18 * sin(drift),
		0.64 + 0.36 * sin(drift * 2.1), is_firefly);
	mote_alpha = strength * fade * pulse * INSTANCE_CUSTOM.a;
	mote_tint = mix(vec3(0.66, 0.76, 0.84),
		vec3(1.0, 0.89, 0.39), is_firefly);
	mote_light = is_firefly;

	// Quad's camera-facing orientation is calculated at four vertices,
	// not for each fragment. Godot performs projection after this step.
	vec3 world_vertex = center
		+ INV_VIEW_MATRIX[0].xyz * VERTEX.x
		+ INV_VIEW_MATRIX[1].xyz * VERTEX.y;
	VERTEX = (VIEW_MATRIX * vec4(world_vertex, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV * 2.0 - vec2(1.0);
	float r2 = dot(p, p);
	float halo = max(1.0 - r2, 0.0);
	halo *= halo;
	ALBEDO = mote_tint;
	EMISSION = mote_tint * (0.32 + mote_light * 1.4);
	ALPHA = clamp(mote_alpha * halo, 0.0, 1.0);
}
