/**************************************************************************/
/*  test_physics_fem_tetra_deviatoric_plasticity.cpp                       */
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

#include "servers/physics_fem_tetra_deviatoric_plasticity.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_deviatoric_plasticity)

namespace TestFEMTetraDeviatoricPlasticity {

static bool rest_tetra(PhysicsFEMTetraRest &r_rest) {
	return physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), r_rest);
}

static bool measure(const Vector3 (&p)[4], const PhysicsFEMTetraRest &p_rest, double &r_value) {
	double dev[3], principal[3][3];
	return physics_fem_tetra_deviatoric_strains(p, p_rest, dev, principal, r_value);
}

TEST_CASE("[PhysicsFEM] Pure shear plastically relaxes with exact rest-volume preservation") {
	PhysicsFEMTetraRest rest;
	REQUIRE(rest_tetra(rest));
	const Vector3 points[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(real_t(0.6), 1, 0), Vector3(0, 0, 1) };
	double previous = 0.0, after = -1.0, history = 0.0;
	REQUIRE(measure(points, rest, previous));
	CHECK(previous > 0.1);
	CHECK(physics_fem_tetra_creep_deviatoric_rest(points[0], points[1],
			points[2], points[3], 0, 1, 3, rest, history));
	REQUIRE(measure(points, rest, after));
	CHECK(after < 1e-4);
	CHECK(rest.volume == doctest::Approx(1.0 / 6.0).epsilon(1e-10));
	CHECK(rest.signed_det == doctest::Approx(1.0).epsilon(1e-10));
	CHECK(history == doctest::Approx(previous).epsilon(1e-4));
	double energy = 1.0;
	Vector3 ga, gb, gc, gd;
	REQUIRE(physics_fem_tetra_energy_gradient(points[0], points[1],
			points[2], points[3], rest, 0.3, energy, ga, gb, gc, gd));
	CHECK(energy < 1e-5);
}

TEST_CASE("[PhysicsFEM] Rigid translation/rotation cannot cause deviatoric creep") {
	PhysicsFEMTetraRest rest;
	REQUIRE(rest_tetra(rest));
	double plastic = 0.0;
	const Vector3 p[4] = { Vector3(10, -5, 3), Vector3(10, -4, 3),
			Vector3(9, -5, 3), Vector3(10, -5, 4) };
	double original = -1.0;
	REQUIRE(measure(p, rest, original));
	CHECK(original == doctest::Approx(0.0).epsilon(1e-7));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(p[0], p[1],
			p[2], p[3], real_t(0.1), 1, 2, rest, plastic));
	CHECK(plastic == 0.0);
	CHECK(rest.inv_dm[0][0] == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsFEM] Uniform compression/expansion creates NO deviatoric plasticity") {
	PhysicsFEMTetraRest rest;
	REQUIRE(rest_tetra(rest));
	double plastic = 0.0;
	for (real_t s : { real_t(0.5), real_t(1.0), real_t(2.0) }) {
		CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(Vector3(),
				Vector3(s, 0, 0), Vector3(0, s, 0), Vector3(0, 0, s),
				real_t(.05), 1, 3, rest, plastic));
	}
	CHECK(plastic == 0.0);
}

TEST_CASE("[PhysicsFEM] Equivalent J2 yield and partial deformation are correct") {
	PhysicsFEMTetraRest rest;
	REQUIRE(rest_tetra(rest));
	const Vector3 p[4] = { Vector3(), Vector3(real_t(1.8), 0, 0),
			Vector3(0, real_t(0.8), 0), Vector3(0, 0, real_t(0.8)) };
	double before, after, plastic = 0.0;
	REQUIRE(measure(p, rest, before));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(p[0], p[1],
			p[2], p[3], real_t(2), 1, 2, rest, plastic));
	CHECK(physics_fem_tetra_creep_deviatoric_rest(p[0], p[1],
			p[2], p[3], real_t(0.1), real_t(.5), 2, rest, plastic));
	REQUIRE(measure(p, rest, after));
	CHECK(after == doctest::Approx(before - plastic).epsilon(2e-4));
	CHECK(after > 0.1);
}

TEST_CASE("[PhysicsFEM] One large time step matches two substeps at constant load") {
	PhysicsFEMTetraRest full, half;
	REQUIRE(rest_tetra(full));
	REQUIRE(rest_tetra(half));
	const Vector3 p[4] = { Vector3(), Vector3(real_t(1.3), 0, 0),
		Vector3(0, real_t(.9), 0), Vector3(0, 0, real_t(.9)) };
	double full_history = 0.0, half_history = 0.0;
	const double fraction = 1.0 - Math::exp(-3.0 * 0.2);
	const double half_fraction = 1.0 - Math::exp(-3.0 * 0.1);
	CHECK(physics_fem_tetra_creep_deviatoric_rest(p[0], p[1], p[2], p[3],
			real_t(.05), fraction, 4.0, full, full_history));
	CHECK(physics_fem_tetra_creep_deviatoric_rest(p[0], p[1], p[2], p[3],
			real_t(.05), half_fraction, 4.0, half, half_history));
	CHECK(physics_fem_tetra_creep_deviatoric_rest(p[0], p[1], p[2], p[3],
			real_t(.05), half_fraction, 4.0, half, half_history));
	CHECK(half_history == doctest::Approx(full_history).epsilon(1e-5));
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			CHECK(half.inv_dm[i][j] == doctest::Approx(full.inv_dm[i][j]).epsilon(1e-5));
		}
	}
}

TEST_CASE("[PhysicsFEM] Accumulated strain budget caps permanent shape change") {
	PhysicsFEMTetraRest rest;
	REQUIRE(rest_tetra(rest));
	double history = 0.0;
	const Vector3 p[4] = { Vector3(), Vector3(real_t(4), 0, 0),
		Vector3(0, real_t(.5), 0), Vector3(0, 0, real_t(.5)) };
	CHECK(physics_fem_tetra_creep_deviatoric_rest(p[0], p[1], p[2], p[3],
			0, 1, .1, rest, history));
	CHECK(history == doctest::Approx(.1).epsilon(1e-8));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(p[0], p[1], p[2], p[3],
			0, 1, .1, rest, history));
	CHECK(rest.volume == doctest::Approx(1.0 / 6.0));
}

TEST_CASE("[PhysicsFEM] Opposite rest winding remains valid after deviatoric relaxation") {
	PhysicsFEMTetraRest rest;
	REQUIRE(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, -1), rest));
	double plastic = 0.0;
	CHECK(physics_fem_tetra_creep_deviatoric_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(real_t(.6), 1, 0), Vector3(0, 0, -1),
			real_t(0), 1, 2.0, rest, plastic));
	CHECK(rest.signed_det == doctest::Approx(-1.0));
	CHECK(plastic > 0.0);
}

TEST_CASE("[PhysicsFEM] Inverted and malformed input do not alter mechanical rest") {
	PhysicsFEMTetraRest rest;
	REQUIRE(rest_tetra(rest));
	double plastic = .1;
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(Vector3(),
			Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1),
			0, 1, 2, rest, plastic));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(Vector3(),
			Vector3(nan, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
			0, 1, 2, rest, plastic));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(Vector3(),
			Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 0),
			0, 1, 2, rest, plastic));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(Vector3(),
			Vector3(1, 0, 0), Vector3(real_t(.6), 1, 0), Vector3(0, 0, 1),
			0, 1, .01, rest, plastic));
	CHECK(plastic == doctest::Approx(.1));
	CHECK(rest.inv_dm[0][0] == doctest::Approx(1.0));
	CHECK(rest.signed_det == doctest::Approx(1.0));
}

} // namespace TestFEMTetraDeviatoricPlasticity
