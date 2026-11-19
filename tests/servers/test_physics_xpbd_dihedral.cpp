/**************************************************************************/
/*  test_physics_xpbd_dihedral.cpp                                        */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_xpbd_dihedral)

#include "servers/physics_xpbd_dihedral.h"

namespace TestPhysicsXPBDDihedral {

TEST_CASE("[Physics] XPBD dihedral flat fold and analytical angle gradients") {
	Vector3 p[4] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.25, 1, 0), Vector3(0.2, -1, 0),
	};
	real_t angle;
	Vector3 gradient[4];
	REQUIRE(physics_xpbd_dihedral_angle_gradients(p[0], p[1], p[2], p[3], angle, gradient));
	CHECK(Math::abs(angle) < real_t(0.00001));

	// A flat fold must have nonzero bending gradients; an acos(dot)
	// implementation would lose gradient accuracy around angle zero.
	CHECK(gradient[2].length() > real_t(0.5));
	CHECK(gradient[3].length() > real_t(0.5));
	CHECK((gradient[0] + gradient[1] + gradient[2] + gradient[3]).length() < real_t(0.00001));

	p[2].z = real_t(0.45);
	p[3].z = real_t(-0.1);
	REQUIRE(physics_xpbd_dihedral_angle_gradients(p[0], p[1], p[2], p[3], angle, gradient));
	const real_t h = real_t(0.0005);
	for (int vertex = 0; vertex < 4; ++vertex) {
		for (int coordinate = 0; coordinate < 3; ++coordinate) {
			Vector3 plus[4] = { p[0], p[1], p[2], p[3] };
			Vector3 minus[4] = { p[0], p[1], p[2], p[3] };
			plus[vertex][coordinate] += h;
			minus[vertex][coordinate] -= h;
			real_t plus_angle, minus_angle;
			Vector3 scratch[4];
			REQUIRE(physics_xpbd_dihedral_angle_gradients(plus[0], plus[1], plus[2], plus[3], plus_angle, scratch));
			REQUIRE(physics_xpbd_dihedral_angle_gradients(minus[0], minus[1], minus[2], minus[3], minus_angle, scratch));
			const real_t central_difference = (plus_angle - minus_angle) / (real_t(2.0) * h);
			CHECK(Math::abs(central_difference - gradient[vertex][coordinate]) < real_t(0.015));
		}
	}
}

TEST_CASE("[Physics] XPBD dihedral resists folding and preserves pinned hinge endpoints") {
	Vector3 p[4] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0, 1, 0.6), Vector3(0, -1, 0),
	};
	const Vector3 pinned_a = p[0], pinned_b = p[1];
	const real_t inv_mass[4] = { 0, 0, 1, 1 };
	real_t lambda = 0.0;
	real_t initial_angle;
	Vector3 g[4];
	REQUIRE(physics_xpbd_dihedral_angle_gradients(p[0], p[1], p[2], p[3], initial_angle, g));
	REQUIRE(Math::abs(initial_angle) > real_t(0.4));
	for (int i = 0; i < 6; ++i) {
		CHECK(physics_xpbd_solve_dihedral(p[0], p[1], p[2], p[3],
					inv_mass[0], inv_mass[1], inv_mass[2], inv_mass[3],
					real_t(0.0), real_t(0.0), lambda));
	}
	real_t resulting_angle;
	REQUIRE(physics_xpbd_dihedral_angle_gradients(p[0], p[1], p[2], p[3], resulting_angle, g));
	CHECK(Math::abs(resulting_angle) < Math::abs(initial_angle) * real_t(0.05));
	CHECK(p[0] == pinned_a);
	CHECK(p[1] == pinned_b);
	for (const Vector3 &point : p) {
		CHECK(point.is_finite());
	}
}

TEST_CASE("[Physics] XPBD dihedral compliance reduces fold correction") {
	Vector3 stiff[4] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0, 1, 0.5), Vector3(0, -1, 0),
	};
	Vector3 compliant[4] = { stiff[0], stiff[1], stiff[2], stiff[3] };
	real_t stiff_lambda = 0.0;
	real_t soft_lambda = 0.0;
	REQUIRE(physics_xpbd_solve_dihedral(stiff[0], stiff[1], stiff[2], stiff[3],
			0.0, 0.0, 1.0, 1.0, 0.0, 0.0, stiff_lambda));
	REQUIRE(physics_xpbd_solve_dihedral(compliant[0], compliant[1], compliant[2], compliant[3],
			0.0, 0.0, 1.0, 1.0, 0.0, 5.0, soft_lambda));
	real_t stiff_angle, soft_angle;
	Vector3 g[4];
	REQUIRE(physics_xpbd_dihedral_angle_gradients(stiff[0], stiff[1], stiff[2], stiff[3], stiff_angle, g));
	REQUIRE(physics_xpbd_dihedral_angle_gradients(compliant[0], compliant[1], compliant[2], compliant[3], soft_angle, g));
	CHECK(Math::abs(stiff_angle) < Math::abs(soft_angle));
}

TEST_CASE("[Physics] XPBD dihedral handles degeneracy, all-pinned and invalid compliance") {
	Vector3 a(0, 0, 0), b(1, 0, 0), c(0, 1, 0), d(0, -1, 0);
	const Vector3 old_a = a, old_b = b, old_c = c, old_d = d;
	real_t lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_dihedral(a, b, c, d, 0, 0, 0, 0, 0, 0, lambda));
	CHECK_FALSE(physics_xpbd_solve_dihedral(a, b, c, d, 0, 0, 1, 1, 0, -1, lambda));
	CHECK(lambda == real_t(0.0));
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c == old_c);
	CHECK(d == old_d);
	b = a; // Collapsed shared edge.
	real_t angle;
	Vector3 g[4];
	CHECK_FALSE(physics_xpbd_dihedral_angle_gradients(a, b, c, d, angle, g));
	CHECK_FALSE(physics_xpbd_solve_dihedral(a, b, c, d, 1, 1, 1, 1, 0, 0, lambda));
	b = old_b;
	c = Vector3(0.5, 0, 0); // Zero-area triangle.
	CHECK_FALSE(physics_xpbd_dihedral_angle_gradients(a, b, c, d, angle, g));
	CHECK_FALSE(physics_xpbd_solve_dihedral(a, b, c, d, 1, 1, 1, 1, 0, 0, lambda));
	CHECK(lambda == real_t(0.0));
}

} // namespace TestPhysicsXPBDDihedral
