/**************************************************************************/
/*  test_physics_softbody_orthotropic_bending.cpp                          */
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

#include "servers/physics_softbody_orthotropic_bending.h"
#include "servers/physics_xpbd_dihedral.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_orthotropic_bending)

namespace TestPhysicsSoftBodyOrthotropicBending {

static const Vector3 a(0, 0, 0), b(1, 0, 0), c(0, 1, 0), d(0, -1, 0);

TEST_CASE("[PhysicsOrthotropicBend] Isotropic ratio preserves legacy material") {
	real_t factor = real_t(-1);
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 0, 0), 1, factor));
	CHECK(factor == real_t(1));
}

TEST_CASE("[PhysicsOrthotropicBend] Warp-aligned fold uses original compliance") {
	real_t factor = real_t(-1);
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 0, 0), 20, factor));
	CHECK(factor == doctest::Approx(1.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Weft-aligned fold uses user ratio") {
	real_t factor = real_t(-1);
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(0, 1, 0), 20, factor));
	CHECK(factor == doctest::Approx(20.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Diagonal fold uses squared directional interpolation") {
	real_t factor = real_t(-1);
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 1, 0), 9, factor));
	CHECK(factor == doctest::Approx(5.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Weft direction can be stiffer than warp") {
	real_t factor = real_t(-1);
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(0, 1, 0), real_t(0.25), factor));
	CHECK(factor == doctest::Approx(0.25).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Reverse material axis has identical response") {
	real_t one = -1, reverse = -1;
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 2, 0), 4, one));
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(-1, -2, 0), 4, reverse));
	CHECK(one == doctest::Approx(reverse).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Reverse shared edge preserves bend ratio") {
	real_t one = -1, reverse = -1;
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 2, 0), 4, one));
	CHECK(physics_softbody_orthotropic_bending_ratio(b, a, d, c,
			Vector3(1, 2, 0), 4, reverse));
	CHECK(one == doctest::Approx(reverse).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Translation and uniform scaling preserve ratio") {
	real_t one = -1, shifted = -1, scaled = -1;
	const Vector3 warp(1, 2, 0);
	const Vector3 offset(100, -300, 500);
	const real_t scale = real_t(0.0001);
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d, warp, 4, one));
	CHECK(physics_softbody_orthotropic_bending_ratio(a + offset, b + offset,
			c + offset, d + offset, warp, 4, shifted));
	CHECK(physics_softbody_orthotropic_bending_ratio(a * scale, b * scale,
			c * scale, d * scale, warp, 4, scaled));
	CHECK(one == doctest::Approx(shifted).epsilon(1e-5));
	CHECK(one == doctest::Approx(scaled).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Tilting both mesh and fiber preserves material angle") {
	const Vector3 tilt_a(0, 0, 0), tilt_b(1, 0, 0);
	const Vector3 tilt_c(0, 0, 1), tilt_d(0, 0, -1);
	real_t flat = -1, tilted = -1;
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 1, 0), 9, flat));
	CHECK(physics_softbody_orthotropic_bending_ratio(tilt_a, tilt_b, tilt_c, tilt_d,
			Vector3(1, 0, 1), 9, tilted));
	CHECK(flat == doctest::Approx(tilted).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Warp normal component is ignored in tangent projection") {
	real_t one = -1, with_normal = -1;
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 1, 0), 4, one));
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 1, 100), 4, with_normal));
	CHECK(one == doctest::Approx(with_normal).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Opposite rest normals use first-face tangent fallback") {
	// Both triangles are geometrically on the same side of the hinge.
	real_t factor = -1;
	CHECK(physics_softbody_orthotropic_bending_ratio(a, b, c,
			Vector3(0, 2, 0), Vector3(0, 1, 0), 7, factor));
	CHECK(factor == doctest::Approx(7.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsOrthotropicBend] Normal-only fiber fails without mutating output") {
	real_t factor = real_t(42);
	CHECK_FALSE(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(0, 0, 1), 4, factor));
	CHECK(factor == real_t(42));
}

TEST_CASE("[PhysicsOrthotropicBend] Degenerate face and invalid ratio fail atomically") {
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	real_t factor = real_t(42);
	CHECK_FALSE(physics_softbody_orthotropic_bending_ratio(a, b, b * 2, d,
			Vector3(1, 0, 0), 4, factor));
	CHECK_FALSE(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(), 4, factor));
	CHECK_FALSE(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 0, 0), 0, factor));
	CHECK_FALSE(physics_softbody_orthotropic_bending_ratio(a, b, c, d,
			Vector3(1, 0, 0), nan, factor));
	CHECK(factor == real_t(42));
}

TEST_CASE("[PhysicsOrthotropicBend] Larger compliance produces a softer physical hinge") {
	// Three pinned particles, the last allowed to rotate the folded hinge.
	// Use a single XPBD correction to avoid dependence on iteration count.
	Vector3 a_stiff = a, b_stiff = b, c_stiff = c, d_stiff(0, -1, real_t(0.5));
	Vector3 a_soft = a, b_soft = b, c_soft = c, d_soft = d_stiff;
	real_t lambda_stiff = 0, lambda_soft = 0;
	real_t initial_angle = 0;
	CHECK(physics_xpbd_dihedral_angle(a, b, c, d_stiff, initial_angle));
	CHECK(physics_xpbd_solve_dihedral(a_stiff, b_stiff, c_stiff, d_stiff,
			0, 0, 0, 1, 0, real_t(0.1), lambda_stiff));
	CHECK(physics_xpbd_solve_dihedral(a_soft, b_soft, c_soft, d_soft,
			0, 0, 0, 1, 0, real_t(0.4), lambda_soft));
	real_t stiff_angle = 0, soft_angle = 0;
	CHECK(physics_xpbd_dihedral_angle(a_stiff, b_stiff, c_stiff, d_stiff, stiff_angle));
	CHECK(physics_xpbd_dihedral_angle(a_soft, b_soft, c_soft, d_soft, soft_angle));
	CHECK(Math::abs(stiff_angle) < Math::abs(soft_angle));
	CHECK(Math::abs(stiff_angle) < Math::abs(initial_angle));
	CHECK(a_stiff == a);
	CHECK(b_stiff == b);
	CHECK(c_stiff == c);
}

} // namespace TestPhysicsSoftBodyOrthotropicBending
