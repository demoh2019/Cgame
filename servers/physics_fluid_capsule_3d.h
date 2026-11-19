/**************************************************************************/
/*  physics_fluid_capsule_3d.h                                            */
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
/* limitation the rights to use, copy, modify, merge, publish, distribute,*/
/* sublicense, and/or sell copies of the Software, and to permit persons  */
/* to whom the Software is furnished to do so, subject to the following   */
/* conditions:                                                            */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#pragma once

#include "servers/physics_fluid_buoyancy_3d.h"

// Circular cross-section of a tilted capsule. All coordinates below are
// normalized by capsule radius: p_radius is its disk radius in these units.
// The horizontal fluid plane cuts a circle along the projection of world Y
// onto its cross-section. Return area and first transverse moment, in
// radius^2 and radius^3 units respectively.
_FORCE_INLINE_ bool godot_physics_fluid_capsule_disk_slice_3d(
		double p_radius, double p_vertical_offset, double p_transverse_y,
		double &r_area, double &r_transverse_moment) {
	r_area = 0.0;
	r_transverse_moment = 0.0;
	if (!(p_radius >= 0.0) || !Math::is_finite(p_radius) ||
			!Math::is_finite(p_vertical_offset) || !(p_transverse_y > 0.0)) {
		return false;
	}
	if (!(p_radius > 0.0) || p_vertical_offset <= -p_transverse_y * p_radius) {
		return true;
	}
	if (p_vertical_offset >= p_transverse_y * p_radius) {
		r_area = Math::PI * p_radius * p_radius;
		return true;
	}
	const double u = CLAMP(p_vertical_offset / (p_transverse_y * p_radius), -1.0, 1.0);
	const double root = Math::sqrt(MAX(0.0, 1.0 - u * u));
	r_area = p_radius * p_radius * (Math::acos(-u) + u * root);
	// Integral of transverse coordinate over the submerged circular
	// segment: -2/3 * (R^2 - h^2)^(3/2).
	r_transverse_moment = -2.0 / 3.0 * p_radius * p_radius * p_radius *
			root * root * root;
	return Math::is_finite(r_area) && Math::is_finite(r_transverse_moment);
}

// Integrate a part of the capsule along its local axis with a fixed,
// allocation-free 8-point Gauss-Legendre rule and bounded subintervals.
// The sections of the hemispherical caps and cylinder are integrated
// separately, so the radius discontinuity in the second derivative cannot
// bias samples across their join.
_FORCE_INLINE_ bool godot_physics_fluid_capsule_integrate_interval_3d(
		double p_start, double p_end, double p_half_cylinder,
		double p_plane_offset, double p_axis_y, double p_transverse_y,
		double &r_volume, double &r_axial_moment, double &r_transverse_moment) {
	if (!(p_end > p_start)) {
		return true;
	}
	static constexpr double nodes[4] = {
		0.183434642495649805, 0.525532409916328986,
		0.796666477413626740, 0.960289856497536232
	};
	static constexpr double weights[4] = {
		0.362683783378361983, 0.313706645877887287,
		0.222381034453374471, 0.101228536290376259
	};
	constexpr int panels = 16;
	for (int j = 0; j < panels; ++j) {
		const double start = p_start + (p_end - p_start) * double(j) / double(panels);
		const double end = p_start + (p_end - p_start) * double(j + 1) / double(panels);
		const double middle = (start + end) * 0.5;
		const double half_width = (end - start) * 0.5;
		for (int k = 0; k < 4; ++k) {
			for (int side = -1; side <= 1; side += 2) {
				const double axial = middle + double(side) * half_width * nodes[k];
				const double cap_distance = MAX(0.0, Math::abs(axial) - p_half_cylinder);
				const double disk_radius = Math::sqrt(MAX(0.0, 1.0 - cap_distance * cap_distance));
				double area = 0.0, moment = 0.0;
				if (!godot_physics_fluid_capsule_disk_slice_3d(
							disk_radius, p_plane_offset - p_axis_y * axial,
							p_transverse_y, area, moment)) {
					return false;
				}
				const double differential = half_width * weights[k];
				r_volume += area * differential;
				r_axial_moment += axial * area * differential;
				r_transverse_moment += moment * differential;
			}
		}
	}
	return Math::is_finite(r_volume) && Math::is_finite(r_axial_moment) &&
			Math::is_finite(r_transverse_moment);
}

// Integrate the true submerged circular sections of a uniformly scaled
// capsule at ANY orientation. For a sphere (zero cylinder) or near-vertical
// capsule, use the existing exact analytic helpers. Otherwise integrate the
// two hemispherical ends, plus the cylinder clipped into dry, wet, and
// partially wet intervals. Complexity is fixed; no per-frame allocations.
//
// The local axial moment and transverse disk moment produce a full 3D
// hydrostatic centroid, so tilted floating bodies get the correct restoring
// torque rather than an AABB-height approximation. The incoming shape volume
// is retained for consistency with the existing rigid-body density model.
// Return false only for invalid geometry; dry but valid capsules return true.
_FORCE_INLINE_ bool godot_physics_fluid_tilted_capsule_sample_3d(
		const Vector3 &p_world_center, const Vector3 &p_world_axis,
		real_t p_world_radius, real_t p_world_height, real_t p_world_volume,
		real_t p_surface_y, GodotPhysicsFluidSample3D &r_sample) {
	r_sample = GodotPhysicsFluidSample3D();
	if (!(p_world_radius > 0.0) || !(p_world_height >= real_t(2.0) * p_world_radius) ||
			!(p_world_volume > 0.0) || !p_world_center.is_finite() ||
			!p_world_axis.is_finite() || !Math::is_finite(p_world_radius) ||
			!Math::is_finite(p_world_height) || !Math::is_finite(p_world_volume) ||
			!Math::is_finite(p_surface_y)) {
		return false;
	}
	const double radius = double(p_world_radius);
	const double length = double(p_world_height) - 2.0 * radius;
	const double cylinder = length / radius;
	const double axis_length_squared = double(p_world_axis.length_squared());
	if (!(axis_length_squared > 0.0) || !Math::is_finite(axis_length_squared) ||
			!Math::is_finite(cylinder) || cylinder < 0.0) {
		return false;
	}
	const Vector3 axis = p_world_axis / real_t(Math::sqrt(axis_length_squared));
	if (!axis.is_finite()) {
		return false;
	}
	const double ay = double(axis.y);
	const double transverse_y = Math::sqrt(MAX(0.0, 1.0 - ay * ay));
	if (length <= 0.0) {
		r_sample = godot_physics_fluid_sphere_sample_3d(
				p_world_center, p_world_radius, p_world_volume, p_surface_y);
		return true;
	}
	if (transverse_y < 1e-5) {
		r_sample = godot_physics_fluid_vertical_capsule_sample_3d(
				p_world_center, p_world_radius, p_world_height,
				p_world_volume, p_surface_y);
		return true;
	}
	const double height = double(p_surface_y) - double(p_world_center.y);
	const double reach = radius + Math::abs(ay) * length * 0.5;
	if (height <= -reach) {
		return true;
	}
	if (height >= reach) {
		r_sample.submerged_volume = p_world_volume;
		r_sample.submerged_fraction = 1.0;
		r_sample.center_of_buoyancy = p_world_center;
		return true;
	}
	const double offset = height / radius;
	const double half_cylinder = cylinder * 0.5;
	double wet_volume = 0.0;
	double axial_moment = 0.0;
	double transverse_moment = 0.0;

	// Hemisphere ends. Their cross sections are circular but shrink to
	// zero at the tips, so preserve their individual integration domains.
	if (!godot_physics_fluid_capsule_integrate_interval_3d(
				-half_cylinder - 1.0, -half_cylinder, half_cylinder,
				offset, ay, transverse_y,
				wet_volume, axial_moment, transverse_moment) ||
			!godot_physics_fluid_capsule_integrate_interval_3d(
				half_cylinder, half_cylinder + 1.0, half_cylinder,
				offset, ay, transverse_y,
				wet_volume, axial_moment, transverse_moment)) {
		return false;
	}

	// A long cylinder must not miss a narrow waterline transition simply
	// because its length/radius ratio is large. Split the interval at the
	// exact full-wet/dry disk thresholds before numerical integration.
	double cuts[4] = { -half_cylinder, half_cylinder, 0.0, 0.0 };
	int cut_count = 2;
	if (Math::abs(ay) > 1e-10) {
		const double first = (offset - transverse_y) / ay;
		const double second = (offset + transverse_y) / ay;
		if (first > -half_cylinder && first < half_cylinder) {
			cuts[cut_count++] = first;
		}
		if (second > -half_cylinder && second < half_cylinder) {
			cuts[cut_count++] = second;
		}
	}
	for (int i = 1; i < cut_count; ++i) {
		const double key = cuts[i];
		int j = i;
		while (j > 0 && cuts[j - 1] > key) {
			cuts[j] = cuts[j - 1];
			--j;
		}
		cuts[j] = key;
	}
	for (int i = 0; i + 1 < cut_count; ++i) {
		const double start = cuts[i];
		const double end = cuts[i + 1];
		if (!(end > start)) {
			continue;
		}
		const double midpoint = (start + end) * 0.5;
		const double surface_offset = offset - ay * midpoint;
		if (surface_offset >= transverse_y) {
			wet_volume += Math::PI * (end - start);
			axial_moment += Math::PI * (end - start) * midpoint;
		} else if (surface_offset > -transverse_y) {
			if (Math::abs(ay) <= 1e-10) {
				// Exactly horizontal cylinder: one circular segment for
				// its entire length, integrated analytically.
				double area = 0.0, moment = 0.0;
				if (!godot_physics_fluid_capsule_disk_slice_3d(
							1.0, surface_offset, transverse_y, area, moment)) {
					return false;
				}
				wet_volume += area * (end - start);
				axial_moment += area * (end - start) * midpoint;
				transverse_moment += moment * (end - start);
			} else if (!godot_physics_fluid_capsule_integrate_interval_3d(
							   start, end, half_cylinder, offset, ay, transverse_y,
							   wet_volume, axial_moment, transverse_moment)) {
				return false;
			}
		}
	}
	const double full_volume = Math::PI * (cylinder + 4.0 / 3.0);
	if (!(full_volume > 0.0) || !Math::is_finite(full_volume) ||
			!Math::is_finite(wet_volume) || !Math::is_finite(axial_moment) ||
			!Math::is_finite(transverse_moment)) {
		return false;
	}
	const double fraction = CLAMP(wet_volume / full_volume, 0.0, 1.0);
	if (!(fraction > 0.0)) {
		return true;
	}
	const Vector3 projection = (Vector3(0, 1, 0) - axis * real_t(ay)) /
			real_t(transverse_y);
	if (!projection.is_finite()) {
		return false;
	}
	const double axial_distance = radius * (axial_moment / wet_volume);
	const double transverse_distance = radius * (transverse_moment / wet_volume);
	const Vector3 center(real_t(double(p_world_center.x) +
					double(axis.x) * axial_distance + double(projection.x) * transverse_distance),
			real_t(double(p_world_center.y) +
					double(axis.y) * axial_distance + double(projection.y) * transverse_distance),
			real_t(double(p_world_center.z) +
					double(axis.z) * axial_distance + double(projection.z) * transverse_distance));
	const real_t submerged_volume = real_t(double(p_world_volume) * fraction);
	if (!center.is_finite() || !Math::is_finite(submerged_volume) ||
			!(submerged_volume >= 0.0)) {
		return false;
	}
	r_sample.submerged_fraction = real_t(fraction);
	r_sample.submerged_volume = submerged_volume;
	r_sample.center_of_buoyancy = center;
	return true;
}
