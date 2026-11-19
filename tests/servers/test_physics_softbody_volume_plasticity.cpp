/**************************************************************************/
/*  test_physics_softbody_volume_plasticity.cpp                           */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_softbody_adiabatic_gas.h"
#include "servers/physics_softbody_volume_plasticity.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_volume_plasticity)

namespace TestPhysicsSoftBodyVolumePlasticity {

TEST_CASE("[PhysicsVolume] Closed body keeps an elastic range without permanent creep") {
	double rest = 1.0;
	CHECK_FALSE(physics_softbody_creep_rest_volume(1.1, 1.0, real_t(0.15), 1.0, rest));
	CHECK(rest == doctest::Approx(1.0));
	CHECK_FALSE(physics_softbody_creep_rest_volume(0.9, 1.0, real_t(0.15), 1.0, rest));
	CHECK(rest == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsVolume] Plastic swelling relaxes rest volume toward tensile yield boundary") {
	double rest = 1.0;
	CHECK(physics_softbody_creep_rest_volume(2.0, 1.0, real_t(0.25), 1.0, rest));
	CHECK(rest == doctest::Approx(1.6).epsilon(1e-6));
	CHECK_FALSE(physics_softbody_creep_rest_volume(2.0, 1.0, real_t(0.25), 1.0, rest));
}

TEST_CASE("[PhysicsVolume] Plastic crushing retains deformation under partial creep") {
	double rest = 1.0;
	CHECK(physics_softbody_creep_rest_volume(0.5, 1.0, real_t(0.2), 0.5, rest));
	CHECK(rest == doctest::Approx(0.8125).epsilon(1e-6));
	CHECK(rest > 0.5);
}

TEST_CASE("[PhysicsVolume] Closed surface with negative winding retains signed volume") {
	double rest = -1.0;
	CHECK(physics_softbody_creep_rest_volume(-2.0, -1.0, real_t(0.25), 1.0, rest));
	CHECK(rest == doctest::Approx(-1.6).epsilon(1e-6));
	CHECK_FALSE(physics_softbody_creep_rest_volume(2.0, -1.0, real_t(0.25), 1.0, rest));
	CHECK(rest == doctest::Approx(-1.6).epsilon(1e-6));
}

TEST_CASE("[PhysicsVolume] Permanent volume has a nonzero minimum and finite maximum") {
	double crushed = 1.0;
	CHECK(physics_softbody_creep_rest_volume(1e-9, 1.0, real_t(0.1), 1.0, crushed));
	CHECK(crushed == doctest::Approx(0.02));
	double expanded = 1.0;
	CHECK(physics_softbody_creep_rest_volume(1000.0, 1.0, real_t(0.1), 1.0, expanded));
	CHECK(expanded == doctest::Approx(20.0));
}

TEST_CASE("[PhysicsVolume] Exponential time subdivision produces equivalent plastic relaxation") {
	const double rate = 3.0;
	const double full_fraction = 1.0 - Math::exp(-rate * 0.2);
	const double half_fraction = 1.0 - Math::exp(-rate * 0.1);
	double full = 1.0, half = 1.0;
	CHECK(physics_softbody_creep_rest_volume(0.5, 1.0, real_t(0.1), full_fraction, full));
	CHECK(physics_softbody_creep_rest_volume(0.5, 1.0, real_t(0.1), half_fraction, half));
	CHECK(physics_softbody_creep_rest_volume(0.5, 1.0, real_t(0.1), half_fraction, half));
	CHECK(half == doctest::Approx(full).epsilon(1e-10));
}

TEST_CASE("[PhysicsVolume] Very small or large closed bodies creep without fixed-unit epsilon") {
	for (double scale : { 1e-120, 1e-30, 1e30, 1e120 }) {
		double rest = scale;
		CHECK(physics_softbody_creep_rest_volume(scale * 0.5, scale, real_t(0.1), 1.0, rest));
		CHECK(rest > scale * 0.5);
		CHECK(rest < scale);
		CHECK(Math::is_finite(rest));
	}
}

TEST_CASE("[PhysicsVolume] Gas pressure stays tied to original enclosed volume") {
	const double original = 1.0;
	double mechanical_rest = original;
	CHECK(physics_softbody_creep_rest_volume(0.5, original, real_t(0.1), 1.0, mechanical_rest));
	double gas_pressure = 0.0;
	CHECK(physics_softbody_adiabatic_pressure(original, 0.5, 1000.0, 1.4, gas_pressure));
	CHECK(gas_pressure == doctest::Approx(1000.0 * Math::pow(2.0, 1.4)).epsilon(1e-10));
	CHECK(mechanical_rest < original);
	CHECK(gas_pressure > 1000.0);
}

TEST_CASE("[PhysicsVolume] Invalid parameters and inverted meshes never change rest state") {
	const double nan = std::numeric_limits<double>::quiet_NaN();
	const double inf = std::numeric_limits<double>::infinity();
	double rest = -1.0;
	CHECK_FALSE(physics_softbody_creep_rest_volume(0.5, -1.0, real_t(0.1), 1.0, rest));
	CHECK_FALSE(physics_softbody_creep_rest_volume(-0.5, -1.0, real_t(-0.1), 1.0, rest));
	CHECK_FALSE(physics_softbody_creep_rest_volume(-0.5, -1.0, real_t(1.0), 1.0, rest));
	CHECK_FALSE(physics_softbody_creep_rest_volume(-0.5, -1.0, real_t(0.1), 0.0, rest));
	CHECK_FALSE(physics_softbody_creep_rest_volume(-0.5, -1.0, real_t(0.1), 1.1, rest));
	CHECK_FALSE(physics_softbody_creep_rest_volume(nan, -1.0, real_t(0.1), 1.0, rest));
	CHECK_FALSE(physics_softbody_creep_rest_volume(-inf, -1.0, real_t(0.1), 1.0, rest));
	CHECK_FALSE(physics_softbody_creep_rest_volume(-0.5, 0.0, real_t(0.1), 1.0, rest));
	CHECK(rest == doctest::Approx(-1.0));
}

} // namespace TestPhysicsSoftBodyVolumePlasticity
