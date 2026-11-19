/**************************************************************************/
/*  physics_fem_tetra_fiber_plasticity.h                                   */
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

#include "servers/physics_fem_tetra_fiber.h"

// Measure |F*a0|, with the fiber axis a0 fixed in the UNDEFORMED material
// coordinates. This is objective under arbitrary rigid world rotations
// and translations, independent of the tetrahedron rest scale.
// A singular or inverted FEM element does not update plastic history.
//
// The scalar is measured on *predicted* positions before XPBD
// elasticity projects away the over-yield deformation.
_FORCE_INLINE_ static bool physics_fem_tetra_fiber_measure_stretch(
		const Vector3 p_positions[4], const PhysicsFEMTetraRest &p_rest,
		const Vector3 &p_material_axis, double &r_stretch) {
	if (p_positions == nullptr || !p_material_axis.is_finite() ||
			!(p_rest.volume > 0.0) || !Math::is_finite(p_rest.volume) ||
			!Math::is_finite(p_rest.signed_det) || p_rest.signed_det == 0.0) {
		return false;
	}
	const double axis[3] = {
		double(p_material_axis.x), double(p_material_axis.y),
		double(p_material_axis.z)
	};
	const double axis_length_sq =
			axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2];
	if (!(axis_length_sq > 0.0) || !Math::is_finite(axis_length_sq)) {
		return false;
	}
	const double inverse_length = 1.0 / Math::sqrt(axis_length_sq);
	double ds[3][3] = {};
	for (int vertex = 0; vertex < 4; ++vertex) {
		if (!p_positions[vertex].is_finite()) {
			return false;
		}
	}
	for (int row = 0; row < 3; ++row) {
		for (int edge = 0; edge < 3; ++edge) {
			ds[row][edge] =
					double(p_positions[edge + 1][row]) - double(p_positions[0][row]);
			if (!Math::is_finite(ds[row][edge])) {
				return false;
			}
		}
	}
	const double determinant =
			ds[0][0] * (ds[1][1] * ds[2][2] - ds[1][2] * ds[2][1]) -
			ds[0][1] * (ds[1][0] * ds[2][2] - ds[1][2] * ds[2][0]) +
			ds[0][2] * (ds[1][0] * ds[2][1] - ds[1][1] * ds[2][0]);
	if (!(determinant / p_rest.signed_det > 1.0e-9) ||
			!Math::is_finite(determinant)) {
		return false;
	}
	double fiber_direction[3] = {};
	for (int row = 0; row < 3; ++row) {
		for (int edge = 0; edge < 3; ++edge) {
			for (int col = 0; col < 3; ++col) {
				const double inverse = p_rest.inv_dm[edge][col];
				if (!Math::is_finite(inverse)) {
					return false;
				}
				fiber_direction[row] += ds[row][edge] *
						inverse * (axis[col] * inverse_length);
			}
		}
	}
	const double stretch_squared =
			fiber_direction[0] * fiber_direction[0] +
			fiber_direction[1] * fiber_direction[1] +
			fiber_direction[2] * fiber_direction[2];
	if (!(stretch_squared > 0.0) || !Math::is_finite(stretch_squared)) {
		return false;
	}
	const double stretch = Math::sqrt(stretch_squared);
	if (!(stretch > 0.0) || !Math::is_finite(stretch)) {
		return false;
	}
	r_stretch = stretch;
	return true;
}

// One-sided, rate-dependent permanent elongation of the material fiber.
// Its zero-tension rest stretch starts at 1 and NEVER decreases.
//
// Yield condition: current_stretch > plastic_rest * (1 + yield_ratio).
// On yield, the equilibrium plastic rest stretch is
// current_stretch / (1 + yield_ratio); approach it exponentially:
//
//    rest_next = rest + (target - rest) * (1-exp(-creep_rate*dt))
//
// At constant imposed extension, the expression is invariant to splitting
// a time step. Only tensile remodeling is supported. Compression is slack.
// Clamp the rest stretch to avoid unbounded strain targets or overflow.
_FORCE_INLINE_ static bool physics_fem_tetra_fiber_creep_rest_stretch(
		double p_current_stretch, double p_yield_ratio, double p_creep_rate,
		double p_delta, double p_max_rest_stretch, real_t &r_rest_stretch) {
	if (!(p_current_stretch > 0.0) || !Math::is_finite(p_current_stretch) ||
			!(p_yield_ratio >= 0.0) || !Math::is_finite(p_yield_ratio) ||
			!(p_creep_rate > 0.0) || !Math::is_finite(p_creep_rate) ||
			!(p_delta > 0.0) || !Math::is_finite(p_delta) ||
			!(p_max_rest_stretch >= 1.0) || p_max_rest_stretch > 16.0 ||
			!Math::is_finite(p_max_rest_stretch) ||
			!Math::is_finite(r_rest_stretch) || r_rest_stretch < real_t(1.0)) {
		return false;
	}
	const real_t cap = real_t(p_max_rest_stretch);
	if (!Math::is_finite(cap) || r_rest_stretch > cap) {
		return false;
	}
	const double threshold = double(r_rest_stretch) * (1.0 + p_yield_ratio);
	if (!(p_current_stretch > threshold)) {
		return false; // No plastic deformation below tensile yield.
	}
	const double target = MIN(p_max_rest_stretch,
			p_current_stretch / (1.0 + p_yield_ratio));
	if (!(target > double(r_rest_stretch)) || !Math::is_finite(target)) {
		return false;
	}
	const double fraction = 1.0 - Math::exp(-p_creep_rate * p_delta);
	if (!(fraction > 0.0) || !Math::is_finite(fraction)) {
		return false;
	}
	const double result = double(r_rest_stretch) +
			(target - double(r_rest_stretch)) * fraction;
	if (!Math::is_finite(result)) {
		return false;
	}
	const real_t next = real_t(MIN(double(cap), result));
	if (!Math::is_finite(next) || next < r_rest_stretch || next > cap ||
			next == r_rest_stretch) {
		return false;
	}
	r_rest_stretch = next;
	return true;
}
