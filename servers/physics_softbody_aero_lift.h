/**************************************************************************/
/*  physics_softbody_aero_lift.h                                           */
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

#pragma once

#include "core/math/vector3.h"

// Two-sided aerodynamic lift for a triangle moving through still air.
// Lift is tangent to the plane perpendicular to mean surface velocity:
// L = -0.5 * Cl * area * |v|^2 * cos(theta) *
//     (n - normalize(v) * cos(theta))
// where theta is the angle between the face normal and its velocity.
// This vanishes for face-on and edge-on incidence; it remains orthogonal
// to the average velocity, unlike a dissipative drag force. Reversing
// triangle winding leaves the force unchanged. Cl folds in air density.
// On invalid or degenerate input, the output is never modified.
_FORCE_INLINE_ bool physics_softbody_compute_face_lift(
        const Vector3 &p_face_normal, const Vector3 &p_face_velocity,
        real_t p_area, real_t p_lift_coefficient, Vector3 &r_force) {
    if (!p_face_normal.is_finite() || !p_face_velocity.is_finite() ||
            !Math::is_finite(p_area) || !Math::is_finite(p_lift_coefficient) ||
            !(p_area > 0.0) || !(p_lift_coefficient > 0.0)) {
        return false;
    }

    const double nx = double(p_face_normal.x);
    const double ny = double(p_face_normal.y);
    const double nz = double(p_face_normal.z);
    const double vx = double(p_face_velocity.x);
    const double vy = double(p_face_velocity.y);
    const double vz = double(p_face_velocity.z);
    const double normal_sq = nx * nx + ny * ny + nz * nz;
    const double speed_sq = vx * vx + vy * vy + vz * vz;
    if (!(normal_sq > 0.0) || !(speed_sq > 0.0) ||
            !Math::is_finite(normal_sq) || !Math::is_finite(speed_sq)) {
        return false;
    }

    const double inv_normal = 1.0 / Math::sqrt(normal_sq);
    const double inv_speed = 1.0 / Math::sqrt(speed_sq);
    const double ux = vx * inv_speed;
    const double uy = vy * inv_speed;
    const double uz = vz * inv_speed;
    const double cos_theta = CLAMP(
            (nx * ux + ny * uy + nz * uz) * inv_normal, -1.0, 1.0);
    const double lx = nx * inv_normal - ux * cos_theta;
    const double ly = ny * inv_normal - uy * cos_theta;
    const double lz = nz * inv_normal - uz * cos_theta;
    const double projected_sq = lx * lx + ly * ly + lz * lz;
    if (!(Math::abs(cos_theta) > 1e-12) ||
            !(projected_sq > 1e-24) || !Math::is_finite(projected_sq)) {
        return false;
    }

    // Compute in double to avoid float overflow in speed squared.
    const double scale = -0.5 * double(p_lift_coefficient) *
            double(p_area) * speed_sq * cos_theta;
    if (!Math::is_finite(scale)) {
        return false;
    }
    const Vector3 candidate(
            real_t(scale * lx), real_t(scale * ly), real_t(scale * lz));
    if (!candidate.is_finite()) {
        return false;
    }
    r_force = candidate;
    return true;
}
