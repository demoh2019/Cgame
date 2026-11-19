/**************************************************************************/
/*  godot_contact_warmstart_3d.h                                          */
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

#include "core/math/vector3.h"

// A contact's anchors may still match after the surface normal turns at an
// edge or deforms. Reusing impulses in that case can kick objects sideways.
// Compare cosine squared without a square root; this also tolerates an
// unnormalized normal from a soft-body collision callback.
_FORCE_INLINE_ static bool godot_physics_3d_can_reuse_contact_impulses(const Vector3 &p_previous_normal, const Vector3 &p_new_normal) {
	const real_t previous_length_squared = p_previous_normal.length_squared();
	const real_t new_length_squared = p_new_normal.length_squared();
	if (previous_length_squared <= CMP_EPSILON2 || new_length_squared <= CMP_EPSILON2) {
		return false;
	}

	const real_t alignment = p_previous_normal.dot(p_new_normal);
	return alignment > 0.0 &&
			alignment * alignment >= real_t(0.98 * 0.98) * previous_length_squared * new_length_squared;
}

// The old tangential impulse need not be tangent to the new contact normal.
// Orthogonal projection preserves the useful friction warm start while
// removing its normal component, without needing a unit-length normal.
_FORCE_INLINE_ static Vector3 godot_physics_3d_reproject_contact_friction(const Vector3 &p_previous_impulse, const Vector3 &p_new_normal) {
	const real_t normal_length_squared = p_new_normal.length_squared();
	if (normal_length_squared <= CMP_EPSILON2) {
		return Vector3();
	}
	return p_previous_impulse - p_new_normal * (p_previous_impulse.dot(p_new_normal) / normal_length_squared);
}
