/**************************************************************************/
/*  test_physics_fem_tetra_inversion_recovery.cpp                         */
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

#include "servers/physics_fem_tetra_inversion_recovery.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_inversion_recovery)

namespace TestFEMTetraInversionRecovery {

static bool make_unit_rest(PhysicsFEMTetraRest &r_rest) {
	return physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), r_rest);
}

TEST_CASE("[PhysicsFEM] Inverted tetrahedron recovers positive Jacobian") {
	PhysicsFEMTetraRest rest;
	REQUIRE(make_unit_rest(rest));
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, -1);
	double energy;
	Vector3 ga, gb, gc, gd;
	CHECK_FALSE(physics_fem_tetra_energy_gradient(a, b, c, d,
			rest, 0.3, energy, ga, gb, gc, gd));
	CHECK(physics_fem_tetra_recover_orientation(a, b, c, d,
			1, 1, 1, 1, rest, 0.05));
	const Vector3 p[4] = { a, b, c, d };
	double jacobian, gradients[4][3];
	CHECK(physics_fem_tetra_recovery_jacobian(p, rest, jacobian, gradients));
	CHECK(jacobian >= 0.05 - 1e-5);
	CHECK(jacobian <= 1.0 + 1e-5);
	CHECK(physics_fem_tetra_energy_gradient(a, b, c, d,
			rest, 0.3, energy, ga, gb, gc, gd));
}

TEST_CASE("[PhysicsFEM] Collapsed tetrahedron expands away from singularity") {
	PhysicsFEMTetraRest rest;
	REQUIRE(make_unit_rest(rest));
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d;
	CHECK(physics_fem_tetra_recover_orientation(a, b, c, d,
			0, 0, 0, 1, rest, 0.05));
	CHECK(d.z == doctest::Approx(0.05).epsilon(1e-4));
	CHECK(a == Vector3());
	CHECK(b == Vector3(1, 0, 0));
	CHECK(c == Vector3(0, 1, 0));
}

TEST_CASE("[PhysicsFEM] All-pinned and already-valid configurations stay untouched") {
	PhysicsFEMTetraRest rest;
	REQUIRE(make_unit_rest(rest));
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, -1);
	CHECK_FALSE(physics_fem_tetra_recover_orientation(a, b, c, d,
			0, 0, 0, 0, rest, 0.05));
	CHECK(d == Vector3(0, 0, -1));
	d = Vector3(0, 0, 1);
	CHECK_FALSE(physics_fem_tetra_recover_orientation(a, b, c, d,
			1, 1, 1, 1, rest, 0.05));
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEM] Negative rest winding is oriented consistently") {
	PhysicsFEMTetraRest rest;
	REQUIRE(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, -1), rest));
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, 1);
	CHECK(physics_fem_tetra_recover_orientation(a, b, c, d,
			0, 0, 0, 1, rest, 0.05));
	CHECK(d.z < 0.0);
}

TEST_CASE("[PhysicsFEM] Smaller and larger tetrahedra share a normalized barrier") {
	for (double scale : { 1e-3, 1.0, 1e3 }) {
		const real_t s = real_t(scale);
		PhysicsFEMTetraRest rest;
		REQUIRE(physics_fem_tetra_make_rest(
				Vector3(), Vector3(s, 0, 0), Vector3(0, s, 0), Vector3(0, 0, s), rest));
		Vector3 a, b(s, 0, 0), c(0, s, 0), d(0, 0, -s);
		CHECK(physics_fem_tetra_recover_orientation(a, b, c, d,
				0, 0, 0, 1, rest, 0.05));
		const Vector3 p[4] = { a, b, c, d };
		double j, g[4][3];
		CHECK(physics_fem_tetra_recovery_jacobian(p, rest, j, g));
		CHECK(j >= .05 - 1e-5);
	}
}

TEST_CASE("[PhysicsFEM] Invalid input cannot mutate any vertex") {
	PhysicsFEMTetraRest rest;
	REQUIRE(make_unit_rest(rest));
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, -1);
	CHECK_FALSE(physics_fem_tetra_recover_orientation(a, b, c, d,
			1, 1, 1, 1, rest, 0));
	CHECK_FALSE(physics_fem_tetra_recover_orientation(a, b, c, d,
			1, -1, 1, 1, rest, .05));
	CHECK_FALSE(physics_fem_tetra_recover_orientation(a, b, c, d,
			1, 1, 1, 1, rest, 0.8));
	CHECK(d == Vector3(0, 0, -1));
	b.x = nan;
	CHECK_FALSE(physics_fem_tetra_recover_orientation(a, b, c, d,
			1, 1, 1, 1, rest, .05));
	CHECK(d == Vector3(0, 0, -1));
}

} // namespace TestFEMTetraInversionRecovery
