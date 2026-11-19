/**************************************************************************/
/*  test_sort_array.cpp                                                   */
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

TEST_FORCE_LINK(test_sort_array)

#include "core/templates/sort_array.h"
#include "core/templates/vector.h"

#include <algorithm>
#include <cstdint>
#include <memory>
#include <vector>

namespace TestSortArray {

TEST_CASE("[SortArray] Moving insertion sort works with noncopyable keys") {
	struct MoveKey {
		std::unique_ptr<int> key;
		explicit MoveKey(int v) : key(std::make_unique<int>(v)) {}
		MoveKey(const MoveKey &) = delete;
		MoveKey &operator=(const MoveKey &) = delete;
		MoveKey(MoveKey &&) = default;
		MoveKey &operator=(MoveKey &&) = default;
	};
	struct Less {
		bool operator()(const MoveKey &a, const MoveKey &b) const {
			return *a.key < *b.key;
		}
	};
	MoveKey values[] = { MoveKey(7), MoveKey(2), MoveKey(6), MoveKey(0), MoveKey(5), MoveKey(1) };
	SortArray<MoveKey, Less> sorter;
	sorter.insertion_sort(0, 6, values);
	for (int i = 0; i < 6; i++) {
		CHECK(values[i].key != nullptr);
		if (i > 0) {
			CHECK(*values[i - 1].key <= *values[i].key);
		}
	}
}



TEST_CASE("[SortArray] Sort Sorted") {
	constexpr int size = 128;
	Vector<int> vector;
	vector.reserve_exact(size);
	for (int i = 0; i < size; i++) {
		vector.push_back(i);
	}

	SortArray<int> sort;
	sort.sort(vector.ptrw(), vector.size());

	CHECK(vector.size() == size);
	for (int i = 1; i < size; i++) {
		CHECK(vector[i] >= vector[i - 1]);
	}
}

TEST_CASE("[SortArray] Sort Reverse") {
	constexpr int size = 128;
	Vector<int> vector;
	vector.reserve_exact(size);
	for (int i = size - 1; i >= 0; i--) {
		vector.push_back(i);
	}

	SortArray<int> sort;
	sort.sort(vector.ptrw(), vector.size());

	CHECK(vector.size() == size);
	for (int i = 1; i < size; i++) {
		CHECK(vector[i] >= vector[i - 1]);
	}
}

TEST_CASE("[SortArray] Sort Pyramid") {
	constexpr int spike = 64;
	constexpr int size = spike * 2 + 1;
	Vector<int> vector;
	vector.reserve_exact(size);

	// This will create a pyramid pattern.
	for (int i = spike; i >= -spike; i--) {
		vector.push_back(spike - Math::abs(i));
	}

	SortArray<int> sort;
	sort.sort(vector.ptrw(), vector.size());

	CHECK(vector.size() == size);
	for (int i = 1; i < size; i++) {
		CHECK(vector[i] >= vector[i - 1]);
	}
}

TEST_CASE("[SortArray] Sort Sawtooth") {
	constexpr int spike = 4;
	constexpr int count = 16;
	constexpr int size = count * (spike * 2 + 1);
	Vector<int> vector;
	vector.reserve_exact(size);

	// This will create a sawtooth pattern.
	for (int i = 0; i < count; i++) {
		for (int ii = spike; ii >= -spike; ii--) {
			vector.push_back(spike - Math::abs(ii));
		}
	}

	SortArray<int> sort;
	sort.sort(vector.ptrw(), vector.size());

	CHECK(vector.size() == size);
	for (int i = 1; i < size; i++) {
		CHECK(vector[i] >= vector[i - 1]);
	}
}

TEST_CASE("[SortArray] Sort Random") {
	constexpr int size = 128;
	for (int i = 0; i < size; i++) {
		Vector<int> vector;
		vector.reserve_exact(size);
		for (int ii = 0; ii < size; ii++) {
			vector.push_back(Math::rand());
		}

		SortArray<int> sort;
		sort.sort(vector.ptrw(), vector.size());

		CHECK(vector.size() == size);
		for (int ii = 1; ii < size; ii++) {
			CHECK(vector[ii] >= vector[ii - 1]);
		}
	}
}

TEST_CASE("[SortArray] Nth Element Sorted") {
	constexpr int size = 128;
	for (int i = 0; i < size; i++) {
		Vector<int> vector;
		vector.reserve_exact(size);
		int n = i;
		for (int ii = 0; ii < size; ii++) {
			vector.push_back(ii);
		}

		SortArray<int> sort;
		sort.nth_element(0, vector.size(), n, vector.ptrw());

		CHECK(vector.size() == size);
		for (int ii = 0; ii < size; ii++) {
			if (ii <= n) {
				CHECK(vector[ii] <= vector[n]);
			} else {
				CHECK(vector[ii] >= vector[n]);
			}
		}
	}
}

TEST_CASE("[SortArray] Nth Element Reverse") {
	constexpr int size = 128;
	for (int i = 0; i < size; i++) {
		Vector<int> vector;
		vector.reserve_exact(size);
		int n = i;
		for (int ii = size - 1; ii >= 0; ii--) {
			vector.push_back(ii);
		}

		SortArray<int> sort;
		sort.nth_element(0, vector.size(), n, vector.ptrw());

		CHECK(vector.size() == size);
		for (int ii = 0; ii < size; ii++) {
			if (ii <= n) {
				CHECK(vector[ii] <= vector[n]);
			} else {
				CHECK(vector[ii] >= vector[n]);
			}
		}
	}
}

TEST_CASE("[SortArray] Nth Element Pyramid") {
	constexpr int spike = 64;
	constexpr int size = spike * 2 + 1;
	for (int i = 0; i < size; i++) {
		Vector<int> vector;
		vector.reserve_exact(size);
		int n = i;

		// This will create a pyramid pattern.
		for (int ii = spike; ii >= -spike; ii--) {
			vector.push_back(spike - Math::abs(ii));
		}

		SortArray<int> sort;
		sort.nth_element(0, vector.size(), n, vector.ptrw());

		CHECK(vector.size() == size);
		for (int ii = 0; ii < size; ii++) {
			if (ii <= n) {
				CHECK(vector[ii] <= vector[n]);
			} else {
				CHECK(vector[ii] >= vector[n]);
			}
		}
	}
}

TEST_CASE("[SortArray] Nth Element Sawtooth") {
	constexpr int spike = 4;
	constexpr int count = 16;
	constexpr int size = count * (spike * 2 + 1);
	for (int i = 0; i < size; i++) {
		Vector<int> vector;
		vector.reserve_exact(size);
		int n = i;

		// This will create a sawtooth pattern.
		for (int ii = 0; ii < count; ii++) {
			for (int iii = spike; iii >= -spike; iii--) {
				vector.push_back(spike - Math::abs(iii));
			}
		}

		SortArray<int> sort;
		sort.nth_element(0, vector.size(), n, vector.ptrw());

		CHECK(vector.size() == size);
		for (int ii = 0; ii < size; ii++) {
			if (ii <= n) {
				CHECK(vector[ii] <= vector[n]);
			} else {
				CHECK(vector[ii] >= vector[n]);
			}
		}
	}
}

TEST_CASE("[SortArray] Nth Element Random") {
	constexpr int size = 128;
	for (int i = 0; i < size; i++) {
		Vector<int> vector;
		vector.reserve_exact(size);
		int n = i;
		for (int ii = 0; ii < size; ii++) {
			vector.push_back(Math::rand());
		}

		SortArray<int> sort;
		sort.nth_element(0, vector.size(), n, vector.ptrw());

		CHECK(vector.size() == size);
		for (int ii = 0; ii < size; ii++) {
			if (ii <= n) {
				CHECK(vector[ii] <= vector[n]);
			} else {
				CHECK(vector[ii] >= vector[n]);
			}
		}
	}
}

struct MoveCountedSortValue {
	int value = 0;
	static inline int copies = 0;
	static inline int moves = 0;

	MoveCountedSortValue() = default;
	explicit MoveCountedSortValue(int p_value) : value(p_value) {}

	MoveCountedSortValue(const MoveCountedSortValue &p_other) : value(p_other.value) {
		copies++;
	}

	MoveCountedSortValue(MoveCountedSortValue &&p_other) noexcept : value(p_other.value) {
		moves++;
		p_other.value = -1000;
	}

	MoveCountedSortValue &operator=(const MoveCountedSortValue &p_other) {
		value = p_other.value;
		copies++;
		return *this;
	}

	MoveCountedSortValue &operator=(MoveCountedSortValue &&p_other) noexcept {
		value = p_other.value;
		moves++;
		p_other.value = -1000;
		return *this;
	}

	bool operator<(const MoveCountedSortValue &p_other) const {
		return value < p_other.value;
	}

	static void reset_counters() {
		copies = 0;
		moves = 0;
	}
};

TEST_CASE("[SortArray] Move-based insertion avoids copies on small reverse-sorted arrays") {
	MoveCountedSortValue data[16];
	for (int i = 0; i < 16; i++) {
		data[i].value = 15 - i;
	}

	MoveCountedSortValue::reset_counters();
	SortArray<MoveCountedSortValue> sorter;
	sorter.sort(data, 16);

	CHECK(MoveCountedSortValue::copies == 0);
	CHECK(MoveCountedSortValue::moves > 0);
	for (int i = 0; i < 16; i++) {
		CHECK(data[i].value == i);
	}
}

TEST_CASE("[SortArray] Move-based insertion avoids copies on sorted and duplicate values") {
	SortArray<MoveCountedSortValue> sorter;
	for (int pattern = 0; pattern < 2; pattern++) {
		MoveCountedSortValue data[16];
		for (int i = 0; i < 16; i++) {
			data[i].value = pattern == 0 ? i : (15 - i) / 3;
		}
		MoveCountedSortValue::reset_counters();
		sorter.sort(data, 16);
		CHECK(MoveCountedSortValue::copies == 0);
		for (int i = 1; i < 16; i++) {
			CHECK(data[i - 1].value <= data[i].value);
		}
	}
}

TEST_CASE("[SortArray] Move-based insertion preserves value multiplicities over threshold") {
	SortArray<MoveCountedSortValue> sorter;
	for (int size = 1; size <= 64; size++) {
		MoveCountedSortValue data[64];
		int before[17] = {};
		int after[17] = {};
		for (int i = 0; i < size; i++) {
			data[i].value = (i * 37 + size * 5) % 17;
			before[data[i].value]++;
		}
		sorter.sort(data, size);
		for (int i = 0; i < size; i++) {
			CHECK(data[i].value >= 0);
			CHECK(data[i].value < 17);
			after[data[i].value]++;
			if (i > 0) {
				CHECK(data[i - 1].value <= data[i].value);
			}
		}
		for (int i = 0; i < 17; i++) {
			CHECK(before[i] == after[i]);
		}
	}
}

TEST_CASE("[SortArray] Move-based insertion respects sort_range boundaries") {
	MoveCountedSortValue data[12];
	for (int i = 0; i < 12; i++) {
		data[i].value = 11 - i;
	}

	MoveCountedSortValue::reset_counters();
	SortArray<MoveCountedSortValue> sorter;
	sorter.sort_range(2, 10, data);

	CHECK(MoveCountedSortValue::copies == 0);
	CHECK(data[0].value == 11);
	CHECK(data[1].value == 10);
	CHECK(data[10].value == 1);
	CHECK(data[11].value == 0);
	for (int i = 3; i < 10; i++) {
		CHECK(data[i - 1].value <= data[i].value);
	}
}

TEST_CASE("[SortArray] Move-based nth_element maintains partition for short and long arrays") {
	SortArray<MoveCountedSortValue> sorter;
	for (int size : { 3, 7, 16, 17, 32 }) {
		for (int nth : { 0, size / 2, size - 1 }) {
			MoveCountedSortValue data[32];
			for (int i = 0; i < size; i++) {
				data[i].value = (i * 19 + size * 3) % 23;
			}
			sorter.nth_element(0, size, nth, data);
			for (int i = 0; i < size; i++) {
				if (i < nth) {
					CHECK(data[i].value <= data[nth].value);
				} else if (i > nth) {
					CHECK(data[i].value >= data[nth].value);
				}
			}
		}
	}
}


struct TrackedSortValue {
	int key = 0;
	int *copies = nullptr;
	int *moves = nullptr;
	TrackedSortValue() = default;
	TrackedSortValue(int p_key, int *p_copies, int *p_moves) : key(p_key), copies(p_copies), moves(p_moves) {}
	TrackedSortValue(const TrackedSortValue &p) : key(p.key), copies(p.copies), moves(p.moves) {
		if (copies) { ++*copies; }
	}
	TrackedSortValue(TrackedSortValue &&p) noexcept : key(p.key), copies(p.copies), moves(p.moves) {
		if (moves) { ++*moves; }
		p.key = -999;
	}
	TrackedSortValue &operator=(const TrackedSortValue &p) {
		key = p.key;
		copies = p.copies;
		moves = p.moves;
		if (copies) { ++*copies; }
		return *this;
	}
	TrackedSortValue &operator=(TrackedSortValue &&p) noexcept {
		key = p.key;
		copies = p.copies;
		moves = p.moves;
		if (moves) { ++*moves; }
		p.key = -999;
		return *this;
	}
	bool operator<(const TrackedSortValue &p) const { return key < p.key; }
};

TEST_CASE("[SortArray] Insertion sort moves values instead of copying") {
	int copies = 0;
	int moves = 0;
	TrackedSortValue values[] = {
		{ 7, &copies, &moves }, { 6, &copies, &moves },
		{ 5, &copies, &moves }, { 4, &copies, &moves },
		{ 3, &copies, &moves }, { 2, &copies, &moves },
		{ 1, &copies, &moves }, { 0, &copies, &moves }
	};
	SortArray<TrackedSortValue> sort;
	sort.insertion_sort(0, 8, values);
	CHECK_EQ(copies, 0);
	CHECK_GT(moves, 0);
	for (int i = 0; i < 8; ++i) {
		CHECK_EQ(values[i].key, i);
	}
}

TEST_CASE("[SortArray] Insertion sort preserves duplicates and sorted input") {
	int copies = 0;
	int moves = 0;
	TrackedSortValue values[] = {
		{ 2, &copies, &moves }, { 1, &copies, &moves },
		{ 1, &copies, &moves }, { 0, &copies, &moves }
	};
	SortArray<TrackedSortValue> sort;
	sort.insertion_sort(0, 4, values);
	CHECK_EQ(copies, 0);
	CHECK_EQ(values[0].key, 0);
	CHECK_EQ(values[1].key, 1);
	CHECK_EQ(values[2].key, 1);
	CHECK_EQ(values[3].key, 2);

	TrackedSortValue sorted[] = {
		{ -1, &copies, &moves }, { 0, &copies, &moves },
		{ 1, &copies, &moves }, { 2, &copies, &moves }
	};
	copies = 0;
	moves = 0;
	sort.insertion_sort(0, 4, sorted);
	sort.insertion_sort(0, 0, sorted);
	sort.insertion_sort(1, 2, sorted);
	CHECK_EQ(copies, 0);
	for (int i = 0; i < 4; ++i) {
		CHECK_EQ(sorted[i].key, i - 1);
	}
}


TEST_CASE("[SortArray] Heap and heapsort move values without copying") {
	SortArray<MoveCountedSortValue> sorter;
	for (int pattern = 0; pattern < 3; pattern++) {
		MoveCountedSortValue data[96];
		int before[17] = {};
		int after[17] = {};
		for (int i = 0; i < 96; i++) {
			data[i].value = pattern == 0 ? 95 - i : (pattern == 1 ? i : (i * 19) % 17);
			if (pattern == 2) {
				before[data[i].value]++;
			}
		}
		MoveCountedSortValue::reset_counters();
		sorter.make_heap(0, 96, data);
		sorter.sort_heap(0, 96, data);
		CHECK(MoveCountedSortValue::copies == 0);
		CHECK(MoveCountedSortValue::moves > 0);
		for (int i = 0; i < 96; i++) {
			if (i > 0) {
				CHECK(data[i - 1].value <= data[i].value);
			}
			if (pattern == 2) {
				after[data[i].value]++;
			}
		}
		if (pattern == 2) {
			for (int k = 0; k < 17; k++) {
				CHECK(before[k] == after[k]);
			}
		}
	}
}

TEST_CASE("[SortArray] Partial heap sort avoids copies and preserves all values") {
	SortArray<MoveCountedSortValue> sorter;
	MoveCountedSortValue data[96];
	int before[17] = {};
	int after[17] = {};
	for (int i = 0; i < 96; i++) {
		data[i].value = (i * 19 + 11) % 17;
		before[data[i].value]++;
	}
	MoveCountedSortValue::reset_counters();
	sorter.partial_sort(0, 96, 16, data);
	CHECK(MoveCountedSortValue::copies == 0);
	CHECK(MoveCountedSortValue::moves > 0);
	for (int i = 0; i < 96; i++) {
		CHECK(data[i].value >= 0);
		CHECK(data[i].value < 17);
		after[data[i].value]++;
		if (i > 0 && i < 16) {
			CHECK(data[i - 1].value <= data[i].value);
		}
		if (i >= 16) {
			CHECK(data[i].value >= data[15].value);
		}
	}
	for (int key = 0; key < 17; key++) {
		CHECK(before[key] == after[key]);
	}
}

TEST_CASE("[SortArray] Large unbalanced and duplicate partitions match std::sort") {
	SortArray<int> sorter;
	CHECK(sorter.bitlog(0) == 0);
	CHECK(sorter.bitlog(1) == 0);
	CHECK(sorter.bitlog(2) == 1);
	CHECK(sorter.bitlog(3) == 1);
	CHECK(sorter.bitlog(256) == 8);
	CHECK(sorter.bitlog(INT64_C(1) << 40) == 40);

	for (int pattern = 0; pattern < 6; pattern++) {
		std::vector<int> values(8192);
		for (int i = 0; i < int(values.size()); i++) {
			switch (pattern) {
				case 0: values[i] = i; break;
				case 1: values[i] = int(values.size()) - i; break;
				case 2: values[i] = i & 3; break;
				case 3: values[i] = (i < int(values.size()) / 2) ? i : int(values.size()) - i; break;
				case 4: values[i] = (i * 37) % 257; break;
				default: values[i] = (i & 1) ? -1000 : 1000; break;
			}
		}
		std::vector<int> expected = values;
		std::sort(expected.begin(), expected.end());
		sorter.sort(values.data(), values.size());
		CHECK(values == expected);
	}
}

TEST_CASE("[SortArray] Small and large partition boundaries preserve guard values") {
	SortArray<int> sorter;
	for (int length : { 0, 1, 2, 15, 16, 17, 18, 31, 32, 33, 1024, 4096 }) {
		std::vector<int> storage(length + 2);
		storage.front() = -54321;
		storage.back() = 54321;
		for (int i = 0; i < length; i++) {
			storage[i + 1] = ((i * 73) ^ (length * 11)) & 511;
		}
		std::vector<int> expected(storage.begin() + 1, storage.end() - 1);
		std::sort(expected.begin(), expected.end());
		sorter.sort_range(1, length + 1, storage.data());
		CHECK(storage.front() == -54321);
		CHECK(storage.back() == 54321);
		for (int i = 0; i < length; i++) {
			CHECK(storage[i + 1] == expected[i]);
		}
	}
}

} // namespace TestSortArray
