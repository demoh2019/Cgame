/**************************************************************************/
/*  test_physics_xpbd_membrane.cpp                                        */
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
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_xpbd_membrane.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_membrane)

namespace TestPhysicsXPBDMembrane {

static PhysicsXPBDMembraneRest make_rest() {
	PhysicsXPBDMembraneRest rest;
	CHECK(physics_xpbd_membrane_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), rest));
	return rest;
}

TEST_CASE("[PhysicsXPBDMembrane] Rest state and rigid motions have zero energy") {
	const PhysicsXPBDMembraneRest rest = make_rest();
	double energy = -1.0;
	Vector3 ga, gb, gc;
	CHECK(physics_xpbd_membrane_energy_gradient(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), rest, 0.3, energy, ga, gb, gc));
	CHECK(energy == doctest::Approx(0.0).epsilon(1e-6));
	CHECK(ga == Vector3());
	CHECK(gb == Vector3());
	CHECK(gc == Vector3());
	CHECK(physics_xpbd_membrane_energy_gradient(Vector3(10, 5, 3),
			Vector3(10, 6, 3), Vector3(9, 5, 3), rest,
			0.3, energy, ga, gb, gc));
	CHECK(energy == doctest::Approx(0.0).epsilon(1e-6));
}

TEST_CASE("[PhysicsXPBDMembrane] Stretching shrinks toward the material rest metric") {
	const PhysicsXPBDMembraneRest rest = make_rest();
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0);
	double lambda = 0.0;
	CHECK(physics_xpbd_membrane_solve(a, b, c, 0.0, 1.0, 0.0,
			rest, 0.3, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
	CHECK(b.x < real_t(1.5));
	CHECK(b.x > real_t(0.9));
	CHECK(lambda < 0.0);
}

TEST_CASE("[PhysicsXPBDMembrane] Compressed triangles resist in-plane collapse") {
	const PhysicsXPBDMembraneRest rest = make_rest();
	Vector3 a, b(real_t(0.6), 0, 0), c(0, 1, 0);
	double lambda = 0.0;
	CHECK(physics_xpbd_membrane_solve(a, b, c, 0.0, 1.0, 0.0,
			rest, 0.3, 0.0, lambda));
	CHECK(b.x > real_t(0.6));
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
}

TEST_CASE("[PhysicsXPBDMembrane] Shear responds even when two vertices are pinned") {
	const PhysicsXPBDMembraneRest rest = make_rest();
	Vector3 a, b(1, 0, 0), c(real_t(0.5), 1, 0);
	double lambda = 0.0;
	CHECK(physics_xpbd_membrane_solve(a, b, c, 0.0, 0.0, 1.0,
			rest, 0.3, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3(1, 0, 0));
	CHECK(c.x < real_t(0.5));
	CHECK(c.is_finite());
}

TEST_CASE("[PhysicsXPBDMembrane] Poisson ratio couples stretching and shear") {
	const PhysicsXPBDMembraneRest rest = make_rest();
	Vector3 a, b0(real_t(1.4), 0, 0), c0(real_t(0.3), 1, 0);
	Vector3 b1 = b0, c1 = c0;
	double lambda0 = 0.0, lambda1 = 0.0;
	CHECK(physics_xpbd_membrane_solve(a, b0, c0, 0.0, 1.0, 1.0,
			rest, 0.0, 0.0, lambda0));
	CHECK(physics_xpbd_membrane_solve(a, b1, c1, 0.0, 1.0, 1.0,
			rest, 0.45, 0.0, lambda1));
	CHECK(Math::abs(c0.y - c1.y) > real_t(0.02));
	CHECK(a == Vector3());
}

TEST_CASE("[PhysicsXPBDMembrane] Energy gradients match centered differences") {
	const PhysicsXPBDMembraneRest rest = make_rest();
	Vector3 a, b(real_t(1.2), real_t(0.2), 0), c(real_t(0.1), real_t(1.1), 0);
	double e, ep, em;
	Vector3 ga, gb, gc, unused1, unused2, unused3;
	CHECK(physics_xpbd_membrane_energy_gradient(a, b, c, rest, 0.3, e, ga, gb, gc));
	const real_t epsilon = real_t(0.001);
	CHECK(physics_xpbd_membrane_energy_gradient(a, b,
			Vector3(c.x + epsilon, c.y, c.z), rest, 0.3, ep, unused1, unused2, unused3));
	CHECK(physics_xpbd_membrane_energy_gradient(a, b,
			Vector3(c.x - epsilon, c.y, c.z), rest, 0.3, em, unused1, unused2, unused3));
	const double finite_difference = (ep - em) / (2.0 * double(epsilon));
	CHECK(double(gc.x) == doctest::Approx(finite_difference).epsilon(0.001));
}

TEST_CASE("[PhysicsXPBDMembrane] Compliant iterations keep a finite multiplier") {
	const PhysicsXPBDMembraneRest rest = make_rest();
	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0);
	double lambda = 0.0;
	for (int i = 0; i < 32; ++i) {
		physics_xpbd_membrane_solve(a, b, c, 0.0, 1.0, 0.0,
				rest, 0.3, 0.05, lambda);
	}
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
	CHECK(b.x > real_t(1.0));
	CHECK(b.x < real_t(1.5));
	CHECK(Math::is_finite(lambda));
}

TEST_CASE("[PhysicsXPBDMembrane] Wide and tiny finite triangles remain valid") {
	const real_t scales[] = { real_t(1e-8), real_t(1e20) };
	for (real_t scale : scales) {
		PhysicsXPBDMembraneRest rest;
		CHECK(physics_xpbd_membrane_make_rest(Vector3(), Vector3(scale, 0, 0),
				Vector3(0, scale, 0), rest));
		Vector3 a, b(real_t(1.5) * scale, 0, 0), c(0, scale, 0);
		double lambda = 0.0;
		CHECK(physics_xpbd_membrane_solve(a, b, c, 0.0, 1.0, 0.0,
				rest, 0.3, 0.0, lambda));
		CHECK(b.x / scale < real_t(1.5));
		CHECK(b.x / scale > real_t(0.9));
		CHECK(Math::is_finite(lambda));
		CHECK(b.is_finite());
	}
}

TEST_CASE("[PhysicsXPBDMembrane] Invalid and pinned inputs are atomic") {
	PhysicsXPBDMembraneRest rest = make_rest();
	const PhysicsXPBDMembraneRest old_rest = rest;
	CHECK_FALSE(physics_xpbd_membrane_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(2, 0, 0), rest));
	CHECK(rest.area == old_rest.area);

	Vector3 a, b(real_t(1.5), 0, 0), c(0, 1, 0);
	double lambda = 0.0;
	CHECK_FALSE(physics_xpbd_membrane_solve(a, b, c, 0.0, 0.0, 0.0,
			rest, 0.3, 0.0, lambda));
	CHECK_FALSE(physics_xpbd_membrane_solve(a, b, c, 1.0, 1.0, 1.0,
			rest, 0.9, 0.0, lambda));
	CHECK_FALSE(physics_xpbd_membrane_solve(a, b, c, 1.0, 1.0, 1.0,
			rest, 0.3, std::numeric_limits<double>::infinity(), lambda));
	CHECK_FALSE(physics_xpbd_membrane_solve(a, b, c, real_t(-1), 1.0, 1.0,
			rest, 0.3, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3(real_t(1.5), 0, 0));
	CHECK(c == Vector3(0, 1, 0));
	CHECK(lambda == 0.0);
}

} // namespace TestPhysicsXPBDMembrane
