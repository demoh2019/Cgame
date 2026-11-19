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

} // namespace TestBVH
