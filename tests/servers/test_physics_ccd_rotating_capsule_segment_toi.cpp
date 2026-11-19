/**************************************************************************/
/*  test_physics_ccd_rotating_capsule_segment_toi.cpp                       */
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

#include "servers/physics_ccd_rotating_capsule_segment_toi.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_ccd_rotating_capsule_segment_toi)

namespace TestPhysicsCCDRotatingCapsuleSegmentTOI {

TEST_CASE("[Physics][RotatingCapsuleSegmentTOI] Rotation hits a finite segment and exits within a step") {
	double fraction = -1.0;
	// Capsule starts vertical and turns 180 degrees around the origin.
	// At the midpoint it reaches a vertical segment x=2.3, y=[-.3,.3].
	// Both the starting and ending poses are separated.
	CHECK(physics_ccd_rotating_capsule_segment_toi(
			Vector2(), Vector2(0.0, 1.0), Vector2(),
			Vector2(2.3, -0.3), Vector2(2.3, 0.3),
			real_t(Math::PI), real_t(1.0), 2.5, 0.25, fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(fraction > 0.0);
	CHECK(fraction < 0.75);

	// Reversing angular direction must still find the same first touch.
	double reverse_fraction = -1.0;
	CHECK(physics_ccd_rotating_capsule_segment_toi(
			Vector2(), Vector2(0.0, 1.0), Vector2(),
			Vector2(2.3, -0.3), Vector2(2.3, 0.3),
			real_t(-Math::PI), real_t(1.0), 2.5, 0.25, reverse_fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(Math::abs(fraction - reverse_fraction) < 0.003);
}

TEST_CASE("[Physics][RotatingCapsuleSegmentTOI] Offset pivot and world translation preserve first contact") {
	const Vector2 capsule_center(2.0, 0.0);
	const Vector2 pivot(0.0, 0.0);
	const Vector2 segment_a(0.0, 1.8);
	const Vector2 segment_b(0.0, 2.2);
	const Vector2 world_offset(2048.0, -4096.0);
	double base_fraction = -1.0;
	double shifted_fraction = -1.0;
	CHECK(physics_ccd_rotating_capsule_segment_toi(
			capsule_center, Vector2(0.0, 1.0), pivot,
			segment_a, segment_b, real_t(Math::PI / 2.0), real_t(1.0),
			0.5, 0.3, base_fraction) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(physics_ccd_rotating_capsule_segment_toi(
			capsule_center + world_offset, Vector2(0.0, 1.0), pivot + world_offset,
			segment_a + world_offset, segment_b + world_offset,
			real_t(Math::PI / 2.0), real_t(1.0),
			0.5, 0.3, shifted_fraction) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(Math::abs(base_fraction - shifted_fraction) < 0.003);
}

TEST_CASE("[Physics][RotatingCapsuleSegmentTOI] Miss, overlap and degenerate segment") {
	double fraction = -1.0;
	CHECK(physics_ccd_rotating_capsule_segment_toi(
			Vector2(), Vector2(0.0, 1.0), Vector2(),
			Vector2(20.0, -0.3), Vector2(20.0, 0.3),
			real_t(Math::PI), real_t(1.0), 2.5, 0.25, fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::MISS);
	CHECK(physics_ccd_rotating_capsule_segment_toi(
			Vector2(), Vector2(0.0, 1.0), Vector2(),
			Vector2(0.0, -0.3), Vector2(0.0, 0.3),
			real_t(Math::PI), real_t(1.0), 2.5, 0.25, fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
	CHECK(physics_ccd_rotating_capsule_segment_toi(
			Vector2(), Vector2(0.0, 1.0), Vector2(),
			Vector2(2.3, 0.0), Vector2(2.3, 0.0),
			real_t(Math::PI), real_t(1.0), 2.5, 0.25, fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(physics_ccd_rotating_capsule_segment_toi(
			Vector2(), Vector2(0.0, 1.0), Vector2(),
			Vector2(2.3, -0.3), Vector2(2.3, 0.3),
			real_t(0.0), real_t(1.0), 2.5, 0.25, fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
}

} // namespace TestPhysicsCCDRotatingCapsuleSegmentTOI
