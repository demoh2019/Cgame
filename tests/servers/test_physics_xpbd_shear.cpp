/**************************************************************************/
/*  test_physics_xpbd_shear.cpp                                             */
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
#include "servers/physics_xpbd_shear.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_shear)

namespace TestPhysicsXPBDShear {

TEST_CASE("[PhysicsXPBD] Triangle shear reduces off-diagonal strain") {
    Vector3 a, b(1, 0, 0), c(real_t(0.5), 1, 0);
    real_t lambda = 0.0;
    const real_t initial_error = Math::abs((b - a).dot(c - a));
    CHECK(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 1.0, 1.0, 0.0, 1.0, 0.1, lambda));
    CHECK(a == Vector3());
    CHECK(Math::abs((b - a).dot(c - a)) < initial_error);
    CHECK(lambda < 0.0);
}

TEST_CASE("[PhysicsXPBD] Pinned triangle vertices stay fixed") {
    Vector3 a, b(1, 0, 0), c(real_t(0.5), 1, 0);
    real_t lambda = 0.0;
    CHECK(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, lambda));
    CHECK(a == Vector3());
    CHECK(b == Vector3(1, 0, 0));
    CHECK(c.is_equal_approx(Vector3(0, 1, 0)));
    CHECK(Math::is_equal_approx(lambda, real_t(-0.5)));
}

TEST_CASE("[PhysicsXPBD] Compliant triangle shear retains one-step lambda") {
    Vector3 a, b(1, 0, 0), c(real_t(0.5), 1, 0);
    real_t lambda = 0.0;
    for (int i = 0; i < 16; ++i) {
        CHECK(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, lambda));
    }
    CHECK(c.is_equal_approx(Vector3(real_t(0.25), 1, 0)));
    CHECK(Math::is_equal_approx(lambda, real_t(-0.25)));
}

TEST_CASE("[PhysicsXPBD] Shear projection is translation invariant") {
    Vector3 a(100, -50, 7), b(101, -50, 7), c(real_t(100.5), -49, 7);
    real_t lambda = 0.0;
    CHECK(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, lambda));
    CHECK(a == Vector3(100, -50, 7));
    CHECK(b == Vector3(101, -50, 7));
    CHECK(c.is_equal_approx(Vector3(100, -49, 7)));
}

TEST_CASE("[PhysicsXPBD] Rest triangle keeps its metric") {
    Vector3 a, b(1, 0, 0), c(0, 1, 0);
    real_t lambda = 0.0;
    CHECK(physics_xpbd_solve_triangle_shear(a, b, c, 1.0, 1.0, 1.0, 0.0, 1.0, 0.01, lambda));
    CHECK(a == Vector3());
    CHECK(b == Vector3(1, 0, 0));
    CHECK(c == Vector3(0, 1, 0));
    CHECK(lambda == 0.0);
}

TEST_CASE("[PhysicsXPBD] Invalid shear input is atomic") {
    Vector3 a, b(1, 0, 0), c(real_t(0.5), 1, 0);
    real_t lambda = 0.0;
    CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, lambda));
    CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, lambda));
    CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, lambda));
    CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0, 0.0, 1.0, -1.0, lambda));
    CHECK_FALSE(physics_xpbd_solve_triangle_shear(a, b, c, 0.0, 0.0, 1.0, 0.0, 1.0,
            std::numeric_limits<real_t>::infinity(), lambda));
    CHECK(a == Vector3());
    CHECK(b == Vector3(1, 0, 0));
    CHECK(c == Vector3(real_t(0.5), 1, 0));
    CHECK(lambda == 0.0);
}

} // namespace TestPhysicsXPBDShear
