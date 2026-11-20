shader_type fog;
// One froxel-volume under the active player. Unlike a transparent fog plane,
// it receives the actual sun/moon/torch lighting and existing shadow maps.
// All noise is stable in world space: chunk streaming cannot change its pattern.
uniform float density = 0.0;
uniform float ground_height = 0.0;
uniform vec3 mist_tint : source_color = vec3(0.70, 0.78, 0.79);
uniform vec2 noise_offset = vec2(0.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float mist_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(cell), hash12(cell + vec2(1.0, 0.0)), f.x),
		mix(hash12(cell + vec2(0.0, 1.0)), hash12(cell + vec2(1.0, 1.0)), f.x),
		f.y);
}

void fog() {
	vec2 field = WORLD_POSITION.xz + noise_offset;
	float broad = mist_noise(field * 0.038);
	float detail = mist_noise(field * 0.125 + vec2(41.0, 17.0));
	float vapor = smoothstep(0.25, 0.88, broad * 0.72 + detail * 0.28);
	float height = WORLD_POSITION.y - ground_height;
	// A volumetric ribbon above the walkable surface, rather than a screen overlay.
	float rising = smoothstep(-0.8, 0.65, height);
	float dissipating = 1.0 - smoothstep(2.2, 7.6, height);
	// Fade before the finite box reaches its boundary: no square popping.
	vec2 border = abs(UVW.xz - vec2(0.5)) * 2.0;
	float outskirts = 1.0 - smoothstep(0.52, 1.0, max(border.x, border.y));
	DENSITY = density * mix(0.13, 1.0, vapor) *
		max(0.0, rising * dissipating * outskirts);
	ALBEDO = mist_tint;
}
