/**************************************************************************/
/*  physics_fem_tetra_viscosity.h                                         */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_tetra_neo_hookean.h"

// A velocity-space, objective finite-strain Kelvin-Voigt-style dashpot for
// a tetrahedral element. Unlike link damping, it also dissipates SHEAR and
// volumetric strain rates. Six scalar material strain-rate modes are treated
// sequentially in a mass-weighted, stable (non-overshooting) projection.
//
// E = (F^T F - I)/2,  dE/dt = (F^T Fdot + Fdot^T F)/2.
// F = Ds * inverse(Dm). Each mode dE_ij/dt is linear in nodal velocities.
// Its Jacobian is computed from the current F, so a rigid translation or
// infinitesimal rigid rotation produces exactly zero strain rate in exact
// arithmetic. Unlike global velocity damping, these internal impulses
// preserve total linear/angular momentum for freely moving nodes.
//
// The exponential p_fraction = 1-exp(-damping_rate*dt) is computed ONCE
// by the caller, in [0,1]. The 6 projections cannot increase kinetic
// energy individually in exact arithmetic; after converting to real_t,
// all velocities are validated and committed together or not at all.
// No allocations, cached matrices, or per-step lambda storage.
_FORCE_INLINE_ static bool physics_fem_tetra_damp_strain_rate(
		const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, const Vector3 &p_d,
		Vector3 &r_va, Vector3 &r_vb, Vector3 &r_vc, Vector3 &r_vd,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest, double p_fraction) {
	if (!(p_fraction > 0.0) || p_fraction > 1.0 ||
			!Math::is_finite(p_fraction) || !(p_rest.volume > 0.0) ||
			!Math::is_finite(p_rest.volume) ||
			!p_a.is_finite() || !p_b.is_finite() ||
			!p_c.is_finite() || !p_d.is_finite() ||
			!r_va.is_finite() || !r_vb.is_finite() ||
			!r_vc.is_finite() || !r_vd.is_finite()) {
		return false;
	}

	const double inv_mass[4] = {
		double(p_inv_a), double(p_inv_b), double(p_inv_c), double(p_inv_d)
	};
	const Vector3 positions[4] = { p_a, p_b, p_c, p_d };
	const Vector3 original[4] = { r_va, r_vb, r_vc, r_vd };
	double velocity[4][3] = {};
	double initial_energy = 0.0;
	for (int vertex = 0; vertex < 4; ++vertex) {
		if (!(inv_mass[vertex] >= 0.0) || !Math::is_finite(inv_mass[vertex])) {
			return false;
		}
		for (int axis = 0; axis < 3; ++axis) {
			velocity[vertex][axis] = double(original[vertex][axis]);
			if (inv_mass[vertex] > 0.0) {
				initial_energy += velocity[vertex][axis] * velocity[vertex][axis] /
						(2.0 * inv_mass[vertex]);
			}
		}
	}
	if (!Math::is_finite(initial_energy)) {
		return false;
	}
	// Edge columns of current Ds and the inverse rest edges. Wide
	// subtractions avoid float overflow for translated large coordinates.
	double deformation[3][3] = {};
	double coeff[4][3] = {};
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			for (int edge = 0; edge < 3; ++edge) {
				const double inv = p_rest.inv_dm[edge][col];
				if (!Math::is_finite(inv)) {
					return false;
				}
				deformation[row][col] +=
						(double(positions[edge + 1][row]) - double(positions[0][row])) * inv;
			}
			if (!Math::is_finite(deformation[row][col])) {
				return false;
			}
		}
		for (int col = 0; col < 3; ++col) {
			coeff[row + 1][col] = p_rest.inv_dm[row][col];
			coeff[0][col] -= p_rest.inv_dm[row][col];
		}
	}
	const double det =
			deformation[0][0] * (deformation[1][1] * deformation[2][2] - deformation[1][2] * deformation[2][1]) -
			deformation[0][1] * (deformation[1][0] * deformation[2][2] - deformation[1][2] * deformation[2][0]) +
			deformation[0][2] * (deformation[1][0] * deformation[2][1] - deformation[1][1] * deformation[2][0]);
	if (!(det > 1e-9) || !Math::is_finite(det)) {
		return false; // Inverted or singular FEM element.
	}

	const int modes[6][2] = { { 0, 0 }, { 1, 1 }, { 2, 2 },
		{ 0, 1 }, { 0, 2 }, { 1, 2 } };
	bool changed = false;
	for (int mode = 0; mode < 6; ++mode) {
		const int i = modes[mode][0];
		const int j = modes[mode][1];
		double gradient[4][3] = {};
		double weighted_mass = 0.0;
		double strain_rate = 0.0;
		for (int vertex = 0; vertex < 4; ++vertex) {
			for (int axis = 0; axis < 3; ++axis) {
				gradient[vertex][axis] = 0.5 *
						(coeff[vertex][j] * deformation[axis][i] +
								coeff[vertex][i] * deformation[axis][j]);
				weighted_mass += inv_mass[vertex] *
						gradient[vertex][axis] * gradient[vertex][axis];
				// Relative velocity prevents rigid translation from
				// causing spurious damping at large world velocities.
				if (vertex != 0) {
					strain_rate += gradient[vertex][axis] *
							(velocity[vertex][axis] - velocity[0][axis]);
				}
			}
		}
		if (!Math::is_finite(weighted_mass) || !Math::is_finite(strain_rate)) {
			return false; // Invalid mode: no partial velocity commits.
		}
		if (!(weighted_mass > 0.0)) {
			continue; // Fully pinned/degenerate mode.
		}
		const double impulse = -p_fraction * strain_rate / weighted_mass;
		if (!Math::is_finite(impulse) || impulse == 0.0) {
			continue;
		}
		changed = true;
		for (int vertex = 0; vertex < 4; ++vertex) {
			for (int axis = 0; axis < 3; ++axis) {
				velocity[vertex][axis] += inv_mass[vertex] * impulse *
						gradient[vertex][axis];
				if (!Math::is_finite(velocity[vertex][axis])) {
					return false;
				}
			}
		}
	}
	if (!changed) {
		return false;
	}

	Vector3 next[4];
	double final_energy = 0.0;
	for (int vertex = 0; vertex < 4; ++vertex) {
		next[vertex] = Vector3(real_t(velocity[vertex][0]),
				real_t(velocity[vertex][1]), real_t(velocity[vertex][2]));
		if (!next[vertex].is_finite()) {
			return false;
		}
		if (inv_mass[vertex] > 0.0) {
			for (int axis = 0; axis < 3; ++axis) {
				const double v = double(next[vertex][axis]);
				final_energy += v * v / (2.0 * inv_mass[vertex]);
			}
		}
	}
	// Roundoff can change the energy by a tiny amount after float casts,
	// but never accept meaningful kinetic energy amplification.
	if (!Math::is_finite(final_energy) ||
			final_energy > initial_energy * (1.0 + 1e-6) + 1e-12) {
		return false;
	}
	r_va = next[0];
	r_vb = next[1];
	r_vc = next[2];
	r_vd = next[3];
	return true;
}
