/**************************************************************************/
/*  test_godot_physics_gyroscopic_midpoint_3d.cpp                         */
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

#include "servers/physics_gyroscopic_3d.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_gyroscopic_midpoint_3d)

namespace TestGodotPhysicsGyroscopicMidpoint3D {

static real_t angular_momentum_squared(const Vector3 &p_omega, const Vector3 &p_inertia) {
	const Vector3 l(p_omega.x * p_inertia.x, p_omega.y * p_inertia.y, p_omega.z * p_inertia.z);
	return l.length_squared();
}

static real_t rotational_energy(const Vector3 &p_omega, const Vector3 &p_inertia) {
	return real_t(0.5) * (p_omega.x * p_omega.x * p_inertia.x +
			p_omega.y * p_omega.y * p_inertia.y + p_omega.z * p_omega.z * p_inertia.z);
}

TEST_CASE("[GodotPhysics3D] Midpoint gyroscope leaves symmetric inertia unchanged") {
	const Vector3 omega(2, -3, 7);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal_midpoint(omega,
			Vector3(real_t(0.5), real_t(0.5), real_t(0.5)), real_t(1.0 / 60.0)) == omega);
}

TEST_CASE("[GodotPhysics3D] Midpoint gyroscope leaves principal spin unchanged") {
	const Vector3 omega(0, 12, 0);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal_midpoint(omega,
			Vector3(real_t(0.25), real_t(0.5), 1), real_t(1.0 / 60.0)) == omega);
}

TEST_CASE("[GodotPhysics3D] Midpoint gyroscope preserves both torque-free invariants") {
	const Vector3 inertia(4, 2, 1);
	const Vector3 inverse_inertia(real_t(0.25), real_t(0.5), 1);
	const Vector3 initial(6, 9, 14);
	Vector3 omega = initial;
	const real_t l2 = angular_momentum_squared(initial, inertia);
	const real_t energy = rotational_energy(initial, inertia);
	for (int i = 0; i < 600; ++i) {
		omega = GodotPhysicsGyroscopic3D::integrate_principal_midpoint(
				omega, inverse_inertia, real_t(1.0 / 120.0));
		CHECK(omega.is_finite());
		CHECK(omega.length_squared() < real_t(10000));
		CHECK(Math::abs(angular_momentum_squared(omega, inertia) - l2) <= l2 * real_t(0.001));
		CHECK(Math::abs(rotational_energy(omega, inertia) - energy) <= energy * real_t(0.001));
	}
	CHECK(omega.distance_squared_to(initial) > real_t(0.01));
}

TEST_CASE("[GodotPhysics3D] Midpoint gyroscope tolerates singular inertia and bad dt") {
	const Vector3 omega(3, 4, 5);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal_midpoint(omega, Vector3(0, 1, 1), real_t(0.01)) == omega);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal_midpoint(omega, Vector3(-1, 1, 1), real_t(0.01)) == omega);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal_midpoint(omega, Vector3(1, 1, 1), 0) == omega);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal_midpoint(omega, Vector3(1, 1, 1), -1) == omega);
}

TEST_CASE("[GodotPhysics3D] Midpoint gyroscope remains finite for very large steps") {
	const Vector3 omega(20, 30, 40);
	for (real_t step : { real_t(1.0 / 60.0), real_t(0.5), real_t(2.0) }) {
		const Vector3 next = GodotPhysicsGyroscopic3D::integrate_principal_midpoint(
				omega, Vector3(real_t(0.1), real_t(0.5), 1), step);
		CHECK(next.is_finite());
	}
}

} // namespace TestGodotPhysicsGyroscopicMidpoint3D
