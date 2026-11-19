/**************************************************************************/
/*  test_godot_physics_ccd_rotational_sphere_cull.cpp                     */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_ccd_rotational_sphere_cull.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_ccd_rotational_sphere_cull)

namespace TestGodotPhysicsCCDRotationalSphereCull {

TEST_CASE("[GodotPhysics2D] Rotating long box distant from target can be culled") {
	const Rect2 long_box(Vector2(-10, -1), Vector2(20, 2));
	CHECK_FALSE(physics_ccd_rotational_sphere_bounds_may_overlap(
			long_box, Vector2(), Rect2(Vector2(-1, 99), Vector2(2, 2)),
			Vector2(0, 100), Vector2(0, 30)));
}

TEST_CASE("[GodotPhysics2D] Off-center rotating box can reach outside its initial AABB") {
	const Rect2 offset_box(Vector2(10, -1), Vector2(2, 2));
	const Rect2 target(Vector2(-1, 10), Vector2(2, 2));
	// The box's farthest corner from its origin can sweep across the target
	// despite no overlap between the starting AABBs.
	CHECK(physics_ccd_rotational_sphere_bounds_may_overlap(
			offset_box, Vector2(), target, Vector2(0, 11), Vector2()));
}

TEST_CASE("[GodotPhysics2D] Swept centers detect head-on approach and near miss") {
	const Rect2 box(Vector2(-1, -1), Vector2(2, 2));
	CHECK(physics_ccd_rotational_sphere_bounds_may_overlap(
			box, Vector2(), Rect2(Vector2(9, -1), Vector2(2, 2)),
			Vector2(10, 0), Vector2(11, 0)));
	CHECK_FALSE(physics_ccd_rotational_sphere_bounds_may_overlap(
			box, Vector2(), Rect2(Vector2(9, 9), Vector2(2, 2)),
			Vector2(10, 10), Vector2(4, 0)));
}

TEST_CASE("[GodotPhysics3D] Rotating long box rejects distant pair") {
	const AABB blade(Vector3(-10, -1, -1), Vector3(20, 2, 2));
	CHECK_FALSE(physics_ccd_rotational_sphere_bounds_may_overlap(
			blade, Vector3(), AABB(Vector3(-1, 79, -1), Vector3(2, 2, 2)),
			Vector3(0, 80, 0), Vector3(0, 25, 0)));
}

TEST_CASE("[GodotPhysics3D] Rotating blade cannot be rejected near its orbital reach") {
	const AABB offset_blade(Vector3(8, -1, -1), Vector3(4, 2, 2));
	const AABB target(Vector3(-1, 8, -1), Vector3(2, 2, 2));
	CHECK(physics_ccd_rotational_sphere_bounds_may_overlap(
			offset_blade, Vector3(), target, Vector3(0, 9, 0), Vector3()));
}

TEST_CASE("[GodotPhysics3D] Invalid geometry falls back to narrowphase") {
	AABB malformed(Vector3(), Vector3(2, 2, 2));
	malformed.size.x = Math::INF;
	const AABB target(Vector3(), Vector3(1, 1, 1));
	CHECK(physics_ccd_rotational_sphere_bounds_may_overlap(
			malformed, Vector3(), target, Vector3(0, 100, 0),
			Vector3(0, 100, 0), Vector3()));
}

} // namespace TestGodotPhysicsCCDRotationalSphereCull
