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

#include "servers/physics_fem_tetra_viscosity.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_viscosity)

namespace TestPhysicsFEMTetraViscosity {

static void unit_tetra(Vector3 (&r_points)[4], PhysicsFEMTetraRest &r_rest) {
	r_points[0] = Vector3();
	r_points[1] = Vector3(1, 0, 0);
	r_points[2] = Vector3(0, 1, 0);
	r_points[3] = Vector3(0, 0, 1);
	CHECK(physics_fem_tetra_make_rest(r_points[0], r_points[1], r_points[2],
			r_points[3], r_rest));
}

TEST_CASE("[PhysicsFEM] Tetra viscosity leaves rigid translation untouched") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(5, 3, 2), Vector3(5, 3, 2),
		Vector3(5, 3, 2), Vector3(5, 3, 2) };
	const real_t w[4] = { 1, 1, 1, 1 };
	CHECK_FALSE(physics_fem_tetra_viscous_damp(x, v, w, rest, 0.3, 50, 0.02));
	for (const Vector3 &q : v) {
		CHECK(q == Vector3(5, 3, 2));
	}
}

TEST_CASE("[PhysicsFEM] Tetra viscosity is objective under rigid rotation") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4];
	for (int i = 0; i < 4; ++i) {
		v[i] = Vector3(-x[i].y, x[i].x, 0);
	}
	Vector3 f[4];
	CHECK(physics_fem_tetra_viscous_forces(x, v, rest, 0.3, 20, f));
	for (const Vector3 &force : f) {
		CHECK(force.length() < real_t(1e-5));
	}
}

TEST_CASE("[PhysicsFEM] Tetra viscosity remains objective after elastic deformation") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	x[1] = Vector3(real_t(1.4), real_t(0.2), 0);
	x[2] = Vector3(real_t(0.1), real_t(0.7), real_t(0.1));
	Vector3 v[4];
	for (int i = 0; i < 4; ++i) {
		v[i] = Vector3(-x[i].y, x[i].x, 0);
	}
	Vector3 f[4];
	CHECK(physics_fem_tetra_viscous_forces(x, v, rest, 0.3, 10, f));
	for (const Vector3 &force : f) {
		CHECK(force.length() < real_t(1e-5));
	}
}

TEST_CASE("[PhysicsFEM] Tetra viscosity reduces relative stretch velocity") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	const real_t w[4] = { 1, 1, 1, 1 };
	const real_t before = (v[1] - v[0]).length();
	CHECK(physics_fem_tetra_viscous_damp(x, v, w, rest, 0.3, 20, 0.02));
	CHECK((v[1] - v[0]).length() < before);
}

TEST_CASE("[PhysicsFEM] Tetra viscosity conserves linear momentum") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	const real_t w[4] = { 1, 1, 1, 1 };
	const Vector3 before = v[0] + v[1] + v[2] + v[3];
	CHECK(physics_fem_tetra_viscous_damp(x, v, w, rest, 0.3, 10, 0.03));
	CHECK((v[0] + v[1] + v[2] + v[3] - before).length() < real_t(1e-5));
}

TEST_CASE("[PhysicsFEM] Viscous impulse never increases kinetic energy") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(), Vector3(3, 0, 0), Vector3(), Vector3() };
	const real_t w[4] = { 1, 1, 1, 1 };
	const double before = double(v[1].length_squared());
	CHECK(physics_fem_tetra_viscous_damp(x, v, w, rest, 0.3, 1e6, 1));
	double after = 0.0;
	for (const Vector3 &p : v) {
		after += double(p.length_squared());
	}
	CHECK(after <= before + 1e-5);
}

TEST_CASE("[PhysicsFEM] Pinned tetra nodes stay fixed during viscosity") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	const real_t w[4] = { 0, 1, 0, 0 };
	CHECK(physics_fem_tetra_viscous_damp(x, v, w, rest, 0.3, 40, 0.02));
	CHECK(v[0] == Vector3());
	CHECK(v[2] == Vector3());
	CHECK(v[3] == Vector3());
	CHECK(v[1].x < real_t(2));
}

TEST_CASE("[PhysicsFEM] Viscous forces sum to zero") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	Vector3 f[4];
	CHECK(physics_fem_tetra_viscous_forces(x, v, rest, 0.3, 8, f));
	CHECK((f[0] + f[1] + f[2] + f[3]).length() < real_t(1e-5));
}

TEST_CASE("[PhysicsFEM] Uniform translations of shape and motion leave stress invariant") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	Vector3 f0[4], f1[4];
	CHECK(physics_fem_tetra_viscous_forces(x, v, rest, 0.3, 10, f0));
	for (int i = 0; i < 4; ++i) {
		x[i] += Vector3(20, 30, -50);
		v[i] += Vector3(-2, 5, 8);
	}
	CHECK(physics_fem_tetra_viscous_forces(x, v, rest, 0.3, 10, f1));
	for (int i = 0; i < 4; ++i) {
		CHECK(f0[i].distance_to(f1[i]) < real_t(1e-4));
	}
}

TEST_CASE("[PhysicsFEM] Poisson ratio changes the viscous bulk response") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	Vector3 f0[4], f1[4];
	CHECK(physics_fem_tetra_viscous_forces(x, v, rest, 0.0, 10, f0));
	CHECK(physics_fem_tetra_viscous_forces(x, v, rest, 0.45, 10, f1));
	CHECK((f0[1] - f1[1]).length() > real_t(0.01));
}

TEST_CASE("[PhysicsFEM] Invalid viscosity never changes velocities") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	const real_t w[4] = { 1, 1, 1, 1 };
	CHECK_FALSE(physics_fem_tetra_viscous_damp(x, v, w, rest, 0.3, 0, 0.03));
	CHECK_FALSE(physics_fem_tetra_viscous_damp(x, v, w, rest, 0.3, 10, 0));
	CHECK_FALSE(physics_fem_tetra_viscous_damp(x, v, w, rest, 0.3,
			std::numeric_limits<double>::infinity(), 0.03));
	CHECK(v[1] == Vector3(2, 0, 0));
}

TEST_CASE("[PhysicsFEM] Inverted material element does not produce nonfinite viscous stress") {
	Vector3 x[4];
	PhysicsFEMTetraRest rest;
	unit_tetra(x, rest);
	x[3].z = -1.0;
	Vector3 v[4] = { Vector3(), Vector3(2, 0, 0), Vector3(), Vector3() };
	Vector3 f[4];
	CHECK_FALSE(physics_fem_tetra_viscous_forces(x, v, rest, 0.3, 10, f));
}

} // namespace TestPhysicsFEMTetraViscosity
