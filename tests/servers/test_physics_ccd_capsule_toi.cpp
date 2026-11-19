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

TEST_CASE("[Physics] Circle-capsule TOI catches glancing end-cap impact") {
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

TEST_CASE("[Physics] Capsule TOI ranks first side entry under both directions") {
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

TEST_CASE("[Physics] Capsule TOI keeps first entry on extreme-length rays") {
	double fraction = -1.0;
	const double begin = 1e20;
	CHECK(physics_ccd_capsule_toi(Vector3(-begin, 0.0, 0.0),
			Vector3(2.0 * begin, 0.0, 0.0), 1.0, 1.5, fraction));
	CHECK(Math::abs(fraction - 0.5) < 1e-12);
	CHECK(physics_ccd_capsule_toi(Vector3(begin, 2.2, 0.0),
			Vector3(-2.0 * begin, 0.0, 0.0), 1.0, 1.5, fraction));
	CHECK(Math::abs(fraction - 0.5) < 1e-12);
}

} // namespace TestPhysicsCCDCapsuleTOI
