/**************************************************************************/
/*  test_bvh_aabb_visitor_containment.cpp                                 */
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

TEST_FORCE_LINK(test_bvh_aabb_visitor_containment)

#include "core/math/bvh.h"

namespace TestBVHAABBVisitorContainment {

struct Item {
	int id = -1;
};

struct PairTest {
	static bool user_pair_check(const Item *, const Item *) { return true; }
};

struct CullTest {
	static bool user_cull_check(const Item *, const Item *) { return true; }
};

constexpr int COUNT = 256;

struct Hits {
	bool seen[COUNT] = {};
	int count = 0;
	int stop_at = 0;
};

static bool collect(Item *p_item, int, void *p_userdata) {
	Hits &hits = *static_cast<Hits *>(p_userdata);
	CHECK(p_item->id >= 0);
	CHECK(p_item->id < COUNT);
	CHECK(!hits.seen[p_item->id]);
	hits.seen[p_item->id] = true;
	hits.count++;
	return hits.stop_at == 0 || hits.count < hits.stop_at;
}

TEST_CASE("[BVH] Streaming 2D AABB visitor: contained, partial, empty and masked queries") {
	using Bounds = BVH_ABB<Rect2, Vector2>;
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	Item items[COUNT];
	Bounds boxes[COUNT];
	for (int i = 0; i < COUNT; ++i) {
		items[i].id = i;
		const Rect2 rect(Vector2(real_t(i % 16) * 3.0, real_t(i / 16) * 3.0), Vector2(1.0, 1.0));
		boxes[i].from(rect);
		tree.create(&items[i], true, uint32_t(i & 1), 3, rect);
	}

	for (int q = 0; q < 100; ++q) {
		const Rect2 query = q == 0 ? Rect2(-100, -100, 300, 300) :
				q == 1 ? Rect2(200, 200, 2, 2) :
				Rect2(real_t((q * 17) % 70) - 5.5, real_t((q * 31) % 70) - 6.5,
						real_t(4 + (q % 7) * 7), real_t(4 + (q % 5) * 9));
		Bounds packed_query;
		packed_query.from(query);
		const uint32_t mask = q % 4 == 0 ? 3 : q % 4 == 1 ? 1 : q % 4 == 2 ? 2 : 0;

		bool expected[COUNT] = {};
		int expected_count = 0;
		for (int i = 0; i < COUNT; ++i) {
			if ((mask & (uint32_t(1) << (i & 1))) && packed_query.intersects(boxes[i])) {
				expected[i] = true;
				expected_count++;
			}
		}

		Hits all;
		CHECK(tree.visit_aabb(query, collect, &all, mask));
		CHECK(all.count == expected_count);
		for (int i = 0; i < COUNT; ++i) {
			CHECK(all.seen[i] == expected[i]);
		}

		Hits short_circuit;
		short_circuit.stop_at = 5;
		const bool completed = tree.visit_aabb(query, collect, &short_circuit, mask);
		CHECK(short_circuit.count == MIN(expected_count, 5));
		CHECK(completed == (expected_count < 5));
	}
}

TEST_CASE("[BVH] Streaming 3D AABB visitor: contained, partial, empty and masked queries") {
	using Bounds = BVH_ABB<AABB, Vector3>;
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	Item items[COUNT];
	Bounds boxes[COUNT];
	for (int i = 0; i < COUNT; ++i) {
		items[i].id = i;
		const AABB aabb(Vector3(real_t(i % 16) * 3.0, real_t((i / 16) % 8) * 3.0, real_t(i / 128) * 3.0),
				Vector3(1.0, 1.0, 1.0));
		boxes[i].from(aabb);
		tree.create(&items[i], true, uint32_t(i & 1), 3, aabb);
	}

	for (int q = 0; q < 100; ++q) {
		const AABB query = q == 0 ? AABB(Vector3(-100, -100, -100), Vector3(300, 300, 300)) :
				q == 1 ? AABB(Vector3(200, 200, 200), Vector3(2, 2, 2)) :
				AABB(Vector3(real_t((q * 17) % 70) - 5.5, real_t((q * 31) % 50) - 6.5, real_t((q * 7) % 20) - 4.5),
						Vector3(real_t(4 + (q % 7) * 7), real_t(4 + (q % 5) * 9), real_t(2 + (q % 3) * 6)));
		Bounds packed_query;
		packed_query.from(query);
		const uint32_t mask = q % 4 == 0 ? 3 : q % 4 == 1 ? 1 : q % 4 == 2 ? 2 : 0;

		bool expected[COUNT] = {};
		int expected_count = 0;
		for (int i = 0; i < COUNT; ++i) {
			if ((mask & (uint32_t(1) << (i & 1))) && packed_query.intersects(boxes[i])) {
				expected[i] = true;
				expected_count++;
			}
		}

		Hits all;
		CHECK(tree.visit_aabb(query, collect, &all, mask));
		CHECK(all.count == expected_count);
		for (int i = 0; i < COUNT; ++i) {
			CHECK(all.seen[i] == expected[i]);
		}

		Hits short_circuit;
		short_circuit.stop_at = 5;
		const bool completed = tree.visit_aabb(query, collect, &short_circuit, mask);
		CHECK(short_circuit.count == MIN(expected_count, 5));
		CHECK(completed == (expected_count < 5));
	}
}

} // namespace TestBVHAABBVisitorContainment
