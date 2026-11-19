/**************************************************************************/
/*  test_physics_fluid_analytic_primitives_3d.cpp                          */
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

TEST_FORCE_LINK(test_physics_fluid_analytic_primitives_3d)

#include "servers/physics_fluid_buoyancy_3d.h"

namespace TestPhysicsFluidAnalyticPrimitives3D {

TEST_CASE("[Physics] Analytic sphere waterline volume and buoyancy centroid") {
	const real_t volume = real_t(4.0 / 3.0) * Math::PI;
	const Vector3 center(2.0, 0.0, -3.0);
	const GodotPhysicsFluidSample3D dry = godot_physics_fluid_sphere_sample_3d(center, 1.0, volume, -1.1);
	CHECK(dry.submerged_volume == 0.0);

	const GodotPhysicsFluidSample3D quarter = godot_physics_fluid_sphere_sample_3d(center, 1.0, volume, -0.5);
	CHECK(Math::is_equal_approx(quarter.submerged_fraction, real_t(0.15625)));
	CHECK(Math::is_equal_approx(quarter.submerged_volume, Math::PI * real_t(5.0 / 24.0)));
	CHECK(Math::is_equal_approx(quarter.center_of_buoyancy.y, real_t(-0.675)));
	CHECK(Math::is_equal_approx(quarter.center_of_buoyancy.x, center.x));
	CHECK(Math::is_equal_approx(quarter.center_of_buoyancy.z, center.z));

	const GodotPhysicsFluidSample3D half = godot_physics_fluid_sphere_sample_3d(center, 1.0, volume, 0.0);
	CHECK(Math::is_equal_approx(half.submerged_fraction, real_t(0.5)));
	CHECK(Math::is_equal_approx(half.center_of_buoyancy.y, real_t(-3.0 / 8.0)));

	const GodotPhysicsFluidSample3D above_half = godot_physics_fluid_sphere_sample_3d(center, 1.0, volume, 0.5);
	CHECK(Math::is_equal_approx(above_half.submerged_fraction, real_t(0.84375)));
	CHECK(Math::is_equal_approx(above_half.center_of_buoyancy.y, real_t(-0.125)));

	const GodotPhysicsFluidSample3D full = godot_physics_fluid_sphere_sample_3d(center, 1.0, volume, 2.0);
	CHECK(Math::is_equal_approx(full.submerged_fraction, real_t(1.0)));
	CHECK(Math::is_equal_approx(full.center_of_buoyancy.y, center.y));
	CHECK(godot_physics_fluid_sphere_sample_3d(center, 0.0, volume, 0.0).submerged_volume == 0.0);
}

TEST_CASE("[Physics] Analytic vertical capsule integrates lower hemisphere cylinder and upper hemisphere") {
	const real_t volume = Math::PI * real_t(10.0 / 3.0); // r=1, height=4; cylinder length=2.
	const Vector3 center(5.0, 0.0, -4.0);
	const GodotPhysicsFluidSample3D dry = godot_physics_fluid_vertical_capsule_sample_3d(center, 1.0, 4.0, volume, -3.0);
	CHECK(dry.submerged_fraction == 0.0);
	const GodotPhysicsFluidSample3D lower_cap = godot_physics_fluid_vertical_capsule_sample_3d(center, 1.0, 4.0, volume, -1.5);
	CHECK(Math::is_equal_approx(lower_cap.submerged_fraction, real_t(0.0625)));
	CHECK(Math::is_equal_approx(lower_cap.center_of_buoyancy.y, real_t(-1.675)));
	const GodotPhysicsFluidSample3D at_cylinder = godot_physics_fluid_vertical_capsule_sample_3d(center, 1.0, 4.0, volume, -1.0);
	CHECK(Math::is_equal_approx(at_cylinder.submerged_fraction, real_t(0.2)));
	CHECK(Math::is_equal_approx(at_cylinder.center_of_buoyancy.y, real_t(-1.375)));
	const GodotPhysicsFluidSample3D half = godot_physics_fluid_vertical_capsule_sample_3d(center, 1.0, 4.0, volume, 0.0);
	CHECK(Math::is_equal_approx(half.submerged_fraction, real_t(0.5)));
	CHECK(Math::is_equal_approx(half.center_of_buoyancy.y, real_t(-0.85)));
	CHECK(Math::is_equal_approx(half.center_of_buoyancy.x, center.x));
	CHECK(Math::is_equal_approx(half.center_of_buoyancy.z, center.z));
	const GodotPhysicsFluidSample3D upper_cap = godot_physics_fluid_vertical_capsule_sample_3d(center, 1.0, 4.0, volume, 1.0);
	CHECK(Math::is_equal_approx(upper_cap.submerged_fraction, real_t(0.8)));
	CHECK(Math::is_equal_approx(upper_cap.center_of_buoyancy.y, real_t(-0.34375)));
	const GodotPhysicsFluidSample3D full = godot_physics_fluid_vertical_capsule_sample_3d(center, 1.0, 4.0, volume, 3.0);
	CHECK(Math::is_equal_approx(full.submerged_fraction, real_t(1.0)));
	CHECK(Math::is_equal_approx(full.center_of_buoyancy.y, center.y));

	// A zero-length cylinder exactly degenerates to the sphere formula.
	const real_t sphere_volume = Math::PI * real_t(4.0 / 3.0);
	const GodotPhysicsFluidSample3D short_capsule = godot_physics_fluid_vertical_capsule_sample_3d(Vector3(), 1.0, 2.0, sphere_volume, -0.5);
	const GodotPhysicsFluidSample3D sphere = godot_physics_fluid_sphere_sample_3d(Vector3(), 1.0, sphere_volume, -0.5);
	CHECK(Math::is_equal_approx(short_capsule.submerged_volume, sphere.submerged_volume));
	CHECK(Math::is_equal_approx(short_capsule.center_of_buoyancy.y, sphere.center_of_buoyancy.y));
	CHECK(godot_physics_fluid_vertical_capsule_sample_3d(center, 1.0, 1.0, volume, 0.0).submerged_volume == 0.0);
}

TEST_CASE("[Physics] Primitive analytic sampling is restricted to similarity transforms and upright capsules") {
	real_t scale = 0.0;
	const Basis upright = Basis::from_scale(Vector3(2.0, 2.0, 2.0));
	CHECK(godot_physics_fluid_uniform_scale_3d(upright, scale));
	CHECK(Math::is_equal_approx(scale, real_t(2.0)));
	CHECK(godot_physics_fluid_capsule_vertical_3d(upright, scale));
	const Basis reflected = Basis::from_scale(Vector3(-2.0, -2.0, 2.0));
	CHECK(godot_physics_fluid_uniform_scale_3d(reflected, scale));
	CHECK(godot_physics_fluid_capsule_vertical_3d(reflected, scale));
	const Basis nonuniform = Basis::from_scale(Vector3(2.0, 2.5, 2.0));
	CHECK(!godot_physics_fluid_uniform_scale_3d(nonuniform, scale));
	const Basis tilted(Vector3(1, 0, 0), real_t(0.3));
	CHECK(godot_physics_fluid_uniform_scale_3d(tilted, scale));
	CHECK(!godot_physics_fluid_capsule_vertical_3d(tilted, scale));

	// A sphere scales under uniform transforms with r^3 volume and its
	// waterline and exact hydrostatic centroid scale together.
	const GodotPhysicsFluidSample3D scaled = godot_physics_fluid_sphere_sample_3d(Vector3(), 2.0,
			real_t(8.0) * Math::PI * real_t(4.0 / 3.0), -1.0);
	CHECK(Math::is_equal_approx(scaled.submerged_fraction, real_t(0.15625)));
	CHECK(Math::is_equal_approx(scaled.center_of_buoyancy.y, real_t(-1.35)));
}

} // namespace TestPhysicsFluidAnalyticPrimitives3D
