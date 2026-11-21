/**************************************************************************/
/*  pcg_path_falloff_3d.cpp                                                 */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_path_falloff_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void PCGPathFalloff3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sample_factors", "positions", "path_points", "inner_radius", "outer_radius"),
			&PCGPathFalloff3D::sample_factors);
}

PackedFloat32Array PCGPathFalloff3D::sample_factors(
		const PackedVector3Array &p_positions, const PackedVector3Array &p_path_points,
		double p_inner_radius, double p_outer_radius) const {
	PackedFloat32Array result;
	if (p_positions.size() > MAX_CANDIDATES || p_path_points.is_empty() ||
			p_path_points.size() > MAX_PATH_POINTS ||
			!Math::is_finite(p_inner_radius) || !Math::is_finite(p_outer_radius) ||
			p_inner_radius < 0.0 || p_outer_radius < p_inner_radius ||
			p_outer_radius > MAX_RADIUS) {
		return result;
	}

	// Check *every* point before producing an output. Even the Y coordinate
	// must be finite, although the falloff is computed horizontally in XZ.
	for (const Vector3 &point : p_positions) {
		if (!point.is_finite() || Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				Math::abs(double(point.z)) > MAX_COORDINATE) {
			return PackedFloat32Array();
		}
	}
	for (const Vector3 &point : p_path_points) {
		if (!point.is_finite() || Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				Math::abs(double(point.z)) > MAX_COORDINATE) {
			return PackedFloat32Array();
		}
	}

	result.resize(p_positions.size());
	const double inner_squared = p_inner_radius * p_inner_radius;
	const double outer_squared = p_outer_radius * p_outer_radius;
	for (int i = 0; i < p_positions.size(); ++i) {
		const Vector3 point = p_positions[i];
		double nearest_squared = 1.0e30;
		const int segments = MAX(1, p_path_points.size() - 1);
		for (int segment = 0; segment < segments; ++segment) {
			const Vector3 from = p_path_points[segment];
			const Vector3 to = p_path_points[MIN(segment + 1, p_path_points.size() - 1)];
			const double dx = double(to.x) - double(from.x);
			const double dz = double(to.z) - double(from.z);
			const double length_squared = dx * dx + dz * dz;
			double along = 0.0;
			if (length_squared > 0.0) {
				along = ((double(point.x) - double(from.x)) * dx +
						(double(point.z) - double(from.z)) * dz) / length_squared;
				along = MAX(0.0, MIN(1.0, along));
			}
			const double offset_x = double(point.x) - (double(from.x) + along * dx);
			const double offset_z = double(point.z) - (double(from.z) + along * dz);
			nearest_squared = MIN(nearest_squared, offset_x * offset_x + offset_z * offset_z);
		}

		// A hard cut is valid when inner and outer radii coincide. Boundaries
		// are inclusive: no density inside/on the inner radius, full outside
		// the outer radius. Smoothstep has zero derivative at both borders.
		if (nearest_squared <= inner_squared) {
			result.set(i, 0.0f);
		} else if (nearest_squared >= outer_squared) {
			result.set(i, 1.0f);
		} else {
			const double t = (Math::sqrt(nearest_squared) - p_inner_radius) /
					(p_outer_radius - p_inner_radius);
			result.set(i, float(t * t * (3.0 - 2.0 * t)));
		}
	}
	return result;
}
