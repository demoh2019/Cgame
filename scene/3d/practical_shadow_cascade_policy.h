// Portable practical split scheme for sun shadow cascades (PSSM).
// Logarithmic/uniform blending improves nearby contact detail without
// allocating extra cascades, shadow atlas texels or renderer resources.
#pragma once

#include <algorithm>
#include <cmath>

namespace PracticalShadowCascades {
struct Splits {
	bool valid = false;
	float one = 0.0f;
	float two = 0.0f;
	float three = 0.0f;
};

inline Splits compute(float near_plane, float far_plane, float lambda, int cascades) {
	if (!std::isfinite(near_plane) || !std::isfinite(far_plane) ||
			!std::isfinite(lambda) || near_plane < 0.01f || near_plane > 250.0f ||
			far_plane < 2.0f || far_plane > 8192.0f || near_plane * 2.0f >= far_plane ||
			lambda < 0.0f || lambda > 1.0f || (cascades != 2 && cascades != 4)) {
		return {};
	}
	Splits result;
	float fractions[3] = {};
	float previous = 0.0f;
	for (int step = 1; step < cascades; ++step) {
		const float p = float(step) / float(cascades);
		const float logarithmic = near_plane * std::pow(far_plane / near_plane, p);
		const float uniform = near_plane + (far_plane - near_plane) * p;
		const float depth = lambda * logarithmic + (1.0f - lambda) * uniform;
		// Pixel-scale camera jitter should not invalidate the shadow pass.
		float fraction = std::floor(depth / far_plane * 1000.0f + 0.5f) * 0.001f;
		fraction = std::clamp(fraction, previous + 0.001f, 0.999f);
		if (!std::isfinite(fraction) || fraction <= previous || fraction >= 1.0f) {
			return {};
		}
		fractions[step - 1] = fraction;
		previous = fraction;
	}
	result.valid = true;
	result.one = fractions[0];
	result.two = fractions[1];
	result.three = fractions[2];
	return result;
}
} // namespace PracticalShadowCascades
