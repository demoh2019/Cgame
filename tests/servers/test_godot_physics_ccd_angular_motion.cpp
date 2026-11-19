/**************************************************************************/
/*  test_godot_physics_ccd_angular_motion.cpp                              */
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

#include "servers/physics_angular_velocity_cap.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_ccd_angular_motion)

namespace TestGodotPhysicsCCDAngularMotion {

TEST_CASE("[GodotPhysics] Disabled per-step CCD angular cap preserves rotation") {
	const real_t angular = 120;
	const Vector3 angular3(20, -30, 40);
	CHECK(godot_physics_clamp_ccd_angular_velocity(angular, 0, real_t(1.0 / 60.0)) == angular);
	CHECK(godot_physics_clamp_ccd_angular_velocity(angular3, 0, real_t(1.0 / 60.0)) == angular3);
}

TEST_CASE("[GodotPhysics] Per-step CCD angular cap scales with delta") {
	const real_t limit = Math::PI / real_t(4.0);
	const real_t step = real_t(1.0 / 60.0);
	const real_t clamped = godot_physics_clamp_ccd_angular_velocity(real_t(100), limit, step);
	CHECK(clamped > 0);
	CHECK(Math::abs(clamped * step) <= limit + real_t(1e-5));
	CHECK(Math::is_equal_approx(godot_physics_clamp_ccd_angular_velocity(real_t(-100), limit, step), -clamped));
	CHECK(godot_physics_clamp_ccd_angular_velocity(real_t(4), limit, step) == real_t(4));
	// A shorter step permits more angular speed while keeping the same
	// physical per-step rotation limit.
	const real_t short_step = step * real_t(0.5);
	const real_t short_limit = godot_physics_clamp_ccd_angular_velocity(real_t(100), limit, short_step);
	CHECK(short_limit >= clamped);
	CHECK(Math::abs(short_limit * short_step) <= limit + real_t(1e-5));
}

TEST_CASE("[GodotPhysics] CCD angular cap preserves 3D rotation direction") {
	const Vector3 omega(100, 200, -300);
	const real_t step = real_t(1.0 / 60.0);
	const real_t limit = Math::PI / real_t(4.0);
	const Vector3 result = godot_physics_clamp_ccd_angular_velocity(omega, limit, step);
	CHECK(result.is_finite());
	CHECK(result.length() * step <= limit + real_t(1e-5));
	CHECK(result.dot(omega) > 0);
	CHECK(result.cross(omega).length() <= real_t(0.001));
}

TEST_CASE("[GodotPhysics] Invalid step and maximum never divide by zero") {
	const Vector3 omega(50, 0, 0);
	CHECK(godot_physics_clamp_ccd_angular_velocity(omega, real_t(0.8), 0) == omega);
	CHECK(godot_physics_clamp_ccd_angular_velocity(omega, real_t(0.8), -1) == omega);
	CHECK(godot_physics_clamp_ccd_angular_velocity(omega, -1, real_t(0.01)) == omega);
	CHECK(godot_physics_clamp_ccd_angular_velocity(real_t(20), real_t(0.8), 0) == real_t(20));
	CHECK(godot_physics_clamp_ccd_angular_velocity(real_t(20), -1, real_t(0.01)) == real_t(20));
}

TEST_CASE("[GodotPhysics] CCD angular cap composes with global angular speed cap") {
	const real_t step = real_t(1.0 / 60.0);
	const real_t max_angle = Math::PI / real_t(4.0);
	const real_t globally_limited = godot_physics_clamp_angular_velocity(real_t(500), real_t(10));
	const real_t ccd_limited = godot_physics_clamp_ccd_angular_velocity(globally_limited, max_angle, step);
	CHECK(Math::is_equal_approx(ccd_limited, real_t(10)));
	const Vector3 globally_limited3 = godot_physics_clamp_angular_velocity(Vector3(0, 0, 500), real_t(10));
	const Vector3 ccd_limited3 = godot_physics_clamp_ccd_angular_velocity(globally_limited3, max_angle, step);
	CHECK(Math::is_equal_approx(ccd_limited3.length(), real_t(10)));
}

} // namespace TestGodotPhysicsCCDAngularMotion
