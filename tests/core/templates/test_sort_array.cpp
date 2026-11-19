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

#include <string>
#include <utility>

#include <memory>

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

struct MoveTrackedValue {
	int key = 0;
	int original_index = 0;
	std::string payload;
	static inline int copies = 0;
	static inline int moves = 0;

	MoveTrackedValue() = default;
	MoveTrackedValue(int p_key, int p_index = 0) :
			key(p_key), original_index(p_index), payload(256, char('a' + p_key % 26)) {}
	MoveTrackedValue(const MoveTrackedValue &p_other) :
			key(p_other.key), original_index(p_other.original_index), payload(p_other.payload) {
		copies++;
	}
	MoveTrackedValue(MoveTrackedValue &&p_other) noexcept :
			key(p_other.key), original_index(p_other.original_index), payload(std::move(p_other.payload)) {
		moves++;
	}
	MoveTrackedValue &operator=(const MoveTrackedValue &p_other) {
		key = p_other.key;
		original_index = p_other.original_index;
		payload = p_other.payload;
		copies++;
		return *this;
	}
	MoveTrackedValue &operator=(MoveTrackedValue &&p_other) noexcept {
		key = p_other.key;
		original_index = p_other.original_index;
		payload = std::move(p_other.payload);
		moves++;
		return *this;
	}
	bool operator<(const MoveTrackedValue &p_other) const {
		return key < p_other.key;
	}
};

struct MoveTrackedDescending {
	bool operator()(const MoveTrackedValue &p_left, const MoveTrackedValue &p_right) const {
		return p_left.key > p_right.key;
	}
};

TEST_CASE("[SortArray] Empty and single-element ranges") {
	SortArray<int> sort;
	sort.sort(nullptr, 0);
	int value = 42;
	sort.sort(&value, 1);
	CHECK(value == 42);
}

TEST_CASE("[SortArray] Insertion sort avoids string copies on reverse data") {
	MoveTrackedValue values[] = { { 9 }, { 8 }, { 7 }, { 6 }, { 5 }, { 4 }, { 3 }, { 2 }, { 1 }, { 0 } };
	MoveTrackedValue::copies = 0;
	MoveTrackedValue::moves = 0;
	SortArray<MoveTrackedValue>().sort(values, 10);
	CHECK(MoveTrackedValue::copies == 0);
	CHECK(MoveTrackedValue::moves > 0);
	for (int i = 0; i < 10; i++) {
		CHECK(values[i].key == i);
		CHECK(values[i].payload == std::string(256, char('a' + i % 26)));
	}
}

TEST_CASE("[SortArray] Insertion sort avoids copies on sorted data") {
	MoveTrackedValue values[] = { { 0 }, { 1 }, { 2 }, { 3 }, { 4 }, { 5 }, { 6 }, { 7 }, { 8 }, { 9 } };
	MoveTrackedValue::copies = 0;
	MoveTrackedValue::moves = 0;
	SortArray<MoveTrackedValue>().sort(values, 10);
	CHECK(MoveTrackedValue::copies == 0);
	for (int i = 0; i < 10; i++) {
		CHECK(values[i].key == i);
	}
}

TEST_CASE("[SortArray] Insertion sort preserves duplicate ordering") {
	MoveTrackedValue values[] = { { 2, 0 }, { 1, 1 }, { 2, 2 }, { 1, 3 }, { 3, 4 }, { 1, 5 }, { 2, 6 } };
	MoveTrackedValue::copies = 0;
	SortArray<MoveTrackedValue>().sort(values, 7);
	CHECK(MoveTrackedValue::copies == 0);
	const int expected_keys[] = { 1, 1, 1, 2, 2, 2, 3 };
	const int expected_indices[] = { 1, 3, 5, 0, 2, 6, 4 };
	for (int i = 0; i < 7; i++) {
		CHECK(values[i].key == expected_keys[i]);
		CHECK(values[i].original_index == expected_indices[i]);
	}
}

TEST_CASE("[SortArray] Insertion sort respects range boundaries") {
	MoveTrackedValue values[] = { { 22 }, { 21 }, { 8 }, { 7 }, { 6 }, { 5 }, { 4 }, { 3 }, { 2 }, { 1 }, { 20 } };
	MoveTrackedValue::copies = 0;
	SortArray<MoveTrackedValue>().sort_range(2, 10, values);
	CHECK(MoveTrackedValue::copies == 0);
	CHECK(values[0].key == 22);
	CHECK(values[1].key == 21);
	CHECK(values[10].key == 20);
	for (int i = 2; i < 10; i++) {
		CHECK(values[i].key == i - 1);
	}
}

TEST_CASE("[SortArray] Threshold and introsort boundary preserve payloads") {
	for (int count : { 15, 16, 17, 33 }) {
		MoveTrackedValue values[33];
		for (int i = 0; i < count; i++) {
			values[i] = MoveTrackedValue(count - i - 1);
		}
		MoveTrackedValue::copies = 0;
		SortArray<MoveTrackedValue>().sort(values, count);
		if (count <= 16) {
			CHECK(MoveTrackedValue::copies == 0);
		}
		for (int i = 0; i < count; i++) {
			CHECK(values[i].key == i);
			CHECK(values[i].payload == std::string(256, char('a' + i % 26)));
		}
	}
}

TEST_CASE("[SortArray] Custom descending comparator remains correct") {
	MoveTrackedValue values[] = { { 3 }, { 1 }, { 2 }, { 4 }, { 0 } };
	MoveTrackedValue::copies = 0;
	SortArray<MoveTrackedValue, MoveTrackedDescending>().sort(values, 5);
	CHECK(MoveTrackedValue::copies == 0);
	for (int i = 0; i < 5; i++) {
		CHECK(values[i].key == 4 - i);
	}
}

TEST_CASE("[SortArray] Exhaustive short duplicate sequences") {
	SortArray<MoveTrackedValue> sort;
	for (int length = 0; length <= 7; length++) {
		int sequences = 1;
		for (int i = 0; i < length; i++) {
			sequences *= 3;
		}
		for (int mask = 0; mask < sequences; mask++) {
			MoveTrackedValue values[7];
			int key_counts[3] = { 0, 0, 0 };
			int encoded = mask;
			for (int i = 0; i < length; i++) {
				int key = encoded % 3;
				encoded /= 3;
				values[i] = MoveTrackedValue(key, i);
				key_counts[key]++;
			}
			MoveTrackedValue::copies = 0;
			sort.sort(values, length);
			CHECK(MoveTrackedValue::copies == 0);
			int position = 0;
			for (int key = 0; key < 3; key++) {
				for (int i = 0; i < key_counts[key]; i++) {
					CHECK(values[position++].key == key);
				}
			}
		}
	}
}

} // namespace TestSortArray
