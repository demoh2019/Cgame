// Height-aware layering for Albion After's 13-material PBR terrain.
// Inspired by height-based terrain blending, but uses existing mid/broad
// procedural noise and a fixed material height palette: ZERO new textures.
// The caller only invokes this on High/Ultra, near camera, outside roads.
//
// A nonzero weight stays nonzero; fully absent layers remain absent.
// Rock/snow protrude above mud/sand where biomes overlap, while old
// region/road/site masks and total natural weight are preserved.
global uniform float aa_terrain_height_blend;

float aa_terrain_relief_gain(int layer, float weight, float mid,
		float broad, float quality) {
	// Index 4 is road dirt (protected and never processed by the caller).
	float relief[9] = {0.64, 0.48, 0.68, 0.22, 0.50,
		0.88, 0.84, 0.36, 0.96};
	// Different materials have staggered micro-heights so their mutual
	// boundaries are not simply sharpened copies of the original masks.
	float local_detail = (layer % 2 == 0) ? mid : (1.0 - mid);
	float height = clamp(relief[layer]
		+ (local_detail - 0.5) * 0.24
		+ (broad - 0.5) * 0.12, 0.0, 1.0);
	// Slightly favour protruding rock/snow at blended edges and recessed
	// mud/sand under them. Purely dominant pixels remain exactly unchanged.
	float blend_edge = 1.0 - clamp(weight, 0.0, 1.0);
	return max(0.25, 1.0 + (height - 0.5) * 1.55
		* clamp(quality, 0.0, 1.0) * blend_edge);
}
