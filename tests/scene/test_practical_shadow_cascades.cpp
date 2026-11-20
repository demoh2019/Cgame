#include "../../scene/3d/practical_shadow_cascade_policy.h"

#include <cassert>
#include <cmath>
#include <limits>

using namespace PracticalShadowCascades;

int main() {
	for (int n = 1; n <= 10; ++n) {
		for (int d = 20; d <= 500; d += 20) {
			for (int lam = 0; lam <= 10; ++lam) {
				const float near_plane = float(n) / 10.0f;
				const float far_plane = float(d);
				const float lambda = float(lam) / 10.0f;
				const Splits two = compute(near_plane, far_plane, lambda, 2);
				const Splits four = compute(near_plane, far_plane, lambda, 4);
				assert(two.valid && four.valid);
				assert(two.one > 0.0f && two.one < 1.0f);
				assert(four.one > 0.0f && four.one < four.two &&
						four.two < four.three && four.three < 1.0f);
				if (lam == 0) {
					assert(std::abs(two.one -
							(0.5f + near_plane / (2.0f * far_plane))) < 0.001f);
				}
			}
		}
	}
	const Splits high = compute(0.35f, 110.0f, 0.68f, 2);
	const Splits ultra = compute(0.35f, 140.0f, 0.62f, 4);
	assert(high.valid && high.one > 0.10f && high.one < 0.23f);
	assert(ultra.valid && ultra.one < 0.12f && ultra.three < 0.54f);
	assert(compute(0.35f, 140.0f, 0.62f, 4).one == ultra.one);
	for (float invalid : {
			std::numeric_limits<float>::quiet_NaN(),
			std::numeric_limits<float>::infinity(), -1.0f }) {
		assert(!compute(invalid, 140.0f, 0.62f, 4).valid);
		assert(!compute(0.35f, invalid, 0.62f, 4).valid);
		assert(!compute(0.35f, 140.0f, invalid, 4).valid);
	}
	assert(!compute(0.0f, 100.0f, 0.6f, 4).valid);
	assert(!compute(100.0f, 101.0f, 0.6f, 4).valid);
	assert(!compute(0.1f, 100.0f, 1.2f, 4).valid);
	assert(!compute(0.1f, 100.0f, 0.6f, 3).valid);
}
