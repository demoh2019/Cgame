/**************************************************************************/
/*  test_physics_fem_tetra_damage.cpp                                     */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER ARISING FROM, OUT OF OR IN */
/* CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/**************************************************************************/

#include "servers/physics_fem_tetra_damage.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_damage)

namespace TestPhysicsFEMTetraDamage {

static PhysicsFEMTetraRest rest() {
	PhysicsFEMTetraRest result;
	physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), result);
	return result;
}

TEST_CASE("[PhysicsFEMDamage] Undeformed tetra has zero objective strain") {
	double strain = -1.0;
	REQUIRE(physics_fem_tetra_damage_strain(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest(), strain));
	CHECK(strain == doctest::Approx(0.0).epsilon(1e-10));
}

TEST_CASE("[PhysicsFEMDamage] Rigid 90 degree rotation and translation cause no damage") {
	double strain = -1.0;
	const Vector3 center(25, -15, 7);
	REQUIRE(physics_fem_tetra_damage_strain(center,
			center + Vector3(0, 1, 0), center + Vector3(-1, 0, 0),
			center + Vector3(0, 0, 1), rest(), strain));
	CHECK(strain == doctest::Approx(0.0).epsilon(1e-10));
	real_t damage = real_t(0.0);
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(
			strain, 0.1, 100.0, 0.02, 0.8, damage));
	CHECK(damage == real_t(0.0));
}

TEST_CASE("[PhysicsFEMDamage] Stretch, compression and shear trigger finite objective strain") {
	const PhysicsFEMTetraRest r = rest();
	double stretch = 0.0, compressed = 0.0, shear = 0.0;
	REQUIRE(physics_fem_tetra_damage_strain(Vector3(),
			Vector3(1.5, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), r, stretch));
	REQUIRE(physics_fem_tetra_damage_strain(Vector3(),
			Vector3(0.7, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), r, compressed));
	REQUIRE(physics_fem_tetra_damage_strain(Vector3(),
			Vector3(1, 0, 0), Vector3(0.6, 1, 0), Vector3(0, 0, 1), r, shear));
	CHECK(stretch == doctest::Approx(Math::sqrt(2.0 / 3.0) * 0.625).epsilon(1e-8));
	CHECK(compressed > 0.0);
	CHECK(shear > 0.0);
	CHECK(Math::is_finite(shear));
}

TEST_CASE("[PhysicsFEMDamage] Creep accumulates irreversibly and never crosses cap") {
	real_t damage = real_t(0.0);
	for (int tick = 0; tick < 500; ++tick) {
		physics_fem_tetra_accumulate_damage(0.5, 0.1, 5.0, 0.016, 0.8, damage);
		CHECK(damage >= real_t(0.0));
		CHECK(damage <= real_t(0.8));
	}
	CHECK(damage > real_t(0.70));
	CHECK(damage <= real_t(0.8));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(
			0.0, 0.1, 10.0, 0.016, 0.8, damage));
}

TEST_CASE("[PhysicsFEMDamage] Rate is nearly invariant to timestep subdivision") {
	real_t single = 0.0;
	real_t many = 0.0;
	REQUIRE(physics_fem_tetra_accumulate_damage(0.6, 0.2, 3.0, 1.0, 0.8, single));
	for (int i = 0; i < 100; ++i) {
		physics_fem_tetra_accumulate_damage(0.6, 0.2, 3.0, 0.01, 0.8, many);
	}
	CHECK(single == doctest::Approx(many).epsilon(0.01));
}

TEST_CASE("[PhysicsFEMDamage] Increased XPBD compliance models softer material") {
	double alpha = -1.0;
	REQUIRE(physics_fem_tetra_damage_alpha(0.002, 0.0, alpha));
	CHECK(alpha == doctest::Approx(0.002));
	REQUIRE(physics_fem_tetra_damage_alpha(0.002, 0.5, alpha));
	CHECK(alpha == doctest::Approx(0.004));
	REQUIRE(physics_fem_tetra_damage_alpha(0.002, 0.8, alpha));
	CHECK(alpha == doctest::Approx(0.01).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEMDamage] Inverted geometry and invalid parameters are transactional") {
	double unchanged = 123.0;
	const PhysicsFEMTetraRest r = rest();
	CHECK_FALSE(physics_fem_tetra_damage_strain(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, -1), r, unchanged));
	CHECK_FALSE(physics_fem_tetra_damage_strain(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 1, 0), r, unchanged));
	CHECK_FALSE(physics_fem_tetra_damage_strain(
			Vector3(std::numeric_limits<real_t>::infinity(), 0, 0),
			Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), r, unchanged));
	CHECK(unchanged == doctest::Approx(123.0));
	real_t damage = 0.2;
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(
			std::numeric_limits<double>::infinity(), 0.1, 2., .02, 0.8, damage));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(0.5, 0.1, -1., .02, 0.8, damage));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(0.5, 0.1, 1., .02, 1.0, damage));
	CHECK(damage == doctest::Approx(0.2));
	double result_alpha = 123.0;
	CHECK_FALSE(physics_fem_tetra_damage_alpha(
			0.001, std::numeric_limits<real_t>::infinity(), result_alpha));
	CHECK(result_alpha == doctest::Approx(123.0));
}

TEST_CASE("[PhysicsFEMDamage] Uniform scale change preserves equivalent strain") {
	const real_t scales[] = { real_t(1e-4), real_t(1), real_t(1e4) };
	for (const real_t scale : scales) {
		PhysicsFEMTetraRest r;
		REQUIRE(physics_fem_tetra_make_rest(Vector3(),
				Vector3(scale, 0, 0), Vector3(0, scale, 0),
				Vector3(0, 0, scale), r));
		double strain;
		REQUIRE(physics_fem_tetra_damage_strain(Vector3(),
				Vector3(scale * real_t(1.2), 0, 0),
				Vector3(0, scale, 0), Vector3(0, 0, scale), r, strain));
		CHECK(strain == doctest::Approx(Math::sqrt(2.0 / 3.0) * 0.22).epsilon(1e-5));
	}
}

} // namespace TestPhysicsFEMTetraDamage
