/**************************************************************************/
/*  test_bvh_dense_leaf.cpp                                               */
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

TEST_FORCE_LINK(test_bvh_dense_leaf)

#include "core/math/bvh.h"
#include "core/math/rect2.h"
#include "core/math/vector2.h"

namespace TestBVHDenseLeaf {

struct Item {
	int value = 0;
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

struct RayStats {
	int callbacks = 0;
	int first = -1;
	int nearest = -1;
	real_t length = 0.0;
};

static real_t record_order(Item *p_item, int, real_t p_max_fraction, void *p_userdata) {
	RayStats &stats = *static_cast<RayStats *>(p_userdata);
	if (stats.callbacks++ == 0) {
		stats.first = p_item->value;
	}
	return p_max_fraction;
}

static real_t closest_hit(Item *p_item, int, real_t p_max_fraction, void *p_userdata) {
	RayStats &stats = *static_cast<RayStats *>(p_userdata);
	stats.callbacks++;
	// Ray starts at x=-2. Each unit-width AABB's exact hit is at x+0.5.
	const real_t fraction = (real_t(p_item->value) * 4.0 + 2.5) / stats.length;
	if (fraction < p_max_fraction) {
		stats.nearest = p_item->value;
		return fraction;
	}
	return p_max_fraction;
}

static real_t ignore_first_hit(Item *p_item, int p_shape, real_t p_max_fraction, void *p_userdata) {
	if (p_item->value == 0) {
		static_cast<RayStats *>(p_userdata)->callbacks++;
		return p_max_fraction;
	}
	return closest_hit(p_item, p_shape, p_max_fraction, p_userdata);
}

TEST_CASE("[BVH] Dense 2D leaf visits nearest proxy first without losing exact-hit filtering") {
	using Tree = BVH_Manager<Item, 1, false, 128, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 64;
	Item items[COUNT];
	for (int i = 0; i < COUNT; i++) {
		const int position = COUNT - 1 - i;
		items[i].value = position;
		tree.create(&items[i], true, 0, 1, Rect2(position * 4, 0, 1, 1));
	}

	const Vector2 from(-2, 0.5);
	const Vector2 to(COUNT * 4 + 2, 0.5);
	RayStats order;
	tree.cast_segment(from, to, record_order, &order);
	CHECK(order.callbacks == COUNT);
	CHECK(order.first == 0);

	RayStats nearest;
	nearest.length = to.x - from.x;
	tree.cast_segment(from, to, closest_hit, &nearest);
	CHECK(nearest.nearest == 0);
	CHECK(nearest.callbacks == 1);

	RayStats ignored;
	ignored.length = to.x - from.x;
	tree.cast_segment(from, to, ignore_first_hit, &ignored);
	CHECK(ignored.nearest == 1);
	CHECK(ignored.callbacks >= 2);

	order = RayStats();
	tree.cast_segment(to, from, record_order, &order);
	CHECK(order.callbacks == COUNT);
	CHECK(order.first == COUNT - 1);
}

TEST_CASE("[BVH] Dense 3D leaf visits nearest proxy first without losing exact-hit filtering") {
	using Tree = BVH_Manager<Item, 1, false, 128, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	constexpr int COUNT = 64;
	Item items[COUNT];
	for (int i = 0; i < COUNT; i++) {
		const int position = COUNT - 1 - i;
		items[i].value = position;
		tree.create(&items[i], true, 0, 1, AABB(Vector3(position * 4, 0, 0), Vector3(1, 1, 1)));
	}

	const Vector3 from(-2, 0.5, 0.5);
	const Vector3 to(COUNT * 4 + 2, 0.5, 0.5);
	RayStats order;
	tree.cast_segment(from, to, record_order, &order);
	CHECK(order.callbacks == COUNT);
	CHECK(order.first == 0);

	RayStats nearest;
	nearest.length = to.x - from.x;
	tree.cast_segment(from, to, closest_hit, &nearest);
	CHECK(nearest.nearest == 0);
	CHECK(nearest.callbacks == 1);

	RayStats ignored;
	ignored.length = to.x - from.x;
	tree.cast_segment(from, to, ignore_first_hit, &ignored);
	CHECK(ignored.nearest == 1);
	CHECK(ignored.callbacks >= 2);

	order = RayStats();
	tree.cast_segment(to, from, record_order, &order);
	CHECK(order.callbacks == COUNT);
	CHECK(order.first == COUNT - 1);
}

TEST_CASE("[BVH] Small 2D leaves keep their original single-pass insertion order") {
	using Tree = BVH_Manager<Item, 1, false, 128, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	Item far_item;
	far_item.value = 1;
	Item near_item;
	near_item.value = 0;
	tree.create(&far_item, true, 0, 1, Rect2(10, 0, 1, 1));
	tree.create(&near_item, true, 0, 1, Rect2(0, 0, 1, 1));
	RayStats order;
	tree.cast_segment(Vector2(-2, 0.5), Vector2(14, 0.5), record_order, &order);
	CHECK(order.callbacks == 2);
	CHECK(order.first == 1);
}

} // namespace TestBVHDenseLeaf
