/**************************************************************************/
/*  test_physics_ccd_capsule_pair_toi.cpp                                       */
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

#include "servers/physics_ccd_capsule_pair_toi.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_ccd_capsule_pair_toi)

namespace TestPhysicsCCDSkewCapsuleTOI {

TEST_CASE("[Physics][CapsulePairTOI] Perpendicular 2D capsules cross between endpoints") {
	double fraction = -1.0;
	const PhysicsCCDCapsulePairTOIResult hit = physics_ccd_capsule_pair_toi(
			Vector2(-5.0, 1.8), Vector2(10.0, 0.0),
			Vector2(1.0, 0.0), Vector2(0.0, 1.0), 1.0, 1.0, 1.0, fraction);
	CHECK(hit == PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.34) < 0.00001);

	// Reversed motion and perpendicular pair ordering have the same TOI.
	fraction = -1.0;
	CHECK(physics_ccd_capsule_pair_toi(Vector2(5.0, 1.8), Vector2(-10.0, 0.0),
			Vector2(1.0, 0.0), Vector2(0.0, 1.0), 1.0, 1.0, 1.0, fraction) ==
			PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - 0.34) < 0.00001);
}

TEST_CASE("[Physics][CapsulePairTOI] Skew 3D capsule grazing at the rounded endpoint") {
	double fraction = -1.0;
	const double expected = (4.0 - Math::sqrt(0.27)) / 10.0;
	CHECK(physics_ccd_capsule_pair_toi(
			Vector3(-5.0, 1.8, 0.3), Vector3(10.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
			1.0, 1.0, 1.0, fraction) == PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - expected) < 0.00001);

	fraction = -1.0;
	CHECK(physics_ccd_capsule_pair_toi(
			Vector3(5.0, 1.8, 0.3), Vector3(-10.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
			1.0, 1.0, 1.0, fraction) == PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - expected) < 0.00001);
}

TEST_CASE("[Physics][CapsulePairTOI] Misses and initial overlap remain distinct") {
	double fraction = -1.0;
	CHECK(physics_ccd_capsule_pair_toi(
			Vector3(-5.0, 3.1, 0.0), Vector3(10.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
			1.0, 1.0, 1.0, fraction) == PhysicsCCDCapsulePairTOIResult::MISS);
	CHECK(physics_ccd_capsule_pair_toi(
			Vector3(-5.0, 1.8, 0.0), Vector3(-10.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
			1.0, 1.0, 1.0, fraction) == PhysicsCCDCapsulePairTOIResult::MISS);
	CHECK(physics_ccd_capsule_pair_toi(
			Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
			1.0, 1.0, 1.0, fraction) == PhysicsCCDCapsulePairTOIResult::FALLBACK);
	CHECK(physics_ccd_capsule_pair_toi(
			Vector3(-5.0, 1.8, 0.0), Vector3(10.0, 0.0, 0.0),
			Vector3(), Vector3(0.0, 1.0, 0.0),
			1.0, 1.0, 1.0, fraction) == PhysicsCCDCapsulePairTOIResult::FALLBACK);
}

TEST_CASE("[Physics][CapsulePairTOI] Different radii and lengths remain accurate") {
	double fraction = -1.0;
	const double expected = (4.0 - Math::sqrt(1.25)) / 12.0;
	CHECK(physics_ccd_capsule_pair_toi(
			Vector3(-6.0, 1.5, 0.0), Vector3(12.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
			2.0, 0.5, 1.5, fraction) == PhysicsCCDCapsulePairTOIResult::HIT);
	CHECK(Math::abs(fraction - expected) < 0.00001);
}

} // namespace TestPhysicsCCDSkewCapsuleTOI
