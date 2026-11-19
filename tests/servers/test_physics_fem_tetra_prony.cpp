/**************************************************************************/
/*  test_physics_fem_tetra_prony.cpp                                */
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

#include "servers/physics_fem_tetra_prony.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_prony)

namespace TestPhysicsFEMTetraProny {

static PhysicsFEMTetraRest unit_rest() {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest));
	return rest;
}

static bool evaluate(const Vector3 (&p_x)[4], const PhysicsFEMTetraRest &p_rest,
		const PhysicsFEMTetraSLSState *const p_arms[3],
		const double p_compliances[3], double &r_energy, Vector3 (&r_grad)[4]) {
	return physics_fem_tetra_prony_energy_gradient(p_x[0], p_x[1], p_x[2],
			p_x[3], p_rest, p_arms, p_compliances, 0.3, r_energy,
			r_grad[0], r_grad[1], r_grad[2], r_grad[3]);
}

TEST_CASE("[PhysicsFEM] Prony all three branches at rest have zero energy") {
	PhysicsFEMTetraPronyState multi;
	PhysicsFEMTetraSLSState base;
	const PhysicsFEMTetraSLSState *arms[3] = { &base, &multi.fast, &multi.slow };
	const double comp[3] = { 0.01, 0.02, 0.03 };
	const Vector3 x[4] = { Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	double energy = -1.0;
	Vector3 grads[4];
	CHECK(evaluate(x, unit_rest(), arms, comp, energy, grads));
	CHECK(energy == doctest::Approx(0.0));
	for (const Vector3 &g : grads) {
		CHECK(g.length() < real_t(1e-6));
	}
}

TEST_CASE("[PhysicsFEM] Prony weighted branches add energy and analytic forces") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState states;
	PhysicsFEMTetraSLSState base;
	states.fast.relaxing_strain[0][0] = 0.08;
	states.slow.relaxing_strain[0][0] = 0.2;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.4), 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	const PhysicsFEMTetraSLSState *arms[3] = { &base, &states.fast, &states.slow };
	const double comp[3] = { 0.01, 0.03, 0.05 };
	Vector3 gradients[4];
	double energy = 0.0;
	CHECK(evaluate(x, rest, arms, comp, energy, gradients));
	double expected_energy = 0.0;
	Vector3 expected_g[4] = { Vector3(), Vector3(), Vector3(), Vector3() };
	for (int i = 0; i < 3; ++i) {
		double single_energy;
		Vector3 g0, g1, g2, g3;
		CHECK(physics_fem_tetra_sls_energy_gradient(x[0], x[1], x[2], x[3],
				rest, *arms[i], 0.3, single_energy, g0, g1, g2, g3));
		expected_energy += single_energy / comp[i];
		const Vector3 g[4] = { g0, g1, g2, g3 };
		for (int v = 0; v < 4; ++v) {
			expected_g[v] += g[v] / real_t(comp[i]);
		}
	}
	CHECK(energy == doctest::Approx(expected_energy).epsilon(1e-5));
	for (int i = 0; i < 4; ++i) {
		CHECK((gradients[i] - expected_g[i]).length() < real_t(0.001));
	}
}

TEST_CASE("[PhysicsFEM] Prony relaxes its fast arm earlier than its slow arm") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.5), 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	CHECK(physics_fem_tetra_prony_relax(x, rest, true, 0.03, true, 2.0, 0.05, state));
	const double target = (1.5 * 1.5 - 1.0) / 2.0;
	CHECK(state.fast.relaxing_strain[0][0] >
			state.slow.relaxing_strain[0][0]);
	CHECK(state.fast.relaxing_strain[0][0] ==
			doctest::Approx(target * (1 - std::exp(-0.05 / 0.03))).epsilon(1e-5));
	CHECK(state.slow.relaxing_strain[0][0] ==
			doctest::Approx(target * (1 - std::exp(-0.05 / 2.0))).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Prony fixed strain relaxation yields two exponential decays") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.45), 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	const PhysicsFEMTetraSLSState *arms[3] = { nullptr, &state.fast, &state.slow };
	const double comp[3] = { 0.0, 0.01, 0.01 };
	Vector3 grads[4];
	double before, after;
	CHECK(evaluate(x, rest, arms, comp, before, grads));
	CHECK(physics_fem_tetra_prony_relax(x, rest, true, 0.05, true, 1.0, 0.1, state));
	CHECK(evaluate(x, rest, arms, comp, after, grads));
	CHECK(after == doctest::Approx(
			0.5 * before * (std::exp(-4.0) + std::exp(-0.2))).epsilon(1e-4));
	CHECK(after < before);
}

TEST_CASE("[PhysicsFEM] Prony time subdivision does not change fixed-strain memory") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState single, divided;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.3), real_t(0.12), 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	CHECK(physics_fem_tetra_prony_relax(x, rest, true, 0.02, true, 3.0, 0.12, single));
	for (int i = 0; i < 6; ++i) {
		CHECK(physics_fem_tetra_prony_relax(x, rest, true, 0.02, true, 3.0, 0.02, divided));
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			CHECK(single.fast.relaxing_strain[i][j] ==
					doctest::Approx(divided.fast.relaxing_strain[i][j]).epsilon(1e-9));
			CHECK(single.slow.relaxing_strain[i][j] ==
					doctest::Approx(divided.slow.relaxing_strain[i][j]).epsilon(1e-9));
		}
	}
}

TEST_CASE("[PhysicsFEM] Prony single branch matches old SLS elastic projection") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraSLSState state;
	const PhysicsFEMTetraSLSState *arms[3] = { &state, nullptr, nullptr };
	const double comp[3] = { 0.02, 0.0, 0.0 };
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	Vector3 pa=a, pb=b, pc=c, pd=d;
	double l0=0.0, l1=0.0;
	const double dt=0.02;
	CHECK(physics_fem_tetra_sls_solve(a, b, c, d, 0, 1, 0, 0,
			rest, state, 0.3, comp[0] / (dt * dt), l0));
	CHECK(physics_fem_tetra_prony_solve(pa, pb, pc, pd, 0, 1, 0, 0,
			rest, arms, comp, 0.3, dt, l1));
	CHECK(pa.x == doctest::Approx(a.x).epsilon(1e-5));
	CHECK(pb.x == doctest::Approx(b.x).epsilon(1e-5));
	CHECK(pc.y == doctest::Approx(c.y).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Prony combined XPBD maintains pins and reduces energy") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const PhysicsFEMTetraSLSState *arms[3] = { nullptr, &state.fast, &state.slow };
	const double comp[3] = { 0.0, 0.005, 0.02 };
	Vector3 a, b(real_t(1.35), 0, 0), c(0, 1, 0), d(0, 0, 1);
	Vector3 g[4];
	const Vector3 x[4] = {a,b,c,d};
	double before, after;
	CHECK(evaluate(x, rest, arms, comp, before, g));
	CHECK(physics_fem_tetra_prony_solve(a, b, c, d,
			0, 1, 0, 0, rest, arms, comp, 0.3, 0.02, state.lambda));
	const Vector3 y[4] = {a,b,c,d};
	CHECK(evaluate(y, rest, arms, comp, after, g));
	CHECK(after < before);
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEM] Prony analytical summed force matches finite differences") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.17), real_t(0.14), 0),
			Vector3(real_t(0.11), real_t(0.92), 0), Vector3(0, 0, real_t(1.05)) };
	CHECK(physics_fem_tetra_prony_relax(x, rest, true, 0.1, true, 1.0, 0.03, state));
	const PhysicsFEMTetraSLSState *arms[3] = { nullptr, &state.fast, &state.slow };
	const double comp[3] = { 0.0, 0.01, 0.05 };
	double energy, plus, minus;
	Vector3 gradients[4], scratch[4];
	CHECK(evaluate(x, rest, arms, comp, energy, gradients));
	const real_t epsilon = real_t(0.0005);
	const Vector3 xp[4] = { x[0], Vector3(x[1].x + epsilon, x[1].y, x[1].z), x[2], x[3] };
	const Vector3 xm[4] = { x[0], Vector3(x[1].x - epsilon, x[1].y, x[1].z), x[2], x[3] };
	CHECK(evaluate(xp, rest, arms, comp, plus, scratch));
	CHECK(evaluate(xm, rest, arms, comp, minus, scratch));
	CHECK(double(gradients[1].x) ==
			doctest::Approx((plus-minus)/(2.0*double(epsilon))).epsilon(0.005));
	CHECK((gradients[0]+gradients[1]+gradients[2]+gradients[3]).length() < real_t(0.001));
}

TEST_CASE("[PhysicsFEM] Prony gradient transforms under rigid world rotation") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.3), 0, 0),
			Vector3(real_t(0.2), 1, 0), Vector3(0, 0, 1) };
	CHECK(physics_fem_tetra_prony_relax(x, rest, true, 0.1, true, 1.0, 0.03, state));
	const PhysicsFEMTetraSLSState *arms[3] = { nullptr, &state.fast, &state.slow };
	const double comp[3] = { 0.0, 0.01, 0.1 };
	Vector3 original_g[4], rotated_g[4], rotated_x[4];
	double first, rotated;
	CHECK(evaluate(x, rest, arms, comp, first, original_g));
	for (int i = 0; i < 4; ++i) {
		rotated_x[i] = Vector3(real_t(20)-x[i].y, real_t(10)+x[i].x, x[i].z);
	}
	CHECK(evaluate(rotated_x, rest, arms, comp, rotated, rotated_g));
	CHECK(first == doctest::Approx(rotated).epsilon(1e-5));
	for (int i = 0; i < 4; ++i) {
		CHECK(rotated_g[i].x == doctest::Approx(-original_g[i].y).epsilon(0.001));
		CHECK(rotated_g[i].y == doctest::Approx(original_g[i].x).epsilon(0.001));
	}
}

TEST_CASE("[PhysicsFEM] Prony disabled second arm remains untouched") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.5), 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	CHECK(physics_fem_tetra_prony_relax(x, rest, true, 0.1, false, 0.0, 0.03, state));
	CHECK(state.fast.relaxing_strain[0][0] > 0.0);
	CHECK(state.slow.relaxing_strain[0][0] == 0.0);
}

TEST_CASE("[PhysicsFEM] Prony rejects invalid slow arm atomically") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.5), 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	CHECK_FALSE(physics_fem_tetra_prony_relax(x, rest,
			true, 0.1, true, -2.0, 0.03, state));
	CHECK(state.fast.relaxing_strain[0][0] == 0.0);
	CHECK(state.slow.relaxing_strain[0][0] == 0.0);
}

TEST_CASE("[PhysicsFEM] Prony unloaded memory creates reverse stress") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 stretched[4] = { Vector3(), Vector3(real_t(1.5), 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	const Vector3 rest_x[4] = { Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	CHECK(physics_fem_tetra_prony_relax(stretched, rest, true, 0.03, true, 2.0, 0.1, state));
	const PhysicsFEMTetraSLSState *arms[3] = { nullptr, &state.fast, &state.slow };
	const double comp[3] = { 0.0, 0.02, 0.02 };
	Vector3 g[4];
	double energy;
	CHECK(evaluate(rest_x, rest, arms, comp, energy, g));
	CHECK(energy > 0.0);
	CHECK(g[1].x < 0.0);
}

TEST_CASE("[PhysicsFEM] Prony inverse tetra rest winding is supported") {
	PhysicsFEMTetraRest rest;
	const Vector3 x[4] = { Vector3(), Vector3(0, 1, 0),
			Vector3(1, 0, 0), Vector3(0, 0, 1) };
	CHECK(physics_fem_tetra_make_rest(x[0], x[1], x[2], x[3], rest));
	CHECK(rest.signed_det < 0.0);
	PhysicsFEMTetraPronyState state;
	const PhysicsFEMTetraSLSState *arms[3] = { nullptr, &state.fast, nullptr };
	const double comp[3] = { 0.0, 0.01, 0.0 };
	Vector3 g[4];
	double energy;
	CHECK(evaluate(x, rest, arms, comp, energy, g));
	CHECK(energy == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Prony rejects inverted tetra without advancing histories") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 flipped[4] = { Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, -1) };
	CHECK_FALSE(physics_fem_tetra_prony_relax(flipped, rest,
			true, 0.1, true, 1.0, 0.1, state));
	CHECK(state.fast.relaxing_strain[0][0] == 0.0);
	CHECK(state.slow.relaxing_strain[0][0] == 0.0);
}

TEST_CASE("[PhysicsFEM] Prony invalid compliance leaves energy output unchanged") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.4), 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1) };
	const PhysicsFEMTetraSLSState *arms[3] = { nullptr, &state.fast, &state.slow };
	const double comp[3] = { 0.0, 0.01, -1.0 };
	Vector3 g[4];
	double energy = 999.0;
	CHECK_FALSE(evaluate(x, rest, arms, comp, energy, g));
	CHECK(energy == 999.0);
}

TEST_CASE("[PhysicsFEM] Prony projection does not move fully pinned tetra") {
	const PhysicsFEMTetraRest rest = unit_rest();
	PhysicsFEMTetraPronyState state;
	const PhysicsFEMTetraSLSState *arms[3] = { nullptr, &state.fast, &state.slow };
	const double comp[3] = { 0.0, 0.01, 0.03 };
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	CHECK_FALSE(physics_fem_tetra_prony_solve(a, b, c, d,
			0, 0, 0, 0, rest, arms, comp, 0.3, 0.02, state.lambda));
	CHECK(b == Vector3(real_t(1.5), 0, 0));
}

} // namespace TestPhysicsFEMTetraProny
