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
	assert(mip_from_coverage(8.0f, 9) == 3);
	assert(prefetch_mip(mip_from_coverage(8.0f, 9), 1) == 2);
	assert(prefetch_mip(mip_from_coverage(0.5f, 9), 1) == 0);
	assert(prefetch_mip(mip_from_coverage(std::numeric_limits<float>::infinity(), 9), 1) == 7);
}
