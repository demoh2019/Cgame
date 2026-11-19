/**************************************************************************/
/*  test_godot_physics_angular_velocity_cap.cpp                            */
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

#include "servers/physics_angular_velocity_cap.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_angular_velocity_cap)

namespace TestGodotPhysicsAngularVelocityCap {

TEST_CASE("[GodotPhysics] Dynamic angular speed limits") {
	SUBCASE("Zero and negative limits preserve legacy behavior") {
		CHECK(godot_physics_clamp_angular_velocity(real_t(-123.0), real_t(0.0)) == doctest::Approx(-123.0));
		CHECK(godot_physics_clamp_angular_velocity(Vector3(30, -40, 0), real_t(-1.0)) == Vector3(30, -40, 0));
	}
	SUBCASE("2D angular cap preserves rotation sign") {
		CHECK(godot_physics_clamp_angular_velocity(real_t(42.0), real_t(10.0)) == doctest::Approx(10.0));
		CHECK(godot_physics_clamp_angular_velocity(real_t(-42.0), real_t(10.0)) == doctest::Approx(-10.0));
		CHECK(godot_physics_clamp_angular_velocity(real_t(8.0), real_t(10.0)) == doctest::Approx(8.0));
	}
	SUBCASE("3D angular cap preserves rotation axis") {
		const Vector3 capped = godot_physics_clamp_angular_velocity(Vector3(30, 40, 0), real_t(10.0));
		CHECK(capped.is_equal_approx(Vector3(6, 8, 0)));
		CHECK(godot_physics_clamp_angular_velocity(Vector3(1, 2, 2), real_t(3.0)) == Vector3(1, 2, 2));
	}
	SUBCASE("Zero angular velocity remains zero") {
		CHECK(godot_physics_clamp_angular_velocity(real_t(0.0), real_t(2.0)) == doctest::Approx(0.0));
		CHECK(godot_physics_clamp_angular_velocity(Vector3(), real_t(2.0)) == Vector3());
	}
	SUBCASE("Extreme 3D angular velocities clamp safely even in float builds") {
		const Vector3 extreme = godot_physics_clamp_angular_velocity(
				Vector3(real_t(1e20), real_t(-1e20), real_t(0.0)), real_t(5.0));
		CHECK(extreme.length() == doctest::Approx(5.0));
		CHECK(extreme.x > 0.0);
		CHECK(extreme.y < 0.0);
	}
}

} // namespace TestGodotPhysicsAngularVelocityCap
