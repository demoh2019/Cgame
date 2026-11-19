/**************************************************************************/
/*  test_physics_softbody_adiabatic_gas.cpp                               */
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

#include "servers/physics_softbody_adiabatic_gas.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_adiabatic_gas)

namespace TestPhysicsSoftBodyAdiabaticGas {

TEST_CASE("[PhysicsSoftBody] Isothermal gas doubles its pressure at half volume") {
	double pressure = 0.0;
	CHECK(physics_softbody_adiabatic_pressure(2.0, 1.0, 100.0, 1.0, pressure));
	CHECK(pressure == doctest::Approx(200.0));
}

TEST_CASE("[PhysicsSoftBody] Adiabatic gas pressure follows gamma exponent") {
	double pressure = 0.0;
	CHECK(physics_softbody_adiabatic_pressure(2.0, 1.0, 100.0, 2.0, pressure));
	CHECK(pressure == doctest::Approx(400.0));
	CHECK(physics_softbody_adiabatic_pressure(2.0, 4.0, 100.0, 2.0, pressure));
	CHECK(pressure == doctest::Approx(25.0));
}

TEST_CASE("[PhysicsSoftBody] Gas pressure limits extreme compression") {
	double pressure = 0.0;
	CHECK(physics_softbody_adiabatic_pressure(1.0, 1e-7, 2.0, 2.0, pressure));
	CHECK(pressure == doctest::Approx(800.0));
	CHECK(Math::is_finite(pressure));
}

TEST_CASE("[PhysicsSoftBody] Reversed mesh orientation keeps gas pressure") {
	double forward = 0.0;
	double reversed = 0.0;
	CHECK(physics_softbody_adiabatic_pressure(2.0, 1.0, 100.0, 1.4, forward));
	CHECK(physics_softbody_adiabatic_pressure(-2.0, -1.0, 100.0, 1.4, reversed));
	CHECK(forward == doctest::Approx(reversed));
}

TEST_CASE("[PhysicsSoftBody] Inverted and open gas volumes remain inactive") {
	double pressure = 42.0;
	CHECK_FALSE(physics_softbody_adiabatic_pressure(2.0, -1.0, 100.0, 1.4, pressure));
	CHECK_FALSE(physics_softbody_adiabatic_pressure(2.0, 0.0, 100.0, 1.4, pressure));
	CHECK_FALSE(physics_softbody_adiabatic_pressure(0.0, 1.0, 100.0, 1.4, pressure));
	CHECK(pressure == 42.0);
}

TEST_CASE("[PhysicsSoftBody] Gas pressure rejects invalid parameters atomically") {
	double pressure = 42.0;
	CHECK_FALSE(physics_softbody_adiabatic_pressure(1.0, 1.0, 100.0, 0.0, pressure));
	CHECK_FALSE(physics_softbody_adiabatic_pressure(1.0, 1.0, 100.0, 6.0, pressure));
	CHECK_FALSE(physics_softbody_adiabatic_pressure(1.0, 1.0, -1.0, 1.4, pressure));
	CHECK_FALSE(physics_softbody_adiabatic_pressure(1.0, 1.0,
			std::numeric_limits<double>::infinity(), 1.4, pressure));
	CHECK(pressure == 42.0);
}

TEST_CASE("[PhysicsSoftBody] Pressure force uses actual triangle area and winding") {
	Vector3 force(7, 7, 7);
	CHECK(physics_softbody_adiabatic_face_force(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), 6.0, 1, force));
	CHECK(force.is_equal_approx(Vector3(0, 0, 1)));
	Vector3 reversed;
	CHECK(physics_softbody_adiabatic_face_force(
			Vector3(), Vector3(0, 1, 0), Vector3(1, 0, 0), 6.0, -1, reversed));
	CHECK(force.is_equal_approx(reversed));
}

TEST_CASE("[PhysicsSoftBody] Closed tetrahedron has zero net pressure force") {
	const Vector3 v[4] = { Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1) };
	const int face[4][3] = { { 0, 2, 1 }, { 0, 1, 3 }, { 0, 3, 2 }, { 1, 2, 3 } };
	Vector3 sum;
	for (int i = 0; i < 4; ++i) {
		Vector3 force;
		CHECK(physics_softbody_adiabatic_face_force(v[face[i][0]], v[face[i][1]],
				v[face[i][2]], 6.0, 1, force));
		sum += force * 3.0;
	}
	CHECK(sum.is_equal_approx(Vector3()));
}

TEST_CASE("[PhysicsSoftBody] Pressure face forces do not overflow on translated mesh") {
	Vector3 force;
	CHECK(physics_softbody_adiabatic_face_force(
			Vector3(1000, 2000, -500), Vector3(1002, 2000, -500),
			Vector3(1000, 2003, -500), 6.0, 1, force));
	CHECK(force.is_equal_approx(Vector3(0, 0, 6)));
}

TEST_CASE("[PhysicsSoftBody] Invalid pressure force never mutates output") {
	Vector3 result(7, 8, 9);
	CHECK_FALSE(physics_softbody_adiabatic_face_force(
			Vector3(), Vector3(1, 0, 0), Vector3(2, 0, 0), 6.0, 1, result));
	CHECK_FALSE(physics_softbody_adiabatic_face_force(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), 6.0, 0, result));
	CHECK_FALSE(physics_softbody_adiabatic_face_force(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), -1.0, 1, result));
	CHECK(result == Vector3(7, 8, 9));
}

} // namespace TestPhysicsSoftBodyAdiabaticGas
