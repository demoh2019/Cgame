/**************************************************************************/
/*  godot_contact_normal_3d.h                                             */
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
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"

// The 3D collision callback normally supplies points ordered A, B and a
// normal pointing from A to B. Contact constraints store the reverse normal.
// At exact tangency the two support points can coincide: normalizing their
// difference yields zero and may produce an unusable contact constraint.
// Use the narrowphase normal only for that degenerate case, retaining the
// historical point-derived normal for every nondegenerate contact.
_FORCE_INLINE_ static Vector3 godot_physics_3d_contact_normal(const Vector3 &p_point_a, const Vector3 &p_point_b, const Vector3 &p_narrowphase_normal) {
	const Vector3 separation = p_point_a - p_point_b;
	const real_t separation_squared = separation.length_squared();
	const real_t min_squared = real_t(CMP_EPSILON) * real_t(CMP_EPSILON);
	if (separation_squared > min_squared) {
		return separation / Math::sqrt(separation_squared);
	}
	const real_t normal_squared = p_narrowphase_normal.length_squared();
	if (normal_squared > min_squared) {
		return -p_narrowphase_normal / Math::sqrt(normal_squared);
	}
	// A fully degenerate manifold still needs a deterministic, unit normal.
	return Vector3(0.0, 1.0, 0.0);
}

// Rigid/soft contacts conventionally use the narrowphase normal rather than
// the separation direction. Preserve that convention, but reject degenerate
// or non-unit normals before using them in effective-mass calculations.
_FORCE_INLINE_ static Vector3 godot_physics_3d_soft_contact_normal(const Vector3 &p_point_a, const Vector3 &p_point_b, const Vector3 &p_narrowphase_normal) {
	const real_t min_squared = real_t(CMP_EPSILON) * real_t(CMP_EPSILON);
	const real_t normal_squared = p_narrowphase_normal.length_squared();
	if (p_narrowphase_normal.is_finite() && normal_squared > min_squared) {
		const Vector3 separation = p_point_a - p_point_b;
		const Vector3 oriented = p_narrowphase_normal.dot(separation) < 0.0 ? -p_narrowphase_normal : p_narrowphase_normal;
		// Narrowphase normally supplies unit normals. Avoid sqrt in the
		// common case, normalize only badly scaled inputs.
		if (Math::abs(normal_squared - real_t(1.0)) <= real_t(CMP_EPSILON)) {
			return oriented;
		}
		return oriented / Math::sqrt(normal_squared);
	}
	// If the normal is degenerate, derive an axis from the contact points.
	// This is intentionally unit length, even at exact tangency.
	const Vector3 separation = p_point_a - p_point_b;
	const real_t separation_squared = separation.length_squared();
	if (separation.is_finite() && separation_squared > min_squared) {
		return separation / Math::sqrt(separation_squared);
	}
	return Vector3(0.0, 1.0, 0.0);
}
