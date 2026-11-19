/**************************************************************************/
/*  physics_ccd_sphere_toi.h                                              */
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

#include "core/math/math_funcs.h"
#include "core/math/vector2.h"
#include "core/math/vector3.h"

// First linear time of impact of two spheres with combined radius p_radius.
// Positions are relative (center A minus center B), and motion is the
// displacement of A relative to B during one step. The fraction lies in [0,1].
// This avoids the support-ray false negatives of a glancing sphere/sphere hit.
//
// Use the stable root c / (-b + sqrt(b*b - a*c)) of
// a*t*t + 2*b*t + c = 0, with a=motion^2 and c=distance^2-radius^2.
// The direct quadratic root loses precision for distant starting positions.
// All intermediates are double so a finite float32 sweep does not overflow.
_FORCE_INLINE_ bool physics_ccd_sphere_toi(double p_x, double p_y, double p_z,
		double p_dx, double p_dy, double p_dz, double p_radius, double &r_fraction) {
	if (!(p_radius > 0.0)) {
		return false;
	}
	const double radius_squared = p_radius * p_radius;
	const double a = p_dx * p_dx + p_dy * p_dy + p_dz * p_dz;
	const double c = p_x * p_x + p_y * p_y + p_z * p_z - radius_squared;
	const double b = p_x * p_dx + p_y * p_dy + p_z * p_dz;
	if (!(a > 0.0 && c > 0.0 && b < 0.0)) {
		return false; // Stationary, initially touching/overlapping, or receding.
	}
	const double discriminant = b * b - a * c;
	if (!(discriminant >= 0.0)) {
		return false;
	}
	const double denominator = -b + Math::sqrt(discriminant);
	if (!(denominator > 0.0)) {
		return false;
	}
	const double fraction = c / denominator;
	if (!(fraction >= 0.0 && fraction <= 1.0)) {
		return false;
	}
	r_fraction = fraction;
	return true;
}

_FORCE_INLINE_ bool physics_ccd_sphere_toi(const Vector2 &p_center_delta, const Vector2 &p_relative_motion, double p_radius, double &r_fraction) {
	return physics_ccd_sphere_toi(double(p_center_delta.x), double(p_center_delta.y), 0.0,
			double(p_relative_motion.x), double(p_relative_motion.y), 0.0, p_radius, r_fraction);
}

_FORCE_INLINE_ bool physics_ccd_sphere_toi(const Vector3 &p_center_delta, const Vector3 &p_relative_motion, double p_radius, double &r_fraction) {
	return physics_ccd_sphere_toi(double(p_center_delta.x), double(p_center_delta.y), double(p_center_delta.z),
			double(p_relative_motion.x), double(p_relative_motion.y), double(p_relative_motion.z), p_radius, r_fraction);
}
