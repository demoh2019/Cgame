/**************************************************************************/
/*  test_physics_joint_fatigue.cpp                                        */
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

#include "servers/physics_joint_fatigue.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_joint_fatigue)

namespace TestPhysicsJointFatigue {

TEST_CASE("[PhysicsJoint] Subcritical repeated force accumulates damage and eventually breaks") {
	double damage = 0.0;
	for (int i = 0; i < 16; ++i) {
		CHECK(physics_joint_accumulate_fatigue_damage(
				75, 0, 100, 0, .5, 10.0, .1, damage));
	}
	CHECK(damage == doctest::Approx(1.0));
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(
			75, 0, 100, 0, .5, 10.0, .1, damage));
}

TEST_CASE("[PhysicsJoint] Force below fatigue yield never accumulates damage") {
	double damage = .2;
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(30, 0, 100, 0, .5, 5.0, 1.0, damage));
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(50, 0, 100, 0, .5, 5.0, 1.0, damage));
	CHECK(damage == doctest::Approx(.2));
}

TEST_CASE("[PhysicsJoint] Torque and force channels are normalized by independent limits") {
	double damage = 0.0;
	CHECK(physics_joint_accumulate_fatigue_damage(
			60, 80, 100, 200, .5, 2, 1, damage));
	// sqrt((60/100)^2+(80/200)^2)=sqrt(.52).
	const double utilization = std::sqrt(.36 + .16);
	CHECK(damage == doctest::Approx(2.0 * (utilization-.5) * (utilization-.5)));
}

TEST_CASE("[PhysicsJoint] An unset force threshold excludes the force channel") {
	double damage = 0;
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(1e9, 0, 0, 100, .5, 1, 1, damage));
	CHECK(physics_joint_accumulate_fatigue_damage(1e9, 60, 0, 100, .5, 1, 1, damage));
	CHECK(damage == doctest::Approx(.01));
}

TEST_CASE("[PhysicsJoint] Force fatigue is additive in time across substeps") {
	double full = 0, split = 0;
	CHECK(physics_joint_accumulate_fatigue_damage(80, 0, 100, 0, .4, 2, .5, full));
	for (int i = 0; i < 10; i++) {
		CHECK(physics_joint_accumulate_fatigue_damage(80, 0, 100, 0, .4, 2, .05, split));
	}
	CHECK(split == doctest::Approx(full).epsilon(1e-10));
}

TEST_CASE("[PhysicsJoint] Finite extreme load saturates and cannot overflow damage") {
	double damage = 0.0;
	CHECK(physics_joint_accumulate_fatigue_damage(
			std::numeric_limits<double>::max(), std::numeric_limits<double>::max(),
			1e-300, 1e-300, .1, 1e300, 1e300, damage));
	CHECK(damage == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsJoint] NaN, negative and zero-rate inputs leave damage unchanged") {
	double damage = .4;
	const double nan = std::numeric_limits<double>::quiet_NaN();
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(nan, 0, 100, 0, .5, 1, .1, damage));
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(-1, 0, 100, 0, .5, 1, .1, damage));
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(90, 0, 100, 0, 1.1, 1, .1, damage));
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(90, 0, 100, 0, .5, 0, .1, damage));
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(90, 0, 100, 0, .5, 1, 0, damage));
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(90, 0, 0, 0, .5, 1, .1, damage));
	CHECK(damage == doctest::Approx(.4));
}

TEST_CASE("[PhysicsJoint] Default-off state and one-tick recovery preserve the old solver") {
	double damage = 0.0;
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(
			90, 0, 100, 0, .5, 0, .1, damage));
	CHECK(damage == 0.0);
	CHECK(physics_joint_accumulate_fatigue_damage(70, 0, 100, 0, .5, 1, .1, damage));
	const double after_loading = damage;
	CHECK_FALSE(physics_joint_accumulate_fatigue_damage(0, 0, 100, 0, .5, 1, .1, damage));
	CHECK(damage == after_loading); // No healing in this simple model.
}

} // namespace TestPhysicsJointFatigue
