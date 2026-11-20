// Shadows of clouds drifting over the island: soft dark patches that slide across the ground, the grass and the trees.
// Every surface that includes this computes the same field from world position and time, so the patches line up.
// The classic trick of top-down games for a living, sunlit world.

float cloud_hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(i), cloud_hash(i + vec2(1.0, 0.0)), f.x), mix(cloud_hash(i + vec2(0.0, 1.0)), cloud_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 0 in sunlight, 1 under a cloud.
float cloud_shadow(vec2 world_xz, float time) {
	vec2 p = world_xz * 0.011 + vec2(time * 0.02, time * 0.012);
	float n = cloud_noise(p) * 0.62 + cloud_noise(p * 2.4 + vec2(7.1, 3.3)) * 0.28 + cloud_noise(p * 5.1 - 2.0) * 0.1;
	return smoothstep(0.5, 0.68, n);
}

// The colour under the cloud: darker and a little cooler, as in the shade of a real cloud.
vec3 apply_cloud_shadow(vec3 color, vec2 world_xz, float time) {
	float shade = cloud_shadow(world_xz, time);
	return color * mix(vec3(1.0), vec3(0.58, 0.63, 0.74), shade);
}
