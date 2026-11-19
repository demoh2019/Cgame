/**************************************************************************/
/*  test_godot_physics_ccd_rotating_capsule_toi.cpp                       */
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

#include "servers/physics_ccd_rotating_capsule_toi.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_ccd_rotating_capsule_toi)

namespace TestGodotPhysicsCCDRotatingCapsuleTOI {

TEST_CASE("[GodotPhysics2D] Rotation-only capsule can strike a stationary circle") {
	double fraction = -1.0;
	const PhysicsCCDRotatingCapsuleTOIResult result = physics_ccd_rotating_capsule_toi(
			Vector2(), Vector2(0, 1), Vector2(), Vector2(2.3, 0),
			real_t(Math::PI / 2.0), real_t(1.0), 2.5, 0.5, fraction);
	CHECK(result == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(fraction > 0.0);
	CHECK(fraction < 1.0);
}

TEST_CASE("[GodotPhysics2D] Fast rotational tunneling is detected even if the endpoints separate") {
	double fraction = -1.0;
	const PhysicsCCDRotatingCapsuleTOIResult result = physics_ccd_rotating_capsule_toi(
			Vector2(), Vector2(0, 1), Vector2(), Vector2(2.3, 0),
			real_t(Math::PI), real_t(1.0), 2.5, 0.5, fraction);
	CHECK(result == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(fraction > 0.0);
	CHECK(fraction < real_t(0.75));
}

TEST_CASE("[GodotPhysics2D] Off-center axis rotates around rigid center of mass") {
	double fraction = -1.0;
	const PhysicsCCDRotatingCapsuleTOIResult result = physics_ccd_rotating_capsule_toi(
			Vector2(2, 0), Vector2(0, 1), Vector2(), Vector2(0, 2),
			real_t(Math::PI / 2.0), real_t(1.0), 0.5, 0.3, fraction);
	CHECK(result == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(fraction > 0.0);
	CHECK(fraction < 1.0);
}

TEST_CASE("[GodotPhysics3D] Capsule sweeps around Z onto a stationary sphere") {
	double fraction = -1.0;
	const PhysicsCCDRotatingCapsuleTOIResult result = physics_ccd_rotating_capsule_toi(
			Vector3(), Vector3(0, 1, 0), Vector3(), Vector3(2.3, 0, 0),
			Vector3(0, 0, real_t(Math::PI / 2.0)), real_t(1.0), 2.5, 0.5, fraction);
	CHECK(result == PhysicsCCDRotatingCapsuleTOIResult::HIT);
	CHECK(fraction > 0.0);
	CHECK(fraction < 1.0);
}

TEST_CASE("[GodotPhysics3D] Rotation in a distant plane is a conclusive miss") {
	double fraction = -1.0;
	const PhysicsCCDRotatingCapsuleTOIResult result = physics_ccd_rotating_capsule_toi(
			Vector3(), Vector3(0, 1, 0), Vector3(), Vector3(0, 0, 4),
			Vector3(0, 0, real_t(Math::PI)), real_t(1.0), 2.5, 0.5, fraction);
	CHECK(result == PhysicsCCDRotatingCapsuleTOIResult::MISS);
	CHECK(fraction == -1.0);
}

TEST_CASE("[GodotPhysics2D] Initial overlap preserves the normal contact solver") {
	double fraction = -1.0;
	const PhysicsCCDRotatingCapsuleTOIResult result = physics_ccd_rotating_capsule_toi(
			Vector2(), Vector2(0, 1), Vector2(), Vector2(0.2, 0),
			real_t(Math::PI), real_t(1.0), 2.5, 0.5, fraction);
	CHECK(result == PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
}

TEST_CASE("[GodotPhysics3D] Invalid geometry or timestep never produces a TOI") {
	double fraction = -1.0;
	CHECK(physics_ccd_rotating_capsule_toi(
				  Vector3(), Vector3(), Vector3(), Vector3(2.3, 0, 0),
				  Vector3(0, 0, 1), real_t(1.0), 2.5, 0.5, fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
	CHECK(physics_ccd_rotating_capsule_toi(
				  Vector3(), Vector3(0, 1, 0), Vector3(), Vector3(2.3, 0, 0),
				  Vector3(), real_t(1.0), 2.5, 0.5, fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
	CHECK(physics_ccd_rotating_capsule_toi(
				  Vector3(), Vector3(0, 1, 0), Vector3(), Vector3(2.3, 0, 0),
				  Vector3(0, 0, 1), 0, 2.5, 0.5, fraction) ==
			PhysicsCCDRotatingCapsuleTOIResult::FALLBACK);
	CHECK(fraction == -1.0);
}

} // namespace TestGodotPhysicsCCDRotatingCapsuleTOI
