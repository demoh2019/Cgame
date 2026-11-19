/**************************************************************************/
/*  test_physics_fem_tetra_neo_hookean.cpp                                */
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

#include "servers/physics_fem_tetra_neo_hookean.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_neo_hookean)

namespace TestPhysicsFEMTetraNeoHookean {

static PhysicsFEMTetraRest make_rest() {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest));
	return rest;
}

static double energy_at(const PhysicsFEMTetraRest &p_rest, const Vector3 &p_a,
		const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_d, double p_poisson = 0.3) {
	double energy = -1.0;
	Vector3 g0, g1, g2, g3;
	CHECK(physics_fem_tetra_energy_gradient(p_a, p_b, p_c, p_d,
			p_rest, p_poisson, energy, g0, g1, g2, g3));
	return energy;
}

TEST_CASE("[PhysicsFEM] Rest state has zero tetrahedral strain energy") {
	const PhysicsFEMTetraRest rest = make_rest();
	CHECK(rest.volume == doctest::Approx(1.0 / 6.0));
	CHECK(energy_at(rest, Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1)) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Rigid translation and rotation preserve energy") {
	const PhysicsFEMTetraRest rest = make_rest();
	const Vector3 a(3, 5, 2), b(3, 6, 2), c(2, 5, 2), d(3, 5, 3);
	CHECK(energy_at(rest, a, b, c, d) == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Negative rest winding is supported") {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(0, 1, 0),
			Vector3(1, 0, 0), Vector3(0, 0, 1), rest));
	CHECK(rest.signed_det < 0.0);
	CHECK(energy_at(rest, Vector3(), Vector3(0, 1, 0), Vector3(1, 0, 0),
			Vector3(0, 0, 1)) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Uniaxial stretching generates restoring corrections") {
	const PhysicsFEMTetraRest rest = make_rest();
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	const double energy_before = energy_at(rest, a, b, c, d);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve(a, b, c, d, 0, 1, 0, 0,
			rest, 0.3, 0.0, lambda));
	CHECK(b.x < real_t(1.5));
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
	CHECK(energy_at(rest, a, b, c, d) < energy_before);
}

TEST_CASE("[PhysicsFEM] Compression pushes a movable tetra node outward") {
	const PhysicsFEMTetraRest rest = make_rest();
	Vector3 a, b(real_t(0.6), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve(a, b, c, d, 0, 1, 0, 0,
			rest, 0.3, 0.0, lambda));
	CHECK(b.x > real_t(0.6));
}

TEST_CASE("[PhysicsFEM] Simple shear produces nonzero strain energy") {
	const PhysicsFEMTetraRest rest = make_rest();
	CHECK(energy_at(rest, Vector3(), Vector3(1, 0, 0),
			Vector3(real_t(0.3), 1, 0), Vector3(0, 0, 1)) > 0.0);
}

TEST_CASE("[PhysicsFEM] Poisson ratio changes bulk response") {
	const PhysicsFEMTetraRest rest = make_rest();
	const Vector3 a, b(real_t(1.2), 0, 0), c(0, 1, 0), d(0, 0, 1);
	const double independent = energy_at(rest, a, b, c, d, 0.0);
	const double coupled = energy_at(rest, a, b, c, d, 0.45);
	CHECK(Math::abs(independent - coupled) > 0.01);
}

TEST_CASE("[PhysicsFEM] Energy gradients agree with centered finite differences") {
	const PhysicsFEMTetraRest rest = make_rest();
	const Vector3 a, b(real_t(1.2), real_t(0.1), 0), c(real_t(0.2), 1, 0), d(0, 0, real_t(1.1));
	double energy, e_plus, e_minus;
	Vector3 ga, gb, gc, gd;
	CHECK(physics_fem_tetra_energy_gradient(a, b, c, d, rest, 0.3,
			energy, ga, gb, gc, gd));
	const real_t eps = real_t(0.0005);
	e_plus = energy_at(rest, a, b, Vector3(c.x + eps, c.y, c.z), d);
	e_minus = energy_at(rest, a, b, Vector3(c.x - eps, c.y, c.z), d);
	CHECK(double(gc.x) == doctest::Approx((e_plus - e_minus) / (2.0 * double(eps))).epsilon(0.002));
	CHECK((ga + gb + gc + gd).length() < real_t(0.00001));
}

TEST_CASE("[PhysicsFEM] Collapsed and inverted elements are rejected atomically") {
	const PhysicsFEMTetraRest rest = make_rest();
	double energy = 17.0;
	Vector3 g0, g1, g2, g3;
	CHECK_FALSE(physics_fem_tetra_energy_gradient(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, -1), rest, 0.3,
			energy, g0, g1, g2, g3));
	CHECK_FALSE(physics_fem_tetra_energy_gradient(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 0), rest, 0.3,
			energy, g0, g1, g2, g3));
	CHECK(energy == 17.0);
}

TEST_CASE("[PhysicsFEM] Degenerate rest tetrahedra leave the output untouched") {
	PhysicsFEMTetraRest rest;
	rest.volume = 42.0;
	CHECK_FALSE(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(1, 1, 0), rest));
	CHECK(rest.volume == 42.0);
}

TEST_CASE("[PhysicsFEM] All-pinned tetrahedra cannot modify the solver state") {
	const PhysicsFEMTetraRest rest = make_rest();
	Vector3 a, b(real_t(1.2), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 7.0;
	CHECK_FALSE(physics_fem_tetra_solve(a, b, c, d, 0, 0, 0, 0,
			rest, 0.3, 0.0, lambda));
	CHECK(b.x == real_t(1.2));
	CHECK(lambda == 7.0);
}

TEST_CASE("[PhysicsFEM] Compliant repeated iterations remain finite") {
	const PhysicsFEMTetraRest rest = make_rest();
	Vector3 a, b(real_t(1.35), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	for (int i = 0; i < 16; ++i) {
		physics_fem_tetra_solve(a, b, c, d, 0, 1, 0, 0, rest, 0.3, 0.01, lambda);
	}
	CHECK(b.x > real_t(1.0));
	CHECK(b.x < real_t(1.35));
	CHECK(Math::is_finite(lambda));
}

TEST_CASE("[PhysicsFEM] Extreme but finite tetrahedron scales can be initialized") {
	const real_t lengths[] = { real_t(1e-6), real_t(1e6) };
	for (real_t size : lengths) {
		PhysicsFEMTetraRest rest;
		CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(size, 0, 0),
				Vector3(0, size, 0), Vector3(0, 0, size), rest));
		CHECK(rest.volume > 0.0);
		CHECK(energy_at(rest, Vector3(), Vector3(size, 0, 0),
				Vector3(0, size, 0), Vector3(0, 0, size)) == doctest::Approx(0.0));
	}
}

} // namespace TestPhysicsFEMTetraNeoHookean
