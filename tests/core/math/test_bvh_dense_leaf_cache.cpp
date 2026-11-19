/**************************************************************************/
/*  test_bvh_dense_leaf_cache.cpp                                         */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_bvh_dense_leaf_cache)

#include "core/math/aabb.h"
#include "core/math/bvh.h"
#include "core/math/rect2.h"

namespace TestBVHDenseLeafCache {

constexpr int COUNT = 64;

struct Item {
	int id = 0;
	Rect2 rect;
	AABB box;
};

struct PairTest {
	static bool user_pair_check(const Item *, const Item *) { return true; }
};

struct CullTest {
	static bool user_cull_check(const Item *, const Item *) { return true; }
};

struct Probe2D {
	Vector2 from;
	Vector2 to;
	int reject_below = 0;
	real_t nearest = 1.0;
	int nearest_id = -1;
	int callbacks = 0;
};

struct Probe3D {
	Vector3 from;
	Vector3 to;
	int reject_below = 0;
	real_t nearest = 1.0;
	int nearest_id = -1;
	int callbacks = 0;
};

static real_t collect_2d(Item *p_item, int, real_t p_max_fraction, void *p_userdata) {
	Probe2D &probe = *static_cast<Probe2D *>(p_userdata);
	probe.callbacks++;
	if (p_item->id < probe.reject_below) {
		return p_max_fraction;
	}
	BVH_ABB<Rect2, Vector2> bounds;
	bounds.from(p_item->rect);
	real_t entry;
	if (bounds.intersects_segment({ probe.from, probe.to }, &entry) && entry < p_max_fraction) {
		probe.nearest = entry;
		probe.nearest_id = p_item->id;
		return entry;
	}
	return p_max_fraction;
}

static real_t collect_3d(Item *p_item, int, real_t p_max_fraction, void *p_userdata) {
	Probe3D &probe = *static_cast<Probe3D *>(p_userdata);
	probe.callbacks++;
	if (p_item->id < probe.reject_below) {
		return p_max_fraction;
	}
	BVH_ABB<AABB, Vector3> bounds;
	bounds.from(p_item->box);
	real_t entry;
	if (bounds.intersects_segment({ probe.from, probe.to }, &entry) && entry < p_max_fraction) {
		probe.nearest = entry;
		probe.nearest_id = p_item->id;
		return entry;
	}
	return p_max_fraction;
}

TEST_CASE("[BVH] Dense 2D leaf caches entries with filtering, clipping and tree masks") {
	using Tree = BVH_Manager<Item, 2, false, 128, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	Item items[COUNT];
	for (int i = COUNT - 1; i >= 0; --i) {
		items[i].id = i;
		items[i].rect = Rect2(real_t(i * 3), i % 11 == 0 ? real_t(5) : real_t(0), 1, 1);
		tree.create(&items[i], true, uint32_t(i & 1), 3, items[i].rect);
	}
	for (int mask = 0; mask < 4; ++mask) {
		for (int reject = 0; reject < COUNT; reject += 7) {
			Probe2D probe;
			probe.from = Vector2(-2, 0.5);
			probe.to = Vector2(COUNT * 3 + 2, 0.5);
			probe.reject_below = reject;
			tree.cast_segment(probe.from, probe.to, collect_2d, &probe, uint32_t(mask));
			int expected_id = -1;
			for (int i = reject; i < COUNT; ++i) {
				if (i % 11 != 0 && (mask & (1 << (i & 1)))) {
					expected_id = i;
					break;
				}
			}
			CHECK(probe.nearest_id == expected_id);
			CHECK(probe.callbacks <= COUNT);
			if (expected_id >= 0) {
				CHECK(probe.nearest > 0.0);
				CHECK(probe.nearest < 1.0);
			}
		}
	}
}

TEST_CASE("[BVH] Dense 3D leaf caches entries with filtering, clipping and tree masks") {
	using Tree = BVH_Manager<Item, 2, false, 128, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	Item items[COUNT];
	for (int i = COUNT - 1; i >= 0; --i) {
		items[i].id = i;
		items[i].box = AABB(Vector3(real_t(i * 3), i % 11 == 0 ? real_t(5) : real_t(0), 0), Vector3(1, 1, 1));
		tree.create(&items[i], true, uint32_t(i & 1), 3, items[i].box);
	}
	for (int mask = 0; mask < 4; ++mask) {
		for (int reject = 0; reject < COUNT; reject += 7) {
			Probe3D probe;
			probe.from = Vector3(-2, 0.5, 0.5);
			probe.to = Vector3(COUNT * 3 + 2, 0.5, 0.5);
			probe.reject_below = reject;
			tree.cast_segment(probe.from, probe.to, collect_3d, &probe, uint32_t(mask));
			int expected_id = -1;
			for (int i = reject; i < COUNT; ++i) {
				if (i % 11 != 0 && (mask & (1 << (i & 1)))) {
					expected_id = i;
					break;
				}
			}
			CHECK(probe.nearest_id == expected_id);
			CHECK(probe.callbacks <= COUNT);
			if (expected_id >= 0) {
				CHECK(probe.nearest > 0.0);
				CHECK(probe.nearest < 1.0);
			}
		}
	}
}

} // namespace TestBVHDenseLeafCache
