/**************************************************************************/
/*  test_physics_fem_tetra_mooney_rivlin.cpp                                       */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_fem_tetra_mooney_rivlin.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_mooney_rivlin)

namespace TestPhysicsFEMTetraMooneyRivlin {

static PhysicsFEMTetraRest unit_rest() {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest));
	return rest;
}

static double energy(const PhysicsFEMTetraRest &p_rest, const Vector3 &a,
		const Vector3 &b, const Vector3 &c, const Vector3 &d, double ratio = 0.5,
		double poisson = 0.3) {
	double result = -1.0;
	Vector3 g0, g1, g2, g3;
	CHECK(physics_fem_tetra_mooney_rivlin_energy_gradient(
			a, b, c, d, p_rest, poisson, ratio, result, g0, g1, g2, g3));
	return result;
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin has zero energy at rest") {
	const PhysicsFEMTetraRest rest = unit_rest();
	CHECK(energy(rest, Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1)) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin is invariant under proper rotations") {
	const PhysicsFEMTetraRest rest = unit_rest();
	CHECK(energy(rest, Vector3(10, 20, 3), Vector3(10, 21, 3),
			Vector3(9, 20, 3), Vector3(10, 20, 4)) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin responds to isochoric large strain") {
	const PhysicsFEMTetraRest rest = unit_rest();
	const real_t length = real_t(1.5);
	const real_t lateral = real_t(1.0 / Math::sqrt(double(length)));
	const double e01 = energy(rest, Vector3(), Vector3(length, 0, 0),
			Vector3(0, lateral, 0), Vector3(0, 0, lateral), 0.1);
	const double e09 = energy(rest, Vector3(), Vector3(length, 0, 0),
			Vector3(0, lateral, 0), Vector3(0, 0, lateral), 0.9);
	CHECK(e01 > 0.0);
	CHECK(e09 > 0.0);
	CHECK(Math::abs(e01 - e09) > 1e-4);
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin produces restoring force on stretch") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	const double before = energy(rest, a, b, c, d);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_mooney_rivlin_solve(a, b, c, d,
			0, 1, 0, 0, rest, 0.3, 0.5, 0.0, lambda));
	CHECK(b.x < real_t(1.5));
	CHECK(b.x > real_t(0.0));
	CHECK(energy(rest, a, b, c, d) < before);
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin compression restores volume") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 a, b(real_t(0.8), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_mooney_rivlin_solve(a, b, c, d,
			0, 1, 0, 0, rest, 0.3, 0.5, 0.0, lambda));
	CHECK(b.x > real_t(0.8));
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin solver keeps pinned particles fixed") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0;
	CHECK(physics_fem_tetra_mooney_rivlin_solve(a, b, c, d,
			0, 1, 0, 0, rest, 0.3, 0.5, 0.001, lambda));
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin gradients agree with finite differences") {
	const PhysicsFEMTetraRest rest = unit_rest();
	const Vector3 a(0, 0, 0), b(real_t(1.25), real_t(0.2), 0),
			c(real_t(0.1), real_t(0.9), real_t(0.05)), d(0, real_t(0.1), real_t(1.15));
	double e = 0;
	Vector3 ga, gb, gc, gd;
	CHECK(physics_fem_tetra_mooney_rivlin_energy_gradient(a, b, c, d,
			rest, 0.3, 0.7, e, ga, gb, gc, gd));
	const real_t eps = real_t(0.0005);
	const double plus = energy(rest, a, b, Vector3(c.x + eps, c.y, c.z), d, 0.7);
	const double minus = energy(rest, a, b, Vector3(c.x - eps, c.y, c.z), d, 0.7);
	CHECK(double(gc.x) == doctest::Approx((plus - minus) / (2.0 * double(eps))).epsilon(0.005));
	CHECK((ga + gb + gc + gd).length() < real_t(1e-4));
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin negative rest winding is supported") {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(0, 1, 0),
			Vector3(1, 0, 0), Vector3(0, 0, 1), rest));
	CHECK(rest.signed_det < 0.0);
	CHECK(energy(rest, Vector3(), Vector3(0, 1, 0),
			Vector3(1, 0, 0), Vector3(0, 0, 1)) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin inverted positions are rejected atomically") {
	const PhysicsFEMTetraRest rest = unit_rest();
	double e = 9.0;
	Vector3 ga, gb, gc, gd;
	CHECK_FALSE(physics_fem_tetra_mooney_rivlin_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, -1), rest, 0.3, 0.5, e, ga, gb, gc, gd));
	CHECK(e == 9.0);
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin rejects invalid split and Poisson ratio") {
	const PhysicsFEMTetraRest rest = unit_rest();
	double e = 9.0;
	Vector3 ga, gb, gc, gd;
	CHECK_FALSE(physics_fem_tetra_mooney_rivlin_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, 1), rest, 0.3, -0.1, e, ga, gb, gc, gd));
	CHECK_FALSE(physics_fem_tetra_mooney_rivlin_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, 1), rest, 0.3, 1.1, e, ga, gb, gc, gd));
	CHECK_FALSE(physics_fem_tetra_mooney_rivlin_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, 1), rest, 0.5, 0.5, e, ga, gb, gc, gd));
	CHECK(e == 9.0);
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin compliance controls stiffness") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	Vector3 soft_a = a, soft_b = b, soft_c = c, soft_d = d;
	double l0 = 0.0, l1 = 0.0;
	CHECK(physics_fem_tetra_mooney_rivlin_solve(a, b, c, d,
			0, 1, 0, 0, rest, 0.3, 0.5, 0.001, l0));
	CHECK(physics_fem_tetra_mooney_rivlin_solve(soft_a, soft_b, soft_c, soft_d,
			0, 1, 0, 0, rest, 0.3, 0.5, 0.1, l1));
	CHECK(soft_b.x > b.x);
}

TEST_CASE("[PhysicsFEM] Mooney-Rivlin passes through no update at rest") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_mooney_rivlin_solve(a, b, c, d,
			1, 1, 1, 1, rest, 0.3, 0.5, 0.001, lambda));
	CHECK(b == Vector3(1, 0, 0));
}

} // namespace TestPhysicsFEMTetraMooneyRivlin
