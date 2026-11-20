// Lightweight obstruction response for scene AudioStreamPlayer3D.
// Does not change distance attenuation, panning or mixer routing.
// Independent of the engine and testable with any C++17 compiler.
#pragma once

#include <algorithm>
#include <cmath>

namespace AudioOcclusionPolicy {
struct Response {
	float gain;
	float cutoff_hz;
	float highshelf_gain;
};

inline Response evaluate(float p_amount, float p_base_cutoff_hz) {
	const float amount = std::isfinite(p_amount) ? std::clamp(p_amount, 0.0f, 1.0f) : 0.0f;
	const float cutoff = std::isfinite(p_base_cutoff_hz) ?
			std::clamp(p_base_cutoff_hz, 20.0f, 20500.0f) : 5000.0f;
	if (amount == 0.0f) {
		return { 1.0f, cutoff, 1.0f };
	}
	// A wall darkens the direct path without muting the entire SFX bus.
	// Log-frequency interpolation matches a perceptual low-pass glide.
	const float occluded_cutoff = std::min(cutoff, 1400.0f);
	const float filtered = std::exp(std::log(cutoff) * (1.0f - amount) +
			std::log(occluded_cutoff) * amount);
	const float attenuation = std::pow(10.0f, -8.0f * amount / 20.0f);
	// Godot's existing distance highshelf is unity for near sounds. Explicit
	// spectral loss is required or lowering cutoff alone has no effect there.
	const float highshelf = std::pow(10.0f, -15.0f * amount / 20.0f);
	return { attenuation, filtered, highshelf };
}
} // namespace AudioOcclusionPolicy
