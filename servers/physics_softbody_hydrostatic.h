/**************************************************************************/
/*  physics_softbody_hydrostatic.h                                        */
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

#pragma once

#include "servers/physics_softbody_fluid_clipping.h"

#include <limits>

// Hydrostatic pressure loading for ONE triangle of a closed, consistently
// oriented SoftBody3D shell, clipped to the water half-space y <= surface_y.
// Internal pressure is zero at the free surface, increasing as rho*g*depth.
//
// The resultant is integrated exactly for a LINEAR depth field on each
// submerged subtriangle. Forces are distributed to original triangle vertices
// using barycentric shape functions (consistent P1 triangle force loading).
// Partial immersion is clipped analytically; no force goes to an arbitrary
// "body center". This preserves the torque/force distribution of the surface
// integral to within float rounding.
//
// With a closed outward-oriented manifold, summing all faces gives
// Archimedes buoyancy for a fully submerged polyhedron. A negative signed
// rest volume requires p_orientation=-1 to correct inward mesh winding.
//
// Not CFD, wave dynamics, or deformable-fluid two-way coupling. Input gravity
// must act in world -Y; p_pressure_gradient is rho * |gravity.y| [N/m^3].
// Uses fixed stack storage, double intermediate calculations, and a
// two-phase commit so invalid/overflowing faces never corrupt node forces.
_FORCE_INLINE_ static bool physics_softbody_hydrostatic_face_forces(
        const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
        double p_surface_y, double p_pressure_gradient, int p_orientation,
        Vector3 (&r_force)[3]) {
    if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() ||
            !Math::is_finite(p_surface_y) || !Math::is_finite(p_pressure_gradient) ||
            p_pressure_gradient < 0.0 || (p_orientation != 1 && p_orientation != -1)) {
        return false;
    }

    PhysicsSoftBodyFluidVertex clipped[4];
    int clipped_count = 0;
    if (!physics_softbody_clip_fluid_triangle(
            p_a, p_b, p_c, p_surface_y, clipped, clipped_count)) {
        return false;
    }

    double accumulated[3][3] = {};
    for (int triangle = 1; triangle + 1 < clipped_count; ++triangle) {
        const PhysicsSoftBodyFluidVertex &a = clipped[0];
        const PhysicsSoftBodyFluidVertex &b = clipped[triangle];
        const PhysicsSoftBodyFluidVertex &c = clipped[triangle + 1];

        const double ax = b.x - a.x, ay = b.y - a.y, az = b.z - a.z;
        const double bx = c.x - a.x, by = c.y - a.y, bz = c.z - a.z;
        const double normal_area[3] = {
            ay * bz - az * by,
            az * bx - ax * bz,
            ax * by - ay * bx,
        }; // 2 * oriented area vector
        const double depth[3] = {
            MAX(0.0, p_surface_y - a.y),
            MAX(0.0, p_surface_y - b.y),
            MAX(0.0, p_surface_y - c.y),
        };
        const PhysicsSoftBodyFluidVertex *vertices[3] = { &a, &b, &c };
        const double depth_sum = depth[0] + depth[1] + depth[2];
        if (!Math::is_finite(depth_sum)) {
            return false;
        }

        // Integral over triangle of N_original * depth:
        // A/12 * sum_i( bary_i * (depth_sum + depth_i) ).
        // The area vector is cross/2, hence cross/24 below.
        for (int node = 0; node < 3; ++node) {
            double depth_weight = 0.0;
            for (int j = 0; j < 3; ++j) {
                depth_weight += vertices[j]->bary[node] * (depth_sum + depth[j]);
            }
            const double scale = -double(p_orientation) * p_pressure_gradient * depth_weight / 24.0;
            for (int component = 0; component < 3; ++component) {
                accumulated[node][component] += normal_area[component] * scale;
            }
        }
    }

    // Nothing is written until the entire clipped face was validated.
    Vector3 candidate[3];
    const double max_coord = double(std::numeric_limits<real_t>::max());
    for (int node = 0; node < 3; ++node) {
        for (int component = 0; component < 3; ++component) {
            const double value = accumulated[node][component];
            if (!Math::is_finite(value) || Math::abs(value) > max_coord) {
                return false;
            }
        }
        candidate[node] = Vector3(real_t(accumulated[node][0]),
                real_t(accumulated[node][1]),
                real_t(accumulated[node][2]));
        if (!candidate[node].is_finite()) {
            return false;
        }
    }
    for (int node = 0; node < 3; ++node) {
        r_force[node] = candidate[node];
    }
    return true;
}
