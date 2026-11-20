// Lightweight, testable heightfield geomorph policy (no renderer dependencies).
// Fits the same (+X,-Z) quad diagonal used by HeightmapTerrainGeometry::sample_height.
#pragma once

#include <algorithm>
#include <cmath>

namespace TerrainGeomorphPolicy {
inline float factor(float p_distance, float p_threshold) {
	if (!(std::isfinite(p_distance) && std::isfinite(p_threshold)) || p_threshold <= 0.0f) {
		return 0.0f;
	}
	// Hysteresis switches at 0.9x/1.1x: fine mesh must already exactly
	// match the coarse surface at both boundaries, including reverse travel.
	const float t = std::clamp((p_distance / p_threshold - 0.65f) / 0.25f, 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

inline float interior_mask(int p_local_x, int p_local_z, int p_quads) {
	// Preserve exact chunk edges (the existing skirts handle mixed neighbours).
	return p_local_x > 0 && p_local_z > 0 && p_local_x < p_quads && p_local_z < p_quads ? 1.0f : 0.0f;
}

template <typename Sampler>
inline float coarse_sample(int p_local_x, int p_local_z, int p_origin_x, int p_origin_z,
		int p_coarse_stride, Sampler p_sample) {
	if (p_coarse_stride <= 0 || p_local_x < 0 || p_local_z < 0) {
		return 0.0f;
	}
	const int left = p_origin_x + (p_local_x / p_coarse_stride) * p_coarse_stride;
	const int top = p_origin_z + (p_local_z / p_coarse_stride) * p_coarse_stride;
	const float fx = float(p_local_x % p_coarse_stride) / float(p_coarse_stride);
	const float fz = float(p_local_z % p_coarse_stride) / float(p_coarse_stride);
	const float h00 = p_sample(left, top);
	// Every vertex shared with the next coarser grid already has the exact
	// target height. Skip the three other lookups for these common vertices.
	if (p_local_x % p_coarse_stride == 0 && p_local_z % p_coarse_stride == 0) {
		return h00;
	}
	const float h10 = p_sample(left + p_coarse_stride, top);
	const float h01 = p_sample(left, top + p_coarse_stride);
	const float h11 = p_sample(left + p_coarse_stride, top + p_coarse_stride);
	if (fx + fz <= 1.0f) {
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz;
	}
	return h11 + (h01 - h11) * (1.0f - fx) + (h10 - h11) * (1.0f - fz);
}
} // namespace TerrainGeomorphPolicy
