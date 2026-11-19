/**************************************************************************/
/*  test_godot_physics_ccd_rotational_bounds.cpp                           */
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

#include "servers/physics_ccd_rotational_bounds.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_ccd_rotational_bounds)

namespace TestGodotPhysicsCCDRotationalBounds {

TEST_CASE("[GodotPhysics] CCD angular broadphase padding") {
	SUBCASE("Zero rotation leaves swept bounds exactly unchanged") {
		CHECK(godot_physics_ccd_rotational_factor(real_t(0.0)) == doctest::Approx(0.0));
		CHECK(godot_physics_ccd_rotational_padding(Rect2(Vector2(0, 0), Vector2(4, 2)), Vector2(), real_t(0.0)) == doctest::Approx(0.0));
		CHECK(godot_physics_ccd_rotational_padding(AABB(Vector3(), Vector3(4, 2, 1)), Vector3(), real_t(0.0)) == doctest::Approx(0.0));
	}
	SUBCASE("Quarter turn and half turn have correct chord factors") {
		CHECK(godot_physics_ccd_rotational_factor(Math::PI / real_t(2.0)) == doctest::Approx(Math::SQRT2));
		CHECK(godot_physics_ccd_rotational_factor(-Math::PI) == doctest::Approx(2.0));
		CHECK(godot_physics_ccd_rotational_factor(real_t(10.0) * Math::PI) == doctest::Approx(2.0));
	}
	SUBCASE("2D long offset collider includes rotating distant corners") {
		const Rect2 bounds(Vector2(8, -1), Vector2(4, 2));
		const real_t pad = godot_physics_ccd_rotational_padding(bounds, Vector2(), real_t(2.0));
		CHECK(pad == doctest::Approx(real_t(2.0) * Math::sqrt(real_t(145.0))));
	}
	SUBCASE("3D long offset collider accounts for all AABB corners") {
		const AABB bounds(Vector3(8, -1, -2), Vector3(4, 2, 4));
		const real_t pad = godot_physics_ccd_rotational_padding(bounds, Vector3(), real_t(2.0));
		CHECK(pad == doctest::Approx(real_t(2.0) * Math::sqrt(real_t(149.0))));
	}
	SUBCASE("Translation independent angle and pivot offset") {
		const Rect2 bounds(Vector2(10, -1), Vector2(2, 2));
		const real_t pad = godot_physics_ccd_rotational_padding(bounds, Vector2(11, 0), real_t(1.0));
		// The pivot sits at the box center, so every corner is sqrt(2) away.
		CHECK(pad == doctest::Approx(Math::SQRT2));
	}
	SUBCASE("Angles below one half turn keep a tighter bound") {
		const real_t tiny = godot_physics_ccd_rotational_factor(real_t(0.01));
		CHECK(tiny > real_t(0.0));
		CHECK(tiny < real_t(0.011));
	}
}

} // namespace TestGodotPhysicsCCDRotationalBounds
