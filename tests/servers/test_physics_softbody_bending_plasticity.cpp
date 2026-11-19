/**************************************************************************/
/*  test_physics_softbody_bending_plasticity.cpp                          */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_softbody_bending_plasticity.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_bending_plasticity)

namespace TestPhysicsSoftBodyBendingPlasticity {

TEST_CASE("[PhysicsBendingPlasticity] Elastic folds do not creep") {
	real_t rest = real_t(0.1);
	CHECK_FALSE(physics_softbody_creep_rest_dihedral(real_t(0.15), real_t(0.1), 1.0, rest));
	CHECK(rest == doctest::Approx(0.1));
	CHECK_FALSE(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(0.1), 0.0, rest));
	CHECK(rest == doctest::Approx(0.1));
}

TEST_CASE("[PhysicsBendingPlasticity] Positive and negative folds respect yield angle") {
	real_t rest_positive = real_t(0.0);
	real_t rest_negative = real_t(0.0);
	CHECK(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(0.2), 1.0, rest_positive));
	CHECK(physics_softbody_creep_rest_dihedral(real_t(-1.0), real_t(0.2), 1.0, rest_negative));
	CHECK(rest_positive == doctest::Approx(0.8).epsilon(1e-5));
	CHECK(rest_negative == doctest::Approx(-0.8).epsilon(1e-5));
}

TEST_CASE("[PhysicsBendingPlasticity] Branch cut uses the short arc") {
	real_t rest = real_t(3.13);
	CHECK_FALSE(physics_softbody_creep_rest_dihedral(real_t(-3.13), real_t(0.05), 1.0, rest));
	CHECK(rest == doctest::Approx(3.13));
	CHECK(physics_softbody_creep_rest_dihedral(real_t(-3.13), real_t(0.01), 1.0, rest));
	const double distance = Math::atan2(Math::sin(double(-3.13) - double(rest)),
			Math::cos(double(-3.13) - double(rest)));
	CHECK(Math::abs(distance) == doctest::Approx(0.01).epsilon(1e-4));
}

TEST_CASE("[PhysicsBendingPlasticity] Exponential creep is timestep subdivision independent") {
	const double whole = 1.0 - Math::exp(-1.0);
	const double half = 1.0 - Math::exp(-0.5);
	real_t one_step = real_t(0.0);
	real_t two_steps = real_t(0.0);
	CHECK(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(0.2), whole, one_step));
	CHECK(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(0.2), half, two_steps));
	CHECK(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(0.2), half, two_steps));
	CHECK(two_steps == doctest::Approx(one_step).epsilon(1e-5));
}

TEST_CASE("[PhysicsBendingPlasticity] Invalid inputs preserve rest angle") {
	real_t rest = real_t(0.25);
	CHECK_FALSE(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(-0.1), 1.0, rest));
	CHECK_FALSE(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(0.1), 1.5, rest));
	CHECK_FALSE(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(0.1), -0.1, rest));
	CHECK_FALSE(physics_softbody_creep_rest_dihedral(real_t(1.0), real_t(3.2), 1.0, rest));
	CHECK_FALSE(physics_softbody_creep_rest_dihedral(
			std::numeric_limits<real_t>::infinity(), real_t(0.1), 1.0, rest));
	CHECK(rest == doctest::Approx(0.25));
}

} // namespace TestPhysicsSoftBodyBendingPlasticity
