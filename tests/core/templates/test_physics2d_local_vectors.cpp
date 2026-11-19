/**************************************************************************/
/*  test_physics2d_local_vectors.cpp                                      */
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

TEST_FORCE_LINK(test_physics2d_local_vectors)

#include "core/math/vector2.h"
#include "core/templates/local_vector.h"

namespace TestPhysics2DLocalVectors {

struct AreaEntry {
	int priority = 0;
	int ref_count = 1;

	AreaEntry() = default;
	explicit AreaEntry(int p_priority) :
			priority(p_priority) {}

	bool operator<(const AreaEntry &p_other) const {
		return priority < p_other.priority;
	}
	bool operator==(const AreaEntry &p_other) const {
		return priority == p_other.priority;
	}
};

struct ContactEntry {
	Vector2 position;
	Vector2 normal;
	real_t depth = 0;
};

TEST_CASE("[Physics2DLocalVector] Ordered insert preserves area priorities") {
	LocalVector<AreaEntry> areas;
	areas.ordered_insert(AreaEntry(8));
	areas.ordered_insert(AreaEntry(1));
	areas.ordered_insert(AreaEntry(5));
	areas.ordered_insert(AreaEntry(3));
	REQUIRE_EQ(areas.size(), 4);
	CHECK(areas[0].priority == 1);
	CHECK(areas[1].priority == 3);
	CHECK(areas[2].priority == 5);
	CHECK(areas[3].priority == 8);
	areas.sort();
	CHECK(areas[0].priority == 1);
	CHECK(areas[3].priority == 8);
}

TEST_CASE("[Physics2DLocalVector] Area reference counts survive ordered removals") {
	LocalVector<AreaEntry> areas;
	areas.ordered_insert(AreaEntry(3));
	areas.ordered_insert(AreaEntry(1));
	areas.ordered_insert(AreaEntry(2));
	int index = areas.find(AreaEntry(2));
	REQUIRE(index >= 0);
	areas[index].ref_count++;
	CHECK(areas[index].ref_count == 2);
	areas[index].ref_count--;
	CHECK(areas[index].ref_count == 1);
	areas.remove_at(index);
	REQUIRE_EQ(areas.size(), 2);
	CHECK(areas.find(AreaEntry(2)) == -1);
	CHECK(areas.find(AreaEntry(1)) >= 0);
	CHECK(areas.find(AreaEntry(3)) >= 0);
}

TEST_CASE("[Physics2DLocalVector] Contact storage is directly mutable through ptr") {
	LocalVector<ContactEntry> contacts;
	contacts.resize(16);
	REQUIRE_EQ(contacts.size(), 16);
	ContactEntry *p = contacts.ptr();
	REQUIRE(p != nullptr);
	for (int i = 0; i < 16; i++) {
		p[i].position = Vector2(i, i * 2);
		p[i].normal = Vector2(0, 1);
		p[i].depth = i * 0.1;
	}
	for (int i = 0; i < 16; i++) {
		CHECK(contacts[i].position == Vector2(i, i * 2));
		CHECK(contacts[i].normal == Vector2(0, 1));
		CHECK(Math::is_equal_approx(contacts[i].depth, real_t(i * 0.1)));
	}
}

TEST_CASE("[Physics2DLocalVector] Resizing contacts invalidates only discarded values") {
	LocalVector<ContactEntry> contacts;
	contacts.resize(4);
	for (int i = 0; i < 4; i++) {
		contacts[i].depth = i + 1;
	}
	contacts.resize(2);
	REQUIRE_EQ(contacts.size(), 2);
	CHECK(contacts[0].depth == 1);
	CHECK(contacts[1].depth == 2);
	contacts.resize(8);
	REQUIRE_EQ(contacts.size(), 8);
	CHECK(contacts[0].depth == 1);
	CHECK(contacts[1].depth == 2);
}

TEST_CASE("[Physics2DLocalVector] Contact replacement maintains deepest collisions") {
	constexpr int capacity = 8;
	LocalVector<ContactEntry> contacts;
	contacts.resize(capacity);
	int count = 0;
	for (int sample = 0; sample < 48; sample++) {
		const real_t depth = sample * 0.05;
		if (count < capacity) {
			contacts[count++].depth = depth;
			continue;
		}
		int min_idx = 0;
		for (int j = 1; j < capacity; j++) {
			if (contacts[j].depth < contacts[min_idx].depth) {
				min_idx = j;
			}
		}
		if (depth > contacts[min_idx].depth) {
			contacts[min_idx].depth = depth;
		}
	}
	CHECK(count == capacity);
	for (int i = 0; i < capacity; i++) {
		CHECK(contacts[i].depth >= (48 - capacity) * 0.05 - 0.0001);
	}
}

TEST_CASE("[Physics2DLocalVector] Many area changes preserve lookup and order") {
	LocalVector<AreaEntry> areas;
	for (int i = 200; i >= 0; i--) {
		areas.ordered_insert(AreaEntry(i));
	}
	REQUIRE_EQ(areas.size(), 201);
	for (int i = 0; i <= 200; i++) {
		CHECK(areas[i].priority == i);
		CHECK(areas.find(AreaEntry(i)) >= 0);
	}
	for (int i = 200; i >= 0; i -= 2) {
		areas.remove_at(i);
	}
	REQUIRE_EQ(areas.size(), 100);
	for (int i = 0; i < 100; i++) {
		CHECK(areas[i].priority == i * 2 + 1);
	}
}

} // namespace TestPhysics2DLocalVectors
