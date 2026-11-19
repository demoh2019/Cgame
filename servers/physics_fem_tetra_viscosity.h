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

#include "servers/physics_fem_tetra_neo_hookean.h"

// Objective finite-strain Kelvin-Voigt tetrahedral viscosity. Its material
// strain rate is E_dot = sym(F^T F_dot); unlike damping per world-space
// vertex speed, this vanishes under arbitrary rigid translation AND rigid
// rotation of a deformed tetrahedron.
//
// Effective viscous first Piola stress:
// P_v = F [ eta * (2*mu*E_dot + lambda*tr(E_dot)*I) ]
// with mu/lambda computed at unit Young modulus using Poisson's ratio.
// Integrate as an explicitly bounded velocity impulse along viscous forces.
//
// The kinetic energy descent bound is derived from
// K(v + t M^-1 f) - K(v) = t sum(v.f) + t²/2 sum(inv_mass * f²).
// Clamp t <= -sum(v.f) / sum(inv_mass * f²) to avoid overshooting the
// one-dimensional kinetic energy minimum, even at extreme viscosity.
// Pinned particles remain fixed, and all four outputs are atomic on error.
// Without moving pins, forces conserve linear/angular momentum.

_FORCE_INLINE_ bool physics_fem_tetra_viscous_forces(
		const Vector3 p_positions[4], const Vector3 p_velocities[4],
		const PhysicsFEMTetraRest &p_rest, double p_poisson,
		double p_viscosity, Vector3 r_forces[4]) {
	if (!p_positions || !p_velocities || !r_forces ||
			!(p_viscosity > 0.0) || !Math::is_finite(p_viscosity) ||
			!Math::is_finite(p_poisson) || p_poisson < 0.0 || p_poisson > 0.49 ||
			!(p_rest.volume > 0.0) || !Math::is_finite(p_rest.volume) ||
			!Math::is_finite(p_rest.signed_det) || p_rest.signed_det == 0.0) {
		return false;
	}
	for (int i = 0; i < 4; ++i) {
		if (!p_positions[i].is_finite() || !p_velocities[i].is_finite()) {
			return false;
		}
	}
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			if (!Math::is_finite(p_rest.inv_dm[row][col])) {
				return false;
			}
		}
	}

	// Current and rate deformation-gradient columns.
	double dx[3][3], dv[3][3];
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			dx[row][col] = double(p_positions[col + 1][row]) - double(p_positions[0][row]);
			dv[row][col] = double(p_velocities[col + 1][row]) - double(p_velocities[0][row]);
		}
	}
	double f[3][3], df[3][3];
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			f[row][col] = 0.0;
			df[row][col] = 0.0;
			for (int k = 0; k < 3; ++k) {
				f[row][col] += dx[row][k] * p_rest.inv_dm[k][col];
				df[row][col] += dv[row][k] * p_rest.inv_dm[k][col];
			}
			if (!Math::is_finite(f[row][col]) || !Math::is_finite(df[row][col])) {
				return false;
			}
		}
	}
	// The elastic Neo-Hookean element rejects inverted or collapsed
	// deformation gradients; viscosity must do the same, or a broken
	// element could dissipate through an unphysical negative-J state.
	const double j = f[0][0] * (f[1][1] * f[2][2] - f[1][2] * f[2][1]) -
			f[0][1] * (f[1][0] * f[2][2] - f[1][2] * f[2][0]) +
			f[0][2] * (f[1][0] * f[2][1] - f[1][1] * f[2][0]);
	if (!(j > 1e-9) || !Math::is_finite(j)) {
		return false;
	}
	// sym(F^T F_dot) is invariant to superposed rigid rotations.
	double edot[3][3], trace = 0.0;
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			double a = 0.0, b = 0.0;
			for (int k = 0; k < 3; ++k) {
				a += f[k][i] * df[k][j];
				b += df[k][i] * f[k][j];
			}
			edot[i][j] = 0.5 * (a + b);
		}
		trace += edot[i][i];
	}
	const double mu = 0.5 / (1.0 + p_poisson);
	const double lame = p_poisson / ((1.0 + p_poisson) * (1.0 - 2.0 * p_poisson));
	double stress[3][3], first_piola[3][3];
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			stress[i][j] = p_viscosity *
					(2.0 * mu * edot[i][j] + (i == j ? lame * trace : 0.0));
			if (!Math::is_finite(stress[i][j])) {
				return false;
			}
		}
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			first_piola[i][j] = 0.0;
			for (int k = 0; k < 3; ++k) {
				first_piola[i][j] += f[i][k] * stress[k][j];
			}
			if (!Math::is_finite(first_piola[i][j])) {
				return false;
			}
		}
	}

	double nodal[4][3] = {};
	for (int row = 0; row < 3; ++row) {
		for (int vertex = 1; vertex < 4; ++vertex) {
			for (int k = 0; k < 3; ++k) {
				nodal[vertex][row] -= p_rest.volume *
						first_piola[row][k] * p_rest.inv_dm[vertex - 1][k];
			}
		}
		nodal[0][row] = -nodal[1][row] - nodal[2][row] - nodal[3][row];
	}
	Vector3 candidate[4];
	for (int i = 0; i < 4; ++i) {
		for (int k = 0; k < 3; ++k) {
			if (!Math::is_finite(nodal[i][k])) {
				return false;
			}
		}
		candidate[i] = Vector3(real_t(nodal[i][0]), real_t(nodal[i][1]), real_t(nodal[i][2]));
		if (!candidate[i].is_finite()) {
			return false;
		}
	}
	for (int i = 0; i < 4; ++i) {
		r_forces[i] = candidate[i];
	}
	return true;
}

_FORCE_INLINE_ bool physics_fem_tetra_viscous_damp(
		const Vector3 p_positions[4], Vector3 r_velocities[4],
		const real_t p_inv_masses[4], const PhysicsFEMTetraRest &p_rest,
		double p_poisson, double p_viscosity, double p_delta) {
	if (!p_positions || !r_velocities || !p_inv_masses ||
			!(p_delta > 0.0) || !Math::is_finite(p_delta)) {
		return false;
	}
	double power = 0.0, denominator = 0.0;
	Vector3 forces[4];
	if (!physics_fem_tetra_viscous_forces(
				p_positions, r_velocities, p_rest, p_poisson,
				p_viscosity, forces)) {
		return false;
	}
	for (int i = 0; i < 4; ++i) {
		const double mass_inverse = double(p_inv_masses[i]);
		if (!(mass_inverse >= 0.0) || !Math::is_finite(mass_inverse)) {
			return false;
		}
		if (mass_inverse == 0.0) {
			continue;
		}
		for (int axis = 0; axis < 3; ++axis) {
			const double f = double(forces[i][axis]);
			power += double(r_velocities[i][axis]) * f;
			denominator += mass_inverse * f * f;
		}
	}
	// With zero movable strain or purely rigid motion, no damping is
	// needed. In a kinematic-pin situation, ignore an energy-injecting
	// force rather than destabilizing the movable degrees of freedom.
	if (!(power < 0.0) || !(denominator > 0.0) ||
			!Math::is_finite(power) || !Math::is_finite(denominator)) {
		return false;
	}
	const double maximum_descent_step = -power / denominator;
	const double step = p_delta < maximum_descent_step ? p_delta : maximum_descent_step;
	if (!(step > 0.0) || !Math::is_finite(step)) {
		return false;
	}
	Vector3 candidate[4];
	for (int i = 0; i < 4; ++i) {
		candidate[i] = r_velocities[i];
		if (p_inv_masses[i] > 0.0) {
			const double change = double(p_inv_masses[i]) * step;
			candidate[i] = Vector3(
					real_t(double(r_velocities[i].x) + change * double(forces[i].x)),
					real_t(double(r_velocities[i].y) + change * double(forces[i].y)),
					real_t(double(r_velocities[i].z) + change * double(forces[i].z)));
			if (!candidate[i].is_finite()) {
				return false;
			}
		}
	}
	for (int i = 0; i < 4; ++i) {
		r_velocities[i] = candidate[i];
	}
	return true;
}
