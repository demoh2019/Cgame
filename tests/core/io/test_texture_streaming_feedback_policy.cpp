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
} // namespace TestTextureStreamingFeedbackPolicy
