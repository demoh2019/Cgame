/**************************************************************************/
/*  test_physics_fem_tetra_deviatoric_plasticity.cpp                      */
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

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_deviatoric_plasticity)

namespace TestPhysicsFEMTetraDeviatoricPlasticity {

static PhysicsFEMTetraRest unit_rest() {
	PhysicsFEMTetraRest rest;
	physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest);
	return rest;
}

static double determinant(const double p_matrix[3][3]) {
	return p_matrix[0][0] * (p_matrix[1][1] * p_matrix[2][2] -
			p_matrix[1][2] * p_matrix[2][1]) -
			p_matrix[0][1] * (p_matrix[1][0] * p_matrix[2][2] -
			p_matrix[1][2] * p_matrix[2][0]) +
			p_matrix[0][2] * (p_matrix[1][0] * p_matrix[2][1] -
			p_matrix[1][1] * p_matrix[2][0]);
}

TEST_CASE("[PhysicsFEMDeviatoricPlastic] Pure isochoric stretch flows but rest volume stays unchanged") {
	PhysicsFEMTetraRest rest = unit_rest();
	const Vector3 points[4] = {
		Vector3(), Vector3(2, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 0, 1)
	};
	const double old_volume = rest.volume;
	const double old_det = determinant(rest.inv_dm);
	double accumulated = 0.0;
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			points, 0.0, 0.0, 1.0, 4.0, rest, accumulated));
	CHECK(accumulated > 0.0);
	CHECK(Math::abs(rest.volume - old_volume) < 1e-12);
	CHECK(Math::abs(determinant(rest.inv_dm) - old_det) < 1e-10);
	CHECK(Math::abs(rest.inv_dm[0][0] - 0.5) < 1e-8);
	CHECK(Math::abs(rest.inv_dm[1][1] - 2.0) < 1e-8);
	CHECK(Math::abs(rest.inv_dm[2][2] - 1.0) < 1e-8);
	CHECK(rest.signed_det == 1.0);
}

TEST_CASE("[PhysicsFEMDeviatoricPlastic] Rigid rotation and translation do not yield") {
	PhysicsFEMTetraRest rest = unit_rest();
	const Vector3 points[4] = {
		Vector3(10, -50, 20), Vector3(10, -49, 20),
		Vector3(9, -50, 20), Vector3(10, -50, 21)
	};
	double accumulated = 0.0;
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			points, 0.0, 0.0, 1.0, 4.0, rest, accumulated));
	CHECK(accumulated == 0.0);
	CHECK(rest.inv_dm[0][0] == 1.0);
}

TEST_CASE("[PhysicsFEMDeviatoricPlastic] Uniform compression or expansion does not cause shear plasticity") {
	for (const real_t scale : { real_t(0.7), real_t(1.4) }) {
		PhysicsFEMTetraRest rest = unit_rest();
		const Vector3 points[4] = {
			Vector3(), Vector3(scale, 0, 0),
			Vector3(0, scale, 0), Vector3(0, 0, scale)
		};
		double accumulated = 0.0;
		CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
				points, 0.0, 0.0, 1.0, 4.0, rest, accumulated));
		CHECK(accumulated == 0.0);
	}
}

TEST_CASE("[PhysicsFEMDeviatoricPlastic] Material hardening reduces subsequent shape flow") {
	const Vector3 points[4] = {
		Vector3(), Vector3(2, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 0, 1)
	};
	PhysicsFEMTetraRest soft = unit_rest(), hardened = unit_rest();
	double soft_strain = 0.0, hard_strain = 0.0;
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			points, 0.1, 0.0, 0.5, 4.0, soft, soft_strain));
	// Same raw rate*dt with H=2: (1-(1-0.5)^3)/3.
	const double hardened_relaxation = (1.0 - 0.125) / 3.0;
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			points, 0.1, 2.0, hardened_relaxation, 4.0, hardened, hard_strain));
	CHECK(hard_strain < soft_strain);
	CHECK(hardened.inv_dm[0][0] > soft.inv_dm[0][0]);
}

TEST_CASE("[PhysicsFEMDeviatoricPlastic] Plastic deformation is bounded and cannot undo prior flow") {
	const Vector3 points[4] = {
		Vector3(), Vector3(8, 0, 0), Vector3(0, 0.25, 0), Vector3(0, 0, 0.5)
	};
	PhysicsFEMTetraRest rest = unit_rest();
	double accumulated = 0.0;
	for (int i = 0; i < 100; ++i) {
		const double before = accumulated;
		physics_fem_tetra_creep_deviatoric_rest(
				points, 0.02, 0.5, 0.1, 0.25, rest, accumulated);
		CHECK(accumulated >= before);
		CHECK(accumulated <= 0.25);
		CHECK(Math::abs(determinant(rest.inv_dm) - 1.0) < 1e-8);
	}
	CHECK(accumulated > 0.20);
}

TEST_CASE("[PhysicsFEMDeviatoricPlastic] Isotropic volume plasticity composes with shear plasticity") {
	PhysicsFEMTetraRest rest = unit_rest();
	const Vector3 points[4] = {
		Vector3(), Vector3(2.2, 0, 0), Vector3(0, 0.6, 0),
		Vector3(0, 0, 1.3)
	};
	double volume_scale = 1.0, accumulated = 0.0;
	REQUIRE(physics_fem_tetra_creep_volume_rest(
			points[0], points[1], points[2], points[3],
			real_t(0.0), 0.8, rest, volume_scale));
	const double intermediate_volume = rest.volume;
	const double intermediate_det = determinant(rest.inv_dm);
	REQUIRE(physics_fem_tetra_creep_deviatoric_rest(
			points, 0.01, 0.1, 0.7, 4.0, rest, accumulated));
	CHECK(Math::abs(rest.volume - intermediate_volume) < 1e-12);
	CHECK(Math::abs(determinant(rest.inv_dm) - intermediate_det) < 1e-8);
	CHECK(volume_scale > 1.0);
	CHECK(accumulated > 0.0);
}

TEST_CASE("[PhysicsFEMDeviatoricPlastic] Inverted, degenerate and invalid inputs preserve rest state") {
	PhysicsFEMTetraRest rest = unit_rest();
	const Vector3 inverted[4] = {
		Vector3(), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	const Vector3 degenerate[4] = {
		Vector3(), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	double accumulated = 0.0;
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			inverted, 0.1, 0.2, 1.0, 4.0, rest, accumulated));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			degenerate, 0.1, 0.2, 1.0, 4.0, rest, accumulated));
	const Vector3 normal[4] = {
		Vector3(), Vector3(1.5, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			normal, -1.0, 0.2, 1.0, 4.0, rest, accumulated));
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			normal, 0.0, 0.2, 1.1, 4.0, rest, accumulated));
	double saturated_history = 4.0;
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			normal, 0.0, 0.2, 0.5, 4.0, rest, saturated_history));
	CHECK(saturated_history == 4.0);
	CHECK_FALSE(physics_fem_tetra_creep_deviatoric_rest(
			normal, 0.0, 0.2, std::numeric_limits<double>::quiet_NaN(),
			4.0, rest, accumulated));
	CHECK(rest.volume == doctest::Approx(1.0 / 6.0));
	CHECK(Math::abs(determinant(rest.inv_dm) - 1.0) < 1e-12);
	CHECK(accumulated == 0.0);
}

} // namespace TestPhysicsFEMTetraDeviatoricPlasticity
