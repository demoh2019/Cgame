/**************************************************************************/
/*  test_bin_sorted_array.cpp                                              */
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
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF   */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_bin_sorted_array)

#include "core/templates/bin_sorted_array.h"

#include <vector>

namespace TestBinSortedArray {

TEST_CASE("[BinSortedArray] Mixed moves across 64 bins preserve grouping") {
	PagedArrayPool<int> pool(64);
	BinSortedArray<int> bins;
	bins.set_page_pool(&pool);

	std::vector<int> expected_bin(257, -1);
	int count = 0;
	for (int id = 1; id <= 256; id++) {
		int value = id;
		const int bin = (id * 19) % 64;
		const uint64_t position = bins.insert(value, bin);
		CHECK(bins[position] == id);
		expected_bin[id] = bin;
		count++;
	}
	CHECK(bins.get_bin_count() == 64);

	auto verify_bins = [&]() {
		std::vector<bool> seen(expected_bin.size(), false);
		int counted = 0;
		for (int bin = 0; bin < bins.get_bin_count(); bin++) {
			const int start = bins.get_bin_start(bin);
			const int length = bins.get_bin_size(bin);
			CHECK(start >= 0);
			CHECK(length >= 0);
			CHECK(start + length <= count);
			for (int i = 0; i < length; i++) {
				const int id = bins[start + i];
				REQUIRE(id > 0);
				REQUIRE(id < int(expected_bin.size()));
				CHECK(expected_bin[id] == bin);
				CHECK_FALSE(seen[id]);
				seen[id] = true;
				counted++;
			}
		}
		CHECK(counted == count);
		for (int id = 1; id < int(expected_bin.size()); id++) {
			CHECK(seen[id] == (expected_bin[id] >= 0));
		}
	};

	verify_bins();
	uint32_t state = 0x1234abcd;
	for (int step = 0; step < 700; step++) {
		state ^= state << 13;
		state ^= state >> 17;
		state ^= state << 5;
		const uint64_t index = state % uint32_t(count);
		const int id = bins[index];
		const int target_bin = int((state >> 16) & 63U);
		const uint64_t moved_index = bins.move(index, target_bin);
		CHECK(bins[moved_index] == id);
		expected_bin[id] = target_bin;
		if (step % 37 == 0) {
			verify_bins();
		}
	}
	verify_bins();

	for (int step = 0; step < 128; step++) {
		state = state * 1664525U + 1013904223U;
		const uint64_t index = state % uint32_t(count);
		const int id = bins[index];
		bins.remove_at(index);
		expected_bin[id] = -1;
		count--;
		if (step % 19 == 0) {
			verify_bins();
		}
	}
	verify_bins();
}

TEST_CASE("[BinSortedArray] Small-bin path and empty reset") {
	PagedArrayPool<int> pool(16);
	BinSortedArray<int> bins;
	bins.set_page_pool(&pool);
	for (int id = 1; id <= 40; id++) {
		int value = id;
		bins.insert(value, id % 4);
	}
	CHECK(bins.get_bin_count() == 4);
	int counted = 0;
	for (int bin = 0; bin < bins.get_bin_count(); bin++) {
		counted += bins.get_bin_size(bin);
	}
	CHECK(counted == 40);

	bins.reset();
	CHECK(bins.get_bin_count() == 0);
	int value = 77;
	CHECK(bins.insert(value, 0) == 0);
	CHECK(bins[0] == 77);
	CHECK(bins.get_bin_count() == 1);
}

} // namespace TestBinSortedArray
