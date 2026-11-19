/**************************************************************************/
/*  test_physics_fem_lumped_mass.cpp                                      */
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

#include "servers/physics_fem_lumped_mass.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_lumped_mass)

namespace TestPhysicsFEMLumpedMass {

static LocalVector<PhysicsFEMConvexTetra> two_elements(double p_first = 1.0, double p_second = 3.0) {
	LocalVector<PhysicsFEMConvexTetra> tets;
	PhysicsFEMConvexTetra first;
	first.a = 0;
	first.b = 1;
	first.c = 2;
	first.d = 3;
	first.rest.volume = p_first;
	tets.push_back(first);

	PhysicsFEMConvexTetra second;
	second.a = 0;
	second.b = 2;
	second.c = 3;
	second.d = 4;
	second.rest.volume = p_second;
	tets.push_back(second);
	return tets;
}

TEST_CASE("[PhysicsFEMMass] Constant density lumps total tetra volume exactly") {
	const LocalVector<PhysicsFEMConvexTetra> tets = two_elements();
	LocalVector<double> fractions;
	LocalVector<real_t> inverse;
	REQUIRE(physics_fem_build_lumped_masses(5, tets, real_t(8.0), fractions, inverse));
	REQUIRE(fractions.size() == 5);
	REQUIRE(inverse.size() == 5);

	const double expected[] = { 0.25, 0.0625, 0.25, 0.25, 0.1875 };
	double total = 0.0;
	for (uint32_t i = 0; i < 5; ++i) {
		CHECK(fractions[i] == doctest::Approx(expected[i]).epsilon(1e-7));
		CHECK(double(inverse[i]) == doctest::Approx(1.0 / (8.0 * expected[i])).epsilon(1e-6));
		total += 1.0 / double(inverse[i]);
	}
	CHECK(total == doctest::Approx(8.0).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEMMass] One tetra yields four equal nodal masses") {
	const LocalVector<PhysicsFEMConvexTetra> tets = two_elements();
	LocalVector<PhysicsFEMConvexTetra> first_only;
	first_only.push_back(tets[0]);
	LocalVector<double> fractions;
	LocalVector<real_t> inverse;
	REQUIRE(physics_fem_build_lumped_masses(4, first_only, real_t(10.0), fractions, inverse));
	for (uint32_t i = 0; i < 4; ++i) {
		CHECK(fractions[i] == doctest::Approx(0.25));
		CHECK(double(inverse[i]) == doctest::Approx(0.4));
	}
}

TEST_CASE("[PhysicsFEMMass] Pinned node keeps fraction for exact unpin restoration") {
	LocalVector<double> fractions;
	LocalVector<real_t> inverse;
	REQUIRE(physics_fem_build_lumped_masses(5, two_elements(), real_t(8.0), fractions, inverse));
	// Physical pinning sets inverse mass to zero. Cache still retains m_i/M.
	const real_t pinned_inverse = real_t(0.0);
	CHECK(pinned_inverse == 0.0);
	CHECK(fractions[4] == doctest::Approx(0.1875));
	real_t restored_inverse = -1.0;
	CHECK(physics_fem_unpinned_inverse_mass(fractions, 4, real_t(8.0), restored_inverse));
	CHECK(restored_inverse == doctest::Approx(inverse[4]).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEMMass] Total-mass edits preserve material density proportions") {
	LocalVector<double> fractions;
	LocalVector<real_t> inverse;
	REQUIRE(physics_fem_build_lumped_masses(5, two_elements(), real_t(8.0), fractions, inverse));
	for (uint32_t i = 0; i < 5; ++i) {
		real_t updated = -1.0;
		REQUIRE(physics_fem_unpinned_inverse_mass(fractions, i, real_t(16.0), updated));
		CHECK(double(updated) == doctest::Approx(double(inverse[i]) * 0.5).epsilon(1e-6));
	}
}

TEST_CASE("[PhysicsFEMMass] Scaling all rest tet volumes leaves fractions invariant") {
	LocalVector<double> base;
	LocalVector<real_t> base_inverse;
	REQUIRE(physics_fem_build_lumped_masses(5, two_elements(), real_t(8.0), base, base_inverse));
	const double scale[] = { 1e-24, 1e60 };
	for (double s : scale) {
		LocalVector<double> weights;
		LocalVector<real_t> inverse;
		REQUIRE(physics_fem_build_lumped_masses(5, two_elements(s, 3.0 * s),
				real_t(8.0), weights, inverse));
		for (uint32_t i = 0; i < 5; ++i) {
			CHECK(weights[i] == doctest::Approx(base[i]).epsilon(1e-7));
			CHECK(double(inverse[i]) == doctest::Approx(double(base_inverse[i])).epsilon(1e-6));
		}
	}
}

TEST_CASE("[PhysicsFEMMass] Unused node rejects invalid cooking atomically") {
	LocalVector<double> fractions;
	LocalVector<real_t> inverse;
	REQUIRE(physics_fem_build_lumped_masses(5, two_elements(), real_t(8.0), fractions, inverse));
	CHECK_FALSE(physics_fem_build_lumped_masses(6, two_elements(), real_t(8.0), fractions, inverse));
	CHECK(fractions.size() == 5);
	CHECK(inverse.size() == 5);
	CHECK(fractions[4] == doctest::Approx(0.1875));
}

TEST_CASE("[PhysicsFEMMass] Bad tets and bad total mass never replace output") {
	LocalVector<double> fractions;
	LocalVector<real_t> inverse;
	REQUIRE(physics_fem_build_lumped_masses(5, two_elements(), real_t(8.0), fractions, inverse));

	LocalVector<PhysicsFEMConvexTetra> invalid = two_elements();
	invalid[0].b = invalid[0].a;
	CHECK_FALSE(physics_fem_build_lumped_masses(5, invalid, real_t(8.0), fractions, inverse));
	invalid = two_elements();
	invalid[1].d = 12345;
	CHECK_FALSE(physics_fem_build_lumped_masses(5, invalid, real_t(8.0), fractions, inverse));
	invalid = two_elements();
	invalid[1].rest.volume = 0.0;
	CHECK_FALSE(physics_fem_build_lumped_masses(5, invalid, real_t(8.0), fractions, inverse));
	invalid = two_elements();
	invalid[1].rest.volume = std::numeric_limits<double>::infinity();
	CHECK_FALSE(physics_fem_build_lumped_masses(5, invalid, real_t(8.0), fractions, inverse));
	CHECK_FALSE(physics_fem_build_lumped_masses(5, two_elements(), real_t(0.0), fractions, inverse));
	CHECK_FALSE(physics_fem_build_lumped_masses(5, two_elements(), real_t(-1.0), fractions, inverse));
	CHECK(fractions.size() == 5);
	CHECK(fractions[1] == doctest::Approx(0.0625));
}

TEST_CASE("[PhysicsFEMMass] Failed unpin inverse lookup preserves destination") {
	LocalVector<double> fractions;
	LocalVector<real_t> inverse;
	REQUIRE(physics_fem_build_lumped_masses(5, two_elements(), real_t(8.0), fractions, inverse));
	real_t result = real_t(123);
	CHECK_FALSE(physics_fem_unpinned_inverse_mass(fractions, 5, real_t(8.0), result));
	CHECK_FALSE(physics_fem_unpinned_inverse_mass(fractions, 0, real_t(0.0), result));
	CHECK(result == real_t(123));
}

} // namespace TestPhysicsFEMLumpedMass
