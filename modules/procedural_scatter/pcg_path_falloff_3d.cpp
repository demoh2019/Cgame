/**************************************************************************/
/*  pcg_path_falloff_3d.cpp                                                 */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_path_falloff_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/vector.h"

void PCGPathFalloff3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sample_factors", "positions", "path_points", "inner_radius", "outer_radius"),
			&PCGPathFalloff3D::sample_factors);
	ClassDB::bind_method(D_METHOD("filter_indices_outside_segments", "candidates", "segment_endpoints", "clearance", "max_selected"),
			&PCGPathFalloff3D::filter_indices_outside_segments, DEFVAL(MAX_CANDIDATES));
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


PackedInt32Array PCGPathFalloff3D::filter_indices_outside_segments(
		const PackedVector3Array &p_candidates, const PackedVector3Array &p_segment_endpoints,
		double p_clearance, int p_max_selected) const {
	PackedInt32Array result;
	const int candidate_count = p_candidates.size();
	const int endpoint_count = p_segment_endpoints.size();
	if (candidate_count > MAX_CANDIDATES || (endpoint_count % 2) != 0 ||
			(endpoint_count / 2) > MAX_CORRIDOR_SEGMENTS ||
			p_max_selected < 0 || p_max_selected > MAX_CANDIDATES ||
			!Math::is_finite(p_clearance) || p_clearance < 0.0 ||
			p_clearance > MAX_RADIUS) {
		return result;
	}
	// Validate every point, including later-excluded candidates, before any
	// result allocation. Roads use horizontal XZ distance but Y must be finite.
	for (const Vector3 &p : p_candidates) {
		if (!p.is_finite() || Math::abs(double(p.x)) > MAX_COORDINATE ||
				Math::abs(double(p.y)) > MAX_COORDINATE ||
				Math::abs(double(p.z)) > MAX_COORDINATE) {
			return PackedInt32Array();
		}
	}
	for (const Vector3 &p : p_segment_endpoints) {
		if (!p.is_finite() || Math::abs(double(p.x)) > MAX_COORDINATE ||
				Math::abs(double(p.y)) > MAX_COORDINATE ||
				Math::abs(double(p.z)) > MAX_COORDINATE) {
			return PackedInt32Array();
		}
	}
	if (p_max_selected == 0 || candidate_count == 0) {
		return result;
	}

	// Cache segment geometry once, not for every scattered plant. Expanded
	// XZ rectangles cheaply reject most segment/point pairs before projection.
	struct Segment {
		double ax, az, dx, dz, length_squared, min_x, max_x, min_z, max_z;
	};
	Vector<Segment> segments;
	const int segment_count = endpoint_count / 2;
	segments.resize(segment_count);
	for (int j = 0; j < segment_count; ++j) {
		const Vector3 a = p_segment_endpoints[2 * j];
		const Vector3 b = p_segment_endpoints[2 * j + 1];
		Segment seg;
		seg.ax = double(a.x);
		seg.az = double(a.z);
		seg.dx = double(b.x) - seg.ax;
		seg.dz = double(b.z) - seg.az;
		seg.length_squared = seg.dx * seg.dx + seg.dz * seg.dz;
		seg.min_x = MIN(double(a.x), double(b.x)) - p_clearance;
		seg.max_x = MAX(double(a.x), double(b.x)) + p_clearance;
		seg.min_z = MIN(double(a.z), double(b.z)) - p_clearance;
		seg.max_z = MAX(double(a.z), double(b.z)) + p_clearance;
		segments.write[j] = seg;
	}
	const double threshold_squared = p_clearance * p_clearance;
	for (int i = 0; i < candidate_count && result.size() < p_max_selected; ++i) {
		const Vector3 point = p_candidates[i];
		const double x = double(point.x);
		const double z = double(point.z);
		bool blocked = false;
		for (const Segment &seg : segments) {
			if (x < seg.min_x || x > seg.max_x || z < seg.min_z || z > seg.max_z) {
				continue;
			}
			const double along = Math::clamp(((x - seg.ax) * seg.dx + (z - seg.az) * seg.dz) /
					MAX(seg.length_squared, 0.0001), 0.0, 1.0);
			const double ox = x - (seg.ax + along * seg.dx);
			const double oz = z - (seg.az + along * seg.dz);
			// Legacy Albion _on_road uses < radius: points exactly on the
			// clearance boundary remain eligible. Zero radius rejects none.
			if (ox * ox + oz * oz < threshold_squared) {
				blocked = true;
				break;
			}
		}
		if (!blocked) {
			result.push_back(i);
		}
	}
	return result;
}
