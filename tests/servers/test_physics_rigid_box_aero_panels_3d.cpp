/**************************************************************************/
/*  test_physics_rigid_box_aero_panels_3d.cpp                              */
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

#include "servers/physics_rigid_box_aero_panels_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_rigid_box_aero_panels_3d)

namespace TestPhysicsRigidBoxAeroPanels3D {

static const Vector3 box_axes[3] = {
	Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
};

static bool apply(Vector3 &r_v, Vector3 &r_w,
		real_t p_pressure, real_t p_skin = 0.0,
		real_t p_density = 1.0, real_t p_dt = real_t(0.01),
		const Vector3 &p_center = Vector3(),
		const Vector3 &p_com = Vector3(),
		const Vector3 &p_wind = Vector3(),
		const Vector3 p_axes[3] = box_axes,
		real_t p_inv_mass = 1.0,
		const Basis &p_inv_inertia = Basis()) {
	return godot_physics_rigid_box_aero_step_3d(
			r_v, r_w, p_center, p_axes, p_com, p_wind,
			p_density, p_pressure, p_skin, p_inv_mass, p_inv_inertia, p_dt);
}

static real_t kinetic_energy(const Vector3 &p_v, const Vector3 &p_w) {
	// Unit mass and unit inertia in every axis, matching default test basis.
	return real_t(0.5) * (p_v.length_squared() + p_w.length_squared());
}

TEST_CASE("[PhysicsBoxAero] Disabled pressure and skin are exact no-ops") {
	Vector3 v(10, -3, 1), w(0, 0, 5);
	CHECK(apply(v, w, 0, 0));
	CHECK(v == Vector3(10, -3, 1));
	CHECK(w == Vector3(0, 0, 5));
}

TEST_CASE("[PhysicsBoxAero] Zero timestep and zero density preserve velocities") {
	Vector3 v(10, 0, 0), w(0, 0, 5);
	CHECK(apply(v, w, 1, 1, 1, 0));
	CHECK(apply(v, w, 1, 1, 0, real_t(0.01)));
	CHECK(v == Vector3(10, 0, 0));
	CHECK(w == Vector3(0, 0, 5));
}

TEST_CASE("[PhysicsBoxAero] One windward face gives analytic axial pressure") {
	Vector3 v(10, 0, 0), w;
	// A=(2*hy)*(2*hz)=4 m^2; F=-0.5*1*1*4*10^2=-200 N.
	// Unit mass, dt=0.01 => velocity falls by 2 m/s.
	CHECK(apply(v, w, 1));
	CHECK(v.x == doctest::Approx(8.0).epsilon(1e-5));
	CHECK(v.y == 0.0);
	CHECK(v.z == 0.0);
	CHECK(w.length() <= real_t(1e-6));
}

TEST_CASE("[PhysicsBoxAero] Negative axial travel uses opposite windward face") {
	Vector3 v(-10, 0, 0), w;
	CHECK(apply(v, w, 1));
	CHECK(v.x == doctest::Approx(-8.0).epsilon(1e-5));
	CHECK(w.length() <= real_t(1e-6));
}

TEST_CASE("[PhysicsBoxAero] No drag when body moves with wind") {
	Vector3 v(4, -3, 9), w;
	CHECK(apply(v, w, 1, 1, 1, real_t(0.1),
			Vector3(), Vector3(), Vector3(4, -3, 9)));
	CHECK(v == Vector3(4, -3, 9));
	CHECK(w == Vector3());
}

TEST_CASE("[PhysicsBoxAero] Uniform Galilean velocity shift leaves relative drag unchanged") {
	Vector3 reference(10, 0, 0), shifted(13, 2, 5);
	Vector3 spin_reference, spin_shifted;
	CHECK(apply(reference, spin_reference, 1));
	CHECK(apply(shifted, spin_shifted, 1, 0, 1, real_t(0.01),
			Vector3(), Vector3(), Vector3(3, 2, 5)));
	CHECK(shifted.x == doctest::Approx(reference.x + 3.0).epsilon(1e-5));
	CHECK(shifted.y == doctest::Approx(reference.y + 2.0).epsilon(1e-5));
	CHECK(shifted.z == doctest::Approx(reference.z + 5.0).epsilon(1e-5));
	CHECK(spin_reference == spin_shifted);
}

TEST_CASE("[PhysicsBoxAero] Pressure doubles with density below limiter") {
	Vector3 one(10, 0, 0), two = one, w1, w2;
	CHECK(apply(one, w1, 1));
	CHECK(apply(two, w2, 1, 0, 2));
	CHECK(one.x == doctest::Approx(8.0));
	CHECK(two.x == doctest::Approx(6.0));
}

TEST_CASE("[PhysicsBoxAero] Pressure doubles with drag coefficient below limiter") {
	Vector3 one(10, 0, 0), two = one, w1, w2;
	CHECK(apply(one, w1, 1));
	CHECK(apply(two, w2, 2));
	CHECK(one.x == doctest::Approx(8.0));
	CHECK(two.x == doctest::Approx(6.0));
}

TEST_CASE("[PhysicsBoxAero] Face area uses affine half axes rather than an AABB") {
	Vector3 v(10, 0, 0), w;
	const Vector3 axes[3] = {
		Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 3)
	};
	CHECK(apply(v, w, 1, 0, 1, real_t(0.001),
			Vector3(), Vector3(), Vector3(), axes));
	// Area of +X face = 4*2*3=24, F=-1200, dt .001 => delta vx=-1.2.
	CHECK(v.x == doctest::Approx(8.8).epsilon(1e-5));
	CHECK(w.length() <= real_t(1e-5));
}

TEST_CASE("[PhysicsBoxAero] Large timestep does not reverse relative slip") {
	Vector3 v(10, 0, 0), w;
	CHECK(apply(v, w, 1, 0, 1, 10));
	CHECK(v.x >= real_t(0.0));
	CHECK(v.x == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsBoxAero] Pressure at centered box causes no spin") {
	Vector3 v(7, 0, 0), w;
	CHECK(apply(v, w, 1));
	CHECK(w.length() <= real_t(1e-6));
}

TEST_CASE("[PhysicsBoxAero] Offset box converts drag into torque") {
	Vector3 v(10, 0, 0), w;
	CHECK(apply(v, w, 1, 0, 1, real_t(0.01),
			Vector3(0, 1, 0)));
	CHECK(v.x < 10);
	CHECK(w.z > 0); // r=(1,1,0), F=-X, r cross F = +Z.
	CHECK(w.is_finite());
}

TEST_CASE("[PhysicsBoxAero] Pure spin loses kinetic energy under skin drag") {
	Vector3 v, w(0, 0, 10);
	const real_t before = kinetic_energy(v, w);
	CHECK(apply(v, w, 0, real_t(0.1)));
	CHECK(Math::abs(w.z) < real_t(10.0));
	CHECK(kinetic_energy(v, w) < before);
}

TEST_CASE("[PhysicsBoxAero] Skin drag resists translation on tangential faces") {
	Vector3 v(10, 0, 0), w;
	CHECK(apply(v, w, 0, real_t(0.1)));
	CHECK(v.x < 10);
	CHECK(v.x >= 0);
	CHECK(kinetic_energy(v, w) < 50);
}

TEST_CASE("[PhysicsBoxAero] All disabled pressure with zero spin has no pressure-induced torque") {
	Vector3 v(10, 0, 0), w;
	CHECK(apply(v, w, 0, 0));
	CHECK(v == Vector3(10, 0, 0));
	CHECK(w == Vector3());
}

TEST_CASE("[PhysicsBoxAero] Reflected box transform preserves pressure direction") {
	Vector3 v(10, 0, 0), w;
	const Vector3 mirror[3] = {
		Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	CHECK(apply(v, w, 1, 0, 1, real_t(0.01),
			Vector3(), Vector3(), Vector3(), mirror));
	CHECK(v.x == doctest::Approx(8.0).epsilon(1e-5));
	CHECK(w.length() <= real_t(1e-6));
}

TEST_CASE("[PhysicsBoxAero] Properly rotated box has a rotated drag response") {
	Vector3 v(0, 10, 0), w;
	const Vector3 rotated[3] = {
		Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)
	};
	CHECK(apply(v, w, 1, 0, 1, real_t(0.01),
			Vector3(), Vector3(), Vector3(), rotated));
	CHECK(v.y == doctest::Approx(8.0).epsilon(1e-5));
	CHECK(v.x == 0.0);
	CHECK(w.length() <= real_t(1e-6));
}

TEST_CASE("[PhysicsBoxAero] Sheared affine box produces finite resisting motion") {
	Vector3 v(10, 0, 0), w;
	const Vector3 sheared[3] = {
		Vector3(1, 0, 0), Vector3(real_t(0.5), 1, 0), Vector3(0, 0, 1)
	};
	CHECK(apply(v, w, real_t(0.5), real_t(0.01), 1, real_t(0.01),
			Vector3(), Vector3(), Vector3(), sheared));
	CHECK(v.is_finite());
	CHECK(w.is_finite());
	CHECK(kinetic_energy(v, w) <= real_t(50.0001));
}

TEST_CASE("[PhysicsBoxAero] Multiple repeated passes dissipate kinetic energy") {
	Vector3 v(10, -3, 4), w(1, -2, 5);
	real_t previous = kinetic_energy(v, w);
	for (int i = 0; i < 25; ++i) {
		CHECK(apply(v, w, real_t(0.5), real_t(0.05)));
		const real_t current = kinetic_energy(v, w);
		CHECK(current <= previous + real_t(0.0001));
		CHECK(v.is_finite());
		CHECK(w.is_finite());
		previous = current;
	}
	CHECK(previous < real_t(0.8) * kinetic_energy(Vector3(10, -3, 4), Vector3(1, -2, 5)));
}

TEST_CASE("[PhysicsBoxAero] Invalid material inputs reject without velocity changes") {
	Vector3 v(10, 0, 0), w(0, 0, 10);
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK_FALSE(apply(v, w, -1));
	CHECK_FALSE(apply(v, w, 1, -1));
	CHECK_FALSE(apply(v, w, 1, 0, -1));
	CHECK_FALSE(apply(v, w, 1, 0, 1, real_t(-0.1)));
	CHECK_FALSE(apply(v, w, nan));
	CHECK_FALSE(apply(v, w, 1, 0, 1, real_t(0.01),
			Vector3(), Vector3(), Vector3(), box_axes, real_t(-1.0)));
	CHECK(v == Vector3(10, 0, 0));
	CHECK(w == Vector3(0, 0, 10));
}

TEST_CASE("[PhysicsBoxAero] Singular geometry is rejected atomically") {
	Vector3 v(10, 0, 0), w;
	const Vector3 singular[3] = {
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 0)
	};
	CHECK_FALSE(apply(v, w, 1, 0, 1, real_t(0.01),
			Vector3(), Vector3(), Vector3(), singular));
	CHECK(v == Vector3(10, 0, 0));
	CHECK(w == Vector3());
}

TEST_CASE("[PhysicsBoxAero] World inverse inertia changes offset aerodynamic torque") {
	Vector3 v1(10, 0, 0), v2 = v1, w1, w2;
	Basis half_inertia;
	half_inertia.scale(Vector3(real_t(0.5), real_t(0.5), real_t(0.5)));
	CHECK(apply(v1, w1, 1, 0, 1, real_t(0.01), Vector3(0, 1, 0)));
	CHECK(apply(v2, w2, 1, 0, 1, real_t(0.01), Vector3(0, 1, 0),
			Vector3(), box_axes, 1, half_inertia));
	CHECK(w1.z > w2.z);
	CHECK(v1.x == doctest::Approx(v2.x).epsilon(1e-5));
}

TEST_CASE("[PhysicsBoxAero] Huge finite values either reject atomically or remain finite") {
	Vector3 v(std::numeric_limits<real_t>::max() / real_t(2.0), 0, 0), w;
	const Vector3 initial = v;
	const bool ok = apply(v, w, 10, 10, 2000, real_t(1.0));
	CHECK(!ok || v.is_finite());
	CHECK(!ok || w.is_finite());
	if (!ok) {
		CHECK(v == initial);
		CHECK(w == Vector3());
	}
}

} // namespace TestPhysicsRigidBoxAeroPanels3D
