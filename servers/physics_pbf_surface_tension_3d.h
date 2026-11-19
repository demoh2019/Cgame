/**************************************************************************/
/*  physics_pbf_surface_tension_3d.h                                      */
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

#include "core/math/vector3.h"

// Akinci-inspired free-surface tension for a PBF particle liquid. Combines
// a radial cohesion kernel (attraction around the desired separation and
// short-range repulsion) with the difference in SPH color-field normals.
// Unlike a one-sided sum, every accepted pair contributes equal/opposite
// velocity increments, ensuring EXACT pairwise linear momentum balance.
//
// The curvature term is generally NOT central and need not conserve
// angular momentum. This is an explicit bounded SPH post-process, not
// an implicit/energy-conserving surface tension scheme or wall adhesion.
//
// Kernel: 32/(pi*h^9) times
//     (h-r)^3 * r^3                  for h/2 < r < h
//     2*(h-r)^3*r^3 - h^6/64         for 0 < r <= h/2
// and zero outside compact support. Centered coincidence is skipped
// because the unit radial direction is undefined.
struct PhysicsPBFSurfaceTension3D {
	static _FORCE_INLINE_ real_t cohesion_kernel(double p_distance, double p_h) {
		if (!(p_distance > 1e-8) || !(p_h > 0.0) ||
				!Math::is_finite(p_distance) || !Math::is_finite(p_h) ||
				p_distance >= p_h) {
			return 0.0;
		}
		const double h2 = p_h * p_h;
		const double h3 = h2 * p_h;
		const double h6 = h3 * h3;
		const double h9 = h6 * h3;
		if (!(h9 > 0.0) || !Math::is_finite(h9)) {
			return 0.0;
		}
		const double r3 = p_distance * p_distance * p_distance;
		const double d = p_h - p_distance;
		const double spline = d * d * d * r3;
		const double shape = (p_distance <= p_h * 0.5) ?
				(2.0 * spline - h6 / 64.0) : spline;
		const double result = (32.0 / (Math::PI * h9)) * shape;
		const real_t coefficient = real_t(result);
		return Math::is_finite(result) && Math::is_finite(coefficient) ?
				coefficient : real_t(0.0);
	}

	static _FORCE_INLINE_ real_t symmetric_density_weight(
			real_t p_self_density, real_t p_neighbor_density, real_t p_rest_density) {
		if (!(p_self_density > 0.0) || !(p_neighbor_density > 0.0) ||
				!(p_rest_density > 0.0) || !Math::is_finite(p_self_density) ||
				!Math::is_finite(p_neighbor_density) || !Math::is_finite(p_rest_density)) {
			return 0.0;
		}
		const double factor = (2.0 * double(p_rest_density)) /
				(double(p_self_density) + double(p_neighbor_density));
		return Math::is_finite(factor) ? real_t(CLAMP(factor, 0.0, 4.0)) : 0.0;
	}

	static _FORCE_INLINE_ Vector3 color_normal_pair(
			const Vector3 &p_kernel_gradient, real_t p_neighbor_mass_over_density,
			real_t p_smoothing_radius) {
		if (!p_kernel_gradient.is_finite() ||
				!(p_neighbor_mass_over_density > 0.0) ||
				!Math::is_finite(p_neighbor_mass_over_density) ||
				!(p_smoothing_radius > 0.0) || !Math::is_finite(p_smoothing_radius)) {
			return Vector3();
		}
		const double scale = double(p_smoothing_radius) *
				double(p_neighbor_mass_over_density);
		const Vector3 normal = p_kernel_gradient * real_t(scale);
		return normal.is_finite() ? normal : Vector3();
	}

	// Returns the change for particle i; apply -delta to particle j.
	// The cohesion contribution points TOWARD j above r=h/2, away from j
	// below the repulsive kernel sign change. Curvature smooths the
	// color-field normal discontinuity near the free surface.
	static _FORCE_INLINE_ Vector3 pair_velocity_increment(
			const Vector3 &p_displacement, const Vector3 &p_normal_i,
			const Vector3 &p_normal_j, real_t p_density_i,
			real_t p_density_j, real_t p_rest_density,
			real_t p_mass, real_t p_h, real_t p_cohesion_strength,
			real_t p_curvature_strength, real_t p_delta,
			real_t p_max_pair_velocity_change) {
		if (!p_displacement.is_finite() || !p_normal_i.is_finite() ||
				!p_normal_j.is_finite() || !(p_density_i > 0.0) ||
				!(p_density_j > 0.0) || !(p_mass > 0.0) ||
				!(p_h > 0.0) || !(p_delta > 0.0) ||
				!(p_max_pair_velocity_change > 0.0) ||
				!(p_cohesion_strength >= 0.0) || !(p_curvature_strength >= 0.0) ||
				!Math::is_finite(p_mass) || !Math::is_finite(p_h) ||
				!Math::is_finite(p_delta) || !Math::is_finite(p_max_pair_velocity_change) ||
				!Math::is_finite(p_cohesion_strength) ||
				!Math::is_finite(p_curvature_strength)) {
			return Vector3();
		}
		if (p_cohesion_strength == 0.0 && p_curvature_strength == 0.0) {
			return Vector3();
		}
		const double r2 = double(p_displacement.length_squared());
		if (!(r2 > 1e-16) || !(r2 < double(p_h) * double(p_h)) ||
				!Math::is_finite(r2)) {
			return Vector3();
		}
		const double distance = Math::sqrt(r2);
		const real_t factor = symmetric_density_weight(
				p_density_i, p_density_j, p_rest_density);
		if (!(factor > 0.0)) {
			return Vector3();
		}
		const Vector3 radial = p_displacement / real_t(distance);
		const Vector3 cohesive = radial *
				(p_mass * cohesion_kernel(distance, p_h) * p_cohesion_strength);
		const Vector3 curvature = (p_normal_i - p_normal_j) * p_curvature_strength;
		const Vector3 acceleration = -(cohesive + curvature) * factor;
		if (!acceleration.is_finite()) {
			return Vector3();
		}
		const double magnitude_squared = double(acceleration.length_squared());
		if (!(magnitude_squared > 0.0) || !Math::is_finite(magnitude_squared)) {
			return Vector3();
		}
		const double magnitude = Math::sqrt(magnitude_squared);
		const double desired = magnitude * double(p_delta);
		if (!(desired > 0.0) || !Math::is_finite(desired)) {
			return Vector3();
		}
		const double bounded = MIN(desired, double(p_max_pair_velocity_change));
		const Vector3 result = (acceleration / real_t(magnitude)) * real_t(bounded);
		return result.is_finite() ? result : Vector3();
	}
};
