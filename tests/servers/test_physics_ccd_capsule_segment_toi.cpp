/**************************************************************************/
/*  test_physics_ccd_capsule_segment_toi.cpp                                       */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_ccd_capsule_segment_toi.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_ccd_capsule_segment_toi)

namespace TestPhysicsCCDCapsuleSegmentTOI {

TEST_CASE("[Physics][CapsuleSegmentTOI] Vertical capsule sweeps glancing horizontal segment endpoint") {
	double fraction = -1.0;
	// Capsule centerline Y=[-1,1], radius 0.5. Segment Y=1.3 and
	// X=[-1,1]. First contact against its left endpoint happens when
	// the capsule center reaches X=-1-sqrt(0.5^2-0.3^2)=-1.4.
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(-4.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 1.0),
			1.0, 0.5, Vector2(-1.0, 1.3), Vector2(1.0, 1.3), fraction) ==
			PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.325) < 0.00001);

	// Swapping the segment endpoints does not change the geometry.
	fraction = -1.0;
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(-4.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 1.0),
			1.0, 0.5, Vector2(1.0, 1.3), Vector2(-1.0, 1.3), fraction) ==
			PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.325) < 0.00001);

	// Reversing motion must yield the same first fraction.
	fraction = -1.0;
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(4.0, 0.0), Vector2(-8.0, 0.0), Vector2(0.0, 1.0),
			1.0, 0.5, Vector2(-1.0, 1.3), Vector2(1.0, 1.3), fraction) ==
			PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.325) < 0.00001);
}

TEST_CASE("[Physics][CapsuleSegmentTOI] Horizontal capsule contacts vertical segment at an endpoint") {
	double fraction = -1.0;
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(-4.0, 1.3), Vector2(8.0, 0.0), Vector2(1.0, 0.0),
			1.0, 0.5, Vector2(0.0, -1.0), Vector2(0.0, 1.0), fraction) ==
			PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.325) < 0.00001);

	// A finite segment of zero length is still a valid point obstacle.
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(-4.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 1.0),
			1.0, 0.5, Vector2(), Vector2(), fraction) ==
			PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.4375) < 0.00001);
}

TEST_CASE("[Physics][CapsuleSegmentTOI] Miss, start overlap, nonfinite and huge sweeps") {
	double fraction = -1.0;
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(-4.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 1.0),
			1.0, 0.5, Vector2(-1.0, 1.6), Vector2(1.0, 1.6), fraction) ==
			PhysicsCCDCapsulePairTOIResult::MISS);
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(0.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 1.0),
			1.0, 0.5, Vector2(-1.0, 1.3), Vector2(1.0, 1.3), fraction) ==
			PhysicsCCDCapsulePairTOIResult::FALLBACK);
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(-4.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 1.0),
			1.0, 0.0, Vector2(-1.0, 1.3), Vector2(1.0, 1.3), fraction) ==
			PhysicsCCDCapsulePairTOIResult::FALLBACK);
	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(-4.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 1.0),
			1.0, 0.5, Vector2(double(Math::INF), 0.0), Vector2(1.0, 1.3), fraction) ==
			PhysicsCCDCapsulePairTOIResult::FALLBACK);

	CHECK(physics_ccd_capsule_segment_toi(
			Vector2(real_t(-1e20), 0.0), Vector2(real_t(2e20), 0.0), Vector2(0.0, 1.0),
			1.0, 0.5, Vector2(0.0, -1.0), Vector2(0.0, 1.0), fraction) ==
			PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.5) < 0.00000001);
}

} // namespace TestPhysicsCCDCapsuleSegmentTOI
