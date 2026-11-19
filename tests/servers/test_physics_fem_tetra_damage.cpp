/**************************************************************************/
/*  test_physics_fem_tetra_damage.cpp                                    */
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

#include "servers/physics_fem_tetra_damage.h"
#include "servers/physics_fem_tetra_neo_hookean.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_damage)

namespace TestPhysicsFEMTetraDamage {

TEST_CASE("[PhysicsFEM] Undamaged elastic range leaves material unchanged") {
	double damage = 0.0;
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(0.05, 0.1, 2.0, 0.5, damage));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(0.1, 0.1, 2.0, 0.5, damage));
	CHECK(damage == doctest::Approx(0.0));
	CHECK(physics_fem_tetra_damage_alpha(1e-5, damage) == 1e-5);
}

TEST_CASE("[PhysicsFEM] Energy overload causes irreversible but bounded local softening") {
	double damage = 0.0;
	CHECK(physics_fem_tetra_accumulate_damage(0.3, 0.1, 2.0, 0.1, damage));
	CHECK(damage == doctest::Approx(1.0 - Math::exp(-0.4)).epsilon(1e-9));
	const double first = damage;
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(0.03, 0.1, 2.0, 0.1, damage));
	CHECK(damage == first);
	CHECK(physics_fem_tetra_damage_alpha(0.01, damage) > 0.01);
}

TEST_CASE("[PhysicsFEM] Rate-dependent damage is consistent across fixed-load substeps") {
	double full = 0.0, half = 0.0;
	CHECK(physics_fem_tetra_accumulate_damage(0.2, 0.1, 2.0, 0.1, full));
	CHECK(physics_fem_tetra_accumulate_damage(0.2, 0.1, 2.0, 0.05, half));
	CHECK(physics_fem_tetra_accumulate_damage(0.2, 0.1, 2.0, 0.05, half));
	CHECK(half == doctest::Approx(full).epsilon(1e-12));
}

TEST_CASE("[PhysicsFEM] Extreme loading cannot eliminate residual stiffness") {
	double damage = 0.0;
	CHECK(physics_fem_tetra_accumulate_damage(1e200, 1e-10, 1000.0, 2.0, damage));
	CHECK(damage == doctest::Approx(0.95));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(1e200, 1e-10, 1000.0, 2.0, damage));
	CHECK(physics_fem_tetra_damage_alpha(0.001, damage) == doctest::Approx(0.02));
	CHECK(Math::is_finite(physics_fem_tetra_damage_alpha(
			std::numeric_limits<double>::max(), damage)));
}

TEST_CASE("[PhysicsFEM] Numerical corruption is rejected without changing damage") {
	const double inf = std::numeric_limits<double>::infinity();
	const double nan = std::numeric_limits<double>::quiet_NaN();
	double damage = 0.25;
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(nan, 0.1, 2, .1, damage));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(inf, 0.1, 2, .1, damage));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(-1, 0.1, 2, .1, damage));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(1, 0.0, 2, .1, damage));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(1, 0.1, 0, .1, damage));
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(1, 0.1, 2, 0, damage));
	CHECK(damage == doctest::Approx(0.25));
}

TEST_CASE("[PhysicsFEM] Actual Neo-Hookean tetrahedra yield only under deformation") {
	const Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, 1);
	PhysicsFEMTetraRest rest;
	REQUIRE(physics_fem_tetra_make_rest(a, b, c, d, rest));
	double energy = -1;
	Vector3 ga, gb, gc, gd;
	REQUIRE(physics_fem_tetra_energy_gradient(a, b, c, d, rest, 0.3, energy, ga, gb, gc, gd));
	CHECK(energy == doctest::Approx(0.0).epsilon(1e-5));
	double damage = 0.0;
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(energy / rest.volume, 0.05, 4.0, 0.1, damage));

	// Rigid 90-degree rotation of the rest tetrahedron has no strain.
	REQUIRE(physics_fem_tetra_energy_gradient(a, Vector3(0, 1, 0),
			Vector3(-1, 0, 0), d, rest, 0.3, energy, ga, gb, gc, gd));
	CHECK(energy < 1e-7);
	CHECK_FALSE(physics_fem_tetra_accumulate_damage(energy / rest.volume, 0.05, 4.0, 0.1, damage));

	REQUIRE(physics_fem_tetra_energy_gradient(a, Vector3(real_t(1.5), 0, 0),
			c, d, rest, 0.3, energy, ga, gb, gc, gd));
	CHECK(energy > 0.0);
	CHECK(physics_fem_tetra_accumulate_damage(energy / rest.volume, 0.05, 4.0, 0.1, damage));
	CHECK(damage > 0.0);
}

} // namespace TestPhysicsFEMTetraDamage
