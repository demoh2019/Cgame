#include "../../scene/3d/audio_occlusion_policy.h"

#include <cassert>
#include <cmath>
#include <limits>

using namespace AudioOcclusionPolicy;

int main() {
	// Zero obstruction must preserve existing artist-authored sound.
	const Response open = evaluate(0.0f, 5000.0f);
	assert(open.gain == 1.0f && open.cutoff_hz == 5000.0f);
	assert(open.highshelf_gain == 1.0f);
	// A thin wall attenuates loudness and only high-frequency information.
	const Response half = evaluate(0.5f, 5000.0f);
	const Response blocked = evaluate(1.0f, 5000.0f);
	assert(half.gain < 1.0f && half.gain > blocked.gain);
	assert(half.cutoff_hz < 5000.0f && half.cutoff_hz > blocked.cutoff_hz);
	assert(std::abs(blocked.gain - 0.398107f) < 0.0001f);
	assert(std::abs(blocked.cutoff_hz - 1400.0f) < 0.01f);
	assert(blocked.highshelf_gain > 0.0f && blocked.highshelf_gain < 0.2f);
	assert(half.highshelf_gain > blocked.highshelf_gain);
	assert(half.highshelf_gain < open.highshelf_gain);
	// Terrain-occluded audio is already muffled; never raise its cutoff.
	const Response terrain = evaluate(1.0f, 900.0f);
	assert(std::abs(terrain.cutoff_hz - 900.0f) < 0.01f);
	for (int i = -100; i <= 200; ++i) {
		const float amount = float(i) / 100.0f;
		const Response sample = evaluate(amount, 8500.0f);
		assert(std::isfinite(sample.gain) && sample.gain > 0.0f && sample.gain <= 1.0f);
		assert(std::isfinite(sample.cutoff_hz));
		assert(std::isfinite(sample.highshelf_gain) && sample.highshelf_gain > 0.0f && sample.highshelf_gain <= 1.0f);
		// Log/exp interpolation may round by a few thousandths of a Hz.
		assert(sample.cutoff_hz >= 1399.98f && sample.cutoff_hz <= 8500.02f);
	}
	const Response nan = evaluate(std::numeric_limits<float>::quiet_NaN(), 5000.0f);
	const Response bad_cutoff = evaluate(0.7f, std::numeric_limits<float>::infinity());
	assert(nan.gain == 1.0f && nan.cutoff_hz == 5000.0f);
	assert(std::isfinite(bad_cutoff.gain) && std::isfinite(bad_cutoff.cutoff_hz));
	assert(evaluate(-20.0f, 5000.0f).gain == 1.0f);
	assert(evaluate(20.0f, 5000.0f).gain == blocked.gain);
}
