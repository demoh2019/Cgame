// Lightweight geometric specular anti-aliasing for PBR materials.
// Similar in goal to HDRP geometric specular AA and normal-to-roughness
// workflows. No extra texture samples or render targets.
//
// The controller sets strength to zero on Performance/Balanced, so the
// derivative path is skipped by one uniform branch. All derivatives are
// outside pixel-dependent branches, keeping fragment quads coherent.
global uniform float aa_specular_aa_strength;

float filter_specular_roughness(float source_roughness, vec3 shading_normal) {
	float base = clamp(source_roughness, 0.04, 1.0);
	if (aa_specular_aa_strength <= 0.001) {
		return base;
	}
	vec3 n = normalize(shading_normal);
	vec3 dx = dFdx(n);
	vec3 dy = dFdy(n);
	float normal_variance = dot(dx, dx) + dot(dy, dy);
	// Variance widens highlights, never sharpens them. Cap to keep wet
	// pavement, rock and leaves from turning uniformly matte.
	float added_variance = min(normal_variance * aa_specular_aa_strength, 0.075);
	return sqrt(min(base * base + added_variance, 1.0));
}
