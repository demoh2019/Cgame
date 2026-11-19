/**************************************************************************/
/*  test_physics_softbody_progressive_damage.cpp                          */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_softbody_progressive_damage.h"
#include "servers/physics_xpbd_distance.h"
#include "servers/physics_xpbd_tension_hardening.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_progressive_damage)

namespace TestPhysicsSoftBodyProgressiveDamage {

TEST_CASE("[PhysicsSoftDamage] Compression and sub-yield tension cause no damage") {
	real_t d = 0.0;
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(real_t(0.5), 0, 0),
			1, real_t(0.1), real_t(0.6), 10, 1, d));
	CHECK(d == 0.0);
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(real_t(1.05), 0, 0),
			1, real_t(0.1), real_t(0.6), 10, 1, d));
	CHECK(d == 0.0);
}

TEST_CASE("[PhysicsSoftDamage] Rate dependent accumulation matches analytic relaxation") {
	real_t d = 0.0;
	// e=0.35; y=0.1; f=0.6 -> target=0.95*(0.25/0.5)=0.475.
	const real_t rate = real_t(0.6931471805599453);
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(real_t(1.35), 0, 0),
			1, real_t(0.1), real_t(0.6), rate, 1, d));
	CHECK(d == doctest::Approx(0.2375).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftDamage] Damage accumulates monotonically under sustained strain") {
	real_t d = 0.0;
	real_t previous = 0.0;
	for (int i = 0; i < 100; ++i) {
		CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(2, 0, 0),
				1, real_t(0.1), real_t(0.6), 2, real_t(0.01), d));
		CHECK(d >= previous);
		CHECK(d <= real_t(0.95));
		previous = d;
	}
	CHECK(d > 0.8);
}

TEST_CASE("[PhysicsSoftDamage] Unloading and compression do not heal damage") {
	real_t d = real_t(0.5);
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(1, 0, 0),
			1, 0.1, 0.6, 10, 1, d));
	CHECK(d == real_t(0.5));
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(0.5, 0, 0),
			1, 0.1, 0.6, 10, 1, d));
	CHECK(d == real_t(0.5));
}

TEST_CASE("[PhysicsSoftDamage] Strong overload never destroys a link") {
	real_t d = 0.0;
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(5, 0, 0),
			1, real_t(0.1), real_t(0.6), 1000, 1, d));
	CHECK(d == doctest::Approx(0.95).epsilon(1e-5));
	real_t alpha = 0;
	CHECK(physics_softbody_progressive_damage_alpha(real_t(0.1), d, alpha));
	CHECK(alpha == doctest::Approx(2.0).epsilon(1e-4));
	CHECK(alpha > 0.0);
}

TEST_CASE("[PhysicsSoftDamage] Disabling rate or time step preserves existing material history") {
	real_t d = real_t(0.2);
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(5, 0, 0),
			1, real_t(0.1), real_t(0.6), 0, 1, d));
	CHECK(d == real_t(0.2));
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(5, 0, 0),
			1, real_t(0.1), real_t(0.6), 10, 0, d));
	CHECK(d == real_t(0.2));
}

TEST_CASE("[PhysicsSoftDamage] Time step subdivision gives equivalent damage") {
	real_t one = 0;
	real_t two = 0;
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(5, 0, 0),
			1, real_t(0.1), real_t(0.6), 3, 1, one));
	for (int i = 0; i < 2; ++i) {
		CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(5, 0, 0),
				1, real_t(0.1), real_t(0.6), 3, real_t(0.5), two));
	}
	CHECK(one == doctest::Approx(two).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftDamage] Stretched link with preexisting high damage stays unchanged") {
	real_t d = real_t(0.7);
	CHECK(physics_softbody_progressive_tension_damage(Vector3(), Vector3(real_t(1.2), 0, 0),
			1, real_t(0.1), real_t(0.6), 100, 1, d));
	CHECK(d == real_t(0.7));
}

TEST_CASE("[PhysicsSoftDamage] Symmetry under translation and reversed links") {
	real_t original = 0, reversed = 0, translated = 0;
	const Vector3 p0(1, 2, 3);
	const Vector3 p1(2.5, 2, 3);
	CHECK(physics_softbody_progressive_tension_damage(p0, p1,
			1, 0.1, 0.6, 3, 1, original));
	CHECK(physics_softbody_progressive_tension_damage(p1, p0,
			1, 0.1, 0.6, 3, 1, reversed));
	const Vector3 shift(100, 200, 300);
	CHECK(physics_softbody_progressive_tension_damage(p0 + shift, p1 + shift,
			1, 0.1, 0.6, 3, 1, translated));
	CHECK(original == doctest::Approx(reversed).epsilon(1e-5));
	CHECK(original == doctest::Approx(translated).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftDamage] Compliance scaling preserves zero alpha and saturates huge alpha") {
	real_t alpha = real_t(-1.0);
	CHECK(physics_softbody_progressive_damage_alpha(0, real_t(0.5), alpha));
	CHECK(alpha == 0.0);
	CHECK(physics_softbody_progressive_damage_alpha(real_t(0.3), 0, alpha));
	CHECK(alpha == real_t(0.3));
	CHECK(physics_softbody_progressive_damage_alpha(real_t(0.3), real_t(0.5), alpha));
	CHECK(alpha == doctest::Approx(0.6).epsilon(1e-5));
	const real_t max_finite = std::numeric_limits<real_t>::max();
	CHECK(physics_softbody_progressive_damage_alpha(max_finite, real_t(0.5), alpha));
	CHECK(alpha == max_finite);
}

TEST_CASE("[PhysicsSoftDamage] Actual XPBD solver weakens damaged links under extension") {
	Vector3 normal_a, normal_b(1.5, 0, 0);
	Vector3 damaged_a, damaged_b(1.5, 0, 0);
	real_t alpha = 0;
	CHECK(physics_softbody_progressive_damage_alpha(real_t(0.1), real_t(0.6), alpha));
	CHECK(alpha > real_t(0.1));
	real_t normal_lambda = 0, damaged_lambda = 0;
	for (int i = 0; i < 16; ++i) {
		CHECK(physics_xpbd_solve_distance(normal_a, normal_b,
				1, 1, 1, real_t(0.1), normal_lambda));
		CHECK(physics_xpbd_solve_distance(damaged_a, damaged_b,
				1, 1, 1, alpha, damaged_lambda));
	}
	CHECK((damaged_b - damaged_a).length() > (normal_b - normal_a).length());
	CHECK(damaged_b.is_finite());
	CHECK(damaged_a.is_finite());
}

TEST_CASE("[PhysicsSoftDamage] Damage composes with nonlinear tensile hardening") {
	const Vector3 a, b(1.5, 0, 0);
	real_t tension_alpha = 1.0;
	CHECK(physics_xpbd_tension_hardening_alpha(a, b,
			1, 1, real_t(0.1), 100, tension_alpha));
	CHECK(tension_alpha < 1);
	real_t combined_alpha = 0;
	CHECK(physics_softbody_progressive_damage_alpha(tension_alpha, real_t(0.5), combined_alpha));
	CHECK(combined_alpha > tension_alpha);
	CHECK(combined_alpha == doctest::Approx(double(tension_alpha) * 2).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftDamage] Invalid inputs preserve damage and alpha atomically") {
	const real_t inf = std::numeric_limits<real_t>::infinity();
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	real_t d = real_t(0.2), alpha = real_t(42);
	CHECK_FALSE(physics_softbody_progressive_tension_damage(Vector3(inf, 0, 0), Vector3(),
			1, real_t(0.1), real_t(0.6), 1, 1, d));
	CHECK_FALSE(physics_softbody_progressive_tension_damage(Vector3(), Vector3(),
			0, real_t(0.1), real_t(0.6), 1, 1, d));
	CHECK_FALSE(physics_softbody_progressive_tension_damage(Vector3(), Vector3(),
			1, real_t(0.6), real_t(0.1), 1, 1, d));
	CHECK_FALSE(physics_softbody_progressive_tension_damage(Vector3(), Vector3(),
			1, real_t(0.1), real_t(0.6), -1, 1, d));
	CHECK_FALSE(physics_softbody_progressive_tension_damage(Vector3(), Vector3(),
			1, real_t(0.1), real_t(0.6), 1, -1, d));
	CHECK_FALSE(physics_softbody_progressive_tension_damage(Vector3(), Vector3(),
			1, real_t(0.1), real_t(0.6), 1, nan, d));
	CHECK(d == real_t(0.2));
	CHECK_FALSE(physics_softbody_progressive_damage_alpha(-1, real_t(0.2), alpha));
	CHECK_FALSE(physics_softbody_progressive_damage_alpha(1, real_t(0.96), alpha));
	CHECK_FALSE(physics_softbody_progressive_damage_alpha(inf, real_t(0.2), alpha));
	CHECK(alpha == real_t(42));
}

} // namespace TestPhysicsSoftBodyProgressiveDamage
