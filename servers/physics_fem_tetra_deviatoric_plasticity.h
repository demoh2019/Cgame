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
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_tetra_neo_hookean.h"

#include <algorithm>
#include <cmath>

// Objective finite-strain deviatoric plasticity for tetrahedral FEM.
//
// F = Ds * inv(Dm) is the mechanical elastic deformation gradient.
// The *right* stretch U=sqrt(F^T F) has eigenvectors q_i and positive
// singular values sigma_i. Deviatoric principal Hencky strains are
// e_i = log(sigma_i) - mean(log(sigma)); sum_i(e_i)=0.
// J2-like equivalent strain = sqrt(2/3 * sum(e_i^2)).
//
// Above an elastic yield threshold, a fraction of the excess equivalent
// strain is permanently absorbed in the tetra's rest geometry. We update
// the rest INVERSE matrix on its right:
//     invDm_new = invDm * Q diag(exp(-de_i)) Q^T
// where de_i = e_i * fraction * (1 - yield / equivalent).
// Because sum(de_i)=0, det(Dm_new)=det(Dm): this plastic rest update is
// volume-preserving and affects ONLY shape/shear, unlike volumetric creep.
//
// This is a phenomenological J2-LIKE strain-space radial return, not a
// calibrated metal stress-return mapping. Optional isotropic hardening
// increases the equivalent yield threshold by H * accumulated_strain;
// the existing per-tet history is reused with no further allocations.
// It is frame-indifferent under rigid world rotation with a bounded
// cumulative-strain budget to cap extreme rest distortion.
//
// Compute the orthonormal principal frame of F^T F by Jacobi sweeps.
// Outputs are atomic: malformed/inverted tetrahedra never change rest.
_FORCE_INLINE_ static bool physics_fem_tetra_deviatoric_strains(
		const Vector3 p_points[4], const PhysicsFEMTetraRest &p_rest,
		double r_deviator[3], double r_basis[3][3], double &r_equivalent) {
	if (!p_points || !(p_rest.volume > 0.0) || !Math::is_finite(p_rest.volume) ||
			!Math::is_finite(p_rest.signed_det) || p_rest.signed_det == 0.0) {
		return false;
	}
	for (int i = 0; i < 4; ++i) {
		if (!p_points[i].is_finite()) {
			return false;
		}
	}
	double ds[3][3], f[3][3];
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			ds[row][col] = double(p_points[col + 1][row]) - double(p_points[0][row]);
			if (!Math::is_finite(ds[row][col])) {
				return false;
			}
		}
	}
	const double determinant =
			ds[0][0] * (ds[1][1] * ds[2][2] - ds[1][2] * ds[2][1]) -
			ds[0][1] * (ds[1][0] * ds[2][2] - ds[1][2] * ds[2][0]) +
			ds[0][2] * (ds[1][0] * ds[2][1] - ds[1][1] * ds[2][0]);
	if (!Math::is_finite(determinant) ||
			!(determinant / p_rest.signed_det > 1e-9)) {
		return false; // Leave inverted tetrahedra to inversion recovery.
	}
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			f[row][col] = 0.0;
			for (int k = 0; k < 3; ++k) {
				if (!Math::is_finite(p_rest.inv_dm[k][col])) {
					return false;
				}
				f[row][col] += ds[row][k] * p_rest.inv_dm[k][col];
			}
			if (!Math::is_finite(f[row][col])) {
				return false;
			}
		}
	}
	double metric[3][3] = {};
	double principal[3][3] = {
		{ 1.0, 0.0, 0.0 },
		{ 0.0, 1.0, 0.0 },
		{ 0.0, 0.0, 1.0 },
	};
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			for (int k = 0; k < 3; ++k) {
				metric[row][col] += f[k][row] * f[k][col];
			}
			if (!Math::is_finite(metric[row][col])) {
				return false;
			}
		}
	}

	// Cyclic max-offdiagonal Jacobi diagonalization of symmetric C=F^T F.
	// The eigenvectors remain orthonormal up to double roundoff.
	for (int sweep = 0; sweep < 32; ++sweep) {
		int p = 0, q = 1;
		double off = std::abs(metric[0][1]);
		if (std::abs(metric[0][2]) > off) {
			p = 0;
			q = 2;
			off = std::abs(metric[0][2]);
		}
		if (std::abs(metric[1][2]) > off) {
			p = 1;
			q = 2;
			off = std::abs(metric[1][2]);
		}
		const double magnitude = std::max(1.0,
				std::max(std::abs(metric[0][0]),
						std::max(std::abs(metric[1][1]), std::abs(metric[2][2]))));
		if (off <= 1e-14 * magnitude) {
			break;
		}
		const double apq = metric[p][q];
		const double tau = (metric[q][q] - metric[p][p]) / (2.0 * apq);
		const double t = (tau < 0.0 ? -1.0 : 1.0) /
				(std::abs(tau) + std::sqrt(1.0 + tau * tau));
		const double c = 1.0 / std::sqrt(1.0 + t * t);
		const double s = t * c;
		const double app = metric[p][p], aqq = metric[q][q];
		metric[p][p] = app - t * apq;
		metric[q][q] = aqq + t * apq;
		metric[p][q] = metric[q][p] = 0.0;
		for (int k = 0; k < 3; ++k) {
			if (k != p && k != q) {
				const double akp = metric[k][p], akq = metric[k][q];
				metric[k][p] = metric[p][k] = c * akp - s * akq;
				metric[k][q] = metric[q][k] = s * akp + c * akq;
			}
			const double vkp = principal[k][p], vkq = principal[k][q];
			principal[k][p] = c * vkp - s * vkq;
			principal[k][q] = s * vkp + c * vkq;
		}
	}
	double stretch_log[3], mean = 0.0;
	for (int i = 0; i < 3; ++i) {
		const double squared = metric[i][i];
		if (!(squared > 1e-12) || squared > 1e12 || !Math::is_finite(squared)) {
			return false;
		}
		stretch_log[i] = 0.5 * std::log(squared);
		if (!Math::is_finite(stretch_log[i])) {
			return false;
		}
		mean += stretch_log[i] / 3.0;
	}
	double dev[3], norm_sq = 0.0;
	for (int i = 0; i < 3; ++i) {
		dev[i] = stretch_log[i] - mean;
		norm_sq += dev[i] * dev[i];
	}
	const double equivalent = std::sqrt((2.0 / 3.0) * norm_sq);
	if (!Math::is_finite(equivalent)) {
		return false;
	}
	for (int i = 0; i < 3; ++i) {
		r_deviator[i] = dev[i];
		for (int j = 0; j < 3; ++j) {
			r_basis[j][i] = principal[j][i];
		}
	}
	r_equivalent = equivalent;
	return true;
}

_FORCE_INLINE_ static bool physics_fem_tetra_creep_deviatoric_rest(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		const Vector3 &p_d, real_t p_yield_equivalent, double p_fraction,
		double p_max_accumulated_strain, PhysicsFEMTetraRest &r_rest,
		double &r_accumulated_strain, double p_hardening = 0.0) {
	if (!Math::is_finite(p_hardening) ||
			!(p_hardening >= 0.0 && p_hardening <= 10.0) ||
			!Math::is_finite(p_yield_equivalent) ||
			!(p_yield_equivalent >= real_t(0.0) && p_yield_equivalent <= real_t(2.0)) ||
			!Math::is_finite(p_fraction) || !(p_fraction > 0.0 && p_fraction <= 1.0) ||
			!Math::is_finite(p_max_accumulated_strain) ||
			!(p_max_accumulated_strain >= 0.01 && p_max_accumulated_strain <= 4.0) ||
			!Math::is_finite(r_accumulated_strain) || r_accumulated_strain < 0.0 ||
			r_accumulated_strain >= p_max_accumulated_strain) {
		return false;
	}
	const Vector3 points[4] = { p_a, p_b, p_c, p_d };
	double dev[3], basis[3][3], equivalent = 0.0;
	if (!physics_fem_tetra_deviatoric_strains(points, r_rest, dev, basis, equivalent) ||
			!(equivalent > double(p_yield_equivalent))) {
		return false;
	}
	// The yield surface expands as accumulated plastic strain grows.
	// The caller may pass (1-exp(-rate*dt*(1+H)))/(1+H) as p_fraction,
	// which is the exact relaxation factor for constant Hencky strain
	// and isotropic hardening. H=0 preserves all legacy behavior.
	const double yield_threshold = double(p_yield_equivalent) +
			p_hardening * r_accumulated_strain;
	if (!Math::is_finite(yield_threshold) || !(equivalent > yield_threshold)) {
		return false;
	}
	const double requested = p_fraction * (equivalent - yield_threshold);
	const double available = p_max_accumulated_strain - r_accumulated_strain;
	const double step = std::min(requested, available);
	if (!(step > 1e-14) || !Math::is_finite(step)) {
		return false;
	}
	const double scale = step / equivalent;
	double multiplier[3];
	for (int i = 0; i < 3; ++i) {
		multiplier[i] = std::exp(-scale * dev[i]);
		if (!(multiplier[i] > 0.0) || !Math::is_finite(multiplier[i])) {
			return false;
		}
	}
	double rest_correction[3][3] = {};
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			for (int j = 0; j < 3; ++j) {
				rest_correction[row][col] += basis[row][j] * multiplier[j] * basis[col][j];
			}
			if (!Math::is_finite(rest_correction[row][col])) {
				return false;
			}
		}
	}
	const double det =
			rest_correction[0][0] *
					(rest_correction[1][1] * rest_correction[2][2] -
							rest_correction[1][2] * rest_correction[2][1]) -
			rest_correction[0][1] *
					(rest_correction[1][0] * rest_correction[2][2] -
							rest_correction[1][2] * rest_correction[2][0]) +
			rest_correction[0][2] *
					(rest_correction[1][0] * rest_correction[2][1] -
							rest_correction[1][1] * rest_correction[2][0]);
	if (!Math::is_finite(det) || std::abs(det - 1.0) > 1e-8) {
		return false; // Material rest volume must remain unchanged.
	}
	PhysicsFEMTetraRest candidate = r_rest;
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			double value = 0.0;
			for (int k = 0; k < 3; ++k) {
				value += r_rest.inv_dm[row][k] * rest_correction[k][col];
			}
			if (!Math::is_finite(value) || std::abs(value) > 1e20) {
				return false;
			}
			candidate.inv_dm[row][col] = value;
		}
	}
	// Correct double-precision determinant drift in the inverse rest
	// matrix rather than allowing tiny non-isochoric errors to accumulate
	// over thousands of plastic steps. Keep physical rest volume/mass fixed.
	const auto det3 = [](const double m[3][3]) -> double {
		return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
				m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
				m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
	};
	const double old_det = det3(r_rest.inv_dm);
	const double new_det = det3(candidate.inv_dm);
	const double determinant_ratio = new_det / old_det;
	if (!(determinant_ratio > 0.0) || !Math::is_finite(determinant_ratio) ||
			std::abs(determinant_ratio - 1.0) > 1e-5) {
		return false;
	}
	const double correction = std::cbrt(determinant_ratio);
	if (!(correction > 0.0) || !Math::is_finite(correction)) {
		return false;
	}
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			candidate.inv_dm[row][col] /= correction;
			if (!Math::is_finite(candidate.inv_dm[row][col])) {
				return false;
			}
		}
	}
	const double updated_strain = r_accumulated_strain + step;
	if (!Math::is_finite(updated_strain) ||
			updated_strain < r_accumulated_strain ||
			updated_strain > p_max_accumulated_strain) {
		return false;
	}
	// Neither rest.volume nor signed_det changes, unlike volumetric creep.
	// A failed step never partially changes the reference geometry/history.
	r_rest = candidate;
	r_accumulated_strain = updated_strain;
	return true;
}
