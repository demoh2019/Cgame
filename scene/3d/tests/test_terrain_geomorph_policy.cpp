#include "../terrain_geomorph_policy.h"
#include <cassert>
#include <cmath>
#include <limits>

using namespace TerrainGeomorphPolicy;
int main() {
	assert(factor(45.0f, 100.0f) == 0.0f);
	assert(factor(90.0f, 100.0f) == 1.0f);
	assert(factor(110.0f, 100.0f) == 1.0f);
	assert(factor(std::numeric_limits<float>::quiet_NaN(), 100.0f) == 0.0f);
	float prev = -1.0f;
	for (int i = 0; i <= 100; ++i) {
		const float v = factor(float(i), 100.0f);
		assert(v >= 0.0f && v <= 1.0f && v >= prev);
		prev = v;
	}
	assert(interior_mask(0, 7, 16) == 0.0f);
	assert(interior_mask(7, 16, 16) == 0.0f);
	assert(interior_mask(7, 7, 16) == 1.0f);
	// Fine-grid sample at the centre of a coarse quad interpolates the same
	// diagonal as the new coarse mesh: no topology pop when switching.
	const float heights[3][3] = {{0, 2, 4}, {6, 8, 10}, {12, 14, 16}};
	// The production HeightField clamps at its edges; match that contract.
	auto sample = [&](int x, int z) -> float { return heights[std::min(z, 2)][std::min(x, 2)]; };
	assert(std::abs(coarse_sample(1, 0, 0, 0, 2, sample) - 2.0f) < 0.0001f); // h10=4 -> 2
	assert(std::abs(coarse_sample(1, 1, 0, 0, 2, sample) - 8.0f) < 0.0001f);
	assert(std::abs(coarse_sample(2, 2, 0, 0, 2, sample) - 16.0f) < 0.0001f);
	assert(std::abs(coarse_sample(0, 2, 0, 0, 2, sample) - 12.0f) < 0.0001f);
	// Non-planar heightfield: the diagonal must match the actual mesh triangles.
	const float twisted[3][3] = {{0, 2, 3}, {1, 10, 2}, {4, 5, 12}};
	auto irregular = [&](int x, int z) -> float {
		return twisted[std::min(z, 2)][std::min(x, 2)];
	};
	assert(std::abs(coarse_sample(1, 1, 0, 0, 2, irregular) - 3.5f) < 0.0001f);
	assert(std::abs(coarse_sample(1, 2, 0, 0, 2, irregular) - 8.0f) < 0.0001f);
	assert(std::abs(coarse_sample(2, 1, 0, 0, 2, irregular) - 7.5f) < 0.0001f);
}
