/**************************************************************************/
/*  physics_softbody_orthotropic_bending.h                                 */
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

#include "core/math/vector3.h"

// Orthotropic bending for an oriented SoftBody3D triangle hinge. Its shared
// edge is the fold axis. Given a material warp axis in the REST-MESH frame,
// blend bend compliance with squared direction cosines:
//
//   alpha_hinge / alpha_base = cos(theta)^2 + weft_ratio * sin(theta)^2
//
// theta is between the shared edge and the warp projected into the
// area-weight-independent mean tangent plane of the two REST triangles.
// Warp-aligned folds have unchanged compliance; folds along the weft have
// weft_ratio times the base compliance. This is a direction-dependent
// phenomenological hinge material, not an exact Kirchhoff-Love shell law.
//
// The caller precomputes this ratio ONCE when hinges are rebuilt. The actual
// XPBD alpha is applied once per step (compliance / dt^2) and kept CONSTANT
// during constraint iterations, preserving lambda consistency. No heap
// allocations. Double intermediates avoid float32 cross-product overflow.
// On nonfinite / degenerate input r_ratio is not modified.
_FORCE_INLINE_ static bool physics_softbody_orthotropic_bending_ratio(
		const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, const Vector3 &p_d,
		const Vector3 &p_warp_axis, real_t p_weft_ratio,
		real_t &r_ratio) {
	if (!p_a.is_finite() || !p_b.is_finite() ||
			!p_c.is_finite() || !p_d.is_finite() ||
			!p_warp_axis.is_finite() || !Math::is_finite(p_weft_ratio) ||
			!(p_weft_ratio > 0.0)) {
		return false;
	}
	if (p_weft_ratio == real_t(1.0)) {
		r_ratio = real_t(1.0);
		return true;
	}

	const double ab[3] = { double(p_b.x) - double(p_a.x),
		double(p_b.y) - double(p_a.y), double(p_b.z) - double(p_a.z) };
	const double ac[3] = { double(p_c.x) - double(p_a.x),
		double(p_c.y) - double(p_a.y), double(p_c.z) - double(p_a.z) };
	const double ad[3] = { double(p_d.x) - double(p_a.x),
		double(p_d.y) - double(p_a.y), double(p_d.z) - double(p_a.z) };
	const double warp[3] = { double(p_warp_axis.x),
		double(p_warp_axis.y), double(p_warp_axis.z) };

	const double edge_sq = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
	const double ac_sq = ac[0] * ac[0] + ac[1] * ac[1] + ac[2] * ac[2];
	const double ad_sq = ad[0] * ad[0] + ad[1] * ad[1] + ad[2] * ad[2];
	const double warp_sq = warp[0] * warp[0] + warp[1] * warp[1] + warp[2] * warp[2];
	if (!(edge_sq > 0.0) || !(ac_sq > 0.0) || !(ad_sq > 0.0) ||
			!(warp_sq > 0.0) || !Math::is_finite(edge_sq) ||
			!Math::is_finite(ac_sq) || !Math::is_finite(ad_sq) ||
			!Math::is_finite(warp_sq)) {
		return false;
	}

	// Use the normals of triangles (a,b,c) and (b,a,d), which should
	// have consistent winding. Normalize BEFORE summing so irregularly
	// sized adjacent triangles do not bias the tangent orientation.
	const double n0[3] = { ab[1] * ac[2] - ab[2] * ac[1],
		ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0] };
	const double n1[3] = { ad[1] * ab[2] - ad[2] * ab[1],
		ad[2] * ab[0] - ad[0] * ab[2], ad[0] * ab[1] - ad[1] * ab[0] };
	const double n0_sq = n0[0] * n0[0] + n0[1] * n0[1] + n0[2] * n0[2];
	const double n1_sq = n1[0] * n1[0] + n1[1] * n1[1] + n1[2] * n1[2];
	if (!(n0_sq > 1e-16 * edge_sq * ac_sq) ||
			!(n1_sq > 1e-16 * edge_sq * ad_sq) ||
			!Math::is_finite(n0_sq) || !Math::is_finite(n1_sq)) {
		return false;
	}

	const double inv_n0 = 1.0 / Math::sqrt(n0_sq);
	const double inv_n1 = 1.0 / Math::sqrt(n1_sq);
	double normal[3];
	double normal_sq = 0.0;
	for (int i = 0; i < 3; ++i) {
		normal[i] = n0[i] * inv_n0 + n1[i] * inv_n1;
		normal_sq += normal[i] * normal[i];
	}
	// Perfectly folded (antiparallel normals) hinges have no mean normal;
	// use the first valid face's tangent frame without adding allocations.
	if (!(normal_sq > 1e-12) || !Math::is_finite(normal_sq)) {
		for (int i = 0; i < 3; ++i) {
			normal[i] = n0[i] * inv_n0;
		}
		normal_sq = 1.0;
	}
	const double inv_normal = 1.0 / Math::sqrt(normal_sq);
	const double warp_dot_normal = (warp[0] * normal[0] +
			warp[1] * normal[1] + warp[2] * normal[2]) * inv_normal;
	double projected[3];
	double projected_sq = 0.0;
	double along = 0.0;
	for (int i = 0; i < 3; ++i) {
		projected[i] = warp[i] - warp_dot_normal * normal[i] * inv_normal;
		projected_sq += projected[i] * projected[i];
		along += ab[i] * projected[i];
	}
	// A nearly normal warp axis has no in-surface direction.
	if (!(projected_sq > warp_sq * 1e-12) || !Math::is_finite(projected_sq)) {
		return false;
	}
	const double cos_sq = CLAMP((along * along) / (edge_sq * projected_sq), 0.0, 1.0);
	const double ratio = cos_sq + (1.0 - cos_sq) * double(p_weft_ratio);
	if (!(ratio > 0.0) || !Math::is_finite(ratio)) {
		return false;
	}
	const real_t candidate = real_t(ratio);
	if (!Math::is_finite(candidate) || !(candidate > 0.0)) {
		return false;
	}
	r_ratio = candidate;
	return true;
}
