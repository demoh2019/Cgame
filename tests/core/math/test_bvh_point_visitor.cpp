/**************************************************************************/
/*  test_bvh_point_visitor.cpp                                            */
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

TEST_FORCE_LINK(test_bvh_point_visitor)

#include "core/math/bvh.h"
#include "core/math/rect2.h"

namespace TestBVHPointVisitor {

constexpr int ITEM_COUNT = 512;

struct Item {
	int id = -1;
};

struct PairTest {
	static bool user_pair_check(const Item *, const Item *) { return true; }
};

struct CullTest {
	static bool user_cull_check(const Item *, const Item *) { return true; }
};

struct Hits {
	bool seen[ITEM_COUNT] = {};
	int count = 0;
	int max_results = 0;
};

static bool collect(Item *p_item, int, void *p_userdata) {
	Hits &hits = *static_cast<Hits *>(p_userdata);
	CHECK(p_item->id >= 0);
	CHECK(p_item->id < ITEM_COUNT);
	CHECK(!hits.seen[p_item->id]);
	hits.seen[p_item->id] = true;
	hits.count++;
	return hits.max_results == 0 || hits.count < hits.max_results;
}

TEST_CASE("[BVH] 2D streaming point visitor visits each matching proxy once") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, Rect2, Vector2, false>;
	using Packed = BVH_ABB<Rect2, Vector2>;
	Tree tree;
	Item items[ITEM_COUNT];
	Packed bounds[ITEM_COUNT];

	for (int i = 0; i < ITEM_COUNT; ++i) {
		items[i].id = i;
		const Vector2 pos(real_t((i * 17) % 131) - 42.0, real_t((i * 23) % 119) - 35.0);
		const Vector2 size(real_t((i % 5) + 1), real_t((i % 7) + 1));
		const Rect2 box(pos, size);
		bounds[i].from(box);
		tree.create(&items[i], true, uint32_t(i & 1), 3, box);
	}

	for (int q = 0; q < 240; ++q) {
		const Vector2 point(q == 0 ? -1000.0 : q == 1 ? 1000.0 : real_t((q * 13) % 139) - 45.0,
				q == 0 ? -1000.0 : q == 1 ? 1000.0 : real_t((q * 31) % 131) - 40.0);
		const uint32_t mask = uint32_t(q % 4);
		int expected = 0;
		bool expected_ids[ITEM_COUNT] = {};
		for (int i = 0; i < ITEM_COUNT; ++i) {
			if ((mask & (uint32_t(1) << (i & 1))) && bounds[i].intersects_point(point)) {
				expected_ids[i] = true;
				expected++;
			}
		}

		Hits hits;
		CHECK(tree.visit_point(point, collect, &hits, mask));
		CHECK(hits.count == expected);
		for (int i = 0; i < ITEM_COUNT; ++i) {
			CHECK(hits.seen[i] == expected_ids[i]);
		}

		Hits limited;
		limited.max_results = 1;
		const bool completed = tree.visit_point(point, collect, &limited, mask);
		CHECK(limited.count == MIN(expected, 1));
		CHECK(completed == (expected == 0));
	}
}

TEST_CASE("[BVH] 3D streaming point visitor preserves boundary and tree-mask results") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, AABB, Vector3, false>;
	using Packed = BVH_ABB<AABB, Vector3>;
	Tree tree;
	Item items[ITEM_COUNT];
	Packed bounds[ITEM_COUNT];

	for (int i = 0; i < ITEM_COUNT; ++i) {
		items[i].id = i;
		const Vector3 pos(real_t((i * 17) % 131) - 42.0, real_t((i * 23) % 119) - 35.0,
				real_t((i * 11) % 79) - 20.0);
		const Vector3 size(real_t((i % 5) + 1), real_t((i % 7) + 1), real_t((i % 3) + 1));
		const AABB box(pos, size);
		bounds[i].from(box);
		tree.create(&items[i], true, uint32_t(i & 1), 3, box);
	}

	for (int q = 0; q < 240; ++q) {
		const Vector3 point(q == 0 ? -1000.0 : q == 1 ? 1000.0 : real_t((q * 13) % 139) - 45.0,
				q == 0 ? -1000.0 : q == 1 ? 1000.0 : real_t((q * 31) % 131) - 40.0,
				q == 0 ? -1000.0 : q == 1 ? 1000.0 : real_t((q * 19) % 83) - 23.0);
		const uint32_t mask = uint32_t(q % 4);
		int expected = 0;
		bool expected_ids[ITEM_COUNT] = {};
		for (int i = 0; i < ITEM_COUNT; ++i) {
			if ((mask & (uint32_t(1) << (i & 1))) && bounds[i].intersects_point(point)) {
				expected_ids[i] = true;
				expected++;
			}
		}

		Hits hits;
		CHECK(tree.visit_point(point, collect, &hits, mask));
		CHECK(hits.count == expected);
		for (int i = 0; i < ITEM_COUNT; ++i) {
			CHECK(hits.seen[i] == expected_ids[i]);
		}

		Hits limited;
		limited.max_results = 1;
		const bool completed = tree.visit_point(point, collect, &limited, mask);
		CHECK(limited.count == MIN(expected, 1));
		CHECK(completed == (expected == 0));
	}
}

} // namespace TestBVHPointVisitor
