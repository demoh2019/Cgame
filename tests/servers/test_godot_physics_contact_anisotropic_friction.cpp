/**************************************************************************/
/*  test_godot_physics_contact_anisotropic_friction.cpp                  */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_contact_anisotropic_friction.h"
#include "servers/physics_contact_velocity_friction.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_godot_physics_contact_anisotropic_friction)

namespace TestGodotPhysicsContactAnisotropicFriction {

TEST_CASE("[GodotPhysics] Elliptical friction limits longitudinal and transverse impulses") {
	const Vector3 n(0, 0, 1), axis(1, 0, 0);
	const Vector3 along = godot_physics_clamp_anisotropic_friction_3d(
			Vector3(4, 0, 0), n, axis, 1, 1, real_t(0.25));
	const Vector3 across = godot_physics_clamp_anisotropic_friction_3d(
			Vector3(0, 4, 0), n, axis, 1, 1, real_t(0.25));
	CHECK(along.is_equal_approx(Vector3(1, 0, 0)));
	CHECK(across.is_equal_approx(Vector3(0, real_t(0.25), 0)));
}

TEST_CASE("[GodotPhysics] Mixed lateral direction maps to elliptical friction cone") {
	const Vector3 result = godot_physics_clamp_anisotropic_friction_3d(
			Vector3(1, 1, 0), Vector3(0, 0, 1),
			Vector3(1, 0, 0), 1, 1, real_t(0.5));
	const real_t expected = real_t(1.0 / Math::sqrt(5.0));
	CHECK(result.is_equal_approx(Vector3(expected, expected, 0)));
	CHECK(result.dot(Vector3(0, 0, 1)) == doctest::Approx(0));
}

TEST_CASE("[GodotPhysics] Elliptical static cone sticks before kinetic breakaway") {
	const Vector3 n(0, 0, 1), axis(1, 0, 0);
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(real_t(1.5), 0, 0), n, axis, 1, 2, real_t(0.5)) ==
			Vector3(real_t(1.5), 0, 0));
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(0, real_t(0.75), 0), n, axis, 1, 2, real_t(0.5)) ==
			Vector3(0, real_t(0.75), 0));
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(0, 4, 0), n, axis, 1, 2, real_t(0.5)).is_equal_approx(
			Vector3(0, real_t(0.5), 0)));
}

TEST_CASE("[GodotPhysics] Contact normal and preferred axis rotate without changing friction") {
	const Vector3 x(1, 0, 0), y(0, 1, 0), z(0, 0, 1);
	const Vector3 result = godot_physics_clamp_anisotropic_friction_3d(
			Vector3(5, 0, 0), y, x, 1, 1, real_t(0.2));
	CHECK(result.is_equal_approx(x));
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(0, 0, 5), x, z, 1, 1, real_t(0.2)).is_equal_approx(z));
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(0, 5, 0), z, x, 1, 1, real_t(0.2)).is_equal_approx(
			Vector3(0, real_t(0.2), 0)));
	// Preferred axis normal to the contact plane is undefined; fallback
	// to the original isotropic friction rather than arbitrary directions.
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(0, 5, 0), z, z, 1, 1, real_t(0.2)).is_equal_approx(y));
}

TEST_CASE("[GodotPhysics] Default anisotropy ratio preserves original Coulomb solver") {
	const Vector3 candidate(3, 4, 0);
	const Vector3 actual = godot_physics_clamp_anisotropic_friction_3d(
			candidate, Vector3(0, 0, 1), Vector3(1, 0, 0),
			real_t(0.5), real_t(2), real_t(1));
	const Vector3 expected = godot_physics_clamp_static_friction_3d(
			candidate, real_t(0.5), real_t(2));
	CHECK(actual == expected);
	CHECK(actual.is_equal_approx(Vector3(real_t(0.3), real_t(0.4), 0)));
}

TEST_CASE("[GodotPhysics] Anisotropic ellipse composes with Stribeck without duplicate static cone") {
	const real_t effective_mu = godot_physics_stribeck_friction_coefficient(
			real_t(0.5), real_t(2), 1, 1);
	CHECK(effective_mu == doctest::Approx(0.75));
	const Vector3 result = godot_physics_clamp_anisotropic_friction_3d(
			Vector3(0, 4, 0), Vector3(0, 0, 1), Vector3(1, 0, 0),
			effective_mu, 1, real_t(0.5));
	CHECK(result.is_equal_approx(Vector3(0, real_t(0.375), 0)));
}

TEST_CASE("[GodotPhysics] Large finite tangential impulses remain bounded without overflow") {
	const Vector3 huge(real_t(1e38), real_t(1e38), 0);
	const Vector3 result = godot_physics_clamp_anisotropic_friction_3d(
			huge, Vector3(0, 0, 1), Vector3(1, 0, 0),
			real_t(1), real_t(1), real_t(0.25));
	CHECK(result.is_finite());
	CHECK(result.x > 0.0);
	CHECK(result.y > 0.0);
	const double q = Math::sqrt(double(result.x) * double(result.x) +
			double(result.y) * double(result.y) * 16.0);
	CHECK(q == doctest::Approx(1.0).epsilon(1e-5));
}

TEST_CASE("[GodotPhysics] Zero normal impulse and malformed data never inject friction") {
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	const real_t inf = std::numeric_limits<real_t>::infinity();
	const Vector3 n(0, 0, 1), axis(1, 0, 0);
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(1, 0, 0), n, axis, 0, 1, real_t(0.2)) == Vector3());
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(nan, 0, 0), n, axis, 1, 1, real_t(0.2)) == Vector3());
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(1, 0, 0), n, axis, inf, 1, real_t(0.2)) == Vector3());
	CHECK(godot_physics_clamp_anisotropic_friction_3d(
			Vector3(1, 0, 0), n, axis, 1, 1, real_t(0.2)) ==
			Vector3(1, 0, 0));
}

} // namespace TestGodotPhysicsContactAnisotropicFriction
