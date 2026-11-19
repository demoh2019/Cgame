/**************************************************************************/
/*  test_hash_map.cpp                                                     */
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

TEST_FORCE_LINK(test_hash_map)

#include "core/templates/hash_map.h"

namespace TestHashMap {

TEST_CASE("[HashMap] List initialization") {
	HashMap<int, String> map{ { 0, "A" }, { 1, "B" }, { 2, "C" }, { 3, "D" }, { 4, "E" } };

	CHECK(map.size() == 5);
	CHECK(map[0] == "A");
	CHECK(map[1] == "B");
	CHECK(map[2] == "C");
	CHECK(map[3] == "D");
	CHECK(map[4] == "E");
}

TEST_CASE("[HashMap] List initialization with existing elements") {
	HashMap<int, String> map{ { 0, "A" }, { 0, "B" }, { 0, "C" }, { 0, "D" }, { 0, "E" } };

	CHECK(map.size() == 1);
	CHECK(map[0] == "E");
}

TEST_CASE("[HashMap] Insert element") {
	HashMap<int, int> map;
	HashMap<int, int>::Iterator e = map.insert(42, 84);

	CHECK(e);
	CHECK(e->key == 42);
	CHECK(e->value == 84);
	CHECK(map[42] == 84);
	CHECK(map.has(42));
	CHECK(map.find(42));
}

TEST_CASE("[HashMap] Overwrite element") {
	HashMap<int, int> map;
	map.insert(42, 84);
	map.insert(42, 1234);

	CHECK(map[42] == 1234);
}

TEST_CASE("[HashMap] Erase via element") {
	HashMap<int, int> map;
	HashMap<int, int>::Iterator e = map.insert(42, 84);
	map.remove(e);
	CHECK(!map.has(42));
	CHECK(!map.find(42));
}

TEST_CASE("[HashMap] Erase via key") {
	HashMap<int, int> map;
	map.insert(42, 84);
	map.erase(42);
	CHECK(!map.has(42));
	CHECK(!map.find(42));
}

TEST_CASE("[HashMap] Size") {
	HashMap<int, int> map;
	map.insert(42, 84);
	map.insert(123, 84);
	map.insert(123, 84);
	map.insert(0, 84);
	map.insert(123485, 84);

	CHECK(map.size() == 4);
}

TEST_CASE("[HashMap] Iteration") {
	HashMap<int, int> map;
	map.insert(42, 84);
	map.insert(123, 12385);
	map.insert(0, 12934);
	map.insert(123485, 1238888);
	map.insert(123, 111111);

	Vector<Pair<int, int>> expected;
	expected.push_back(Pair<int, int>(42, 84));
	expected.push_back(Pair<int, int>(123, 111111));
	expected.push_back(Pair<int, int>(0, 12934));
	expected.push_back(Pair<int, int>(123485, 1238888));

	int idx = 0;
	for (const KeyValue<int, int> &E : map) {
		CHECK(expected[idx] == Pair<int, int>(E.key, E.value));
		++idx;
	}
}

TEST_CASE("[HashMap] Const iteration") {
	HashMap<int, int> map;
	map.insert(42, 84);
	map.insert(123, 12385);
	map.insert(0, 12934);
	map.insert(123485, 1238888);
	map.insert(123, 111111);

	const HashMap<int, int> const_map(map);

	Vector<Pair<int, int>> expected;
	expected.push_back(Pair<int, int>(42, 84));
	expected.push_back(Pair<int, int>(123, 111111));
	expected.push_back(Pair<int, int>(0, 12934));
	expected.push_back(Pair<int, int>(123485, 1238888));
	expected.push_back(Pair<int, int>(123, 111111));

	int idx = 0;
	for (const KeyValue<int, int> &E : const_map) {
		CHECK(expected[idx] == Pair<int, int>(E.key, E.value));
		++idx;
	}
}

TEST_CASE("[HashMap] Sort") {
	HashMap<int, int> hashmap;
	int shuffled_ints[]{ 6, 1, 9, 8, 3, 0, 4, 5, 7, 2 };

	for (int i : shuffled_ints) {
		hashmap[i] = i;
	}
	hashmap.sort();

	int i = 0;
	for (const KeyValue<int, int> &kv : hashmap) {
		CHECK_EQ(kv.key, i);
		i++;
	}

	struct ReverseSort {
		bool operator()(const KeyValue<int, int> &p_a, const KeyValue<int, int> &p_b) {
			return p_a.key > p_b.key;
		}
	};
	hashmap.sort_custom<ReverseSort>();

	for (const KeyValue<int, int> &kv : hashmap) {
		i--;
		CHECK_EQ(kv.key, i);
	}
}


TEST_CASE("[AnimationAudioMapFastPath] one bracket lookup creates and reuses a track entry") {
	HashMap<int, Vector<int>> playing;
	Vector<int> &first = playing[42];
	CHECK_EQ(playing.size(), 1);
	CHECK(first.is_empty());
	first.push_back(7);
	Vector<int> &reused = playing[42];
	CHECK(&first == &reused);
	REQUIRE_EQ(reused.size(), 1);
	CHECK_EQ(reused[0], 7);
	CHECK_EQ(playing.size(), 1);
}

TEST_CASE("[AnimationAudioMapFastPath] missing and existing track keys preserve values after erase") {
	HashMap<int, int> playing;
	CHECK(playing.getptr(17) == nullptr);
	playing[17] = 120;
	playing[18] = 240;
	REQUIRE(playing.getptr(17) != nullptr);
	CHECK_EQ(*playing.getptr(17), 120);
	playing.erase(17);
	CHECK(playing.getptr(17) == nullptr);
	CHECK_EQ(playing.size(), 1);
	CHECK_EQ(playing[18], 240);
}


TEST_CASE("[ViewportMaskFastPath] missing mask lookup does not insert a viewport") {
	HashMap<int, uint64_t> masks;
	CHECK(masks.getptr(100) == nullptr);
	CHECK(masks.is_empty());
	const uint64_t *existing = masks.getptr(100);
	const uint64_t mask = existing != nullptr ? *existing : 0;
	CHECK_EQ(mask, uint64_t(0));
	CHECK(masks.is_empty());
}

TEST_CASE("[ViewportMaskFastPath] registered viewport returns the original 64-bit mask") {
	HashMap<int, uint64_t> masks;
	const uint64_t high_bit = uint64_t(1) << 63;
	masks[101] = high_bit;
	const uint64_t *ptr = masks.getptr(101);
	REQUIRE(ptr != nullptr);
	CHECK_EQ(*ptr, high_bit);
	CHECK_EQ(masks.size(), 1);
}

TEST_CASE("[ViewportMaskFastPath] removing viewport releases only its visibility bit") {
	HashMap<int, uint64_t> masks;
	uint64_t used = uint64_t(1) | uint64_t(4) | (uint64_t(1) << 63);
	masks[1] = uint64_t(1);
	masks[2] = uint64_t(4);
	masks[3] = uint64_t(1) << 63;
	const uint64_t *entry = masks.getptr(2);
	REQUIRE(entry != nullptr);
	const uint64_t removed_mask = *entry;
	used &= ~removed_mask;
	masks.erase(2);
	CHECK_EQ(used, uint64_t(1) | (uint64_t(1) << 63));
	CHECK(masks.getptr(2) == nullptr);
	CHECK_EQ(*masks.getptr(1), uint64_t(1));
	CHECK_EQ(*masks.getptr(3), uint64_t(1) << 63);
}

TEST_CASE("[ViewportMaskFastPath] adding a viewport preserves existing mask pointers after lookup") {
	HashMap<int, uint64_t> masks;
	masks[1] = uint64_t(1);
	const uint64_t *mask = masks.getptr(2);
	CHECK(mask == nullptr);
	if (mask == nullptr) {
		masks[2] = uint64_t(2);
		mask = masks.getptr(2);
	}
	REQUIRE(mask != nullptr);
	CHECK_EQ(*mask, uint64_t(2));
	CHECK_EQ(*masks.getptr(1), uint64_t(1));
}

struct CollidingHash {
	static uint32_t hash(int) {
		return 0x13579bdu;
	}
};

TEST_CASE("[HashMap] Clear sparse reserved table handles collision clusters") {
	for (int count : { 1, 8, 16, 17 }) {
		HashMap<int, int, CollidingHash> map;
		map.reserve(16384);
		const uint32_t capacity = map.get_capacity();
		for (int i = 0; i < count; i++) {
			map.insert(i, i + 100);
		}
		CHECK(map.size() == uint32_t(count));
		for (int i = 0; i < count; i++) {
			CHECK(map.has(i));
			CHECK(map.get(i) == i + 100);
		}

		map.clear();
		CHECK(map.is_empty());
		CHECK(map.get_capacity() == capacity);
		CHECK(!map.begin());
		for (int i = 0; i < count; i++) {
			CHECK(!map.has(i));
			CHECK(map.getptr(i) == nullptr);
		}

		// A reused table must not retain stale probe chains.
		for (int i = 0; i < count; i++) {
			map.insert(i + 1000, i + 10);
		}
		for (int i = 0; i < count; i++) {
			CHECK(map.get(i + 1000) == i + 10);
		}
		map.clear();
		CHECK(map.is_empty());
	}
}

} // namespace TestHashMap
