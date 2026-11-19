/**************************************************************************/
/*  test_physics_xpbd_compression_hardening.cpp                           */
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

#include "servers/physics_xpbd_compression_hardening.h"
#include "servers/physics_xpbd_distance.h"
#include "servers/physics_xpbd_tension_hardening.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_compression_hardening)

namespace TestPhysicsXPBDCompressionHardening {

TEST_CASE("[PhysicsXPBD] Compression hardening activates only past compressive yield") {
	real_t alpha = real_t(99.0);
	CHECK(physics_xpbd_compression_hardening_alpha(
			Vector3(), Vector3(real_t(0.9), 0, 0), 1, 1, real_t(0.2), 100, alpha));
	CHECK(Math::is_equal_approx(alpha, real_t(1.0)));
	CHECK(physics_xpbd_compression_hardening_alpha(
			Vector3(), Vector3(real_t(0.5), 0, 0), 1, 1, real_t(0.2), 100, alpha));
	CHECK(Math::abs(alpha - real_t(0.1)) < real_t(0.0001));
}

TEST_CASE("[PhysicsXPBD] Compression law leaves stretching links unchanged") {
	real_t alpha = real_t(42.0);
	CHECK(physics_xpbd_compression_hardening_alpha(Vector3(), Vector3(2, 0, 0),
			1, real_t(0.25), 0, 1000, alpha));
	CHECK(alpha == real_t(0.25));
}

TEST_CASE("[PhysicsXPBD] Combined hardening independently handles tension and compression") {
	real_t tension_alpha = 1.0;
	CHECK(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(2, 0, 0),
			1, 1, 0, 100, tension_alpha));
	const real_t before = tension_alpha;
	CHECK(physics_xpbd_compression_hardening_alpha(Vector3(), Vector3(2, 0, 0),
			1, tension_alpha, 0, 100, tension_alpha));
	CHECK(tension_alpha == before);
	CHECK(tension_alpha < real_t(1.0));

	real_t compression_alpha = 1.0;
	CHECK(physics_xpbd_tension_hardening_alpha(Vector3(), Vector3(real_t(0.25), 0, 0),
			1, 1, 0, 100, compression_alpha));
	CHECK(compression_alpha == real_t(1.0));
	CHECK(physics_xpbd_compression_hardening_alpha(Vector3(), Vector3(real_t(0.25), 0, 0),
			1, compression_alpha, 0, 100, compression_alpha));
	CHECK(compression_alpha < real_t(1.0));
}

TEST_CASE("[PhysicsXPBD] Harder compression reduces deformation and leaves pins fixed") {
	Vector3 linear_a, linear_b(real_t(0.5), 0, 0);
	Vector3 harder_a, harder_b(real_t(0.5), 0, 0);
	real_t alpha = 1;
	CHECK(physics_xpbd_compression_hardening_alpha(harder_a, harder_b,
			1, 1, 0, 100, alpha));
	real_t linear_lambda = 0, harder_lambda = 0;
	for (int iteration = 0; iteration < 24; ++iteration) {
		CHECK(physics_xpbd_solve_distance(linear_a, linear_b, 0, 1, 1, 1, linear_lambda));
		CHECK(physics_xpbd_solve_distance(harder_a, harder_b, 0, 1, 1, alpha, harder_lambda));
	}
	CHECK(harder_a == Vector3());
	CHECK(linear_a == Vector3());
	CHECK(harder_b.x > linear_b.x);
	CHECK(harder_b.x < real_t(1.0));
	CHECK(harder_b.is_finite());
}

TEST_CASE("[PhysicsXPBD] Compression hardening saturates safely for collapsed links") {
	real_t alpha = 1.0;
	CHECK(physics_xpbd_compression_hardening_alpha(
			Vector3(), Vector3(), real_t(1.0), alpha, 0, real_t(1e10), alpha));
	CHECK(alpha > real_t(0.0));
	CHECK(alpha < real_t(1e-4));
	CHECK(Math::is_finite(alpha));
}

TEST_CASE("[PhysicsXPBD] Invalid and degenerate material parameters are safe") {
	real_t alpha = real_t(123.0);
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK_FALSE(physics_xpbd_compression_hardening_alpha(Vector3(nan, 0, 0), Vector3(),
			1, 1, 0, 1, alpha));
	CHECK_FALSE(physics_xpbd_compression_hardening_alpha(Vector3(), Vector3(1, 0, 0),
			-1, 1, 0, 1, alpha));
	CHECK_FALSE(physics_xpbd_compression_hardening_alpha(Vector3(), Vector3(1, 0, 0),
			1, -1, 0, 1, alpha));
	CHECK_FALSE(physics_xpbd_compression_hardening_alpha(Vector3(), Vector3(1, 0, 0),
			1, 1, -1, 1, alpha));
	CHECK_FALSE(physics_xpbd_compression_hardening_alpha(Vector3(), Vector3(1, 0, 0),
			1, 1, 0, nan, alpha));
	CHECK(alpha == real_t(123.0));
}

} // namespace TestPhysicsXPBDCompressionHardening
