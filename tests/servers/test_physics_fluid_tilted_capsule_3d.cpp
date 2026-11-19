/**************************************************************************/
/*  test_physics_fluid_tilted_capsule_3d.cpp                               */
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
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#include "servers/physics_fluid_capsule_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fluid_tilted_capsule_3d)

namespace TestPhysicsFluidTiltedCapsule3D {

static const real_t volume = real_t(10.0 / 3.0) * Math::PI; // r=1, H=4, L=2

TEST_CASE("[PhysicsTiltedCapsule] Half-submerged horizontal capsule has correct moment") {
	GodotPhysicsFluidSample3D sample;
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(5, 0, -2), Vector3(1, 0, 0), 1.0, 4.0, volume, 0.0, sample));
	CHECK(sample.submerged_fraction == doctest::Approx(0.5).epsilon(1e-4));
	// Half-cylinder moment is -2 L r^3 / 3 and half-sphere moment
	// is -pi r^4 / 4. Divide by their combined half-submerged volume.
	const real_t expected = -(real_t(4.0 / 3.0) + Math::PI / real_t(4.0)) /
			(real_t(5.0) * Math::PI / real_t(3.0));
	CHECK(sample.center_of_buoyancy.x == doctest::Approx(5.0).epsilon(1e-4));
	CHECK(sample.center_of_buoyancy.y == doctest::Approx(expected).epsilon(2e-4));
	CHECK(sample.center_of_buoyancy.z == doctest::Approx(-2.0).epsilon(1e-4));
}

TEST_CASE("[PhysicsTiltedCapsule] Oblique half-submerged capsule restores lateral torque") {
	GodotPhysicsFluidSample3D sample;
	const Vector3 axis = Vector3(1, 1, 0).normalized();
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(), axis, 1.0, 4.0, volume, 0.0, sample));
	CHECK(sample.submerged_fraction == doctest::Approx(0.5).epsilon(1e-4));
	CHECK(sample.center_of_buoyancy.x < real_t(-0.3));
	CHECK(sample.center_of_buoyancy.y < real_t(-0.5));
	CHECK(Math::abs(sample.center_of_buoyancy.z) < real_t(1e-5));
}

TEST_CASE("[PhysicsTiltedCapsule] Complementary waterlines conserve displaced volume and moment") {
	const Vector3 axis = Vector3(0.8, 0.6, 0).normalized();
	for (real_t height : { real_t(-1.1), real_t(-0.5), real_t(0.0), real_t(0.75), real_t(1.3) }) {
		GodotPhysicsFluidSample3D lower;
		GodotPhysicsFluidSample3D mirrored;
		REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
				Vector3(), axis, 1.0, 4.0, volume, height, lower));
		REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
				Vector3(), axis, 1.0, 4.0, volume, -height, mirrored));
		CHECK(lower.submerged_fraction + mirrored.submerged_fraction ==
				doctest::Approx(1.0).epsilon(1e-4));
		const Vector3 conservation =
				lower.center_of_buoyancy * lower.submerged_fraction -
				mirrored.center_of_buoyancy * mirrored.submerged_fraction;
		CHECK(conservation.length() < real_t(2e-3));
	}
}

TEST_CASE("[PhysicsTiltedCapsule] Axis inversion and full-submersion identity") {
	const Vector3 axis = Vector3(0.6, 0.8, 0);
	GodotPhysicsFluidSample3D first, reversed;
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(5, 0, -8), axis, 1.0, 4.0, volume, -0.3, first));
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(5, 0, -8), -axis, 1.0, 4.0, volume, -0.3, reversed));
	CHECK(first.submerged_fraction == doctest::Approx(reversed.submerged_fraction).epsilon(1e-4));
	CHECK((first.center_of_buoyancy - reversed.center_of_buoyancy).length() < real_t(2e-3));

	GodotPhysicsFluidSample3D dry, full;
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(5, 0, -8), axis, 1.0, 4.0, volume, -10, dry));
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(5, 0, -8), axis, 1.0, 4.0, volume, 10, full));
	CHECK(dry.submerged_volume == 0.0);
	CHECK(full.submerged_volume == volume);
	CHECK(full.center_of_buoyancy == Vector3(5, 0, -8));
}

TEST_CASE("[PhysicsTiltedCapsule] Vertical limit matches exact analytic capsule") {
	GodotPhysicsFluidSample3D sample;
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(1, 0, 2), Vector3(0, 1, 0), 1.0, 4.0, volume, 0.0, sample));
	const GodotPhysicsFluidSample3D exact = godot_physics_fluid_vertical_capsule_sample_3d(
			Vector3(1, 0, 2), 1.0, 4.0, volume, 0.0);
	CHECK(Math::is_equal_approx(sample.submerged_fraction, exact.submerged_fraction));
	CHECK(Math::is_equal_approx(sample.center_of_buoyancy.y, exact.center_of_buoyancy.y));

	GodotPhysicsFluidSample3D sphere;
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(), Vector3(1, 0, 0), 1.0, 2.0,
			Math::PI * real_t(4.0 / 3.0), -0.5, sphere));
	CHECK(sphere.submerged_fraction == doctest::Approx(0.15625).epsilon(1e-5));
}

TEST_CASE("[PhysicsTiltedCapsule] Very long capsules have bounded integration error") {
	GodotPhysicsFluidSample3D sample;
	const Vector3 axis = Vector3(0.1, 0.995, 0).normalized();
	REQUIRE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(), axis, 1.0, 1002.0,
			Math::PI * real_t(1000.0 + 4.0 / 3.0), -400, sample));
	CHECK(sample.submerged_fraction > real_t(0.09));
	CHECK(sample.submerged_fraction < real_t(0.11));
	CHECK(sample.center_of_buoyancy.is_finite());
	CHECK(sample.center_of_buoyancy.y < real_t(-400.0));
}

TEST_CASE("[PhysicsTiltedCapsule] Reject nonfinite geometry without partial results") {
	GodotPhysicsFluidSample3D sample;
	const real_t infinity = std::numeric_limits<real_t>::infinity();
	CHECK_FALSE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(), Vector3(0, 0, 0), 1.0, 4.0, volume, 0.0, sample));
	CHECK_FALSE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(), Vector3(1, 0, 0), -1.0, 4.0, volume, 0.0, sample));
	CHECK_FALSE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(), Vector3(1, 0, 0), 1.0, 1.0, volume, 0.0, sample));
	CHECK_FALSE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(), Vector3(1, 0, 0), 1.0, 4.0, infinity, 0.0, sample));
	CHECK_FALSE(godot_physics_fluid_tilted_capsule_sample_3d(
			Vector3(), Vector3(1, 0, 0), 1.0, 4.0, volume, infinity, sample));
	CHECK(sample.submerged_volume == 0.0);
}

} // namespace TestPhysicsFluidTiltedCapsule3D
