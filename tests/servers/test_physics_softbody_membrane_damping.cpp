/**************************************************************************/
/*  test_physics_softbody_membrane_damping.cpp                            */
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

#include "servers/physics_softbody_membrane_damping.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_membrane_damping)

namespace TestPhysicsSoftBodyMembraneDamping {

static PhysicsXPBDMembraneRest unit_triangle() {
	PhysicsXPBDMembraneRest rest;
	REQUIRE(physics_xpbd_membrane_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), rest));
	return rest;
}

static double kinetic_energy(const Vector3 &p_va, const Vector3 &p_vb,
		const Vector3 &p_vc) {
	return 0.5 * (double(p_va.length_squared()) +
			double(p_vb.length_squared()) + double(p_vc.length_squared()));
}

TEST_CASE("[SoftBodyMembraneDamping] Extension rate dissipates kinetic energy") {
	const PhysicsXPBDMembraneRest rest = unit_triangle();
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 va, vb(2, 0, 0), vc;
	const double before = kinetic_energy(va, vb, vc);
	CHECK(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			1.0, 1.0, 1.0, rest, 1.0));
	CHECK(kinetic_energy(va, vb, vc) < before);
	CHECK((va + vb + vc).is_equal_approx(Vector3(2, 0, 0)));
}

TEST_CASE("[SoftBodyMembraneDamping] Shear velocity decays") {
	const PhysicsXPBDMembraneRest rest = unit_triangle();
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 va, vb, vc(1, 0, 0);
	CHECK(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			1.0, 1.0, 1.0, rest, 1.0));
	CHECK((va + vb + vc).is_equal_approx(Vector3(1, 0, 0)));
	CHECK(kinetic_energy(va, vb, vc) < 0.5);
}

TEST_CASE("[SoftBodyMembraneDamping] Pure translation generates no strain damping") {
	const PhysicsXPBDMembraneRest rest = unit_triangle();
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 va(5, 3, -2), vb = va, vc = va;
	physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			1.0, 1.0, 1.0, rest, 1.0);
	CHECK(va.is_equal_approx(Vector3(5, 3, -2)));
	CHECK(vb.is_equal_approx(Vector3(5, 3, -2)));
	CHECK(vc.is_equal_approx(Vector3(5, 3, -2)));
}

TEST_CASE("[SoftBodyMembraneDamping] Rigid rotation generates no strain damping") {
	const PhysicsXPBDMembraneRest rest = unit_triangle();
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 va, vb(0, 1, 0), vc(-1, 0, 0);
	physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			1.0, 1.0, 1.0, rest, 0.95);
	CHECK(va.is_equal_approx(Vector3()));
	CHECK(vb.is_equal_approx(Vector3(0, 1, 0)));
	CHECK(vc.is_equal_approx(Vector3(-1, 0, 0)));
}

TEST_CASE("[SoftBodyMembraneDamping] Pinned particles retain their exact velocities") {
	const PhysicsXPBDMembraneRest rest = unit_triangle();
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 va(2, 0, 0), vb(0, 2, 0), vc(3, 0, 0);
	const Vector3 original_a = va, original_b = vb;
	CHECK(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			0.0, 0.0, 1.0, rest, 1.0));
	CHECK(va == original_a);
	CHECK(vb == original_b);
	CHECK(vc.is_finite());
}

TEST_CASE("[SoftBodyMembraneDamping] Weighted linear and angular momentum are conserved") {
	const PhysicsXPBDMembraneRest rest = unit_triangle();
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 va(2, 1, 3), vb(-1, 3, -2), vc(4, -2, 1);
	const real_t inv_a = real_t(0.5), inv_b = real_t(1.0), inv_c = real_t(2.0);
	const Vector3 before_linear = va * real_t(2) + vb + vc * real_t(0.5);
	const Vector3 before_angular = a.cross(va * real_t(2)) +
			b.cross(vb) + c.cross(vc * real_t(0.5));
	CHECK(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			inv_a, inv_b, inv_c, rest, 0.7));
	const Vector3 after_linear = va * real_t(2) + vb + vc * real_t(0.5);
	const Vector3 after_angular = a.cross(va * real_t(2)) +
			b.cross(vb) + c.cross(vc * real_t(0.5));
	CHECK((after_linear - before_linear).length() < real_t(1e-4));
	CHECK((after_angular - before_angular).length() < real_t(1e-4));
}

TEST_CASE("[SoftBodyMembraneDamping] Smaller damping fraction removes less energy") {
	const PhysicsXPBDMembraneRest rest = unit_triangle();
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 va0, vb0(2, 0, 0), vc0;
	Vector3 va1 = va0, vb1 = vb0, vc1 = vc0;
	CHECK(physics_softbody_damp_membrane(a, b, c, va0, vb0, vc0,
			1.0, 1.0, 1.0, rest, 0.1));
	CHECK(physics_softbody_damp_membrane(a, b, c, va1, vb1, vc1,
			1.0, 1.0, 1.0, rest, 0.9));
	CHECK(kinetic_energy(va1, vb1, vc1) < kinetic_energy(va0, vb0, vc0));
}

TEST_CASE("[SoftBodyMembraneDamping] Very small and large triangles stay finite") {
	for (real_t scale : { real_t(1e-8), real_t(1e20) }) {
		PhysicsXPBDMembraneRest rest;
		const Vector3 a, b(scale, 0, 0), c(0, scale, 0);
		REQUIRE(physics_xpbd_membrane_make_rest(a, b, c, rest));
		Vector3 va, vb(2, 0, 0), vc;
		CHECK(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
				1.0, 1.0, 1.0, rest, 1.0));
		CHECK(va.is_finite());
		CHECK(vb.is_finite());
		CHECK(vc.is_finite());
		CHECK((va + vb + vc).is_equal_approx(Vector3(2, 0, 0)));
	}
}

TEST_CASE("[SoftBodyMembraneDamping] Invalid data does not modify any velocities") {
	const PhysicsXPBDMembraneRest rest = unit_triangle();
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 va, vb(2, 0, 0), vc;
	CHECK_FALSE(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			1.0, 1.0, 1.0, rest, 0.0));
	CHECK_FALSE(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			1.0, 1.0, 1.0, rest, 1.01));
	CHECK_FALSE(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			1.0, real_t(-1), 1.0, rest, 0.5));
	CHECK_FALSE(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			0.0, 0.0, 0.0, rest, 1.0));
	CHECK_FALSE(physics_softbody_damp_membrane(a, b, c, va, vb, vc,
			1.0, 1.0, 1.0, rest, std::numeric_limits<double>::infinity()));
	CHECK(va == Vector3());
	CHECK(vb == Vector3(2, 0, 0));
	CHECK(vc == Vector3());
}

} // namespace TestPhysicsSoftBodyMembraneDamping
