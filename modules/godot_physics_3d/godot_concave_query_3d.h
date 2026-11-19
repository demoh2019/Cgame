/**************************************************************************/
/*  godot_concave_query_3d.h                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "godot_shape_3d.h"

// Computes a conservative convex query bound directly in the concave
// shape's local space. For an affine (possibly sheared) concave transform,
// projecting on its basis columns is NOT equivalent to local axis projection.
//
// If p_world_hint is given, it bounds a swept/kinematic query or a
// soft-body node patch in world coordinates; p_convex_shape may be null.
// Otherwise the convex shape's exact support projections give a generally
// tighter bound than transforming its local AABB.
//
// Returns false for singular transforms; the caller must then visit all
// triangles rather than risk rejecting valid collisions.
_FORCE_INLINE_ static bool godot_physics_3d_concave_query_aabb(
		const GodotShape3D *p_convex_shape,
		const Transform3D &p_convex_transform,
		const Transform3D &p_concave_transform,
		AABB &r_local_aabb,
		real_t p_margin_a = 0.0,
		real_t p_margin_b = 0.0,
		const AABB *p_world_hint = nullptr) {
	const real_t determinant = p_concave_transform.basis.determinant();
	if (Math::is_zero_approx(determinant)) {
		return false;
	}

	const Basis inverse_basis = p_concave_transform.basis.inverse();
	const Transform3D local_basis(inverse_basis, Vector3());
	if (p_world_hint != nullptr) {
		// Preserve precision by subtracting the concave origin before
		// transforming the world-space hint into mesh-local coordinates.
		const AABB relative_hint(p_world_hint->position - p_concave_transform.origin, p_world_hint->size);
		r_local_aabb = local_basis.xform(relative_hint);
	} else {
		Transform3D relative_transform = p_convex_transform;
		relative_transform.origin -= p_concave_transform.origin;
		relative_transform = local_basis * relative_transform;

		for (int i = 0; i < 3; ++i) {
			Vector3 axis;
			axis[i] = 1.0;
			real_t minimum = 0.0;
			real_t maximum = 0.0;
			p_convex_shape->project_range(axis, relative_transform, minimum, maximum);
			r_local_aabb.position[i] = minimum;
			r_local_aabb.size[i] = maximum - minimum;
		}
	}

	// World-space margins transform into an ellipsoid under an inverse
	// affine map. The support radius along a mesh-local axis equals the
	// Euclidean length of that row of the inverse basis.
	const real_t world_margin = MAX(p_margin_a, real_t(0.0)) + MAX(p_margin_b, real_t(0.0));
	if (world_margin > 0.0) {
		for (int i = 0; i < 3; ++i) {
			const real_t margin = world_margin * inverse_basis[i].length();
			r_local_aabb.position[i] -= margin;
			r_local_aabb.size[i] += 2.0 * margin;
		}
	}
	return true;
}
