/**************************************************************************/
/*  test_bvh_stream_query.cpp                                             */
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

TEST_FORCE_LINK(test_bvh_stream_query)

#include "core/math/bvh.h"
#include "core/math/rect2.h"
#include "core/math/vector2.h"

namespace TestBVHStreamQuery {

struct Item {
	int id = -1;
};

struct PairTest {
	static bool user_pair_check(const Item *, const Item *) {
		return true;
	}
};

struct CullTest {
	static bool user_cull_check(const Item *, const Item *) {
		return true;
	}
};

struct VisitorStats {
	int candidates = 0;
	int accepted = 0;
	int wanted_id = -1;
	int max_results = 0;
};

static bool collect_matches(Item *p_item, int, void *p_userdata) {
	VisitorStats &stats = *static_cast<VisitorStats *>(p_userdata);
	stats.candidates++;
	if (p_item->id != stats.wanted_id) {
		return true;
	}
	stats.accepted++;
	return stats.max_results == 0 || stats.accepted < stats.max_results;
}

TEST_CASE("[BVH] Streaming 2D AABB visitor does not lose filtered candidates beyond 2048") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 4096;
	Item items[COUNT];
	for (int i = 0; i < COUNT; ++i) {
		items[i].id = i;
		tree.create(&items[i], true, uint32_t(i & 1), 3, Rect2(-1, -1, 2, 2));
	}
	const Rect2 query(-0.01, -0.01, 0.02, 0.02);
	Item *bounded_results[8] = {};
	CHECK(tree.cull_aabb(query, bounded_results, 8, nullptr) == 8);

	VisitorStats all;
	all.wanted_id = COUNT - 1;
	CHECK(tree.visit_aabb(query, collect_matches, &all));
	CHECK(all.candidates == COUNT);
	CHECK(all.accepted == 1);

	VisitorStats early;
	early.wanted_id = COUNT - 1;
	early.max_results = 1;
	CHECK(!tree.visit_aabb(query, collect_matches, &early));
	CHECK(early.accepted == 1);

	VisitorStats static_only;
	CHECK(tree.visit_aabb(query, collect_matches, &static_only, 1));
	CHECK(static_only.candidates == COUNT / 2);

	VisitorStats no_tree;
	CHECK(tree.visit_aabb(query, collect_matches, &no_tree, 0));
	CHECK(no_tree.candidates == 0);
}

TEST_CASE("[BVH] Streaming 3D point visitor does not lose filtered candidates beyond 2048") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	constexpr int COUNT = 4096;
	Item items[COUNT];
	for (int i = 0; i < COUNT; ++i) {
		items[i].id = i;
		tree.create(&items[i], true, uint32_t(i & 1), 3, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)));
	}
	const Vector3 point(0, 0, 0);
	Item *bounded_results[8] = {};
	CHECK(tree.cull_point(point, bounded_results, 8, nullptr) == 8);

	VisitorStats all;
	all.wanted_id = COUNT - 1;
	CHECK(tree.visit_point(point, collect_matches, &all));
	CHECK(all.candidates == COUNT);
	CHECK(all.accepted == 1);

	VisitorStats early;
	early.wanted_id = COUNT - 1;
	early.max_results = 1;
	CHECK(!tree.visit_point(point, collect_matches, &early));
	CHECK(early.accepted == 1);

	VisitorStats dynamic_only;
	CHECK(tree.visit_point(point, collect_matches, &dynamic_only, 2));
	CHECK(dynamic_only.candidates == COUNT / 2);

	VisitorStats no_tree;
	CHECK(tree.visit_point(point, collect_matches, &no_tree, 0));
	CHECK(no_tree.candidates == 0);
}

} // namespace TestBVHStreamQuery
