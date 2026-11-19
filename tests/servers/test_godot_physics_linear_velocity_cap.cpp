/**************************************************************************/
/*  test_godot_physics_linear_velocity_cap.cpp                             */
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
/**************************************************************************/

#include "core/math/vector2.h"
#include "core/math/vector3.h"
#include "servers/physics_linear_velocity_cap.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_linear_velocity_cap)

namespace TestGodotPhysicsLinearVelocityCap {

TEST_CASE("[GodotPhysics] Opt-in dynamic linear velocity cap") {
	SUBCASE("Disabled is fully backwards compatible") {
		CHECK(godot_physics_clamp_linear_velocity(Vector2(3.0, 4.0), 0.0) == Vector2(3.0, 4.0));
		CHECK(godot_physics_clamp_linear_velocity(Vector3(1.0, 2.0, 3.0), -1.0) == Vector3(1.0, 2.0, 3.0));
	}
	SUBCASE("Below the maximum avoids normalizing") {
		CHECK(godot_physics_clamp_linear_velocity(Vector2(3.0, 4.0), 10.0) == Vector2(3.0, 4.0));
		CHECK(godot_physics_clamp_linear_velocity(Vector3(1.0, 2.0, 2.0), 3.0) == Vector3(1.0, 2.0, 2.0));
	}
	SUBCASE("2D speed and direction preserved") {
		const Vector2 v = godot_physics_clamp_linear_velocity(Vector2(6.0, 8.0), 5.0);
		CHECK(v.is_equal_approx(Vector2(3.0, 4.0)));
	}
	SUBCASE("3D speed and direction preserved") {
		const Vector3 v = godot_physics_clamp_linear_velocity(Vector3(0.0, 0.0, -20.0), 2.0);
		CHECK(v.is_equal_approx(Vector3(0.0, 0.0, -2.0)));
	}
	SUBCASE("Overflow-safe scaling of extreme finite velocities") {
		// In 32-bit real_t, these vectors are finite but length_squared()
		// overflows. They must still be clamped instead of passing through.
		const Vector2 extreme2 = godot_physics_clamp_linear_velocity(
				Vector2(real_t(1e20), real_t(0.0)), real_t(7.0));
		CHECK(extreme2.is_equal_approx(Vector2(7.0, 0.0)));
		const Vector3 extreme3 = godot_physics_clamp_linear_velocity(
				Vector3(real_t(-1e20), real_t(1e20), real_t(0.0)), real_t(10.0));
		CHECK(extreme3.length() == doctest::Approx(10.0));
		CHECK(extreme3.x < 0.0);
		CHECK(extreme3.y > 0.0);
	}
	SUBCASE("Zero and large velocities") {
		CHECK(godot_physics_clamp_linear_velocity(Vector2(), 5.0) == Vector2());
		CHECK(godot_physics_clamp_linear_velocity(Vector3(), 5.0) == Vector3());
		const Vector3 big = godot_physics_clamp_linear_velocity(Vector3(30000.0, -40000.0, 0.0), 50.0);
		CHECK(big.length() == doctest::Approx(50.0));
	}
}

} // namespace TestGodotPhysicsLinearVelocityCap
