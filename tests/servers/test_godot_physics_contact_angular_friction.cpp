/**************************************************************************/
/*  test_godot_physics_contact_angular_friction.cpp                       */
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

#include "servers/physics_contact_angular_friction.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_contact_angular_friction)

namespace TestGodotPhysicsContactAngularFriction {

TEST_CASE("[GodotPhysics] Rolling friction is zero by default and without load") {
	using Solver = GodotPhysicsContactAngularFriction;
	CHECK(Solver::clamped_impulse(8, 2, 10, 0, 1) == 0.0);
	CHECK(Solver::clamped_impulse(8, 2, 0, 0.4, 1) == 0.0);
	CHECK(Solver::clamped_impulse(8, 2, 10, 0.4, 0) == 0.0);
	CHECK(Solver::clamped_impulse(8, 0, 10, 0.4, 1) == 0.0);
	CHECK(Solver::clamped_impulse(8, -2, 10, 0.4, 1) == 0.0);
}

TEST_CASE("[GodotPhysics] Friction torque is bounded and opposes relative spin") {
	using Solver = GodotPhysicsContactAngularFriction;
	// Desired impulse is -8 / 2 = -4; Coulomb limit is 0.1 * 10 * 1 = 1.
	CHECK(Math::is_equal_approx(Solver::clamped_impulse(8, 2, 10, real_t(0.1), 1), real_t(-1)));
	CHECK(Math::is_equal_approx(Solver::clamped_impulse(-8, 2, 10, real_t(0.1), 1), real_t(1)));
	// A large load can cancel all relative rotation in one correction,
	// but cannot reverse its sign (which would add energy).
	CHECK(Math::is_equal_approx(Solver::clamped_impulse(8, 2, 100, 1, 1), real_t(-4)));
}

TEST_CASE("[GodotPhysics] Rolling friction scales with loaded radius") {
	using Solver = GodotPhysicsContactAngularFriction;
	const real_t narrow = Solver::clamped_impulse(8, 2, 10, real_t(0.1), real_t(0.5));
	const real_t wide = Solver::clamped_impulse(8, 2, 10, real_t(0.1), real_t(2.0));
	CHECK(Math::is_equal_approx(narrow, real_t(-0.5)));
	CHECK(Math::is_equal_approx(wide, real_t(-2.0)));
}

TEST_CASE("[GodotPhysics] Pure angular impulse cannot increase relative rotational energy") {
	using Solver = GodotPhysicsContactAngularFriction;
	const real_t inv_inertias[] = { real_t(0.01), real_t(0.25), real_t(1), real_t(4) };
	const real_t relative_speeds[] = { real_t(-100), real_t(-3), real_t(-0.01), real_t(0), real_t(0.01), real_t(3), real_t(100) };
	for (real_t inverse_inertia : inv_inertias) {
		for (real_t speed : relative_speeds) {
			const real_t impulse = Solver::clamped_impulse(speed, inverse_inertia, real_t(2), real_t(0.3), real_t(1.5));
			const real_t corrected = speed + inverse_inertia * impulse;
			CHECK(Math::abs(corrected) <= Math::abs(speed) + real_t(0.0001));
		}
	}
}

} // namespace TestGodotPhysicsContactAngularFriction
