/**************************************************************************/
/*  test_lru.cpp                                                          */
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

TEST_FORCE_LINK(test_lru)

#include "core/templates/lru.h"

namespace TestLRU {

TEST_CASE("[LRU] Store and read") {
	LRUCache<int, int> lru;

	lru.set_capacity(3);
	lru.insert(1, 1);
	lru.insert(50, 2);
	lru.insert(100, 5);

	CHECK(lru.has(1));
	CHECK(lru.has(50));
	CHECK(lru.has(100));
	CHECK(!lru.has(200));

	CHECK(lru.get(1) == 1);
	CHECK(lru.get(50) == 2);
	CHECK(lru.get(100) == 5);

	CHECK(lru.getptr(1) != nullptr);
	CHECK(lru.getptr(1000) == nullptr);

	lru.insert(600, 600); // Erase <50>
	CHECK(lru.has(600));
	CHECK(!lru.has(50));
}

TEST_CASE("[LRU] Resize and clear") {
	LRUCache<int, int> lru;

	lru.set_capacity(3);
	lru.insert(1, 1);
	lru.insert(2, 2);
	lru.insert(3, 3);

	CHECK(lru.get_capacity() == 3);

	lru.set_capacity(5);
	CHECK(lru.get_capacity() == 5);

	CHECK(lru.has(1));
	CHECK(lru.has(2));
	CHECK(lru.has(3));
	CHECK(!lru.has(4));

	lru.set_capacity(2);
	CHECK(lru.get_capacity() == 2);

	CHECK(!lru.has(1));
	CHECK(lru.has(2));
	CHECK(lru.has(3));
	CHECK(!lru.has(4));

	lru.clear();
	CHECK(!lru.has(1));
	CHECK(!lru.has(2));
	CHECK(!lru.has(3));
	CHECK(!lru.has(4));
}


static int replacement_eviction_count = 0;
static int replacement_evicted_value = 0;

static void on_replacement_eviction(const int &p_key, int &p_value) {
	++replacement_eviction_count;
	replacement_evicted_value = p_value;
	p_value = -42;
}

TEST_CASE("[LRU] Repeated insert reuses the existing node and remains most recent") {
	LRUCache<int, int> lru(2);
	const auto first = lru.insert(1, 10);
	lru.insert(2, 20);
	const auto replacement = lru.insert(1, 11);
	CHECK(first == replacement);
	CHECK(lru.get_size() == 2);
	CHECK(lru.get(1) == 11);
	lru.insert(3, 30);
	CHECK(lru.has(1));
	CHECK(!lru.has(2));
	CHECK(lru.has(3));

	for (int i = 0; i < 100; i++) {
		CHECK(lru.insert(1, i)->value == i);
	}
	CHECK(lru.get_size() == 2);
}

TEST_CASE("[LRU] Replacement hook observes the old value once") {
	replacement_eviction_count = 0;
	replacement_evicted_value = 0;
	LRUCache<int, int, HashMapHasherDefault, HashMapComparatorDefault<int>, on_replacement_eviction> lru(2);
	lru.insert(1, 30);
	const auto replacement = lru.insert(1, 50);
	CHECK(replacement_eviction_count == 1);
	CHECK(replacement_evicted_value == 30);
	CHECK(replacement->value == 50);
	CHECK(lru.get_size() == 1);
}

TEST_CASE("[LRU] Aliased replacement survives an eviction hook") {
	replacement_eviction_count = 0;
	LRUCache<int, int, HashMapHasherDefault, HashMapComparatorDefault<int>, on_replacement_eviction> lru(2);
	lru.insert(7, 77);
	const int &value = lru.get(7);
	const auto replacement = lru.insert(7, value);
	CHECK(replacement->value == 77);
	CHECK(replacement_eviction_count == 1);
	CHECK(replacement_evicted_value == 77);
}

TEST_CASE("[HashMap] Renew key preserves value addresses and insertion order") {
	HashMap<int, int> map;
	map.insert(1, 10);
	map.insert(2, 20);
	map.insert(3, 30);

	int *first = map.getptr(1);
	REQUIRE(first != nullptr);
	CHECK(map.renew_key(99) == nullptr);
	CHECK(map.renew_key(1) == first);
	REQUIRE_EQ(map.size(), 3);

	int expected[] = { 2, 3, 1 };
	int index = 0;
	for (const KeyValue<int, int> &entry : map) {
		REQUIRE(index < 3);
		CHECK_EQ(entry.key, expected[index++]);
	}
	CHECK_EQ(index, 3);
	CHECK(map.renew_key(1) == first);
	CHECK_EQ(map.last()->key, 1);
	CHECK(map.erase(2));
	CHECK(map.renew_key(3) != nullptr);
	CHECK_EQ(map.begin()->key, 1);
	CHECK_EQ(map.last()->key, 3);
}

TEST_CASE("[LRU] Single-map cache preserves recency, pointer stability, and eviction") {
	LRUCache<int, int> cache(16);
	for (int i = 0; i < 256; i++) {
		cache.insert(i, i * 7);
	}
	REQUIRE_EQ(cache.get_size(), 16);
	for (int i = 0; i < 240; i++) {
		CHECK_FALSE(cache.has(i));
	}
	for (int i = 240; i < 256; i++) {
		CHECK(cache.has(i));
		CHECK_EQ(cache.get(i), i * 7);
	}

	const int *original = cache.getptr(255);
	REQUIRE(original != nullptr);
	const auto first_entry = cache.insert(255, 999);
	const auto replaced = cache.insert(255, 1000);
	CHECK(first_entry == replaced);
	CHECK(cache.getptr(255) == original);
	CHECK_EQ(*original, 1000);
	for (int i = 0; i < 1024; i++) {
		cache.insert(255, i);
	}
	CHECK_EQ(cache.get_size(), 16);
	CHECK(cache.getptr(255) == original);
	CHECK_EQ(cache.get(255), 1023);

	cache.set_capacity(4);
	CHECK_EQ(cache.get_size(), 4);
	CHECK(cache.has(255));
	cache.clear();
	CHECK_EQ(cache.get_size(), 0);
	CHECK_FALSE(cache.has(255));
}

struct CountingLRUHasher {
	static inline int calls = 0;
	static uint32_t hash(const int &p_key) {
		calls++;
		return HashMapHasherDefault::hash(p_key);
	}
};

TEST_CASE("[LRU] Zero-capacity cache avoids hashing and transient entries") {
	CountingLRUHasher::calls = 0;
	LRUCache<int, int, CountingLRUHasher> cache(0);
	CHECK(cache.get_capacity() == 0);
	for (int i = 0; i < 2048; i++) {
		CHECK_FALSE(cache.insert(i, i * 3));
	}
	CHECK(cache.get_size() == 0);
	CHECK(CountingLRUHasher::calls == 0);

	cache.set_capacity(3);
	CHECK(cache.get_capacity() == 3);
	cache.insert(10, 100);
	cache.insert(11, 110);
	CHECK(cache.get_size() == 2);
	CHECK(CountingLRUHasher::calls > 0);
	cache.set_capacity(0);
	CHECK(cache.get_size() == 0);
	CHECK(cache.get_capacity() == 0);
	const int calls_before = CountingLRUHasher::calls;
	for (int i = 0; i < 256; i++) {
		CHECK_FALSE(cache.insert(i, i));
	}
	CHECK(cache.get_size() == 0);
	CHECK(CountingLRUHasher::calls == calls_before);
}

static int disabled_cache_evictions = 0;
static void on_disabled_cache_evict(const int &, int &p_value) {
	disabled_cache_evictions++;
	p_value = -1;
}

TEST_CASE("[LRU] Hook-enabled zero-capacity cache still invokes eviction") {
	disabled_cache_evictions = 0;
	LRUCache<int, int, HashMapHasherDefault, HashMapComparatorDefault<int>, on_disabled_cache_evict> cache(0);
	CHECK_FALSE(cache.insert(5, 50));
	CHECK(cache.get_size() == 0);
	CHECK(disabled_cache_evictions == 1);
	CHECK_FALSE(cache.insert(6, 60));
	CHECK(cache.get_size() == 0);
	CHECK(disabled_cache_evictions == 2);
	cache.set_capacity(1);
	cache.insert(7, 70);
	CHECK(cache.get_size() == 1);
	cache.insert(8, 80);
	CHECK(disabled_cache_evictions == 3);
	CHECK(cache.has(8));
	CHECK_FALSE(cache.has(7));
}

} // namespace TestLRU
