/**************************************************************************/
/*  test_physics_softbody_dihedral_damping.cpp                            */
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

#include "servers/physics_softbody_dihedral_damping.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_dihedral_damping)

namespace TestPhysicsSoftBodyDihedralDamping {

static const Vector3 A(-1, 0, 0);
static const Vector3 B(1, 0, 0);
static const Vector3 C(0, 1, 0);
static const Vector3 D(0, 0, 1);

// Independently compute the signed hinge Jacobian to verify damping rates.
// A separate finite-difference angle check below catches sign mistakes.
static double angular_rate(const Vector3 &p_va, const Vector3 &p_vb,
		const Vector3 &p_vc, const Vector3 &p_vd) {
	const Vector3 edge = B - A;
	const Vector3 nc = edge.cross(C - A);
	const Vector3 nd = (D - A).cross(edge);
	const real_t length = edge.length();
	const Vector3 gc = nc * (-length / nc.length_squared());
	const Vector3 gd = nd * (-length / nd.length_squared());
	const Vector3 ga = gc * ((C - B).dot(edge) / edge.length_squared()) +
			gd * ((D - B).dot(edge) / edge.length_squared());
	const Vector3 gb = gc * ((A - C).dot(edge) / edge.length_squared()) +
			gd * ((A - D).dot(edge) / edge.length_squared());
	return double(ga.dot(p_va)) + double(gb.dot(p_vb)) +
			double(gc.dot(p_vc)) + double(gd.dot(p_vd));
}

TEST_CASE("[PhysicsDihedralDamping] Full angular damping removes bending velocity") {
	Vector3 va, vb, vc(0, 0, 5), vd(0, 4, 0);
	const double before = angular_rate(va, vb, vc, vd);
	CHECK(Math::abs(before) > 1.0);
	CHECK(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, 1.0));
	CHECK(Math::abs(angular_rate(va, vb, vc, vd)) < 1e-5);

	// Also test the actual change of the signed dihedral, not just the
	// analytical Jacobian used by the damping projection.
	const auto signed_angle = [](const Vector3 &p_a, const Vector3 &p_b,
			const Vector3 &p_c, const Vector3 &p_d) {
		const Vector3 edge = (p_b - p_a).normalized();
		const Vector3 nc = (p_b - p_a).cross(p_c - p_a).normalized();
		const Vector3 nd = (p_d - p_a).cross(p_b - p_a).normalized();
		return Math::atan2(edge.dot(nc.cross(nd)), nc.dot(nd));
	};
	const real_t h = real_t(0.0001);
	const double start_angle = signed_angle(A, B, C, D);
	const double end_angle = signed_angle(A + va * h, B + vb * h, C + vc * h, D + vd * h);
	const double angle_delta = Math::atan2(Math::sin(end_angle - start_angle), Math::cos(end_angle - start_angle));
	CHECK(Math::abs(angle_delta / h) < 0.01);
}

TEST_CASE("[PhysicsDihedralDamping] Damping removes kinetic energy and conserves momentum") {
	Vector3 va(1, 2, 0), vb(3, -2, 0), vc(0, 0, 5), vd(0, 4, 0);
	const Vector3 momentum = va + vb / 2.0 + vc * 2.0 + vd / 1.5;
	const double energy_before = 0.5 * (double(va.length_squared()) +
			double(vb.length_squared()) / 2.0 + double(vc.length_squared()) * 2.0 +
			double(vd.length_squared()) / 1.5);
	const double angular_before = angular_rate(va, vb, vc, vd);
	CHECK(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			1.0, 2.0, 0.5, 1.5, 0.45));
	CHECK(angular_rate(va, vb, vc, vd) == doctest::Approx(angular_before * 0.55).epsilon(1e-5));
	CHECK((va + vb / 2.0 + vc * 2.0 + vd / 1.5).is_equal_approx(momentum));
	const double energy_after = 0.5 * (double(va.length_squared()) +
			double(vb.length_squared()) / 2.0 + double(vc.length_squared()) * 2.0 +
			double(vd.length_squared()) / 1.5);
	CHECK(energy_after <= energy_before + 1e-5);
}

TEST_CASE("[PhysicsDihedralDamping] Pinned hinge vertices remain at rest") {
	Vector3 va, vb, vc, vd(0, 7, 0);
	CHECK(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			0.0, 0.0, 0.0, 1.0, 1.0));
	CHECK(va == Vector3());
	CHECK(vb == Vector3());
	CHECK(vc == Vector3());
	CHECK(Math::abs(angular_rate(va, vb, vc, vd)) < 1e-5);
}

TEST_CASE("[PhysicsDihedralDamping] Rigid translation and rotation are unaffected") {
	const Vector3 omega(0.25, -0.1, 0.35);
	const Vector3 translation(2, 3, -1);
	Vector3 va = omega.cross(A) + translation;
	Vector3 vb = omega.cross(B) + translation;
	Vector3 vc = omega.cross(C) + translation;
	Vector3 vd = omega.cross(D) + translation;
	const Vector3 old_va = va, old_vb = vb, old_vc = vc, old_vd = vd;
	CHECK(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, 1.0));
	CHECK(va.is_equal_approx(old_va));
	CHECK(vb.is_equal_approx(old_vb));
	CHECK(vc.is_equal_approx(old_vc));
	CHECK(vd.is_equal_approx(old_vd));
}

TEST_CASE("[PhysicsDihedralDamping] Two half relaxations equal one three-quarter relaxation") {
	Vector3 a1, b1, c1(0, 0, 8), d1(0, 6, 0);
	Vector3 a2 = a1, b2 = b1, c2 = c1, d2 = d1;
	CHECK(physics_softbody_damp_dihedral(A, B, C, D, a1, b1, c1, d1,
			1.0, 1.0, 1.0, 1.0, 0.5));
	CHECK(physics_softbody_damp_dihedral(A, B, C, D, a1, b1, c1, d1,
			1.0, 1.0, 1.0, 1.0, 0.5));
	CHECK(physics_softbody_damp_dihedral(A, B, C, D, a2, b2, c2, d2,
			1.0, 1.0, 1.0, 1.0, 0.75));
	CHECK(a1.is_equal_approx(a2));
	CHECK(b1.is_equal_approx(b2));
	CHECK(c1.is_equal_approx(c2));
	CHECK(d1.is_equal_approx(d2));
}

TEST_CASE("[PhysicsDihedralDamping] Degenerate and invalid inputs are transactional") {
	Vector3 va, vb, vc(0, 0, 2), vd(0, 4, 0);
	const Vector3 old_va = va, old_vb = vb, old_vc = vc, old_vd = vd;
	CHECK_FALSE(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			0.0, 0.0, 0.0, 0.0, 1.0));
	CHECK_FALSE(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, -0.5));
	CHECK_FALSE(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, 1.1));
	CHECK_FALSE(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			-1.0, 1.0, 1.0, 1.0, 1.0));
	CHECK_FALSE(physics_softbody_damp_dihedral(A, B, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, std::numeric_limits<double>::infinity()));
	CHECK_FALSE(physics_softbody_damp_dihedral(A, A, C, D, va, vb, vc, vd,
			1.0, 1.0, 1.0, 1.0, 1.0));
	CHECK(va == old_va);
	CHECK(vb == old_vb);
	CHECK(vc == old_vc);
	CHECK(vd == old_vd);
}

} // namespace TestPhysicsSoftBodyDihedralDamping
