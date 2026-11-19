/**************************************************************************/
/*  test_physics_rotating_frame_3d.cpp                                    */
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

#include "servers/physics_rotating_frame_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_rotating_frame_3d)

namespace TestPhysicsRotatingFrame3D {

static const Vector3 zero;

static bool update(Vector3 &r_velocity, const Vector3 &p_position,
		const Vector3 &p_omega, real_t p_dt,
		const Vector3 &p_origin = Vector3(),
		const Vector3 &p_alpha = Vector3()) {
	return godot_physics_rotating_frame_step_3d(r_velocity, p_position,
			p_origin, p_omega, p_alpha, p_dt);
}

TEST_CASE("[PhysicsRotatingFrame] Disabled frame is an exact no-op") {
	Vector3 velocity(1, 2, 3);
	CHECK(update(velocity, Vector3(4, 5, 6), zero, 0.5));
	CHECK(velocity == Vector3(1, 2, 3));
}

TEST_CASE("[PhysicsRotatingFrame] Zero timestep is an exact no-op") {
	Vector3 velocity(1, 2, 3);
	CHECK(update(velocity, Vector3(3, 4, 5),
			Vector3(0, 0, 10), 0, zero, Vector3(0, 0, 5)));
	CHECK(velocity == Vector3(1, 2, 3));
}

TEST_CASE("[PhysicsRotatingFrame] Pure Coriolis follows the Boris Cayley rotation") {
	Vector3 velocity(1, 0, 0);
	CHECK(update(velocity, zero, Vector3(0, 0, 1), real_t(0.1)));
	CHECK(velocity.x == doctest::Approx(0.9801980198).epsilon(1e-5));
	CHECK(velocity.y == doctest::Approx(-0.198019802).epsilon(1e-5));
	CHECK(velocity.z == 0.0);
}

TEST_CASE("[PhysicsRotatingFrame] Pure Coriolis conserves speed") {
	Vector3 velocity(3, 4, 5);
	const real_t original = velocity.length();
	for (int i = 0; i < 100; ++i) {
		CHECK(update(velocity, zero, Vector3(0, 0, real_t(2.5)), real_t(0.04)));
	}
	CHECK(velocity.length() == doctest::Approx(original).epsilon(1e-4));
}

TEST_CASE("[PhysicsRotatingFrame] Coriolis conserves speed at extremely coarse timestep") {
	Vector3 velocity(1, 2, 3);
	const real_t original = velocity.length();
	CHECK(update(velocity, zero, Vector3(0, 0, 20), real_t(100.0)));
	CHECK(velocity.length() == doctest::Approx(original).epsilon(1e-5));
	CHECK(velocity.is_finite());
}

TEST_CASE("[PhysicsRotatingFrame] Reversing frame spin reverses deflection") {
	Vector3 positive(1, 0, 0);
	Vector3 negative = positive;
	CHECK(update(positive, zero, Vector3(0, 0, 1), real_t(0.1)));
	CHECK(update(negative, zero, Vector3(0, 0, -1), real_t(0.1)));
	CHECK(positive.x == doctest::Approx(negative.x).epsilon(1e-5));
	CHECK(positive.y == doctest::Approx(-negative.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsRotatingFrame] Pure Coriolis reverse-step returns to original velocity") {
	Vector3 velocity(2, -3, 0.5);
	const Vector3 original = velocity;
	const Vector3 omega(0, 0, 3);
	CHECK(update(velocity, zero, omega, real_t(0.12)));
	CHECK(update(velocity, zero, -omega, real_t(0.12)));
	CHECK(velocity.distance_to(original) == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsRotatingFrame] Velocity parallel to rotation axis stays constant") {
	Vector3 velocity(0, 0, 4);
	CHECK(update(velocity, zero, Vector3(0, 0, 5), real_t(0.5)));
	CHECK(velocity == Vector3(0, 0, 4));
}

TEST_CASE("[PhysicsRotatingFrame] Rotation around own COM does not cause centrifugal drift") {
	Vector3 velocity;
	CHECK(update(velocity, zero, Vector3(0, 0, 5), real_t(1.0)));
	CHECK(velocity == Vector3());
}

TEST_CASE("[PhysicsRotatingFrame] Centrifugal acceleration points away from rotation axis") {
	Vector3 velocity;
	CHECK(update(velocity, Vector3(2, 0, 0), Vector3(0, 0, 3), real_t(0.001)));
	CHECK(velocity.x > real_t(0.0));
	CHECK(velocity.x == doctest::Approx(0.018).epsilon(1e-4));
	CHECK(velocity.y < real_t(0.0)); // Coriolis deflects the acquired speed.
}

TEST_CASE("[PhysicsRotatingFrame] Centrifugal acceleration vanishes along spin axis") {
	Vector3 velocity;
	CHECK(update(velocity, Vector3(0, 0, 20), Vector3(0, 0, 4), real_t(0.1)));
	CHECK(velocity == Vector3());
}

TEST_CASE("[PhysicsRotatingFrame] Euler acceleration is opposite frame spin-up cross radius") {
	Vector3 velocity;
	CHECK(update(velocity, Vector3(2, 0, 0), zero, real_t(0.1),
			zero, Vector3(0, 0, 4)));
	CHECK(velocity == Vector3(0, real_t(-0.8), 0));
}

TEST_CASE("[PhysicsRotatingFrame] Reversing angular acceleration reverses Euler response") {
	Vector3 plus, minus;
	CHECK(update(plus, Vector3(2, 0, 0), zero, real_t(0.1),
			zero, Vector3(0, 0, 4)));
	CHECK(update(minus, Vector3(2, 0, 0), zero, real_t(0.1),
			zero, Vector3(0, 0, -4)));
	CHECK(plus == -minus);
}

TEST_CASE("[PhysicsRotatingFrame] Translating origin and COM together changes nothing") {
	Vector3 at_origin;
	Vector3 shifted;
	const Vector3 origin(100, -200, 300);
	CHECK(update(at_origin, Vector3(2, 0, 0), Vector3(0, 0, 3), real_t(0.01)));
	CHECK(update(shifted, Vector3(2, 0, 0) + origin, Vector3(0, 0, 3),
			real_t(0.01), origin));
	CHECK(at_origin.distance_to(shifted) == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsRotatingFrame] Reversing position reverses centrifugal-only velocity") {
	Vector3 pos, neg;
	CHECK(update(pos, Vector3(2, 0, 0), Vector3(0, 0, 3), real_t(0.1)));
	CHECK(update(neg, Vector3(-2, 0, 0), Vector3(0, 0, 3), real_t(0.1)));
	CHECK(pos.distance_to(-neg) == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsRotatingFrame] Faster frame yields quadratic centrifugal scaling for small dt") {
	Vector3 slow, fast;
	CHECK(update(slow, Vector3(1, 0, 0), Vector3(0, 0, 1), real_t(0.0001)));
	CHECK(update(fast, Vector3(1, 0, 0), Vector3(0, 0, 2), real_t(0.0001)));
	CHECK(fast.x == doctest::Approx(4.0 * slow.x).epsilon(1e-5));
}

TEST_CASE("[PhysicsRotatingFrame] Coriolis force does no instantaneous work") {
	// Explicit expression a=-2 omega×v has v·a=0.
	const Vector3 velocity(3, 4, 5);
	const Vector3 omega(1, -2, 3);
	const Vector3 acceleration = -real_t(2.0) * omega.cross(velocity);
	CHECK(velocity.dot(acceleration) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsRotatingFrame] Arbitrary 3D spin and velocity remain finite") {
	Vector3 velocity(3, -7, 12);
	CHECK(update(velocity, Vector3(2, -5, 1), Vector3(3, 4, -2),
			real_t(0.1), Vector3(1, 1, 0), Vector3(.1, -.5, .2)));
	CHECK(velocity.is_finite());
}

TEST_CASE("[PhysicsRotatingFrame] Invalid input is rejected transactionally") {
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	const real_t inf = std::numeric_limits<real_t>::infinity();
	Vector3 velocity(1, 2, 3);
	CHECK_FALSE(update(velocity, zero, Vector3(0, 0, nan), real_t(0.1)));
	CHECK_FALSE(update(velocity, Vector3(inf, 0, 0), Vector3(0, 0, 1), real_t(0.1)));
	CHECK_FALSE(update(velocity, zero, Vector3(0, 0, 1), real_t(-0.1)));
	CHECK_FALSE(update(velocity, zero, Vector3(0, 0, 1), nan));
	CHECK_FALSE(update(velocity, zero, Vector3(0, 0, 1), real_t(0.1),
			zero, Vector3(inf, 0, 0)));
	CHECK(velocity == Vector3(1, 2, 3));
}

TEST_CASE("[PhysicsRotatingFrame] Numerical overflow leaves velocity unchanged") {
	const real_t large = std::numeric_limits<real_t>::max() / real_t(2.0);
	Vector3 velocity(1, 2, 3);
	CHECK_FALSE(update(velocity, Vector3(large, 0, 0),
			Vector3(0, 0, 100), real_t(100)));
	CHECK(velocity == Vector3(1, 2, 3));
}

} // namespace TestPhysicsRotatingFrame3D
