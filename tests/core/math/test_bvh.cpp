/**************************************************************************/
/*  test_bvh.cpp                                                          */
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

TEST_FORCE_LINK(test_bvh)

#include "core/math/bvh.h"
#include "core/math/rect2.h"
#include "core/math/vector2.h"

namespace TestBVH {

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

TEST_CASE("[BVH] 2D queued removals and ref reuse") {
	using Tree = BVH_Manager<Item, 1, true, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 128;
	Item items[COUNT + 1];
	BVHHandle handles[COUNT];

	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, 0, 1, Rect2(i * 20, 0, 2, 2));
	}

	// Move every item before removing a non-last entry in the changed queue.
	for (int i = 0; i < COUNT; i++) {
		tree.move(handles[i], Rect2(i * 20 + 8, 0, 2, 2));
	}
	tree.erase(handles[7]);

	// The first erase flushes queued collision checks. Refill the queue
	// and remove another middle entry to exercise repeated swap-removal.
	for (int i = 0; i < COUNT; i++) {
		if (i != 7) {
			tree.move(handles[i], Rect2(i * 20 + 12, 0, 2, 2));
		}
	}
	tree.erase(handles[83]);
	tree.update();

	Item *found[COUNT] = {};
	CHECK(tree.cull_aabb(Rect2(0, 0, 4000, 20), found, COUNT, nullptr) == COUNT - 2);

	items[COUNT].value = COUNT;
	BVHHandle new_handle = tree.create(&items[COUNT], true, 0, 1, Rect2(3000, 0, 2, 2));
	tree.update();
	CHECK(tree.get(new_handle) == &items[COUNT]);
	CHECK(tree.cull_aabb(Rect2(0, 0, 4000, 20), found, COUNT, nullptr) == COUNT - 1);
}

TEST_CASE("[BVH] 3D queued removals preserve remaining bodies") {
	using Tree = BVH_Manager<Item, 1, true, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	constexpr int COUNT = 64;
	Item items[COUNT];
	BVHHandle handles[COUNT];

	for (int i = 0; i < COUNT; i++) {
		handles[i] = tree.create(&items[i], true, 0, 1, AABB(Vector3(i * 20, 0, 0), Vector3(2, 2, 2)));
	}
	for (int i = 0; i < COUNT; i++) {
		tree.move(handles[i], AABB(Vector3(i * 20 + 8, 0, 0), Vector3(2, 2, 2)));
	}
	tree.erase(handles[31]);
	tree.update();

	Item *found[COUNT] = {};
	CHECK(tree.cull_aabb(AABB(Vector3(0, 0, 0), Vector3(2000, 20, 20)), found, COUNT, nullptr) == COUNT - 1);
}

struct CountingPairTest {
	static int calls;
	static bool allow;

	static bool user_pair_check(const Item *, const Item *) {
		calls++;
		return allow;
	}
};

int CountingPairTest::calls = 0;
bool CountingPairTest::allow = true;

static void *count_pair(void *p_userdata, uint32_t, Item *, int, uint32_t, Item *, int) {
	(*static_cast<int *>(p_userdata))++;
	return nullptr;
}

static void count_unpair(void *p_userdata, uint32_t, Item *, int, uint32_t, Item *, int, void *) {
	(*static_cast<int *>(p_userdata))++;
}

TEST_CASE("[BVH] Existing pairs skip redundant user filters but honor forced checks") {
	using Tree = BVH_Manager<Item, 1, true, 16, CountingPairTest, CullTest, Rect2, Vector2, false>;
	CountingPairTest::calls = 0;
	CountingPairTest::allow = true;

	Tree tree;
	int created = 0;
	int removed = 0;
	tree.set_pair_callback(count_pair, &created);
	// Unpair callbacks must receive their own userdata, not pair-callback userdata.
	tree.set_unpair_callback(count_unpair, &removed);

	Item a;
	Item b;
	BVHHandle ha = tree.create(&a, true, 0, 1, Rect2(0, 0, 2, 2));
	BVHHandle hb = tree.create(&b, true, 0, 1, Rect2(1, 0, 2, 2));
	CHECK(created == 1);
	const int initial_filter_calls = CountingPairTest::calls;

	// This move preserves overlap and the existing pair.
	tree.move(ha, Rect2(0.25, 0, 2, 2));
	tree.update();
	CHECK(created == 1);
	CHECK(removed == 0);
	CHECK(CountingPairTest::calls == initial_filter_calls);

	// A forced collision check is still required to re-evaluate changed masks.
	CountingPairTest::allow = false;
	tree.force_collision_check(ha);
	CHECK(removed == 1);
	CountingPairTest::allow = true;
	tree.force_collision_check(ha);
	CHECK(created == 2);

	tree.erase(ha);
	CHECK(removed == 2);
	tree.erase(hb);
}

TEST_CASE("[BVH] Compound shapes avoid self-pair user filters") {
	using Tree = BVH_Manager<Item, 1, true, 16, CountingPairTest, CullTest, AABB, Vector3, false>;
	CountingPairTest::calls = 0;
	CountingPairTest::allow = true;

	Tree tree;
	Item object;
	BVHHandle a = tree.create(&object, true, 0, 1, AABB(Vector3(0, 0, 0), Vector3(2, 2, 2)), 0);
	BVHHandle b = tree.create(&object, true, 0, 1, AABB(Vector3(1, 0, 0), Vector3(2, 2, 2)), 1);
	tree.update();
	CHECK(CountingPairTest::calls == 0);
	tree.erase(a);
	tree.erase(b);
}

struct CountingCullTest {
	static inline int calls = 0;

	static bool user_cull_check(const Item *, const Item *) {
		calls++;
		return true;
	}
};

TEST_CASE("[BVH] Culls stop at result capacity inside densely populated leaves") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CountingCullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 48;
	Item items[COUNT];
	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		// A dense cluster spanning both BVH trees, with no internal filtering.
		tree.create(&items[i], true, uint32_t(i & 1), 3, Rect2(0, 0, 4, 4));
	}

	Item *result[1] = { nullptr };
	CountingCullTest::calls = 0;
	CHECK(tree.cull_aabb(Rect2(-1, -1, 6, 6), result, 1, nullptr) == 1);
	CHECK(result[0] != nullptr);
	CHECK(CountingCullTest::calls == 1);

	result[0] = nullptr;
	CountingCullTest::calls = 0;
	CHECK(tree.cull_segment(Vector2(-1, 2), Vector2(5, 2), result, 1, nullptr) == 1);
	CHECK(result[0] != nullptr);
	CHECK(CountingCullTest::calls == 1);
}

TEST_CASE("[BVH] 3D point culls stop at result capacity") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CountingCullTest, AABB, Vector3, false>;
	Tree tree;
	constexpr int COUNT = 48;
	Item items[COUNT];
	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		tree.create(&items[i], true, uint32_t(i & 1), 3, AABB(Vector3(0, 0, 0), Vector3(4, 4, 4)));
	}

	Item *result[1] = { nullptr };
	CountingCullTest::calls = 0;
	CHECK(tree.cull_point(Vector3(2, 2, 2), result, 1, nullptr) == 1);
	CHECK(result[0] != nullptr);
	CHECK(CountingCullTest::calls == 1);
}

TEST_CASE("[BVH] 3D convex culls stop at requested result capacity") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CountingCullTest, AABB, Vector3, false>;
	Tree tree;
	constexpr int COUNT = 48;
	Item items[COUNT];
	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		tree.create(&items[i], true, uint32_t(i & 1), 3, AABB(Vector3(0, 0, 0), Vector3(4, 4, 4)));
	}

	// Six outward-facing planes enclosing every AABB in both trees.
	Vector<Plane> hull;
	hull.push_back(Plane(Vector3(1, 0, 0), 10));
	hull.push_back(Plane(Vector3(-1, 0, 0), 10));
	hull.push_back(Plane(Vector3(0, 1, 0), 10));
	hull.push_back(Plane(Vector3(0, -1, 0), 10));
	hull.push_back(Plane(Vector3(0, 0, 1), 10));
	hull.push_back(Plane(Vector3(0, 0, -1), 10));

	Item *results[3] = { nullptr, nullptr, nullptr };
	CountingCullTest::calls = 0;
	CHECK(tree.cull_convex(hull, results, 1, nullptr) == 1);
	CHECK(results[0] != nullptr);
	CHECK(CountingCullTest::calls == 1);

	CountingCullTest::calls = 0;
	CHECK(tree.cull_convex(hull, results, 3, nullptr) == 3);
	CHECK(results[0] != nullptr);
	CHECK(results[1] != nullptr);
	CHECK(results[2] != nullptr);
	CHECK(CountingCullTest::calls == 3);

	CountingCullTest::calls = 0;
	CHECK(tree.cull_convex(hull, results, 0, nullptr) == 0);
	CHECK(CountingCullTest::calls == 0);
}


TEST_CASE("[BVH] Deferred compound insertion reports pairs on flush") {
	using Tree = BVH_Manager<Item, 2, true, 16, CountingPairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	CountingPairTest::allow = true;
	CountingPairTest::calls = 0;
	int created = 0;
	int removed = 0;
	tree.set_pair_callback(count_pair, &created);
	tree.set_unpair_callback(count_unpair, &removed);

	Item a, b, distant;
	// Static A versus dynamic B; both participate in spatial queries even
	// before pairing is finalized.
	const BVHHandle ha = tree.create(&a, true, 0, 2, Rect2(0, 0, 2, 2), 0, true);
	const BVHHandle hb = tree.create(&b, true, 1, 3, Rect2(1, 0, 2, 2), 0, true);
	const BVHHandle hc = tree.create(&distant, true, 1, 3, Rect2(30, 0, 2, 2), 0, true);
	CHECK(created == 0);
	CHECK(CountingPairTest::calls == 0);
	Item *results[3] = {};
	CHECK(tree.cull_aabb(Rect2(-1, -1, 8, 8), results, 3, nullptr) == 2);

	tree.flush_pending_pairs();
	CHECK(created == 1);
	CHECK(CountingPairTest::calls == 1);
	tree.flush_pending_pairs();
	CHECK(created == 1);

	// A normal (nondeferred) insertion still triggers callbacks immediately.
	Item immediate;
	const BVHHandle hd = tree.create(&immediate, true, 1, 3, Rect2(1.5, 0, 2, 2));
	CHECK(created == 3);
	tree.erase(hd);
	CHECK(removed == 2);
	tree.erase(hb);
	CHECK(removed == 3);
	tree.erase(hc);
	tree.erase(ha);
}

TEST_CASE("[BVH] Deferred 3D insertion and removal before flush") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	int created = 0;
	int removed = 0;
	tree.set_pair_callback(count_pair, &created);
	tree.set_unpair_callback(count_unpair, &removed);

	Item a, b, c;
	const BVHHandle ha = tree.create(&a, true, 0, 2, AABB(Vector3(0, 0, 0), Vector3(2, 2, 2)), 0, true);
	const BVHHandle hb = tree.create(&b, true, 1, 3, AABB(Vector3(1, 0, 0), Vector3(2, 2, 2)), 0, true);
	CHECK(created == 0);
	tree.flush_pending_pairs();
	CHECK(created == 1);

	// A deferred item may be erased without leaving a stale changed handle.
	const BVHHandle hc = tree.create(&c, true, 1, 3, AABB(Vector3(1, 0, 0), Vector3(2, 2, 2)), 0, true);
	CHECK(created == 1);
	tree.erase(hc);
	CHECK(created == 1);
	tree.flush_pending_pairs();
	CHECK(created == 1);
	tree.erase(hb);
	tree.erase(ha);
	CHECK(removed == 1);
}
struct StreamCastStats {
	int callbacks = 0;
	int nearest_item = -1;
	real_t ray_length = 0.0;
};

static real_t _stream_all_casts(Item *, int, real_t p_max_fraction, void *p_userdata) {
	static_cast<StreamCastStats *>(p_userdata)->callbacks++;
	return p_max_fraction;
}

static real_t _stream_nearest_cast(Item *p_item, int, real_t p_max_fraction, void *p_userdata) {
	StreamCastStats &stats = *static_cast<StreamCastStats *>(p_userdata);
	stats.callbacks++;
	// The exact hit is at the middle of this item's unit-width AABB.
	const real_t fraction = (p_item->value * 4.0 + 2.5) / stats.ray_length;
	if (fraction <= p_max_fraction && (stats.nearest_item < 0 || fraction < (stats.nearest_item * 4.0 + 2.5) / stats.ray_length)) {
		stats.nearest_item = p_item->value;
		return fraction;
	}
	return p_max_fraction;
}

TEST_CASE("[BVH] Streaming segment ray visits more than 2048 2D candidates and clips closest") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 4096;
	Item items[COUNT];
	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		tree.create(&items[i], true, uint32_t(i & 1), 3, Rect2(i * 4, 0, 1, 1), i & 3);
	}

	const Vector2 from(-2, 0.5);
	const Vector2 to(COUNT * 4 + 2, 0.5);
	StreamCastStats stats;
	tree.cast_segment(from, to, _stream_all_casts, &stats);
	CHECK(stats.callbacks == COUNT);

	stats = StreamCastStats();
	tree.cast_segment(from, to, _stream_all_casts, &stats, 1);
	CHECK(stats.callbacks == COUNT / 2);

	stats = StreamCastStats();
	stats.ray_length = to.x - from.x;
	tree.cast_segment(from, to, _stream_nearest_cast, &stats);
	CHECK(stats.nearest_item == 0);
	CHECK(stats.callbacks > 0);
}

TEST_CASE("[BVH] Streaming 3D segment ray spans multiple trees and preserves closest hit") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	constexpr int COUNT = 4096;
	Item items[COUNT];
	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		tree.create(&items[i], true, uint32_t(i & 1), 3, AABB(Vector3(i * 4, 0, 0), Vector3(1, 1, 1)));
	}

	const Vector3 from(-2, 0.5, 0.5);
	const Vector3 to(COUNT * 4 + 2, 0.5, 0.5);
	StreamCastStats stats;
	tree.cast_segment(from, to, _stream_all_casts, &stats);
	CHECK(stats.callbacks == COUNT);

	stats = StreamCastStats();
	stats.ray_length = to.x - from.x;
	tree.cast_segment(from, to, _stream_nearest_cast, &stats);
	CHECK(stats.nearest_item == 0);
	CHECK(stats.callbacks > 0);
}


TEST_CASE("[BVH] Bulk insertion of independent 2D bodies preserves every adjacent pair") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 96;
	Item items[COUNT];
	BVHHandle handles[COUNT];
	int created = 0;
	int removed = 0;
	tree.set_pair_callback(count_pair, &created);
	tree.set_unpair_callback(count_unpair, &removed);

	// Every adjacent pair overlaps; all more distant pairs are separated.
	// Alternate between two trees to exercise cross-tree pair generation.
	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, uint32_t(i & 1), 3,
				Rect2(real_t(i) * real_t(1.5), 0, 2, 2), 0, true);
	}
	CHECK(created == 0);
	tree.flush_pending_pairs();
	CHECK(created == COUNT - 1);
	tree.update();
	CHECK(created == COUNT - 1);

	for (int i = 0; i < COUNT; i++) {
		tree.erase(handles[i]);
	}
	CHECK(removed == COUNT - 1);
}

} // namespace TestBVH
