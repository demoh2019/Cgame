/**************************************************************************/
/*  test_physics_softbody_aero_lift.cpp                                    */
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

#include "servers/physics_softbody_aero_lift.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_aero_lift)

namespace TestPhysicsSoftBodyAeroLift {

TEST_CASE("[PhysicsSoftBody] Aerodynamic lift is orthogonal to face velocity") {
    const Vector3 velocity(2, 0, 1);
    Vector3 lift;
    CHECK(physics_softbody_compute_face_lift(Vector3(0, 0, 1), velocity, 2.0, 1.0, lift));
    CHECK(lift.length_squared() > 0.0);
    CHECK(Math::abs(lift.dot(velocity)) < real_t(1e-5));
}

TEST_CASE("[PhysicsSoftBody] Aerodynamic lift is two-sided") {
    const Vector3 velocity(1, 0, 1);
    Vector3 front, back;
    CHECK(physics_softbody_compute_face_lift(Vector3(0, 0, 1), velocity, 1.0, 1.0, front));
    CHECK(physics_softbody_compute_face_lift(Vector3(0, 0, -1), velocity, 1.0, 1.0, back));
    CHECK(front.is_equal_approx(back));
}

TEST_CASE("[PhysicsSoftBody] Lift vanishes for edge-on and face-on motion") {
    Vector3 force(3, 4, 5);
    CHECK_FALSE(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(1, 0, 0), 1.0, 1.0, force));
    CHECK_FALSE(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(0, 0, 2), 1.0, 1.0, force));
    CHECK(force == Vector3(3, 4, 5));
}

TEST_CASE("[PhysicsSoftBody] Lift scales quadratically with velocity") {
    Vector3 slow, fast;
    CHECK(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(1, 0, 1), 1.0, 0.5, slow));
    CHECK(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(2, 0, 2), 1.0, 0.5, fast));
    CHECK(fast.is_equal_approx(slow * real_t(4.0)));
}

TEST_CASE("[PhysicsSoftBody] Lift is invariant to normal length") {
    Vector3 a, b;
    CHECK(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(1, 0, 1), 1.0, 0.5, a));
    CHECK(physics_softbody_compute_face_lift(
            Vector3(0, 0, 7), Vector3(1, 0, 1), 1.0, 0.5, b));
    CHECK(a.is_equal_approx(b));
}

TEST_CASE("[PhysicsSoftBody] Invalid aerodynamic inputs never modify outputs") {
    Vector3 output(3, 4, 5);
    CHECK_FALSE(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(), 1.0, 1.0, output));
    CHECK_FALSE(physics_softbody_compute_face_lift(
            Vector3(), Vector3(1, 0, 1), 1.0, 1.0, output));
    CHECK_FALSE(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(1, 0, 1), 0.0, 1.0, output));
    CHECK_FALSE(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(1, 0, 1), 1.0, -1.0, output));
    CHECK_FALSE(physics_softbody_compute_face_lift(
            Vector3(0, 0, 1), Vector3(1, 0, 1),
            std::numeric_limits<real_t>::infinity(), 1.0, output));
    CHECK(output == Vector3(3, 4, 5));
}

} // namespace TestPhysicsSoftBodyAeroLift
