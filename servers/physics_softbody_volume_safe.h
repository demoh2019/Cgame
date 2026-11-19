/**************************************************************************/
/*  physics_softbody_volume_safe.h                                        */
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

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// A tiny closed mesh should not be rejected by a fixed world-unit volume
// epsilon. Use a dimensionless test against the cube of its characteristic
// extent, preserving the same behavior under uniform rescaling.
// Reject nonfinite, nearly flat, and unrepresentable geometries.
_FORCE_INLINE_ static bool physics_softbody_volume_is_non_degenerate(double p_signed_volume, double p_axis_extent) {
	if (!(p_axis_extent > 0.0) || !Math::is_finite(p_axis_extent) ||
			!Math::is_finite(p_signed_volume)) {
		return false;
	}
	const double extent_cubed = p_axis_extent * p_axis_extent * p_axis_extent;
	if (!(extent_cubed > 0.0) || !Math::is_finite(extent_cubed)) {
		return false;
	}
	return Math::abs(p_signed_volume / extent_cubed) > 1e-10;
}

// Face gradients of signed enclosed volume with a common origin:
//   dV/da = cross(b-origin, c-origin)/6 (cyclic for b and c).
// Subtract and cross in double before converting to Vector3: subtracting
// two finite float32 world positions can overflow before their resulting
// volume gradient is formed. On any failure, leave outputs unchanged.
_FORCE_INLINE_ static bool physics_softbody_volume_face_gradients(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		const Vector3 &p_origin,
		Vector3 &r_grad_a, Vector3 &r_grad_b, Vector3 &r_grad_c) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() || !p_origin.is_finite()) {
		return false;
	}
	const double ax = double(p_a.x) - double(p_origin.x);
	const double ay = double(p_a.y) - double(p_origin.y);
	const double az = double(p_a.z) - double(p_origin.z);
	const double bx = double(p_b.x) - double(p_origin.x);
	const double by = double(p_b.y) - double(p_origin.y);
	const double bz = double(p_b.z) - double(p_origin.z);
	const double cx = double(p_c.x) - double(p_origin.x);
	const double cy = double(p_c.y) - double(p_origin.y);
	const double cz = double(p_c.z) - double(p_origin.z);
	const double sixth = 1.0 / 6.0;

	const Vector3 ga(real_t((by * cz - bz * cy) * sixth),
			real_t((bz * cx - bx * cz) * sixth),
			real_t((bx * cy - by * cx) * sixth));
	const Vector3 gb(real_t((cy * az - cz * ay) * sixth),
			real_t((cz * ax - cx * az) * sixth),
			real_t((cx * ay - cy * ax) * sixth));
	const Vector3 gc(real_t((ay * bz - az * by) * sixth),
			real_t((az * bx - ax * bz) * sixth),
			real_t((ax * by - ay * bx) * sixth));
	if (!ga.is_finite() || !gb.is_finite() || !gc.is_finite()) {
		return false;
	}
	r_grad_a = ga;
	r_grad_b = gb;
	r_grad_c = gc;
	return true;
}
