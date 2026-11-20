#include "../scattering_policy.h"

#include <cassert>
#include <cmath>
#include <limits>

using namespace SkyScatteringPolicy;

int main() {
	for (int yi = 0; yi < 72; ++yi) {
		float sun = -0.15f + 1.15f * yi / 71;
		for (int xi = 0; xi < 128; ++xi) {
			Sample s = sample(-0.08f + 1.08f * xi / 127, sun, 2.0f);
			for (float v : { s.r, s.g, s.b, s.transmittance }) {
				assert(std::isfinite(v) && v >= 0.0f && v <= 1.0f);
			}
		}
	}
	Sample zenith = sample(1, 1, 2), horizon = sample(0, 1, 2);
	assert(zenith.b > zenith.r);
	assert(horizon.transmittance < zenith.transmittance);
	Sample sunset = sample(0.04f, 0.01f, 2), midday = sample(0.04f, 1, 2);
	assert((sunset.r / sunset.b) > (midday.r / midday.b));
	assert(sample(std::numeric_limits<float>::quiet_NaN(), 1, 2).r >= 0);

	// Direct sunlight is normalized to the existing midday white point.
	const SunTransmittance high = sun_transmittance(1.0f, 2.0f);
	assert(std::abs(high.r - 1.0f) < 0.00001f);
	assert(std::abs(high.g - 1.0f) < 0.00001f);
	assert(std::abs(high.b - 1.0f) < 0.00001f);
	SunTransmittance previous = sun_transmittance(0.0f, 2.0f);
	assert(previous.r > previous.g && previous.g > previous.b);
	for (int i = 0; i <= 100; ++i) {
		const float elevation = float(i) / 100.0f;
		const SunTransmittance t = sun_transmittance(elevation, 2.0f);
		for (float c : {t.r, t.g, t.b}) {
			assert(std::isfinite(c) && c > 0.0f && c <= 1.0f);
		}
		assert(t.r >= previous.r - 1e-5f);
		assert(t.g >= previous.g - 1e-5f);
		assert(t.b >= previous.b - 1e-5f);
		previous = t;
	}
	const SunTransmittance clear = sun_transmittance(0.07f, 0.0f);
	const SunTransmittance hazy = sun_transmittance(0.07f, 5.0f);
	assert(hazy.b < clear.b && hazy.g < clear.g && hazy.r < clear.r);
	const SunTransmittance invalid = sun_transmittance(
			std::numeric_limits<float>::quiet_NaN(),
			std::numeric_limits<float>::infinity());
	for (float c : {invalid.r, invalid.g, invalid.b}) {
		assert(std::isfinite(c) && c > 0.0f && c <= 1.0f);
	}
}
