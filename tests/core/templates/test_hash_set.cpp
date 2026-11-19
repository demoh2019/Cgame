/**************************************************************************/
/*  test_hash_set.cpp                                                     */
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

TEST_FORCE_LINK(test_hash_set)

#include "core/templates/hash_set.h"

namespace TestHashSet {

struct CountingHasher {
	static inline uint32_t calls = 0;

	static uint32_t hash(const int &p_key) {
		++calls;
		// Exercise the EMPTY_HASH normalization as well as the ordinary path.
		return p_key == 0 ? 0 : HashMapHasherDefault::hash(p_key);
	}
};

struct ClusteredHasher {
	static uint32_t hash(const int &p_key) {
		// Force long probe chains, including keys whose hash is zero.
		return uint32_t(p_key % 4);
	}
};

TEST_CASE("[HashSet] Insert hashes new and existing keys only once") {
	HashSet<int, CountingHasher> set;

	CountingHasher::calls = 0;
	set.insert(0);
	CHECK_EQ(CountingHasher::calls, 1);
	CHECK_EQ(set.size(), 1);

	CountingHasher::calls = 0;
	set.insert(0);
	CHECK_EQ(CountingHasher::calls, 1);
	CHECK_EQ(set.size(), 1);

	CountingHasher::calls = 0;
	for (int i = 1; i <= 256; i++) {
		set.insert(i);
	}
	// Growing / rehashing must use saved hashes, not rehash existing keys.
	CHECK_EQ(CountingHasher::calls, 256);
	CHECK_EQ(set.size(), 257);

	for (int i = 0; i <= 256; i++) {
		CHECK(set.has(i));
	}
}

TEST_CASE("[HashSet] Colliding keys survive wraparound and repeated erases") {
	HashSet<int, ClusteredHasher> set;
	for (int i = 0; i < 160; i++) {
		set.insert(i);
	}
	for (int i = 0; i < 160; i += 3) {
		CHECK(set.erase(i));
	}
	for (int i = 0; i < 160; i++) {
		CHECK(set.has(i) == (i % 3 != 0));
	}
	for (int i = 0; i < 160; i += 3) {
		set.insert(i);
	}
	CHECK_EQ(set.size(), 160);
	for (int i = 0; i < 160; i++) {
		CHECK(set.has(i));
	}
}

TEST_CASE("[HashSet] Growing a cleared set reuses empty hash storage") {
	HashSet<int, CountingHasher> set;
	for (int i = 0; i < 64; i++) {
		set.insert(i);
	}
	set.clear();
	CHECK(set.is_empty());
	const uint32_t previous_capacity = set.get_capacity();
	CountingHasher::calls = 0;
	set.reserve(8192);
	CHECK(set.get_capacity() > previous_capacity);
	CHECK(CountingHasher::calls == 0);
	set.reserve(32768);
	CHECK(set.get_capacity() >= 32768);
	CHECK(set.is_empty());

	// A growth after clear must initialize all newly available hash
	// slots, even when the allocator returns uninitialized memory.
	for (int i = 0; i < 512; i++) {
		set.insert(i * 17 + 1000);
	}
	CHECK(set.size() == 512);
	for (int i = 0; i < 512; i++) {
		CHECK(set.has(i * 17 + 1000));
	}
	for (int i = 0; i < 512; i += 2) {
		CHECK(set.erase(i * 17 + 1000));
	}
	CHECK(set.size() == 256);
	set.clear();
	CHECK(set.is_empty());
	set.reserve(65536);
	for (int i = 0; i < 512; i++) {
		CHECK_FALSE(set.has(i * 17 + 1000));
	}
	for (int i = 0; i < 128; i++) {
		set.insert(i + 200000);
	}
	for (int i = 0; i < 128; i++) {
		CHECK(set.has(i + 200000));
	}
}

TEST_CASE("[HashSet] Sparse clear reuses reserved table without stale keys") {
	HashSet<int> set;
	set.reserve(49157);
	const uint32_t reserved_capacity = set.get_capacity();

	for (int cycle = 0; cycle < 8; cycle++) {
		const int first = cycle * 10000;
		for (int i = 0; i < 96; i++) {
			set.insert(first + i);
		}
		for (int i = 0; i < 96; i += 3) {
			CHECK(set.erase(first + i));
		}
		CHECK_EQ(set.size(), 64);

		// Deleting keys also relocates the last key. Clearing must follow
		// the current index mappings, not the original insertion order.
		set.clear();
		CHECK(set.is_empty());
		CHECK_EQ(set.get_capacity(), reserved_capacity);
		for (int i = 0; i < 96; i++) {
			CHECK_FALSE(set.has(first + i));
		}
	}

	// This crosses the sparse-clear threshold and exercises the memset path.
	for (int i = 0; i < 2048; i++) {
		set.insert(i);
	}
	CHECK_EQ(set.size(), 2048);
	set.clear();
	CHECK(set.is_empty());
	CHECK_EQ(set.get_capacity(), reserved_capacity);
	for (int i = 0; i < 2048; i++) {
		CHECK_FALSE(set.has(i));
		set.insert(i + 50000);
	}
	CHECK_EQ(set.size(), 2048);
	for (int i = 0; i < 2048; i++) {
		CHECK(set.has(i + 50000));
	}
}

TEST_CASE("[HashSet] Sparse clear handles collided and relocated hash slots") {
	HashSet<int, ClusteredHasher> set;
	set.reserve(3079);
	const uint32_t original_capacity = set.get_capacity();
	for (int i = 0; i < 40; i++) {
		set.insert(i);
	}
	for (int i = 0; i < 40; i += 4) {
		CHECK(set.erase(i));
	}
	CHECK_EQ(set.size(), 30);
	set.clear();
	CHECK(set.is_empty());
	CHECK_EQ(set.get_capacity(), original_capacity);
	for (int i = 0; i < 40; i++) {
		CHECK_FALSE(set.has(i));
	}
	for (int i = 40; i < 80; i++) {
		set.insert(i);
	}
	CHECK_EQ(set.size(), 40);
	for (int i = 40; i < 80; i++) {
		CHECK(set.has(i));
	}
}

TEST_CASE("[HashSet] Sparse clear releases String keys without leaks") {
	const uint64_t before = Memory::get_mem_usage();
	{
		HashSet<String> set;
		set.reserve(12289);
		for (int cycle = 0; cycle < 3; cycle++) {
			for (int i = 0; i < 32; i++) {
				set.insert("long_key_" + itos(i) + String("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"));
			}
			set.clear();
		}
	}
	CHECK_EQ(Memory::get_mem_usage(), before);
}

TEST_CASE("[HashSet] List initialization") {
	HashSet<int> set{ 0, 1, 2, 3, 4 };

	CHECK(set.size() == 5);
	CHECK(set.has(0));
	CHECK(set.has(1));
	CHECK(set.has(2));
	CHECK(set.has(3));
	CHECK(set.has(4));
}

TEST_CASE("[HashSet] List initialization with existing elements") {
	HashSet<int> set{ 0, 0, 0, 0, 0 };

	CHECK(set.size() == 1);
	CHECK(set.has(0));
}

TEST_CASE("[HashSet] Insert element") {
	HashSet<int> set;
	HashSet<int>::Iterator e = set.insert(42);

	CHECK(e);
	CHECK(*e == 42);
	CHECK(set.has(42));
	CHECK(set.find(42));
	set.reset();
}

TEST_CASE("[HashSet] Insert existing element") {
	HashSet<int> set;
	set.insert(42);
	set.insert(42);

	CHECK(set.has(42));
	CHECK(set.size() == 1);
}

TEST_CASE("[HashSet] Insert, iterate and remove many elements") {
	const int elem_max = 12343;
	HashSet<int> set;
	for (int i = 0; i < elem_max; i++) {
		set.insert(i);
	}

	//insert order should have been kept
	int idx = 0;
	for (const int &K : set) {
		CHECK(idx == K);
		CHECK(set.has(idx));
		idx++;
	}

	Vector<int> elems_still_valid;

	for (int i = 0; i < elem_max; i++) {
		if ((i % 5) == 0) {
			set.erase(i);
		} else {
			elems_still_valid.push_back(i);
		}
	}

	CHECK(elems_still_valid.size() == set.size());

	for (int i = 0; i < elems_still_valid.size(); i++) {
		CHECK(set.has(elems_still_valid[i]));
	}
}

TEST_CASE("[HashSet] Insert, iterate and remove many strings") {
	// This tests a key that uses allocation, to see if any leaks occur

	uint64_t pre_mem = Memory::get_mem_usage();
	const int elem_max = 4018;
	HashSet<String> set;
	for (int i = 0; i < elem_max; i++) {
		set.insert(itos(i));
	}

	//insert order should have been kept
	int idx = 0;
	for (const String &K : set) {
		CHECK(itos(idx) == K);
		CHECK(set.has(itos(idx)));
		idx++;
	}

	Vector<String> elems_still_valid;

	for (int i = 0; i < elem_max; i++) {
		if ((i % 5) == 0) {
			set.erase(itos(i));
		} else {
			elems_still_valid.push_back(itos(i));
		}
	}

	CHECK(elems_still_valid.size() == set.size());

	for (int i = 0; i < elems_still_valid.size(); i++) {
		CHECK(set.has(elems_still_valid[i]));
	}

	elems_still_valid.clear();
	set.reset();

	CHECK(Memory::get_mem_usage() == pre_mem);
}

TEST_CASE("[HashSet] Erase via element") {
	HashSet<int> set;
	HashSet<int>::Iterator e = set.insert(42);
	set.remove(e);
	CHECK(!set.has(42));
	CHECK(!set.find(42));
}

TEST_CASE("[HashSet] Erase via key") {
	HashSet<int> set;
	set.insert(42);
	set.insert(49);
	set.erase(42);
	CHECK(!set.has(42));
	CHECK(!set.find(42));
}

TEST_CASE("[HashSet] Insert and erase half elements") {
	HashSet<int> set;
	set.insert(1);
	set.insert(2);
	set.insert(3);
	set.insert(4);
	set.erase(1);
	set.erase(3);

	CHECK(set.size() == 2);
	CHECK(set.has(2));
	CHECK(set.has(4));
}

TEST_CASE("[HashSet] Size") {
	HashSet<int> set;
	set.insert(42);
	set.insert(123);
	set.insert(123);
	set.insert(0);
	set.insert(123485);

	CHECK(set.size() == 4);
}

TEST_CASE("[HashSet] Iteration") {
	HashSet<int> set;
	set.insert(42);
	set.insert(123);
	set.insert(0);
	set.insert(123485);

	Vector<int> expected;
	expected.push_back(42);
	expected.push_back(123);
	expected.push_back(0);
	expected.push_back(123485);

	int idx = 0;
	for (const int &E : set) {
		CHECK(expected[idx] == E);
		++idx;
	}
}

TEST_CASE("[HashSet] Copy") {
	HashSet<int> set;
	set.insert(42);
	set.insert(123);
	set.insert(0);
	set.insert(123485);

	Vector<int> expected;
	expected.push_back(42);
	expected.push_back(123);
	expected.push_back(0);
	expected.push_back(123485);

	HashSet<int> copy_assign;
	copy_assign = set;

	int idx = 0;
	for (const int &E : copy_assign) {
		CHECK(expected[idx] == E);
		++idx;
	}

	HashSet<int> copy_construct(set);

	idx = 0;
	for (const int &E : copy_construct) {
		CHECK(expected[idx] == E);
		++idx;
	}
}

TEST_CASE("[HashSet] Equality") {
	// Empty sets.
	CHECK(HashSet<int>{} == HashSet<int>{});
	CHECK(HashSet<int>{} != HashSet<int>{ 1, 2, 3 });
	CHECK(HashSet<int>{ 1, 2, 3 } != HashSet<int>{});

	// Different length.
	CHECK(HashSet<int>{ 1, 2, 3 } != HashSet<int>{ 1, 2, 3, 4 });
	CHECK(HashSet<int>{ 1, 2, 3, 4 } != HashSet<int>{ 4, 3, 2 });

	// Same length.
	CHECK(HashSet<int>{ 1, 2, 3 } == HashSet<int>{ 1, 2, 3 });
	CHECK(HashSet<int>{ 1, 2, 3 } == HashSet<int>{ 3, 2, 1 });
	CHECK(HashSet<int>{ 1, 2, 3 } != HashSet<int>{ 1, 2, 8 });
}


TEST_CASE("[HashSet] Relocating last string on middle erase preserves ownership") {
	HashSet<String> set;
	for (int i = 0; i < 160; i++) {
		set.insert("entry_" + itos(i) + String("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
	}
	CHECK(set.erase("entry_4" + String("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")));
	CHECK(set.size() == 159);
	CHECK_FALSE(set.has("entry_4" + String("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")));
	CHECK(set.has("entry_159" + String("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")));
	CHECK(set.has("entry_0" + String("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")));
}

TEST_CASE("[HashSet] Relocation after erase retains all unrelated values") {
	HashSet<int> set;
	for (int i = 0; i < 300; i++) {
		set.insert(i);
	}
	for (int i = 0; i < 300; i += 3) {
		CHECK(set.erase(i));
	}
	CHECK(set.size() == 200);
	for (int i = 0; i < 300; i++) {
		CHECK(set.has(i) == (i % 3 != 0));
	}
}

TEST_CASE("[HashSet] Erase last key and erase middle key both work") {
	HashSet<int> set;
	set.insert(1);
	set.insert(2);
	set.insert(3);
	CHECK(set.erase(3));
	CHECK(set.erase(1));
	CHECK(set.size() == 1);
	CHECK(set.has(2));
	CHECK(set.erase(2));
	CHECK(set.is_empty());
}

TEST_CASE("[HashSet] Alternating insert and erase retains lookup correctness") {
	HashSet<int> set;
	bool present[257] = {};
	uint32_t state = 0x12345678;
	for (int i = 0; i < 15000; i++) {
		state = 1664525U * state + 1013904223U;
		int key = state % 257;
		if ((state & 0x100U) != 0) {
			set.insert(key);
			present[key] = true;
		} else {
			set.erase(key);
			present[key] = false;
		}
		if ((i % 257) == 0) {
			uint32_t expected_size = 0;
			for (int j = 0; j < 257; j++) {
				CHECK(set.has(j) == present[j]);
				expected_size += present[j] ? 1 : 0;
			}
			CHECK(set.size() == expected_size);
		}
	}
}

TEST_CASE("[HashSet] Erase while entries contain heap-backed strings") {
	uint64_t start_usage = Memory::get_mem_usage();
	{
		HashSet<String> set;
		for (int round = 0; round < 4; round++) {
			for (int i = 0; i < 512; i++) {
				set.insert("large key " + itos(i) + String("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"));
			}
			for (int i = 0; i < 512; i += 2) {
				CHECK(set.erase("large key " + itos(i) + String("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")));
			}
			for (int i = 1; i < 512; i += 2) {
				CHECK(set.has("large key " + itos(i) + String("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")));
			}
			set.clear();
		}
	}
	CHECK(Memory::get_mem_usage() == start_usage);
}

TEST_CASE("[HashSet] Iteration after interleaved relocation visits each retained key") {
	HashSet<int> set;
	for (int i = 0; i < 128; i++) {
		set.insert(i);
	}
	for (int i = 0; i < 128; i += 2) {
		set.erase(i);
	}
	bool encountered[128] = {};
	int count = 0;
	for (int key : set) {
		CHECK(key % 2 == 1);
		CHECK_FALSE(encountered[key]);
		encountered[key] = true;
		count++;
	}
	CHECK(count == 64);
	for (int i = 1; i < 128; i += 2) {
		CHECK(encountered[i]);
	}
}

} // namespace TestHashSet
