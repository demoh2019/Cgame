/**************************************************************************/
/*  test_physics_xpbd_fiber.cpp                                           */
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

#include "servers/physics_xpbd_distance.h"
#include "servers/physics_xpbd_fiber.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_fiber)

namespace TestPhysicsXPBDFiber {

TEST_CASE("[PhysicsXPBDFiber] Fiber direction controls longitudinal compliance") {
	const Vector3 zero;
	const real_t alpha = real_t(0.1);
	CHECK(physics_xpbd_fiber_alpha(zero, Vector3(2, 0, 0), alpha, 0, 4.0) == doctest::Approx(0.4));
	CHECK(physics_xpbd_fiber_alpha(zero, Vector3(0, 2, 0), alpha, 0, 4.0) == doctest::Approx(0.1));
	CHECK(physics_xpbd_fiber_alpha(zero, Vector3(1, 1, 0), alpha, 0, 4.0) == doctest::Approx(0.25));
	CHECK(physics_xpbd_fiber_alpha(zero, Vector3(0, 0, 2), alpha, 2, 0.25) == doctest::Approx(0.025));
	CHECK(physics_xpbd_fiber_alpha(zero, Vector3(0, 2, 0), alpha, 1, 0.25) == doctest::Approx(0.025));
}

TEST_CASE("[PhysicsXPBDFiber] Compliance is invariant to link reversal and source translation") {
	const real_t forward = physics_xpbd_fiber_alpha(Vector3(1, 2, 3), Vector3(3, 5, 3),
			real_t(0.1), 1, real_t(3.0));
	const real_t reversed = physics_xpbd_fiber_alpha(Vector3(3, 5, 3), Vector3(1, 2, 3),
			real_t(0.1), 1, real_t(3.0));
	const real_t moved = physics_xpbd_fiber_alpha(Vector3(101, 52, -37), Vector3(103, 55, -37),
			real_t(0.1), 1, real_t(3.0));
	CHECK(forward == doctest::Approx(reversed));
	CHECK(forward == doctest::Approx(moved));
}

TEST_CASE("[PhysicsXPBDFiber] Directional compliant cloth deforms more along soft fibers") {
	Vector3 a_parallel, b_parallel(2, 0, 0);
	Vector3 a_cross, b_cross(0, 2, 0);
	real_t lambda_parallel = 0.0;
	real_t lambda_cross = 0.0;
	const real_t alpha_parallel = physics_xpbd_fiber_alpha(Vector3(), Vector3(1, 0, 0), 0.1, 0, 4.0);
	const real_t alpha_cross = physics_xpbd_fiber_alpha(Vector3(), Vector3(0, 1, 0), 0.1, 0, 4.0);
	CHECK(physics_xpbd_solve_distance(a_parallel, b_parallel, 0.0, 1.0, 1.0, alpha_parallel, lambda_parallel));
	CHECK(physics_xpbd_solve_distance(a_cross, b_cross, 0.0, 1.0, 1.0, alpha_cross, lambda_cross));
	CHECK(a_parallel == Vector3());
	CHECK(a_cross == Vector3());
	CHECK(b_parallel.x > b_cross.y);
	CHECK(b_parallel.is_finite());
	CHECK(b_cross.is_finite());
}

TEST_CASE("[PhysicsXPBDFiber] Isotropic default and zero compliance preserve legacy links") {
	const Vector3 a(0, 0, 0), b(1, 2, 3);
	CHECK(physics_xpbd_fiber_alpha(a, b, 0.1, 0, 1.0) == doctest::Approx(0.1));
	CHECK(physics_xpbd_fiber_alpha(a, b, 0.1, -1, 4.0) == doctest::Approx(0.1));
	CHECK(physics_xpbd_fiber_alpha(a, b, 0.0, 0, 4.0) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsXPBDFiber] Extreme finite rest lengths avoid squared-length overflow") {
	for (real_t scale : { real_t(1e-12), real_t(1e20) }) {
		const real_t diagonal = physics_xpbd_fiber_alpha(Vector3(), Vector3(scale, scale, 0),
				real_t(0.1), 0, real_t(4.0));
		CHECK(diagonal == doctest::Approx(0.25).epsilon(1e-5));
	}
}

TEST_CASE("[PhysicsXPBDFiber] Degenerate, invalid and overflowed inputs are bounded") {
	const Vector3 a, b(1, 0, 0);
	CHECK(physics_xpbd_fiber_alpha(a, a, 0.1, 0, 4.0) == doctest::Approx(0.1));
	CHECK(physics_xpbd_fiber_alpha(a, b, 0.1, 6, 4.0) == doctest::Approx(0.1));
	CHECK(physics_xpbd_fiber_alpha(a, b, 0.1, 0, -1.0) == doctest::Approx(0.1));
	CHECK(physics_xpbd_fiber_alpha(a, b, 0.1, 0, std::numeric_limits<real_t>::infinity()) == doctest::Approx(0.1));
	CHECK(physics_xpbd_fiber_alpha(a, b, std::numeric_limits<real_t>::infinity(), 0, 2.0) == real_t(0.0));
	const real_t large = physics_xpbd_fiber_alpha(a, b, std::numeric_limits<real_t>::max(), 0, 10.0);
	CHECK(Math::is_finite(large));
	CHECK(large == std::numeric_limits<real_t>::max());
}

} // namespace TestPhysicsXPBDFiber
