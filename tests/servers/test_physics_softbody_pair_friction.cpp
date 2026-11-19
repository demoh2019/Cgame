/**************************************************************************/
/*  test_physics_softbody_pair_friction.cpp                              */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_softbody_pair_contact.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_pair_friction)

namespace TestPhysicsSoftBodyPairFriction {

static const Vector3 POINT(0.2, 0.3, 0.01);
static const Vector3 A(0, 0, 0);
static const Vector3 B(1, 0, 0);
static const Vector3 C(0, 1, 0);

static Vector3 relative_tangent(const Vector3 &p_vertex, const Vector3 &p_a,
		const Vector3 &p_b, const Vector3 &p_c) {
	// Barycentric weights at (0.2, 0.3): 0.5 / 0.2 / 0.3.
	const Vector3 relative = p_vertex - (p_a * 0.5 + p_b * 0.2 + p_c * 0.3);
	return Vector3(relative.x, relative.y, 0.0);
}

TEST_CASE("[PhysicsSoftSoftFriction] High friction removes tangential relative velocity") {
	Vector3 v(3, 4, 0), a, b, c;
	const Vector3 momentum_before = v + a + b + c;
	const double energy_before = v.length_squared() + a.length_squared() +
			b.length_squared() + c.length_squared();
	CHECK(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.1, 0.1));
	CHECK(relative_tangent(v, a, b, c).length() < real_t(1e-5));
	CHECK((v + a + b + c).is_equal_approx(momentum_before));
	const double energy_after = v.length_squared() + a.length_squared() +
			b.length_squared() + c.length_squared();
	CHECK(energy_after <= energy_before + 1e-5);
	CHECK(v.z == doctest::Approx(0.0));
	CHECK(a.z == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsSoftSoftFriction] Unequal masses conserve momentum and dissipate energy") {
	Vector3 v(6, 2, 1), a, b, c;
	const real_t inv_a = 2.0, inv_b = 0.5, inv_c = 3.0;
	const Vector3 momentum_before = v + a / inv_a + b / inv_b + c / inv_c;
	const double energy_before = double(v.length_squared()) +
			double(a.length_squared()) / double(inv_a) +
			double(b.length_squared()) / double(inv_b) +
			double(c.length_squared()) / double(inv_c);
	CHECK(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, inv_a, inv_b, inv_c, 1.0, 2.0, 0.1, 0.1));
	CHECK((v + a / inv_a + b / inv_b + c / inv_c).is_equal_approx(momentum_before));
	CHECK(relative_tangent(v, a, b, c).length() < real_t(1e-5));
	const double energy_after = double(v.length_squared()) +
			double(a.length_squared()) / double(inv_a) +
			double(b.length_squared()) / double(inv_b) +
			double(c.length_squared()) / double(inv_c);
	CHECK(energy_after <= energy_before + 1e-5);
	CHECK(v.z == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsSoftSoftFriction] Coulomb cap limits impulse and reduces slip") {
	Vector3 v(3, 4, 5), a, b, c;
	const real_t initial_speed = relative_tangent(v, a, b, c).length();
	// Impulse budget = mu * normal_lambda / dt = 0.2.
	const double budget = 0.2;
	CHECK(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, 1.0, 1.0, 1.0, 0.2, 0.1, 0.1, 0.1));
	const real_t result_speed = relative_tangent(v, a, b, c).length();
	CHECK(result_speed < initial_speed);
	CHECK(result_speed == doctest::Approx(double(initial_speed) - 1.38 * budget).epsilon(1e-5));
	CHECK(v.z == doctest::Approx(5.0)); // Normal velocity is untouched.
}

TEST_CASE("[PhysicsSoftSoftFriction] Pinned face keeps both positions and velocities") {
	Vector3 v(4, 0, 0), a, b, c;
	CHECK(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.1, 0.1));
	CHECK(v.x == doctest::Approx(0.0));
	CHECK(a == Vector3());
	CHECK(b == Vector3());
	CHECK(c == Vector3());
}

TEST_CASE("[PhysicsSoftSoftFriction] Pinned vertex transmits friction to moving face") {
	Vector3 v, a(2, 0, 0), b(2, 0, 0), c(2, 0, 0);
	CHECK(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.1, 0.1));
	CHECK(v == Vector3());
	CHECK(a.x < 2.0);
	CHECK(b.x < 2.0);
	CHECK(c.x < 2.0);
	CHECK(relative_tangent(v, a, b, c).length() < real_t(1e-5));
}

TEST_CASE("[PhysicsSoftSoftFriction] No slip or normal reaction produces no impulse") {
	Vector3 v(4, 0, 2), a(4, 0, 2), b(4, 0, 2), c(4, 0, 2);
	CHECK_FALSE(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.1, 0.1));
	CHECK_FALSE(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.1, 0.1));
	CHECK(v == Vector3(4, 0, 2));
	CHECK(a == v);
	CHECK(b == v);
	CHECK(c == v);
}

TEST_CASE("[PhysicsSoftSoftFriction] Invalid inputs never modify any vertex velocity") {
	Vector3 v(3, 4, 0), a, b, c;
	const Vector3 original = v;
	CHECK_FALSE(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, 1.0, 1.0, 1.0, -1.0, 1.0, 0.1, 0.1));
	CHECK_FALSE(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			-1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.1, 0.1));
	CHECK_FALSE(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.1, 0.0));
	CHECK_FALSE(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			1.0, 1.0, 1.0, 1.0, 1.0,
			std::numeric_limits<real_t>::infinity(), 0.1, 0.1));
	CHECK_FALSE(physics_softbody_solve_pair_friction(POINT, A, A, C, v, a, b, c,
			1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.1, 0.1));
	CHECK_FALSE(physics_softbody_solve_pair_friction(POINT, A, B, C, v, a, b, c,
			0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.1, 0.1));
	CHECK(v == original);
	CHECK(a == Vector3());
	CHECK(b == Vector3());
	CHECK(c == Vector3());
}

} // namespace TestPhysicsSoftBodyPairFriction
