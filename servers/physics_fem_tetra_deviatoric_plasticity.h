/**************************************************************************/
/*  physics_fem_tetra_deviatoric_plasticity.h                             */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER ARISING FROM, OUT OF OR IN */
/* CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_tetra_neo_hookean.h"

#include <cmath>

// Experimental finite-strain, ISOCHORIC deviatoric plasticity for a tetra.
// F = Ds * inverse(Dm_plastic), C = F^T F. Principal logarithmic stretches
// e_i=log(sigma_i) are objective. Their deviatoric part e_i-mean(e) has
// equivalent norm sqrt(2/3 * sum(dev_i^2)), unlike isotropic volume creep.
//
// A symmetric material flow S = V diag(exp(-beta*dev_i)) V^T updates the
// inverse REST matrix as invDm_new = S * invDm. Since sum(dev_i)=0,
// det(S)=1: the plastic correction RELAXES SHEAR without changing the
// plastic rest volume or signed determinant. This can coexist with the
// separate isotropic volume-plasticity solver, which updates both.
//
// Bilinear kinematic-free isotropic hardening uses a scalar equivalent
// accumulated plastic strain, integrated once on predicted coordinates:
// delta_p = clamp( (eq - yield - hardening*p) * fraction,
//                  0, eq, max_p-p).
// fraction=(1-exp(-rate*dt*(1+hardening)))/(1+hardening).
// This exactly integrates the equivalent-strain relaxation at a fixed
// predicted deformation and fixed principal directions. This is a rate-limited approximation to a J2
// radial return in LOG STRAIN space, not a calibrated finite-strain J2
// stress return, fracture, plastic spin, or mesh remeshing.
//
// Jacobi eigen diagonalization uses stack-only doubles. All matrix/state
// writes are atomic and guarded against inversion, non-finiteness and
// excessive conditioning. Rest volume/mass and topology never change.
_FORCE_INLINE_ static bool physics_fem_tetra_creep_deviatoric_rest(
		const Vector3 p_position[4], double p_yield, double p_hardening,
		double p_fraction, double p_max_accumulated,
		PhysicsFEMTetraRest &r_rest, double &r_accumulated) {
	if (p_position == nullptr || !Math::is_finite(p_yield) || p_yield < 0.0 ||
			!Math::is_finite(p_hardening) || p_hardening < 0.0 ||
			!Math::is_finite(p_fraction) || !(p_fraction > 0.0 && p_fraction <= 1.0) ||
			!Math::is_finite(p_max_accumulated) || !(p_max_accumulated > 0.0) ||
			p_max_accumulated > 8.0 || !Math::is_finite(r_accumulated) ||
			r_accumulated < 0.0 || r_accumulated > p_max_accumulated ||
			!(r_rest.volume > 0.0) || !Math::is_finite(r_rest.volume) ||
			r_rest.signed_det == 0.0 || !Math::is_finite(r_rest.signed_det)) {
		return false;
	}
	for (int a = 0; a < 4; ++a) {
		if (!p_position[a].is_finite()) {
			return false;
		}
	}
	double ds[3][3] = {};
	double deformation[3][3] = {};
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			ds[row][col] = double(p_position[col + 1][row]) - double(p_position[0][row]);
			if (!Math::is_finite(ds[row][col])) {
				return false;
			}
			for (int edge = 0; edge < 3; ++edge) {
				if (!Math::is_finite(r_rest.inv_dm[edge][col])) {
					return false;
				}
				deformation[row][col] +=
						(double(p_position[edge + 1][row]) - double(p_position[0][row])) *
						r_rest.inv_dm[edge][col];
			}
			if (!Math::is_finite(deformation[row][col]) ||
					Math::abs(deformation[row][col]) > 1.0e7) {
				return false;
			}
		}
	}
	const double determinant =
			deformation[0][0] * (deformation[1][1] * deformation[2][2] -
					deformation[1][2] * deformation[2][1]) -
			deformation[0][1] * (deformation[1][0] * deformation[2][2] -
					deformation[1][2] * deformation[2][0]) +
			deformation[0][2] * (deformation[1][0] * deformation[2][1] -
					deformation[1][1] * deformation[2][0]);
	if (!(determinant > 1.0e-9) || !Math::is_finite(determinant)) {
		return false;
	}

	// Right Cauchy–Green strain. Eigenvectors are in undeformed MATERIAL
	// coordinates; rigid world rotations do not change its eigenvalues.
	double c[3][3] = {};
	double basis[3][3] = { { 1.0, 0.0, 0.0 },
		{ 0.0, 1.0, 0.0 }, { 0.0, 0.0, 1.0 } };
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			for (int k = 0; k < 3; ++k) {
				c[i][j] += deformation[k][i] * deformation[k][j];
			}
		}
	}
	// Cyclic symmetric Jacobi, bounded 12 sweeps; reject poor convergence.
	for (int sweep = 0; sweep < 12; ++sweep) {
		for (int pair = 0; pair < 3; ++pair) {
			const int p = pair == 0 ? 0 : (pair == 1 ? 0 : 1);
			const int q = pair == 0 ? 1 : (pair == 1 ? 2 : 2);
			const double off = c[p][q];
			if (Math::abs(off) <= 1.0e-15 *
					Math::sqrt(MAX(0.0, c[p][p] * c[q][q]))) {
				continue;
			}
			const double tau = (c[q][q] - c[p][p]) / (2.0 * off);
			const double sign = tau >= 0.0 ? 1.0 : -1.0;
			const double t = sign / (Math::abs(tau) + Math::sqrt(1.0 + tau * tau));
			const double co = 1.0 / Math::sqrt(1.0 + t * t);
			const double si = t * co;
			const double pp = c[p][p], qq = c[q][q];
			c[p][p] = pp - t * off;
			c[q][q] = qq + t * off;
			c[p][q] = c[q][p] = 0.0;
			for (int k = 0; k < 3; ++k) {
				if (k != p && k != q) {
					const double a = c[k][p], b = c[k][q];
					c[k][p] = c[p][k] = co * a - si * b;
					c[k][q] = c[q][k] = si * a + co * b;
				}
				const double a = basis[k][p], b = basis[k][q];
				basis[k][p] = co * a - si * b;
				basis[k][q] = si * a + co * b;
			}
		}
	}
	double logarithmic[3];
	double average = 0.0;
	for (int i = 0; i < 3; ++i) {
		if (!(c[i][i] > 1.0e-12) || c[i][i] > 1.0e12 ||
				!Math::is_finite(c[i][i])) {
			return false;
		}
		for (int j = i + 1; j < 3; ++j) {
			if (Math::abs(c[i][j]) > 1.0e-9 *
					Math::sqrt(c[i][i] * c[j][j])) {
				return false;
			}
		}
		logarithmic[i] = 0.5 * std::log(c[i][i]);
		average += logarithmic[i] / 3.0;
	}
	double dev[3];
	double squared = 0.0;
	for (int i = 0; i < 3; ++i) {
		dev[i] = logarithmic[i] - average;
		squared += dev[i] * dev[i];
	}
	const double equivalent = Math::sqrt((2.0 / 3.0) * squared);
	const double threshold = p_yield + p_hardening * r_accumulated;
	if (!(equivalent > threshold + 1.0e-12) || !Math::is_finite(equivalent) ||
			!Math::is_finite(threshold)) {
		return false;
	}
	double plastic_step = (equivalent - threshold) * p_fraction;
	plastic_step = MIN(plastic_step, MIN(equivalent, p_max_accumulated - r_accumulated));
	if (!(plastic_step > 1.0e-12) || !Math::is_finite(plastic_step)) {
		return false;
	}
	const double beta = plastic_step / equivalent;
	double flow[3][3] = {};
	for (int i = 0; i < 3; ++i) {
		const double factor = std::exp(-beta * dev[i]);
		if (!(factor > 0.0) || !Math::is_finite(factor)) {
			return false;
		}
		for (int row = 0; row < 3; ++row) {
			for (int col = 0; col < 3; ++col) {
				flow[row][col] += basis[row][i] * factor * basis[col][i];
			}
		}
	}
	PhysicsFEMTetraRest candidate = r_rest;
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			candidate.inv_dm[row][col] = 0.0;
			for (int k = 0; k < 3; ++k) {
				candidate.inv_dm[row][col] += flow[row][k] * r_rest.inv_dm[k][col];
			}
			if (!Math::is_finite(candidate.inv_dm[row][col])) {
				return false;
			}
		}
	}
	// The update is isochoric. Finite arithmetic can introduce tiny
	// determinant drift: normalize the inverse rest matrix to exactly
	// preserve its previous determinant (and the physical element mass).
	const auto matrix_det = [](const double p[3][3]) -> double {
		return p[0][0] * (p[1][1] * p[2][2] - p[1][2] * p[2][1]) -
				p[0][1] * (p[1][0] * p[2][2] - p[1][2] * p[2][0]) +
				p[0][2] * (p[1][0] * p[2][1] - p[1][1] * p[2][0]);
	};
	const double old_det = matrix_det(r_rest.inv_dm);
	const double new_det = matrix_det(candidate.inv_dm);
	const double ratio = new_det / old_det;
	if (!(ratio > 0.0) || !Math::is_finite(ratio) ||
			Math::abs(ratio - 1.0) > 1.0e-5) {
		return false;
	}
	const double renorm = std::cbrt(ratio);
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			candidate.inv_dm[row][col] /= renorm;
			if (!Math::is_finite(candidate.inv_dm[row][col])) {
				return false;
			}
		}
	}
	const double next_accumulated = MIN(p_max_accumulated, r_accumulated + plastic_step);
	if (!Math::is_finite(next_accumulated) || next_accumulated < r_accumulated) {
		return false;
	}
	r_rest = candidate;
	r_accumulated = next_accumulated;
	return true;
}
