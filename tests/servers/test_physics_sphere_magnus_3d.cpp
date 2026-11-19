/**************************************************************************/
/*  test_physics_sphere_magnus_3d.cpp                                     */
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

#include "servers/physics_sphere_magnus_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_sphere_magnus_3d)

namespace TestPhysicsSphereMagnus3D {

static bool lift(const Vector3 &p_velocity, const Vector3 &p_spin,
		Vector3 &r_force, const Vector3 &p_flow = Vector3(),
		real_t p_radius = real_t(0.1), real_t p_density = real_t(1.225),
		real_t p_coefficient = real_t(0.2),
		real_t p_max_lift = real_t(1.5)) {
	return godot_physics_sphere_magnus_force_3d(p_velocity, p_spin,
			p_flow, p_radius, p_density, p_coefficient, p_max_lift, r_force);
}

TEST_CASE("[PhysicsMagnus] Right-handed Magnus force points orthogonal to motion and spin") {
	Vector3 f;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100), f));
	CHECK(f.x == 0.0);
	CHECK(f.z == 0.0);
	CHECK(f.y > 0.0);
	CHECK(f.y == doctest::Approx(0.3848451).epsilon(1e-5));
	CHECK(f.dot(Vector3(10, 0, 0)) == doctest::Approx(0.0));
	CHECK(f.dot(Vector3(0, 0, 100)) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsMagnus] Reverse spin reverses aerodynamic deflection") {
	Vector3 positive, negative;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100), positive));
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, -100), negative));
	CHECK(positive.y > 0.0);
	CHECK(negative.y < 0.0);
	CHECK(positive.y == doctest::Approx(-negative.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Reverse relative flow reverses aerodynamic deflection") {
	Vector3 forward, reverse;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100), forward));
	CHECK(lift(Vector3(-10, 0, 0), Vector3(0, 0, 100), reverse));
	CHECK(forward.y == doctest::Approx(-reverse.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Global wind and body translation cancel exactly") {
	Vector3 baseline, moving_medium;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100), baseline));
	CHECK(lift(Vector3(10, 2, 4), Vector3(0, 0, 100),
			moving_medium, Vector3(0, 2, 4)));
	CHECK(baseline.y == doctest::Approx(moving_medium.y).epsilon(1e-5));
	CHECK(baseline.x == doctest::Approx(moving_medium.x).epsilon(1e-5));
	CHECK(baseline.z == doctest::Approx(moving_medium.z).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Same world velocity and wind produces no lift") {
	Vector3 f(1, 2, 3);
	CHECK(lift(Vector3(10, 2, 3), Vector3(0, 0, 100),
			f, Vector3(10, 2, 3)));
	CHECK(f == Vector3());
}

TEST_CASE("[PhysicsMagnus] Zero spin is no-op") {
	Vector3 f(1, 2, 3);
	CHECK(lift(Vector3(10, 0, 0), Vector3(), f));
	CHECK(f == Vector3());
}

TEST_CASE("[PhysicsMagnus] Spin parallel to relative flow is a no-op") {
	Vector3 f(1, 2, 3);
	CHECK(lift(Vector3(10, 0, 0), Vector3(100, 0, 0), f));
	CHECK(f == Vector3());
}

TEST_CASE("[PhysicsMagnus] Zero medium density or spin coefficient switches effect off") {
	Vector3 f(1, 2, 3);
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100),
			f, Vector3(), 0.1, 0.0));
	CHECK(f == Vector3());
	f = Vector3(1, 2, 3);
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100),
			f, Vector3(), 0.1, 1.225, 0.0));
	CHECK(f == Vector3());
}

TEST_CASE("[PhysicsMagnus] Density doubles Magnus force when uncapped") {
	Vector3 one, two;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100), one));
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100),
			two, Vector3(), 0.1, 2.45));
	CHECK(two.y == doctest::Approx(2.0 * one.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Sphere radius follows cubic lift scaling at fixed spin") {
	Vector3 small, large;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100), small,
			Vector3(), real_t(0.1)));
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100), large,
			Vector3(), real_t(0.2)));
	CHECK(large.y == doctest::Approx(8.0 * small.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Uncapped force grows linearly with spin") {
	Vector3 a, b;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 20), a));
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 40), b));
	CHECK(b.y == doctest::Approx(2.0 * a.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Saturated lift obeys dynamic pressure maximum") {
	Vector3 f;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 10000), f));
	const double upper = 0.5 * 1.225 * Math::PI * 0.1 * 0.1 * 1.5 * 100;
	CHECK(f.y == doctest::Approx(upper).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Saturated lift becomes independent of spin magnitude") {
	Vector3 a, b;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 1000), a));
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 5000), b));
	CHECK(a.y == doctest::Approx(b.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Zero cap disables Magnus without changing inputs") {
	Vector3 f(1, 2, 3);
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100),
			f, Vector3(), 0.1, 1.225, 0.2, 0));
	CHECK(f == Vector3());
}

TEST_CASE("[PhysicsMagnus] Velocity scaling is linear uncapped and quadratic when capped") {
	Vector3 slow, fast, capped_slow, capped_fast;
	CHECK(lift(Vector3(5, 0, 0), Vector3(0, 0, 10), slow));
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 10), fast));
	CHECK(fast.y == doctest::Approx(2.0 * slow.y).epsilon(1e-5));
	CHECK(lift(Vector3(5, 0, 0), Vector3(0, 0, 10000), capped_slow));
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 10000), capped_fast));
	CHECK(capped_fast.y == doctest::Approx(4.0 * capped_slow.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Rotating world frame rotates lift vector") {
	Vector3 x, y;
	CHECK(lift(Vector3(10, 0, 0), Vector3(0, 0, 100), x));
	CHECK(lift(Vector3(0, 10, 0), Vector3(0, 0, 100), y));
	CHECK(y.x == doctest::Approx(-x.y).epsilon(1e-5));
	CHECK(y.y == doctest::Approx(x.x).epsilon(1e-5));
}

TEST_CASE("[PhysicsMagnus] Offset sphere applies nonzero physically consistent body torque") {
	const Vector3 lever(0, 0, 1);
	const Vector3 omega(0, 0, 100);
	const Vector3 linear_velocity(10, 0, 0);
	Vector3 f;
	CHECK(lift(linear_velocity + omega.cross(lever), omega, f));
	const Vector3 torque = lever.cross(f);
	CHECK(f.y > 0);
	CHECK(torque.x < 0);
	CHECK(torque.dot(lever) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsMagnus] Invalid inputs fail atomically without corrupting force") {
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	const real_t inf = std::numeric_limits<real_t>::infinity();
	Vector3 f(1, 2, 3);
	CHECK_FALSE(lift(Vector3(10, 0, 0), Vector3(0, 0, 100),
			f, Vector3(), -1));
	CHECK_FALSE(lift(Vector3(10, 0, 0), Vector3(0, 0, 100),
			f, Vector3(), 0.1, -1));
	CHECK_FALSE(lift(Vector3(10, 0, 0), Vector3(0, 0, 100),
			f, Vector3(), 0.1, 1.225, -1));
	CHECK_FALSE(lift(Vector3(10, 0, 0), Vector3(0, 0, 100),
			f, Vector3(), 0.1, 1.225, .2, -1));
	CHECK_FALSE(lift(Vector3(inf, 0, 0), Vector3(0, 0, 100), f));
	CHECK_FALSE(lift(Vector3(10, 0, 0), Vector3(0, 0, nan), f));
	CHECK(f == Vector3(1, 2, 3));
}

TEST_CASE("[PhysicsMagnus] Huge but finite inputs never produce nonfinite lift") {
	Vector3 force(0, 0, 0);
	const real_t huge = std::numeric_limits<real_t>::max() / real_t(2.0);
	const bool computed = lift(Vector3(huge, 0, 0),
			Vector3(0, 0, huge), force);
	CHECK(!computed || force.is_finite());
}

} // namespace TestPhysicsSphereMagnus3D
