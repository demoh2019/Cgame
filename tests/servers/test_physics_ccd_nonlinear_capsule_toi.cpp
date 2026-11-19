/**************************************************************************/
/*  test_physics_ccd_nonlinear_capsule_toi.cpp                       */
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

#include "servers/physics_ccd_nonlinear_capsule_toi.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_ccd_nonlinear_capsule_toi)

namespace TestPhysicsCCDMixedCapsuleTOI {

TEST_CASE("[Physics][MixedCapsuleTOI] 2D capsule hits circle mid-sweep with translation and rotation") {
	double fraction = -1.0;
	// At both ends the capsule is vertical and clear of the circle, but
	// at half a turn its rounded end passes through the circle at x=2.3.
	// The linear displacement is shorter than a capsule diameter, so a
	// pure-linear fast-object gate would skip the collision entirely.
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector2(), Vector2(0.0, 1.0), Vector2(), Vector2(2.3, 0.0),
			Vector2(0.1, 0.0), real_t(Math::PI), real_t(1.0),
			2.5, 0.5, fraction) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(fraction > 0.0);
	CHECK(fraction < 0.75);

	double retreat_fraction = -1.0;
	// Moving slowly away does not eliminate a hit by the rotating end.
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector2(), Vector2(0.0, 1.0), Vector2(), Vector2(2.3, 0.0),
			Vector2(-0.1, 0.0), real_t(Math::PI), real_t(1.0),
			2.5, 0.5, retreat_fraction) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(retreat_fraction > 0.0);
	CHECK(retreat_fraction < 0.75);
}

TEST_CASE("[Physics][MixedCapsuleTOI] 3D capsule hits sphere during combined motion") {
	double fraction = -1.0;
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(), Vector3(0.0, 1.0, 0.0), Vector3(), Vector3(2.3, 0.0, 0.0),
			Vector3(0.1, 0.0, 0.0), Vector3(0.0, 0.0, real_t(Math::PI)), real_t(1.0),
			2.5, 0.5, fraction) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(fraction > 0.0);
	CHECK(fraction < 0.75);
}

TEST_CASE("[Physics][MixedCapsuleTOI] 3D capsule rotates about X while translating along Z") {
	double fraction = -1.0;
	// This is not a planar Z rotation: the capsule starts along Y and
	// rotates into the Z axis, contacting a sphere during the step.
	// The initial and final poses are both separated.
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(), Vector3(0.0, 1.0, 0.0), Vector3(), Vector3(0.0, 0.0, 2.3),
			Vector3(0.0, 0.0, 0.1), Vector3(real_t(Math::PI), 0.0, 0.0), real_t(1.0),
			2.5, 0.5, fraction) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(fraction > 0.0);
	CHECK(fraction < 0.75);
}

TEST_CASE("[Physics][MixedCapsuleTOI] Off-center pivots remain correct after world translation") {
	const Vector2 offset_2d(2048.0, -4096.0);
	double base_2d = -1.0;
	double shifted_2d = -1.0;
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector2(2.0, 0.0), Vector2(0.0, 1.0), Vector2(), Vector2(0.0, 2.0),
			Vector2(0.1, 0.0), real_t(Math::PI / 2.0), real_t(1.0),
			0.5, 0.3, base_2d) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector2(2.0, 0.0) + offset_2d, Vector2(0.0, 1.0), offset_2d, Vector2(0.0, 2.0) + offset_2d,
			Vector2(0.1, 0.0), real_t(Math::PI / 2.0), real_t(1.0),
			0.5, 0.3, shifted_2d) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(Math::abs(base_2d - shifted_2d) < 0.003);

	const Vector3 offset_3d(2048.0, -4096.0, 1024.0);
	double base_3d = -1.0;
	double shifted_3d = -1.0;
	const Vector3 omega(0.0, 0.0, real_t(Math::PI / 2.0));
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(2.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(), Vector3(0.0, 2.0, 0.0),
			Vector3(0.1, 0.0, 0.0), omega, real_t(1.0),
			0.5, 0.3, base_3d) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(2.0, 0.0, 0.0) + offset_3d, Vector3(0.0, 1.0, 0.0), offset_3d, Vector3(0.0, 2.0, 0.0) + offset_3d,
			Vector3(0.1, 0.0, 0.0), omega, real_t(1.0),
			0.5, 0.3, shifted_3d) == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(Math::abs(base_3d - shifted_3d) < 0.003);
}

TEST_CASE("[Physics][MixedCapsuleTOI] Distant, overlapping and invalid cases stay conservative") {
	double fraction = -1.0;
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(), Vector3(0.0, 1.0, 0.0), Vector3(), Vector3(2.3, 0.0, 4.0),
			Vector3(0.1, 0.0, 0.0), Vector3(0.0, 0.0, real_t(Math::PI)), real_t(1.0),
			2.5, 0.5, fraction) == PhysicsCCDRotatingCapsuleTOIResult::MISS);
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(), Vector3(0.0, 1.0, 0.0), Vector3(), Vector3(0.2, 0.0, 0.0),
			Vector3(0.1, 0.0, 0.0), Vector3(0.0, 0.0, real_t(Math::PI)), real_t(1.0),
			2.5, 0.5, fraction) == PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(), Vector3(), Vector3(), Vector3(2.3, 0.0, 0.0),
			Vector3(0.1, 0.0, 0.0), Vector3(0.0, 0.0, real_t(Math::PI)), real_t(1.0),
			2.5, 0.5, fraction) == PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(), Vector3(0.0, 1.0, 0.0), Vector3(), Vector3(2.3, 0.0, 0.0),
			Vector3(real_t(Math::INF), 0.0, 0.0), Vector3(0.0, 0.0, real_t(Math::PI)), real_t(1.0),
			2.5, 0.5, fraction) == PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
	CHECK(physics_ccd_nonlinear_capsule_toi(
			Vector3(), Vector3(0.0, 1.0, 0.0), Vector3(), Vector3(2.3, 0.0, 0.0),
			Vector3(0.1, 0.0, 0.0), Vector3(), real_t(1.0),
			2.5, 0.5, fraction) == PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
	CHECK(fraction == -1.0);
}

} // namespace TestPhysicsCCDMixedCapsuleTOI
