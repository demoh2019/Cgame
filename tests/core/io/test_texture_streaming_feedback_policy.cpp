/**************************************************************************/
/*  test_texture_streaming_feedback_policy.cpp                            */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "modules/texture_streaming/feedback_buffer_policy.h"
#include "tests/test_macros.h"

#include <cmath>
#include <cstring>
#include <limits>

TEST_FORCE_LINK(test_texture_streaming_feedback_policy)

namespace TestTextureStreamingFeedbackPolicy {
TEST_CASE("[TextureStreaming] feedback allocation and growth") {
	using namespace TextureStreamingFeedbackPolicy;
	CHECK(needs_resize(0, false, 0));
	CHECK(needs_resize(4096, false, 0));
	CHECK(needs_resize(4095, true, 0));
	CHECK_FALSE(needs_resize(4096, true, 0));
	CHECK_FALSE(needs_resize(4096, true, 1024));
	CHECK(needs_resize(4096, true, 1025));
	CHECK_FALSE(needs_resize(8192, true, 2048));
	CHECK(needs_resize(8192, true, 2049));
	CHECK(needs_resize(UINT32_MAX, true, (1u << 30)));
}
TEST_CASE("[TextureStreaming] mip level count all 16-bit dimensions") {
	using namespace TextureStreamingFeedbackPolicy;
	CHECK(mip_level_count(0, 0) == 1);
	CHECK(mip_level_count(1, 1) == 1);
	CHECK(mip_level_count(2, 1) == 2);
	CHECK(mip_level_count(3, 1) == 2);
	CHECK(mip_level_count(4, 1) == 3);
	CHECK(mip_level_count(1023, 5) == 10);
	CHECK(mip_level_count(5, 1024) == 11);
	CHECK(mip_level_count(65535, 65535) == 16);
	for (uint32_t dim = 0; dim <= UINT16_MAX; ++dim) {
		uint32_t rest = dim;
		uint8_t expected = 1;
		while (rest > 1) {
			rest >>= 1;
			++expected;
		}
		CHECK(mip_level_count(uint16_t(dim), 1) == expected);
		CHECK(mip_level_count(1, uint16_t(dim)) == expected);
	}
}

TEST_CASE("[TextureStreaming] fast mip selector matches IEEE 754 logarithm boundaries") {
	using namespace TextureStreamingFeedbackPolicy;
	CHECK(mip_from_coverage(0.0f, 14) == 0);
	CHECK(mip_from_coverage(-1.0f, 14) == 0);
	CHECK(mip_from_coverage(1.0f, 14) == 0);
	CHECK(mip_from_coverage(1.9999f, 14) == 0);
	CHECK(mip_from_coverage(2.0f, 14) == 1);
	CHECK(mip_from_coverage(4.0f, 14) == 2);
	CHECK(mip_from_coverage(8192.0f, 14) == 13);
	CHECK(mip_from_coverage(16384.0f, 14) == 13);
	CHECK(mip_from_coverage(10.0f, 1) == 0);
	CHECK(mip_from_coverage(10.0f, 0) == 0);
	CHECK(mip_from_coverage(std::numeric_limits<float>::infinity(), 14) == 13);
	CHECK(mip_from_coverage(-std::numeric_limits<float>::infinity(), 14) == 0);
	CHECK(mip_from_coverage(std::numeric_limits<float>::quiet_NaN(), 14) == 0);
	for (int exp = 0; exp < 16; exp++) {
		const float exact_power = std::ldexp(1.0f, exp);
		CHECK(mip_from_coverage(exact_power, 16) == exp);
	}
	uint32_t seed = 0x69bea4cdu;
	for (int i = 0; i < 100000; i++) {
		seed = seed * 1664525u + 1013904223u;
		float coverage;
		memcpy(&coverage, &seed, sizeof(coverage));
		const uint8_t mip_count = uint8_t(1 + (i % 16));
		int expected = 0;
		if (coverage >= 1.0f) {
			if (std::isfinite(coverage)) {
				int exponent;
				std::frexp(coverage, &exponent);
				expected = exponent - 1;
			} else {
				expected = mip_count - 1;
			}
			expected = expected < mip_count ? expected : mip_count - 1;
		}
		CHECK(mip_from_coverage(coverage, mip_count) == expected);
	}
}

} // namespace TestTextureStreamingFeedbackPolicy
