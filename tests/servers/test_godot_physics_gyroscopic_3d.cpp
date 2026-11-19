/**************************************************************************/
/*  test_godot_physics_gyroscopic_3d.cpp                                  */
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

TEST_FORCE_LINK(test_godot_physics_gyroscopic_3d)

namespace TestGodotPhysicsGyroscopic3D {

TEST_CASE("[GodotPhysics3D] Isotropic inertia produces no gyroscopic torque") {
	const Vector3 omega(2, -3, 7);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal(omega, Vector3(2, 2, 2), real_t(0.1)) == omega);
}

TEST_CASE("[GodotPhysics3D] Principal-axis spin produces no gyroscopic torque") {
	const Vector3 omega(0, 8, 0);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal(omega, Vector3(real_t(0.5), 1, 2), real_t(0.1)) == omega);
}

TEST_CASE("[GodotPhysics3D] Gyro correction preserves angular momentum magnitude") {
	const Vector3 inverse_inertia(real_t(0.5), real_t(0.25), 1);
	const Vector3 inertia(2, 4, 1);
	const Vector3 omega(2, 3, 5);
	const Vector3 before(inertia.x * omega.x, inertia.y * omega.y, inertia.z * omega.z);
	const Vector3 updated = GodotPhysicsGyroscopic3D::integrate_principal(omega, inverse_inertia, real_t(1.0 / 60.0));
	const Vector3 after(inertia.x * updated.x, inertia.y * updated.y, inertia.z * updated.z);
	CHECK(updated.is_finite());
	CHECK(updated.distance_squared_to(omega) > 0.0);
	CHECK(Math::is_equal_approx(before.length_squared(), after.length_squared()));
}

TEST_CASE("[GodotPhysics3D] Gyro integration skips singular inertia and invalid timesteps") {
	const Vector3 omega(3, 4, 5);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal(omega, Vector3(0, 1, 1), real_t(0.1)) == omega);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal(omega, Vector3(-1, 1, 1), real_t(0.1)) == omega);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal(omega, Vector3(1, 1, 1), 0) == omega);
	CHECK(GodotPhysicsGyroscopic3D::integrate_principal(omega, Vector3(1, 1, 1), -1) == omega);
}

TEST_CASE("[GodotPhysics3D] Fast asymmetric free rotation remains bounded") {
	const Vector3 inverse_inertia(real_t(0.25), real_t(0.5), 1);
	const Vector3 inertia(4, 2, 1);
	Vector3 omega(6, 9, 14);
	const Vector3 initial_momentum(inertia.x * omega.x, inertia.y * omega.y, inertia.z * omega.z);
	const real_t initial_momentum_squared = initial_momentum.length_squared();
	for (int i = 0; i < 600; i++) {
		omega = GodotPhysicsGyroscopic3D::integrate_principal(omega, inverse_inertia, real_t(1.0 / 120.0));
		CHECK(omega.is_finite());
		const Vector3 momentum(inertia.x * omega.x, inertia.y * omega.y, inertia.z * omega.z);
		CHECK(Math::is_equal_approx(momentum.length_squared(), initial_momentum_squared));
		CHECK(omega.length_squared() < real_t(10000));
	}
}

} // namespace TestGodotPhysicsGyroscopic3D
