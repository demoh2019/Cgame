/**************************************************************************/
/*  test_physics_fem_tetra_damage.cpp                                     */
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

#include "servers/physics_fem_tetra_damage.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_damage)

namespace TestPhysicsFEMTetraDamage {

static void tetra(Vector3 (&r_points)[4], PhysicsFEMTetraRest &r_rest) {
	r_points[0] = Vector3();
	r_points[1] = Vector3(1, 0, 0);
	r_points[2] = Vector3(0, 1, 0);
	r_points[3] = Vector3(0, 0, 1);
	CHECK(physics_fem_tetra_make_rest(r_points[0], r_points[1], r_points[2],
			r_points[3], r_rest));
}

TEST_CASE("[PhysicsFEM] Undamaged tetrahedron has zero equivalent strain") {
	Vector3 p[4];
	PhysicsFEMTetraRest rest;
	tetra(p, rest);
	double strain = 10.0;
	CHECK(PhysicsFEMTetraDamage::equivalent_strain(p, rest, 0.3, strain));
	CHECK(strain == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEM] Rigid rotation and translation never create damage") {
	Vector3 p[4];
	PhysicsFEMTetraRest rest;
	tetra(p, rest);
	for (Vector3 &v : p) {
		v = Vector3(-v.y + 10, v.x + 20, v.z - 3);
	}
	double strain = 10.0, damage = 0.0;
	CHECK(PhysicsFEMTetraDamage::equivalent_strain(p, rest, 0.3, strain));
	CHECK(strain < 1e-5);
	CHECK_FALSE(PhysicsFEMTetraDamage::evolve(strain, 0.1, 10, 0.02, damage));
	CHECK(damage == 0.0);
}

TEST_CASE("[PhysicsFEM] Stretch and shear produce nonzero damage drive") {
	Vector3 p[4];
	PhysicsFEMTetraRest rest;
	tetra(p, rest);
	p[1] = Vector3(real_t(1.4), 0, 0);
	double stretch = 0.0;
	CHECK(PhysicsFEMTetraDamage::equivalent_strain(p, rest, 0.3, stretch));
	CHECK(stretch > 0.0);
	p[1] = Vector3(1, 0, 0);
	p[2] = Vector3(real_t(0.4), 1, 0);
	double shear = 0.0;
	CHECK(PhysicsFEMTetraDamage::equivalent_strain(p, rest, 0.3, shear));
	CHECK(shear > 0.0);
}

TEST_CASE("[PhysicsFEM] Compression also drives material damage") {
	Vector3 p[4];
	PhysicsFEMTetraRest rest;
	tetra(p, rest);
	p[1] = Vector3(real_t(0.7), 0, 0);
	double equivalent = 0.0;
	CHECK(PhysicsFEMTetraDamage::equivalent_strain(p, rest, 0.3, equivalent));
	CHECK(equivalent > 0.0);
}

TEST_CASE("[PhysicsFEM] Damage accumulates above yield and never decreases") {
	double damage = 0.0;
	CHECK(PhysicsFEMTetraDamage::evolve(0.7, 0.2, 3.0, 0.02, damage));
	const double first = damage;
	CHECK(first > 0.0);
	CHECK(PhysicsFEMTetraDamage::evolve(0.7, 0.2, 3.0, 0.02, damage));
	CHECK(damage > first);
	const double second = damage;
	CHECK_FALSE(PhysicsFEMTetraDamage::evolve(0.0, 0.2, 3.0, 0.02, damage));
	CHECK(damage == second);
}

TEST_CASE("[PhysicsFEM] Sub-yield strain causes no damage") {
	double damage = 0.1;
	CHECK_FALSE(PhysicsFEMTetraDamage::evolve(0.19, 0.2, 50, 1, damage));
	CHECK_FALSE(PhysicsFEMTetraDamage::evolve(0.2, 0.2, 50, 1, damage));
	CHECK(damage == 0.1);
}

TEST_CASE("[PhysicsFEM] Damage evolution is independent of fixed timestep subdivision") {
	double once = 0.0, twice = 0.0;
	CHECK(PhysicsFEMTetraDamage::evolve(0.5, 0.1, 5, 0.02, once));
	CHECK(PhysicsFEMTetraDamage::evolve(0.5, 0.1, 5, 0.01, twice));
	CHECK(PhysicsFEMTetraDamage::evolve(0.5, 0.1, 5, 0.01, twice));
	CHECK(once == doctest::Approx(twice).epsilon(1e-12));
}

TEST_CASE("[PhysicsFEM] Severe damage retains strictly positive residual stiffness") {
	double damage = 0.0;
	CHECK(PhysicsFEMTetraDamage::evolve(100, 0.1, 1e9, 10, damage));
	CHECK(damage == doctest::Approx(PhysicsFEMTetraDamage::MAX_DAMAGE));
	double alpha = 0.0;
	CHECK(PhysicsFEMTetraDamage::effective_compliance(1e-4, damage, alpha));
	CHECK(alpha == doctest::Approx(2e-3));
}

TEST_CASE("[PhysicsFEM] Stiffness decreases monotonically with scalar damage") {
	double a, b, c;
	CHECK(PhysicsFEMTetraDamage::effective_compliance(1e-4, 0.0, a));
	CHECK(PhysicsFEMTetraDamage::effective_compliance(1e-4, 0.25, b));
	CHECK(PhysicsFEMTetraDamage::effective_compliance(1e-4, 0.9, c));
	CHECK(a < b);
	CHECK(b < c);
}

TEST_CASE("[PhysicsFEM] Damage does not change undeformed tetrahedron rest matrix") {
	Vector3 p[4];
	PhysicsFEMTetraRest rest;
	tetra(p, rest);
	const double volume = rest.volume;
	double damage = 0.0;
	CHECK(PhysicsFEMTetraDamage::evolve(0.6, 0.2, 10, 0.02, damage));
	CHECK(rest.volume == volume);
	CHECK(rest.inv_dm[0][0] == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsFEM] Invalid damage arguments leave output unchanged") {
	double damage = 0.2;
	const double inf = std::numeric_limits<double>::infinity();
	CHECK_FALSE(PhysicsFEMTetraDamage::evolve(inf, 0.1, 1, 1, damage));
	CHECK_FALSE(PhysicsFEMTetraDamage::evolve(0.8, -0.1, 1, 1, damage));
	CHECK_FALSE(PhysicsFEMTetraDamage::evolve(0.8, 0.1, -1, 1, damage));
	CHECK_FALSE(PhysicsFEMTetraDamage::evolve(0.8, 0.1, 1, -1, damage));
	CHECK(damage == 0.2);
	double alpha = 123.0;
	CHECK_FALSE(PhysicsFEMTetraDamage::effective_compliance(0.0, damage, alpha));
	CHECK_FALSE(PhysicsFEMTetraDamage::effective_compliance(1.0, 1.1, alpha));
	CHECK(alpha == 123.0);
}

TEST_CASE("[PhysicsFEM] Inverted tetrahedron cannot advance damage state") {
	Vector3 p[4];
	PhysicsFEMTetraRest rest;
	tetra(p, rest);
	p[3] = Vector3(0, 0, -1);
	double strain = 7.0;
	CHECK_FALSE(PhysicsFEMTetraDamage::equivalent_strain(p, rest, 0.3, strain));
	CHECK(strain == 7.0);
}

} // namespace TestPhysicsFEMTetraDamage
