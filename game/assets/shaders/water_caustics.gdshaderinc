// Directional sunlight concentrated by moving shallow-water waves.
// Shared by textured PBR terrain and the procedural Compatibility fallback.
// This contains no texture reads, screen copy, material clones or draw passes.
//
// Water is a visual mesh at WATER_LEVEL - 0.35m. Submerged terrain receives
// light only within 4.5m below that surface, close to the camera, at daytime.
global uniform float aa_water_caustics_strength; // Graphics preset; 0 on low tiers.
global uniform float aa_water_caustics_sun; // Precomputed daylight/storm response at 5Hz.

// Cheap line network resembling refracted wave focusing. Coordinates are in
// world metres so chunk borders and different biome materials remain seamless.
float aa_water_caustic_lace(vec2 world_xz, float seconds) {
	vec2 q = world_xz * 1.68;
	vec2 warp = vec2(sin(q.y * 1.19 + seconds * 0.77),
		sin(q.x * 1.33 - seconds * 0.61)) * 0.29;
	float stripe_a = abs(sin((q.x + warp.x) * 1.78
		+ 0.45 * sin(q.y * 0.89 + seconds * 0.39)));
	float stripe_b = abs(sin((q.y + warp.y) * 2.03
		- 0.45 * sin(q.x * 1.07 - seconds * 0.48)));
	return pow(clamp(1.0 - min(stripe_a, stripe_b), 0.0, 1.0), 9.0);
}

float aa_water_caustic_illumination(vec2 world_xz, float world_height,
		float upward_normal, float camera_distance, float seconds) {
	// Uniform branch rejects all work on Performance/Balanced, dark skies
	// and every pixel away from visible, submerged near-field terrain.
	if (aa_water_caustics_strength <= 0.001 || aa_water_caustics_sun <= 0.001
			|| world_height >= -0.35 || world_height < -4.85
			|| camera_distance > 48.0 || upward_normal < 0.45) {
		return 0.0;
	}
	float depth = -0.35 - world_height;
	float depth_fade = smoothstep(0.16, 0.55, depth)
		* (1.0 - smoothstep(2.2, 4.5, depth));
	float range_fade = 1.0 - smoothstep(26.0, 48.0, camera_distance);
	float intensity = aa_water_caustic_lace(world_xz, seconds);
	// Ultra: an offset, slower second wave breaks up periodic bright lines.
	if (aa_water_caustics_strength > 0.75) {
		float detail = aa_water_caustic_lace(
			world_xz * 1.43 + vec2(13.7, -17.3), seconds * 0.73);
		intensity = mix(intensity, intensity * detail * 2.1, 0.34);
	}
	return clamp(intensity * depth_fade * range_fade
		* aa_water_caustics_sun * aa_water_caustics_strength, 0.0, 1.0);
}
