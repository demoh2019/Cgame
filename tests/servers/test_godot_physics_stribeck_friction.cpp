/**************************************************************************/
/*  test_godot_physics_stribeck_friction.cpp                              */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER OF CONTRACT, TORT OR OTHERWISE, */
/* ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR   */
/* OTHER DEALINGS IN THE SOFTWARE.                                        */
/**************************************************************************/

#include "servers/physics_contact_velocity_friction.h"
#include "servers/physics_contact_static_friction.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_godot_physics_stribeck_friction)

namespace TestGodotPhysicsStribeckFriction {

TEST_CASE("[GodotPhysics] Stribeck coefficient decays smoothly with tangential speed") {
	CHECK(godot_physics_stribeck_friction_coefficient(real_t(0.5), real_t(2), 0, 1) == doctest::Approx(1.0));
	CHECK(godot_physics_stribeck_friction_coefficient(real_t(0.5), real_t(2), 1, 1) == doctest::Approx(0.75));
	CHECK(godot_physics_stribeck_friction_coefficient(real_t(0.5), real_t(2), 3, 1) == doctest::Approx(0.55));
	CHECK(godot_physics_stribeck_friction_coefficient(real_t(0.5), real_t(2), 1e9, 1) == doctest::Approx(0.5));
}

TEST_CASE("[GodotPhysics] Stribeck never increases friction when speed increases") {
	real_t previous = 10;
	for (int i = 0; i <= 500; ++i) {
		const real_t v = real_t(i) * real_t(0.01);
		const real_t value = godot_physics_stribeck_friction_coefficient(real_t(0.6), real_t(3), v, real_t(0.4));
		CHECK(value <= previous);
		CHECK(value >= real_t(0.6));
		CHECK(value <= real_t(1.8));
		previous = value;
	}
}

TEST_CASE("[GodotPhysics] Zero transition and unit multiplier retain exact Coulomb behavior") {
	CHECK(godot_physics_stribeck_friction_coefficient(0.5, 4, 0.1, 0) == real_t(0.5));
	CHECK(godot_physics_stribeck_friction_coefficient(0.5, 1, 0.1, 3) == real_t(0.5));
	CHECK(godot_physics_stribeck_friction_coefficient(0, 4, 0.1, 3) == real_t(0.0));
}

TEST_CASE("[GodotPhysics] Stribeck uses a single smooth friction cone") {
	const real_t coefficient = godot_physics_stribeck_friction_coefficient(0.5, 2, 1, 1);
	const Vector3 clamped = godot_physics_clamp_static_friction_3d(Vector3(5, 0, 0), coefficient, 1);
	CHECK(clamped.is_equal_approx(Vector3(real_t(0.75), 0, 0)));
	CHECK(godot_physics_clamp_static_friction_3d(Vector3(real_t(0.6), 0, 0), coefficient, 1) ==
			Vector3(real_t(0.6), 0, 0));
}

TEST_CASE("[GodotPhysics] Extreme and malformed input cannot inject invalid friction") {
	const real_t inf = std::numeric_limits<real_t>::infinity();
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK(godot_physics_stribeck_friction_coefficient(0.5, 2, inf, 1) == real_t(0.5));
	CHECK(godot_physics_stribeck_friction_coefficient(0.5, 2, nan, 1) == real_t(0.5));
	CHECK(godot_physics_stribeck_friction_coefficient(nan, 2, 1, 1) == real_t(0));
	CHECK(godot_physics_stribeck_friction_coefficient(0.5, 2, 1, nan) == real_t(0.5));
	CHECK(godot_physics_stribeck_friction_coefficient(0.5, 2, 1, -1) == real_t(0.5));
	const real_t huge = std::numeric_limits<real_t>::max();
	CHECK(Math::is_finite(godot_physics_stribeck_friction_coefficient(huge, huge, 0, 1)));
}

} // namespace TestGodotPhysicsStribeckFriction
