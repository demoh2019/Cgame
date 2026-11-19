/**************************************************************************/
/*  test_physics_softbody_hydrostatic.cpp                                 */
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

#include "servers/physics_softbody_hydrostatic.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_hydrostatic)

namespace TestPhysicsSoftBodyHydrostatic {

static Vector3 sum_three(const Vector3 (&p_force)[3]) {
    return p_force[0] + p_force[1] + p_force[2];
}

TEST_CASE("[PhysicsSoftBody] Fully submerged horizontal face integrates exact pressure") {
    Vector3 nodal[3] = { Vector3(9, 9, 9), Vector3(9, 9, 9), Vector3(9, 9, 9) };
    CHECK(physics_softbody_hydrostatic_face_forces(
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
            2.0, 6.0, 1, nodal));
    // Triangle area 1/2, depth 2, pressure gradient 6 -> total +6Y.
    CHECK(nodal[0].y == doctest::Approx(2.0));
    CHECK(nodal[1].y == doctest::Approx(2.0));
    CHECK(nodal[2].y == doctest::Approx(2.0));
    CHECK(sum_three(nodal).x == doctest::Approx(0.0));
    CHECK(sum_three(nodal).y == doctest::Approx(6.0));
    CHECK(sum_three(nodal).z == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsSoftBody] Completely dry and zero-density faces receive no force") {
    Vector3 dry[3] = { Vector3(5, 5, 5), Vector3(5, 5, 5), Vector3(5, 5, 5) };
    CHECK(physics_softbody_hydrostatic_face_forces(
            Vector3(0, 1, 0), Vector3(1, 2, 0), Vector3(0, 2, 1),
            0.0, 9810.0, 1, dry));
    CHECK(dry[0] == Vector3());
    CHECK(dry[1] == Vector3());
    CHECK(dry[2] == Vector3());
    CHECK(physics_softbody_hydrostatic_face_forces(
            Vector3(), Vector3(1, 0, 0), Vector3(0, 0, 1),
            3.0, 0.0, 1, dry));
    CHECK(sum_three(dry) == Vector3());
}

TEST_CASE("[PhysicsSoftBody] Partially submerged triangle clips exactly at waterline") {
    const Vector3 a(0, -1, 0), b(1, 1, 0), c(0, 1, 1);
    Vector3 f[3];
    CHECK(physics_softbody_hydrostatic_face_forces(a, b, c, 0.0, 12.0, 1, f));
    // Clipped triangle has 1/4 the area; its average depth is 1/3.
    // Force = -cross(b-a,c-a)/2 * 12 * (1/4) * (1/3).
    const Vector3 expected = -((b - a).cross(c - a)) * real_t(0.5);
    const Vector3 sum = sum_three(f);
    CHECK(sum.x == doctest::Approx(expected.x).epsilon(1e-5));
    CHECK(sum.y == doctest::Approx(expected.y).epsilon(1e-5));
    CHECK(sum.z == doctest::Approx(expected.z).epsilon(1e-5));
    // Consistent shape-function distribution: A gets 75% of the force,
    // and B/C get 12.5% each, rather than equal shares.
    CHECK(f[0].length() == doctest::Approx(expected.length() * 0.75).epsilon(1e-5));
    CHECK(f[1].length() == doctest::Approx(expected.length() * 0.125).epsilon(1e-5));
    CHECK(f[2].length() == doctest::Approx(expected.length() * 0.125).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftBody] Sealed submerged tetrahedron obeys Archimedes principle") {
    const Vector3 a, b(1, 0, 0), c(0, 1, 0), d(0, 0, 1);
    const Vector3 triangles[4][3] = {
        { a, c, b }, // outward -Z
        { a, b, d }, // outward -Y
        { a, d, c }, // outward -X
        { b, c, d }, // outward +X,+Y,+Z
    };
    Vector3 sum;
    for (int i = 0; i < 4; ++i) {
        Vector3 f[3];
        CHECK(physics_softbody_hydrostatic_face_forces(
                triangles[i][0], triangles[i][1], triangles[i][2],
                2.0, 6.0, 1, f));
        sum += sum_three(f);
    }
    // 6 * (tetra volume=1/6) gives +1Y regardless of water depth.
    CHECK(sum.x == doctest::Approx(0.0).epsilon(1e-5));
    CHECK(sum.y == doctest::Approx(1.0).epsilon(1e-5));
    CHECK(sum.z == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftBody] Reversed mesh winding corrected using signed rest volume") {
    Vector3 front[3], back[3];
    const Vector3 a(0, -1, 0), b(1, 1, 0), c(0, 1, 1);
    CHECK(physics_softbody_hydrostatic_face_forces(a, b, c, 0.0, 12.0, 1, front));
    CHECK(physics_softbody_hydrostatic_face_forces(a, c, b, 0.0, 12.0, -1, back));
    const Vector3 f = sum_three(front), g = sum_three(back);
    CHECK(f.distance_to(g) < real_t(1e-5));
}

TEST_CASE("[PhysicsSoftBody] Water plane height monotonically increases hydrostatic load") {
    Vector3 shallow[3], deep[3];
    const Vector3 a, b(1, 0, 0), c(0, 0, 1);
    CHECK(physics_softbody_hydrostatic_face_forces(a, b, c, 1.0, 10.0, 1, shallow));
    CHECK(physics_softbody_hydrostatic_face_forces(a, b, c, 2.0, 10.0, 1, deep));
    CHECK(sum_three(deep).y == doctest::Approx(2 * sum_three(shallow).y));
}

TEST_CASE("[PhysicsSoftBody] Invalid and overflowing inputs do not mutate nodal forces") {
    const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
    Vector3 f[3] = { Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9) };
    CHECK_FALSE(physics_softbody_hydrostatic_face_forces(
            Vector3(nan, 0, 0), Vector3(), Vector3(),
            1.0, 1000.0, 1, f));
    CHECK_FALSE(physics_softbody_hydrostatic_face_forces(
            Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
            1.0, -1.0, 1, f));
    CHECK_FALSE(physics_softbody_hydrostatic_face_forces(
            Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
            1.0, 1000.0, 0, f));
    CHECK_FALSE(physics_softbody_hydrostatic_face_forces(
            Vector3(0, -real_t(1e30), 0), Vector3(real_t(1e30), -real_t(1e30), 0),
            Vector3(0, -real_t(1e30), real_t(1e30)),
            0.0, 1e30, 1, f));
    CHECK(f[0] == Vector3(1, 2, 3));
    CHECK(f[1] == Vector3(4, 5, 6));
    CHECK(f[2] == Vector3(7, 8, 9));
}

} // namespace TestPhysicsSoftBodyHydrostatic
