#include "../normal_variance_policy.h"

#include <cassert>
#include <cmath>
#include <limits>

using namespace NormalVariancePolicy;

int main() {
	const Mean flat = normal_from_rgb(128, 128, 255);
	assert(coherence(flat) > 0.999f);
	const Mean opposite_a = normal_from_rgb(255, 128, 128);
	const Mean opposite_b = normal_from_rgb(0, 128, 128);
	const Mean cancel = average4(opposite_a, opposite_b, opposite_a, opposite_b);
	assert(coherence(cancel) < 0.02f);
	const Mean aligned = average4(flat, flat, flat, flat);
	assert(coherence(aligned) > 0.999f);
	assert(std::abs(filtered_roughness(0.20f, 1.0f, 1.0f) - 0.20f) < 0.000001f);
	assert(filtered_roughness(0.20f, coherence(cancel), 1.0f) > 0.20f);
	assert(filtered_roughness(0.20f, coherence(cancel), 0.0f) == 0.20f);
	assert(filtered_roughness(0.98f, 0.0f, 1.0f) <= 1.0f);
	assert(filtered_roughness(std::numeric_limits<float>::quiet_NaN(), 0.4f, 1.0f) == 1.0f);
	assert(encode(1.0f) == 255 && encode(0.0f) == 0);
	for (int i = 0; i < 256; ++i) {
		const Mean n = normal_from_rgb(uint8_t(i), 255, uint8_t(255 - i));
		const Mean mixed = average4(n, flat, opposite_a, opposite_b);
		const float c = coherence(mixed);
		const float r = filtered_roughness(0.08f, c, 0.75f);
		assert(std::isfinite(c) && c >= 0.0f && c <= 1.0f);
		assert(std::isfinite(r) && r >= 0.08f && r <= 1.0f);
	}
}
