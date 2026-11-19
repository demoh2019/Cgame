/**************************************************************************/
/*  physics_rigid_box_aero_panels_3d.h                                    */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/basis.h"
#include "core/math/vector3.h"

// Six-panel, oriented affine box aerodynamic model. For each face center:
//     u = v_COM + omega x (face - COM) - wind
//     u_n = dot(u, outward_normal), u_t = u - u_n*normal
//     F_pressure = -0.5*rho*C_pressure*A*max(u_n,0)^2*normal
//     F_skin = -0.5*rho*C_skin*A*|u_t|*u_t
//
// Only windward (positive outward-speed) faces receive pressure; both
// orientations receive shear drag. Each force is dissipative relative to
// the flow at that face: F dot u <= 0. This is a six-center, quadratic
// panel approximation, NOT CFD, a wing-lift model or vortex shedding.
//
// Sequential impulses at the six face centers update temporary COM
// velocities using the world-space inverse inertia. To avoid explicit
// Euler reversal, each panel's impulse magnitude J is limited by:
//     J <= -dot(u, F/|F|) / (inv_mass +
//           (r x dir) dot (I_world^-1 * (r x dir))).
// This caps the velocity change along the resisting direction at that
// face. It is a *local* dissipative stability guard, not a globally
// implicit multiple-panel solve. Processing order is deterministic:
// faces +X,-X,+Y,-Y,+Z,-Z.
//
// Half axes MUST be world-space vectors transformed from box local
// half-extents by its affine shape-to-world basis. No uniform-scale
// assumption: cross products produce true face normals and areas,
// including reflections and shear. Singular boxes are rejected.
//
// All outputs are transactional: either all six panels are evaluated
// successfully and both velocities are updated, or neither changes.
// Disabled rates and zero dt perform no work or allocation. Call only
// on dynamic rigid bodies with finite positive inverse mass.
_FORCE_INLINE_ static bool godot_physics_rigid_box_aero_step_3d(
		Vector3 &r_linear_velocity, Vector3 &r_angular_velocity,
		const Vector3 &p_box_center, const Vector3 p_world_half_axes[3],
		const Vector3 &p_world_com, const Vector3 &p_wind,
		real_t p_medium_density, real_t p_pressure_coefficient,
		real_t p_skin_coefficient, real_t p_inverse_mass,
		const Basis &p_inverse_inertia_world, real_t p_delta) {
	if (!p_world_half_axes || !r_linear_velocity.is_finite() ||
			!r_angular_velocity.is_finite() || !p_box_center.is_finite() ||
			!p_world_com.is_finite() || !p_wind.is_finite() ||
			!p_inverse_inertia_world.is_finite() ||
			!Math::is_finite(p_medium_density) || p_medium_density < 0.0 ||
			!Math::is_finite(p_pressure_coefficient) || p_pressure_coefficient < 0.0 ||
			!Math::is_finite(p_skin_coefficient) || p_skin_coefficient < 0.0 ||
			!Math::is_finite(p_inverse_mass) || !(p_inverse_mass > 0.0) ||
			!Math::is_finite(p_delta) || p_delta < 0.0) {
		return false;
	}
	if (p_delta == 0.0 || p_medium_density == 0.0 ||
			(p_pressure_coefficient == 0.0 && p_skin_coefficient == 0.0)) {
		return true;
	}
	for (int axis = 0; axis < 3; ++axis) {
		if (!p_world_half_axes[axis].is_finite() ||
				!(p_world_half_axes[axis].length_squared() > 0.0)) {
			return false;
		}
	}
	Vector3 linear = r_linear_velocity;
	Vector3 angular = r_angular_velocity;
	const real_t half_density = real_t(0.5) * p_medium_density;
	for (int axis = 0; axis < 3; ++axis) {
		const Vector3 &ax = p_world_half_axes[axis];
		// Cyclic other axes preserve the geometric face orientation,
		// including a negative-determinant/mirrored shape transform.
		const Vector3 face_area_normal = p_world_half_axes[(axis + 1) % 3].cross(
				p_world_half_axes[(axis + 2) % 3]);
		const real_t normal_length = face_area_normal.length();
		const real_t orient = face_area_normal.dot(ax);
		if (!(normal_length > 0.0) || !Math::is_finite(normal_length) ||
				!(Math::abs(orient) > 0.0) || !Math::is_finite(orient)) {
			return false;
		}
		const real_t world_area = real_t(4.0) * normal_length;
		if (!(world_area > 0.0) || !Math::is_finite(world_area)) {
			return false;
		}
		const Vector3 plus_normal = face_area_normal *
				((orient > 0.0 ? real_t(1.0) : real_t(-1.0)) / normal_length);
		for (int side = 0; side < 2; ++side) {
			const real_t sign = side == 0 ? real_t(1.0) : real_t(-1.0);
			const Vector3 normal = plus_normal * sign;
			const Vector3 center = p_box_center + ax * sign;
			const Vector3 lever = center - p_world_com;
			const Vector3 relative_velocity = linear + angular.cross(lever) - p_wind;
			if (!center.is_finite() || !lever.is_finite() ||
					!relative_velocity.is_finite()) {
				return false;
			}
			const real_t normal_speed = relative_velocity.dot(normal);
			const Vector3 tangential = relative_velocity - normal * normal_speed;
			const real_t tangent_length = tangential.length();
			if (!Math::is_finite(normal_speed) ||
					!tangential.is_finite() || !Math::is_finite(tangent_length)) {
				return false;
			}
			const real_t pressure_speed = MAX(real_t(0.0), normal_speed);
			const Vector3 pressure = normal *
					(-half_density * p_pressure_coefficient * world_area *
							pressure_speed * pressure_speed);
			const Vector3 skin = tangential *
					(-half_density * p_skin_coefficient * world_area * tangent_length);
			const Vector3 force = pressure + skin;
			const real_t force_length = force.length();
			if (!pressure.is_finite() || !skin.is_finite() ||
					!force.is_finite() || !Math::is_finite(force_length)) {
				return false;
			}
			if (!(force_length > 0.0)) {
				continue;
			}
			const Vector3 direction = force / force_length;
			const Vector3 arm = lever.cross(direction);
			const Vector3 inverse_rotational_arm = p_inverse_inertia_world.xform(arm);
			const real_t k = p_inverse_mass + arm.dot(inverse_rotational_arm);
			const real_t opposing_speed = -relative_velocity.dot(direction);
			if (!direction.is_finite() || !arm.is_finite() ||
					!inverse_rotational_arm.is_finite() ||
					!Math::is_finite(k) || !(k > 0.0) ||
					!Math::is_finite(opposing_speed)) {
				return false;
			}
			// The force must oppose local relative motion. For extremely
			// small rounded values a zero impulse is safer than reversal.
			if (!(opposing_speed > 0.0)) {
				continue;
			}
			const double proposed_impulse = double(force_length) * double(p_delta);
			const double max_impulse = double(opposing_speed) / double(k);
			if (!Math::is_finite(proposed_impulse) ||
					!Math::is_finite(max_impulse)) {
				return false;
			}
			const double magnitude = MIN(proposed_impulse, max_impulse);
			const Vector3 impulse = direction * real_t(magnitude);
			const Vector3 next_linear = linear + impulse * p_inverse_mass;
			const Vector3 next_angular = angular + p_inverse_inertia_world.xform(
					lever.cross(impulse));
			if (!impulse.is_finite() || !next_linear.is_finite() ||
					!next_angular.is_finite()) {
				return false;
			}
			linear = next_linear;
			angular = next_angular;
		}
	}
	r_linear_velocity = linear;
	r_angular_velocity = angular;
	return true;
}
