/**************************************************************************/
/*  test_bvh_ray_entry_cache.cpp                                          */
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

TEST_FORCE_LINK(test_bvh_ray_entry_cache)

#include "core/math/aabb.h"
#include "core/math/bvh.h"
#include "core/math/rect2.h"
#include "core/math/vector2.h"
#include "core/math/vector3.h"

namespace TestBVHRayEntryCache {

constexpr int COUNT = 512;

struct Item {
	int id = -1;
	Rect2 rect;
	AABB box;
};

struct PairTest {
	static bool user_pair_check(const Item *, const Item *) { return true; }
};

struct CullTest {
	static bool user_cull_check(const Item *, const Item *) { return true; }
};

struct Query2D {
	Vector2 from;
	Vector2 to;
	real_t best = 1.0;
	int callbacks = 0;
	bool ignore_even = false;
};

struct Query3D {
	Vector3 from;
	Vector3 to;
	real_t best = 1.0;
	int callbacks = 0;
	bool ignore_even = false;
};

static real_t visit_2d(Item *p_item, int, real_t p_max_fraction, void *p_userdata) {
	Query2D &query = *static_cast<Query2D *>(p_userdata);
	query.callbacks++;
	if (query.ignore_even && (p_item->id % 2 == 0)) {
		return p_max_fraction; // A broadphase candidate rejected by narrowphase.
	}
	BVH_ABB<Rect2, Vector2> bounds;
	bounds.from(p_item->rect);
	real_t entry;
	if (bounds.intersects_segment({ query.from, query.to }, &entry) && entry < p_max_fraction) {
		query.best = entry;
		return entry;
	}
	return p_max_fraction;
}

static real_t visit_3d(Item *p_item, int, real_t p_max_fraction, void *p_userdata) {
	Query3D &query = *static_cast<Query3D *>(p_userdata);
	query.callbacks++;
	if (query.ignore_even && (p_item->id % 2 == 0)) {
		return p_max_fraction;
	}
	BVH_ABB<AABB, Vector3> bounds;
	bounds.from(p_item->box);
	real_t entry;
	if (bounds.intersects_segment({ query.from, query.to }, &entry) && entry < p_max_fraction) {
		query.best = entry;
		return entry;
	}
	return p_max_fraction;
}

TEST_CASE("[BVH] 2D ray stack entries remain correct after clipping by nearer hits") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	Item items[COUNT];
	for (int i = 0; i < COUNT; ++i) {
		items[i].id = i;
		items[i].rect = Rect2(Vector2(real_t((i * 17) % 97) - 45, real_t((i * 23) % 113) - 52),
				Vector2(real_t(i % 6 + 1), real_t(i % 5 + 1)));
		tree.create(&items[i], true, uint32_t(i & 1), 3, items[i].rect);
	}
	for (int q = 0; q < 360; ++q) {
		const Vector2 from(q == 0 ? -90 : real_t((q * 19) % 131) - 65,
				q == 0 ? 0 : real_t((q * 31) % 129) - 64);
		const Vector2 to(q == 0 ? 90 : q % 17 == 0 ? from.x : real_t((q * 41) % 139) - 69,
				q == 0 ? 0 : q % 17 == 0 ? from.y : real_t((q * 13) % 149) - 74);
		const uint32_t mask = uint32_t(q % 4);
		for (int ignored = 0; ignored < 2; ++ignored) {
			Query2D query;
			query.from = from;
			query.to = to;
			query.ignore_even = (ignored == 1);
			tree.cast_segment(from, to, visit_2d, &query, mask);

			real_t expected = 1.0;
			for (int i = 0; i < COUNT; ++i) {
				if (!(mask & (uint32_t(1) << (i & 1))) || (query.ignore_even && i % 2 == 0)) {
					continue;
				}
				BVH_ABB<Rect2, Vector2> bounds;
				bounds.from(items[i].rect);
				real_t entry;
				if (bounds.intersects_segment({ from, to }, &entry)) {
					expected = MIN(expected, entry);
				}
			}
			CHECK(Math::abs(query.best - expected) < real_t(0.00001));
		}
	}
}

TEST_CASE("[BVH] 3D ray stack entries remain correct after clipping by nearer hits") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	Item items[COUNT];
	for (int i = 0; i < COUNT; ++i) {
		items[i].id = i;
		items[i].box = AABB(Vector3(real_t((i * 17) % 97) - 45,
						real_t((i * 23) % 113) - 52, real_t((i * 11) % 61) - 30),
				Vector3(real_t(i % 6 + 1), real_t(i % 5 + 1), real_t(i % 4 + 1)));
		tree.create(&items[i], true, uint32_t(i & 1), 3, items[i].box);
	}
	for (int q = 0; q < 360; ++q) {
		const Vector3 from(q == 0 ? -90 : real_t((q * 19) % 131) - 65,
				q == 0 ? 0 : real_t((q * 31) % 129) - 64, q == 0 ? 0 : real_t((q * 11) % 77) - 38);
		const Vector3 to(q == 0 ? 90 : q % 17 == 0 ? from.x : real_t((q * 41) % 139) - 69,
				q == 0 ? 0 : q % 17 == 0 ? from.y : real_t((q * 13) % 149) - 74,
				q == 0 ? 0 : q % 17 == 0 ? from.z : real_t((q * 29) % 83) - 41);
		const uint32_t mask = uint32_t(q % 4);
		for (int ignored = 0; ignored < 2; ++ignored) {
			Query3D query;
			query.from = from;
			query.to = to;
			query.ignore_even = (ignored == 1);
			tree.cast_segment(from, to, visit_3d, &query, mask);

			real_t expected = 1.0;
			for (int i = 0; i < COUNT; ++i) {
				if (!(mask & (uint32_t(1) << (i & 1))) || (query.ignore_even && i % 2 == 0)) {
					continue;
				}
				BVH_ABB<AABB, Vector3> bounds;
				bounds.from(items[i].box);
				real_t entry;
				if (bounds.intersects_segment({ from, to }, &entry)) {
					expected = MIN(expected, entry);
				}
			}
			CHECK(Math::abs(query.best - expected) < real_t(0.00001));
		}
	}
}

} // namespace TestBVHRayEntryCache
