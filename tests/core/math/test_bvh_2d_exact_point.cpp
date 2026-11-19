/**************************************************************************/
/*  test_bvh_2d_exact_point.cpp                                           */
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

TEST_FORCE_LINK(test_bvh_2d_exact_point)

#include "core/math/bvh.h"
#include "core/math/rect2.h"

namespace TestBVH2DExactPoint {

struct Item {
	int id = -1;
};

struct PairTest {
	static bool user_pair_check(const Item *, const Item *) { return true; }
};

struct CullTest {
	static bool user_cull_check(const Item *, const Item *) { return true; }
};

struct Result {
	int candidates = 0;
	int target_hits = 0;
	int stop_after = 0;
};

static bool collect(Item *p_item, int, void *p_userdata) {
	Result &result = *static_cast<Result *>(p_userdata);
	result.candidates++;
	if (p_item->id == 4096) {
		result.target_hits++;
	}
	return result.stop_after == 0 || result.candidates < result.stop_after;
}

TEST_CASE("[BVH] Exact 2D point traversal skips AABBs that only touch a near-point epsilon query") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int DISTRACTORS = 4096;
	Item items[DISTRACTORS + 1];
	// All distractors overlap the old synthetic (-1e-5, +1e-5) query
	// AABB, but none contains the exact point x=0.
	for (int i = 0; i < DISTRACTORS; ++i) {
		items[i].id = i;
		const Rect2 near_only(Vector2(real_t(0.000005), real_t(-0.5)), Vector2(0.2, 1.0));
		tree.create(&items[i], true, uint32_t(i & 1), 3, near_only);
	}
	items[DISTRACTORS].id = DISTRACTORS;
	tree.create(&items[DISTRACTORS], true, 0, 3, Rect2(Vector2(-1, -1), Vector2(2, 2)));

	Result exact;
	CHECK(tree.visit_point(Vector2(), collect, &exact));
	CHECK(exact.candidates == 1);
	CHECK(exact.target_hits == 1);

	Result old_epsilon;
	const Rect2 old_query(Vector2(-0.00001, -0.00001), Vector2(0.00002, 0.00002));
	CHECK(tree.visit_aabb(old_query, collect, &old_epsilon));
	CHECK(old_epsilon.candidates == DISTRACTORS + 1);
	CHECK(old_epsilon.target_hits == 1);

	Result matching_tree;
	CHECK(tree.visit_point(Vector2(), collect, &matching_tree, 1));
	CHECK(matching_tree.candidates == 1);
	CHECK(matching_tree.target_hits == 1);

	Result other_tree;
	CHECK(tree.visit_point(Vector2(), collect, &other_tree, 2));
	CHECK(other_tree.candidates == 0);

	Result early_stop;
	early_stop.stop_after = 1;
	CHECK(!tree.visit_point(Vector2(), collect, &early_stop));
	CHECK(early_stop.candidates == 1);
	CHECK(early_stop.target_hits == 1);
}

} // namespace TestBVH2DExactPoint
