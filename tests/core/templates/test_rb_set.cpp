/**************************************************************************/
/*  test_rb_set.cpp                                                       */
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
/* MERCHANTABILITY, FITNESS OR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_rb_set)

#include "core/templates/rb_set.h"

#include <cstdint>
#include <set>

namespace TestRBSet {

TEST_CASE("[RBSet] lower_bound returns first equivalent or greater key") {
	RBSet<int> set;
	CHECK(set.lower_bound(0) == nullptr);
	for (int value : { 10, 20, 30, 40 }) {
		set.insert(value);
	}
	const int queries[] = { -3, 0, 10, 11, 19, 20, 21, 39, 40, 41, 100 };
	const int answers[] = { 10, 10, 10, 20, 20, 20, 30, 40, 40, -1, -1 };
	for (int i = 0; i < 11; ++i) {
		const RBSet<int>::Element *actual = set.lower_bound(queries[i]);
		if (answers[i] == -1) {
			CHECK(actual == nullptr);
		} else {
			REQUIRE(actual != nullptr);
			CHECK(actual->get() == answers[i]);
		}
	}
	CHECK(set.erase(20));
	CHECK(set.lower_bound(19)->get() == 30);
	CHECK(set.erase(40));
	CHECK(set.lower_bound(31) == nullptr);
	CHECK(set.erase(10));
	CHECK(set.erase(30));
	CHECK(set.lower_bound(0) == nullptr);
}

struct DecadeKey {
	int value = 0;
	bool operator<(const DecadeKey &p_other) const {
		return value / 10 < p_other.value / 10;
	}
};

TEST_CASE("[RBSet] lower_bound honors strict weak ordering equivalence") {
	RBSet<DecadeKey> set;
	set.insert({ 12 });
	set.insert({ 19 });
	set.insert({ 25 });
	CHECK(set.size() == 2);
	CHECK(set.lower_bound({ 11 })->get().value == 12);
	CHECK(set.lower_bound({ 18 })->get().value == 12);
	CHECK(set.lower_bound({ 20 })->get().value == 25);
	CHECK(set.lower_bound({ 29 })->get().value == 25);
	CHECK(set.lower_bound({ 30 }) == nullptr);
}

TEST_CASE("[RBSet] lower_bound agrees with std::set for random mutations") {
	RBSet<int> actual_set;
	std::set<int> reference;
	uint32_t seed = 0x41e718a9u;
	for (int i = 0; i < 4096; ++i) {
		seed = seed * 1664525u + 1013904223u;
		const int value = int((seed >> 8) % 2048u) - 1024;
		if (i % 7 == 0) {
			CHECK(actual_set.erase(value) == (reference.erase(value) != 0));
		} else {
			actual_set.insert(value);
			reference.insert(value);
		}
		if ((i & 31) == 0) {
			CHECK(actual_set.size() == int(reference.size()));
			for (int query = -1200; query <= 1200; query += 47) {
				const auto expected = reference.lower_bound(query);
				const RBSet<int>::Element *actual = actual_set.lower_bound(query);
				if (expected == reference.end()) {
					CHECK(actual == nullptr);
				} else {
					REQUIRE(actual != nullptr);
					CHECK(actual->get() == *expected);
				}
			}
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

TEST_CASE("[RBSet] lower_bound compares once per visited tree node") {
	RBSet<CountedKey> set;
	for (int i = 0; i < 2048; ++i) {
		set.insert({ i * 2 });
	}
	const int maximum_depth = set.calculate_depth();
	for (int query = -1; query <= 4099; query += 37) {
		CountedKey::comparisons = 0;
		const RBSet<CountedKey>::Element *found = set.lower_bound({ query });
		CHECK(CountedKey::comparisons <= maximum_depth + 1);
		const int expected = query <= 0 ? 0 : (query + (query & 1));
		if (expected > 4094) {
			CHECK(found == nullptr);
		} else {
			REQUIRE(found != nullptr);
			CHECK(found->get().value == expected);
		}
	}
}

} // namespace TestRBSet
