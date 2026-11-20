// Build standalone: c++ -std=c++17 -Wall -Wextra -pedantic
//   modules/texture_streaming/tests/test_feedback_prefetch.cpp -o /tmp/test_prefetch
#include "../feedback_buffer_policy.h"
#include <cassert>
#include <limits>

using namespace TextureStreamingFeedbackPolicy;

int main() {
	static_assert(prefetch_mip(0, 2) == 0, "no unsigned underflow");
	static_assert(prefetch_mip(1, 2) == 0, "prefetch saturates at mip 0");
	static_assert(prefetch_mip(3, 1) == 2, "premium detail prefetches one mip");
	static_assert(prefetch_mip(8, 0) == 8, "low-end unchanged");
	static_assert(next_reload_mip(8, 2, 0) == 7, "Balanced retains old gradual reloads");
	static_assert(next_reload_mip(8, 2, 1) == 6, "High skips one blurry upload");
	static_assert(next_reload_mip(8, 2, 2) == 6, "Ultra keeps the jump bounded");
	static_assert(next_reload_mip(8, 7, 2) == 7, "no overshoot of target quality");
	static_assert(next_reload_mip(3, 6, 2) == 4, "budget pressure still reduces one mip");
	static_assert(next_reload_mip(3, 3, 2) == 3, "no reload at stable quality");
	static_assert(next_reload_mip(255, 5, 2) == 5, "fresh textures load selected target");
	static_assert(next_reload_mip(0, 0, 2) == 0, "no unsigned underflow");
	assert(next_reload_mip(13, 0, 1) == 11);
	assert(next_reload_mip(1, 0, 1) == 0);
	assert(mip_from_coverage(8.0f, 9) == 3);
	assert(prefetch_mip(mip_from_coverage(8.0f, 9), 1) == 2);
	assert(prefetch_mip(mip_from_coverage(0.5f, 9), 1) == 0);
	assert(prefetch_mip(mip_from_coverage(std::numeric_limits<float>::infinity(), 9), 1) == 7);
}
