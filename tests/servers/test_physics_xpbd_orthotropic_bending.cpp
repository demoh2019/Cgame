/**************************************************************************/
/*  test_physics_xpbd_orthotropic_bending.cpp                             */
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

#include "servers/physics_xpbd_anisotropic_stretch.h"
#include "servers/physics_xpbd_dihedral.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_orthotropic_bending)

namespace TestPhysicsXPBDOrthotropicBending {

// A hinge crease is the shared rest edge. Its compliance is directed by
// that edge in the original fiber frame, not by live bent-world geometry.
static bool bend_alpha(
        const Vector3 &p_a, const Vector3 &p_b,
        const Vector3 &p_fiber, real_t p_base,
        real_t p_ratio, real_t &r_alpha) {
    return physics_xpbd_anisotropic_stretch_alpha(
            p_a, p_b, p_fiber, p_base, p_ratio, r_alpha);
}

TEST_CASE("[PhysicsXPBD] Orthotropic bend differentiates parallel and transverse creases") {
    real_t parallel = 100;
    real_t transverse = 100;
    real_t diagonal = 100;
    const Vector3 fiber(1, 0, 0);
    CHECK(bend_alpha(Vector3(), Vector3(2, 0, 0), fiber, 1, real_t(0.2), parallel));
    CHECK(bend_alpha(Vector3(), Vector3(0, 0, 2), fiber, 1, real_t(0.2), transverse));
    CHECK(bend_alpha(Vector3(), Vector3(2, 0, 2), fiber, 1, real_t(0.2), diagonal));
    CHECK(parallel == doctest::Approx(0.2));
    CHECK(transverse == doctest::Approx(1.0));
    CHECK(diagonal == doctest::Approx(0.6));
}

TEST_CASE("[PhysicsXPBD] Orthotropic bend can soften or stiffen along a fiber") {
    real_t stiff = 1, soft = 1;
    CHECK(bend_alpha(Vector3(), Vector3(1, 0, 0),
            Vector3(1, 0, 0), 1, real_t(0.1), stiff));
    CHECK(bend_alpha(Vector3(), Vector3(1, 0, 0),
            Vector3(1, 0, 0), 1, real_t(5.0), soft));
    CHECK(stiff < real_t(1.0));
    CHECK(soft > real_t(1.0));
}

TEST_CASE("[PhysicsXPBD] Default bend ratio is strictly isotropic") {
    const real_t input = real_t(0.023);
    real_t output = real_t(100);
    CHECK(bend_alpha(Vector3(), Vector3(2, 1, -2),
            Vector3(17, -2, 5), input, 1.0, output));
    CHECK(output == input);
}

TEST_CASE("[PhysicsXPBD] Orthotropic bend is unchanged by rigid rotation of rest frame") {
    real_t x = 0, z = 0;
    CHECK(bend_alpha(Vector3(), Vector3(2, 1, 0),
            Vector3(1, 0, 0), 1, real_t(0.3), x));
    CHECK(bend_alpha(Vector3(), Vector3(0, 1, -2),
            Vector3(0, 0, -1), 1, real_t(0.3), z));
    CHECK(x == doctest::Approx(z));
}

TEST_CASE("[PhysicsXPBD] Orthotropic bend is independent of fiber magnitude and sign") {
    real_t normalized = 0, long_axis = 0, reversed = 0;
    CHECK(bend_alpha(Vector3(), Vector3(2, 1, 0),
            Vector3(1, 0, 0), 1, real_t(0.5), normalized));
    CHECK(bend_alpha(Vector3(), Vector3(2, 1, 0),
            Vector3(1e9, 0, 0), 1, real_t(0.5), long_axis));
    CHECK(bend_alpha(Vector3(), Vector3(2, 1, 0),
            Vector3(-1e9, 0, 0), 1, real_t(0.5), reversed));
    CHECK(normalized == doctest::Approx(long_axis));
    CHECK(normalized == doctest::Approx(reversed));
}

TEST_CASE("[PhysicsXPBD] XPBD hinge solver accepts rest-axis-dependent compliance") {
    // Flat hinge: (a,b,c) and (b,a,d) share (a,b).
    const Vector3 base_a, base_b(1, 0, 0), base_c(0, 0, 1);
    const Vector3 initial_d(0, real_t(0.35), -1);
    Vector3 stiff_a = base_a, stiff_b = base_b, stiff_c = base_c, stiff_d = initial_d;
    Vector3 soft_a = base_a, soft_b = base_b, soft_c = base_c, soft_d = initial_d;
    real_t stiff_alpha = 1.0, soft_alpha = 1.0;
    CHECK(bend_alpha(base_a, base_b, Vector3(1, 0, 0),
            1, real_t(0.1), stiff_alpha));
    CHECK(bend_alpha(base_a, base_b, Vector3(1, 0, 0),
            1, real_t(5.0), soft_alpha));
    real_t lambda_stiff = 0, lambda_soft = 0;
    real_t initial_angle = 0;
    CHECK(physics_xpbd_dihedral_angle(base_a, base_b, base_c, initial_d, initial_angle));
    CHECK(Math::abs(initial_angle) > real_t(0.01));
    for (int i = 0; i < 12; ++i) {
        CHECK(physics_xpbd_solve_dihedral(
                stiff_a, stiff_b, stiff_c, stiff_d,
                0, 0, 0, 1, 0, stiff_alpha, lambda_stiff));
        CHECK(physics_xpbd_solve_dihedral(
                soft_a, soft_b, soft_c, soft_d,
                0, 0, 0, 1, 0, soft_alpha, lambda_soft));
    }
    real_t angle_stiff = 0, angle_soft = 0;
    CHECK(physics_xpbd_dihedral_angle(stiff_a, stiff_b, stiff_c, stiff_d, angle_stiff));
    CHECK(physics_xpbd_dihedral_angle(soft_a, soft_b, soft_c, soft_d, angle_soft));
    CHECK(stiff_a == base_a);
    CHECK(stiff_b == base_b);
    CHECK(stiff_c == base_c);
    CHECK(soft_a == base_a);
    CHECK(soft_b == base_b);
    CHECK(soft_c == base_c);
    CHECK(Math::abs(angle_stiff) < Math::abs(angle_soft));
    CHECK(Math::abs(angle_soft) <= Math::abs(initial_angle));
}

TEST_CASE("[PhysicsXPBD] Collapsed rest crease uses original isotropic compliance") {
    real_t alpha = 99;
    CHECK(bend_alpha(Vector3(), Vector3(), Vector3(1, 0, 0),
            real_t(0.25), 5, alpha));
    CHECK(alpha == real_t(0.25));
}

TEST_CASE("[PhysicsXPBD] Invalid orthotropic bend material cannot modify compliance") {
    const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
    real_t alpha = real_t(42);
    CHECK_FALSE(bend_alpha(Vector3(nan, 0, 0), Vector3(1, 0, 0),
            Vector3(1, 0, 0), 1, 0.5, alpha));
    CHECK_FALSE(bend_alpha(Vector3(), Vector3(1, 0, 0),
            Vector3(nan, 0, 0), 1, 0.5, alpha));
    CHECK_FALSE(bend_alpha(Vector3(), Vector3(1, 0, 0),
            Vector3(), 1, 0.5, alpha));
    CHECK_FALSE(bend_alpha(Vector3(), Vector3(1, 0, 0),
            Vector3(1, 0, 0), 1, 0, alpha));
    CHECK_FALSE(bend_alpha(Vector3(), Vector3(1, 0, 0),
            Vector3(1, 0, 0), -1, 1, alpha));
    CHECK(alpha == real_t(42));
}

} // namespace TestPhysicsXPBDOrthotropicBending
