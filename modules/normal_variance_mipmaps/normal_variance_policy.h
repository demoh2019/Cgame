// Portable Toksvig-style normal variance policy.
// RGB stores unit mean direction; alpha carries the length of the unnormalized
// vector mean. Unlike renormalizing every mip, this preserves lost microdetail.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace NormalVariancePolicy {
struct Mean {
	float x;
	float y;
	float z;
};

inline Mean normal_from_rgb(uint8_t r, uint8_t g, uint8_t b) {
	float x = float(r) * (2.0f / 255.0f) - 1.0f;
	float y = float(g) * (2.0f / 255.0f) - 1.0f;
	float z = float(b) * (2.0f / 255.0f) - 1.0f;
	float magnitude = std::sqrt(x * x + y * y + z * z);
	if (magnitude < 1e-6f) {
		return { 0.0f, 0.0f, 1.0f };
	}
	return { x / magnitude, y / magnitude, z / magnitude };
}

inline Mean average4(Mean a, Mean b, Mean c, Mean d) {
	return { (a.x + b.x + c.x + d.x) * 0.25f,
		(a.y + b.y + c.y + d.y) * 0.25f,
		(a.z + b.z + c.z + d.z) * 0.25f };
}

inline float coherence(Mean mean) {
	const float length = std::sqrt(mean.x * mean.x + mean.y * mean.y + mean.z * mean.z);
	return std::isfinite(length) ? std::clamp(length, 0.0f, 1.0f) : 0.0f;
}

inline uint8_t encode(float value) {
	float bounded = std::isfinite(value) ? std::clamp(value, 0.0f, 1.0f) : 0.0f;
	return uint8_t(bounded * 255.0f + 0.5f);
}

// Adds only the *unresolved* normal variance; alpha=1 leaves roughness intact.
inline float filtered_roughness(float base, float coherence_value, float strength) {
	const float roughness = std::isfinite(base) ? std::clamp(base, 0.045f, 1.0f) : 1.0f;
	const float c = std::isfinite(coherence_value) ? std::clamp(coherence_value, 0.05f, 1.0f) : 1.0f;
	const float weight = std::isfinite(strength) ? std::clamp(strength, 0.0f, 1.0f) : 0.0f;
	const float variance = std::min((1.0f - c) / c, 0.14f);
	return std::sqrt(std::min(1.0f, roughness * roughness + variance * weight));
}
} // namespace NormalVariancePolicy
