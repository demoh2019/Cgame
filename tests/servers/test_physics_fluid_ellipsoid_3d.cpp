/**************************************************************************/
/*  test_physics_fluid_ellipsoid_3d.cpp                                   */
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

#include "servers/physics_fluid_ellipsoid_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fluid_ellipsoid_3d)

namespace TestPhysicsFluidEllipsoid3D {

TEST_CASE("[PhysicsEllipsoid] Identity transform is the exact spherical cap") {
	GodotPhysicsFluidSample3D sample;
	real_t total_volume = 0.0;
	const Transform3D identity;
	REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(identity, 1.0, 0.0, sample, total_volume));
	CHECK(total_volume == doctest::Approx(real_t(4.0 / 3.0) * Math::PI).epsilon(1e-5));
	CHECK(sample.submerged_fraction == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(sample.submerged_volume == doctest::Approx(total_volume * 0.5).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.is_equal_approx(Vector3(0, real_t(-3.0 / 8.0), 0)));
	const GodotPhysicsFluidSample3D original = godot_physics_fluid_sphere_sample_3d(
			Vector3(), 1.0, total_volume, 0.0);
	CHECK(sample.center_of_buoyancy.is_equal_approx(original.center_of_buoyancy));
}

TEST_CASE("[PhysicsEllipsoid] Axis aligned nonuniform scale has exact volume and buoyancy") {
	const Transform3D transform(Basis::from_scale(Vector3(2, 1, real_t(0.5))), Vector3(2, 0, -3));
	GodotPhysicsFluidSample3D sample;
	real_t total_volume = 0.0;
	REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			transform, 1.0, 0.0, sample, total_volume));
	CHECK(total_volume == doctest::Approx(real_t(4.0 / 3.0) * Math::PI).epsilon(1e-5));
	CHECK(sample.submerged_fraction == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.is_equal_approx(Vector3(2, real_t(-0.375), -3)));
}

TEST_CASE("[PhysicsEllipsoid] Rotated nonuniform ellipsoid generates lateral restoring torque") {
	const Basis rotation(Vector3(0, 0, 1), real_t(Math::PI / 4.0));
	const Basis scale = Basis::from_scale(Vector3(2, 1, 1));
	const Transform3D transform(rotation * scale, Vector3(5, 0, -1));
	GodotPhysicsFluidSample3D sample;
	real_t total_volume = 0.0;
	REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			transform, 1.0, 0.0, sample, total_volume));
	CHECK(total_volume == doctest::Approx(real_t(8.0 / 3.0) * Math::PI).epsilon(1e-5));
	CHECK(sample.submerged_fraction == doctest::Approx(0.5).epsilon(1e-5));
	// B*B^T has xy = 1.5, yy = 2.5: center shifts in -X and -Y.
	const real_t expected_y = -real_t(3.0 / 8.0) * Math::sqrt(real_t(2.5));
	const real_t expected_x = expected_y * real_t(1.5 / 2.5);
	CHECK(sample.center_of_buoyancy.x == doctest::Approx(5.0 + expected_x).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.y == doctest::Approx(expected_y).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.z == doctest::Approx(-1.0).epsilon(1e-5));
	CHECK((sample.center_of_buoyancy - transform.origin).cross(Vector3(0, 1, 0)).z < 0.0);
}

TEST_CASE("[PhysicsEllipsoid] Affine shear contributes exactly to lateral buoyancy center") {
	// x_world = x_local + 0.8*y_local, y_world = y_local.
	const Basis shear(Vector3(1, 0, 0), Vector3(real_t(0.8), 1, 0), Vector3(0, 0, 1));
	const Transform3D transform(shear, Vector3());
	GodotPhysicsFluidSample3D sample;
	real_t total_volume = 0.0;
	REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			transform, 1.0, 0.0, sample, total_volume));
	CHECK(total_volume == doctest::Approx(real_t(4.0 / 3.0) * Math::PI).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.x == doctest::Approx(-0.3).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.y == doctest::Approx(-0.375).epsilon(1e-5));
}

TEST_CASE("[PhysicsEllipsoid] Reflected basis still displaces positive volume") {
	const Transform3D mirrored(Basis::from_scale(Vector3(-2, 1, 1)), Vector3());
	GodotPhysicsFluidSample3D sample;
	real_t total_volume = 0.0;
	REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			mirrored, 1.0, 0.0, sample, total_volume));
	CHECK(total_volume == doctest::Approx(real_t(8.0 / 3.0) * Math::PI).epsilon(1e-5));
	CHECK(sample.submerged_volume == doctest::Approx(total_volume * 0.5).epsilon(1e-5));
	CHECK(sample.center_of_buoyancy.y == doctest::Approx(-0.375).epsilon(1e-5));
}

TEST_CASE("[PhysicsEllipsoid] Wet and dry complement preserve total centroid") {
	const Basis rotation(Vector3(0, 0, 1), real_t(0.35));
	const Transform3D transform(rotation * Basis::from_scale(Vector3(2, 1, 1)), Vector3(3, 0, 8));
	for (real_t height : { real_t(-0.6), real_t(-0.2), real_t(0.0), real_t(0.7), real_t(1.25) }) {
		GodotPhysicsFluidSample3D positive, negative;
		real_t full0 = 0.0, full1 = 0.0;
		REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
				transform, 1.0, height, positive, full0));
		REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
				transform, 1.0, -height, negative, full1));
		CHECK(positive.submerged_fraction + negative.submerged_fraction ==
				doctest::Approx(1.0).epsilon(1e-5));
		const Vector3 moment =
				(positive.center_of_buoyancy - transform.origin) * positive.submerged_fraction -
				(negative.center_of_buoyancy - transform.origin) * negative.submerged_fraction;
		CHECK(moment.length() < real_t(1e-4));
	}
}

TEST_CASE("[PhysicsEllipsoid] Dry full and translated ellipsoids have stable outcomes") {
	const Transform3D transform(Basis::from_scale(Vector3(2, 3, 1)), Vector3(300, 80, -700));
	GodotPhysicsFluidSample3D dry, full, half;
	real_t dry_total = 0.0, full_total = 0.0, half_total = 0.0;
	REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			transform, 1.0, 75.0, dry, dry_total));
	REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			transform, 1.0, 85.0, full, full_total));
	REQUIRE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			transform, 1.0, 80.0, half, half_total));
	CHECK(dry.submerged_volume == 0.0);
	CHECK(full.submerged_fraction == 1.0);
	CHECK(full.center_of_buoyancy == transform.origin);
	CHECK(half.submerged_fraction == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(half.center_of_buoyancy.y == doctest::Approx(real_t(80.0 - 1.125)).epsilon(1e-5));
	CHECK(dry_total == full_total);
	CHECK(full_total == half_total);
}

TEST_CASE("[PhysicsEllipsoid] Degenerate and nonfinite affine transforms fail atomically") {
	GodotPhysicsFluidSample3D sample;
	real_t total_volume = 777.0;
	const Transform3D zero(Basis::from_scale(Vector3(1, 0, 1)), Vector3());
	CHECK_FALSE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			zero, 1.0, 0.0, sample, total_volume));
	CHECK(total_volume == 0.0);
	const Transform3D identity;
	CHECK_FALSE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			identity, -1.0, 0.0, sample, total_volume));
	CHECK_FALSE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			identity, 1.0, std::numeric_limits<real_t>::infinity(), sample, total_volume));
	CHECK_FALSE(godot_physics_fluid_affine_ellipsoid_sample_3d(
			identity, 0.0, 0.0, sample, total_volume));
	CHECK(sample.submerged_volume == 0.0);
	CHECK(total_volume == 0.0);
}

} // namespace TestPhysicsFluidEllipsoid3D
