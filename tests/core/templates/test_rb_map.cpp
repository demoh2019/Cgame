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

} // namespace TestRBMap
