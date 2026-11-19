/**************************************************************************/
/*  test_physics_cast_motion_pruning.cpp                                  */
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

TEST_FORCE_LINK(test_physics_cast_motion_pruning)

#include "servers/physics_cast_motion_pruning.h"

namespace TestPhysicsCastMotionPruning {

TEST_CASE("[Physics] 2D cast clips sweep conservatively after a nearer hit") {
	const Rect2 start(Vector2(-0.5, -0.5), Vector2(1, 1));
	const Vector2 motion(10, 0);
	const Rect2 clipped = godot_physics_cast_motion_clipped_aabb(start, motion, real_t(0.25), real_t(0));
	CHECK(clipped.intersects(Rect2(Vector2(1.5, -0.5), Vector2(1, 1)), true));
	CHECK(!clipped.intersects(Rect2(Vector2(8, -0.5), Vector2(1, 1)), true));

	// The end of the earliest possible contact interval remains inside
	// the conservative bounds even when it only touches a candidate.
	CHECK(clipped.intersects(Rect2(Vector2(3.0, -0.5), Vector2(1, 1)), true));
	CHECK(clipped.has_point(Vector2(0, 0)));

	// Negative movement must extend the sweep to the left, not right.
	const Rect2 reverse = godot_physics_cast_motion_clipped_aabb(start, Vector2(-10, 0), real_t(0.25), real_t(0));
	CHECK(reverse.intersects(Rect2(Vector2(-3.4, -0.5), Vector2(1, 1)), true));
	CHECK(!reverse.intersects(Rect2(Vector2(4, -0.5), Vector2(1, 1)), true));
}

TEST_CASE("[Physics] 3D shape casts preserve boundary and initial overlaps") {
	const AABB start(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1));
	const Vector3 motion(10, 0, 0);
	const AABB clipped = godot_physics_cast_motion_clipped_aabb(start, motion, real_t(0.25), real_t(0));
	CHECK(clipped.intersects(AABB(Vector3(1.5, -0.5, -0.5), Vector3(1, 1, 1))));
	CHECK(!clipped.intersects(AABB(Vector3(8, -0.5, -0.5), Vector3(1, 1, 1))));
	CHECK(clipped.intersects(AABB(Vector3(3.0, -0.5, -0.5), Vector3(1, 1, 1))));
	CHECK(clipped.has_point(Vector3(0, 0, 0)));

	const AABB reverse = godot_physics_cast_motion_clipped_aabb(start, Vector3(-10, 0, 0), real_t(0.25), real_t(0));
	CHECK(reverse.intersects(AABB(Vector3(-3.4, -0.5, -0.5), Vector3(1, 1, 1))));
	CHECK(!reverse.intersects(AABB(Vector3(4, -0.5, -0.5), Vector3(1, 1, 1))));
}

TEST_CASE("[Physics] Nonnegative margin and stationary casts never shrink candidate bounds") {
	const Rect2 start2(Vector2(-0.5, -0.5), Vector2(1, 1));
	const AABB start3(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1));

	const Rect2 zero2 = godot_physics_cast_motion_clipped_aabb(start2, Vector2(), real_t(0), real_t(0.25));
	const AABB zero3 = godot_physics_cast_motion_clipped_aabb(start3, Vector3(), real_t(0), real_t(0.25));
	CHECK(zero2.intersects(Rect2(Vector2(0.55, -0.1), Vector2(0.1, 0.2)), true));
	CHECK(zero3.intersects(AABB(Vector3(0.55, -0.1, -0.1), Vector3(0.1, 0.2, 0.2))));

	const Rect2 negative_margin2 = godot_physics_cast_motion_clipped_aabb(start2, Vector2(1, 0), real_t(0.5), real_t(-0.25));
	const AABB negative_margin3 = godot_physics_cast_motion_clipped_aabb(start3, Vector3(1, 0, 0), real_t(0.5), real_t(-0.25));
	CHECK(negative_margin2.has_point(Vector2(0, 0)));
	CHECK(negative_margin3.has_point(Vector3(0, 0, 0)));
}

} // namespace TestPhysicsCastMotionPruning
