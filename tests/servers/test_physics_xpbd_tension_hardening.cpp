/**************************************************************************/
/*  test_physics_xpbd_tension_hardening.cpp                               */
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

#include "servers/physics_xpbd_distance.h"
#include "servers/physics_xpbd_tension_hardening.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_tension_hardening)

namespace TestPhysicsXPBDTensionHardening {

TEST_CASE("[PhysicsXPBD] Tension hardening activates only beyond elastic yield") {
	real_t alpha = real_t(99.0);
	CHECK(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(real_t(1.1), 0, 0),
			1, 1, real_t(0.2), 100, alpha));
	CHECK(Math::is_equal_approx(alpha, real_t(1.0)));
	CHECK(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(real_t(1.5), 0, 0),
			1, 1, real_t(0.2), 100, alpha));
	CHECK(Math::abs(alpha - real_t(0.1)) < real_t(0.0001));
}

TEST_CASE("[PhysicsXPBD] Nonlinear material reduces extension at large strain") {
	Vector3 linear_a, linear_b(3, 0, 0);
	Vector3 harder_a, harder_b(3, 0, 0);
	real_t alpha = real_t(1.0);
	CHECK(physics_xpbd_tension_hardening_alpha(harder_a, harder_b,
			1, 1, 0, 100, alpha));
	CHECK(alpha > 0.0);
	CHECK(alpha < 1.0);
	real_t linear_lambda = 0, harder_lambda = 0;
	for (int iteration = 0; iteration < 32; ++iteration) {
		CHECK(physics_xpbd_solve_distance(linear_a, linear_b,
				1, 1, 1, 1, linear_lambda));
		CHECK(physics_xpbd_solve_distance(harder_a, harder_b,
				1, 1, 1, alpha, harder_lambda));
	}
	CHECK((harder_b - harder_a).length() < (linear_b - linear_a).length());
	CHECK((harder_b - harder_a).length() > real_t(1.0));
	CHECK(harder_a.is_finite());
	CHECK(harder_b.is_finite());
}

TEST_CASE("[PhysicsXPBD] Compression never activates tensile hardening") {
	real_t alpha = real_t(99.0);
	CHECK(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(real_t(0.2), 0, 0),
			1, real_t(0.25), 0, 100000, alpha));
	CHECK(alpha == real_t(0.25));
}

TEST_CASE("[PhysicsXPBD] Hardening preserves pins and fixed-alpha solver convergence") {
	Vector3 a(0, 0, 0), b(2, 0, 0);
	real_t alpha = 1;
	CHECK(physics_xpbd_tension_hardening_alpha(a, b, 1, 1, 0, 80, alpha));
	real_t lambda = 0;
	for (int i = 0; i < 40; ++i) {
		CHECK(physics_xpbd_solve_distance(a, b, 0, 1, 1, alpha, lambda));
	}
	CHECK(a == Vector3());
	CHECK(Math::abs(b.x - (1 + alpha / (1 + alpha))) < real_t(0.00001));
}

TEST_CASE("[PhysicsXPBD] Nonlinear response handles extreme finite coordinates") {
	real_t alpha = 1.0;
	CHECK(physics_xpbd_tension_hardening_alpha(
			Vector3(real_t(-1e20), 0, 0), Vector3(real_t(1e20), 0, 0),
			real_t(1e-6), 1, 0, real_t(1e10), alpha));
	CHECK(alpha >= 0.0);
	CHECK(alpha < real_t(1e-4));
	CHECK(Math::is_finite(alpha));
}

TEST_CASE("[PhysicsXPBD] Invalid material parameters cannot change output") {
	real_t alpha = real_t(123.0);
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK_FALSE(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(1, 0, 0),
			1, 1, 0, nan, alpha));
	CHECK_FALSE(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(1, 0, 0),
			1, -1, 0, 1, alpha));
	CHECK_FALSE(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(1, 0, 0),
			1, 1, -1, 1, alpha));
	CHECK_FALSE(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(1, 0, 0),
			-1, 1, 0, 1, alpha));
	CHECK_FALSE(physics_xpbd_tension_hardening_alpha(Vector3(nan, 0, 0), Vector3(1, 0, 0),
			1, 1, 0, 1, alpha));
	CHECK(alpha == real_t(123.0));
}

} // namespace TestPhysicsXPBDTensionHardening
