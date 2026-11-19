/**************************************************************************/
/*  test_rb_map.cpp                                                       */
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

TEST_FORCE_LINK(test_rb_map)

#include "core/templates/rb_map.h"

#include <cstdint>
#include <map>

namespace TestRBMap {

TEST_CASE("[RBMap] In-order links and values match std::map after mutations") {
	RBMap<int, int> map;
	std::map<int, int> expected;
	uint32_t seed = 0xf92ed137u;
	for (int i = 0; i < 3000; i++) {
		seed = seed * 1664525u + 1013904223u;
		int key = int((seed >> 8) % 1200u) - 600;
		if (i < 700) {
			key = i;
		} else if (i < 1400) {
			key = 700 - i;
		}
		if (i % 11 == 0 && i >= 1400) {
			CHECK(map.erase(key) == (expected.erase(key) != 0));
		} else {
			map.insert(key, i);
			expected[key] = i;
		}
		if (i % 41 == 0) {
			CHECK(map.size() == int(expected.size()));
			const RBMap<int, int>::Element *element = map.front();
			const RBMap<int, int>::Element *previous = nullptr;
			for (const auto &entry : expected) {
				REQUIRE(element != nullptr);
				CHECK(element->key() == entry.first);
				CHECK(element->value() == entry.second);
				CHECK(element->prev() == previous);
				previous = element;
				element = element->next();
			}
			CHECK(element == nullptr);
			CHECK(previous == map.back());
			const RBMap<int, int>::Element *next = nullptr;
			for (auto it = expected.rbegin(); it != expected.rend(); ++it) {
				REQUIRE(previous != nullptr);
				CHECK(previous->key() == it->first);
				CHECK(previous->next() == next);
				next = previous;
				previous = previous->prev();
			}
			CHECK(previous == nullptr);
			CHECK(next == map.front());
		}
	}
}

struct CountedKey {
	int value = 0;
	static inline int comparisons = 0;
	bool operator<(const CountedKey &p_other) const {
		++comparisons;
		return value < p_other.value;
	}
};

TEST_CASE("[RBMap] Leaf insertion avoids redundant parent comparison") {
	RBMap<CountedKey, int> map;
	map.insert({ 20 }, 1);
	CountedKey::comparisons = 0;
	map.insert({ 10 }, 2);
	CHECK(CountedKey::comparisons == 1);
	CountedKey::comparisons = 0;
	map.insert({ 30 }, 3);
	CHECK(CountedKey::comparisons == 2);
	CHECK(map.size() == 3);
	CHECK(map.find({ 20 })->value() == 1);
}


TEST_CASE("[RBMap] find_closest returns greatest equivalent or smaller key") {
	RBMap<int, int> map;
	CHECK(map.find_closest(1) == nullptr);
	for (int key : { 10, 20, 30, 40 }) {
		map.insert(key, key * 3);
	}
	const int queries[] = { -1, 0, 9, 10, 11, 19, 20, 21, 39, 40, 41, 100 };
	const int answers[] = { -1, -1, -1, 10, 10, 10, 20, 20, 30, 40, 40, 40 };
	for (int i = 0; i < 12; i++) {
		const auto *found = map.find_closest(queries[i]);
		if (answers[i] == -1) {
			CHECK(found == nullptr);
		} else {
			REQUIRE(found != nullptr);
			CHECK(found->key() == answers[i]);
		}
	}
	map.erase(20);
	CHECK(map.find_closest(21)->key() == 10);
	map.erase(10);
	CHECK(map.find_closest(21) == nullptr);
}

TEST_CASE("[RBMap] find_closest compares once per visited level") {
	RBMap<CountedKey, int> map;
	for (int i = 0; i < 2048; i++) {
		map.insert({ i * 2 }, i);
	}
	const int depth = map.calculate_depth();
	for (int query = -1; query <= 4100; query += 37) {
		CountedKey::comparisons = 0;
		const auto *found = map.find_closest({ query });
		CHECK(CountedKey::comparisons <= depth + 1);
		if (query < 0) {
			CHECK(found == nullptr);
		} else {
			REQUIRE(found != nullptr);
			CHECK(found->key().value == (query >= 4094 ? 4094 : (query / 2) * 2));
		}
	}
}

TEST_CASE("[RBMap] find_closest matches std::map upper_bound after random mutations") {
	RBMap<int, int> map;
	std::map<int, int> reference;
	uint32_t seed = 0xe52991cdu;
	for (int i = 0; i < 4000; i++) {
		seed = seed * 1664525u + 1013904223u;
		const int value = int((seed >> 8) % 2048u) - 1024;
		if (i % 7 == 0) {
			map.erase(value);
			reference.erase(value);
		} else {
			map.insert(value, i);
			reference[value] = i;
		}
		if ((i & 31) == 0) {
			for (int query = -1200; query <= 1200; query += 53) {
				auto it = reference.upper_bound(query);
				const auto *actual = map.find_closest(query);
				if (it == reference.begin()) {
					CHECK(actual == nullptr);
				} else {
					--it;
					REQUIRE(actual != nullptr);
					CHECK(actual->key() == it->first);
					CHECK(actual->value() == it->second);
				}
			}
		}
	}
}

} // namespace TestRBMap
