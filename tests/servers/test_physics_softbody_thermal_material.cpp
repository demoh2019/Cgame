/**************************************************************************/
/*  test_physics_softbody_thermal_material.cpp                            */
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

#include "servers/physics_softbody_thermal_material.h"
#include "servers/physics_xpbd_distance.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_thermal_material)

namespace TestPhysicsSoftBodyThermalMaterial {

TEST_CASE("[PhysicsThermal] Two-node conduction preserves mean temperature") {
	real_t a = 0, b = 100;
	CHECK(physics_softbody_thermal_exchange_pair(a, b, 1, 1));
	CHECK(a == doctest::Approx(43.2332358).epsilon(1e-5));
	CHECK(b == doctest::Approx(56.7667642).epsilon(1e-5));
	CHECK(double(a) + double(b) == doctest::Approx(100.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Conduction conserves heat through a three-node link chain") {
	real_t a = 100, b = 0, c = 0;
	for (int i = 0; i < 50; ++i) {
		CHECK(physics_softbody_thermal_exchange_pair(a, b, 2, real_t(0.02)));
		CHECK(physics_softbody_thermal_exchange_pair(b, c, 2, real_t(0.02)));
		CHECK(a >= 0.0);
		CHECK(b >= 0.0);
		CHECK(c >= 0.0);
		CHECK(a <= 100);
		CHECK(b <= 100);
		CHECK(c <= 100);
	}
	CHECK(double(a) + double(b) + double(c) == doctest::Approx(100.0).epsilon(1e-4));
	CHECK(c > real_t(10.0));
}

TEST_CASE("[PhysicsThermal] Extreme rate is bounded and reaches pairwise mean") {
	real_t a = real_t(-100), b = real_t(900);
	CHECK(physics_softbody_thermal_exchange_pair(a, b, 1000, 10));
	CHECK(a == doctest::Approx(400.0));
	CHECK(b == doctest::Approx(400.0));
}

TEST_CASE("[PhysicsThermal] Conduction is stable under timestep splitting") {
	real_t one_a = 0, one_b = 100;
	real_t many_a = 0, many_b = 100;
	CHECK(physics_softbody_thermal_exchange_pair(one_a, one_b, 2, 1));
	for (int i = 0; i < 10; ++i) {
		CHECK(physics_softbody_thermal_exchange_pair(many_a, many_b,
				2, real_t(0.1)));
	}
	CHECK(one_a == doctest::Approx(many_a).epsilon(1e-5));
	CHECK(one_b == doctest::Approx(many_b).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Conduction is symmetric under exchanging node order") {
	real_t a = 7, b = 200, reversed_a = b, reversed_b = a;
	CHECK(physics_softbody_thermal_exchange_pair(a, b, 2, 0.25));
	CHECK(physics_softbody_thermal_exchange_pair(reversed_a, reversed_b, 2, 0.25));
	CHECK(a == doctest::Approx(reversed_b).epsilon(1e-5));
	CHECK(b == doctest::Approx(reversed_a).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] No conduction at zero rate, zero timestep or equal temperatures") {
	real_t a = 50, b = 120;
	CHECK(physics_softbody_thermal_exchange_pair(a, b, 0, 1));
	CHECK(physics_softbody_thermal_exchange_pair(a, b, 100, 0));
	CHECK(a == 50);
	CHECK(b == 120);
	real_t c = 50;
	CHECK(physics_softbody_thermal_exchange_pair(a, c, 20, 1));
	CHECK(a == 50);
	CHECK(c == 50);
}

TEST_CASE("[PhysicsThermal] Ambient exchange follows analytic cooling curve") {
	real_t temp = 100;
	CHECK(physics_softbody_thermal_relax(temp, 20, real_t(0.69314718056), 1));
	CHECK(temp == doctest::Approx(60.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Cooling and heating stay inside bath bounds") {
	real_t cool = 100, heat = -100;
	CHECK(physics_softbody_thermal_relax(cool, 20, 1000, 100));
	CHECK(physics_softbody_thermal_relax(heat, 150, 1000, 100));
	CHECK(cool == real_t(20));
	CHECK(heat == real_t(150));
}

TEST_CASE("[PhysicsThermal] Bath exchange is invariant under step subdivision") {
	real_t one = 100, many = 100;
	CHECK(physics_softbody_thermal_relax(one, 20, 1, 1));
	for (int i = 0; i < 10; ++i) {
		CHECK(physics_softbody_thermal_relax(many, 20, 1, real_t(0.1)));
	}
	CHECK(one == doctest::Approx(many).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Uniform temperature above ambient expands links") {
	real_t result = -1;
	CHECK(physics_softbody_thermal_expanded_rest_length(
			2, 100, 100, 20, real_t(0.001), result));
	CHECK(result == doctest::Approx(2.16).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Mean endpoint temperature drives expansion") {
	real_t result = -1;
	CHECK(physics_softbody_thermal_expanded_rest_length(
			2, 100, 20, 20, real_t(0.001), result));
	CHECK(result == doctest::Approx(2.08).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Cold material contracts relative to reference temperature") {
	real_t result = -1;
	CHECK(physics_softbody_thermal_expanded_rest_length(
			2, -100, -100, 20, real_t(0.001), result));
	CHECK(result == doctest::Approx(1.76).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Negative coefficient yields reversible thermal contraction") {
	real_t result = -1;
	CHECK(physics_softbody_thermal_expanded_rest_length(
			2, 100, 100, 20, real_t(-0.001), result));
	CHECK(result == doctest::Approx(1.84).epsilon(1e-5));
	CHECK(physics_softbody_thermal_expanded_rest_length(
			2, 20, 20, 20, real_t(-0.001), result));
	CHECK(result == doctest::Approx(2.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Extreme thermal expansion is safely bounded") {
	real_t result = -1;
	CHECK(physics_softbody_thermal_expanded_rest_length(
			2, 2000, 2000, 20, 1000, result));
	CHECK(result == doctest::Approx(8.0));
	CHECK(physics_softbody_thermal_expanded_rest_length(
			2, 2000, 2000, 20, -1000, result));
	CHECK(result == doctest::Approx(0.5));
}

TEST_CASE("[PhysicsThermal] Thermal expansion modifies actual XPBD spring equilibrium") {
	Vector3 a, b(1.2, 0, 0), c, d(1.2, 0, 0);
	real_t lambda_baseline = 0, lambda_hot = 0;
	real_t hot_length = 1;
	CHECK(physics_softbody_thermal_expanded_rest_length(
			1, 220, 220, 20, real_t(0.001), hot_length));
	CHECK(hot_length == doctest::Approx(1.2).epsilon(1e-5));
	CHECK(physics_xpbd_solve_distance(a, b, 1, 1, 1, real_t(0.01), lambda_baseline));
	CHECK(physics_xpbd_solve_distance(c, d, 1, 1, hot_length, real_t(0.01), lambda_hot));
	CHECK((b - a).length() < (d - c).length());
	CHECK(lambda_hot == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsThermal] Heat-source sphere is symmetric and uses world coordinates") {
	CHECK(physics_softbody_thermal_in_source(Vector3(100, 101, 102),
			Vector3(100, 100, 102), real_t(1.0)));
	CHECK_FALSE(physics_softbody_thermal_in_source(Vector3(100, 102, 102),
			Vector3(100, 100, 102), real_t(1.0)));
	CHECK(physics_softbody_thermal_in_source(Vector3(1, 0, 0),
			Vector3(), real_t(1.0)));
}

TEST_CASE("[PhysicsThermal] Source with radius zero remains disabled") {
	CHECK_FALSE(physics_softbody_thermal_in_source(Vector3(), Vector3(), 0));
	CHECK_FALSE(physics_softbody_thermal_in_source(Vector3(), Vector3(), -1));
}

TEST_CASE("[PhysicsThermal] Invalid thermal exchange and bath inputs are atomic") {
	real_t a = 50, b = 120;
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK_FALSE(physics_softbody_thermal_exchange_pair(a, b, -1, 1));
	CHECK_FALSE(physics_softbody_thermal_exchange_pair(a, b, nan, 1));
	CHECK_FALSE(physics_softbody_thermal_exchange_pair(a, b, 1, -1));
	CHECK_FALSE(physics_softbody_thermal_relax(a, nan, 1, 1));
	CHECK_FALSE(physics_softbody_thermal_relax(a, 20, -1, 1));
	CHECK(a == 50);
	CHECK(b == 120);
}

TEST_CASE("[PhysicsThermal] Invalid rest expansion leaves output unchanged") {
	real_t output = 77;
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	const real_t inf = std::numeric_limits<real_t>::infinity();
	CHECK_FALSE(physics_softbody_thermal_expanded_rest_length(
			0, 20, 20, 20, real_t(0.001), output));
	CHECK_FALSE(physics_softbody_thermal_expanded_rest_length(
			1, nan, 20, 20, real_t(0.001), output));
	CHECK_FALSE(physics_softbody_thermal_expanded_rest_length(
			1, 20, 20, 20, inf, output));
	CHECK_FALSE(physics_softbody_thermal_expanded_rest_length(
			std::numeric_limits<real_t>::max(), 2000, 2000, 20, real_t(0.01), output));
	CHECK(output == 77);
}

} // namespace TestPhysicsSoftBodyThermalMaterial
