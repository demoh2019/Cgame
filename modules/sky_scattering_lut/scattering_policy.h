// Bounded, renderer-independent atmospheric single-scattering approximation.
// Wavelength-dependent extinction creates a warm low-sun horizon at no runtime
// GPU raymarch cost. All lookups are generated once per graphics session.
#pragma once

#include <algorithm>
#include <cmath>

namespace SkyScatteringPolicy {
struct Sample {
	float r;
	float g;
	float b;
	float transmittance;
};

inline float clamp_finite(float v, float lo, float hi, float fallback) {
	return std::isfinite(v) ? std::clamp(v, lo, hi) : fallback;
}

inline float optical_path(float elevation) {
	// Bounded curved-horizon approximation: never divides by horizon zero.
	float sin_height = std::max(elevation, 0.0f) + 0.095f;
	return std::min(12.0f, 1.0f / std::sqrt(0.012f + sin_height * sin_height));
}

inline Sample sample(float view_elevation, float sun_elevation, float aerosol) {
	float view = clamp_finite(view_elevation, -0.08f, 1.0f, 0.0f);
	float sun = clamp_finite(sun_elevation, -0.15f, 1.0f, 0.0f);
	float haze = clamp_finite(aerosol, 0.0f, 5.0f, 2.0f);
	float view_path = optical_path(view);
	float sun_path = optical_path(sun);
	float beta[3] = { 0.17f + 0.013f * haze, 0.36f + 0.017f * haze, 0.68f + 0.020f * haze };
	float scattered[3];
	for (int c = 0; c < 3; ++c) {
		float visible_scatter = -std::expm1(-beta[c] * view_path * 0.40f);
		float warm_illumination = std::exp(-beta[c] * sun_path * 0.26f);
		scattered[c] = visible_scatter * warm_illumination * 0.9f;
	}
	float transmittance = std::exp(-view_path * (0.08f + 0.018f * haze));
	return { scattered[0], scattered[1], scattered[2], transmittance };
}
} // namespace SkyScatteringPolicy
