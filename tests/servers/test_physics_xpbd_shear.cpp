/**************************************************************************/
/*  test_physics_xpbd_shear.cpp                                           */
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

#include "servers/physics_xpbd_shear.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_shear)

namespace TestPhysicsXPBDShear {

TEST_CASE("[PhysicsXPBD] Triangle shear restores a right angle with two pins") {
	Vector3 a, b(1, 0, 0), c(real_t(0.5), 1, 0);
	double lambda = 0.0;
	CHECK(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0, 0.0, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3(1, 0, 0));
	CHECK(Math::abs(c.x) < real_t(1e-5));
	CHECK(c.y > real_t(1.0));
	CHECK(lambda < 0.0);
}

TEST_CASE("[PhysicsXPBD] Shear compliance remains stable across iterations") {
	Vector3 a, b(1, 0, 0), c(real_t(0.5), 1, 0);
	double lambda = 0.0;
	for (int i = 0; i < 20; ++i) {
		CHECK(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0,
				0.0, real_t(0.1), lambda));
	}
	real_t cosine = 2.0;
	CHECK(physics_xpbd_triangle_shear_rest_cosine(a, b, c, cosine));
	CHECK(cosine > real_t(0.0));
	CHECK(cosine < real_t(0.1));
	CHECK(double(cosine) == doctest::Approx(-0.1 * lambda).epsilon(1e-4));
}

TEST_CASE("[PhysicsXPBD] Shear rest angle is translation and uniform-scale invariant") {
	real_t rest = 2.0, transformed = 2.0;
	CHECK(physics_xpbd_triangle_shear_rest_cosine(Vector3(), Vector3(2, 0, 0),
			Vector3(1, 1, 0), rest));
	CHECK(physics_xpbd_triangle_shear_rest_cosine(
			Vector3(100, -30, 12), Vector3(100, -24, 12),
			Vector3(97, -27, 12), transformed));
	CHECK(rest == doctest::Approx(transformed).epsilon(1e-6));
}

TEST_CASE("[PhysicsXPBD] Small and large triangles keep a valid shear gradient") {
	const real_t scales[] = { real_t(1e-8), real_t(1e20) };
	for (const real_t scale : scales) {
		Vector3 a, b(scale, 0, 0), c(scale * real_t(0.5), scale, 0);
		double lambda = 0.0;
		CHECK(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0,
				0.0, 0.0, lambda));
		CHECK(a == Vector3());
		CHECK(b == Vector3(scale, 0, 0));
		CHECK(Math::abs(c.x / scale) < real_t(1e-4));
		CHECK(c.is_finite());
		CHECK(Math::is_finite(lambda));
	}
}

TEST_CASE("[PhysicsXPBD] Invalid and degenerate triangles cannot change state") {
	Vector3 a, b(1, 0, 0), c(2, 0, 0);
	const Vector3 old_c = c;
	double lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, 1.0, 1.0, 1.0, 0.0, 0.0, lambda));
	CHECK(c == old_c);
	c = Vector3(0, 1, 0);
	CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 0.0, 0.0, 0.0, lambda));
	CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, 1.0, 1.0, 1.0, real_t(2.0), 0.0, lambda));
	CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, 1.0, 1.0, 1.0, 0.0,
			std::numeric_limits<real_t>::infinity(), lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3(1, 0, 0));
	CHECK(c == Vector3(0, 1, 0));
	CHECK(lambda == real_t(0.0));
	real_t rest = real_t(0.25);
	CHECK_FALSE(physics_xpbd_triangle_shear_rest_cosine(a, b, old_c, rest));
	CHECK(rest == real_t(0.25));
}

} // namespace TestPhysicsXPBDShear
