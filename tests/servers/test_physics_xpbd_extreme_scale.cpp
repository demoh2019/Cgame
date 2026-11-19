/**************************************************************************/
/*  test_physics_xpbd_extreme_scale.cpp                                   */
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

#include "servers/physics_xpbd_distance.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_xpbd_extreme_scale)

namespace TestPhysicsXPBDExtremeScale {

TEST_CASE("[PhysicsXPBD] Large finite XPBD links do not overflow their squared distance") {
	Vector3 a, b(real_t(2e20), 0, 0);
	real_t lambda = real_t(0.0);
	CHECK(physics_xpbd_solve_distance(a, b, real_t(1.0), real_t(1.0), real_t(1e20), real_t(0.0), lambda));
	CHECK(a.is_finite());
	CHECK(b.is_finite());
	CHECK(a.x / real_t(1e20) == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(b.x / real_t(1e20) == doctest::Approx(1.5).epsilon(1e-5));
	CHECK(lambda / real_t(1e20) == doctest::Approx(-0.5).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBD] Large opposite positions use wide distance and projection") {
	Vector3 a(real_t(-1e38), 0, 0), b(real_t(1e38), 0, 0);
	real_t lambda = real_t(0.0);
	CHECK(physics_xpbd_solve_distance(a, b, real_t(1.0), real_t(1.0), real_t(1e38), real_t(0.0), lambda));
	CHECK(a.is_finite());
	CHECK(b.is_finite());
	CHECK(a.x / real_t(1e38) == doctest::Approx(-0.5).epsilon(1e-5));
	CHECK(b.x / real_t(1e38) == doctest::Approx(0.5).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBD] Tiny representable links must not be culled by fixed epsilon") {
	const real_t unit = real_t(1e-8);
	Vector3 a, b(real_t(2.0) * unit, 0, 0);
	real_t lambda = real_t(0.0);
	CHECK(physics_xpbd_solve_distance(a, b, real_t(1.0), real_t(1.0), unit, real_t(0.0), lambda));
	CHECK(a.x / unit == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(b.x / unit == doctest::Approx(1.5).epsilon(1e-5));
	CHECK((b.x - a.x) / unit == doctest::Approx(1.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBD] Unrepresentable multiplier keeps positions and lambda unchanged") {
	Vector3 a, b(real_t(1e20), 0, 0);
	const Vector3 old_a = a;
	const Vector3 old_b = b;
	real_t lambda = real_t(0.0);
	// The correction multiplier would be roughly -5e39, not a finite
	// float32 value; no partial position update is permitted.
	CHECK_FALSE(physics_xpbd_solve_distance(a, b, real_t(1e-20), real_t(1e-20),
			real_t(0.0), real_t(0.0), lambda));
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(lambda == real_t(0.0));
}

} // namespace TestPhysicsXPBDExtremeScale
