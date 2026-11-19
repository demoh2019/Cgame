/**************************************************************************/
/*  test_local_vector.cpp                                                 */
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

TEST_FORCE_LINK(test_local_vector)

#include "core/templates/local_vector.h"

#include <algorithm>
#include <cstdint>
#include <string>
#include <type_traits>
#include <vector>

namespace TestLocalVector {

TEST_CASE("[LocalVector] Reserve known size avoids relocation for bulk append") {
	LocalVector<uint32_t> entries;
	entries.reserve(128);
	CHECK(entries.get_capacity() >= 128);
	const uint32_t *begin = entries.ptr();
	for (uint32_t i = 0; i < 128; ++i) {
		entries.push_back(i * 3);
		CHECK(entries.ptr() == begin);
	}
	CHECK(entries.size() == 128);
	for (uint32_t i = 0; i < entries.size(); ++i) {
		CHECK(entries[i] == i * 3);
	}
}



TEST_CASE("[LocalVector] List Initialization.") {
	LocalVector<int> vector{ 0, 1, 2, 3, 4 };

	CHECK(vector.size() == 5);
	CHECK(vector[0] == 0);
	CHECK(vector[1] == 1);
	CHECK(vector[2] == 2);
	CHECK(vector[3] == 3);
	CHECK(vector[4] == 4);
}

TEST_CASE("[LocalVector] Push Back.") {
	LocalVector<int> vector;
	vector.push_back(0);
	vector.push_back(1);
	vector.push_back(2);
	vector.push_back(3);
	vector.push_back(4);

	CHECK(vector[0] == 0);
	CHECK(vector[1] == 1);
	CHECK(vector[2] == 2);
	CHECK(vector[3] == 3);
	CHECK(vector[4] == 4);
}

TEST_CASE("[LocalVector] Find, has.") {
	LocalVector<int> vector;
	vector.push_back(3);
	vector.push_back(1);
	vector.push_back(4);
	vector.push_back(0);
	vector.push_back(2);

	CHECK(vector[0] == 3);
	CHECK(vector[1] == 1);
	CHECK(vector[2] == 4);
	CHECK(vector[3] == 0);
	CHECK(vector[4] == 2);

	CHECK(vector.find(0) == 3);
	CHECK(vector.find(1) == 1);
	CHECK(vector.find(2) == 4);
	CHECK(vector.find(3) == 0);
	CHECK(vector.find(4) == 2);

	CHECK(vector.find(-1) == -1);
	CHECK(vector.find(5) == -1);

	CHECK(vector.has(0));
	CHECK(vector.has(1));
	CHECK(vector.has(2));
	CHECK(vector.has(3));
	CHECK(vector.has(4));

	CHECK(!vector.has(-1));
	CHECK(!vector.has(5));
}

TEST_CASE("[LocalVector] Remove.") {
	LocalVector<int> vector;
	vector.push_back(0);
	vector.push_back(1);
	vector.push_back(2);
	vector.push_back(3);
	vector.push_back(4);

	vector.remove_at(0);

	CHECK(vector[0] == 1);
	CHECK(vector[1] == 2);
	CHECK(vector[2] == 3);
	CHECK(vector[3] == 4);

	vector.remove_at(2);

	CHECK(vector[0] == 1);
	CHECK(vector[1] == 2);
	CHECK(vector[2] == 4);

	vector.remove_at(1);

	CHECK(vector[0] == 1);
	CHECK(vector[1] == 4);

	vector.remove_at(0);

	CHECK(vector[0] == 4);
}

TEST_CASE("[LocalVector] Remove Unordered.") {
	LocalVector<int> vector;
	vector.push_back(0);
	vector.push_back(1);
	vector.push_back(2);
	vector.push_back(3);
	vector.push_back(4);

	CHECK(vector.size() == 5);

	vector.remove_at_unordered(0);

	CHECK(vector.size() == 4);

	CHECK(vector.find(0) == -1);
	CHECK(vector.find(1) != -1);
	CHECK(vector.find(2) != -1);
	CHECK(vector.find(3) != -1);
	CHECK(vector.find(4) != -1);

	// Now the vector is no more ordered.
	vector.remove_at_unordered(vector.find(3));

	CHECK(vector.size() == 3);

	CHECK(vector.find(3) == -1);
	CHECK(vector.find(1) != -1);
	CHECK(vector.find(2) != -1);
	CHECK(vector.find(4) != -1);

	vector.remove_at_unordered(vector.find(2));

	CHECK(vector.size() == 2);

	CHECK(vector.find(2) == -1);
	CHECK(vector.find(1) != -1);
	CHECK(vector.find(4) != -1);

	vector.remove_at_unordered(vector.find(4));

	CHECK(vector.size() == 1);

	CHECK(vector.find(4) == -1);
	CHECK(vector.find(1) != -1);

	// Remove the last one.
	vector.remove_at_unordered(0);

	CHECK(vector.is_empty());
	CHECK(vector.size() == 0);
}

TEST_CASE("[LocalVector] Erase Unordered.") {
	LocalVector<int> vector;
	vector.push_back(1);
	vector.push_back(3);
	vector.push_back(0);
	vector.push_back(2);
	vector.push_back(4);

	CHECK(vector.find(1) == 0);

	vector.erase_unordered(1);

	CHECK(vector.find(1) == -1);
	CHECK(vector.size() == 4);
	CHECK(vector[0] == 4);
}

TEST_CASE("[LocalVector] Erase.") {
	LocalVector<int> vector;
	vector.push_back(1);
	vector.push_back(3);
	vector.push_back(0);
	vector.push_back(2);
	vector.push_back(4);

	CHECK(vector.find(2) == 3);

	vector.erase(2);

	CHECK(vector.find(2) == -1);
	CHECK(vector.size() == 4);
}

TEST_CASE("[LocalVector] Size / Resize / Reserve.") {
	LocalVector<int> vector;

	CHECK(vector.is_empty());
	CHECK(vector.size() == 0);
	CHECK(vector.get_capacity() == 0);

	vector.resize(10);

	CHECK(vector.size() == 10);
	CHECK(vector.get_capacity() >= 10);

	vector.resize(5);

	CHECK(vector.size() == 5);
	// Capacity is supposed to change only when the size increase.
	CHECK(vector.get_capacity() >= 10);

	vector.remove_at(0);
	vector.remove_at(0);
	vector.remove_at(0);

	CHECK(vector.size() == 2);
	// Capacity is supposed to change only when the size increase.
	CHECK(vector.get_capacity() >= 10);

	vector.reset();

	CHECK(vector.size() == 0);
	CHECK(vector.get_capacity() == 0);

	vector.reserve(3);

	CHECK(vector.is_empty());
	CHECK(vector.size() == 0);
	CHECK(vector.get_capacity() >= 3);

	vector.push_back(0);
	vector.push_back(0);
	vector.push_back(0);

	CHECK(vector.size() == 3);
	CHECK(vector.get_capacity() >= 3);

	vector.push_back(0);

	CHECK(vector.size() == 4);
	CHECK(vector.get_capacity() >= 4);
}


TEST_CASE("[LocalVector] Trivial inserts and erases match std::vector through randomized shifts") {
	LocalVector<int> actual;
	std::vector<int> reference;
	uint32_t seed = 0x48d12a73;
	for (int step = 0; step < 4096; step++) {
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		if (((seed & 3) != 0 && reference.size() < 256) || reference.empty()) {
			const size_t at = (seed >> 8) % (reference.size() + 1);
			const int value = int(seed >> 10);
			actual.insert(uint32_t(at), value);
			reference.insert(reference.begin() + at, value);
		} else {
			const size_t at = (seed >> 8) % reference.size();
			actual.remove_at(uint32_t(at));
			reference.erase(reference.begin() + at);
		}
		CHECK(actual.size() == reference.size());
		for (size_t i = 0; i < reference.size(); i++) {
			CHECK(actual[uint32_t(i)] == reference[i]);
		}
	}
}

struct NonTrivialLocalItem {
	int value = 0;
	NonTrivialLocalItem() = default;
	explicit NonTrivialLocalItem(int p_value) :
			value(p_value) {}
	NonTrivialLocalItem(const NonTrivialLocalItem &) = default;
	NonTrivialLocalItem(NonTrivialLocalItem &&p_other) :
			value(p_other.value) {}
	NonTrivialLocalItem &operator=(const NonTrivialLocalItem &) = default;
	NonTrivialLocalItem &operator=(NonTrivialLocalItem &&p_other) {
		value = p_other.value;
		return *this;
	}
	~NonTrivialLocalItem() {}
};
static_assert(!std::is_trivially_copyable_v<NonTrivialLocalItem>);

TEST_CASE("[LocalVector] Nontrivial inserted elements retain normal move semantics") {
	LocalVector<NonTrivialLocalItem> values;
	for (int i = 0; i < 12; i++) {
		values.push_back(NonTrivialLocalItem(i));
	}
	values.insert(0, NonTrivialLocalItem(99));
	values.insert(7, NonTrivialLocalItem(88));
	values.insert(values.size(), NonTrivialLocalItem(77));
	CHECK(values.size() == 15);
	CHECK(values[0].value == 99);
	CHECK(values[7].value == 88);
	CHECK(values[14].value == 77);
	values.remove_at(0);
	values.remove_at(6);
	CHECK(values.size() == 13);
	for (int i = 0; i < 12; i++) {
		CHECK(values[uint32_t(i)].value == i);
	}
	CHECK(values[12].value == 77);
}

struct CountedLocalAssignment {
	int value = 0;
	static inline int assignments = 0;

	CountedLocalAssignment() = default;
	explicit CountedLocalAssignment(int p_value) :
			value(p_value) {}
	CountedLocalAssignment(const CountedLocalAssignment &) = default;
	CountedLocalAssignment(CountedLocalAssignment &&) = default;
	CountedLocalAssignment &operator=(const CountedLocalAssignment &p_other) {
		value = p_other.value;
		assignments++;
		return *this;
	}
	CountedLocalAssignment &operator=(CountedLocalAssignment &&p_other) {
		value = p_other.value;
		assignments++;
		return *this;
	}
	~CountedLocalAssignment() { value = -999; }
};

TEST_CASE("[LocalVector] Self and overlapping nontrivial Span assignments avoid wasted copies") {
	LocalVector<CountedLocalAssignment> items;
	for (int i = 0; i < 8; i++) {
		items.push_back(CountedLocalAssignment(i));
	}
	CountedLocalAssignment::assignments = 0;
	items = items.span();
	CHECK(CountedLocalAssignment::assignments == 0);
	CHECK(items.size() == 8);

	// The source lives in the tail that resize() would otherwise destroy.
	items = Span<CountedLocalAssignment>(items.ptr() + 3, 5);
	CHECK(items.size() == 5);
	CHECK(CountedLocalAssignment::assignments == 5);
	for (int i = 0; i < 5; i++) {
		CHECK(items[uint32_t(i)].value == i + 3);
	}

	CountedLocalAssignment::assignments = 0;
	items = Span<CountedLocalAssignment>(items.ptr(), 3);
	CHECK(items.size() == 3);
	CHECK(CountedLocalAssignment::assignments == 0);
	CHECK(items[0].value == 3);
	CHECK(items[1].value == 4);
	CHECK(items[2].value == 5);

	CountedLocalAssignment::assignments = 0;
	const LocalVector<CountedLocalAssignment> &self = items;
	items = self;
	CHECK(CountedLocalAssignment::assignments == 0);
	CHECK(items.size() == 3);
}

TEST_CASE("[LocalVector] Trivial edge shifts preserve zero and last slot") {
	LocalVector<uint64_t> values;
	values.insert(0, uint64_t(0x101));
	CHECK(values.size() == 1);
	values.insert(0, uint64_t(0x202));
	values.insert(1, uint64_t(0x303));
	values.insert(3, uint64_t(0x404));
	CHECK(values.size() == 4);
	CHECK(values[0] == 0x202);
	CHECK(values[1] == 0x303);
	CHECK(values[2] == 0x101);
	CHECK(values[3] == 0x404);
	values.remove_at(3);
	values.remove_at(0);
	CHECK(values.size() == 2);
	CHECK(values[0] == 0x303);
	CHECK(values[1] == 0x101);
}


TEST_CASE("[LocalVector] Trivial Span assignment supports overlapping storage") {
	LocalVector<int> values;
	for (int i = 0; i < 32; i++) {
		values.push_back(i);
	}
	values = Span<int>(values.ptr() + 8, 24);
	CHECK(values.size() == 24);
	for (int i = 0; i < 24; i++) {
		CHECK(values[uint32_t(i)] == i + 8);
	}
	values = values.span();
	CHECK(values.size() == 24);
	for (int i = 0; i < 24; i++) {
		CHECK(values[uint32_t(i)] == i + 8);
	}
	LocalVector<int> empty;
	values = empty.span();
	CHECK(values.is_empty());
}

TEST_CASE("[LocalVector] Trivial Vector move assignment copies bulk values") {
	Vector<uint32_t> source;
	source.resize(256);
	uint32_t *write = source.ptrw();
	for (uint32_t i = 0; i < 256; i++) {
		write[i] = (i << 16) ^ 0xBA5E;
	}
	LocalVector<uint32_t> values;
	values = std::move(source);
	CHECK(values.size() == 256);
	for (uint32_t i = 0; i < 256; i++) {
		CHECK(values[i] == ((i << 16) ^ 0xBA5E));
	}
}


TEST_CASE("[LocalVector] Bulk unordered erase handles clustered and complete matches") {
	LocalVector<int> values{ 7, 1, 7, 2, 7, 7, 7 };
	CHECK(values.erase_multiple_unordered(7) == 5);
	CHECK(values.size() == 2);
	CHECK(values.find(1) != -1);
	CHECK(values.find(2) != -1);
	CHECK(values.erase_multiple_unordered(7) == 0);
	CHECK(values.size() == 2);

	LocalVector<int> all_matches{ 4, 4, 4, 4 };
	CHECK(all_matches.erase_multiple_unordered(4) == 4);
	CHECK(all_matches.is_empty());
	CHECK(all_matches.erase_multiple_unordered(4) == 0);

	LocalVector<int> tail_matches{ 1, 2, 3, 4, 4, 4 };
	CHECK(tail_matches.erase_multiple_unordered(4) == 3);
	CHECK(tail_matches.size() == 3);
	CHECK(tail_matches[0] == 1);
	CHECK(tail_matches[1] == 2);
	CHECK(tail_matches[2] == 3);
}

TEST_CASE("[LocalVector] Bulk unordered erase matches reference across deterministic distributions") {
	uint32_t seed = 0xc0ffee13;
	for (int round = 0; round < 256; round++) {
		LocalVector<uint32_t> values;
		std::vector<uint32_t> expected;
		const int length = (round * 37) % 193;
		for (int i = 0; i < length; i++) {
			seed = seed * 1664525u + 1013904223u;
			const uint32_t value = (seed >> 24) % 9;
			values.push_back(value);
			expected.push_back(value);
		}
		const uint32_t needle = uint32_t(round % 9);
		const uint32_t original_capacity = values.get_capacity();
		expected.erase(std::remove(expected.begin(), expected.end(), needle), expected.end());
		CHECK(values.erase_multiple_unordered(needle) == uint32_t(length - expected.size()));
		CHECK(values.get_capacity() == original_capacity);
		CHECK(values.size() == expected.size());
		CHECK(values.erase_multiple_unordered(needle) == 0);

		std::vector<uint32_t> survivors;
		for (uint32_t value : values) {
			survivors.push_back(value);
		}
		std::sort(survivors.begin(), survivors.end());
		std::sort(expected.begin(), expected.end());
		CHECK(survivors == expected);
	}
}

TEST_CASE("[LocalVector] Bulk unordered erase destroys nontrivial matching elements") {
	LocalVector<std::string> values{ "alpha", "drop", "beta", "drop", "drop", "gamma", "drop" };
	CHECK(values.erase_multiple_unordered(std::string("drop")) == 4);
	CHECK(values.size() == 3);
	std::vector<std::string> survivors;
	for (const std::string &value : values) {
		survivors.push_back(value);
	}
	std::sort(survivors.begin(), survivors.end());
	const std::vector<std::string> expected{ "alpha", "beta", "gamma" };
	CHECK(survivors == expected);
	CHECK(values.erase_multiple_unordered(std::string("drop")) == 0);
}


struct LocalOrderedComparisonCount {
	int value = 0;
	static inline int comparisons = 0;

	bool operator<(const LocalOrderedComparisonCount &p_other) const {
		comparisons++;
		return value < p_other.value;
	}
};

TEST_CASE("[LocalVector] Ordered append skips binary search for ascending and equal values") {
	LocalVector<LocalOrderedComparisonCount> values;
	for (int i = 0; i < 256; i++) {
		LocalOrderedComparisonCount::comparisons = 0;
		values.ordered_insert({ i });
		CHECK(LocalOrderedComparisonCount::comparisons == (i == 0 ? 0 : 1));
	}
	CHECK(values.size() == 256);
	LocalOrderedComparisonCount::comparisons = 0;
	values.ordered_insert({ 255 });
	CHECK(LocalOrderedComparisonCount::comparisons == 1);
	CHECK(values[255].value == 255);
	CHECK(values[256].value == 255);
	values.ordered_insert({ -1 });
	CHECK(values[0].value == -1);
}

TEST_CASE("[LocalVector] Ordered insert matches upper_bound through mixed workloads") {
	LocalVector<int> values;
	std::vector<int> reference;
	uint32_t seed = 0x971c5b36u;
	for (int i = 0; i < 2048; i++) {
		seed = seed * 1664525u + 1013904223u;
		const int value = i < 500 ? i : (i < 1000 ? 1000 - i : int((seed >> 8) % 129u) - 64);
		values.ordered_insert(value);
		reference.insert(std::upper_bound(reference.begin(), reference.end(), value), value);
	}
	CHECK(values.size() == reference.size());
	for (uint32_t i = 0; i < values.size(); i++) {
		CHECK(values[i] == reference[i]);
	}

	LocalVector<std::string> strings;
	strings.ordered_insert("zeta");
	strings.ordered_insert("alpha");
	strings.ordered_insert("alpha");
	strings.ordered_insert("omega");
	CHECK(strings.size() == 4);
	CHECK(strings[0] == "alpha");
	CHECK(strings[1] == "alpha");
	CHECK(strings[2] == "omega");
	CHECK(strings[3] == "zeta");
}

} // namespace TestLocalVector
