/**************************************************************************/
/*  physics_fluid_cylinder_3d.h                                           */
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

// Exact hydrostatic displaced volume and 3D centroid for an arbitrarily
// oriented RIGHT CIRCULAR CYLINDER under a horizontal free surface.
// The owning rigid body supplies uniform world-space radius/height and
// a unit cylinder axis; nonuniform scale/shear is rejected by its caller.
//
// A disk at axial coordinate s has relative vertical coordinate
// a_y*s + beta*u, beta=sqrt(1-a_y^2), with -R <= u <= R.
// For -1<t<1, t=(waterline-a_y*s)/(beta*R), its submerged area and
// perpendicular first moment are:
//
//   A(t) = R^2 [acos(-t) + t*sqrt(1-t^2)]
//   M(t) = -(2/3) R^3 (1-t^2)^(3/2).
//
// Their ANTIDERIVATIVES as functions of t (for normalized R=1) give
// axial volume, axial first moment and transverse first moment exactly,
// with no per-body quadrature, mesh clipping or allocation. Cutting the
// axial interval at t=+1 and t=-1 keeps dry/full/partial regimes distinct.
struct GodotPhysicsCylinderDiskAntiderivatives3D {
	double area = 0.0;
	double axial_area = 0.0;
	double transverse_moment = 0.0;
};

_FORCE_INLINE_ GodotPhysicsCylinderDiskAntiderivatives3D godot_physics_fluid_cylinder_disk_antiderivatives_3d(double p_t) {
	const double t = CLAMP(p_t, -1.0, 1.0);
	const double q = Math::sqrt(MAX(0.0, 1.0 - t * t));
	const double asin_t = Math::asin(t);
	GodotPhysicsCylinderDiskAntiderivatives3D result;
	// Derivatives: area, t*area, and the wet-disk transverse moment.
	result.area = Math::PI * 0.5 * t + t * asin_t + q - q * q * q / 3.0;
	result.axial_area = Math::PI * 0.25 * t * t +
			(4.0 * t * t - 1.0) * asin_t / 8.0 +
			t * q * (1.0 + 2.0 * t * t) / 8.0;
	result.transverse_moment = -(3.0 * asin_t + t * q * (5.0 - 2.0 * t * t)) / 12.0;
	return result;
}

_FORCE_INLINE_ double godot_physics_fluid_cylinder_disk_area_3d(double p_t) {
	if (p_t <= -1.0) {
		return 0.0;
	}
	if (p_t >= 1.0) {
		return Math::PI;
	}
	const double root = Math::sqrt(MAX(0.0, 1.0 - p_t * p_t));
	return Math::acos(-p_t) + p_t * root;
}

_FORCE_INLINE_ double godot_physics_fluid_cylinder_disk_moment_3d(double p_t) {
	if (p_t <= -1.0 || p_t >= 1.0) {
		return 0.0;
	}
	const double remaining = MAX(0.0, 1.0 - p_t * p_t);
	return -(2.0 / 3.0) * remaining * Math::sqrt(remaining);
}

// Return false on invalid geometry, leaving both outputs zero. A valid dry
// cylinder returns true with zero immersed volume. The exact FULL volume is
// also returned for correcting the solver's angular-drag fraction (its
// cached shape area is an AABB estimate for some transformed primitives).
_FORCE_INLINE_ bool godot_physics_fluid_cylinder_sample_3d(
		const Vector3 &p_world_center, const Vector3 &p_world_axis,
		real_t p_world_radius, real_t p_world_height, real_t p_surface_y,
		GodotPhysicsFluidSample3D &r_sample, real_t &r_total_volume) {
	r_sample = GodotPhysicsFluidSample3D();
	r_total_volume = 0.0;
	if (!(p_world_radius > real_t(0.0)) || !(p_world_height > real_t(0.0)) ||
			!Math::is_finite(p_world_radius) || !Math::is_finite(p_world_height) ||
			!Math::is_finite(p_surface_y) || !p_world_center.is_finite() ||
			!p_world_axis.is_finite()) {
		return false;
	}
	const double axis_length_squared =
			double(p_world_axis.x) * double(p_world_axis.x) +
			double(p_world_axis.y) * double(p_world_axis.y) +
			double(p_world_axis.z) * double(p_world_axis.z);
	if (!(axis_length_squared > 0.0) || !Math::is_finite(axis_length_squared)) {
		return false;
	}
	const Vector3 axis = p_world_axis / real_t(Math::sqrt(axis_length_squared));
	if (!axis.is_finite()) {
		return false;
	}

	const double radius = double(p_world_radius);
	const double height = double(p_world_height);
	const double half_length = height / (2.0 * radius);
	const double volume = Math::PI * radius * radius * height;
	if (!(half_length > 0.0) || !Math::is_finite(half_length) ||
			!(volume > 0.0) || !Math::is_finite(volume)) {
		return false;
	}
	const real_t bounded_volume = real_t(volume);
	if (!(bounded_volume > real_t(0.0)) || !Math::is_finite(bounded_volume)) {
		return false;
	}

	const double ay = double(axis.y);
	const double beta = Math::sqrt(MAX(0.0, 1.0 - ay * ay));
	const double level = (double(p_surface_y) - double(p_world_center.y)) / radius;
	const double reach = Math::abs(ay) * half_length + beta;
	if (!Math::is_finite(level) || !Math::is_finite(reach)) {
		return false;
	}
	if (level <= -reach) {
		r_total_volume = bounded_volume;
		return true;
	}
	if (level >= reach) {
		r_total_volume = bounded_volume;
		r_sample.submerged_volume = bounded_volume;
		r_sample.submerged_fraction = 1.0;
		r_sample.center_of_buoyancy = p_world_center;
		return true;
	}

	// Integrals of normalized disk area and the first moments over axial
	// coordinate s/r. Restore physical radius only after taking their ratios.
	double wet_integral = 0.0;
	double axial_integral = 0.0;
	double transverse_integral = 0.0;
	if (beta <= 1e-8) {
		// Vertical cylinder: an exactly clipped axial slab.
		const double crossing = level / ay;
		const double begin = ay > 0.0 ? -half_length : MAX(-half_length, crossing);
		const double end = ay > 0.0 ? MIN(half_length, crossing) : half_length;
		if (end > begin) {
			wet_integral = Math::PI * (end - begin);
			axial_integral = Math::PI * (end - begin) * (begin + end) * 0.5;
		}
	} else if (Math::abs(ay) <= 1e-7) {
		// Horizontal cylinder: the submerged circular segment is constant
		// along its length, including its first transverse moment.
		const double t = level / beta;
		wet_integral = 2.0 * half_length * godot_physics_fluid_cylinder_disk_area_3d(t);
		transverse_integral = 2.0 * half_length * godot_physics_fluid_cylinder_disk_moment_3d(t);
	} else {
		// Split at all in-range full-disk and dry-disk transitions.
		// At most four boundaries and three intervals, on the stack.
		double cuts[4] = { -half_length, half_length, 0.0, 0.0 };
		int count = 2;
		const double t_full = (level - beta) / ay;
		const double t_dry = (level + beta) / ay;
		if (t_full > -half_length && t_full < half_length) {
			cuts[count++] = t_full;
		}
		if (t_dry > -half_length && t_dry < half_length) {
			cuts[count++] = t_dry;
		}
		for (int i = 1; i < count; ++i) {
			const double key = cuts[i];
			int j = i;
			while (j > 0 && cuts[j - 1] > key) {
				cuts[j] = cuts[j - 1];
				--j;
			}
			cuts[j] = key;
		}
		for (int i = 0; i + 1 < count; ++i) {
			const double begin = cuts[i];
			const double end = cuts[i + 1];
			if (!(end > begin)) {
				continue;
			}
			const double mid = (begin + end) * 0.5;
			const double t_mid = (level - ay * mid) / beta;
			if (t_mid >= 1.0) {
				wet_integral += Math::PI * (end - begin);
				axial_integral += Math::PI * (end - begin) * mid;
				continue;
			}
			if (t_mid <= -1.0) {
				continue;
			}
			const double t_begin = CLAMP((level - ay * begin) / beta, -1.0, 1.0);
			const double t_end = CLAMP((level - ay * end) / beta, -1.0, 1.0);
			const GodotPhysicsCylinderDiskAntiderivatives3D first =
					godot_physics_fluid_cylinder_disk_antiderivatives_3d(t_begin);
			const GodotPhysicsCylinderDiskAntiderivatives3D last =
					godot_physics_fluid_cylinder_disk_antiderivatives_3d(t_end);
			const double delta_area = last.area - first.area;
			const double factor = -beta / ay;
			wet_integral += factor * delta_area;
			axial_integral += (factor / ay) *
					(level * delta_area - beta * (last.axial_area - first.axial_area));
			transverse_integral += factor * (last.transverse_moment - first.transverse_moment);
		}
	}

	if (!Math::is_finite(wet_integral) || !Math::is_finite(axial_integral) ||
			!Math::is_finite(transverse_integral)) {
		return false;
	}
	// A near-tangent, underflow-scale wet cap may be lost to round-off;
	// never create negative displacement or an unbounded first moment.
	const double max_wet = Math::PI * 2.0 * half_length;
	if (!(wet_integral > 0.0)) {
		r_total_volume = bounded_volume;
		return true;
	}
	if (wet_integral > max_wet * (1.0 + 1e-8)) {
		return false;
	}
	const double fraction = CLAMP(wet_integral / max_wet, 0.0, 1.0);
	const double axial_offset = radius * axial_integral / wet_integral;
	const double transverse_offset = radius * transverse_integral / wet_integral;
	const Vector3 transverse_axis = beta > 0.0 ?
			(Vector3(0, 1, 0) - axis * real_t(ay)) / real_t(beta) : Vector3();
	const Vector3 center(
			real_t(double(p_world_center.x) + double(axis.x) * axial_offset + double(transverse_axis.x) * transverse_offset),
			real_t(double(p_world_center.y) + double(axis.y) * axial_offset + double(transverse_axis.y) * transverse_offset),
			real_t(double(p_world_center.z) + double(axis.z) * axial_offset + double(transverse_axis.z) * transverse_offset));
	const real_t displaced = real_t(volume * fraction);
	if (!center.is_finite() || !Math::is_finite(displaced) ||
			!Math::is_finite(real_t(fraction)) || !(displaced >= real_t(0.0))) {
		return false;
	}
	r_total_volume = bounded_volume;
	r_sample.submerged_volume = displaced;
	r_sample.submerged_fraction = real_t(fraction);
	r_sample.center_of_buoyancy = center;
	return true;
}
