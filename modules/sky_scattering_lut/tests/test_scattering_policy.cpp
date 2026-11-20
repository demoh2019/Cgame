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
}
