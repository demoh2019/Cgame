/**************************************************************************/
/*  test_physics_fluid_box_3d.cpp                                         */
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

TEST_FORCE_LINK(test_physics_fluid_box_3d)

#include "servers/physics_fluid_box_3d.h"

namespace TestPhysicsFluidBox3D {

TEST_CASE("[Physics] Exact box hydrostatics preserve partial volume and centroid") {
	GodotPhysicsFluidSample3D sample;
	real_t volume = 0.0;
	const Vector3 half(1, 1, 1);
	CHECK(godot_physics_fluid_box_sample_3d(half, Transform3D(), 0.0, sample, volume));
	CHECK(Math::is_equal_approx(volume, real_t(8.0)));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(4.0)));
	CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(0.5)));
	CHECK(sample.center_of_buoyancy.distance_to(Vector3(0, -0.5, 0)) < real_t(0.0001));

	CHECK(godot_physics_fluid_box_sample_3d(half, Transform3D(), -0.5, sample, volume));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(2.0)));
	CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(0.25)));
	CHECK(sample.center_of_buoyancy.distance_to(Vector3(0, -0.75, 0)) < real_t(0.0001));

	CHECK(godot_physics_fluid_box_sample_3d(half, Transform3D(), -3.0, sample, volume));
	CHECK(sample.submerged_volume == real_t(0.0));
	CHECK(sample.submerged_fraction == real_t(0.0));
	CHECK(godot_physics_fluid_box_sample_3d(half, Transform3D(), 3.0, sample, volume));
	CHECK(Math::is_equal_approx(sample.submerged_volume, volume));
	CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(1.0)));
	CHECK(sample.center_of_buoyancy.distance_to(Vector3()) < real_t(0.0001));
}

TEST_CASE("[Physics] Rotated box hydrostatic centroid differs from naive world AABB") {
	const Basis rotated(Vector3(0, 0, 1), real_t(Math::PI / 4.0));
	GodotPhysicsFluidSample3D sample;
	real_t volume;
	CHECK(godot_physics_fluid_box_sample_3d(Vector3(1, 1, 1),
			Transform3D(rotated, Vector3()), real_t(0.0), sample, volume));
	CHECK(Math::is_equal_approx(volume, real_t(8.0)));
	CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(0.5)));
	CHECK(Math::abs(sample.center_of_buoyancy.y +
			Math::sqrt(real_t(2.0)) / real_t(3.0)) < real_t(0.0001));
	CHECK(Math::abs(sample.center_of_buoyancy.x) < real_t(0.0001));
	CHECK(Math::abs(sample.center_of_buoyancy.z) < real_t(0.0001));

	// Old AABB height clipping would yield a submerged centroid of
	// -sqrt(2)/2 instead of the true -sqrt(2)/3.
	CHECK(Math::abs(sample.center_of_buoyancy.y + Math::sqrt(real_t(2.0)) * real_t(0.5)) > real_t(0.2));
}

TEST_CASE("[Physics] Exact box immersion supports nonuniform scale reflection shear and world translation") {
	GodotPhysicsFluidSample3D sample;
	real_t volume;
	const Transform3D stretched(Basis::from_scale(Vector3(2, 3, 4)), Vector3(100, 20, -100));
	CHECK(godot_physics_fluid_box_sample_3d(Vector3(1, 1, 1), stretched, 20.0, sample, volume));
	CHECK(Math::is_equal_approx(volume, real_t(192.0)));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(96.0)));
	CHECK(sample.center_of_buoyancy.distance_to(Vector3(100, 18.5, -100)) < real_t(0.0002));

	const Transform3D mirrored(Basis::from_scale(Vector3(-2, 3, 4)), Vector3());
	CHECK(godot_physics_fluid_box_sample_3d(Vector3(1, 1, 1), mirrored, 0.0, sample, volume));
	CHECK(Math::is_equal_approx(volume, real_t(192.0)));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(96.0)));

	const Basis sheared(Vector3(1, 0, 0), Vector3(0.35, 1, 0), Vector3(0, 0, 1));
	CHECK(godot_physics_fluid_box_sample_3d(Vector3(1, 1, 1), Transform3D(sheared, Vector3()), 0.0, sample, volume));
	CHECK(Math::is_equal_approx(volume, real_t(8.0)));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(4.0)));
	CHECK(sample.center_of_buoyancy.distance_to(Vector3(-0.175, -0.5, 0)) < real_t(0.0001));
}

TEST_CASE("[Physics] Degenerate or invalid boxes cannot inject nonfinite fluid forces") {
	GodotPhysicsFluidSample3D sample;
	real_t volume = 1.0;
	CHECK(!godot_physics_fluid_box_sample_3d(Vector3(1, 0, 1), Transform3D(), 0.0, sample, volume));
	CHECK(volume == real_t(0.0));
	CHECK(!godot_physics_fluid_box_sample_3d(Vector3(-1, 1, 1), Transform3D(), 0.0, sample, volume));
	CHECK(!godot_physics_fluid_box_sample_3d(Vector3(1, 1, 1),
			Transform3D(Basis::from_scale(Vector3(0, 1, 1)), Vector3()), 0.0, sample, volume));
	CHECK(!godot_physics_fluid_box_sample_3d(Vector3(1, 1, 1), Transform3D(), Math::INF, sample, volume));
}

} // namespace TestPhysicsFluidBox3D
