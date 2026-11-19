/**************************************************************************/
/*  test_godot_physics_contact_static_friction.cpp                         */
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

#include "servers/physics_contact_static_friction.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_contact_static_friction)

namespace TestGodotPhysicsContactStaticFriction {

TEST_CASE("[GodotPhysics] Static and dynamic Coulomb friction cones") {
	SUBCASE("Default multiplier has exactly the legacy clamp") {
		for (int i = -20; i <= 20; ++i) {
			const real_t candidate = i * real_t(0.1);
			CHECK(godot_physics_clamp_static_friction_2d(candidate, real_t(0.5), real_t(1.0)) ==
					doctest::Approx(CLAMP(candidate, real_t(-0.5), real_t(0.5))));
		}
	}
	SUBCASE("2D sticks inside static cone, slides with dynamic friction outside") {
		CHECK(godot_physics_clamp_static_friction_2d(real_t(0.8), real_t(0.5), real_t(2.0)) == doctest::Approx(0.8));
		CHECK(godot_physics_clamp_static_friction_2d(real_t(-0.8), real_t(0.5), real_t(2.0)) == doctest::Approx(-0.8));
		CHECK(godot_physics_clamp_static_friction_2d(real_t(1.2), real_t(0.5), real_t(2.0)) == doctest::Approx(0.5));
	}
	SUBCASE("3D cone uses impulse length, not individual components") {
		const Vector3 static_impulse(0.6, 0.8, 0.0);
		CHECK(godot_physics_clamp_static_friction_3d(static_impulse, real_t(0.6), real_t(2.0)) == static_impulse);
		const Vector3 slip = godot_physics_clamp_static_friction_3d(Vector3(3.0, 4.0, 0.0), real_t(0.6), real_t(2.0));
		CHECK(slip.is_equal_approx(Vector3(0.36, 0.48, 0.0)));
	}
	SUBCASE("No normal load cannot sustain friction") {
		CHECK(godot_physics_clamp_static_friction_2d(real_t(1.0), real_t(0.0), real_t(3.0)) == doctest::Approx(0.0));
		CHECK(godot_physics_clamp_static_friction_3d(Vector3(1.0, 0.0, 0.0), real_t(0.0), real_t(3.0)) == Vector3());
	}
	SUBCASE("Static cone can hold a cached impulse larger than dynamic cone") {
		CHECK(godot_physics_clamp_static_friction_2d(real_t(0.9), real_t(0.5), real_t(2.0)) == doctest::Approx(0.9));
		CHECK(godot_physics_clamp_static_friction_3d(Vector3(0.0, 0.9, 0.0), real_t(0.5), real_t(2.0)) ==
				Vector3(0.0, 0.9, 0.0));
	}
	SUBCASE("3D large finite slip keeps a nonzero kinetic friction impulse") {
		// float32 length_squared(1e20, -1e20, 0) is infinite.
		// Projection must still have exactly the requested kinetic magnitude.
		const Vector3 slip = godot_physics_clamp_static_friction_3d(
				Vector3(real_t(1e20), real_t(-1e20), real_t(0.0)),
				real_t(5.0), real_t(2.0));
		CHECK(slip.is_finite());
		CHECK(slip.x / real_t(5.0) == doctest::Approx(0.70710678118).epsilon(1e-5));
		CHECK(slip.y / real_t(5.0) == doctest::Approx(-0.70710678118).epsilon(1e-5));
		CHECK(slip.z == real_t(0.0));
		CHECK(slip.length() == doctest::Approx(5.0));
	}
	SUBCASE("3D large finite impulse stays inside large static cone") {
		const Vector3 candidate(real_t(1e20), real_t(-1e20), real_t(0.0));
		CHECK(godot_physics_clamp_static_friction_3d(
					candidate, real_t(1e20), real_t(2.0)) == candidate);
	}
	SUBCASE("3D large impulse and tiny kinetic limit do not underflow scale") {
		const Vector3 slip = godot_physics_clamp_static_friction_3d(
				Vector3(real_t(1e38), real_t(-1e38), real_t(0.0)),
				real_t(1e-10), real_t(1.0));
		CHECK(slip.is_finite());
		CHECK(slip.x / real_t(1e-10) == doctest::Approx(0.70710678118).epsilon(1e-5));
		CHECK(slip.y / real_t(1e-10) == doctest::Approx(-0.70710678118).epsilon(1e-5));
		CHECK(godot_physics_clamp_static_friction_3d(
					Vector3(real_t(1e20), 0, 0), real_t(0.0), real_t(2.0)) == Vector3());
	}
	SUBCASE("Multiplier cannot weaken normal kinetic friction") {
		CHECK(godot_physics_clamp_static_friction_2d(real_t(0.6), real_t(0.5), real_t(-2.0)) == doctest::Approx(0.5));
		CHECK(godot_physics_clamp_static_friction_3d(Vector3(0.0, 0.0, 0.6), real_t(0.5), real_t(-2.0)).length() ==
				doctest::Approx(0.5));
	}
}

} // namespace TestGodotPhysicsContactStaticFriction
