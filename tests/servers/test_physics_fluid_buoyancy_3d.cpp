/**************************************************************************/
/*  test_physics_fluid_buoyancy_3d.cpp                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_fluid_buoyancy_3d)

#include "servers/physics_fluid_buoyancy_3d.h"

namespace TestPhysicsFluidBuoyancy3D {

TEST_CASE("[Physics] Fluid surface produces correct dry partial and full submerged volume") {
	const AABB bounds(Vector3(-1, -2, -3), Vector3(2, 4, 6));
	const real_t volume = 24.0;

	const GodotPhysicsFluidSample3D dry = godot_physics_fluid_sample_3d(bounds, volume, -3.0);
	CHECK(dry.submerged_volume == 0.0);
	CHECK(dry.submerged_fraction == 0.0);

	const GodotPhysicsFluidSample3D partial = godot_physics_fluid_sample_3d(bounds, volume, 0.0);
	CHECK(Math::is_equal_approx(partial.submerged_volume, real_t(12.0)));
	CHECK(Math::is_equal_approx(partial.submerged_fraction, real_t(0.5)));
	CHECK(Math::is_equal_approx(partial.center_of_buoyancy.y, real_t(-1.0)));
	CHECK(Math::is_equal_approx(partial.center_of_buoyancy.x, real_t(0.0)));
	CHECK(Math::is_equal_approx(partial.center_of_buoyancy.z, real_t(0.0)));

	const GodotPhysicsFluidSample3D full = godot_physics_fluid_sample_3d(bounds, volume, 3.0);
	CHECK(Math::is_equal_approx(full.submerged_volume, volume));
	CHECK(Math::is_equal_approx(full.submerged_fraction, real_t(1.0)));
	CHECK(Math::is_equal_approx(full.center_of_buoyancy.y, real_t(0.0)));

	CHECK(godot_physics_fluid_sample_3d(bounds, -1.0, 0.0).submerged_volume == 0.0);
	CHECK(godot_physics_fluid_sample_3d(AABB(Vector3(), Vector3(1, 0, 1)), volume, 1.0).submerged_volume == 0.0);
}

TEST_CASE("[Physics] Partly submerged eccentric shape generates restoring buoyant torque") {
	const GodotPhysicsFluidSample3D sample = godot_physics_fluid_sample_3d(
			AABB(Vector3(1, -1, -1), Vector3(2, 2, 2)), 8.0, 0.0);
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(4.0)));
	const Vector3 gravity(0.0, -9.8, 0.0);
	const Vector3 lift = -gravity * sample.submerged_volume; // Density 1.
	const Vector3 lever = sample.center_of_buoyancy - Vector3();
	const Vector3 torque = lever.cross(lift);
	CHECK(lift.y > 0.0);
	CHECK(torque.z > 0.0);
	CHECK(Math::is_equal_approx(torque.z, real_t(2.0) * lift.y));
}

TEST_CASE("[Physics] Quadratic fluid drag opposes relative flow and increases with speed squared") {
	const Vector3 size(2, 3, 4);
	const Vector3 slow = godot_physics_fluid_quadratic_drag_3d(Vector3(2, 0, 0), size, 1.0, 1.0, 1.0);
	const Vector3 fast = godot_physics_fluid_quadratic_drag_3d(Vector3(4, 0, 0), size, 1.0, 1.0, 1.0);
	CHECK(slow.x < 0.0);
	CHECK(Math::is_equal_approx(fast.x, real_t(4.0) * slow.x));
	CHECK(Math::is_equal_approx(slow.y, real_t(0.0)));
	CHECK(Math::is_equal_approx(slow.z, real_t(0.0)));

	const Vector3 half = godot_physics_fluid_quadratic_drag_3d(Vector3(2, 0, 0), size, 0.5, 1.0, 1.0);
	CHECK(Math::is_equal_approx(half.x, real_t(0.5) * slow.x));
	CHECK(godot_physics_fluid_quadratic_drag_3d(Vector3(), size, 1.0, 1.0, 1.0) == Vector3());
	CHECK(godot_physics_fluid_quadratic_drag_3d(Vector3(2, 0, 0), size, 0.0, 1.0, 1.0) == Vector3());
	CHECK(godot_physics_fluid_quadratic_drag_3d(Vector3(2, 0, 0), size, 1.0, 0.0, 1.0) == Vector3());
}

TEST_CASE("[Physics] Angular water drag is stable under large timesteps") {
	CHECK(Math::is_equal_approx(godot_physics_fluid_angular_damping_3d(0.0, 1.0, 1.0), real_t(1.0)));
	CHECK(Math::is_equal_approx(godot_physics_fluid_angular_damping_3d(10.0, 0.0, 1.0), real_t(1.0)));
	const real_t short_step = godot_physics_fluid_angular_damping_3d(2.0, 1.0, 0.1);
	const real_t long_step = godot_physics_fluid_angular_damping_3d(2.0, 1.0, 10.0);
	CHECK(short_step > long_step);
	CHECK(short_step < 1.0);
	CHECK(long_step > 0.0);
}

} // namespace TestPhysicsFluidBuoyancy3D
