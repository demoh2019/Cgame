/**************************************************************************/
/*  test_physics_softbody_gas_leak.cpp                                    */
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

#include "servers/physics_softbody_gas_leak.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_gas_leak)

namespace TestPhysicsSoftBodyGasLeak {

TEST_CASE("[PhysicsGasLeak] Zero rate reproduces closed adiabatic pressure") {
	for (double gamma : { 1.0, 1.4, 2.0, 5.0 }) {
		double mass = 1.0;
		double pressure = 0.0;
		double sealed_pressure = 0.0;
		REQUIRE(physics_softbody_adiabatic_pressure(2.0, 0.8, 100.0, gamma, sealed_pressure));
		REQUIRE(physics_softbody_gas_leak_step(2.0, 0.8, 100.0, gamma,
				0.0, 1.0 / 60.0, mass, pressure));
		CHECK(mass == 1.0);
		CHECK(pressure == doctest::Approx(sealed_pressure).epsilon(1e-12));
	}
}

TEST_CASE("[PhysicsGasLeak] Isothermal deflation at rest follows exponential mass loss") {
	double mass = 1.0;
	double pressure = 0.0;
	REQUIRE(physics_softbody_gas_leak_step(1.0, 1.0, 100.0, 1.0,
			1.0, 1.0, mass, pressure));
	CHECK(mass == doctest::Approx(Math::exp(-1.0)).epsilon(1e-12));
	CHECK(pressure == doctest::Approx(100.0 * Math::exp(-1.0)).epsilon(1e-12));
}

TEST_CASE("[PhysicsGasLeak] Compressing the shell accelerates pressure-driven discharge") {
	double compressed_mass = 1.0;
	double expanded_mass = 1.0;
	double compressed_pressure = 0.0;
	double expanded_pressure = 0.0;
	REQUIRE(physics_softbody_gas_leak_step(1.0, 0.5, 100.0, 1.4,
			2.0, 0.1, compressed_mass, compressed_pressure));
	REQUIRE(physics_softbody_gas_leak_step(1.0, 2.0, 100.0, 1.4,
			2.0, 0.1, expanded_mass, expanded_pressure));
	CHECK(compressed_mass < expanded_mass);
	CHECK(compressed_pressure > 0);
	CHECK(expanded_pressure > 0);
}

TEST_CASE("[PhysicsGasLeak] Repeated updates are passive and pressure eventually vanishes") {
	double mass = 1.0;
	double pressure = 0.0;
	double previous_mass = 1.0;
	for (int i = 0; i < 10000; ++i) {
		REQUIRE(physics_softbody_gas_leak_step(1.0, 1.0, 100.0, 1.4,
				4.0, 1.0 / 60.0, mass, pressure));
		CHECK(mass >= 0.0);
		CHECK(mass <= previous_mass);
		CHECK(Math::is_finite(pressure));
		previous_mass = mass;
	}
	CHECK(mass < 0.01);
	CHECK(pressure < 1.0);
}

TEST_CASE("[PhysicsGasLeak] Zero mass, zero step and extreme flow never overcharge") {
	double mass = 0.0;
	double pressure = -100.0;
	REQUIRE(physics_softbody_gas_leak_step(2.0, 1.0, 100.0, 1.4,
			1.0, 0.02, mass, pressure));
	CHECK(mass == 0.0);
	CHECK(pressure == 0.0);
	mass = 1.0;
	REQUIRE(physics_softbody_gas_leak_step(2.0, 1.0, 100.0, 1.4,
			1000.0, 0.0, mass, pressure));
	CHECK(mass == 1.0);
	mass = 1.0;
	REQUIRE(physics_softbody_gas_leak_step(2.0, 0.01, 100.0, 5.0,
			1e100, 1e100, mass, pressure));
	CHECK(mass >= 0.0);
	CHECK(mass <= 1.0);
	CHECK(Math::is_finite(pressure));
}

TEST_CASE("[PhysicsGasLeak] Inverted or nonmanifold geometry cannot mutate gas charge") {
	double mass = 0.65;
	double pressure = 87.0;
	CHECK_FALSE(physics_softbody_gas_leak_step(1.0, -1.0, 100.0, 1.4,
			1.0, 1.0, mass, pressure));
	CHECK_FALSE(physics_softbody_gas_leak_step(1.0, 0.0, 100.0, 1.4,
			1.0, 1.0, mass, pressure));
	CHECK_FALSE(physics_softbody_gas_leak_step(0.0, 1.0, 100.0, 1.4,
			1.0, 1.0, mass, pressure));
	CHECK(mass == 0.65);
	CHECK(pressure == 87.0);
}

TEST_CASE("[PhysicsGasLeak] Invalid rate, timestep, gamma or mass is atomic") {
	const double infinity = std::numeric_limits<double>::infinity();
	for (double invalid_rate : { -1.0, infinity }) {
		double mass = 0.6;
		double pressure = 37.0;
		CHECK_FALSE(physics_softbody_gas_leak_step(1.0, 1.0, 100.0, 1.4,
				invalid_rate, 0.1, mass, pressure));
		CHECK(mass == 0.6);
		CHECK(pressure == 37.0);
	}
	double mass = 0.6, pressure = 37.0;
	CHECK_FALSE(physics_softbody_gas_leak_step(1.0, 1.0, 100.0, 1.4,
			1.0, -0.1, mass, pressure));
	CHECK_FALSE(physics_softbody_gas_leak_step(1.0, 1.0, 100.0, 0.0,
			1.0, 0.1, mass, pressure));
	mass = -1.0;
	CHECK_FALSE(physics_softbody_gas_leak_step(1.0, 1.0, 100.0, 1.4,
			1.0, 0.1, mass, pressure));
	CHECK(mass == -1.0);
	CHECK(pressure == 37.0);
}

} // namespace TestPhysicsSoftBodyGasLeak
