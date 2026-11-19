/**************************************************************************/
/*  test_physics_softbody_hydrostatic_buoyancy.cpp                        */
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

#include "servers/physics_softbody_hydrostatic_buoyancy.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_hydrostatic_buoyancy)

namespace TestPhysicsSoftBodyHydrostaticBuoyancy {

static Vector3 tetra_force(real_t p_water, real_t p_density, real_t p_g, int p_winding, real_t p_shift = 0.0) {
	const Vector3 vertices[4] = {
		Vector3(0, 0 + p_shift, 0), Vector3(1, 0 + p_shift, 0),
		Vector3(0, 1 + p_shift, 0), Vector3(0, 0 + p_shift, 1)
	};
	const int faces[4][3] = { { 0, 2, 1 }, { 0, 1, 3 }, { 0, 3, 2 }, { 1, 2, 3 } };
	Vector3 total;
	for (int j = 0; j < 4; ++j) {
		Vector3 a, b, c;
		const bool success = physics_softbody_hydrostatic_face_forces(
				vertices[faces[j][0]], vertices[faces[j][1]], vertices[faces[j][2]],
				p_water + p_shift, p_density, p_g, p_winding, a, b, c);
		CHECK(success);
		total += a + b + c;
	}
	return total;
}

TEST_CASE("[PhysicsHydrostaticSoft] Fully submerged tetrahedron satisfies Archimedes law") {
	const Vector3 force = tetra_force(real_t(2.0), real_t(1000.0), real_t(9.8), 1);
	CHECK(force.x == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(force.z == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(force.y == doctest::Approx(1000.0 * 9.8 / 6.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsHydrostaticSoft] Partial immersion integrates clipped displaced volume") {
	// Tetrahedron with y in [0,1]: submerged volume fraction = 1 - (1-h)^3.
	const Vector3 force = tetra_force(real_t(0.5), real_t(1000.0), real_t(9.8), 1);
	const real_t expected = real_t(1000.0 * 9.8 * 7.0 / 48.0);
	CHECK(force.y == doctest::Approx(expected).epsilon(1e-5));
	CHECK(force.x == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(force.z == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsHydrostaticSoft] Dry tetrahedron has zero buoyant force") {
	CHECK(tetra_force(real_t(-1.0), real_t(1000.0), real_t(9.8), 1) == Vector3());
}

TEST_CASE("[PhysicsHydrostaticSoft] Surface pressure is barycentrically distributed") {
	const Vector3 a(0, -1, 0), b(1, -1, 0), c(0, -1, 1);
	Vector3 fa, fb, fc;
	CHECK(physics_softbody_hydrostatic_face_forces(a, b, c, 0.0, 1000.0, 10.0, 1, fa, fb, fc));
	CHECK(fa.y == doctest::Approx(10000.0 / 6.0).epsilon(1e-5));
	CHECK(fb.y == doctest::Approx(fa.y).epsilon(1e-5));
	CHECK(fc.y == doctest::Approx(fa.y).epsilon(1e-5));
	CHECK((fa + fb + fc).y == doctest::Approx(5000.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsHydrostaticSoft] Translation and reversed mesh winding") {
	const Vector3 base = tetra_force(real_t(0.5), 1000.0, 9.8, 1);
	const Vector3 shifted = tetra_force(real_t(0.5), 1000.0, 9.8, 1, 200.0);
	CHECK(base.is_equal_approx(shifted));
	// The caller must reverse all faces as well as set -1 for the winding.
	const Vector3 a(0, -1, 0), b(1, -1, 0), c(0, -1, 1);
	Vector3 fa, fb, fc, reverse_a, reverse_b, reverse_c;
	CHECK(physics_softbody_hydrostatic_face_forces(a, b, c, 0, 1, 10, 1, fa, fb, fc));
	CHECK(physics_softbody_hydrostatic_face_forces(a, c, b, 0, 1, 10, -1,
			reverse_a, reverse_b, reverse_c));
	CHECK((fa + fb + fc).is_equal_approx(reverse_a + reverse_b + reverse_c));
}

TEST_CASE("[PhysicsHydrostaticSoft] Invalid and degenerate faces do not mutate outputs") {
	Vector3 fa(1, 2, 3), fb(4, 5, 6), fc(7, 8, 9);
	const Vector3 original_a = fa, original_b = fb, original_c = fc;
	const Vector3 a, b(1, 0, 0), c(2, 0, 0);
	CHECK_FALSE(physics_softbody_hydrostatic_face_forces(a, b, c, 0, 1000, 9.8, 1, fa, fb, fc));
	CHECK_FALSE(physics_softbody_hydrostatic_face_forces(a, b, Vector3(0, 1, 0),
			0, -1, 9.8, 1, fa, fb, fc));
	CHECK_FALSE(physics_softbody_hydrostatic_face_forces(a, b, Vector3(0, 1, 0),
			0, 1000, 9.8, 0, fa, fb, fc));
	CHECK_FALSE(physics_softbody_hydrostatic_face_forces(a, b, Vector3(0, 1, 0),
			std::numeric_limits<real_t>::infinity(), 1000, 9.8, 1, fa, fb, fc));
	CHECK_FALSE(physics_softbody_hydrostatic_face_forces(Vector3(0, real_t(-1e20), 0),
			Vector3(real_t(1e20), real_t(-1e20), 0),
			Vector3(0, real_t(-1e20), real_t(1e20)),
			0, real_t(1e20), 10, 1, fa, fb, fc));
	CHECK(fa == original_a);
	CHECK(fb == original_b);
	CHECK(fc == original_c);
}

TEST_CASE("[PhysicsHydrostaticSoft] Zero density and gravity produce no pressure") {
	Vector3 fa, fb, fc;
	const Vector3 a(0, -1, 0), b(1, -1, 0), c(0, -1, 1);
	CHECK(physics_softbody_hydrostatic_face_forces(a, b, c, 0, 0, 10, 1, fa, fb, fc));
	CHECK(fa == Vector3());
	CHECK(fb == Vector3());
	CHECK(fc == Vector3());
	CHECK(physics_softbody_hydrostatic_face_forces(a, b, c, 0, 1000, 0, 1, fa, fb, fc));
	CHECK(fa == Vector3());
}

} // namespace TestPhysicsSoftBodyHydrostaticBuoyancy
