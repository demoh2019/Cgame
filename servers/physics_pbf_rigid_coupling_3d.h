/**************************************************************************/
/*  physics_pbf_rigid_coupling_3d.h                                       */
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

#include "core/math/basis.h"
#include "core/math/vector3.h"

// Pairwise, non-penetrating particle/rigid impact at one detected boundary
// contact. An effective mass includes the body's world-space inverse inertia
// and the particle's translational inverse mass:
//
// J = -(1 + e) * [(v_particle - v_body_at_contact) . n]
//     / [1/m_particle + 1/m_body +
//        n . ((I_world^-1 * (r x n)) x r)]
//
// The particle receives +J*n and the rigid body -J*n, with the rigid
// impulse applied at contact offset r. Hence their collision impulses
// preserve total linear momentum and, about the same origin, angular
// momentum; a positive restitution <=1 cannot inject normal kinetic energy.
// Bounds keep badly conditioned/degenerate impacts from exploding.
//
// Optional to the PBF solver: does NOT represent boundary particles,
// continuum pressure, drag, submerged-volume buoyancy or two-way
// incompressible Navier-Stokes. Inverse inertia is provided by the actual
// backend's DirectBodyState, not reconstructed from a collision shape.
struct PhysicsPBFRigidContactResult3D {
	Vector3 particle_velocity;
	Vector3 body_impulse;
	real_t impulse_magnitude = 0.0;
};

_FORCE_INLINE_ bool physics_pbf_rigid_contact_solve_3d(
		const Vector3 &p_particle_velocity, real_t p_particle_mass,
		const Vector3 &p_body_contact_velocity, real_t p_body_inverse_mass,
		const Basis &p_world_inverse_inertia, const Vector3 &p_lever,
		const Vector3 &p_normal, real_t p_restitution,
		real_t p_max_impulse, PhysicsPBFRigidContactResult3D &r_result) {
	r_result = PhysicsPBFRigidContactResult3D();
	if (!p_particle_velocity.is_finite() || !p_body_contact_velocity.is_finite() ||
			!p_lever.is_finite() || !p_normal.is_finite() ||
			!p_world_inverse_inertia.is_finite() ||
			!(p_particle_mass > real_t(0.0)) || !Math::is_finite(p_particle_mass) ||
			!(p_body_inverse_mass > real_t(0.0)) || !Math::is_finite(p_body_inverse_mass) ||
			!(p_restitution >= real_t(0.0)) || !(p_restitution <= real_t(1.0)) ||
			!Math::is_finite(p_restitution) ||
			!(p_max_impulse > real_t(0.0)) || !Math::is_finite(p_max_impulse)) {
		return false;
	}
	const double len2 = double(p_normal.length_squared());
	if (!(len2 > 1e-16) || !Math::is_finite(len2)) {
		return false;
	}
	const Vector3 n = p_normal / real_t(Math::sqrt(len2));
	const Vector3 v_relative = p_particle_velocity - p_body_contact_velocity;
	const double closing_speed = double(v_relative.dot(n));
	if (!Math::is_finite(closing_speed) || !(closing_speed < 0.0)) {
		return false; // No new impact when the particle is separating.
	}

	const Vector3 rxn = p_lever.cross(n);
	const Vector3 inertia_response = p_world_inverse_inertia.xform(rxn);
	if (!inertia_response.is_finite()) {
		return false;
	}
	const double rotational_mass = double(n.dot(inertia_response.cross(p_lever)));
	const double effective_inverse_mass =
			1.0 / double(p_particle_mass) + double(p_body_inverse_mass) +
			MAX(0.0, rotational_mass);
	if (!(effective_inverse_mass > 0.0) || !Math::is_finite(effective_inverse_mass)) {
		return false;
	}
	const double unconstrained_impulse =
			-(1.0 + double(p_restitution)) * closing_speed / effective_inverse_mass;
	const double magnitude = MIN(unconstrained_impulse, double(p_max_impulse));
	if (!(magnitude > 0.0) || !Math::is_finite(magnitude)) {
		return false;
	}
	const Vector3 impulse = n * real_t(magnitude);
	const Vector3 corrected_velocity = p_particle_velocity + impulse / p_particle_mass;
	if (!impulse.is_finite() || !corrected_velocity.is_finite()) {
		return false;
	}
	r_result.particle_velocity = corrected_velocity;
	r_result.body_impulse = -impulse;
	r_result.impulse_magnitude = real_t(magnitude);
	return true;
}
