/**************************************************************************/
/*  test_physics_softbody_plasticity.cpp                                  */
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

#include "servers/physics_softbody_plasticity.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_plasticity)

namespace TestPhysicsSoftBodyPlasticity {

TEST_CASE("[PhysicsPlasticity] Elastic strain below yield does not change rest length") {
	real_t rest = real_t(1.0);
	CHECK_FALSE(physics_softbody_creep_rest_length(real_t(1.05), real_t(0.1), 1.0, rest));
	CHECK(rest == real_t(1.0));
	CHECK_FALSE(physics_softbody_creep_rest_length(real_t(1.5), real_t(0.1), 0.0, rest));
	CHECK(rest == real_t(1.0));
}

TEST_CASE("[PhysicsPlasticity] Tensile yielding leaves exactly allowed elastic stretch") {
	real_t rest = real_t(1.0);
	CHECK(physics_softbody_creep_rest_length(real_t(1.5), real_t(0.1), 1.0, rest));
	CHECK(rest == doctest::Approx(1.5 / 1.1).epsilon(1e-5));
	CHECK(real_t(1.5) / rest == doctest::Approx(1.1).epsilon(1e-5));
}

TEST_CASE("[PhysicsPlasticity] Compressive yielding permanently shortens rest length") {
	real_t rest = real_t(2.0);
	CHECK(physics_softbody_creep_rest_length(real_t(1.0), real_t(0.2), 1.0, rest));
	CHECK(rest == doctest::Approx(1.25).epsilon(1e-5));
	CHECK(real_t(1.0) / rest == doctest::Approx(0.8).epsilon(1e-5));
}

TEST_CASE("[PhysicsPlasticity] Creep integrates independent of subdivision for fixed strain") {
	const double half = 1.0 - Math::exp(-0.5);
	const double whole = 1.0 - Math::exp(-1.0);
	real_t one_step = real_t(1.0);
	real_t two_steps = real_t(1.0);
	CHECK(physics_softbody_creep_rest_length(real_t(1.8), real_t(0.1), whole, one_step));
	CHECK(physics_softbody_creep_rest_length(real_t(1.8), real_t(0.1), half, two_steps));
	CHECK(physics_softbody_creep_rest_length(real_t(1.8), real_t(0.1), half, two_steps));
	CHECK(two_steps == doctest::Approx(one_step).epsilon(1e-5));
}

TEST_CASE("[PhysicsPlasticity] Invalid inputs do not corrupt the rest state") {
	real_t rest = real_t(1.0);
	CHECK_FALSE(physics_softbody_creep_rest_length(real_t(1.5), real_t(-0.1), 0.5, rest));
	CHECK_FALSE(physics_softbody_creep_rest_length(real_t(1.5), real_t(0.1), 1.5, rest));
	CHECK_FALSE(physics_softbody_creep_rest_length(real_t(1.5), real_t(0.1), -0.1, rest));
	CHECK_FALSE(physics_softbody_creep_rest_length(real_t(0.0), real_t(0.1), 0.5, rest));
	CHECK_FALSE(physics_softbody_creep_rest_length(
			std::numeric_limits<real_t>::infinity(), real_t(0.1), 0.5, rest));
	CHECK(rest == real_t(1.0));
}

TEST_CASE("[PhysicsPlasticity] Unsafe squared rest length is rejected without mutation") {
	real_t rest = real_t(1e19);
	const real_t old = rest;
	CHECK_FALSE(physics_softbody_creep_rest_length(real_t(1e20), real_t(0.1), 1.0, rest));
	CHECK(rest == old);
}

} // namespace TestPhysicsSoftBodyPlasticity
