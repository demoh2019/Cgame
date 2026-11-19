/**************************************************************************/
/*  test_physics_xpbd_rod_torsion.cpp                                     */
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

#include "servers/physics_xpbd_rod_torsion.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_rod_torsion)

namespace TestPhysicsXPBDRodTorsion {

static void _get_rest_vertices(Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d) {
	r_a = Vector3(-1.0, 0.0, 0.0);
	r_b = Vector3(0.0, 0.0, 0.0);
	r_c = Vector3(1.0, 1.0, 0.0);
	r_d = Vector3(2.0, 1.1, 0.5);
}

TEST_CASE("[PhysicsXPBD] Four-point torsion equals central hinge dihedral") {
	Vector3 a, b, c, d;
	_get_rest_vertices(a, b, c, d);
	real_t torsion = 0.0, hinge = 0.0;
	CHECK(physics_xpbd_rod_geometric_torsion_angle(a, b, c, d, torsion));
	CHECK(physics_xpbd_dihedral_angle(b, c, a, d, hinge));
	CHECK(torsion == hinge);
	CHECK(Math::abs(torsion) > real_t(0.05));
}

TEST_CASE("[PhysicsXPBD] Planar curved rod has zero geometric torsion") {
	Vector3 a(-1, 0, 0), b, c(1, 1, 0), d(2, 1, 0);
	real_t angle = 5.0;
	CHECK(physics_xpbd_rod_geometric_torsion_angle(a, b, c, d, angle));
	CHECK(Math::abs(angle) < real_t(1e-5));
}

TEST_CASE("[PhysicsXPBD] Spatial rod twist responds differently to opposite chirality") {
	Vector3 a, b, c, d;
	_get_rest_vertices(a, b, c, d);
	real_t right = 0, left = 0;
	CHECK(physics_xpbd_rod_geometric_torsion_angle(a, b, c, d, right));
	d.z = -d.z;
	CHECK(physics_xpbd_rod_geometric_torsion_angle(a, b, c, d, left));
	CHECK(right == doctest::Approx(-left).epsilon(1e-4));
}

TEST_CASE("[PhysicsXPBD] Reference torsion angle remains unchanged in its rest pose") {
	Vector3 a, b, c, d;
	_get_rest_vertices(a, b, c, d);
	const Vector3 original_a = a, original_b = b, original_c = c, original_d = d;
	real_t rest = 0, lambda = 0;
	CHECK(physics_xpbd_rod_geometric_torsion_angle(a, b, c, d, rest));
	CHECK(physics_xpbd_solve_rod_geometric_torsion(a, b, c, d,
			1, 1, 1, 1, rest, 0.1, lambda));
	CHECK(a == original_a);
	CHECK(b == original_b);
	CHECK(c == original_c);
	CHECK(d == original_d);
	CHECK(lambda == 0);
}

TEST_CASE("[PhysicsXPBD] Stiffer geometric torsion returns further toward preferred twist") {
	Vector3 a, b, c, d;
	_get_rest_vertices(a, b, c, d);
	Vector3 stiff_a = a, stiff_b = b, stiff_c = c, stiff_d = d;
	Vector3 soft_a = a, soft_b = b, soft_c = c, soft_d = d;
	real_t lambda_stiff = 0, lambda_soft = 0;
	for (int i = 0; i < 12; ++i) {
		CHECK(physics_xpbd_solve_rod_geometric_torsion(
				stiff_a, stiff_b, stiff_c, stiff_d, 0, 0, 0, 1, 0,
				real_t(0.1), lambda_stiff));
		CHECK(physics_xpbd_solve_rod_geometric_torsion(
				soft_a, soft_b, soft_c, soft_d, 0, 0, 0, 1, 0,
				real_t(5.0), lambda_soft));
	}
	real_t alpha_stiff = 0, alpha_soft = 0;
	CHECK(physics_xpbd_rod_geometric_torsion_angle(stiff_a, stiff_b, stiff_c, stiff_d, alpha_stiff));
	CHECK(physics_xpbd_rod_geometric_torsion_angle(soft_a, soft_b, soft_c, soft_d, alpha_soft));
	CHECK(Math::abs(alpha_stiff) < Math::abs(alpha_soft));
	CHECK(stiff_a == a);
	CHECK(stiff_b == b);
	CHECK(stiff_c == c);
	CHECK(soft_a == a);
	CHECK(soft_b == b);
	CHECK(soft_c == c);
}

TEST_CASE("[PhysicsXPBD] Torsion corrections conserve center of mass for equal masses") {
	Vector3 a, b, c, d;
	_get_rest_vertices(a, b, c, d);
	const Vector3 sum_before = a + b + c + d;
	real_t lambda = 0;
	CHECK(physics_xpbd_solve_rod_geometric_torsion(a, b, c, d,
			1, 1, 1, 1, 0, 0.1, lambda));
	CHECK((a + b + c + d).distance_to(sum_before) < real_t(1e-5));
}

TEST_CASE("[PhysicsXPBD] Pinned vertices remain exactly unchanged") {
	Vector3 a, b, c, d;
	_get_rest_vertices(a, b, c, d);
	const Vector3 original_b = b, original_c = c;
	real_t lambda = 0;
	CHECK(physics_xpbd_solve_rod_geometric_torsion(a, b, c, d,
			1, 0, 0, 1, 0, 0.1, lambda));
	CHECK(b == original_b);
	CHECK(c == original_c);
}

TEST_CASE("[PhysicsXPBD] Non-degenerate torsion is invariant under translation") {
	Vector3 a, b, c, d;
	_get_rest_vertices(a, b, c, d);
	real_t before = 0, after = 0;
	CHECK(physics_xpbd_rod_geometric_torsion_angle(a, b, c, d, before));
	const Vector3 offset(100, -20, 35);
	CHECK(physics_xpbd_rod_geometric_torsion_angle(
			a + offset, b + offset, c + offset, d + offset, after));
	CHECK(before == doctest::Approx(after).epsilon(1e-4));
}

TEST_CASE("[PhysicsXPBD] Perfectly straight centerline has no geometric torsion") {
	const Vector3 a(-1, 0, 0), b, c(1, 0, 0), d(2, 0, 0);
	real_t invalid_angle = 42.0;
	CHECK_FALSE(physics_xpbd_rod_geometric_torsion_angle(a, b, c, d, invalid_angle));
	CHECK(invalid_angle == 42.0);
	Vector3 a2 = a, b2 = b, c2 = c, d2 = d;
	real_t lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_rod_geometric_torsion(
			a2, b2, c2, d2, 1, 1, 1, 1, 0, 0.1, lambda));
	CHECK(a2 == a);
	CHECK(b2 == b);
	CHECK(c2 == c);
	CHECK(d2 == d);
	CHECK(lambda == 0.0);
}

TEST_CASE("[PhysicsXPBD] Invalid torsion material cannot mutate solver positions") {
	Vector3 a, b, c, d;
	_get_rest_vertices(a, b, c, d);
	const Vector3 original_a = a, original_b = b, original_c = c, original_d = d;
	real_t lambda = real_t(10);
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK_FALSE(physics_xpbd_solve_rod_geometric_torsion(a, b, c, d,
			1, -1, 1, 1, 0, 0.1, lambda));
	CHECK_FALSE(physics_xpbd_solve_rod_geometric_torsion(a, b, c, d,
			1, 1, 1, 1, 0, -1, lambda));
	CHECK_FALSE(physics_xpbd_solve_rod_geometric_torsion(a, b, c, d,
			1, 1, 1, 1, 0, nan, lambda));
	CHECK(a == original_a);
	CHECK(b == original_b);
	CHECK(c == original_c);
	CHECK(d == original_d);
	CHECK(lambda == real_t(10));
}

} // namespace TestPhysicsXPBDRodTorsion
