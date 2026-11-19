/**************************************************************************/
/*  physics_contact_anisotropic_friction.h                               */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER OF CONTRACT, TORT OR OTHERWISE, */
/* ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR   */
/* OTHER DEALINGS IN THE SOFTWARE.                                        */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"
#include "servers/physics_contact_static_friction.h"

// Bullet-inspired directional friction, expressed as an elliptical Coulomb
// cone projected into the contact tangent plane. The user-specified world
// axis determines the stronger, "parallel" direction. The perpendicular
// direction is scaled by p_transverse_ratio in (0,1].
//
// q(J) = sqrt((dot(J,u)/L)^2 + (dot(J,v)/(L*ratio))^2)
//   q <= static_multiplier: retain the candidate (static/sticking).
//   q >  static_multiplier: project radially to q=1 (kinetic/sliding).
//
// This is a *radial* projection in tangent-impulse space, suitable for
// Cgame's sequential impulse solver, not an exact maximum-dissipation
// friction-cone optimization. Works with the existing speed-dependent
// Stribeck cone by passing static_multiplier=1.
//
// Important: only call on TANGENTIAL impulses. Fallback to isotropic
// friction when the preferred axis nearly parallels the normal.
// All ellipse calculations use double to avoid float32 length overflow.
// No allocations, contact state, or changes when ratio == 1.
_FORCE_INLINE_ static Vector3 godot_physics_clamp_anisotropic_friction_3d(
		const Vector3 &p_impulse, const Vector3 &p_normal,
		const Vector3 &p_preferred_axis, real_t p_dynamic_limit,
		real_t p_static_multiplier, real_t p_transverse_ratio) {
	if (!p_impulse.is_finite()) {
		return Vector3();
	}
	if (!Math::is_finite(p_dynamic_limit) || !(p_dynamic_limit > real_t(0.0))) {
		return Vector3();
	}
	if (!Math::is_finite(p_static_multiplier) || p_static_multiplier < real_t(1.0) ||
			!Math::is_finite(p_transverse_ratio) || p_transverse_ratio <= real_t(0.0) ||
			p_transverse_ratio >= real_t(1.0) || !p_normal.is_finite() ||
			!p_preferred_axis.is_finite()) {
		return godot_physics_clamp_static_friction_3d(p_impulse, p_dynamic_limit, p_static_multiplier);
	}

	const double nx0 = double(p_normal.x);
	const double ny0 = double(p_normal.y);
	const double nz0 = double(p_normal.z);
	const double normal_sq = nx0 * nx0 + ny0 * ny0 + nz0 * nz0;
	if (!(normal_sq > 0.0) || !Math::is_finite(normal_sq)) {
		return godot_physics_clamp_static_friction_3d(p_impulse, p_dynamic_limit, p_static_multiplier);
	}
	const double inv_normal = 1.0 / Math::sqrt(normal_sq);
	const double nx = nx0 * inv_normal;
	const double ny = ny0 * inv_normal;
	const double nz = nz0 * inv_normal;

	const double dot_axis = nx * double(p_preferred_axis.x) +
			ny * double(p_preferred_axis.y) + nz * double(p_preferred_axis.z);
	const double ax = double(p_preferred_axis.x) - nx * dot_axis;
	const double ay = double(p_preferred_axis.y) - ny * dot_axis;
	const double az = double(p_preferred_axis.z) - nz * dot_axis;
	const double axis_sq = ax * ax + ay * ay + az * az;
	const double preferred_sq = double(p_preferred_axis.x) * double(p_preferred_axis.x) +
			double(p_preferred_axis.y) * double(p_preferred_axis.y) +
			double(p_preferred_axis.z) * double(p_preferred_axis.z);
	if (!(axis_sq > preferred_sq * 1e-12) ||
			!Math::is_finite(axis_sq) || !Math::is_finite(preferred_sq)) {
		// Undefined preferred direction in this tangent plane.
		return godot_physics_clamp_static_friction_3d(p_impulse, p_dynamic_limit, p_static_multiplier);
	}

	const double inv_axis = 1.0 / Math::sqrt(axis_sq);
	const double ux = ax * inv_axis;
	const double uy = ay * inv_axis;
	const double uz = az * inv_axis;
	const double vx = ny * uz - nz * uy;
	const double vy = nz * ux - nx * uz;
	const double vz = nx * uy - ny * ux;

	const double iu = double(p_impulse.x) * ux + double(p_impulse.y) * uy + double(p_impulse.z) * uz;
	const double iv = double(p_impulse.x) * vx + double(p_impulse.y) * vy + double(p_impulse.z) * vz;
	const double lu = double(p_dynamic_limit);
	const double lv = lu * double(p_transverse_ratio);
	const double su = iu / lu;
	const double sv = iv / lv;
	const double q_sq = su * su + sv * sv;
	if (!Math::is_finite(q_sq)) {
		return Vector3();
	}
	const double static_multiplier = double(p_static_multiplier);
	if (q_sq <= static_multiplier * static_multiplier) {
		return p_impulse; // Static friction can hold the candidate.
	}
	const double q = Math::sqrt(q_sq);
	if (!(q > 0.0)) {
		return Vector3();
	}
	const double scale = 1.0 / q; // Project to the kinetic ellipse.
	const Vector3 output(real_t((iu * ux + iv * vx) * scale),
			real_t((iu * uy + iv * vy) * scale),
			real_t((iu * uz + iv * vz) * scale));
	return output.is_finite() ? output : Vector3();
}
