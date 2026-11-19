/**************************************************************************/
/*  test_span.cpp                                                         */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_span)

#include "core/templates/span.h"

#include <limits>
#include <string>

namespace TestSpan {

TEST_CASE("[Span] Constexpr Validators") {
	constexpr Span<uint16_t> span_empty;
	static_assert(span_empty.ptr() == nullptr);
	static_assert(span_empty.size() == 0);
	static_assert(span_empty.is_empty());

	constexpr static uint16_t value = 5;
	Span<uint16_t> span_value(&value, 1);
	CHECK(span_value.ptr() == &value);
	CHECK(span_value.size() == 1);
	CHECK(!span_value.is_empty());

	static constexpr int ints[] = { 0, 1, 2, 3, 4, 5 };
	constexpr Span<int> span_array = ints;
	static_assert(span_array.size() == 6);
	static_assert(!span_array.is_empty());
	static_assert(span_array[0] == 0);
	static_assert(span_array[span_array.size() - 1] == 5);

	constexpr Span<char32_t> span_string = U"122345";
	static_assert(span_string.size() == 6);
	static_assert(!span_string.is_empty());
	static_assert(span_string[0] == U'1');
	static_assert(span_string[span_string.size() - 1] == U'5');

	CHECK_EQ(span_string, span_string); // Same identity / ptr.
	CHECK_EQ(span_string, Span(U"1223456", 6)); // Different ptr.
	CHECK_EQ(span_string, Span("122345").reinterpret<uint8_t>()); // Different type.

	int idx = 0;
	for (const char32_t &chr : span_string) {
		CHECK_EQ(chr, span_string[idx++]);
	}
}

TEST_CASE("[Span] Sequence find prefilters repeated candidates") {
	const uint8_t haystack[] = { 7, 7, 7, 7, 8, 7, 7, 8, 7, 7 };
	const uint8_t needle[] = { 7, 7, 8 };
	const Span<uint8_t> hay(haystack);
	const Span<uint8_t> pattern(needle);

	CHECK(hay.find_sequence(pattern) == 2);
	CHECK(hay.find_sequence(pattern, 3) == 5);
	CHECK(hay.find_sequence(pattern, 6) == -1);
	CHECK(hay.rfind_sequence(pattern) == 5);
	CHECK(hay.rfind_sequence(pattern, 4) == 2);
	CHECK(hay.rfind_sequence(pattern, 1) == -1);

	const uint8_t single[] = { 8 };
	CHECK(hay.find_sequence(Span<uint8_t>(single)) == 4);
	CHECK(hay.rfind_sequence(Span<uint8_t>(single)) == 7);
}

TEST_CASE("[Span] Sequence search empty and out-of-bounds ranges") {
	const int data[] = { 1, 2, 3, 4 };
	const int too_long[] = { 1, 2, 3, 4, 5 };
	const Span<int> hay(data);
	const Span<int> oversized(too_long);
	const Span<int> empty;

	CHECK(hay.find_sequence(oversized) == -1);
	CHECK(hay.rfind_sequence(oversized) == -1);
	CHECK(hay.find_sequence(oversized, 3) == -1);
	CHECK(hay.rfind_sequence(oversized, 3) == -1);
	CHECK(hay.find_sequence(empty) == 0);
	CHECK(hay.find_sequence(empty, hay.size()) == 4);
	CHECK(hay.find_sequence(empty, hay.size() + 1) == -1);
	CHECK(hay.rfind_sequence(empty) == 4);
	CHECK(hay.rfind_sequence(empty, hay.size() + 1) == -1);
	CHECK(hay.find_sequence(hay) == 0);
	CHECK(hay.rfind_sequence(hay) == 0);

	CHECK(empty.find_sequence(empty) == 0);
	CHECK(empty.rfind_sequence(empty) == 0);
	CHECK(empty.find_sequence(hay) == -1);
	CHECK(empty.rfind_sequence(hay) == -1);
}

TEST_CASE("[Span] Sequence search supports mixed and nontrivial types") {
	const int haystack[] = { 100, 200, 100, 200, 300 };
	const int16_t needle[] = { 100, 200 };
	const Span<int> hay(haystack);
	const Span<int16_t> pattern(needle);
	CHECK(hay.find_sequence(pattern) == 0);
	CHECK(hay.find_sequence(pattern, 1) == 2);
	CHECK(hay.rfind_sequence(pattern) == 2);

	const std::string words[] = { "alpha", "beta", "alpha", "beta", "gamma" };
	const std::string pair[] = { "alpha", "beta" };
	const Span<std::string> word_span(words);
	const Span<std::string> pair_span(pair);
	CHECK(word_span.find_sequence(pair_span) == 0);
	CHECK(word_span.find_sequence(pair_span, 1) == 2);
	CHECK(word_span.rfind_sequence(pair_span) == 2);
}

TEST_CASE("[Span] Reverse sequence word scan handles sparse and dense byte candidates") {
	uint8_t data[513];
	for (uint8_t &byte : data) {
		byte = 0x31;
	}
	const uint8_t pattern[] = { 0x31, 0x40, 0x50 };
	for (int start : { 63, 255, 509 }) {
		data[start] = pattern[0];
		data[start + 1] = pattern[1];
		data[start + 2] = pattern[2];
	}
	const Span<uint8_t> hay(data);
	const Span<uint8_t> needle(pattern);

	CHECK_EQ(hay.rfind_sequence(needle), 509);
	CHECK_EQ(hay.rfind_sequence(needle, 508), 255);
	CHECK_EQ(hay.rfind_sequence(needle, 254), 63);
	CHECK_EQ(hay.rfind_sequence(needle, 62), -1);

	const Span<uint8_t> unaligned(data + 1, 512);
	CHECK_EQ(unaligned.rfind_sequence(needle), 508);
	CHECK_EQ(unaligned.rfind_sequence(needle, 253), 62);

	const uint8_t none[] = { 0x31, 0x71 };
	CHECK_EQ(hay.rfind_sequence(Span<uint8_t>(none)), -1);

	const uint8_t dense[17] = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 };
	const uint8_t same_endpoints[] = { 1, 2, 1 };
	const uint8_t different_endpoints[] = { 1, 2 };
	CHECK_EQ(Span<uint8_t>(dense).rfind_sequence(Span<uint8_t>(same_endpoints)), -1);
	CHECK_EQ(Span<uint8_t>(dense).rfind_sequence(Span<uint8_t>(different_endpoints)), -1);
	const uint8_t single[] = { 1 };
	CHECK_EQ(Span<uint8_t>(dense).rfind_sequence(Span<uint8_t>(single)), 16);

	const int8_t signed_data[] = { -128, -7, 2, -128, -7, 2, 100 };
	const int8_t signed_pattern[] = { -128, -7, 2 };
	CHECK_EQ(Span<int8_t>(signed_data).rfind_sequence(Span<int8_t>(signed_pattern)), 3);
	CHECK_EQ(Span<int8_t>(signed_data).rfind_sequence(Span<int8_t>(signed_pattern), 2), 0);
}

TEST_CASE("[Span] Reverse sequence randomized differential regression") {
	uint8_t data[160];
	uint8_t pattern[7];
	uint32_t state = 0x12345678U;
	for (int round = 0; round < 120; round++) {
		for (uint8_t &byte : data) {
			state = 1664525U * state + 1013904223U;
			byte = uint8_t(state >> 24);
		}
		for (uint8_t &byte : pattern) {
			state = 1664525U * state + 1013904223U;
			byte = uint8_t(state >> 24);
		}
		const Span<uint8_t> hay(data);
		for (int len = 1; len <= 7; len++) {
			const Span<uint8_t> needle(pattern, len);
			for (int attempt = 0; attempt < 5; attempt++) {
				state = 1664525U * state + 1013904223U;
				const uint64_t from = state % (161 - len);
				int64_t expected = -1;
				for (int64_t i = int64_t(from); i >= 0; i--) {
					bool equal = true;
					for (int j = 0; j < len; j++) {
						if (data[i + j] != pattern[j]) {
							equal = false;
							break;
						}
					}
					if (equal) {
						expected = i;
						break;
					}
				}
				CHECK_EQ(hay.rfind_sequence(needle, from), expected);
			}
		}
	}
}

TEST_CASE("[Span] Reverse sequence retains empty constexpr and nonempty runtime semantics") {
	static constexpr uint8_t data[] = { 1, 2, 3, 1, 2, 3, 4 };
	static constexpr uint8_t pattern[] = { 1, 2, 3 };
	static constexpr Span<uint8_t> hay(data);
	static constexpr Span<uint8_t> needle(pattern);
	static constexpr Span<uint8_t> empty;
	// Nonempty matching calls are_spans_equal(), which is not constexpr.
	static_assert(hay.rfind_sequence(empty) == hay.size());
	static_assert(hay.rfind_sequence(empty, 0) == 0);
	CHECK_EQ(hay.rfind_sequence(needle), 3);
	CHECK_EQ(hay.rfind_sequence(needle, 2), 0);
	CHECK_EQ(hay.rfind_sequence(needle, 0), 0);
}

TEST_CASE("[Span] Float sequence searches preserve bitwise comparison semantics") {
	const float nan = std::numeric_limits<float>::quiet_NaN();
	const float values[] = { -0.0f, nan, 1.0f, -0.0f, nan };
	const float pattern[] = { values[0], values[1] };
	const float positive_zero[] = { 0.0f };
	const Span<float> hay(values);

	CHECK(hay.find_sequence(Span<float>(pattern)) == 0);
	CHECK(hay.rfind_sequence(Span<float>(pattern)) == 3);
	CHECK(hay.find_sequence(Span<float>(positive_zero)) == -1);
}

TEST_CASE("[Span] Runtime byte search respects offsets and signed values") {
	uint8_t bytes[4096];
	for (uint64_t i = 0; i < 4096; i++) {
		bytes[i] = uint8_t(i & 255);
	}
	const Span<uint8_t> hay(bytes);
	CHECK(hay.find(uint8_t(255)) == 255);
	CHECK(hay.find(uint8_t(255), 256) == 511);
	CHECK(hay.find(uint8_t(0), 4095) == -1);
	CHECK(hay.find(uint8_t(0), 4096) == -1);
	CHECK(hay.find(uint8_t(0), 4097) == -1);

	const int8_t signed_bytes[] = { -128, -7, 0, 42, 127 };
	const Span<int8_t> signed_hay(signed_bytes);
	CHECK(signed_hay.find(int8_t(-128)) == 0);
	CHECK(signed_hay.find(int8_t(-7), 1) == 1);
	CHECK(signed_hay.find(int8_t(-7), 2) == -1);
	CHECK(signed_hay.find(int8_t(127)) == 4);
}

TEST_CASE("[Span] Reverse byte search handles long spans, offsets and unaligned input") {
	uint8_t bytes[257];
	for (int i = 0; i < 257; i++) {
		bytes[i] = 0x31;
	}
	bytes[0] = 0xFF;
	bytes[8] = 0xFF;
	bytes[64] = 0xFF;
	bytes[255] = 0xFF;

	const Span<uint8_t> hay(bytes);
	CHECK_EQ(hay.rfind(uint8_t(0xFF)), 255);
	CHECK_EQ(hay.rfind(uint8_t(0xFF), 254), 64);
	CHECK_EQ(hay.rfind(uint8_t(0xFF), 63), 8);
	CHECK_EQ(hay.rfind(uint8_t(0xFF), 7), 0);
	CHECK_EQ(hay.rfind(uint8_t(0xFF), 0), 0);
	CHECK_EQ(hay.rfind(uint8_t(0xFE)), -1);

	// A one-byte offset must not require aligned 64-bit memory accesses.
	const Span<uint8_t> unaligned(bytes + 1, 256);
	CHECK_EQ(unaligned.rfind(uint8_t(0xFF)), 254);
	CHECK_EQ(unaligned.rfind(uint8_t(0xFF), 253), 63);
	CHECK_EQ(unaligned.rfind(uint8_t(0xFF), 6), -1);

	// The word-at-a-time zero-byte filter may report false candidates due
	// to a borrow, but the result must always be the last actual match.
	uint8_t borrow_bytes[24];
	for (uint8_t &byte : borrow_bytes) {
		byte = 1;
	}
	borrow_bytes[0] = 0;
	borrow_bytes[8] = 0;
	borrow_bytes[16] = 0;
	const Span<uint8_t> borrow_span(borrow_bytes);
	CHECK_EQ(borrow_span.rfind(uint8_t(0)), 16);
	CHECK_EQ(borrow_span.rfind(uint8_t(0), 15), 8);
	CHECK_EQ(borrow_span.rfind(uint8_t(0), 7), 0);

	const int8_t signed_bytes[] = { -128, -7, 0, -7, 127, -128 };
	const Span<int8_t> signed_span(signed_bytes);
	CHECK_EQ(signed_span.rfind(int8_t(-128)), 5);
	CHECK_EQ(signed_span.rfind(int8_t(-128), 4), 0);
	CHECK_EQ(signed_span.rfind(int8_t(-7)), 3);
}

TEST_CASE("[Span] Constexpr reverse byte search retains compile-time evaluation") {
	static constexpr uint8_t values[] = { 12, 99, 1, 99, 12, 5 };
	static constexpr Span<uint8_t> hay(values);
	static_assert(hay.rfind(uint8_t(12)) == 4);
	static_assert(hay.rfind(uint8_t(12), 3) == 0);
	static_assert(hay.rfind(uint8_t(99)) == 3);
	static_assert(hay.rfind(uint8_t(99), 2) == 1);
	static_assert(hay.rfind(uint8_t(3)) == -1);
	CHECK_EQ(hay.rfind(uint8_t(12)), 4);
}

TEST_CASE("[Span] Constexpr byte search retains compile-time evaluation") {
	static constexpr uint8_t values[] = { 0, 1, 2, 3, 4, 5 };
	static constexpr Span<uint8_t> span(values);
	static_assert(span.find(uint8_t(3)) == 3);
	static_assert(span.find(uint8_t(3), 4) == -1);
	static_assert(span.find(uint8_t(5)) == 5);
	static_assert(span.find(uint8_t(255)) == -1);
	CHECK(span.find(uint8_t(4)) == 4);
}

TEST_CASE("[Span] Fundamental storage identity and value comparisons") {
	int values[2048];
	int identical_copy[2048];
	for (int i = 0; i < 2048; i++) {
		values[i] = (i * 17) ^ (i >> 3);
		identical_copy[i] = values[i];
	}
	const Span<int> original(values);
	const Span<int> same_bytes(values);
	const Span<int> independent(identical_copy);
	CHECK(original == same_bytes);
	CHECK(original == independent);
	identical_copy[2047]++;
	CHECK(original != independent);
	CHECK(original == same_bytes);
	CHECK(Span<int>() == Span<int>());

	const float negative_zero[] = { -0.0f };
	const float positive_zero[] = { 0.0f };
	CHECK(Span<float>(negative_zero) == Span<float>(negative_zero));
	CHECK(Span<float>(negative_zero) != Span<float>(positive_zero));
}

TEST_CASE("[Span] Non-reflexive custom comparisons still call element equality") {
	struct NeverEqual {
		bool operator!=(const NeverEqual &) const { return true; }
	};
	NeverEqual value;
	const Span<NeverEqual> same(&value, 1);
	CHECK_FALSE(same == same);
}

} // namespace TestSpan
