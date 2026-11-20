// Cheap foliage thin-sheet spectral transport approximation.
// A rational Beer-Lambert fit avoids costly exponential evaluations and samples
// NO new textures. Color pigment and geometric thickness approximate veins.
// The scene's existing BACKLIGHT supplies real per-light color/shadows.
vec3 aa_foliage_spectral_filter(vec3 pigment, float thickness, float strength) {
	float t = clamp(thickness, 0.35, 1.55);
	float dry = clamp((pigment.r - pigment.g) * 1.6, 0.0, 1.0);
	// Chlorophyll suppresses red/blue more than green; dry foliage is warmer.
	vec3 absorption = mix(vec3(1.22, 0.50, 1.72),
		vec3(0.72, 0.88, 1.28), dry);
	vec3 transmission = 1.0 / (vec3(1.0) + absorption * t);
	// Energy bounded: never turn translucency into a fake emissive glow.
	vec3 spectral = clamp(transmission * 1.55, vec3(0.20), vec3(1.05));
	return mix(vec3(1.0), spectral, clamp(strength, 0.0, 1.0));
}
