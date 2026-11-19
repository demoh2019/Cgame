/**************************************************************************/
/*  test_paged_array.cpp                                                  */
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

TEST_FORCE_LINK(test_paged_array)

#include "core/templates/paged_array.h"

#include <algorithm>
#include <vector>
#include <thread>
#include <unordered_set>

namespace TestPagedArray {

TEST_CASE("[PagedArray][Performance] New pages allocate concurrently without duplicate ownership") {
	// Exercise simultaneous metadata growth and page payload allocation.
	// Every thread owns only its local collection; the pool is the shared state.
	constexpr int thread_count = 8;
	constexpr int pages_per_thread = 96;
	using Pool = PagedArrayPool<uint64_t>;
	Pool pool(64);
	std::vector<std::vector<Pool::PageInfo>> batches(thread_count);
	std::vector<std::thread> workers;
	workers.reserve(thread_count);

	for (int thread_index = 0; thread_index < thread_count; thread_index++) {
		workers.emplace_back([&pool, &batches, thread_index]() {
			auto &pages = batches[thread_index];
			pages.reserve(pages_per_thread);
			for (int i = 0; i < pages_per_thread; i++) {
				Pool::PageInfo page = pool.alloc_page();
				page.page[0] = (uint64_t(thread_index) << 32) | uint32_t(i);
				pages.push_back(page);
			}
		});
	}
	for (std::thread &worker : workers) {
		worker.join();
	}

	std::unordered_set<uint32_t> allocated_ids;
	std::unordered_set<uint64_t *> allocated_ptrs;
	for (int thread_index = 0; thread_index < thread_count; thread_index++) {
		const auto &pages = batches[thread_index];
		REQUIRE(pages.size() == pages_per_thread);
		for (int i = 0; i < pages_per_thread; i++) {
			const auto &page = pages[i];
			REQUIRE(page.page != nullptr);
			CHECK(page.page[0] == ((uint64_t(thread_index) << 32) | uint32_t(i)));
			CHECK(allocated_ids.insert(page.page_id).second);
			CHECK(allocated_ptrs.insert(page.page).second);
		}
	}
	CHECK(allocated_ids.size() == size_t(thread_count * pages_per_thread));

	// Once all pages are returned, a second allocation wave must recycle
	// precisely those pages instead of allocating new ones.
	for (const auto &pages : batches) {
		std::vector<uint32_t> ids;
		ids.reserve(pages.size());
		for (const auto &page : pages) {
			ids.push_back(page.page_id);
		}
		pool.free_pages(ids.data(), uint32_t(ids.size()));
	}

	for (int i = 0; i < thread_count * pages_per_thread; i++) {
		const Pool::PageInfo reused = pool.alloc_page();
		REQUIRE(reused.page != nullptr);
		CHECK(allocated_ids.erase(reused.page_id) == 1);
		pool.free_page(reused.page_id);
	}
	// The repeated alloc/free loop only exercises the most recently returned
	// page, so every page is still available for the final reset.
	pool.reset();
}

TEST_CASE("[PagedArray] Simple fill and refill") {
	PagedArrayPool<uint32_t> pool;
	PagedArray<uint32_t> array;
	array.set_page_pool(&pool);

	for (uint32_t i = 0; i < 123456; i++) {
		array.push_back(i);
	}
	CHECK_MESSAGE(
			array.size() == 123456,
			"PagedArray should have 123456 elements.");

	bool all_match = true;
	for (uint32_t i = 0; i < 123456; i++) {
		if (array[i] != i) {
			all_match = false;
			break;
		}
	}

	CHECK_MESSAGE(
			all_match,
			"PagedArray elements should match from 0 to 123455.");

	array.clear();

	CHECK_MESSAGE(
			array.size() == 0,
			"PagedArray elements should be 0 after clear.");

	for (uint32_t i = 0; i < 999; i++) {
		array.push_back(i);
	}
	CHECK_MESSAGE(
			array.size() == 999,
			"PagedArray should have 999 elements.");

	all_match = true;
	for (uint32_t i = 0; i < 999; i++) {
		if (array[i] != i) {
			all_match = false;
		}
	}

	CHECK_MESSAGE(
			all_match,
			"PagedArray elements should match from 0 to 998.");

	array.reset(); //reset so pagepool can be reset
	pool.reset();
}

TEST_CASE("[PagedArray] Shared pool fill, including merging") {
	PagedArrayPool<uint32_t> pool;
	PagedArray<uint32_t> array1;
	PagedArray<uint32_t> array2;
	array1.set_page_pool(&pool);
	array2.set_page_pool(&pool);

	for (uint32_t i = 0; i < 123456; i++) {
		array1.push_back(i);
	}
	CHECK_MESSAGE(
			array1.size() == 123456,
			"PagedArray #1 should have 123456 elements.");

	bool all_match = true;
	for (uint32_t i = 0; i < 123456; i++) {
		if (array1[i] != i) {
			all_match = false;
		}
	}

	CHECK_MESSAGE(
			all_match,
			"PagedArray #1 elements should match from 0 to 123455.");

	for (uint32_t i = 0; i < 999; i++) {
		array2.push_back(i);
	}
	CHECK_MESSAGE(
			array2.size() == 999,
			"PagedArray #2 should have 999 elements.");

	all_match = true;
	for (uint32_t i = 0; i < 999; i++) {
		if (array2[i] != i) {
			all_match = false;
		}
	}

	CHECK_MESSAGE(
			all_match,
			"PagedArray #2 elements should match from 0 to 998.");

	array1.merge_unordered(array2);

	CHECK_MESSAGE(
			array1.size() == 123456 + 999,
			"PagedArray #1 should now be 123456 + 999 elements.");

	CHECK_MESSAGE(
			array2.size() == 0,
			"PagedArray #2 should now be 0 elements.");

	array1.reset(); //reset so pagepool can be reset
	array2.reset(); //reset so pagepool can be reset
	pool.reset();
}

TEST_CASE("[PagedArray] Extensive merge_unordered() test") {
	for (int page_size = 1; page_size <= 128; page_size *= 2) {
		PagedArrayPool<uint32_t> pool(page_size);
		PagedArray<uint32_t> array1;
		PagedArray<uint32_t> array2;
		array1.set_page_pool(&pool);
		array2.set_page_pool(&pool);

		const int max_count = 123;
		// Test merging arrays of lengths 0+123, 1+122, 2+121, ..., 123+0
		for (uint32_t j = 0; j < max_count; j++) {
			CHECK(array1.size() == 0);
			CHECK(array2.size() == 0);

			uint32_t sum = 12345;
			for (uint32_t i = 0; i < j; i++) {
				// Hashing the addend makes it extremely unlikely for any values
				// other than the original inputs to produce a matching sum
				uint32_t addend = hash_murmur3_one_32(i) + i;
				array1.push_back(addend);
				sum += addend;
			}
			for (uint32_t i = j; i < max_count; i++) {
				// See above
				uint32_t addend = hash_murmur3_one_32(i) + i;
				array2.push_back(addend);
				sum += addend;
			}

			CHECK(array1.size() == j);
			CHECK(array2.size() == max_count - j);

			array1.merge_unordered(array2);
			CHECK_MESSAGE(array1.size() == max_count, "merge_unordered() added/dropped elements while merging");

			// If any elements were altered during merging, the sum will not match up.
			for (uint32_t i = 0; i < array1.size(); i++) {
				sum -= array1[i];
			}
			CHECK_MESSAGE(sum == 12345, "merge_unordered() altered elements while merging");

			array1.clear();
		}

		array1.reset();
		array2.reset();
		pool.reset();
	}
}


TEST_CASE("[PagedArray] Bulk clear releases many pages without losing shared ownership") {
	PagedArrayPool<uint32_t> pool(4);
	PagedArray<uint32_t> first;
	PagedArray<uint32_t> second;
	PagedArray<uint32_t> third;
	first.set_page_pool(&pool);
	second.set_page_pool(&pool);
	third.set_page_pool(&pool);

	for (uint32_t i = 0; i < 1029; i++) {
		first.push_back(i + 100);
	}
	for (uint32_t i = 0; i < 733; i++) {
		second.push_back(i + 5000);
	}
	for (uint32_t i = 0; i < 333; i++) {
		third.push_back(i + 9000);
	}

	first.clear();
	third.clear();
	CHECK(first.size() == 0);
	CHECK(third.size() == 0);
	for (uint32_t i = 0; i < 733; i++) {
		CHECK(second[i] == i + 5000);
	}

	// Interleaved allocation reuses the returned pages while second remains live.
	for (uint32_t i = 0; i < 1401; i++) {
		third.push_back(i + 12000);
	}
	for (uint32_t i = 0; i < 1401; i++) {
		CHECK(third[i] == i + 12000);
	}
	for (uint32_t i = 0; i < 733; i++) {
		CHECK(second[i] == i + 5000);
	}

	second.clear();
	third.clear();
	for (uint32_t i = 0; i < 2003; i++) {
		first.push_back(i ^ 0x5a5a);
	}
	for (uint32_t i = 0; i < 2003; i++) {
		CHECK(first[i] == (i ^ 0x5a5a));
	}
	first.reset();
	second.reset();
	third.reset();
	pool.reset();
}

TEST_CASE("[PagedArray] Metadata capacity growth survives repeated allocation boundaries") {
	PagedArrayPool<uint64_t> pool(1);
	PagedArray<uint64_t> array;
	array.set_page_pool(&pool);

	for (uint32_t round = 0; round < 9; round++) {
		const uint32_t elements = (uint32_t(1) << round) + 3;
		for (uint32_t i = 0; i < elements; i++) {
			array.push_back((uint64_t(round) << 32) | i);
		}
		for (uint32_t i = 0; i < elements; i++) {
			CHECK(array[i] == ((uint64_t(round) << 32) | i));
		}
		while (array.size() > elements / 2) {
			array.pop_back();
		}
		for (uint32_t i = 0; i < elements / 2; i++) {
			CHECK(array[i] == ((uint64_t(round) << 32) | i));
		}
		array.clear();
		CHECK(array.size() == 0);
	}

	// Reset frees the metadata even when capacity exceeds the number of pages.
	array.reset();
	pool.reset();
	for (uint32_t i = 0; i < 129; i++) {
		array.push_back(i * 3);
	}
	for (uint32_t i = 0; i < 129; i++) {
		CHECK(array[i] == uint64_t(i) * 3);
	}
	array.reset();
	pool.reset();
}

TEST_CASE("[PagedArray] Clearing an empty paged array is safe") {
	PagedArrayPool<uint32_t> pool(2);
	PagedArray<uint32_t> array;
	array.set_page_pool(&pool);
	array.clear();
	array.clear();
	array.push_back(42);
	array.pop_back();
	array.clear();
	CHECK(array.size() == 0);
	array.reset();
	pool.reset();
}


TEST_CASE("[PagedArray] Bulk page merge preserves every element across partial pages") {
	for (uint32_t page_size = 1; page_size <= 128; page_size *= 2) {
		PagedArrayPool<uint32_t> pool(page_size);
		PagedArray<uint32_t> dst;
		PagedArray<uint32_t> src;
		dst.set_page_pool(&pool);
		src.set_page_pool(&pool);
		std::vector<uint32_t> expected;
		expected.reserve(1290);

		for (uint32_t i = 0; i < 513; i++) {
			const uint32_t value = i * 17 + 5;
			dst.push_back(value);
			expected.push_back(value);
		}
		for (uint32_t i = 0; i < 777; i++) {
			const uint32_t value = i * 31 + 50000;
			src.push_back(value);
			expected.push_back(value);
		}
		dst.merge_unordered(src);
		CHECK(dst.size() == expected.size());
		CHECK(src.size() == 0);
		std::vector<uint32_t> actual;
		actual.reserve(dst.size());
		for (uint64_t i = 0; i < dst.size(); i++) {
			actual.push_back(dst[i]);
		}
		std::sort(expected.begin(), expected.end());
		std::sort(actual.begin(), actual.end());
		CHECK(actual == expected);
		// Empty source merging must not discard the existing destination remainder.
		dst.merge_unordered(src);
		CHECK(dst.size() == expected.size());
		dst.reset();
		src.reset();
		pool.reset();
	}
}

struct PagedAssignmentProbe {
	inline static int assignments = 0;
	int value = 0;

	explicit PagedAssignmentProbe(int p_value = 0) :
			value(p_value) {}
	PagedAssignmentProbe(const PagedAssignmentProbe &) = default;
	PagedAssignmentProbe &operator=(const PagedAssignmentProbe &p_other) {
		assignments++;
		value = p_other.value;
		return *this;
	}
};

TEST_CASE("[PagedArray] Unordered removal avoids last-element self-assignment") {
	PagedArrayPool<PagedAssignmentProbe> pool(4);
	PagedArray<PagedAssignmentProbe> array;
	array.set_page_pool(&pool);
	for (int i = 0; i < 9; i++) {
		PagedAssignmentProbe item(i);
		array.push_back(item);
	}
	PagedAssignmentProbe::assignments = 0;
	array.remove_at_unordered(8);
	CHECK(array.size() == 8);
	CHECK(PagedAssignmentProbe::assignments == 0);
	array.remove_at_unordered(0);
	CHECK(array.size() == 7);
	CHECK(PagedAssignmentProbe::assignments == 1);
	CHECK(array[0].value == 7);
	for (int i = 1; i < 7; i++) {
		CHECK(array[i].value == i);
	}
	array.reset();
	pool.reset();
}

struct PagedLifetimeProbe {
	inline static int alive = 0;
	inline static int destroyed = 0;
	inline static int copies = 0;
	int value = 0;

	explicit PagedLifetimeProbe(int p_value = 0) :
			value(p_value) {
		alive++;
	}
	PagedLifetimeProbe(const PagedLifetimeProbe &p_other) :
			value(p_other.value) {
		alive++;
		copies++;
	}
	PagedLifetimeProbe &operator=(const PagedLifetimeProbe &p_other) {
		value = p_other.value;
		return *this;
	}
	~PagedLifetimeProbe() {
		destroyed++;
		alive--;
	}
};

TEST_CASE("[PagedArray] Page-wise clear destroys exactly the live nontrivial elements") {
	PagedLifetimeProbe::alive = 0;
	PagedLifetimeProbe::destroyed = 0;
	PagedLifetimeProbe::copies = 0;
	PagedArrayPool<PagedLifetimeProbe> pool(8);
	PagedArray<PagedLifetimeProbe> array;
	array.set_page_pool(&pool);

	for (int n : { 1, 7, 8, 9, 16, 17, 35, 64 }) {
		for (int i = 0; i < n; i++) {
			PagedLifetimeProbe item(i);
			array.push_back(item);
		}
		CHECK(array.size() == uint64_t(n));
		CHECK(PagedLifetimeProbe::alive == n);
		for (int i = 0; i < n; i++) {
			CHECK(array[i].value == i);
		}
		array.pop_back();
		CHECK(PagedLifetimeProbe::alive == n - 1);
		array.clear();
		CHECK(PagedLifetimeProbe::alive == 0);
		CHECK(array.size() == 0);
		array.clear();
	}
	CHECK(PagedLifetimeProbe::destroyed > 0);
	array.reset();
	pool.reset();
	CHECK(PagedLifetimeProbe::alive == 0);
}

TEST_CASE("[PagedArray] Merge and page-wise clear preserve nontrivial lifetimes") {
	PagedLifetimeProbe::alive = 0;
	PagedLifetimeProbe::destroyed = 0;
	PagedLifetimeProbe::copies = 0;
	PagedArrayPool<PagedLifetimeProbe> pool(8);
	PagedArray<PagedLifetimeProbe> dst;
	PagedArray<PagedLifetimeProbe> src;
	dst.set_page_pool(&pool);
	src.set_page_pool(&pool);

	for (int i = 0; i < 13; i++) {
		PagedLifetimeProbe item(i);
		dst.push_back(item);
	}
	for (int i = 13; i < 39; i++) {
		PagedLifetimeProbe item(i);
		src.push_back(item);
	}
	CHECK(PagedLifetimeProbe::alive == 39);
	dst.merge_unordered(src);
	CHECK(dst.size() == 39);
	CHECK(src.size() == 0);
	CHECK(PagedLifetimeProbe::alive == 39);
	bool seen[39] = {};
	for (uint64_t i = 0; i < dst.size(); i++) {
		const int value = dst[i].value;
		REQUIRE(value >= 0);
		REQUIRE(value < 39);
		CHECK_FALSE(seen[value]);
		seen[value] = true;
	}
	for (bool present : seen) {
		CHECK(present);
	}
	dst.clear();
	CHECK(PagedLifetimeProbe::alive == 0);
	src.clear();
	dst.reset();
	src.reset();
	pool.reset();
}

TEST_CASE("[PagedArray] Bulk trivial remainder copy preserves large partial pages") {
	PagedArrayPool<uint64_t> pool(1024);
	PagedArray<uint64_t> dst;
	PagedArray<uint64_t> src;
	dst.set_page_pool(&pool);
	src.set_page_pool(&pool);
	std::vector<uint64_t> expected;
	for (uint64_t i = 0; i < 1537; i++) {
		const uint64_t value = i + 1;
		dst.push_back(value);
		expected.push_back(value);
	}
	for (uint64_t i = 0; i < 1903; i++) {
		const uint64_t value = i + 100000;
		src.push_back(value);
		expected.push_back(value);
	}
	dst.merge_unordered(src);
	CHECK(dst.size() == expected.size());
	CHECK(src.size() == 0);
	std::vector<uint64_t> actual;
	actual.reserve(dst.size());
	for (uint64_t i = 0; i < dst.size(); i++) {
		actual.push_back(dst[i]);
	}
	std::sort(actual.begin(), actual.end());
	std::sort(expected.begin(), expected.end());
	CHECK(actual == expected);
	dst.reset();
	src.reset();
	pool.reset();
}

} // namespace TestPagedArray
