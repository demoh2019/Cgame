/**************************************************************************/
/*  test_physics_softbody_area_rate_damping.cpp                            */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_softbody_area_rate_damping.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_area_rate_damping)

namespace TestPhysicsSoftBodyAreaRateDamping {

static Vector3 a(0, 0, 0);
static Vector3 b(1, 0, 0);
static Vector3 c(0, 1, 0);

// Independent analytical rate for the standard unit-right triangle.
static double area_rate(const Vector3 &p_va, const Vector3 &p_vb, const Vector3 &p_vc) {
	return 0.5 * (double(p_vb.x) + double(p_vc.y) -
			double(p_va.x) - double(p_va.y));
}

TEST_CASE("[PhysicsSoftAreaDamping] Fraction 0.5 halves triangle area-change velocity") {
	Vector3 va, vb(2, 0, 0), vc;
	const Vector3 original_a = a, original_b = b, original_c = c;
	const double before = area_rate(va, vb, vc);
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			1, 1, 1, 0.5));
	CHECK(before == doctest::Approx(1.0));
	CHECK(area_rate(va, vb, vc) == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(a == original_a);
	CHECK(b == original_b);
	CHECK(c == original_c);
}

TEST_CASE("[PhysicsSoftAreaDamping] Fraction 1 stops area oscillation without freezing particles") {
	Vector3 va, vb(2, 0, 0), vc;
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			1, 1, 1, 1.0));
	CHECK(area_rate(va, vb, vc) == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(vb.x > 0);
	CHECK(va.length_squared() > 0);
}

TEST_CASE("[PhysicsSoftAreaDamping] Uniform translation causes zero damping") {
	const Vector3 v(5, -3, 2);
	Vector3 va(v), vb(v), vc(v);
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			1, 1, 1, 0.9));
	CHECK(va == v);
	CHECK(vb == v);
	CHECK(vc == v);
}

TEST_CASE("[PhysicsSoftAreaDamping] Pure angular rigid motion causes zero damping") {
	// Omega = (0,0,3): v=omega cross position.
	Vector3 va, vb(0, 3, 0), vc(-3, 0, 0);
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			1, 1, 1, 0.9));
	CHECK(va == Vector3());
	CHECK(vb == Vector3(0, 3, 0));
	CHECK(vc == Vector3(-3, 0, 0));
}

TEST_CASE("[PhysicsSoftAreaDamping] Exactly pinned vertices keep their velocities") {
	Vector3 va, vb(2, 0, 0), vc;
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			0, 1, 1, 0.5));
	CHECK(va == Vector3());
	CHECK(area_rate(va, vb, vc) == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(vb.x < 2.0);
}

TEST_CASE("[PhysicsSoftAreaDamping] All-pinned triangle and invalid fraction do not mutate") {
	Vector3 va(1, 0, 0), vb(2, 0, 0), vc(3, 0, 0);
	const Vector3 old_a = va, old_b = vb, old_c = vc;
	CHECK_FALSE(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			0, 0, 0, 0.5));
	CHECK_FALSE(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			1, 1, 1, 0.0));
	CHECK_FALSE(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			1, 1, 1, 1.1));
	CHECK(va == old_a);
	CHECK(vb == old_b);
	CHECK(vc == old_c);
}

TEST_CASE("[PhysicsSoftAreaDamping] Unequal masses preserve total linear momentum") {
	Vector3 va(1, -1, 0), vb(3, 1, 0), vc(-2, 4, 0);
	const real_t wa = 1, wb = real_t(0.5), wc = real_t(0.25);
	const Vector3 initial = va / wa + vb / wb + vc / wc;
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			wa, wb, wc, 0.75));
	const Vector3 final_momentum = va / wa + vb / wb + vc / wc;
	CHECK(initial.is_equal_approx(final_momentum));
}

TEST_CASE("[PhysicsSoftAreaDamping] Unequal masses preserve angular momentum") {
	Vector3 va(1, -1, 0), vb(3, 1, 0), vc(-2, 4, 0);
	const real_t wa = 1, wb = real_t(0.5), wc = real_t(0.25);
	const Vector3 angular_initial = a.cross(va / wa) + b.cross(vb / wb) + c.cross(vc / wc);
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			wa, wb, wc, 0.75));
	const Vector3 angular_final = a.cross(va / wa) + b.cross(vb / wb) + c.cross(vc / wc);
	CHECK(angular_initial.is_equal_approx(angular_final));
}

TEST_CASE("[PhysicsSoftAreaDamping] Kinetic energy cannot increase for isolated viscous impulse") {
	Vector3 va(1, -1, 0), vb(3, 1, 0), vc(-2, 4, 0);
	const real_t wa = 1, wb = real_t(0.5), wc = real_t(0.25);
	const double initial = 0.5 * (double(va.length_squared()) / wa +
			double(vb.length_squared()) / wb + double(vc.length_squared()) / wc);
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc,
			wa, wb, wc, 0.75));
	const double final_energy = 0.5 * (double(va.length_squared()) / wa +
			double(vb.length_squared()) / wb + double(vc.length_squared()) / wc);
	CHECK(final_energy < initial);
}

TEST_CASE("[PhysicsSoftAreaDamping] Face winding and triangle translation are invariant") {
	Vector3 va, vb(2, 0, 0), vc;
	Vector3 reversed_va, reversed_vc, reversed_vb(2, 0, 0);
	Vector3 translated_va, translated_vb(2, 0, 0), translated_vc;
	CHECK(physics_softbody_damp_triangle_area_rate(a, b, c, va, vb, vc, 1, 1, 1, 0.5));
	CHECK(physics_softbody_damp_triangle_area_rate(a, c, b, reversed_va, reversed_vc,
			reversed_vb, 1, 1, 1, 0.5));
	const Vector3 translation(1000, -2000, 3000);
	CHECK(physics_softbody_damp_triangle_area_rate(a + translation,
			b + translation, c + translation,
			translated_va, translated_vb, translated_vc, 1, 1, 1, 0.5));
	CHECK(va.is_equal_approx(reversed_va));
	CHECK(vb.is_equal_approx(reversed_vb));
	CHECK(vc.is_equal_approx(reversed_vc));
	CHECK(va.is_equal_approx(translated_va));
	CHECK(vb.is_equal_approx(translated_vb));
	CHECK(vc.is_equal_approx(translated_vc));
}

TEST_CASE("[PhysicsSoftAreaDamping] Microscopic triangles are scale independent") {
	const real_t scale = real_t(0.000001);
	Vector3 va, vb(2, 0, 0), vc;
	CHECK(physics_softbody_damp_triangle_area_rate(a * scale, b * scale, c * scale,
			va, vb, vc, 1, 1, 1, 0.5));
	CHECK(va.x == doctest::Approx(0.25).epsilon(1e-5));
	CHECK(vb.x == doctest::Approx(1.75).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftAreaDamping] Degenerate and nonfinite geometry fail atomically") {
	Vector3 va(1, 0, 0), vb(2, 0, 0), vc(3, 0, 0);
	const Vector3 old_va = va, old_vb = vb, old_vc = vc;
	const real_t inf = std::numeric_limits<real_t>::infinity();
	CHECK_FALSE(physics_softbody_damp_triangle_area_rate(a, b, b * 2.0,
			va, vb, vc, 1, 1, 1, 0.5));
	CHECK_FALSE(physics_softbody_damp_triangle_area_rate(a, b, c,
			va, vb, vc, -1, 1, 1, 0.5));
	CHECK_FALSE(physics_softbody_damp_triangle_area_rate(Vector3(inf, 0, 0), b, c,
			va, vb, vc, 1, 1, 1, 0.5));
	CHECK_FALSE(physics_softbody_damp_triangle_area_rate(a, b, c,
			va, vb, vc, 1, 1, 1, std::numeric_limits<double>::quiet_NaN()));
	CHECK(va == old_va);
	CHECK(vb == old_vb);
	CHECK(vc == old_vc);
}

TEST_CASE("[PhysicsSoftAreaDamping] Negative damping parameters are rejected") {
	Vector3 va, vb(2, 0, 0), vc;
	CHECK_FALSE(physics_softbody_damp_triangle_area_rate(a, b, c,
			va, vb, vc, 1, 1, 1, -1.0));
	CHECK(vb == Vector3(2, 0, 0));
}

} // namespace TestPhysicsSoftBodyAreaRateDamping
