// World-aligned, seamless cloud occlusion shared by terrain, grass and leaves.
// The low-resolution L8 noise texture is generated ONCE on the client rather
// than calculating 3 octaves of sine/hash noise in every fragment shader.
// GPU cost: at most one bilinearly filtered texture lookup per shaded pixel.
// Performance mode and nighttime skip the lookup altogether.
global uniform sampler2D aa_cloud_shadow_map : filter_linear, repeat_enable;
global uniform float aa_cloud_shadow_strength;

float cloud_shadow(vec2 world_xz, float time) {
	if (aa_cloud_shadow_strength <= 0.001) {
		return 0.0;
	}
	vec2 uv = world_xz / 1024.0 + vec2(time * 0.0005, time * 0.0003);
	return texture(aa_cloud_shadow_map, uv).r * aa_cloud_shadow_strength;
}

// Clouds cool the ground and foliage consistently, regardless of chunk or
// material. Their opacity fades under moonlight and heavy storm cover.
vec3 apply_cloud_shadow(vec3 color, vec2 world_xz, float time) {
	float shade = cloud_shadow(world_xz, time);
	return color * mix(vec3(1.0), vec3(0.58, 0.63, 0.74), shade);
}
