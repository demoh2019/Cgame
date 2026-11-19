/**************************************************************************/
/*  test_physics_xpbd_compression_buckling.cpp                            */
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

#include "servers/physics_xpbd_compression_buckling.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_compression_buckling)

namespace TestPhysicsXPBDCompressionBuckling {

TEST_CASE("[PhysicsXPBDBuckling] Disabled ratio leaves baseline XPBD compliance unchanged") {
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(0.25, 0, 0),
			real_t(1.0), real_t(0.25), real_t(0.05), real_t(0.05), real_t(1.0), output));
	CHECK(output == real_t(0.25));
}

TEST_CASE("[PhysicsXPBDBuckling] Tensile deformation is not softened") {
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(2.0, 0, 0),
			real_t(1.0), real_t(0.25), real_t(0.05), real_t(0.05), real_t(100.0), output));
	CHECK(output == real_t(0.25));
}

TEST_CASE("[PhysicsXPBDBuckling] No change at or below compression yield") {
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(0.95, 0, 0),
			real_t(1.0), real_t(0.25), real_t(0.05), real_t(0.1), real_t(9.0), output));
	CHECK(output == real_t(0.25));
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(0.975, 0, 0),
			real_t(1.0), real_t(0.25), real_t(0.05), real_t(0.1), real_t(9.0), output));
	CHECK(output == real_t(0.25));
}

TEST_CASE("[PhysicsXPBDBuckling] Smoothstep halfway gives halfway softening") {
	// Compression 10%, yield 5%, transition 10% -> t = 0.5.
	// smoothstep(0.5) = 0.5. Ratio 9 means compliance multiplier 5.
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(0.9, 0, 0),
			real_t(1.0), real_t(0.25), real_t(0.05), real_t(0.1), real_t(9.0), output));
	CHECK(output == doctest::Approx(1.25).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBDBuckling] Full compression multiplies compliance by ratio") {
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(0.75, 0, 0),
			real_t(1.0), real_t(0.25), real_t(0.05), real_t(0.1), real_t(9.0), output));
	CHECK(output == doctest::Approx(2.25).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBDBuckling] Zero transition makes an abrupt yield response") {
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(0.949, 0, 0),
			real_t(1.0), real_t(0.25), real_t(0.05), real_t(0.0), real_t(9.0), output));
	CHECK(output == doctest::Approx(2.25).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBDBuckling] Collapsed link is maximally softened, not NaN") {
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			real_t(1.0), real_t(0.25), real_t(0.05), real_t(0.1), real_t(9.0), output));
	CHECK(output == doctest::Approx(2.25).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBDBuckling] Zero rest length skips material transformation") {
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			real_t(0.0), real_t(0.25), real_t(0.05), real_t(0.1), real_t(9.0), output));
	CHECK(output == real_t(0.25));
}

TEST_CASE("[PhysicsXPBDBuckling] Position translation and link reversal leave compliance invariant") {
	real_t base = real_t(-1.0);
	real_t translated = real_t(-1.0);
	real_t reversed = real_t(-1.0);
	const Vector3 a(1.0, 0.0, 0.0);
	const Vector3 b(1.4, 0.0, 0.0);
	CHECK(physics_xpbd_compression_buckling_alpha(a, b, 1.0, 0.2, 0.1, 0.2, 9.0, base));
	CHECK(physics_xpbd_compression_buckling_alpha(a + Vector3(100, 200, 300),
			b + Vector3(100, 200, 300), 1.0, 0.2, 0.1, 0.2, 9.0, translated));
	CHECK(physics_xpbd_compression_buckling_alpha(b, a, 1.0, 0.2, 0.1, 0.2, 9.0, reversed));
	CHECK(base == doctest::Approx(translated).epsilon(1e-5));
	CHECK(base == doctest::Approx(reversed).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBDBuckling] At yield strain one no compression is sufficient") {
	real_t output = real_t(-1.0);
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			1.0, 0.25, 1.0, 0.05, 100.0, output));
	CHECK(output == real_t(0.25));
}

TEST_CASE("[PhysicsXPBDBuckling] Extremely large alpha safely saturates") {
	real_t output = real_t(-1.0);
	const real_t huge = std::numeric_limits<real_t>::max();
	CHECK(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			real_t(1.0), huge, real_t(0.0), real_t(0.1), huge, output));
	CHECK(Math::is_finite(output));
	CHECK(output == huge);
}

TEST_CASE("[PhysicsXPBDBuckling] Invalid input must not mutate the output") {
	const real_t infinity = std::numeric_limits<real_t>::infinity();
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	real_t output = real_t(42.0);
	CHECK_FALSE(physics_xpbd_compression_buckling_alpha(Vector3(infinity, 0, 0), Vector3(),
			1, 1, 0.05, 0.1, 2, output));
	CHECK_FALSE(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			-1, 1, 0.05, 0.1, 2, output));
	CHECK_FALSE(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			1, -1, 0.05, 0.1, 2, output));
	CHECK_FALSE(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			1, 1, -0.05, 0.1, 2, output));
	CHECK_FALSE(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			1, 1, 0.05, -0.1, 2, output));
	CHECK_FALSE(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			1, 1, 0.05, 0.1, 0.5, output));
	CHECK_FALSE(physics_xpbd_compression_buckling_alpha(Vector3(), Vector3(),
			1, 1, 0.05, 0.1, nan, output));
	CHECK(output == real_t(42.0));
}

} // namespace TestPhysicsXPBDCompressionBuckling
