/**************************************************************************/
/*  test_physics_fem_tetra_ogden.cpp                                       */
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

#include "servers/physics_fem_tetra_ogden.h"
#include "servers/physics_fem_tetra_mooney_rivlin.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_ogden)

namespace TestPhysicsFEMTetraOgden {

static PhysicsFEMTetraRest make_rest() {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest));
	return rest;
}

static double energy(const PhysicsFEMTetraRest &p_rest, const Vector3 &a,
		const Vector3 &b, const Vector3 &c, const Vector3 &d,
		double exponent = 3.0) {
	double e = -1.0;
	Vector3 ga, gb, gc, gd;
	CHECK(physics_fem_tetra_ogden_energy_gradient(
			a, b, c, d, p_rest, 0.3, exponent, e, ga, gb, gc, gd));
	return e;
}

TEST_CASE("[PhysicsFEM] Ogden energy and gradients vanish in rest configuration") {
	const PhysicsFEMTetraRest rest = make_rest();
	double e = -1.0;
	Vector3 ga, gb, gc, gd;
	CHECK(physics_fem_tetra_ogden_energy_gradient(Vector3(),
			Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
			rest, 0.3, 3.0, e, ga, gb, gc, gd));
	CHECK(e == doctest::Approx(0.0));
	CHECK(ga.length() < real_t(1e-6));
	CHECK(gb.length() < real_t(1e-6));
}

TEST_CASE("[PhysicsFEM] Ogden is invariant under rigid translation and rotation") {
	const PhysicsFEMTetraRest rest = make_rest();
	CHECK(energy(rest, Vector3(9, 3, 4), Vector3(9, 4, 4),
			Vector3(8, 3, 4), Vector3(9, 3, 5)) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Ogden order two agrees with isochoric Mooney-Rivlin") {
	const PhysicsFEMTetraRest rest = make_rest();
	const Vector3 a, b(real_t(1.3), real_t(0.15), 0),
			c(real_t(0.1), real_t(0.85), 0), d(0, 0, real_t(1.1));
	double eo, em;
	Vector3 a0, b0, c0, d0, a1, b1, c1, d1;
	CHECK(physics_fem_tetra_ogden_energy_gradient(
			a, b, c, d, rest, 0.3, 2.0, eo, a0, b0, c0, d0));
	CHECK(physics_fem_tetra_mooney_rivlin_energy_gradient(
			a, b, c, d, rest, 0.3, 0.0, em, a1, b1, c1, d1));
	CHECK(eo == doctest::Approx(em).epsilon(1e-5));
	CHECK((a0 - a1).length() < real_t(1e-5));
	CHECK((b0 - b1).length() < real_t(1e-5));
}

TEST_CASE("[PhysicsFEM] Ogden exponent modifies finite-strain stress") {
	const PhysicsFEMTetraRest rest = make_rest();
	const double low = energy(rest, Vector3(), Vector3(real_t(1.7), 0, 0),
			Vector3(0, real_t(0.7), 0), Vector3(0, 0, 1), 1.1);
	const double high = energy(rest, Vector3(), Vector3(real_t(1.7), 0, 0),
			Vector3(0, real_t(0.7), 0), Vector3(0, 0, 1), 7.0);
	CHECK(low > 0.0);
	CHECK(high > 0.0);
	CHECK(Math::abs(low - high) > 1e-4);
}

TEST_CASE("[PhysicsFEM] Ogden compression and shear resist deformation") {
	const PhysicsFEMTetraRest rest = make_rest();
	CHECK(energy(rest, Vector3(), Vector3(real_t(0.75), 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1)) > 0.0);
	CHECK(energy(rest, Vector3(), Vector3(1, 0, 0),
			Vector3(real_t(0.3), 1, 0), Vector3(0, 0, 1)) > 0.0);
}

TEST_CASE("[PhysicsFEM] Ogden XPBD returns stretched tetrahedron toward rest") {
	const PhysicsFEMTetraRest rest = make_rest();
	Vector3 a, b(real_t(1.4), 0, 0), c(0, 1, 0), d(0, 0, 1);
	const double before = energy(rest, a, b, c, d);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_ogden_solve(a, b, c, d, 0, 1, 0, 0,
			rest, 0.3, 3.0, 0.001, lambda));
	CHECK(b.x < real_t(1.4));
	CHECK(energy(rest, a, b, c, d) < before);
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEM] Ogden analytical gradient matches finite differences") {
	const PhysicsFEMTetraRest rest = make_rest();
	const Vector3 a, b(real_t(1.25), real_t(0.2), 0),
			c(real_t(0.2), real_t(0.9), real_t(0.05)), d(0, real_t(0.1), real_t(1.1));
	double e;
	Vector3 ga, gb, gc, gd;
	CHECK(physics_fem_tetra_ogden_energy_gradient(
			a, b, c, d, rest, 0.3, 3.5, e, ga, gb, gc, gd));
	const real_t eps = real_t(0.0005);
	const double plus = energy(rest, a, b, Vector3(c.x + eps, c.y, c.z), d, 3.5);
	const double minus = energy(rest, a, b, Vector3(c.x - eps, c.y, c.z), d, 3.5);
	CHECK(double(gc.x) == doctest::Approx((plus - minus) / (2.0 * double(eps))).epsilon(0.005));
	CHECK((ga + gb + gc + gd).length() < real_t(1e-4));
}

TEST_CASE("[PhysicsFEM] Ogden accepts inverse rest winding") {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(0, 1, 0),
			Vector3(1, 0, 0), Vector3(0, 0, 1), rest));
	CHECK(rest.signed_det < 0.0);
	CHECK(energy(rest, Vector3(), Vector3(0, 1, 0),
			Vector3(1, 0, 0), Vector3(0, 0, 1)) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Ogden rejects collapsed and inverted tets atomically") {
	const PhysicsFEMTetraRest rest = make_rest();
	double e = 71.0;
	Vector3 ga, gb, gc, gd;
	CHECK_FALSE(physics_fem_tetra_ogden_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, -1), rest, 0.3, 3, e, ga, gb, gc, gd));
	CHECK_FALSE(physics_fem_tetra_ogden_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(), rest, 0.3, 3, e, ga, gb, gc, gd));
	CHECK(e == 71.0);
}

TEST_CASE("[PhysicsFEM] Ogden clamps invalid exponents and Poisson inputs") {
	const PhysicsFEMTetraRest rest = make_rest();
	double e = 41.0;
	Vector3 ga, gb, gc, gd;
	CHECK_FALSE(physics_fem_tetra_ogden_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, 1), rest, 0.3, 0.0, e, ga, gb, gc, gd));
	CHECK_FALSE(physics_fem_tetra_ogden_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, 1), rest, 0.3, 9.0, e, ga, gb, gc, gd));
	CHECK_FALSE(physics_fem_tetra_ogden_energy_gradient(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, 1), rest, 0.5, 3.0, e, ga, gb, gc, gd));
	CHECK(e == 41.0);
}

TEST_CASE("[PhysicsFEM] Ogden stable near repeated principal stretches") {
	const PhysicsFEMTetraRest rest = make_rest();
	const Vector3 a, b(real_t(1.01), 0, 0),
			c(0, real_t(1.01), 0), d(0, 0, real_t(0.99));
	double e;
	Vector3 ga, gb, gc, gd;
	CHECK(physics_fem_tetra_ogden_energy_gradient(
			a, b, c, d, rest, 0.3, 4.0, e, ga, gb, gc, gd));
	CHECK(e > 0.0);
	CHECK(ga.is_finite());
	CHECK(gb.is_finite());
}

TEST_CASE("[PhysicsFEM] Ogden soft compliance reduces one-step correction") {
	const PhysicsFEMTetraRest rest = make_rest();
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	Vector3 sa = a, sb = b, sc = c, sd = d;
	double l0 = 0.0, l1 = 0.0;
	CHECK(physics_fem_tetra_ogden_solve(a, b, c, d, 0, 1, 0, 0,
			rest, 0.3, 4.0, 0.001, l0));
	CHECK(physics_fem_tetra_ogden_solve(sa, sb, sc, sd, 0, 1, 0, 0,
			rest, 0.3, 4.0, 0.1, l1));
	CHECK(sb.x > b.x);
}

TEST_CASE("[PhysicsFEM] Ogden at rest leaves pinned node and multiplier unchanged") {
	const PhysicsFEMTetraRest rest = make_rest();
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_ogden_solve(a, b, c, d, 1, 1, 1, 1,
			rest, 0.3, 3.0, 0.001, lambda));
	CHECK(b == Vector3(1, 0, 0));
	CHECK(lambda == 0.0);
}

} // namespace TestPhysicsFEMTetraOgden
