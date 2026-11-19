/**************************************************************************/
/*  test_physics_ccd_swept_bounds.cpp                                     */
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

#include "servers/physics_ccd_swept_bounds.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_ccd_swept_bounds)

namespace TestPhysicsCCDSweptBounds {

TEST_CASE("[PhysicsCCDSweep] 2D rejects misses without rejecting border touches") {
	const Rect2 moving(Vector2(0, 0), Vector2(2, 2));
	const Rect2 target(Vector2(8, 0), Vector2(2, 2));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(moving, target, Vector2(5, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(moving, target, Vector2(6, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(moving, target, Vector2(10, 0)));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(moving, target, Vector2(-10, 0)));
	// Legacy support rays extend 10 percent behind the moving shape.
	const Rect2 behind(Vector2(-1.5, 0), Vector2(1, 1));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(moving, behind, Vector2(10, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(moving, behind, Vector2(10, 0), real_t(0.1)));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(moving,
			Rect2(Vector2(4, 5), Vector2(2, 2)), Vector2(10, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(moving,
			Rect2(Vector2(1, 1), Vector2(2, 2)), Vector2(-10, 0)));
	// The old start/end AABB union included this target even though the
	// moving box passes above it before reaching the target's X interval.
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(
			Rect2(Vector2(0, 0), Vector2(1, 1)),
			Rect2(Vector2(5, 0), Vector2(1, 1)), Vector2(6, 6)));
}

TEST_CASE("[PhysicsCCDSweep] 3D rejects misses along any coordinate") {
	const AABB moving(Vector3(0, 0, 0), Vector3(2, 2, 2));
	const AABB target(Vector3(8, 0, 0), Vector3(2, 2, 2));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(moving, target, Vector3(5, 0, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(moving, target, Vector3(6, 0, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(moving, target, Vector3(10, 0, 0)));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(moving, target, Vector3(-10, 0, 0)));
	const AABB behind(Vector3(-1.5, 0, 0), Vector3(1, 1, 1));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(moving, behind, Vector3(10, 0, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(moving, behind, Vector3(10, 0, 0), real_t(0.1)));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(moving,
			AABB(Vector3(8, 0, 4), Vector3(2, 2, 2)), Vector3(10, 0, 0)));
	// A diagonal false positive of the old union-of-bounds culling.
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(
			AABB(Vector3(0, 0, 0), Vector3(1, 1, 1)),
			AABB(Vector3(5, 0, 0), Vector3(1, 1, 1)), Vector3(6, 6, 0)));
	// A genuine glancing diagonal contact must remain eligible.
	CHECK(physics_ccd_swept_bounds_may_overlap(
			AABB(Vector3(0, 0, 0), Vector3(1, 1, 1)),
			AABB(Vector3(5, 5, 0), Vector3(1, 1, 1)), Vector3(6, 6, 0)));
}

TEST_CASE("[PhysicsCCDSweep] Sheared shape AABBs remain conservative") {
	const Transform2D sheared2d(Vector2(1, 0), Vector2(0.5, 1), Vector2());
	const Rect2 moving2d = sheared2d.xform(Rect2(Vector2(-1, -1), Vector2(2, 2)));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(
			moving2d, Rect2(Vector2(8, 0), Vector2(1, 1)), Vector2(4, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(
			moving2d, Rect2(Vector2(8, 0), Vector2(1, 1)), Vector2(10, 0)));
	Basis shear3d;
	shear3d.set_column(1, Vector3(0.5, 1, 0));
	const AABB moving3d = Transform3D(shear3d, Vector3()).xform(
			AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)));
	CHECK_FALSE(physics_ccd_swept_bounds_may_overlap(
			moving3d, AABB(Vector3(8, 0, 0), Vector3(1, 1, 1)), Vector3(4, 0, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(
			moving3d, AABB(Vector3(8, 0, 0), Vector3(1, 1, 1)), Vector3(10, 0, 0)));
}

TEST_CASE("[PhysicsCCDSweep] Overflow and invalid bounds never reject casts") {
	const real_t huge = std::numeric_limits<real_t>::max();
	const Rect2 target2d(Vector2(), Vector2(1, 1));
	CHECK(physics_ccd_swept_bounds_may_overlap(
			Rect2(Vector2(huge, 0), Vector2(1, 1)), target2d, Vector2(huge, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(
			Rect2(Vector2(), Vector2(-1, 1)), target2d, Vector2(10, 0)));
	const AABB target3d(Vector3(), Vector3(1, 1, 1));
	CHECK(physics_ccd_swept_bounds_may_overlap(
			AABB(Vector3(huge, 0, 0), Vector3(1, 1, 1)), target3d, Vector3(huge, 0, 0)));
	CHECK(physics_ccd_swept_bounds_may_overlap(
			AABB(Vector3(), Vector3(-1, 1, 1)), target3d, Vector3(10, 0, 0)));
}

} // namespace TestPhysicsCCDSweptBounds
