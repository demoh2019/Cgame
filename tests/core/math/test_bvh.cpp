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
	// Spatially ordered branches should avoid invoking the narrowphase on
	// thousands of farther objects before finding the closest body.
	CHECK(stats.callbacks > 0);
	CHECK(stats.callbacks < COUNT / 4);
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
	// Spatially ordered branches should avoid invoking the narrowphase on
	// thousands of farther objects before finding the closest body.
	CHECK(stats.callbacks > 0);
	CHECK(stats.callbacks < COUNT / 4);
}


struct BatchAdjacentPairRecorder {
	int total = 0;
	int non_adjacent = 0;
	int adjacent[95] = {};
};

static void *record_adjacent_pair(void *p_userdata, uint32_t, Item *p_a, int, uint32_t, Item *p_b, int) {
	BatchAdjacentPairRecorder *recorder = static_cast<BatchAdjacentPairRecorder *>(p_userdata);
	const int first = MIN(p_a->value, p_b->value);
	const int last = MAX(p_a->value, p_b->value);
	recorder->total++;
	if (last - first == 1 && first >= 0 && first < 95) {
		recorder->adjacent[first]++;
	} else {
		recorder->non_adjacent++;
	}
	return nullptr;
}

TEST_CASE("[BVH] Bulk insertion of independent 2D bodies preserves every adjacent pair") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 96;
	Item items[COUNT];
	BVHHandle handles[COUNT];
	BatchAdjacentPairRecorder recorder;
	int removed = 0;
	tree.set_pair_callback(record_adjacent_pair, &recorder);
	tree.set_unpair_callback(count_unpair, &removed);

	// Every adjacent pair overlaps; all more distant pairs are separated.
	// Alternate between two trees to exercise cross-tree pair generation.
	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, uint32_t(i & 1), 3,
				Rect2(real_t(i) * real_t(1.5), 0, 2, 2), 0, true);
	}
	CHECK(recorder.total == 0);
	tree.flush_pending_pairs();
	CHECK(recorder.total == COUNT - 1);
	CHECK(recorder.non_adjacent == 0);
	for (int i = 0; i < COUNT - 1; i++) {
		CHECK(recorder.adjacent[i] == 1);
	}
	tree.update();
	CHECK(recorder.total == COUNT - 1);

	for (int i = 0; i < COUNT; i++) {
		tree.erase(handles[i]);
	}
	CHECK(removed == COUNT - 1);
}


TEST_CASE("[BVH] Bulk insertion of independent 3D bodies preserves adjacent pairs") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	constexpr int COUNT = 96;
	Item items[COUNT];
	BVHHandle handles[COUNT];
	BatchAdjacentPairRecorder recorder;
	int removed = 0;
	tree.set_pair_callback(record_adjacent_pair, &recorder);
	tree.set_unpair_callback(count_unpair, &removed);

	for (int i = 0; i < COUNT; i++) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, uint32_t(i & 1), 3,
				AABB(Vector3(real_t(i) * real_t(1.5), 0, 0), Vector3(2, 2, 2)), 0, true);
	}
	CHECK(recorder.total == 0);
	tree.flush_pending_pairs();
	CHECK(recorder.total == COUNT - 1);
	CHECK(recorder.non_adjacent == 0);
	for (int i = 0; i < COUNT - 1; i++) {
		CHECK(recorder.adjacent[i] == 1);
	}
	tree.update();
	CHECK(recorder.total == COUNT - 1);

	for (int i = 0; i < COUNT; i++) {
		tree.erase(handles[i]);
	}
	CHECK(removed == COUNT - 1);
}


struct RayCallbackOrder {
	int count = 0;
	int first = -1;
};

static real_t _record_stream_order(Item *p_item, int, real_t p_max_fraction, void *p_userdata) {
	RayCallbackOrder &stats = *static_cast<RayCallbackOrder *>(p_userdata);
	if (stats.count++ == 0) {
		stats.first = p_item->value;
	}
	return p_max_fraction;
}

TEST_CASE("[BVH] Ray casts visit the nearer of two separate BVH trees first") {
	// The far proxy is in tree 0 and the near proxy in tree 1.
	// Both roots overlap the long ray but an arbitrary tree order would
	// trigger expensive shape tests on the far proxy first.
	using Tree2D = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree2D tree2d;
	Item far_item;
	far_item.value = 1;
	Item near_item;
	near_item.value = 2;
	tree2d.create(&far_item, true, 0, 3, Rect2(100, 0, 2, 2));
	tree2d.create(&near_item, true, 1, 3, Rect2(1, 0, 2, 2));
	RayCallbackOrder order;
	tree2d.cast_segment(Vector2(0, 1), Vector2(104, 1), _record_stream_order, &order);
	CHECK(order.count == 2);
	CHECK(order.first == 2);

	using Tree3D = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree3D tree3d;
	tree3d.create(&far_item, true, 0, 3, AABB(Vector3(100, 0, 0), Vector3(2, 2, 2)));
	tree3d.create(&near_item, true, 1, 3, AABB(Vector3(1, 0, 0), Vector3(2, 2, 2)));
	order = RayCallbackOrder();
	tree3d.cast_segment(Vector3(0, 1, 1), Vector3(104, 1, 1), _record_stream_order, &order);
	CHECK(order.count == 2);
	CHECK(order.first == 2);
}

TEST_CASE("[BVH] Axis-aligned and reversed streaming rays retain intersection results") {
	using Tree2D = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree2D tree2d;
	Item central;
	central.value = 7;
	Item outside;
	outside.value = 9;
	tree2d.create(&central, true, 0, 3, Rect2(-1, -1, 2, 2));
	tree2d.create(&outside, true, 1, 3, Rect2(10, 10, 2, 2));

	RayCallbackOrder order;
	tree2d.cast_segment(Vector2(0, -5), Vector2(0, 5), _record_stream_order, &order);
	CHECK(order.count == 1);
	CHECK(order.first == 7);
	order = RayCallbackOrder();
	tree2d.cast_segment(Vector2(0, 5), Vector2(0, -5), _record_stream_order, &order);
	CHECK(order.count == 1);
	CHECK(order.first == 7);

	using Tree3D = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree3D tree3d;
	tree3d.create(&central, true, 0, 3, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)));
	tree3d.create(&outside, true, 1, 3, AABB(Vector3(10, 10, 10), Vector3(2, 2, 2)));
	order = RayCallbackOrder();
	tree3d.cast_segment(Vector3(0, -5, 0), Vector3(0, 5, 0), _record_stream_order, &order);
	CHECK(order.count == 1);
	CHECK(order.first == 7);
	order = RayCallbackOrder();
	tree3d.cast_segment(Vector3(0, 5, 0), Vector3(0, -5, 0), _record_stream_order, &order);
	CHECK(order.count == 1);
	CHECK(order.first == 7);
}


struct DensePairCounts {
	int created = 0;
	int removed = 0;
	int invalid_userdata = 0;
};

static void *dense_pair_created(void *p_userdata, uint32_t, Item *, int, uint32_t, Item *, int) {
	DensePairCounts *counts = static_cast<DensePairCounts *>(p_userdata);
	counts->created++;
	return p_userdata;
}

static void dense_pair_removed(void *p_userdata, uint32_t, Item *, int, uint32_t, Item *, int, void *p_pair_userdata) {
	DensePairCounts *counts = static_cast<DensePairCounts *>(p_userdata);
	counts->removed++;
	if (p_pair_userdata != p_userdata) {
		counts->invalid_userdata++;
	}
}

TEST_CASE("[BVH] Pair graph stores only the authoritative adjacency vector size") {
	using Pairs2D = BVH_Tree<Item, 2, 2, 16, PairTest, CullTest, true, Rect2, Vector2>::ItemPairs;
	using Pairs3D = BVH_Tree<Item, 2, 2, 16, PairTest, CullTest, true, AABB, Vector3>::ItemPairs;

	// No extra per-object pair counter or alignment gap. The vector already
	// owns an authoritative count and adjacency links remain externally stored.
	CHECK(sizeof(Pairs2D) == sizeof(Rect2) + sizeof(LocalVector<Pairs2D::Link>));
	CHECK(sizeof(Pairs3D) == sizeof(AABB) + sizeof(LocalVector<Pairs3D::Link>));
}

TEST_CASE("[BVH] Dense contact graph survives pair deletion and handle reuse") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 32;
	Item items[COUNT + 1];
	BVHHandle handles[COUNT];
	DensePairCounts counts;

	tree.set_pair_callback(dense_pair_created, &counts);
	tree.set_unpair_callback(dense_pair_removed, &counts);

	for (int i = 0; i < COUNT; ++i) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, uint32_t(i & 1), 3, Rect2(0, 0, 4, 4), 0, true);
	}
	CHECK(counts.created == 0);
	tree.flush_pending_pairs();

	constexpr int TOTAL_PAIRS = COUNT * (COUNT - 1) / 2;
	CHECK(counts.created == TOTAL_PAIRS);
	CHECK(counts.removed == 0);
	tree.update();
	CHECK(counts.created == TOTAL_PAIRS);

	constexpr int REPLACED = COUNT / 2;
	tree.erase(handles[REPLACED]);
	CHECK(counts.removed == COUNT - 1);

	items[COUNT].value = COUNT;
	const BVHHandle replacement = tree.create(&items[COUNT], true, uint32_t(REPLACED & 1), 3, Rect2(0, 0, 4, 4));
	CHECK(counts.created == TOTAL_PAIRS + COUNT - 1);
	tree.update();
	CHECK(counts.created == TOTAL_PAIRS + COUNT - 1);

	for (int i = 0; i < COUNT; ++i) {
		if (i != REPLACED) {
			tree.erase(handles[i]);
		}
	}
	tree.erase(replacement);
	CHECK(counts.removed == counts.created);
	CHECK(counts.invalid_userdata == 0);
}


TEST_CASE("[BVH] High-bit tree masks keep 32nd-layer pairs and culls consistent") {
	using Tree = BVH_Manager<Item, 32, true, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	Item low_layer;
	Item high_layer;
	int paired = 0;
	int unpaired = 0;
	tree.set_pair_callback(count_pair, &paired);
	tree.set_unpair_callback(count_unpair, &unpaired);

	constexpr uint32_t HIGH_BIT = uint32_t(1) << 31;
	const Rect2 bounds(0, 0, 4, 4);
	const BVHHandle low = tree.create(&low_layer, true, 0, HIGH_BIT, bounds);
	const BVHHandle high = tree.create(&high_layer, true, 31, uint32_t(1), bounds);
	CHECK(paired == 1);
	CHECK(unpaired == 0);

	Item *hits[2] = {};
	CHECK(tree.cull_aabb(bounds, hits, 2, nullptr, HIGH_BIT) == 1);
	CHECK(hits[0] == &high_layer);
	CHECK(tree.cull_aabb(bounds, hits, 2, nullptr, uint32_t(1)) == 1);
	CHECK(hits[0] == &low_layer);

	// A one-sided tree mask is still compatible; disabling both removes
	// the pair even when one side uses the sign bit of uint32_t.
	tree.set_tree(low, 0, 0, true);
	CHECK(paired == 1);
	CHECK(unpaired == 0);
	tree.set_tree(high, 31, 0, true);
	CHECK(unpaired == 1);

	tree.set_tree(low, 0, HIGH_BIT, true);
	CHECK(paired == 2);
	CHECK(unpaired == 1);

	tree.erase(high);
	CHECK(unpaired == 2);
	tree.erase(low);
	CHECK(unpaired == 2);
}


TEST_CASE("[BVH] Empty tree masks and zero-capacity queries skip all candidates") {
	using Tree = BVH_Manager<Item, 2, false, 16, PairTest, CullTest, AABB, Vector3, false>;
	Tree tree;
	Item item;
	tree.create(&item, true, 0, 3, AABB(Vector3(0, 0, 0), Vector3(4, 4, 4)));
	const AABB bounds(Vector3(-1, -1, -1), Vector3(6, 6, 6));
	const Vector3 from(-2, 2, 2);
	const Vector3 to(6, 2, 2);
	Item *hits[1] = { nullptr };

	Vector<Plane> hull;
	hull.push_back(Plane(Vector3(1, 0, 0), 10));
	hull.push_back(Plane(Vector3(-1, 0, 0), 10));
	hull.push_back(Plane(Vector3(0, 1, 0), 10));
	hull.push_back(Plane(Vector3(0, -1, 0), 10));
	hull.push_back(Plane(Vector3(0, 0, 1), 10));
	hull.push_back(Plane(Vector3(0, 0, -1), 10));

	CHECK(tree.cull_aabb(bounds, hits, 1, nullptr, 0) == 0);
	CHECK(tree.cull_segment(from, to, hits, 1, nullptr, 0) == 0);
	CHECK(tree.cull_point(Vector3(2, 2, 2), hits, 1, nullptr, 0) == 0);
	CHECK(tree.cull_convex(hull, hits, 1, nullptr, 0) == 0);
	CHECK(hits[0] == nullptr);

	CHECK(tree.cull_aabb(bounds, hits, 0, nullptr) == 0);
	CHECK(tree.cull_segment(from, to, hits, 0, nullptr) == 0);
	CHECK(tree.cull_point(Vector3(2, 2, 2), hits, 0, nullptr) == 0);
	CHECK(tree.cull_convex(hull, hits, 0, nullptr) == 0);
	CHECK(hits[0] == nullptr);

	StreamCastStats stats;
	tree.cast_segment(from, to, _stream_all_casts, &stats, 0);
	CHECK(stats.callbacks == 0);
	// A normal query must still find the same item.
	CHECK(tree.cull_aabb(bounds, hits, 1, nullptr, 1) == 1);
	CHECK(hits[0] == &item);
}


TEST_CASE("[BVH] Dense 2D contact churn removes known adjacency links without double callbacks") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, Rect2, Vector2, false>;
	constexpr int COUNT = 24;
	Item items[COUNT];
	BVHHandle handles[COUNT];
	DensePairCounts counts;
	Tree tree;
	tree.set_pair_callback(dense_pair_created, &counts);
	tree.set_unpair_callback(dense_pair_removed, &counts);

	for (int i = 0; i < COUNT; ++i) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, uint32_t(i & 1), 3, Rect2(0, 0, 4, 4), 0, true);
	}
	tree.flush_pending_pairs();
	constexpr int TOTAL_PAIRS = COUNT * (COUNT - 1) / 2;
	CHECK(counts.created == TOTAL_PAIRS);

	// A low, high and middle handle exercise both branches of _unpair
	// after its handles have been sorted.
	const int moved_ids[] = { 0, COUNT - 1, COUNT / 2 };
	for (int iteration = 0; iteration < 3; ++iteration) {
		const int index = moved_ids[iteration];
		tree.move(handles[index], Rect2(100 + iteration * 10, 0, 4, 4));
		tree.update();
		CHECK(counts.removed == (iteration + 1) * (COUNT - 1));
		CHECK(counts.created == TOTAL_PAIRS + iteration * (COUNT - 1));

		tree.move(handles[index], Rect2(0, 0, 4, 4));
		tree.update();
		CHECK(counts.created == TOTAL_PAIRS + (iteration + 1) * (COUNT - 1));
		CHECK(counts.removed == (iteration + 1) * (COUNT - 1));
		tree.update();
		CHECK(counts.created == TOTAL_PAIRS + (iteration + 1) * (COUNT - 1));
	}

	for (const BVHHandle &handle : handles) {
		tree.erase(handle);
	}
	CHECK(counts.removed == counts.created);
	CHECK(counts.invalid_userdata == 0);
}

TEST_CASE("[BVH] Dense 3D contact churn preserves pair userdata") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, AABB, Vector3, false>;
	constexpr int COUNT = 12;
	Item items[COUNT];
	BVHHandle handles[COUNT];
	DensePairCounts counts;
	Tree tree;
	tree.set_pair_callback(dense_pair_created, &counts);
	tree.set_unpair_callback(dense_pair_removed, &counts);

	for (int i = 0; i < COUNT; ++i) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, uint32_t(i & 1), 3,
				AABB(Vector3(0, 0, 0), Vector3(4, 4, 4)), 0, true);
	}
	tree.flush_pending_pairs();
	constexpr int TOTAL_PAIRS = COUNT * (COUNT - 1) / 2;
	CHECK(counts.created == TOTAL_PAIRS);
	for (int iteration = 0; iteration < 2; ++iteration) {
		const int index = iteration == 0 ? 0 : COUNT - 1;
		tree.move(handles[index], AABB(Vector3(100, 0, 0), Vector3(4, 4, 4)));
		tree.update();
		CHECK(counts.removed == (iteration + 1) * (COUNT - 1));
		tree.move(handles[index], AABB(Vector3(0, 0, 0), Vector3(4, 4, 4)));
		tree.update();
		CHECK(counts.created == TOTAL_PAIRS + (iteration + 1) * (COUNT - 1));
	}
	for (const BVHHandle &handle : handles) {
		tree.erase(handle);
	}
	CHECK(counts.removed == counts.created);
	CHECK(counts.invalid_userdata == 0);
}

template <typename Pairs>
static void _exercise_compact_pair_links() {
	Pairs pairs;
	int payload = 42;
	CHECK(pairs.extended_pairs.get_capacity() == 0);

	BVHHandle first;
	first.set_id(7);
	pairs.add_pair_to(first, &payload);
	CHECK(pairs.extended_pairs.size() == 1);
	CHECK(pairs.extended_pairs.get_capacity() == 1);
	CHECK(pairs.contains_pair_to(first));
	CHECK(pairs.remove_pair_at(0) == &payload);
	CHECK(pairs.extended_pairs.is_empty());
	// Retain the single-slot allocation for low-degree contact churn.
	CHECK(pairs.extended_pairs.get_capacity() == 1);

	// Dense, temporary contact clusters release their large retained buffers
	// once the last link is removed.
	constexpr uint32_t DENSE_COUNT = 32;
	for (uint32_t i = 0; i < DENSE_COUNT; ++i) {
		BVHHandle h;
		h.set_id(i + 10);
		pairs.add_pair_to(h, &payload);
	}
	CHECK(pairs.extended_pairs.size() == DENSE_COUNT);
	CHECK(pairs.extended_pairs.get_capacity() > 8);
	for (uint32_t i = 0; i < DENSE_COUNT; ++i) {
		CHECK(pairs.remove_pair_at(0) == &payload);
	}
	CHECK(pairs.extended_pairs.is_empty());
	CHECK(pairs.extended_pairs.get_capacity() == 0);

	pairs.add_pair_to(first, &payload);
	CHECK(pairs.extended_pairs.get_capacity() == 1);
	CHECK(pairs.remove_pair_to(first) == &payload);
	CHECK(pairs.extended_pairs.is_empty());
	pairs.clear();
	CHECK(pairs.extended_pairs.get_capacity() == 0);
}

TEST_CASE("[BVH] Sparse and dense adjacency buffers use adaptive contact storage") {
	using Pairs2D = BVH_Tree<Item, 2, 2, 16, PairTest, CullTest, true, Rect2, Vector2>::ItemPairs;
	using Pairs3D = BVH_Tree<Item, 2, 2, 16, PairTest, CullTest, true, AABB, Vector3>::ItemPairs;
	_exercise_compact_pair_links<Pairs2D>();
	_exercise_compact_pair_links<Pairs3D>();
}

template <typename Pairs>
static void _exercise_partial_contact_buffer_shrink() {
	Pairs pairs;
	constexpr uint32_t COUNT = 128;
	int userdata[COUNT] = {};
	for (uint32_t i = 0; i < COUNT; ++i) {
		BVHHandle handle;
		handle.set_id(i + 1);
		userdata[i] = int(i);
		pairs.add_pair_to(handle, &userdata[i]);
	}
	const uint32_t peak_capacity = pairs.extended_pairs.get_capacity();
	CHECK(peak_capacity >= COUNT);

	// A dense cluster can shrink to a few contacts without becoming empty.
	for (uint32_t i = 0; i < COUNT - 8; ++i) {
		BVHHandle handle;
		handle.set_id(i + 1);
		CHECK(pairs.remove_pair_to(handle) == &userdata[i]);
	}
	CHECK(pairs.extended_pairs.size() == 8);
	CHECK(pairs.extended_pairs.get_capacity() < peak_capacity);
	CHECK(pairs.extended_pairs.get_capacity() >= pairs.extended_pairs.size());
	CHECK(pairs.extended_pairs.get_capacity() <= 64);

	for (uint32_t i = COUNT - 8; i < COUNT; ++i) {
		BVHHandle handle;
		handle.set_id(i + 1);
		CHECK(pairs.contains_pair_to(handle));
		CHECK(pairs.remove_pair_to(handle) == &userdata[i]);
	}
	CHECK(pairs.extended_pairs.is_empty());
	CHECK(pairs.extended_pairs.get_capacity() <= 8);
}

TEST_CASE("[BVH] Partially dissolved dense clusters release excess adjacency memory") {
	using Pairs2D = BVH_Tree<Item, 2, 2, 16, PairTest, CullTest, true, Rect2, Vector2>::ItemPairs;
	using Pairs3D = BVH_Tree<Item, 2, 2, 16, PairTest, CullTest, true, AABB, Vector3>::ItemPairs;
	_exercise_partial_contact_buffer_shrink<Pairs2D>();
	_exercise_partial_contact_buffer_shrink<Pairs3D>();
}

TEST_CASE("[BVH] Star-shaped 2D contact graph retains surviving pairs during churn") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int LEAVES = 96;
	Item center;
	Item leaves[LEAVES];
	BVHHandle handles[LEAVES];
	DensePairCounts counts;
	tree.set_pair_callback(dense_pair_created, &counts);
	tree.set_unpair_callback(dense_pair_removed, &counts);
	const BVHHandle central_handle = tree.create(&center, true, 0, 2, Rect2(0, 0, 200, 4), 0, true);
	for (int i = 0; i < LEAVES; ++i) {
		leaves[i].value = i;
		handles[i] = tree.create(&leaves[i], true, 1, 1, Rect2(real_t(i * 2), 1, 1, 1), 0, true);
	}
	tree.flush_pending_pairs();
	CHECK(counts.created == LEAVES);
	CHECK(counts.removed == 0);

	for (int i = 8; i < LEAVES; ++i) {
		tree.move(handles[i], Rect2(real_t(i * 2), 20, 1, 1));
	}
	tree.update();
	CHECK(counts.created == LEAVES);
	CHECK(counts.removed == LEAVES - 8);
	CHECK(counts.invalid_userdata == 0);

	for (int i = 8; i < LEAVES; ++i) {
		tree.move(handles[i], Rect2(real_t(i * 2), 1, 1, 1));
	}
	tree.update();
	CHECK(counts.created == LEAVES * 2 - 8);
	CHECK(counts.removed == LEAVES - 8);

	for (const BVHHandle &handle : handles) {
		tree.erase(handle);
	}
	tree.erase(central_handle);
	CHECK(counts.removed == counts.created);
	CHECK(counts.invalid_userdata == 0);
}

TEST_CASE("[BVH] Batch flush filters only new 2D contact pairs") {
	using Tree = BVH_Manager<Item, 2, true, 16, CountingPairTest, CullTest, Rect2, Vector2, false>;
	CountingPairTest::calls = 0;
	CountingPairTest::allow = true;
	Tree tree;
	Item a, b, c;
	int created = 0;
	int removed = 0;
	tree.set_pair_callback(count_pair, &created);
	tree.set_unpair_callback(count_unpair, &removed);

	const BVHHandle ha = tree.create(&a, true, 0, 3, Rect2(0, 0, 4, 4));
	const BVHHandle hb = tree.create(&b, true, 1, 3, Rect2(1, 0, 4, 4));
	CHECK(created == 1);
	const int prior_checks = CountingPairTest::calls;

	// Both a moved and c was just inserted, but a-b is an existing contact.
	tree.move(ha, Rect2(0.5, 0, 4, 4));
	const BVHHandle hc = tree.create(&c, true, 1, 3, Rect2(2, 0, 4, 4), 0, true);
	CHECK(created == 1);
	tree.flush_pending_pairs();
	CHECK(created == 3);
	CHECK(removed == 0);
	CHECK(CountingPairTest::calls == prior_checks + 2);
	tree.flush_pending_pairs();
	CHECK(CountingPairTest::calls == prior_checks + 2);

	// Explicit full checks must still re-evaluate changed collision filters.
	CountingPairTest::allow = false;
	tree.force_collision_check(ha);
	CHECK(removed == 2);
	CountingPairTest::allow = true;
	tree.force_collision_check(ha);
	CHECK(created == 5);

	tree.erase(hc);
	tree.erase(hb);
	tree.erase(ha);
	CHECK(removed == created);
}

TEST_CASE("[BVH] Batch flush filters only new 3D contact pairs") {
	using Tree = BVH_Manager<Item, 2, true, 16, CountingPairTest, CullTest, AABB, Vector3, false>;
	CountingPairTest::calls = 0;
	CountingPairTest::allow = true;
	Tree tree;
	Item a, b, c;
	int created = 0;
	int removed = 0;
	tree.set_pair_callback(count_pair, &created);
	tree.set_unpair_callback(count_unpair, &removed);

	const BVHHandle ha = tree.create(&a, true, 0, 3, AABB(Vector3(0, 0, 0), Vector3(4, 4, 4)));
	const BVHHandle hb = tree.create(&b, true, 1, 3, AABB(Vector3(1, 0, 0), Vector3(4, 4, 4)));
	CHECK(created == 1);
	const int prior_checks = CountingPairTest::calls;
	tree.move(ha, AABB(Vector3(0.5, 0, 0), Vector3(4, 4, 4)));
	const BVHHandle hc = tree.create(&c, true, 1, 3, AABB(Vector3(2, 0, 0), Vector3(4, 4, 4)), 0, true);
	tree.flush_pending_pairs();
	CHECK(created == 3);
	CHECK(removed == 0);
	CHECK(CountingPairTest::calls == prior_checks + 2);

	tree.erase(hc);
	tree.erase(hb);
	tree.erase(ha);
	CHECK(removed == created);
}


template <typename Bounds, typename Point>
static void _exercise_dense_pair_index(const Bounds &p_overlap, const Bounds &p_far) {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, Bounds, Point, false>;
	Tree tree;
	constexpr int COUNT = 40;
	constexpr int REMOVED = 11; // Drop all remaining degrees below the dense threshold.
	Item items[COUNT + REMOVED];
	BVHHandle handles[COUNT];
	DensePairCounts counts;
	tree.set_pair_callback(dense_pair_created, &counts);
	tree.set_unpair_callback(dense_pair_removed, &counts);

	for (int i = 0; i < COUNT; ++i) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, uint32_t(i & 1), 3, p_overlap, 0, true);
	}
	CHECK(counts.created == 0);
	tree.flush_pending_pairs();
	constexpr int INITIAL_PAIRS = COUNT * (COUNT - 1) / 2;
	CHECK(counts.created == INITIAL_PAIRS);
	CHECK(counts.removed == 0);

	// All pairs must be recognized as already present, even if both
	// participants have crossed the hash-index threshold.
	for (int i = 0; i < COUNT; ++i) {
		tree.force_collision_check(handles[i]);
	}
	tree.update();
	CHECK(counts.created == INITIAL_PAIRS);
	CHECK(counts.removed == 0);

	// Replacing handles tests dense-to-sparse index removal and stale-key
	// cleanup when freed IDs become available for reuse.
	for (int i = 0; i < REMOVED; ++i) {
		tree.erase(handles[i]);
	}
	constexpr int REMAINING = COUNT - REMOVED;
	constexpr int SURVIVING_PAIRS = REMAINING * (REMAINING - 1) / 2;
	CHECK(counts.removed == INITIAL_PAIRS - SURVIVING_PAIRS);
	for (int i = REMOVED; i < COUNT; ++i) {
		tree.force_collision_check(handles[i]);
	}
	CHECK(counts.created == INITIAL_PAIRS);

	for (int i = 0; i < REMOVED; ++i) {
		items[COUNT + i].value = COUNT + i;
		handles[i] = tree.create(&items[COUNT + i], true, uint32_t(i & 1), 3, p_overlap, 0, true);
	}
	tree.flush_pending_pairs();
	CHECK(counts.created == INITIAL_PAIRS + (INITIAL_PAIRS - SURVIVING_PAIRS));
	for (int i = 0; i < COUNT; ++i) {
		tree.force_collision_check(handles[i]);
	}
	CHECK(counts.created == INITIAL_PAIRS + (INITIAL_PAIRS - SURVIVING_PAIRS));

	// Move one dense body away and back through the index threshold.
	tree.move(handles[0], p_far);
	tree.update();
	CHECK(counts.removed == (INITIAL_PAIRS - SURVIVING_PAIRS) + (COUNT - 1));
	tree.move(handles[0], p_overlap);
	tree.update();
	CHECK(counts.created == INITIAL_PAIRS + (INITIAL_PAIRS - SURVIVING_PAIRS) + (COUNT - 1));

	for (const BVHHandle &handle : handles) {
		tree.erase(handle);
	}
	CHECK(counts.removed == counts.created);
	CHECK(counts.invalid_userdata == 0);
}

TEST_CASE("[BVH] Dense pair hash index preserves 2D contacts across threshold and handle reuse") {
	_exercise_dense_pair_index<Rect2, Vector2>(Rect2(0, 0, 4, 4), Rect2(100, 0, 4, 4));
}

TEST_CASE("[BVH] Dense pair hash index preserves 3D contacts across threshold and handle reuse") {
	_exercise_dense_pair_index<AABB, Vector3>(
			AABB(Vector3(0, 0, 0), Vector3(4, 4, 4)),
			AABB(Vector3(100, 0, 0), Vector3(4, 4, 4)));
}

struct ReciprocalPairStats {
	int created = 0;
	int removed = 0;
	int checked = 0;
	int bad_userdata = 0;
	int initial_token = 13;
	int updated_token = 29;
};

static void *reciprocal_pair_created(void *p_userdata, uint32_t, Item *, int, uint32_t, Item *, int) {
	ReciprocalPairStats *stats = static_cast<ReciprocalPairStats *>(p_userdata);
	stats->created++;
	return &stats->initial_token;
}

static void *reciprocal_pair_checked(void *p_userdata, uint32_t, Item *, int, uint32_t, Item *, int, void *p_pair_userdata) {
	ReciprocalPairStats *stats = static_cast<ReciprocalPairStats *>(p_userdata);
	stats->checked++;
	if (p_pair_userdata != &stats->initial_token && p_pair_userdata != &stats->updated_token) {
		stats->bad_userdata++;
	}
	return &stats->updated_token;
}

static void reciprocal_pair_removed(void *p_userdata, uint32_t, Item *, int, uint32_t, Item *, int, void *p_pair_userdata) {
	ReciprocalPairStats *stats = static_cast<ReciprocalPairStats *>(p_userdata);
	stats->removed++;
	if (p_pair_userdata != &stats->updated_token) {
		stats->bad_userdata++;
	}
}

template <typename Bounds, typename Point>
static void _exercise_reciprocal_pair_links(const Bounds &p_overlap, const Bounds &p_far) {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CullTest, Bounds, Point, false>;
	constexpr int COUNT = 40;
	constexpr int REPLACEMENTS = 8;
	Tree tree;
	Item items[COUNT + REPLACEMENTS];
	BVHHandle handles[COUNT];
	ReciprocalPairStats stats;
	tree.set_pair_callback(reciprocal_pair_created, &stats);
	tree.set_check_pair_callback(reciprocal_pair_checked, &stats);
	tree.set_unpair_callback(reciprocal_pair_removed, &stats);

	for (int i = 0; i < COUNT; ++i) {
		items[i].value = i;
		handles[i] = tree.create(&items[i], true, uint32_t(i & 1), 3, p_overlap, 0, true);
	}
	tree.flush_pending_pairs();
	constexpr int TOTAL = COUNT * (COUNT - 1) / 2;
	CHECK(stats.created == TOTAL);

	// Both copies of every pair's payload must be synchronized by the
	// reciprocal index, even after unordered adjacency swaps.
	auto recheck_all = [&]() {
		for (const BVHHandle &handle : handles) {
			tree.refresh_pair_userdata(handle);
		}
		CHECK(stats.bad_userdata == 0);
	};
	recheck_all();
	CHECK(stats.checked == TOTAL * 2);

	const int replace_indices[REPLACEMENTS] = { 0, COUNT - 1, COUNT / 2, 5, 31, 1, 37, 14 };
	for (int i = 0; i < REPLACEMENTS; ++i) {
		const int replace = replace_indices[i];
		tree.erase(handles[replace]);
		CHECK(stats.removed == (i + 1) * (COUNT - 1));

		items[COUNT + i].value = COUNT + i;
		handles[replace] = tree.create(&items[COUNT + i], true, uint32_t(replace & 1), 3, p_overlap);
		CHECK(stats.created == TOTAL + (i + 1) * (COUNT - 1));
		recheck_all();
	}

	// Force one more unordered-link removal and regeneration without
	// destroying its body; all reciprocal indices must remain consistent.
	tree.move(handles[0], p_far);
	tree.update();
	CHECK(stats.removed == (REPLACEMENTS + 1) * (COUNT - 1));
	tree.move(handles[0], p_overlap);
	tree.update();
	CHECK(stats.created == TOTAL + (REPLACEMENTS + 1) * (COUNT - 1));
	recheck_all();

	for (const BVHHandle &handle : handles) {
		tree.erase(handle);
	}
	CHECK(stats.removed == stats.created);
	CHECK(stats.bad_userdata == 0);
}

TEST_CASE("[BVH] Reciprocal 2D pair indices survive dense removals and handle reuse") {
	_exercise_reciprocal_pair_links<Rect2, Vector2>(Rect2(0, 0, 4, 4), Rect2(100, 0, 4, 4));
}

TEST_CASE("[BVH] Reciprocal 3D pair indices survive dense removals and handle reuse") {
	_exercise_reciprocal_pair_links<AABB, Vector3>(
			AABB(Vector3(0, 0, 0), Vector3(4, 4, 4)),
			AABB(Vector3(100, 0, 0), Vector3(4, 4, 4)));
}

TEST_CASE("[BVH] Reciprocal pair indices fit into the 64-bit contact link") {
	using Pairs2D = BVH_Tree<Item, 2, 2, 16, PairTest, CullTest, true, Rect2, Vector2>::ItemPairs;
	using Pairs3D = BVH_Tree<Item, 2, 2, 16, PairTest, CullTest, true, AABB, Vector3>::ItemPairs;
	if (sizeof(void *) == 8) {
		CHECK(sizeof(Pairs2D::Link) == 16);
		CHECK(sizeof(Pairs3D::Link) == 16);
	}
}


TEST_CASE("[BVH] 2D point and box culls reject empty roots and preserve subtree results") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CountingCullTest, Rect2, Vector2, false>;
	Tree tree;
	constexpr int COUNT = 96;
	Item items[COUNT];
	for (int i = 0; i < COUNT; ++i) {
		items[i].value = i;
		tree.create(&items[i], true, uint32_t(i & 1), 3, Rect2(i * 4, 0, 1, 1));
	}
	Item *results[COUNT] = {};

	// Entirely absent queries must not yield false positives from a leaf.
	CountingCullTest::calls = 0;
	CHECK(tree.cull_aabb(Rect2(0, 1000, 1000, 4), results, COUNT, nullptr) == 0);
	CHECK(tree.cull_point(Vector2(999, 999), results, COUNT, nullptr) == 0);
	CHECK(tree.cull_segment(Vector2(-10, 1000), Vector2(500, 1000), results, COUNT, nullptr) == 0);
	CHECK(CountingCullTest::calls == 0);

	// Fully covering each root should still enumerate each proxy exactly once.
	CountingCullTest::calls = 0;
	CHECK(tree.cull_aabb(Rect2(-2, -2, COUNT * 4 + 4, 6), results, COUNT, nullptr) == COUNT);
	CHECK(CountingCullTest::calls == COUNT);
	bool seen[COUNT] = {};
	for (int i = 0; i < COUNT; ++i) {
		REQUIRE(results[i] != nullptr);
		CHECK(results[i]->value >= 0);
		CHECK(results[i]->value < COUNT);
		seen[results[i]->value] = true;
	}
	for (bool found : seen) {
		CHECK(found);
	}

	CHECK(tree.cull_aabb(Rect2(-2, -2, COUNT * 4 + 4, 6), results, COUNT, nullptr, 1) == COUNT / 2);
	CHECK(tree.cull_aabb(Rect2(16.5, 0, 18, 1), results, COUNT, nullptr) == 5);
	CHECK(tree.cull_point(Vector2(20.5, 0.5), results, COUNT, nullptr) == 1);
	CHECK(results[0] == &items[5]);
	CHECK(tree.cull_segment(Vector2(-2, 0.5), Vector2(COUNT * 4, 0.5), results, COUNT, nullptr) == COUNT);
	CountingCullTest::calls = 0;
	CHECK(tree.cull_aabb(Rect2(-2, -2, COUNT * 4 + 4, 6), results, 3, nullptr) == 3);
	CHECK(CountingCullTest::calls == 3);
}

TEST_CASE("[BVH] 3D point, segment and box culls preserve exact results") {
	using Tree = BVH_Manager<Item, 2, true, 16, PairTest, CountingCullTest, AABB, Vector3, false>;
	Tree tree;
	constexpr int COUNT = 96;
	Item items[COUNT];
	for (int i = 0; i < COUNT; ++i) {
		items[i].value = i;
		tree.create(&items[i], true, uint32_t(i & 1), 3,
				AABB(Vector3(i * 4, 0, 0), Vector3(1, 1, 1)));
	}
	Item *results[COUNT] = {};

	CountingCullTest::calls = 0;
	CHECK(tree.cull_aabb(AABB(Vector3(0, 1000, 0), Vector3(1000, 1, 1)), results, COUNT, nullptr) == 0);
	CHECK(tree.cull_point(Vector3(999, 999, 999), results, COUNT, nullptr) == 0);
	CHECK(tree.cull_segment(Vector3(-10, 1000, 0.5), Vector3(500, 1000, 0.5), results, COUNT, nullptr) == 0);
	CHECK(CountingCullTest::calls == 0);

	const AABB all(Vector3(-2, -2, -2), Vector3(COUNT * 4 + 4, 6, 6));
	CountingCullTest::calls = 0;
	CHECK(tree.cull_aabb(all, results, COUNT, nullptr) == COUNT);
	CHECK(CountingCullTest::calls == COUNT);
	bool seen[COUNT] = {};
	for (int i = 0; i < COUNT; ++i) {
		REQUIRE(results[i] != nullptr);
		CHECK(results[i]->value >= 0);
		CHECK(results[i]->value < COUNT);
		seen[results[i]->value] = true;
	}
	for (bool found : seen) {
		CHECK(found);
	}
	CHECK(tree.cull_aabb(all, results, COUNT, nullptr, 2) == COUNT / 2);
	CHECK(tree.cull_point(Vector3(16.5, 0.5, 0.5), results, COUNT, nullptr) == 1);
	CHECK(results[0] == &items[4]);
	CHECK(tree.cull_segment(Vector3(-2, 0.5, 0.5), Vector3(COUNT * 4, 0.5, 0.5), results, COUNT, nullptr) == COUNT);
	CountingCullTest::calls = 0;
	CHECK(tree.cull_aabb(all, results, 1, nullptr) == 1);
	CHECK(CountingCullTest::calls == 1);
}

} // namespace TestBVH
