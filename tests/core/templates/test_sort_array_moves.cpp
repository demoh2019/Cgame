/**************************************************************************/
/*  test_sort_array_moves.cpp                                                   */
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

TEST_FORCE_LINK(test_sort_array_moves)

#include "core/templates/sort_array.h"

#include <string>
#include <utility>

namespace TestSortArrayMoves {

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

TEST_CASE("[SortArrayMoves] Empty and single-element ranges") {
	SortArray<int> sort;
	sort.sort(nullptr, 0);
	int value = 42;
	sort.sort(&value, 1);
	CHECK(value == 42);
}

TEST_CASE("[SortArrayMoves] Insertion sort avoids string copies on reverse data") {
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

TEST_CASE("[SortArrayMoves] Insertion sort avoids copies on sorted data") {
	MoveTrackedValue values[] = { { 0 }, { 1 }, { 2 }, { 3 }, { 4 }, { 5 }, { 6 }, { 7 }, { 8 }, { 9 } };
	MoveTrackedValue::copies = 0;
	MoveTrackedValue::moves = 0;
	SortArray<MoveTrackedValue>().sort(values, 10);
	CHECK(MoveTrackedValue::copies == 0);
	for (int i = 0; i < 10; i++) {
		CHECK(values[i].key == i);
	}
}

TEST_CASE("[SortArrayMoves] Insertion sort preserves duplicate ordering") {
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

TEST_CASE("[SortArrayMoves] Insertion sort respects range boundaries") {
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

TEST_CASE("[SortArrayMoves] Threshold and introsort boundary preserve payloads") {
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

TEST_CASE("[SortArrayMoves] Custom descending comparator remains correct") {
	MoveTrackedValue values[] = { { 3 }, { 1 }, { 2 }, { 4 }, { 0 } };
	MoveTrackedValue::copies = 0;
	SortArray<MoveTrackedValue, MoveTrackedDescending>().sort(values, 5);
	CHECK(MoveTrackedValue::copies == 0);
	for (int i = 0; i < 5; i++) {
		CHECK(values[i].key == 4 - i);
	}
}

TEST_CASE("[SortArrayMoves] Exhaustive short duplicate sequences") {
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

} // namespace TestSortArrayMoves
