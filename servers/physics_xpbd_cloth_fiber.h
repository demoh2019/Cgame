/**************************************************************************/
/*  physics_xpbd_cloth_fiber.h                                             */
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

#include <limits>

// Direction-dependent XPBD distance compliance for orthotropic cloth.
//
// The unit fiber axis is defined in the mesh's REST coordinate system.
// C(e) = C_perpendicular + (C_parallel - C_perpendicular) * cos²(theta)
// where cos(theta) is the angle between a REST structural edge and the
// fiber axis. This preserves behavior under world-space rotation and
// reversal of edge/fiber orientation. The input alpha is the
// time-step-scaled compliance, not a stiffness coefficient.
//
// This helper does not modify r_alpha on failure. A degenerate edge or
// invalid material input should keep the ordinary isotropic constraint.
// C++ double intermediate products avoid float overflow for large ratios.
_FORCE_INLINE_ bool physics_xpbd_cloth_fiber_alpha(
		const Vector3 &p_rest_a, const Vector3 &p_rest_b,
		const Vector3 &p_unit_fiber_axis, real_t p_parallel_compliance_ratio,
		real_t p_isotropic_alpha, real_t &r_alpha) {
	if (!p_rest_a.is_finite() || !p_rest_b.is_finite() ||
			!p_unit_fiber_axis.is_finite() ||
			!Math::is_finite(p_parallel_compliance_ratio) ||
			p_parallel_compliance_ratio < 0.0 ||
			!Math::is_finite(p_isotropic_alpha) || p_isotropic_alpha < 0.0) {
		return false;
	}
	const double dx = double(p_rest_b.x) - double(p_rest_a.x);
	const double dy = double(p_rest_b.y) - double(p_rest_a.y);
	const double dz = double(p_rest_b.z) - double(p_rest_a.z);
	const double len2 = dx * dx + dy * dy + dz * dz;
	const double ax = double(p_unit_fiber_axis.x);
	const double ay = double(p_unit_fiber_axis.y);
	const double az = double(p_unit_fiber_axis.z);
	const double axis2 = ax * ax + ay * ay + az * az;
	if (!(len2 > 0.0) || !(axis2 > 0.0) ||
			!Math::is_finite(len2) || !Math::is_finite(axis2)) {
		return false;
	}
	const double dot = dx * ax + dy * ay + dz * az;
	const double cos2 = CLAMP((dot * dot) / (len2 * axis2), 0.0, 1.0);
	if (!Math::is_finite(cos2)) {
		return false;
	}
	const double multiplier = 1.0 +
			(double(p_parallel_compliance_ratio) - 1.0) * cos2;
	if (!Math::is_finite(multiplier) || multiplier < 0.0) {
		return false;
	}
	// Guard BEFORE multiplication: in a real_t=double build, multiplying
	// DBL_MAX by a softening ratio must saturate instead of overflowing.
	const double max_alpha = double(std::numeric_limits<real_t>::max());
	const double isotropic = double(p_isotropic_alpha);
	const double alpha = multiplier > 1.0 && isotropic > max_alpha / multiplier ?
			max_alpha : isotropic * multiplier;
	if (!Math::is_finite(alpha) || alpha < 0.0) {
		return false;
	}
	const real_t value = real_t(MIN(alpha, max_alpha));
	if (!Math::is_finite(value)) {
		return false;
	}
	r_alpha = value;
	return true;
}
