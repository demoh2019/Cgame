/**************************************************************************/
/*  test_physics_xpbd_anisotropic_stretch.cpp                             */
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

#include "servers/physics_xpbd_anisotropic_stretch.h"
#include "servers/physics_xpbd_compression_hardening.h"
#include "servers/physics_xpbd_distance.h"
#include "servers/physics_xpbd_tension_hardening.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_anisotropic_stretch)

namespace TestPhysicsXPBDAnisotropicStretch {

TEST_CASE("[PhysicsXPBD] Material direction distinguishes warp and weft compliance") {
	real_t parallel = 123, perpendicular = 123, diagonal = 123;
	const Vector3 axis(1, 0, 0);
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(2, 0, 0),
			axis, 1, real_t(0.1), parallel));
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(0, 2, 0),
			axis, 1, real_t(0.1), perpendicular));
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(2, 2, 0),
			axis, 1, real_t(0.1), diagonal));
	CHECK(parallel == doctest::Approx(0.1));
	CHECK(perpendicular == doctest::Approx(1.0));
	CHECK(diagonal == doctest::Approx(0.55));
}

TEST_CASE("[PhysicsXPBD] Material ratio one preserves legacy XPBD exactly") {
	real_t alpha = 99;
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(0, 0, 0), Vector3(5, 4, 3),
			Vector3(3, 2, 1), real_t(0.0625), 1, alpha));
	CHECK(alpha == real_t(0.0625));
}

TEST_CASE("[PhysicsXPBD] Orthotropic axis magnitude and orientation do not change results") {
	real_t alpha_x = 0, alpha_scaled = 0, alpha_reversed = 0;
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(2, 1, 0),
			Vector3(1, 0, 0), 1, 3, alpha_x));
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(2, 1, 0),
			Vector3(100, 0, 0), 1, 3, alpha_scaled));
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(2, 1, 0),
			Vector3(-100, 0, 0), 1, 3, alpha_reversed));
	CHECK(alpha_x == doctest::Approx(alpha_scaled));
	CHECK(alpha_x == doctest::Approx(alpha_reversed));
	CHECK(alpha_x == doctest::Approx(2.6));
}

TEST_CASE("[PhysicsXPBD] Rotating mesh and material frame together preserves compliance") {
	real_t before = 0, after = 0;
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(2, 1, 0),
			Vector3(1, 0, 0), 2, real_t(0.25), before));
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(-1, 2, 0),
			Vector3(0, 1, 0), 2, real_t(0.25), after));
	CHECK(before == doctest::Approx(after));
}

TEST_CASE("[PhysicsXPBD] Material fiber with low compliance resists stretch") {
	Vector3 normal_a, normal_b(2, 0, 0);
	Vector3 fiber_a, fiber_b(2, 0, 0);
	real_t parallel_alpha = 100;
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(1, 0, 0),
			Vector3(1, 0, 0), 1, real_t(0.1), parallel_alpha));
	real_t standard_lambda = 0, fiber_lambda = 0;
	for (int i = 0; i < 25; i++) {
		CHECK(physics_xpbd_solve_distance(normal_a, normal_b, 0, 1, 1, 1, standard_lambda));
		CHECK(physics_xpbd_solve_distance(fiber_a, fiber_b, 0, 1, 1, parallel_alpha, fiber_lambda));
	}
	CHECK(normal_a == Vector3());
	CHECK(fiber_a == Vector3());
	CHECK(fiber_b.x < normal_b.x);
	CHECK(fiber_b.x > real_t(1.0));
}

TEST_CASE("[PhysicsXPBD] Fiber alpha combines with nonlinear tension and compression") {
	real_t stretch_alpha = 1;
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(1, 0, 0),
			Vector3(1, 0, 0), 1, real_t(0.5), stretch_alpha));
	CHECK(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(2, 0, 0),
			1, stretch_alpha, 0, 10, stretch_alpha));
	CHECK(stretch_alpha < real_t(0.5));

	real_t compression_alpha = 1;
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(1, 0, 0),
			Vector3(1, 0, 0), 1, real_t(0.5), compression_alpha));
	CHECK(physics_xpbd_compression_hardening_alpha(Vector3(), Vector3(real_t(0.5), 0, 0),
			1, compression_alpha, 0, 10, compression_alpha));
	CHECK(compression_alpha < real_t(0.5));
}

TEST_CASE("[PhysicsXPBD] Degenerate rest edges do not create undefined fiber direction") {
	real_t alpha = 7;
	CHECK(physics_xpbd_anisotropic_stretch_alpha(Vector3(), Vector3(),
			Vector3(1, 0, 0), 3, 2, alpha));
	CHECK(alpha == real_t(3.0));
}

TEST_CASE("[PhysicsXPBD] Large finite rest mesh coordinates remain safe") {
	real_t alpha = 17;
	CHECK(physics_xpbd_anisotropic_stretch_alpha(
			Vector3(real_t(-1e20), 0, 0), Vector3(real_t(1e20), 0, 0),
			Vector3(real_t(1e20), 0, 0), 1, real_t(0.2), alpha));
	CHECK(Math::is_finite(alpha));
	CHECK(alpha == doctest::Approx(0.2));
}

TEST_CASE("[PhysicsXPBD] Invalid values are rejected without mutating alpha") {
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	real_t alpha = 123;
	CHECK_FALSE(physics_xpbd_anisotropic_stretch_alpha(Vector3(nan, 0, 0),
			Vector3(1, 0, 0), Vector3(1, 0, 0), 1, 0.5, alpha));
	CHECK_FALSE(physics_xpbd_anisotropic_stretch_alpha(Vector3(),
			Vector3(1, 0, 0), Vector3(nan, 0, 0), 1, 0.5, alpha));
	CHECK_FALSE(physics_xpbd_anisotropic_stretch_alpha(Vector3(),
			Vector3(1, 0, 0), Vector3(), 1, 0.5, alpha));
	CHECK_FALSE(physics_xpbd_anisotropic_stretch_alpha(Vector3(),
			Vector3(1, 0, 0), Vector3(1, 0, 0), -1, 0.5, alpha));
	CHECK_FALSE(physics_xpbd_anisotropic_stretch_alpha(Vector3(),
			Vector3(1, 0, 0), Vector3(1, 0, 0), 1, -0.5, alpha));
	CHECK(alpha == real_t(123.0));
}

} // namespace TestPhysicsXPBDAnisotropicStretch
