/**************************************************************************/
/*  test_physics_softbody_fatigue_damage.cpp                              */
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

#include "servers/physics_softbody_fatigue_damage.h"
#include "servers/physics_xpbd_distance.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_fatigue_damage)

namespace TestPhysicsSoftBodyFatigueDamage {

TEST_CASE("[PhysicsSoftBody] Fatigue accumulates only above material yield") {
	real_t damage = 0.0;
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(real_t(1.1), 0, 0),
			1, real_t(0.2), 2, real_t(0.95), 1.0, damage));
	CHECK(damage == 0.0);
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(real_t(1.5), 0, 0),
			1, real_t(0.2), 2, real_t(0.95), 1.0, damage));
	CHECK(damage > real_t(0.0));
	CHECK(damage < real_t(0.95));
}

TEST_CASE("[PhysicsSoftBody] Fatigue is irreversible and saturates at the cap") {
	real_t damage = 0.0;
	for (int i = 0; i < 100; i++) {
		const real_t previous = damage;
		CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(2, 0, 0),
				1, real_t(0.1), 4, real_t(0.9), 0.1, damage));
		CHECK(damage >= previous);
		CHECK(damage <= real_t(0.9));
	}
	const real_t saturated = damage;
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(1, 0, 0),
			1, real_t(0.1), 4, real_t(0.9), 30.0, damage));
	CHECK(damage == saturated);
}

TEST_CASE("[PhysicsSoftBody] Equal elapsed time has step-size consistent damage") {
	real_t one_step = real_t(0.1);
	real_t two_steps = one_step;
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(2, 0, 0),
			1, 0, 3, real_t(0.95), 0.3, one_step));
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(2, 0, 0),
			1, 0, 3, real_t(0.95), 0.15, two_steps));
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(2, 0, 0),
			1, 0, 3, real_t(0.95), 0.15, two_steps));
	CHECK(Math::abs(one_step - two_steps) < real_t(1e-5));
}

TEST_CASE("[PhysicsSoftBody] Compression and extension both cause damage") {
	real_t compressed = 0, extended = 0;
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(real_t(0.5), 0, 0),
			1, 0, 2, real_t(0.8), 0.3, compressed));
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(real_t(1.5), 0, 0),
			1, 0, 2, real_t(0.8), 0.3, extended));
	CHECK(Math::abs(compressed - extended) < real_t(1e-5));
}

TEST_CASE("[PhysicsSoftBody] Damage increases XPBD compliance while preserving pins") {
	real_t alpha = real_t(1.0);
	CHECK(physics_softbody_fatigue_compliance_alpha(alpha, real_t(0.8), alpha));
	CHECK(Math::abs(alpha - real_t(5.0)) < real_t(1e-5));
	Vector3 normal_a, normal_b(2, 0, 0);
	Vector3 damaged_a, damaged_b(2, 0, 0);
	real_t normal_lambda = 0, damaged_lambda = 0;
	for (int i = 0; i < 30; i++) {
		CHECK(physics_xpbd_solve_distance(normal_a, normal_b, 0, 1, 1, 1, normal_lambda));
		CHECK(physics_xpbd_solve_distance(damaged_a, damaged_b, 0, 1, 1, alpha, damaged_lambda));
	}
	CHECK(normal_a == Vector3());
	CHECK(damaged_a == Vector3());
	CHECK(damaged_b.x > normal_b.x);
	CHECK(damaged_b.x < 2);
}

TEST_CASE("[PhysicsSoftBody] Zero damage rate and zero timestep leave material intact") {
	real_t damage = real_t(0.2);
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(2, 0, 0),
			1, 0, 0, real_t(0.9), 1.0, damage));
	CHECK(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(2, 0, 0),
			1, 0, 3, real_t(0.9), 0.0, damage));
	CHECK(damage == real_t(0.2));
	real_t alpha = 123.0;
	CHECK(physics_softbody_fatigue_compliance_alpha(real_t(1.0), 0, alpha));
	CHECK(alpha == 1.0);
}

TEST_CASE("[PhysicsSoftBody] Extremely fast damage safely reaches finite cap") {
	real_t damage = 0;
	CHECK(physics_softbody_accumulate_fatigue_damage(
			Vector3(real_t(-1e20), 0, 0), Vector3(real_t(1e20), 0, 0),
			real_t(1e-6), 0, real_t(1e10), real_t(0.99), 1.0, damage));
	CHECK(Math::is_finite(damage));
	CHECK(Math::abs(damage - real_t(0.99)) < real_t(1e-5));
	real_t alpha = 1;
	CHECK(physics_softbody_fatigue_compliance_alpha(alpha, damage, alpha));
	CHECK(Math::is_finite(alpha));
	CHECK(alpha >= 1);
}

TEST_CASE("[PhysicsSoftBody] Invalid fatigue inputs cannot corrupt persistent damage") {
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	real_t damage = real_t(0.25);
	CHECK_FALSE(physics_softbody_accumulate_fatigue_damage(Vector3(nan, 0, 0), Vector3(),
			1, 0, 1, real_t(0.8), 1, damage));
	CHECK_FALSE(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(1, 0, 0),
			-1, 0, 1, real_t(0.8), 1, damage));
	CHECK_FALSE(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(1, 0, 0),
			1, -1, 1, real_t(0.8), 1, damage));
	CHECK_FALSE(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(1, 0, 0),
			1, 0, -1, real_t(0.8), 1, damage));
	CHECK_FALSE(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(1, 0, 0),
			1, 0, 1, 1, 1, damage));
	CHECK_FALSE(physics_softbody_accumulate_fatigue_damage(Vector3(), Vector3(1, 0, 0),
			1, 0, 1, real_t(0.8), -1, damage));
	CHECK(damage == real_t(0.25));
	real_t alpha = real_t(123.0);
	CHECK_FALSE(physics_softbody_fatigue_compliance_alpha(1, nan, alpha));
	CHECK_FALSE(physics_softbody_fatigue_compliance_alpha(-1, real_t(0.5), alpha));
	CHECK_FALSE(physics_softbody_fatigue_compliance_alpha(1, real_t(1.0), alpha));
	CHECK(alpha == real_t(123.0));
}

} // namespace TestPhysicsSoftBodyFatigueDamage
