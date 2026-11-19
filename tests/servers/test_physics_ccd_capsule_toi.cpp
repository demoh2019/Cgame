/**************************************************************************/
/*  test_physics_ccd_capsule_toi.cpp                                       */
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

#include "servers/physics_ccd_capsule_toi.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_ccd_capsule_toi)

namespace TestPhysicsCCDCapsuleTOI {

TEST_CASE("[Physics][CapsuleTOI] Circle-capsule TOI catches glancing end-cap impact") {
	double fraction = -1.0;
	// A circle's leading point at y=-2.2 misses a capsule of radius 0.5
	// whose bottom end is y=-2.0. Their Minkowski sum has radius 1.0:
	// the capsule centerline ends at y=-1.5 and the offset is 0.7.
	const double expected = (8.0 - Math::sqrt(0.51)) / 8.0;
	CHECK(physics_ccd_capsule_toi(Vector2(-8.0, -2.2), Vector2(8.0, 0.0), 1.0, 1.5, fraction));
	CHECK(Math::abs(fraction - expected) < 1e-6);

	CHECK_FALSE(physics_ccd_capsule_toi(Vector2(-8.0, -2.51), Vector2(8.0, 0.0), 1.0, 1.5, fraction));
	CHECK_FALSE(physics_ccd_capsule_toi(Vector2(-8.0, -2.2), Vector2(-8.0, 0.0), 1.0, 1.5, fraction));
	CHECK_FALSE(physics_ccd_capsule_toi(Vector2(-8.0, -2.2), Vector2(), 1.0, 1.5, fraction));
	CHECK_FALSE(physics_ccd_capsule_toi(Vector2(0.0, 0.0), Vector2(8.0, 0.0), 1.0, 1.5, fraction));
}

TEST_CASE("[Physics][CapsuleTOI] Capsule TOI ranks first side entry under both directions") {
	double fraction = -1.0;
	CHECK(physics_ccd_capsule_toi(Vector3(-4.0, 0.0, 0.3), Vector3(8.0, 0.0, 0.0), 1.0, 1.5, fraction));
	CHECK(Math::abs(fraction - (4.0 - Math::sqrt(0.91)) / 8.0) < 1e-6);
	CHECK(physics_ccd_capsule_toi(Vector3(4.0, 0.0, 0.3), Vector3(-8.0, 0.0, 0.0), 1.0, 1.5, fraction));
	CHECK(Math::abs(fraction - (4.0 - Math::sqrt(0.91)) / 8.0) < 1e-6);

	CHECK(physics_ccd_capsule_toi(Vector3(-4.0, 2.2, 0.0), Vector3(8.0, 0.0, 0.0), 1.0, 1.5, fraction));
	CHECK(Math::abs(fraction - (4.0 - Math::sqrt(0.51)) / 8.0) < 1e-6);

	CHECK_FALSE(physics_ccd_capsule_toi(Vector3(-4.0, 0.0, 2.0), Vector3(8.0, 0.0, 0.0), 1.0, 1.5, fraction));
	CHECK_FALSE(physics_ccd_capsule_toi(Vector3(-4.0, 0.0, 0.0), Vector3(8.0, 0.0, 0.0), 0.0, 1.5, fraction));
	CHECK_FALSE(physics_ccd_capsule_toi(Vector3(-4.0, 0.0, 0.0), Vector3(8.0, 0.0, 0.0), 1.0, -1.0, fraction));
}

TEST_CASE("[Physics][CapsuleTOI] Capsule TOI keeps first entry on extreme-length rays") {
	double fraction = -1.0;
	const double begin = 1e20;
	CHECK(physics_ccd_capsule_toi(Vector3(-begin, 0.0, 0.0),
			Vector3(2.0 * begin, 0.0, 0.0), 1.0, 1.5, fraction));
	CHECK(Math::abs(fraction - 0.5) < 1e-12);
	CHECK(physics_ccd_capsule_toi(Vector3(begin, 2.2, 0.0),
			Vector3(-2.0 * begin, 0.0, 0.0), 1.0, 1.5, fraction));
	CHECK(Math::abs(fraction - 0.5) < 1e-12);
}


TEST_CASE("[Physics][CapsuleTOI] Parallel capsule pair reduces to expanded capsule") {
	// Both capsules have radius 0.5 and centerline half-length 1.5.
	// Their Minkowski sum has radius 1 and half-length 3.
	// A glancing sweep at Y=3.8 intersects the upper hemispherical end.
	double fraction = -1.0;
	const double expected = (4.0 - Math::sqrt(0.36)) / 8.0;
	CHECK(physics_ccd_capsule_toi(Vector2(-4.0, 3.8), Vector2(8.0, 0.0), 1.0, 3.0, fraction));
	CHECK(Math::abs(fraction - expected) < 1e-6);
	CHECK(physics_ccd_capsule_toi(Vector2(4.0, 3.8), Vector2(-8.0, 0.0), 1.0, 3.0, fraction));
	CHECK(Math::abs(fraction - expected) < 1e-6);

	// With the B capsule centerline at Y=3, two parallel center segments
	// overlap across Y=0, so the radial side is the first hit.
	CHECK(physics_ccd_capsule_toi(Vector3(-4.0, 0.0, 0.0), Vector3(8.0, 0.0, 0.0), 1.0, 3.0, fraction));
	CHECK(Math::abs(fraction - 0.375) < 1e-10);

	// World scale A=2, B=1. Radii and half-segments must be added
	// after converting A into B's local coordinate system.
	const double radius = 0.5 + 0.5 * 2.0;
	const double half_segment = 1.5 + 1.5 * 2.0;
	CHECK(physics_ccd_capsule_toi(Vector3(-7.0, 5.7, 0.0), Vector3(14.0, 0.0, 0.0),
			radius, half_segment, fraction));
	CHECK(Math::abs(fraction - (7.0 - 0.9) / 14.0) < 1e-6);

	CHECK_FALSE(physics_ccd_capsule_toi(Vector2(-4.0, 4.01), Vector2(8.0, 0.0), 1.0, 3.0, fraction));
	CHECK_FALSE(physics_ccd_capsule_toi(Vector3(-4.0, 0.0, 0.0), Vector3(), 1.0, 3.0, fraction));
}

} // namespace TestPhysicsCCDCapsuleTOI
