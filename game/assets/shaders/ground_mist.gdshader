shader_type fog;
// One froxel-volume under the active player. Unlike a transparent fog plane,
// it receives the actual sun/moon/torch lighting and existing shadow maps.
// All noise is stable in world space: chunk streaming cannot change its pattern.
uniform float density = 0.0;
uniform float ground_height = 0.0;
uniform vec3 mist_tint : source_color = vec3(0.70, 0.78, 0.79);
uniform vec2 noise_offset = vec2(0.0);
// Ultra-only: break up flat cloud layers using real 3D turbulence.
// The zero-strength High preset skips the 3D octave entirely.
uniform float vapor_3d_detail = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float mist_hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Eight hash corners interpolated smoothly in three axes. World-aligned
// modulation avoids view-dependent "billboard fog" under a moving camera.
float mist_noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float v000 = mist_hash3(cell);
	float v100 = mist_hash3(cell + vec3(1.0, 0.0, 0.0));
	float v010 = mist_hash3(cell + vec3(0.0, 1.0, 0.0));
	float v110 = mist_hash3(cell + vec3(1.0, 1.0, 0.0));
	float v001 = mist_hash3(cell + vec3(0.0, 0.0, 1.0));
	float v101 = mist_hash3(cell + vec3(1.0, 0.0, 1.0));
	float v011 = mist_hash3(cell + vec3(0.0, 1.0, 1.0));
	float v111 = mist_hash3(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(v000, v100, f.x), mix(v010, v110, f.x), f.y),
		mix(mix(v001, v101, f.x), mix(v011, v111, f.x), f.y),
		f.z);
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
	if (vapor_3d_detail > 0.001) {
		// High settings retain the original two cached-in-shader XY fields.
		// On Ultra, a third *volumetric* octave carves curling vapor sheets.
		// The existing weather-driven noise_offset advects all three layers.
		vec3 mist_position = vec3(
			field.x * 0.086 + (broad - 0.5) * 0.36,
			height * 0.24 + detail * 0.30,
			field.y * 0.086 - (broad - 0.5) * 0.36);
		float air_swirl = mist_noise3(mist_position + vec3(19.3, 4.7, 7.1));
		float airy_wisps = smoothstep(0.16, 0.77, air_swirl);
		vapor *= mix(1.0, 0.22 + 1.28 * airy_wisps,
			clamp(vapor_3d_detail, 0.0, 0.75));
	}
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
