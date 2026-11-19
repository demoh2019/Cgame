/**************************************************************************/
/*  physics_fluid_ellipsoid_3d.h                                          */
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

#include "servers/physics_fluid_buoyancy_3d.h"

// Exact hydrostatic volume and buoyancy centroid for any non-degenerate
// affine image of a sphere (ellipsoid), even with nonuniform scale, rotation,
// reflection or shear. Supports the existing horizontal fluid plane.
//
// In local unit-ball coordinates u, world position = origin + radius*B*u.
// The vertical coordinate is origin.y + radius*(B^T*Y).dot(u).
// A plane cutting a unit ball produces a spherical cap of known volume and
// centroid. Transforming the cap centroid by B gives the ellipsoid centroid:
//   effective_vertical_radius = radius * |B^T*Y|
//   fractional_volume = t^2 * (3-t) / 4, t = clamp(1 + waterline/H, 0, 2)
//   delta_y = -3*H*(2-t)^2 / (4*(3-t))
//   delta_world = (B*B^T*Y) / |B^T*Y|^2 * delta_y
//
// Jacobian |det(B)| gives exact world volume. Relative centroids and all
// determinant products are accumulated in double precision. No allocation,
// numerical integration, trigonometry, or persistent state. Invalid input
// returns false with zeroed output; fully dry ellipsoids return true with
// volume zero, fully submerged ellipsoids return the world center.
_FORCE_INLINE_ bool godot_physics_fluid_affine_ellipsoid_sample_3d(
		const Transform3D &p_world_transform, real_t p_local_radius,
		real_t p_surface_y, GodotPhysicsFluidSample3D &r_sample,
		real_t &r_total_volume) {
	r_sample = GodotPhysicsFluidSample3D();
	r_total_volume = 0.0;
	if (!(p_local_radius > 0.0) || !Math::is_finite(p_local_radius) ||
			!Math::is_finite(p_surface_y) ||
			!p_world_transform.origin.is_finite() ||
			!p_world_transform.basis.is_finite()) {
		return false;
	}
	const Vector3 col_x = p_world_transform.basis.get_column(0);
	const Vector3 col_y = p_world_transform.basis.get_column(1);
	const Vector3 col_z = p_world_transform.basis.get_column(2);
	const double gx = double(col_x.y);
	const double gy = double(col_y.y);
	const double gz = double(col_z.y);
	const double vertical_squared = gx * gx + gy * gy + gz * gz;

	const double ax = double(col_x.x), ay = double(col_x.y), az = double(col_x.z);
	const double bx = double(col_y.x), by = double(col_y.y), bz = double(col_y.z);
	const double cx = double(col_z.x), cy = double(col_z.y), cz = double(col_z.z);
	const double determinant = ax * (by * cz - bz * cy) +
			bx * (cy * az - cz * ay) + cx * (ay * bz - az * by);
	const double radius = double(p_local_radius);
	const double total_volume = (4.0 / 3.0) * double(Math_PI) *
			radius * radius * radius * Math::abs(determinant);
	const double height = radius * Math::sqrt(vertical_squared);
	if (!(vertical_squared > 0.0) || !(height > 0.0) ||
			!(total_volume > 0.0) ||
			!Math::is_finite(vertical_squared) || !Math::is_finite(height) ||
			!Math::is_finite(total_volume)) {
		return false;
	}
	const real_t bounded_volume = real_t(total_volume);
	if (!(bounded_volume > 0.0) || !Math::is_finite(bounded_volume)) {
		return false;
	}
	const double signed_waterline = double(p_surface_y) - double(p_world_transform.origin.y);
	const double t = CLAMP(1.0 + signed_waterline / height, 0.0, 2.0);
	r_total_volume = bounded_volume;
	if (t <= 0.0) {
		return true;
	}
	if (t >= 2.0) {
		r_sample.submerged_volume = bounded_volume;
		r_sample.submerged_fraction = 1.0;
		r_sample.center_of_buoyancy = p_world_transform.origin;
		return true;
	}

	// Double precision avoids catastrophic cancellation for small caps
	// on large or highly stretched ellipsoids.
	const double fraction = t * t * (3.0 - t) * 0.25;
	const double delta_y = -0.75 * height * (2.0 - t) *
			(2.0 - t) / (3.0 - t);
	// B*B^T*Y is the cross-axis response of the affine sphere to the
	// vertical plane. Its x/z components are not generally zero.
	const double response_x = (gx * ax + gy * bx + gz * cx) / vertical_squared;
	const double response_y = (gx * ay + gy * by + gz * cy) / vertical_squared;
	const double response_z = (gx * az + gy * bz + gz * cz) / vertical_squared;
	const Vector3 center(
			real_t(double(p_world_transform.origin.x) + response_x * delta_y),
			real_t(double(p_world_transform.origin.y) + response_y * delta_y),
			real_t(double(p_world_transform.origin.z) + response_z * delta_y));
	const real_t submerged_volume = real_t(total_volume * fraction);
	const real_t submerged_fraction = real_t(fraction);
	if (!Math::is_finite(submerged_volume) ||
			!Math::is_finite(submerged_fraction) || !center.is_finite()) {
		r_sample = GodotPhysicsFluidSample3D();
		r_total_volume = 0.0;
		return false;
	}
	r_sample.submerged_fraction = submerged_fraction;
	r_sample.submerged_volume = submerged_volume;
	r_sample.center_of_buoyancy = center;
	return true;
}
