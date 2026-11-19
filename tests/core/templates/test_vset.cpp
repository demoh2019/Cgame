/**************************************************************************/
/*  test_vset.cpp                                                         */
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

TEST_FORCE_LINK(test_vset)

#include "core/templates/vset.h"

#include <cstdint>
#include <set>

namespace TestVSet {

template <typename T>
class TestClass : public VSet<T> {
public:
	int _find(const T &p_val, bool &r_exact) const {
		return VSet<T>::_find(p_val, r_exact);
	}
};

TEST_CASE("[VSet] _find and _find_exact correctness.") {
	TestClass<int> set;

	// insert some values
	set.insert(10);
	set.insert(20);
	set.insert(30);
	set.insert(40);
	set.insert(50);

	// data should be sorted
	CHECK(set.size() == 5);
	CHECK(set[0] == 10);
	CHECK(set[1] == 20);
	CHECK(set[2] == 30);
	CHECK(set[3] == 40);
	CHECK(set[4] == 50);

	// _find_exact return exact position for existing elements
	CHECK(set.find(10) == 0);
	CHECK(set.find(30) == 2);
	CHECK(set.find(50) == 4);

	// _find_exact return -1 for non-existing elements
	CHECK(set.find(15) == -1);
	CHECK(set.find(0) == -1);
	CHECK(set.find(60) == -1);

	// test _find
	bool exact;

	// existing elements
	CHECK(set._find(10, exact) == 0);
	CHECK(exact == true);

	CHECK(set._find(30, exact) == 2);
	CHECK(exact == true);

	// non-existing elements
	CHECK(set._find(25, exact) == 2);
	CHECK(exact == false);

	CHECK(set._find(35, exact) == 3);
	CHECK(exact == false);

	CHECK(set._find(5, exact) == 0);
	CHECK(exact == false);

	CHECK(set._find(60, exact) == 5);
	CHECK(exact == false);
}

struct ComparisonCountedInt {
	int value = 0;
	static inline int comparisons = 0;

	bool operator<(const ComparisonCountedInt &p_other) const {
		comparisons++;
		return value < p_other.value;
	}
};

TEST_CASE("[VSet] Membership and insertion use one comparison after lower bound") {
	TestClass<ComparisonCountedInt> set;
	for (int i = 1; i <= 5; i++) {
		set.insert({ i * 10 });
	}

	ComparisonCountedInt::comparisons = 0;
	CHECK(set.find({ 30 }) == 2);
	// Two lower-bound comparisons plus one equivalence comparison.
	CHECK(ComparisonCountedInt::comparisons <= 3);

	ComparisonCountedInt::comparisons = 0;
	CHECK(!set.has({ 25 }));
	CHECK(ComparisonCountedInt::comparisons <= 3);

	ComparisonCountedInt::comparisons = 0;
	set.insert({ 30 });
	CHECK(set.size() == 5);
	CHECK(ComparisonCountedInt::comparisons <= 3);
}

struct DecadeOrderedInt {
	int value = 0;

	bool operator<(const DecadeOrderedInt &p_other) const {
		return value / 10 < p_other.value / 10;
	}
};

TEST_CASE("[VSet] Equivalent keys use strict weak ordering rather than equality") {
	VSet<DecadeOrderedInt> set;
	set.insert({ 12 });
	set.insert({ 19 });
	set.insert({ 25 });
	CHECK(set.size() == 2);
	CHECK(set.find({ 11 }) == 0);
	CHECK(set.has({ 18 }));
	CHECK(set.find({ 29 }) == 1);
	CHECK(!set.has({ 35 }));
	set.erase({ 17 });
	CHECK(set.size() == 1);
	CHECK(set[0].value == 25);
}


TEST_CASE("[VSet] Ascending insertion uses one comparison after the first element") {
	VSet<ComparisonCountedInt> set;
	for (int i = 0; i < 512; i++) {
		ComparisonCountedInt::comparisons = 0;
		set.insert({ i });
		CHECK(ComparisonCountedInt::comparisons == (i == 0 ? 0 : 1));
	}
	CHECK(set.size() == 512);
	for (int i = 0; i < 512; i++) {
		CHECK(set[i].value == i);
	}

	// Duplicate maximums and smaller insertions must preserve uniqueness and order.
	set.insert({ 511 });
	CHECK(set.size() == 512);
	set.insert({ -1 });
	CHECK(set.size() == 513);
	CHECK(set[0].value == -1);
	CHECK(set[512].value == 511);
}

TEST_CASE("[VSet] Ordered and mixed inserts retain reference set semantics") {
	VSet<int> set;
	std::set<int> reference;
	uint32_t seed = 0x71c03e9au;

	for (int i = 0; i < 4096; i++) {
		seed = seed * 1664525u + 1013904223u;
		int value = int((seed >> 8) % 601u) - 300;
		// Exercise monotone, reverse, duplicate-heavy and random workloads.
		if (i < 800) {
			value = i * 2;
		} else if (i < 1600) {
			value = -i * 2;
		} else if (i < 2400) {
			value = 17;
		}
		set.insert(value);
		reference.insert(value);
	}
	CHECK(set.size() == int(reference.size()));
	int index = 0;
	for (int value : reference) {
		CHECK(set[index] == value);
		CHECK(set.find(value) == index);
		CHECK(set.has(value));
		index++;
	}
	CHECK(set.find(12345678) == -1);
}

TEST_CASE("[VSet] Ascending insertion preserves copy-on-write isolation") {
	VSet<int> original;
	for (int i = 0; i < 80; i++) {
		original.insert(i);
	}
	VSet<int> shared = original;
	shared.insert(80);
	CHECK(shared.size() == 81);
	CHECK(shared[80] == 80);
	CHECK(original.size() == 80);
	CHECK(!original.has(80));

	original.insert(81);
	CHECK(original.size() == 81);
	CHECK(original[80] == 81);
	CHECK(!shared.has(81));
}

} // namespace TestVSet
