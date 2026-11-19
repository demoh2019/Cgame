/**************************************************************************/
/*  test_physics_fluid_cylinder_3d.cpp                                    */
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

#include "servers/physics_fluid_cylinder_3d.h"
#include "tests/test_macros.h"

#include <initializer_list>
#include <limits>

TEST_FORCE_LINK(test_physics_fluid_cylinder_3d)

namespace TestPhysicsFluidCylinder3D {

TEST_CASE("[PhysicsCylinderFluid] Upright cylinder has exact clipped volume and axial centroid") {
	const Vector3 center(2, 0, -3);
	const Vector3 axis(0, 1, 0);
	GodotPhysicsFluidSample3D sample;
	real_t volume = 0.0;
	REQUIRE(godot_physics_fluid_cylinder_sample_3d(center, axis,
			1.0, 4.0, -1.0, sample, volume));
	CHECK(volume == doctest::Approx(real_t(4.0) * Math::PI).epsilon(1e-5));
	CHECK(sample.submerged_fraction == doctest::Approx(0.25).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.is_equal_approx(Vector3(2, -1.5, -3)));

	GodotPhysicsFluidSample3D half;
	real_t total = 0.0;
	REQUIRE(godot_physics_fluid_cylinder_sample_3d(center, axis,
			1.0, 4.0, 0.0, half, total));
	CHECK(half.submerged_fraction == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(half.center_of_buoyancy.is_equal_approx(Vector3(2, -1, -3)));
}

TEST_CASE("[PhysicsCylinderFluid] Horizontal cylinder has exact circular-segment first moment") {
	const Vector3 center(5, 0, -2);
	GodotPhysicsFluidSample3D sample;
	real_t full_volume = 0.0;
	REQUIRE(godot_physics_fluid_cylinder_sample_3d(center, Vector3(1, 0, 0),
			1.0, 4.0, 0.0, sample, full_volume));
	CHECK(full_volume == doctest::Approx(real_t(4.0) * Math::PI).epsilon(1e-5));
	CHECK(sample.submerged_fraction == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.x == doctest::Approx(5.0).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.y == doctest::Approx(
			-real_t(4.0) / (real_t(3.0) * Math::PI)).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.z == doctest::Approx(-2.0).epsilon(1e-5));
	CHECK(Math::abs(sample.center_of_buoyancy.y + real_t(0.5)) > real_t(0.07));
}

TEST_CASE("[PhysicsCylinderFluid] Arbitrary tilt shifts center laterally and creates torque") {
	const Vector3 axis = Vector3(1, 1, 0).normalized();
	GodotPhysicsFluidSample3D sample;
	real_t volume = 0.0;
	REQUIRE(godot_physics_fluid_cylinder_sample_3d(
			Vector3(), axis, 1.0, 4.0, 0.0, sample, volume));
	CHECK(sample.submerged_fraction == doctest::Approx(0.5).epsilon(2e-5));
	CHECK(sample.center_of_buoyancy.x < real_t(-0.3));
	CHECK(sample.center_of_buoyancy.y < real_t(-0.5));
	CHECK(Math::abs(sample.center_of_buoyancy.z) < real_t(1e-5));
	// Upward buoyancy at negative x produces a negative torque around Z.
	CHECK(sample.center_of_buoyancy.cross(Vector3(0, 1, 0)).z < 0.0);
}

TEST_CASE("[PhysicsCylinderFluid] Reversing cylinder axis does not change its physics") {
	const Vector3 axis = Vector3(0.8, 0.6, 0);
	for (real_t waterline : { real_t(-0.8), real_t(0.0), real_t(1.1) }) {
		GodotPhysicsFluidSample3D a, b;
		real_t volume_a = 0.0, volume_b = 0.0;
		REQUIRE(godot_physics_fluid_cylinder_sample_3d(
				Vector3(2, 0, 7), axis, 1.0, 4.0, waterline, a, volume_a));
		REQUIRE(godot_physics_fluid_cylinder_sample_3d(
				Vector3(2, 0, 7), -axis, 1.0, 4.0, waterline, b, volume_b));
		CHECK(a.submerged_fraction == doctest::Approx(b.submerged_fraction).epsilon(1e-5));
		CHECK((a.center_of_buoyancy - b.center_of_buoyancy).length() < real_t(0.0001));
	}
}

TEST_CASE("[PhysicsCylinderFluid] Complementary waterlines conserve displaced volume and centroid") {
	const Vector3 center(0, 0, 0);
	const Vector3 axis = Vector3(0.6, 0.8, 0);
	for (real_t h : { real_t(-1.3), real_t(-0.5), real_t(0.0), real_t(0.35), real_t(1.1) }) {
		GodotPhysicsFluidSample3D a, b;
		real_t total_a = 0.0, total_b = 0.0;
		REQUIRE(godot_physics_fluid_cylinder_sample_3d(center, axis, 1.0, 4.0, h, a, total_a));
		REQUIRE(godot_physics_fluid_cylinder_sample_3d(center, axis, 1.0, 4.0, -h, b, total_b));
		CHECK(total_a == doctest::Approx(total_b).epsilon(1e-6));
		CHECK(a.submerged_fraction + b.submerged_fraction == doctest::Approx(1.0).epsilon(2e-5));
		const Vector3 moment_balance =
				a.center_of_buoyancy * a.submerged_fraction -
				b.center_of_buoyancy * b.submerged_fraction;
		CHECK(moment_balance.length() < real_t(0.0002));
	}
}

TEST_CASE("[PhysicsCylinderFluid] Full, dry, reflected and scaled geometry remain bounded") {
	const Vector3 center(3, 0, 9);
	const Vector3 axis(0, -2, 0); // A reflected orientation is equivalent.
	GodotPhysicsFluidSample3D dry, full;
	real_t volume_dry = 0.0, volume_full = 0.0;
	REQUIRE(godot_physics_fluid_cylinder_sample_3d(
			center, axis, 2.0, 8.0, -5.0, dry, volume_dry));
	REQUIRE(godot_physics_fluid_cylinder_sample_3d(
			center, axis, 2.0, 8.0, 5.0, full, volume_full));
	CHECK(volume_full == doctest::Approx(real_t(32.0) * Math::PI).epsilon(1e-5));
	CHECK(volume_dry == volume_full);
	CHECK(dry.submerged_volume == 0.0);
	CHECK(full.submerged_volume == volume_full);
	CHECK(full.center_of_buoyancy == center);
}

TEST_CASE("[PhysicsCylinderFluid] Very long cylinder clips narrow wet band accurately") {
	const Vector3 axis = Vector3(0.01, 1.0, 0).normalized();
	GodotPhysicsFluidSample3D sample;
	real_t total = 0.0;
	REQUIRE(godot_physics_fluid_cylinder_sample_3d(
			Vector3(), axis, 1.0, 1002.0, -400.0, sample, total));
	CHECK(sample.submerged_fraction > real_t(0.09));
	CHECK(sample.submerged_fraction < real_t(0.11));
	CHECK(sample.center_of_buoyancy.y < real_t(-400.0));
	CHECK(sample.center_of_buoyancy.is_finite());
}

TEST_CASE("[PhysicsCylinderFluid] Extremely long near-horizontal cylinders preserve axial hydrostatic lever") {
	// A slope of 1e-12 seems horizontal, but a cylinder extending a
	// million radii to either side accumulates a finite first moment.
	// Simply returning zero axial moment would lose restoring torque.
	const Vector3 almost_horizontal(1, real_t(1e-12), 0);
	GodotPhysicsFluidSample3D sample;
	real_t total_volume = 0.0;
	REQUIRE(godot_physics_fluid_cylinder_sample_3d(
			Vector3(), almost_horizontal, 1.0, real_t(2e6), 0.1,
			sample, total_volume));
	CHECK(total_volume > 0.0);
	CHECK(sample.submerged_fraction > real_t(0.5));
	CHECK(sample.center_of_buoyancy.is_finite());
	CHECK(sample.center_of_buoyancy.x < real_t(-0.25));
	CHECK(sample.center_of_buoyancy.x > real_t(-0.5));
}

TEST_CASE("[PhysicsCylinderFluid] Invalid inputs fail without partial updates") {
	GodotPhysicsFluidSample3D sample;
	real_t total_volume = 15.0;
	CHECK_FALSE(godot_physics_fluid_cylinder_sample_3d(
			Vector3(), Vector3(), 1.0, 4.0, 0.0, sample, total_volume));
	CHECK(total_volume == 0.0);
	CHECK_FALSE(godot_physics_fluid_cylinder_sample_3d(
			Vector3(), Vector3(0, 1, 0), 0.0, 4.0, 0.0, sample, total_volume));
	CHECK_FALSE(godot_physics_fluid_cylinder_sample_3d(
			Vector3(), Vector3(0, 1, 0), 1.0, -4.0, 0.0, sample, total_volume));
	CHECK_FALSE(godot_physics_fluid_cylinder_sample_3d(
			Vector3(), Vector3(0, 1, 0), 1.0, 4.0,
			std::numeric_limits<real_t>::infinity(), sample, total_volume));
	CHECK(total_volume == 0.0);
	CHECK(sample.submerged_volume == 0.0);
}

} // namespace TestPhysicsFluidCylinder3D
