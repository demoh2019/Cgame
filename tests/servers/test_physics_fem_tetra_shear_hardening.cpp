/**************************************************************************/
/*  test_physics_fem_tetra_shear_hardening.cpp                            */
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

#include "servers/physics_fem_tetra_deviatoric_plasticity.h"
#include "servers/physics_fem_tetra_volume_plasticity.h"
#include "tests/test_macros.h"

#include <cmath>
#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_shear_hardening)

namespace TestPhysicsFEMTetraShearHardening {

static PhysicsFEMTetraRest unit() {
	PhysicsFEMTetraRest rest;
	physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest);
	return rest;
}

static double det3(const double m[3][3]) {
	return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
			m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
			m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
}

static double relaxation(double p_rate, double p_time, double p_hardening) {
	return (1.0 - std::exp(-p_rate * p_time * (1.0 + p_hardening))) /
			(1.0 + p_hardening);
}

TEST_CASE("[PhysicsFEMShearHardening] Higher hardening reduces plastic strain under the same load") {
	PhysicsFEMTetraRest plain = unit(), hardened = unit();
	const Vector3 p[4] = { Vector3(), Vector3(2, 0, 0),
		Vector3(0, 0.5, 0), Vector3(0, 0, 1) };
	double old_strain = 0.0, new_strain = 0.0;
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(0.1),
			relaxation(3, 0.5, 0), 3.0, plain, old_strain));
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(0.1),
			relaxation(3, 0.5, 2), 3.0, hardened, new_strain, 2.0));
	CHECK(old_strain > new_strain);
	CHECK(new_strain > 0.0);
	CHECK(Math::abs(plain.volume - hardened.volume) < 1e-12);
}

TEST_CASE("[PhysicsFEMShearHardening] Accumulated plasticity raises the yield threshold") {
	const Vector3 p[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(real_t(.6), 1, 0), Vector3(0, 0, 1) };
	PhysicsFEMTetraRest rest = unit();
	double hardening_history = 0.5;
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(.05),
			relaxation(5, .1, 2), 3.0, rest, hardening_history, 2));
	CHECK(hardening_history == 0.5);
	double legacy_history = 0.5;
	CHECK(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(.05),
			relaxation(5, .1, 0), 3.0, rest, legacy_history));
	CHECK(legacy_history > 0.5);
}

TEST_CASE("[PhysicsFEMShearHardening] One tick equals many substeps at fixed strain") {
	PhysicsFEMTetraRest full = unit(), subdivided = unit();
	const Vector3 p[4] = { Vector3(), Vector3(1.7, 0, 0),
		Vector3(0, real_t(.7), 0), Vector3(0, 0, real_t(.85)) };
	double full_history = 0.0, split_history = 0.0;
	const double hardening = 1.5;
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(.05),
			relaxation(5, .25, hardening), 3.0, full, full_history, hardening));
	for (int i = 0; i < 50; ++i) {
		physics_fem_tetra_creep_deviatoric_rest(
				p[0], p[1], p[2], p[3], real_t(.05),
				relaxation(5, .25 / 50, hardening), 3.0, subdivided, split_history,
				hardening);
	}
	CHECK(split_history == doctest::Approx(full_history).epsilon(1e-5));
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			CHECK(subdivided.inv_dm[i][j] ==
					doctest::Approx(full.inv_dm[i][j]).epsilon(1e-5));
		}
	}
}

TEST_CASE("[PhysicsFEMShearHardening] Skew rest tetra keeps volume and decreases elastic shear") {
	PhysicsFEMTetraRest rest;
	REQUIRE(physics_fem_tetra_make_rest(
			Vector3(), Vector3(2, 0, 0), Vector3(real_t(.4), real_t(1.3), 0),
			Vector3(real_t(.2), real_t(.3), real_t(1.1)), rest));
	const Vector3 p[4] = {
		Vector3(), Vector3(2, 0, 0),
		Vector3(real_t(1.1), real_t(1.3), 0),
		Vector3(real_t(.2), real_t(.3), real_t(1.1))
	};
	const double original_volume = rest.volume, old_det = det3(rest.inv_dm);
	double dev[3], basis[3][3], before = 0.0, after = 0.0, history = 0.0;
	REQUIRE(physics_fem_tetra_deviatoric_strains(p, rest, dev, basis, before));
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(.02),
			relaxation(4, .2, .4), 3.0, rest, history, .4));
	REQUIRE(physics_fem_tetra_deviatoric_strains(p, rest, dev, basis, after));
	CHECK(after < before);
	CHECK(Math::abs(rest.volume - original_volume) < 1e-12);
	CHECK(Math::abs(det3(rest.inv_dm) / old_det - 1.0) < 1e-9);
}

TEST_CASE("[PhysicsFEMShearHardening] Volume and deviatoric plasticity compose") {
	PhysicsFEMTetraRest rest = unit();
	const Vector3 p[4] = { Vector3(), Vector3(2, 0, 0),
		Vector3(0, real_t(.6), 0), Vector3(0, 0, real_t(1.2)) };
	double plastic_volume = 1.0, shear_history = 0.0;
	REQUIRE(physics_fem_tetra_creep_volume_rest(
			p[0], p[1], p[2], p[3], real_t(0.0), .8,
			rest, plastic_volume));
	const double volume = rest.volume, det = det3(rest.inv_dm);
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(.05),
			relaxation(3, .1, .5), 3.0, rest, shear_history, .5));
	CHECK(rest.volume == doctest::Approx(volume));
	CHECK(Math::abs(det3(rest.inv_dm) / det - 1.0) < 1e-9);
	CHECK(plastic_volume > 1.0);
	CHECK(shear_history > 0.0);
}

TEST_CASE("[PhysicsFEMShearHardening] Invalid hardening is transactional, default zero compatible") {
	const Vector3 p[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(real_t(.8), 1, 0), Vector3(0, 0, 1) };
	PhysicsFEMTetraRest previous = unit(), explicit_zero = unit();
	double historical = 0.0, comparison = 0.0;
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(0.0),
			.5, 3.0, previous, historical, -1.0));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(0.0),
			.5, 3.0, previous, historical,
			std::numeric_limits<double>::quiet_NaN()));
	CHECK(historical == 0.0);
	CHECK(previous.inv_dm[0][0] == 1.0);
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(0.0),
			.5, 3.0, previous, historical));
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			p[0], p[1], p[2], p[3], real_t(0.0),
			.5, 3.0, explicit_zero, comparison, 0.0));
	CHECK(historical == doctest::Approx(comparison));
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			CHECK(previous.inv_dm[i][j] ==
					doctest::Approx(explicit_zero.inv_dm[i][j]));
		}
	}
}

} // namespace TestPhysicsFEMTetraShearHardening
