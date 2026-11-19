/**************************************************************************/
/*  godot_contact_normal_2d.h                                             */
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
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector2.h"

// Preserve point-derived normals for penetrating contacts. At exact tangency,
// both contact points can coincide, yielding a zero vector with normalized().
// Use the body-center direction as a fallback without allocating or changing
// nondegenerate contact behavior; fully coincident centers get a fixed axis.
_FORCE_INLINE_ static Vector2 godot_physics_2d_contact_normal(const Vector2 &p_point_a, const Vector2 &p_point_b, const Vector2 &p_center_direction) {
	const real_t min_squared = real_t(CMP_EPSILON) * real_t(CMP_EPSILON);
	const Vector2 separation = p_point_a - p_point_b;
	const real_t separation_squared = separation.length_squared();
	if (separation_squared > min_squared) {
		return separation / Math::sqrt(separation_squared);
	}
	const real_t center_squared = p_center_direction.length_squared();
	if (center_squared > min_squared) {
		return p_center_direction / Math::sqrt(center_squared);
	}
	return Vector2(0.0, 1.0);
}
