/**************************************************************************/
/*  test_physics_fem_tetra_volume_plasticity.cpp                          */
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

#include "servers/physics_fem_tetra_volume_plasticity.h"
#include "servers/physics_fem_tetra_mooney_rivlin.h"
#include "tests/test_macros.h"

#include <cmath>
#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_volume_plasticity)

namespace TestPhysicsFEMTetraVolumePlasticity {

static bool unit_rest(PhysicsFEMTetraRest &r_rest) {
	return physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), r_rest);
}

TEST_CASE("[PhysicsFEM] Plastic expansion changes local rest volume and restores relaxed Neo-Hookean energy") {
	PhysicsFEMTetraRest rest;
	REQUIRE(unit_rest(rest));
	double scale = 1.0;
	const real_t t = real_t(1.1);
	CHECK(physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(t, 0, 0),
			Vector3(0, t, 0), Vector3(0, 0, t), 0, 1, rest, scale));
	CHECK(scale == doctest::Approx(1.331).epsilon(1e-5));
	CHECK(rest.volume == doctest::Approx(1.331 / 6.0).epsilon(1e-5));
	CHECK(rest.signed_det == doctest::Approx(1.331).epsilon(1e-5));
	CHECK(rest.inv_dm[0][0] == doctest::Approx(1.0 / 1.1).epsilon(1e-5));
	double energy = -1.0;
	Vector3 ga, gb, gc, gd;
	REQUIRE(physics_fem_tetra_energy_gradient(Vector3(), Vector3(t, 0, 0),
			Vector3(0, t, 0), Vector3(0, 0, t), rest, .3,
			energy, ga, gb, gc, gd));
	CHECK(energy < 1e-5);
}

TEST_CASE("[PhysicsFEM] Plastic compression and negative rest winding are supported") {
	PhysicsFEMTetraRest rest;
	REQUIRE(unit_rest(rest));
	double scale = 1.0;
	const real_t t = real_t(0.8);
	CHECK(physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(t, 0, 0),
			Vector3(0, t, 0), Vector3(0, 0, t), 0, 1, rest, scale));
	CHECK(scale == doctest::Approx(0.512).epsilon(1e-5));
	CHECK(rest.signed_det == doctest::Approx(0.512).epsilon(1e-5));
	REQUIRE(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, -1), rest));
	scale = 1.0;
	CHECK(physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(t, 0, 0),
			Vector3(0, t, 0), Vector3(0, 0, -t), 0, 1, rest, scale));
	CHECK(scale == doctest::Approx(0.512).epsilon(1e-5));
	CHECK(rest.signed_det == doctest::Approx(-0.512).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Subyield strain and rigid movement never cause rest creep") {
	PhysicsFEMTetraRest rest;
	REQUIRE(unit_rest(rest));
	double scale = 1.0;
	CHECK_FALSE(physics_fem_tetra_creep_volume_rest(Vector3(20, 30, -7),
			Vector3(20, 31, -7), Vector3(19, 30, -7),
			Vector3(20, 30, -6), .1, 1, rest, scale));
	CHECK_FALSE(physics_fem_tetra_creep_volume_rest(Vector3(),
			Vector3(real_t(1.05), 0, 0), Vector3(0, real_t(1.05), 0),
			Vector3(0, 0, real_t(1.05)), real_t(.2), 1, rest, scale));
	CHECK(scale == doctest::Approx(1.0));
	CHECK(rest.volume == doctest::Approx(1.0 / 6.0));
}

TEST_CASE("[PhysicsFEM] Yield boundary remains elastic after accumulated plastic expansion") {
	PhysicsFEMTetraRest rest;
	REQUIRE(unit_rest(rest));
	double plastic = 1.0;
	const real_t t = real_t(1.3);
	CHECK(physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(t, 0, 0),
			Vector3(0, t, 0), Vector3(0, 0, t), real_t(.2), 1, rest, plastic));
	CHECK(plastic == doctest::Approx(2.197 / std::exp(.2)).epsilon(1e-5));
	const double current_det = double(t) * double(t) * double(t);
	CHECK(current_det / rest.signed_det == doctest::Approx(std::exp(.2)).epsilon(1e-5));
	CHECK_FALSE(physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(t, 0, 0),
			Vector3(0, t, 0), Vector3(0, 0, t), real_t(.2), 1, rest, plastic));
}

TEST_CASE("[PhysicsFEM] Exponential relaxation agrees across fixed-time subdivisions") {
	PhysicsFEMTetraRest full_rest, half_rest;
	REQUIRE(unit_rest(full_rest));
	REQUIRE(unit_rest(half_rest));
	double full = 1.0, half = 1.0;
	const double fraction = 1.0 - std::exp(-2.0 * .2);
	const double half_fraction = 1.0 - std::exp(-2.0 * .1);
	const Vector3 a, b(real_t(1.3), 0, 0), c(0, real_t(1.3), 0), d(0, 0, real_t(1.3));
	CHECK(physics_fem_tetra_creep_volume_rest(a, b, c, d, real_t(.1),
			fraction, full_rest, full));
	CHECK(physics_fem_tetra_creep_volume_rest(a, b, c, d, real_t(.1),
			half_fraction, half_rest, half));
	CHECK(physics_fem_tetra_creep_volume_rest(a, b, c, d, real_t(.1),
			half_fraction, half_rest, half));
	CHECK(half == doctest::Approx(full).epsilon(1e-6));
	CHECK(half_rest.inv_dm[0][0] == doctest::Approx(full_rest.inv_dm[0][0]).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEM] Accumulated plastic scaling saturates without zero or infinite rest") {
	PhysicsFEMTetraRest rest;
	REQUIRE(unit_rest(rest));
	double plastic = 1.0;
	CHECK(physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(100, 0, 0),
			Vector3(0, 100, 0), Vector3(0, 0, 100), 0, 1, rest, plastic));
	CHECK(plastic == doctest::Approx(5.0));
	CHECK(rest.volume == doctest::Approx(5.0 / 6.0));
	PhysicsFEMTetraRest compressed;
	REQUIRE(unit_rest(compressed));
	double compressed_scale = 1.0;
	CHECK(physics_fem_tetra_creep_volume_rest(Vector3(),
			Vector3(real_t(.01), 0, 0), Vector3(0, real_t(.01), 0),
			Vector3(0, 0, real_t(.01)), 0, 1, compressed, compressed_scale));
	CHECK(compressed_scale == doctest::Approx(.2));
	CHECK(compressed.volume == doctest::Approx(.2 / 6.0));
}

TEST_CASE("[PhysicsFEM] Invalid, inverted and nonfinite geometry does not modify rest state") {
	PhysicsFEMTetraRest rest;
	REQUIRE(unit_rest(rest));
	double plastic = 1.0;
	CHECK_FALSE(physics_fem_tetra_creep_volume_rest(Vector3(),
			Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1),
			0, 1, rest, plastic));
	CHECK_FALSE(physics_fem_tetra_creep_volume_rest(Vector3(),
			Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 0),
			0, 1, rest, plastic));
	CHECK_FALSE(physics_fem_tetra_creep_volume_rest(Vector3(),
			Vector3(2, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 2),
			0, 0, rest, plastic));
	CHECK_FALSE(physics_fem_tetra_creep_volume_rest(Vector3(),
			Vector3(2, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 2),
			0, std::numeric_limits<double>::quiet_NaN(), rest, plastic));
	CHECK(rest.volume == doctest::Approx(1.0 / 6.0));
	CHECK(rest.signed_det == doctest::Approx(1.0));
	CHECK(rest.inv_dm[0][0] == doctest::Approx(1.0));
	CHECK(plastic == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsFEM] Plastic deformation remains local to individual tetrahedra") {
	PhysicsFEMTetraRest a, b;
	REQUIRE(unit_rest(a));
	REQUIRE(unit_rest(b));
	double s_a = 1.0, s_b = 1.0;
	CHECK(physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(real_t(1.2), 0, 0),
			Vector3(0, real_t(1.2), 0), Vector3(0, 0, real_t(1.2)),
			real_t(.1), .5, a, s_a));
	CHECK_FALSE(physics_fem_tetra_creep_volume_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), real_t(.1), .5, b, s_b));
	CHECK(s_a > 1.0);
	CHECK(s_b == doctest::Approx(1.0));
	CHECK(b.volume == doctest::Approx(1.0 / 6.0));
}

} // namespace TestPhysicsFEMTetraVolumePlasticity
