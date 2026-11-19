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
#include "core/math/transform_2d.h"
#include "core/math/transform_3d.h"
#include "core/math/vector2.h"
#include "core/math/vector3.h"


// An affine transform preserves a circle/sphere only when its basis is
 // orthogonal with equal axis lengths. Return zero for ellipses/ellipsoids:
 // they must continue through the general support-ray CCD path.
_FORCE_INLINE_ double physics_ccd_uniform_sphere_scale(const Transform2D &p_transform) {
	const Vector2 &x = p_transform.columns[0];
	const Vector2 &y = p_transform.columns[1];
	const double sx = Math::sqrt(double(x.x) * x.x + double(x.y) * x.y);
	const double sy = Math::sqrt(double(y.x) * y.x + double(y.y) * y.y);
	if (!(sx > 0.0 && sy > 0.0) || !Math::is_equal_approx(sx, sy)) {
		return 0.0;
	}
	if (Math::abs(double(x.x) * y.x + double(x.y) * y.y) > double(CMP_EPSILON) * sx * sy) {
		return 0.0;
	}
	return sx;
}

_FORCE_INLINE_ double physics_ccd_uniform_sphere_scale(const Transform3D &p_transform) {
	const Vector3 x = p_transform.basis.get_column(0);
	const Vector3 y = p_transform.basis.get_column(1);
	const Vector3 z = p_transform.basis.get_column(2);
	const double sx = Math::sqrt(double(x.x) * x.x + double(x.y) * x.y + double(x.z) * x.z);
	const double sy = Math::sqrt(double(y.x) * y.x + double(y.y) * y.y + double(y.z) * y.z);
	const double sz = Math::sqrt(double(z.x) * z.x + double(z.y) * z.y + double(z.z) * z.z);
	if (!(sx > 0.0 && sy > 0.0 && sz > 0.0) ||
			!Math::is_equal_approx(sx, sy) || !Math::is_equal_approx(sx, sz)) {
		return 0.0;
	}
	const double tol = double(CMP_EPSILON) * sx * sx;
	if (Math::abs(double(x.x) * y.x + double(x.y) * y.y + double(x.z) * y.z) > tol ||
			Math::abs(double(x.x) * z.x + double(x.y) * z.y + double(x.z) * z.z) > tol ||
			Math::abs(double(y.x) * z.x + double(y.y) * z.y + double(y.z) * z.z) > tol) {
		return 0.0;
	}
	return sx;
}

// First linear time of impact of two spheres with combined radius p_radius.
// Positions are relative (center A minus center B), and motion is the
// displacement of A relative to B during one step. The fraction lies in [0,1].
// This avoids the support-ray false negatives of a glancing sphere/sphere hit.
//
// Compute the closest point on the relative trajectory, then step back
// sqrt(radius^2 - closest_distance^2) along its direction. Avoid the usual
// quadratic discriminant: even in double, subtracting squared coordinates
// of order 1e16 can erase a unit-radius hit. Double intermediates keep
// finite float32 sweeps from overflowing their squared lengths.
_FORCE_INLINE_ bool physics_ccd_sphere_toi(double p_x, double p_y, double p_z,
		double p_dx, double p_dy, double p_dz, double p_radius, double &r_fraction) {
	if (!(p_radius > 0.0)) {
		return false;
	}
	const double radius_squared = p_radius * p_radius;
	const double a = p_dx * p_dx + p_dy * p_dy + p_dz * p_dz;
	const double initial_distance_squared = p_x * p_x + p_y * p_y + p_z * p_z;
	const double b = p_x * p_dx + p_y * p_dy + p_z * p_dz;
	if (!(a > 0.0 && initial_distance_squared > radius_squared && b < 0.0)) {
		return false; // Stationary, initially touching/overlapping, or receding.
	}

	const double closest_fraction = -b / a;
	const double closest_x = p_x + p_dx * closest_fraction;
	const double closest_y = p_y + p_dy * closest_fraction;
	const double closest_z = p_z + p_dz * closest_fraction;
	const double gap_squared = radius_squared -
			(closest_x * closest_x + closest_y * closest_y + closest_z * closest_z);
	if (!(gap_squared >= 0.0)) {
		return false;
	}

	const double fraction = closest_fraction - Math::sqrt(gap_squared / a);
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
