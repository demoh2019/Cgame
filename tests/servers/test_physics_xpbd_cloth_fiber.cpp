/**************************************************************************/
/*  test_physics_xpbd_cloth_fiber.cpp                                      */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_xpbd_cloth_fiber)

#include "servers/physics_xpbd_cloth_fiber.h"

#include <limits>

namespace TestPhysicsXPBDClothFiber {

TEST_CASE("[Physics] Orthotropic cloth warp and weft compliances follow rest fibers") {
	const Vector3 origin;
	const Vector3 fiber(1, 0, 0);
	const real_t isotropic = 4.0;
	real_t alpha = -1.0;
	REQUIRE(physics_xpbd_cloth_fiber_alpha(origin, Vector3(2, 0, 0),
			fiber, real_t(0.25), isotropic, alpha));
	CHECK(Math::abs(alpha - real_t(1.0)) < real_t(1e-5)); // Warp: stiffer.
	REQUIRE(physics_xpbd_cloth_fiber_alpha(origin, Vector3(0, 2, 0),
			fiber, real_t(0.25), isotropic, alpha));
	CHECK(Math::abs(alpha - real_t(4.0)) < real_t(1e-5)); // Weft: unchanged.
	REQUIRE(physics_xpbd_cloth_fiber_alpha(origin, Vector3(2, 2, 0),
			fiber, real_t(0.25), isotropic, alpha));
	CHECK(Math::abs(alpha - real_t(2.5)) < real_t(1e-5)); // cos² = 0.5.
	REQUIRE(physics_xpbd_cloth_fiber_alpha(origin, Vector3(3, 0, 0),
			fiber, real_t(4.0), isotropic, alpha));
	CHECK(Math::abs(alpha - real_t(16.0)) < real_t(1e-5)); // Warp: softer.
}

TEST_CASE("[Physics] Orthotropic cloth axis reversal and rigid rest translations are invariant") {
	const Vector3 a(3, 4, 5), b(4, 6, 7);
	const Vector3 offset(100, -50, 7);
	real_t reference = -1, reverse = -1, translated = -1, scaled_axis = -1;
	REQUIRE(physics_xpbd_cloth_fiber_alpha(a, b, Vector3(0, 1, 0),
			real_t(0.3), real_t(5.0), reference));
	REQUIRE(physics_xpbd_cloth_fiber_alpha(b, a, Vector3(0, -1, 0),
			real_t(0.3), real_t(5.0), reverse));
	REQUIRE(physics_xpbd_cloth_fiber_alpha(a + offset, b + offset,
			Vector3(0, 1, 0), real_t(0.3), real_t(5.0), translated));
	REQUIRE(physics_xpbd_cloth_fiber_alpha(a, b, Vector3(0, 4, 0),
			real_t(0.3), real_t(5.0), scaled_axis));
	CHECK(Math::abs(reference - reverse) < real_t(1e-5));
	CHECK(Math::abs(reference - translated) < real_t(1e-5));
	CHECK(Math::abs(reference - scaled_axis) < real_t(1e-5));
}

TEST_CASE("[Physics] Orthotropic cloth handles zero and isotropic ratios") {
	real_t alpha = 99.0;
	REQUIRE(physics_xpbd_cloth_fiber_alpha(Vector3(), Vector3(1, 0, 0),
			Vector3(1, 0, 0), real_t(0.0), real_t(3.0), alpha));
	CHECK(alpha == real_t(0.0)); // Idealized inextensible warp.
	REQUIRE(physics_xpbd_cloth_fiber_alpha(Vector3(), Vector3(0, 1, 0),
			Vector3(1, 0, 0), real_t(0.0), real_t(3.0), alpha));
	CHECK(alpha == real_t(3.0));
	REQUIRE(physics_xpbd_cloth_fiber_alpha(Vector3(), Vector3(1, 1, 1),
			Vector3(1, 0, 0), real_t(1.0), real_t(3.0), alpha));
	CHECK(Math::abs(alpha - real_t(3.0)) < real_t(1e-5));
}

TEST_CASE("[Physics] Orthotropic cloth rejects degenerate and nonfinite input without mutation") {
	const Vector3 origin;
	real_t alpha = 42.0;
	CHECK_FALSE(physics_xpbd_cloth_fiber_alpha(origin, origin, Vector3(1, 0, 0),
			real_t(0.25), real_t(2.0), alpha));
	CHECK_FALSE(physics_xpbd_cloth_fiber_alpha(origin, Vector3(1, 0, 0), Vector3(),
			real_t(0.25), real_t(2.0), alpha));
	CHECK_FALSE(physics_xpbd_cloth_fiber_alpha(origin, Vector3(1, 0, 0),
			Vector3(1, 0, 0), real_t(-1.0), real_t(2.0), alpha));
	CHECK_FALSE(physics_xpbd_cloth_fiber_alpha(origin, Vector3(1, 0, 0),
			Vector3(1, 0, 0), real_t(0.25),
			std::numeric_limits<real_t>::infinity(), alpha));
	CHECK(alpha == real_t(42.0));

	// Extremely soft fibers are capped to finite engine real_t.
	REQUIRE(physics_xpbd_cloth_fiber_alpha(origin, Vector3(1, 0, 0),
			Vector3(1, 0, 0), real_t(100.0),
			std::numeric_limits<real_t>::max(), alpha));
	CHECK(Math::is_finite(alpha));
	CHECK(alpha == std::numeric_limits<real_t>::max());
}

} // namespace TestPhysicsXPBDClothFiber
