/**************************************************************************/
/*  test_physics_ccd_sphere_toi.cpp                                       */
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

#include "servers/physics_ccd_sphere_toi.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_ccd_sphere_toi)

namespace TestPhysicsCCDSphereTOI {

TEST_CASE("[Physics] Analytic circle CCD finds glancing contacts missed by support rays") {
	double fraction = -1.0;
	// Two radius-0.5 disks. B is 0.8 above A's path; A's leading
	// support ray at y=0 misses B's radius-0.5 disk, but the swept
	// Minkowski disk of radius 1 touches when x=3.4.
	CHECK(physics_ccd_sphere_toi(Vector2(-4.0, -0.8), Vector2(8.0, 0.0), 1.0, fraction));
	CHECK(Math::abs(fraction - 0.425) < 1e-6);

	CHECK_FALSE(physics_ccd_sphere_toi(Vector2(-4.0, -1.01), Vector2(8.0, 0.0), 1.0, fraction));
	CHECK_FALSE(physics_ccd_sphere_toi(Vector2(-4.0, -0.8), Vector2(-8.0, 0.0), 1.0, fraction));
	CHECK_FALSE(physics_ccd_sphere_toi(Vector2(-4.0, -0.8), Vector2(), 1.0, fraction));
	CHECK_FALSE(physics_ccd_sphere_toi(Vector2(-0.5, 0.0), Vector2(8.0, 0.0), 1.0, fraction));

	CHECK(physics_ccd_sphere_toi(Vector2(-4.0, -1.0), Vector2(8.0, 0.0), 1.0, fraction));
	CHECK(Math::abs(fraction - 0.5) < 1e-10);
}

TEST_CASE("[Physics] Analytic sphere CCD accounts for the third dimension") {
	double fraction = -1.0;
	CHECK(physics_ccd_sphere_toi(Vector3(-4.0, 0.0, -0.8), Vector3(8.0, 0.0, 0.0), 1.0, fraction));
	CHECK(Math::abs(fraction - 0.425) < 1e-6);
	CHECK_FALSE(physics_ccd_sphere_toi(Vector3(-4.0, 0.8, 0.8), Vector3(8.0, 0.0, 0.0), 1.0, fraction));

	// Stable quadratic root: the entry is a unit before the midpoint
	// of an enormous (but representable) sweep.
	CHECK(physics_ccd_sphere_toi(Vector3(-100000000.0, 0.0, 0.0), Vector3(200000000.0, 0.0, 0.0), 1.0, fraction));
	CHECK(Math::abs(fraction - (100000000.0 - 1.0) / 200000000.0) < 1e-10);
}

TEST_CASE("[Physics] Analytic sphere CCD rejects ellipsoidal transforms") {
	CHECK(Math::abs(physics_ccd_uniform_sphere_scale(Transform2D()) - 1.0) < 1e-10);
	CHECK(Math::abs(physics_ccd_uniform_sphere_scale(Transform2D(Vector2(2.0, 0.0), Vector2(0.0, -2.0), Vector2())) - 2.0) < 1e-10);
	CHECK(physics_ccd_uniform_sphere_scale(Transform2D(Vector2(2.0, 0.0), Vector2(0.0, 1.0), Vector2())) == 0.0);
	CHECK(physics_ccd_uniform_sphere_scale(Transform2D(Vector2(1.0, 0.0), Vector2(0.5, 1.0), Vector2())) == 0.0);

	CHECK(Math::abs(physics_ccd_uniform_sphere_scale(Transform3D()) - 1.0) < 1e-10);
	CHECK(Math::abs(physics_ccd_uniform_sphere_scale(Transform3D(Basis::from_scale(Vector3(3.0, 3.0, 3.0)), Vector3())) - 3.0) < 1e-10);
	CHECK(physics_ccd_uniform_sphere_scale(Transform3D(Basis::from_scale(Vector3(2.0, 1.0, 1.0)), Vector3())) == 0.0);
	Basis shear;
	shear.set_column(1, Vector3(0.5, 1.0, 0.0));
	CHECK(physics_ccd_uniform_sphere_scale(Transform3D(shear, Vector3())) == 0.0);
}

} // namespace TestPhysicsCCDSphereTOI
