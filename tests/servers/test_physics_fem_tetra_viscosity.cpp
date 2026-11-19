/**************************************************************************/
/*  test_physics_fem_tetra_viscosity.cpp                                  */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_fem_tetra_viscosity.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_viscosity)

namespace TestPhysicsFEMTetraViscosity {

static const Vector3 A(0, 0, 0);
static const Vector3 B(1, 0, 0);
static const Vector3 C(0, 1, 0);
static const Vector3 D(0, 0, 1);

static PhysicsFEMTetraRest rest_tetra() {
	PhysicsFEMTetraRest result;
	physics_fem_tetra_make_rest(A, B, C, D, result);
	return result;
}

static double energy(const Vector3 *p_velocities, const real_t *p_inverse_masses) {
	double sum = 0.0;
	for (int i = 0; i < 4; ++i) {
		if (p_inverse_masses[i] != 0.0) {
			sum += double(p_velocities[i].length_squared()) / (2.0 * double(p_inverse_masses[i]));
		}
	}
	return sum;
}

TEST_CASE("[PhysicsFEMViscosity] Resting tetra and rigid translation have no viscosity") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 va(3, -4, 2), vb = va, vc = va, vd = va;
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, rest, 1.0));
	CHECK(va == Vector3(3, -4, 2));
	CHECK(vb == va);
	CHECK(vc == va);
	CHECK(vd == va);
}

TEST_CASE("[PhysicsFEMViscosity] Rigid angular motion preserves all velocities") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	// Omega=(0,0,2), v=Omega cross x. Symmetric Green-strain rate is zero.
	Vector3 va, vb(0, 2, 0), vc(-2, 0, 0), vd;
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, rest, 1.0));
	CHECK(va == Vector3());
	CHECK(vb == Vector3(0, 2, 0));
	CHECK(vc == Vector3(-2, 0, 0));
	CHECK(vd == Vector3());
}

TEST_CASE("[PhysicsFEMViscosity] Pure shear is damped and dissipates kinetic energy") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 va, vb, vc(4, 0, 0), vd;
	const real_t inverse_masses[4] = { 1, 1, 1, 1 };
	const Vector3 before[4] = { va, vb, vc, vd };
	const double before_energy = energy(before, inverse_masses);
	const Vector3 before_momentum = va + vb + vc + vd;
	const Vector3 before_angular = B.cross(vb) + C.cross(vc) + D.cross(vd);
	CHECK(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, rest, 1.0));
	const Vector3 after[4] = { va, vb, vc, vd };
	CHECK(energy(after, inverse_masses) < before_energy);
	CHECK((va + vb + vc + vd).is_equal_approx(before_momentum));
	CHECK((B.cross(vb) + C.cross(vc) + D.cross(vd)).is_equal_approx(before_angular));
	CHECK(Math::abs(vc.x - vb.y) < real_t(4.0));
}

TEST_CASE("[PhysicsFEMViscosity] Volume expansion rate is damped with unequal masses") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 va(-1, -1, -1), vb(1, 0, 0), vc(0, 1, 0), vd(0, 0, 1);
	const real_t inv[4] = { 0.5, 1, 2, 3 };
	const Vector3 before[4] = { va, vb, vc, vd };
	const double initial = energy(before, inv);
	const Vector3 momentum = va / inv[0] + vb / inv[1] + vc / inv[2] + vd / inv[3];
	CHECK(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			inv[0], inv[1], inv[2], inv[3], rest, 0.8));
	const Vector3 after[4] = { va, vb, vc, vd };
	CHECK(energy(after, inv) < initial);
	CHECK((va / inv[0] + vb / inv[1] + vc / inv[2] + vd / inv[3]).is_equal_approx(momentum));
}

TEST_CASE("[PhysicsFEMViscosity] Pinned vertices remain fixed") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 va(0, 0, 0), vb(3, 0, 0), vc, vd;
	const real_t inv[4] = { 0, 1, 1, 1 };
	const Vector3 old[4] = { va, vb, vc, vd };
	const double before = energy(old, inv);
	CHECK(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			inv[0], inv[1], inv[2], inv[3], rest, 0.7));
	const Vector3 next[4] = { va, vb, vc, vd };
	CHECK(va == Vector3());
	CHECK(energy(next, inv) <= before);
	CHECK(vb.x < real_t(3.0));
}

TEST_CASE("[PhysicsFEMViscosity] No inverse masses or zero coefficient means no write") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 va, vb(2, 0, 0), vc, vd;
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			0, 0, 0, 0, rest, 1.0));
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			1, 1, 1, 1, rest, 0.0));
	CHECK(vb == Vector3(2, 0, 0));
}

TEST_CASE("[PhysicsFEMViscosity] Invalid, inverted and singular inputs are transactional") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 va, vb(2, 0, 0), vc, vd;
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			1, 1, 1, 1, rest, -1.0));
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			1, 1, 1, 1, rest, 1.01));
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			1, -1, 1, 1, rest, 0.7));
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, Vector3(0, 0, -1), va, vb, vc, vd,
			1, 1, 1, 1, rest, 0.7));
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, C, va, vb, vc, vd,
			1, 1, 1, 1, rest, 0.7));
	CHECK_FALSE(physics_fem_tetra_damp_strain_rate(A, B, C, D, va, vb, vc, vd,
			1, 1, 1, 1, rest, std::numeric_limits<double>::infinity()));
	CHECK(va == Vector3());
	CHECK(vb == Vector3(2, 0, 0));
	CHECK(vc == Vector3());
	CHECK(vd == Vector3());
}

} // namespace TestPhysicsFEMTetraViscosity
