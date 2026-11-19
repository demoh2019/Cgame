/**************************************************************************/
/*  test_physics_softbody_hydrodynamic_drag.cpp                           */
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

#include "servers/physics_softbody_hydrodynamic_drag.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_hydrodynamic_drag)

namespace TestPhysicsSoftBodyHydrodynamicDrag {

static double relative_energy(const Vector3 (&p_velocity)[3],
        const real_t (&p_inverse_mass)[3], const Vector3 &p_flow) {
    double energy = 0.0;
    for (int i = 0; i < 3; ++i) {
        if (!(p_inverse_mass[i] > real_t(0.0))) {
            continue;
        }
        const Vector3 relative = p_velocity[i] - p_flow;
        energy += double(relative.length_squared()) / double(p_inverse_mass[i]) * 0.5;
    }
    return energy;
}

static bool drag(const Vector3 (&p_positions)[3],
        const Vector3 (&p_velocities)[3],
        const real_t (&p_inv_mass)[3], const Vector3 &p_flow,
        double p_surface, double p_density, double p_cd, double p_tangent,
        double p_delta, Vector3 (&r_velocity_delta)[3]) {
    return physics_softbody_hydrodynamic_drag_face(
            p_positions, p_velocities, p_inv_mass, p_flow,
            p_surface, p_density, p_cd, p_tangent, p_delta,
            r_velocity_delta);
}

TEST_CASE("[PhysicsSoftBody] Quadratic submerged drag slows normal motion without reversal") {
    const Vector3 p[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
    const Vector3 v[3] = { Vector3(0, 5, 0), Vector3(0, 5, 0), Vector3(0, 5, 0) };
    const real_t inv_mass[3] = { 1, 1, 1 };
    Vector3 delta[3];
    CHECK(drag(p, v, inv_mass, Vector3(), 0, 2, 1, 0, 0.1, delta));
    for (int i = 0; i < 3; ++i) {
        CHECK(delta[i].y < 0);
        CHECK(v[i].y + delta[i].y >= 0);
        CHECK(delta[i].x == doctest::Approx(0));
        CHECK(delta[i].z == doctest::Approx(0));
    }
    const Vector3 next[3] = { v[0] + delta[0], v[1] + delta[1], v[2] + delta[2] };
    CHECK(relative_energy(next, inv_mass, Vector3()) < relative_energy(v, inv_mass, Vector3()));
}

TEST_CASE("[PhysicsSoftBody] Uniform moving current accelerates stationary cloth toward flow") {
    const Vector3 p[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
    const Vector3 v[3] = { Vector3(), Vector3(), Vector3() };
    const real_t inv_mass[3] = { 1, 1, 1 };
    const Vector3 flow(0, 4, 0);
    Vector3 delta[3];
    CHECK(drag(p, v, inv_mass, flow, 0, 100, 1, 0, 1.0, delta));
    for (int i = 0; i < 3; ++i) {
        CHECK(delta[i].y > 0);
        CHECK(delta[i].y <= flow.y);
        CHECK(delta[i].x == doctest::Approx(0));
    }
    const Vector3 next[3] = { v[0] + delta[0], v[1] + delta[1], v[2] + delta[2] };
    CHECK(relative_energy(next, inv_mass, flow) <= relative_energy(v, inv_mass, flow));
}

TEST_CASE("[PhysicsSoftBody] Tangential drag is independent of normal resistance") {
    const Vector3 p[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
    const Vector3 v[3] = { Vector3(4, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 0) };
    const real_t inv_mass[3] = { 1, 1, 1 };
    Vector3 normal_only[3], shear_drag[3];
    CHECK(drag(p, v, inv_mass, Vector3(), 0, 5, 1, 0, 0.1, normal_only));
    CHECK(drag(p, v, inv_mass, Vector3(), 0, 5, 1, 0.5, 0.1, shear_drag));
    for (int i = 0; i < 3; ++i) {
        CHECK(normal_only[i] == Vector3());
        CHECK(shear_drag[i].x < 0);
        CHECK(v[i].x + shear_drag[i].x >= 0);
    }
}

TEST_CASE("[PhysicsSoftBody] Half-submerged triangle receives less drag than full immersion") {
    const Vector3 p[3] = { Vector3(0, -1, 0), Vector3(2, 1, 0), Vector3(0, 1, 2) };
    const Vector3 v[3] = { Vector3(1, -1, 1), Vector3(1, -1, 1), Vector3(1, -1, 1) };
    const real_t inv_mass[3] = { 1, 1, 1 };
    Vector3 half[3], full[3];
    CHECK(drag(p, v, inv_mass, Vector3(), 0, 2, 1, 0, 0.001, half));
    CHECK(drag(p, v, inv_mass, Vector3(), 3, 2, 1, 0, 0.001, full));
    const Vector3 half_sum = half[0] + half[1] + half[2];
    const Vector3 full_sum = full[0] + full[1] + full[2];
    CHECK(half_sum.length() > 0);
    CHECK(full_sum.length() > half_sum.length());
    CHECK(half_sum.length() / full_sum.length() == doctest::Approx(0.25).epsilon(0.01));
}

TEST_CASE("[PhysicsSoftBody] Pinned vertices stay fixed and no partial update occurs") {
    const Vector3 p[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
    const Vector3 v[3] = { Vector3(0, 9, 0), Vector3(0, 9, 0), Vector3(0, 9, 0) };
    const real_t inv_mass[3] = { 0, 1, 1 };
    Vector3 delta[3];
    CHECK(drag(p, v, inv_mass, Vector3(), 0, 1000, 100, 0.5, 5.0, delta));
    CHECK(delta[0] == Vector3());
    CHECK(delta[1].y < 0);
    CHECK(delta[2].y < 0);
    const Vector3 next[3] = { v[0] + delta[0], v[1] + delta[1], v[2] + delta[2] };
    CHECK(relative_energy(next, inv_mass, Vector3()) <= relative_energy(v, inv_mass, Vector3()));
}

TEST_CASE("[PhysicsSoftBody] Dry faces, disabled coefficients, and pins yield zero drag") {
    const Vector3 p[3] = { Vector3(0, 2, 0), Vector3(1, 2, 0), Vector3(0, 2, 1) };
    const Vector3 v[3] = { Vector3(0, 5, 0), Vector3(0, 5, 0), Vector3(0, 5, 0) };
    const real_t inv_mass[3] = { 1, 1, 1 };
    Vector3 delta[3];
    CHECK(drag(p, v, inv_mass, Vector3(), 0, 100, 2, 1, 0.1, delta));
    CHECK(delta[0] == Vector3());
    CHECK(delta[1] == Vector3());
    CHECK(delta[2] == Vector3());
    CHECK(drag(p, v, inv_mass, Vector3(), 4, 0, 2, 1, 0.1, delta));
    CHECK(delta[0] == Vector3());
    CHECK(drag(p, v, inv_mass, Vector3(), 4, 100, 0, 1, 0.1, delta));
    CHECK(delta[1] == Vector3());
    const real_t pins[3] = { 0, 0, 0 };
    CHECK(drag(p, v, pins, Vector3(), 4, 100, 2, 1, 0.1, delta));
    CHECK(delta[2] == Vector3());
}

TEST_CASE("[PhysicsSoftBody] Extreme drag coefficient cannot reverse relative velocity") {
    const Vector3 p[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
    const Vector3 v[3] = { Vector3(0, 7, 0), Vector3(0, 7, 0), Vector3(0, 7, 0) };
    const real_t inv_mass[3] = { 1, 1, 1 };
    Vector3 delta[3];
    CHECK(drag(p, v, inv_mass, Vector3(), 0, 1e8, 1e6, 0, 1e5, delta));
    for (int i = 0; i < 3; ++i) {
        CHECK(delta[i].is_finite());
        CHECK(v[i].y + delta[i].y >= real_t(-1e-5));
    }
    const Vector3 next[3] = { v[0] + delta[0], v[1] + delta[1], v[2] + delta[2] };
    CHECK(relative_energy(next, inv_mass, Vector3()) <= relative_energy(v, inv_mass, Vector3()));
}

TEST_CASE("[PhysicsSoftBody] Non-finite inputs fail without modifying output") {
    const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
    const Vector3 p[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
    const Vector3 v[3] = { Vector3(0, 7, 0), Vector3(0, 7, 0), Vector3(0, 7, 0) };
    const real_t inv_mass[3] = { 1, 1, 1 };
    Vector3 delta[3] = { Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9) };
    CHECK_FALSE(drag(p, v, inv_mass, Vector3(nan, 0, 0), 0, 5, 1, 0, 0.1, delta));
    CHECK_FALSE(drag(p, v, inv_mass, Vector3(), 0, 5, -1, 0, 0.1, delta));
    CHECK_FALSE(drag(p, v, inv_mass, Vector3(), 0, 5, 1, -1, 0.1, delta));
    CHECK_FALSE(drag(p, v, inv_mass, Vector3(), 0, 5, 1, 0, nan, delta));
    CHECK(delta[0] == Vector3(1, 2, 3));
    CHECK(delta[1] == Vector3(4, 5, 6));
    CHECK(delta[2] == Vector3(7, 8, 9));
}

TEST_CASE("[PhysicsSoftBody] Relative kinetic energy cannot grow across many face updates") {
    const Vector3 p[3] = { Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(0, -1, 1) };
    Vector3 v[3] = { Vector3(9, 7, -4), Vector3(1, 2, 4), Vector3(-7, 5, -1) };
    const real_t inv_mass[3] = { 0.5, 2.0, 1.0 };
    const Vector3 current(3, 1, -2);
    double previous_energy = relative_energy(v, inv_mass, current);
    for (int iteration = 0; iteration < 100; ++iteration) {
        Vector3 dv[3];
        CHECK(drag(p, v, inv_mass, current, 0, 1200, 4, 0.35, 0.02, dv));
        for (int i = 0; i < 3; ++i) {
            v[i] += dv[i];
        }
        const double energy = relative_energy(v, inv_mass, current);
        CHECK(energy <= previous_energy + 1e-4);
        previous_energy = energy;
    }
}

} // namespace TestPhysicsSoftBodyHydrodynamicDrag
