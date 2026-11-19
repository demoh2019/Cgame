/**************************************************************************/
/*  test_physics_softbody_strain_rate_damping.cpp                         */
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

#include "servers/physics_softbody_strain_rate_damping.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_strain_rate_damping)

namespace TestPhysicsSoftBodyStrainRateDamping {

TEST_CASE("[PhysicsSoftBody] Relative strain rate below yield is not damped") {
	Vector3 a(1, 2, 0), b(4, 5, 0);
	CHECK_FALSE(physics_softbody_damp_strain_rate(Vector3(), Vector3(2, 0, 0),
			a, b, 1, 1, 2, 1, 2, 1.0));
	CHECK(a == Vector3(1, 2, 0));
	CHECK(b == Vector3(4, 5, 0));
}

TEST_CASE("[PhysicsSoftBody] Nonlinear damping is stronger at high strain rates") {
	Vector3 slow_a, slow_b(2, 3, 0);
	Vector3 fast_a, fast_b(10, 3, 0);
	CHECK(physics_softbody_damp_strain_rate(Vector3(), Vector3(1, 0, 0),
			slow_a, slow_b, 1, 1, 1, 1, 0, 0.1));
	CHECK(physics_softbody_damp_strain_rate(Vector3(), Vector3(1, 0, 0),
			fast_a, fast_b, 1, 1, 1, 1, 0, 0.1));
	const real_t slow_fraction = 1.0 - (slow_b.x - slow_a.x) / real_t(2.0);
	const real_t fast_fraction = 1.0 - (fast_b.x - fast_a.x) / real_t(10.0);
	CHECK(slow_fraction > real_t(0.0));
	CHECK(fast_fraction > slow_fraction);
	CHECK(slow_b.y == real_t(3.0));
	CHECK(fast_b.y == real_t(3.0));
}

TEST_CASE("[PhysicsSoftBody] Unequal masses keep total momentum and dissipate kinetic energy") {
	Vector3 a, b(9, 2, 0);
	const real_t original_energy = (a.length_squared() * 3 + b.length_squared()) * real_t(0.5);
	CHECK(physics_softbody_damp_strain_rate(Vector3(), Vector3(1, 0, 0),
			a, b, real_t(1.0 / 3.0), 1, 1, 2, 0, 0.25));
	CHECK(a.x * 3 + b.x == doctest::Approx(9.0));
	CHECK(a.y == real_t(0.0));
	CHECK(b.y == real_t(2.0));
	const real_t energy = (a.length_squared() * 3 + b.length_squared()) * real_t(0.5);
	CHECK(energy <= original_energy);
	CHECK(a.is_finite());
	CHECK(b.is_finite());
}

TEST_CASE("[PhysicsSoftBody] A pinned vertex and tangential motion remain unchanged") {
	Vector3 pin(0, 1, 0), free(10, 7, 0);
	CHECK(physics_softbody_damp_strain_rate(Vector3(), Vector3(1, 0, 0),
			pin, free, 0, 2, 1, 1, 0, 0.2));
	CHECK(pin == Vector3(0, 1, 0));
	CHECK(free.x < real_t(10.0));
	CHECK(free.x >= real_t(0.0));
	CHECK(free.y == real_t(7.0));
}

TEST_CASE("[PhysicsSoftBody] More integration time produces stronger damping") {
	Vector3 short_a, short_b(4, 0, 0);
	Vector3 long_a, long_b(4, 0, 0);
	CHECK(physics_softbody_damp_strain_rate(Vector3(), Vector3(1, 0, 0),
			short_a, short_b, 1, 1, 1, 1, 0, 0.01));
	CHECK(physics_softbody_damp_strain_rate(Vector3(), Vector3(1, 0, 0),
			long_a, long_b, 1, 1, 1, 1, 0, 0.5));
	CHECK((long_b.x - long_a.x) < (short_b.x - short_a.x));
	CHECK((short_b.x - short_a.x) < real_t(4.0));
}

TEST_CASE("[PhysicsSoftBody] Extreme strain rates saturate without NaN") {
	Vector3 a, b(real_t(1e20), 0, 0);
	CHECK(physics_softbody_damp_strain_rate(Vector3(real_t(-1e20), 0, 0),
			Vector3(real_t(1e20), 0, 0), a, b,
			1, 1, real_t(1e-6), 1000, 0, 1.0));
	CHECK(a.is_finite());
	CHECK(b.is_finite());
	CHECK(Math::is_equal_approx(a.x, b.x));
}

TEST_CASE("[PhysicsSoftBody] Invalid inputs never mutate either velocity") {
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	Vector3 a(1, 2, 3), b(4, 5, 6);
	const Vector3 before_a = a, before_b = b;
	const Vector3 origin, end(1, 0, 0);
	CHECK_FALSE(physics_softbody_damp_strain_rate(origin, end, a, b, 1, 1,
			0, 1, 0, 1));
	CHECK_FALSE(physics_softbody_damp_strain_rate(origin, end, a, b, 1, 1,
			1, 0, 0, 1));
	CHECK_FALSE(physics_softbody_damp_strain_rate(origin, end, a, b, 1, 1,
			1, 1, -1, 1));
	CHECK_FALSE(physics_softbody_damp_strain_rate(origin, end, a, b, -1, 1,
			1, 1, 0, 1));
	CHECK_FALSE(physics_softbody_damp_strain_rate(origin, end, a, b, 1, 1,
			1, 1, 0, nan));
	CHECK_FALSE(physics_softbody_damp_strain_rate(Vector3(nan, 0, 0), end, a, b, 1, 1,
			1, 1, 0, 1));
	CHECK_FALSE(physics_softbody_damp_strain_rate(origin, origin, a, b, 1, 1,
			1, 1, 0, 1));
	CHECK(a == before_a);
	CHECK(b == before_b);
}

} // namespace TestPhysicsSoftBodyStrainRateDamping
