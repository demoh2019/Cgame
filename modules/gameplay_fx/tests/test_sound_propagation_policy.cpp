#include "../sound_propagation_policy.h"

#include <cassert>
#include <cmath>
#include <limits>

using namespace SoundPropagationPolicy;

int main() {
	// Calibrated to Albion After's existing server-owned 21m steps / 32m shots.
	assert(std::abs(hearing_radius(21.0f, 21.0f, true) - 13.02f) < 0.001f);
	assert(std::abs(hearing_radius(32.0f, 32.0f, true) - 25.6f) < 0.001f);
	assert(hearing_radius(21.0f, 21.0f, false) == 21.0f);
	assert(hearing_radius(32.0f, 32.0f, false) == 32.0f);
	assert(transmission(32.0f) > transmission(21.0f));
	assert(transmission(999.0f) == LOUD_TRANSMISSION);
	assert(transmission(1.0f) == QUIET_TRANSMISSION);
	assert(hearing_radius(0.0f, 21.0f, false) == 0.0f);
	assert(hearing_radius(0.0f, 21.0f, true) == 0.0f);
	assert(hearing_radius(-1.0f, 21.0f, true) == 0.0f);
	for (int n = 1; n <= 150; ++n) {
		for (int wind = 1; wind <= 60; ++wind) {
			const float original = float(wind);
			const float adjusted = hearing_radius(float(n), original, true);
			assert(std::isfinite(adjusted) && adjusted > 0.0f);
			assert(adjusted >= original * QUIET_TRANSMISSION - 0.001f);
			assert(adjusted <= original * LOUD_TRANSMISSION + 0.001f);
			assert(adjusted < hearing_radius(float(n), original, false));
		}
	}
	const float invalid[] = {
		std::numeric_limits<float>::quiet_NaN(),
		std::numeric_limits<float>::infinity(),
		-std::numeric_limits<float>::infinity()
	};
	for (float bad : invalid) {
		assert(hearing_radius(bad, 21.0f, true) == 0.0f);
		assert(hearing_radius(21.0f, bad, true) == 0.0f);
		assert(transmission(bad) == 0.0f);
	}
	// The flash is immediate, but thunder travels at the temperature-
	// adjusted speed of sound. Frame timing is not part of this calculation.
	const float t343 = sound_delay_seconds(343.42f, 20.0f);
	assert(std::abs(t343 - 1.0f) < 0.0001f);
	assert(sound_delay_seconds(0.0f) == 0.0f);
	assert(sound_delay_seconds(700.0f, -20.0f) >
			sound_delay_seconds(700.0f, 35.0f));
	assert(sound_delay_seconds(2400.0f, 20.0f) > 6.9f);
	assert(sound_delay_seconds(2400.0f, 20.0f) < 7.1f);
	assert(sound_delay_seconds(-1.0f) == -1.0f);
	assert(sound_delay_seconds(2400.1f) == -1.0f);
	assert(sound_delay_seconds(100.0f, 80.0f) == -1.0f);
	for (float bad : invalid) {
		assert(sound_delay_seconds(bad) == -1.0f);
		assert(sound_delay_seconds(100.0f, bad) == -1.0f);
	}
	for (int d = 0; d <= 2400; ++d) {
		const float delay = sound_delay_seconds(float(d), 20.0f);
		assert(std::isfinite(delay) && delay >= 0.0f);
		assert(delay <= 7.0f);
	}

	// Leash-clipped sound remains clipped even if original noise was loud.
	assert(hearing_radius(32.0f, 29.0f, true) <= 29.0f);
}
