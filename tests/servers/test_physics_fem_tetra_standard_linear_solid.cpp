/**************************************************************************/
/*  test_physics_fem_tetra_standard_linear_solid.cpp                                */
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

#include "servers/physics_fem_tetra_standard_linear_solid.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_standard_linear_solid)

namespace TestPhysicsFEMTetraStandardLinearSolid {

static PhysicsFEMTetraRest unit_rest() {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest));
	return rest;
}

static bool evaluate(const Vector3 (&x)[4], const PhysicsFEMTetraRest &rest,
		const PhysicsFEMTetraSLSState &state, double &energy,
		Vector3 (&grad)[4]) {
	return physics_fem_tetra_sls_energy_gradient(
			x[0], x[1], x[2], x[3], rest, state, 0.3, energy,
			grad[0], grad[1], grad[2], grad[3]);
}

TEST_CASE("[PhysicsFEM] SLS equilibrium at rest has zero energy and force") {
	const PhysicsFEMTetraRest rest = unit_rest();
	const PhysicsFEMTetraSLSState state;
	const Vector3 x[4] = { Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	Vector3 grad[4];
	double energy = -1.0;
	CHECK(evaluate(x, rest, state, energy, grad));
	CHECK(energy == doctest::Approx(0.0));
	for (Vector3 &g : grad) {
		CHECK(g.length() < real_t(1e-6));
	}
}

TEST_CASE("[PhysicsFEM] SLS objective under rigid translation and rotation") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const Vector3 original[4] = {
		Vector3(), Vector3(real_t(1.4), real_t(0.2), 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	CHECK(physics_fem_tetra_sls_relax(original, rest, 0.5, 0.03, state));
	Vector3 grads[4], rotated_grads[4];
	double before, after;
	CHECK(evaluate(original, rest, state, before, grads));
	Vector3 rotated[4];
	for (int v = 0; v < 4; ++v) {
		rotated[v] = Vector3(real_t(10.0) - original[v].y,
				real_t(20.0) + original[v].x, original[v].z + real_t(5.0));
	}
	CHECK(evaluate(rotated, rest, state, after, rotated_grads));
	CHECK(after == doctest::Approx(before).epsilon(1e-5));
	for (int v = 0; v < 4; ++v) {
		CHECK(rotated_grads[v].x == doctest::Approx(-grads[v].y).epsilon(1e-4));
		CHECK(rotated_grads[v].y == doctest::Approx(grads[v].x).epsilon(1e-4));
	}
}

TEST_CASE("[PhysicsFEM] SLS exponential creep reaches a constant strain") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const Vector3 stretched[4] = {
		Vector3(), Vector3(real_t(1.5), 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	const double target = (1.5 * 1.5 - 1.0) * 0.5;
	CHECK(physics_fem_tetra_sls_relax(stretched, rest, 0.2, 0.1, state));
	CHECK(state.relaxing_strain[0][0] ==
			doctest::Approx(target * (1.0 - std::exp(-0.5))).epsilon(1e-6));
	CHECK(physics_fem_tetra_sls_relax(stretched, rest, 0.2, 3.0, state));
	CHECK(state.relaxing_strain[0][0] == doctest::Approx(target).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEM] SLS has decreasing transient stored energy under constant strain") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const Vector3 stretched[4] = {
		Vector3(), Vector3(real_t(1.3), 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	Vector3 g[4];
	double first, second;
	CHECK(evaluate(stretched, rest, state, first, g));
	CHECK(physics_fem_tetra_sls_relax(stretched, rest, 0.2, 0.05, state));
	CHECK(evaluate(stretched, rest, state, second, g));
	CHECK(second < first);
	CHECK(second == doctest::Approx(first * std::exp(-0.5)).epsilon(0.001));
}

TEST_CASE("[PhysicsFEM] SLS exhibits temporary elastic recovery after unloading") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const Vector3 stretched[4] = {
		Vector3(), Vector3(real_t(1.4), 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	const Vector3 unloaded[4] = {
		Vector3(), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	CHECK(physics_fem_tetra_sls_relax(stretched, rest, 0.1, 0.1, state));
	Vector3 g[4];
	double stored = 0.0;
	CHECK(evaluate(unloaded, rest, state, stored, g));
	CHECK(stored > 0.0);
	CHECK(g[1].x < 0.0);
	CHECK(physics_fem_tetra_sls_relax(unloaded, rest, 0.1, 0.1, state));
	double relaxed = 0.0;
	CHECK(evaluate(unloaded, rest, state, relaxed, g));
	CHECK(relaxed < stored);
}

TEST_CASE("[PhysicsFEM] SLS relaxation rate independent of timestep subdivision") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState a, b;
	const Vector3 x[4] = {
		Vector3(), Vector3(real_t(1.6), 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	CHECK(physics_fem_tetra_sls_relax(x, rest, 0.3, 0.2, a));
	CHECK(physics_fem_tetra_sls_relax(x, rest, 0.3, 0.1, b));
	CHECK(physics_fem_tetra_sls_relax(x, rest, 0.3, 0.1, b));
	CHECK(a.relaxing_strain[0][0] ==
			doctest::Approx(b.relaxing_strain[0][0]).epsilon(1e-11));
}

TEST_CASE("[PhysicsFEM] SLS shear strain populates symmetric memory tensor") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const Vector3 x[4] = {
		Vector3(), Vector3(1, 0, 0),
		Vector3(real_t(0.4), 1, 0), Vector3(0, 0, 1)
	};
	CHECK(physics_fem_tetra_sls_relax(x, rest, 0.2, 0.03, state));
	CHECK(state.relaxing_strain[0][1] > 0.0);
	CHECK(state.relaxing_strain[0][1] ==
			doctest::Approx(state.relaxing_strain[1][0]));
}

TEST_CASE("[PhysicsFEM] SLS energy gradient agrees with central differences") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const Vector3 x[4] = {
		Vector3(), Vector3(real_t(1.25), real_t(0.13), 0),
		Vector3(real_t(0.1), real_t(0.92), real_t(0.04)),
		Vector3(0, real_t(0.05), real_t(1.11))
	};
	CHECK(physics_fem_tetra_sls_relax(x, rest, 0.8, 0.1, state));
	Vector3 g[4], h[4];
	double before, plus, minus;
	CHECK(evaluate(x, rest, state, before, g));
	const real_t eps = real_t(0.0005);
	Vector3 xp[4] = { x[0], x[1], x[2], x[3] };
	Vector3 xm[4] = { x[0], x[1], x[2], x[3] };
	xp[2].x += eps;
	xm[2].x -= eps;
	CHECK(evaluate(xp, rest, state, plus, h));
	CHECK(evaluate(xm, rest, state, minus, h));
	CHECK(double(g[2].x) ==
			doctest::Approx((plus - minus) / (2.0 * double(eps))).epsilon(0.005));
	CHECK((g[0] + g[1] + g[2] + g[3]).length() < real_t(1e-5));
}

TEST_CASE("[PhysicsFEM] SLS handles negative rest orientation") {
	PhysicsFEMTetraRest rest;
	const Vector3 x[4] = {
		Vector3(), Vector3(0, 1, 0),
		Vector3(1, 0, 0), Vector3(0, 0, 1)
	};
	CHECK(physics_fem_tetra_make_rest(x[0], x[1], x[2], x[3], rest));
	CHECK(rest.signed_det < 0.0);
	PhysicsFEMTetraSLSState state;
	Vector3 grad[4];
	double energy;
	CHECK(evaluate(x, rest, state, energy, grad));
	CHECK(energy == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] SLS rejects inverted tetra without advancing memory") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const Vector3 inverted[4] = {
		Vector3(), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, -1)
	};
	CHECK_FALSE(physics_fem_tetra_sls_relax(inverted, rest, 0.1, 0.05, state));
	CHECK(state.relaxing_strain[0][0] == 0.0);
}

TEST_CASE("[PhysicsFEM] SLS rejects invalid relaxation parameters atomically") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const Vector3 x[4] = {
		Vector3(), Vector3(real_t(1.3), 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	CHECK_FALSE(physics_fem_tetra_sls_relax(x, rest, -1, 0.02, state));
	CHECK_FALSE(physics_fem_tetra_sls_relax(x, rest, 0.1, -1, state));
	CHECK_FALSE(physics_fem_tetra_sls_relax(x, rest,
			std::numeric_limits<double>::quiet_NaN(), 0.02, state));
	CHECK(state.relaxing_strain[0][0] == 0.0);
}

TEST_CASE("[PhysicsFEM] SLS XPBD returns stretched tetra toward equilibrium") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	CHECK(physics_fem_tetra_sls_solve(a, b, c, d, 0, 1, 0, 0,
			rest, state, 0.3, 0.001, state.lambda));
	CHECK(b.x < real_t(1.5));
	CHECK(b.x > real_t(0.0));
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEM] SLS transient stiffness depends on XPBD compliance") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState hard, soft;
	Vector3 a, b(real_t(1.4), 0, 0), c(0, 1, 0), d(0, 0, 1);
	Vector3 sa = a, sb = b, sc = c, sd = d;
	CHECK(physics_fem_tetra_sls_solve(a, b, c, d, 0, 1, 0, 0,
			rest, hard, 0.3, 0.0, hard.lambda));
	CHECK(physics_fem_tetra_sls_solve(sa, sb, sc, sd, 0, 1, 0, 0,
			rest, soft, 0.3, 0.1, soft.lambda));
	CHECK(sb.x > b.x);
}

TEST_CASE("[PhysicsFEM] SLS at rest and fully pinned skip projection") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, 1);
	CHECK_FALSE(physics_fem_tetra_sls_solve(a, b, c, d, 1, 1, 1, 1,
			rest, state, 0.3, 0.001, state.lambda));
	b.x = real_t(1.5);
	CHECK_FALSE(physics_fem_tetra_sls_solve(a, b, c, d, 0, 0, 0, 0,
			rest, state, 0.3, 0.001, state.lambda));
}

} // namespace TestPhysicsFEMTetraStandardLinearSolid
