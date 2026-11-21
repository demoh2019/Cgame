/**************************************************************************/
/*  pcg_polyline_sampler_3d.cpp                                             */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_polyline_sampler_3d.h"

#include "core/math/math_funcs.h"
#include "core/math/transform_3d.h"
#include "core/object/class_db.h"
#include "core/templates/vector.h"

void PCGPolylineSampler3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sample_positions", "path_points", "spacing", "max_samples", "fit_to_path"),
			&PCGPolylineSampler3D::sample_positions, DEFVAL(MAX_SAMPLES), DEFVAL(true));
	ClassDB::bind_method(D_METHOD("sample_transforms", "path_points", "spacing", "max_samples", "fit_to_path"),
			&PCGPolylineSampler3D::sample_transforms, DEFVAL(MAX_SAMPLES), DEFVAL(true));
}

PackedVector3Array PCGPolylineSampler3D::sample_positions(
		const PackedVector3Array &p_path_points, double p_spacing,
		int p_max_samples, bool p_fit_to_path) const {
	PackedVector3Array empty;
	const int count = p_path_points.size();
	if (count < 1 || count > MAX_PATH_POINTS || p_max_samples < 1 ||
			p_max_samples > MAX_SAMPLES || !Math::is_finite(p_spacing) ||
			p_spacing < MIN_SPACING || p_spacing > MAX_SPACING) {
		return empty;
	}

	// Validate everything first, even if the final output budget would
	// allow just one point. Never return a partial malformed batch.
	for (const Vector3 &point : p_path_points) {
		if (!point.is_finite() || Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				Math::abs(double(point.z)) > MAX_COORDINATE) {
			return empty;
		}
	}

	Vector<double> lengths;
	lengths.resize(count - 1);
	double total_length = 0.0;
	for (int i = 0; i < count - 1; ++i) {
		const Vector3 a = p_path_points[i];
		const Vector3 b = p_path_points[i + 1];
		const double dx = double(b.x) - double(a.x);
		const double dy = double(b.y) - double(a.y);
		const double dz = double(b.z) - double(a.z);
		const double length = Math::sqrt(dx * dx + dy * dy + dz * dz);
		lengths.write[i] = length;
		total_length += length;
	}

	// A one-point or completely degenerate route still has one sample.
	if (total_length == 0.0) {
		PackedVector3Array single;
		single.push_back(p_path_points[0]);
		return single;
	}

	// Check the count as a double BEFORE converting to int, since a valid
	// huge polyline with the smallest spacing may exceed int32.
	const double desired_intervals = p_fit_to_path ?
			Math::ceil(total_length / p_spacing) : Math::floor(total_length / p_spacing);
	if (!Math::is_finite(desired_intervals) ||
			desired_intervals > double(p_max_samples - 1)) {
		return empty;
	}
	const int intervals = int(desired_intervals);
	PackedVector3Array result;
	const int segment_count = count - 1;
	int segment = 0;
	double distance_before_segment = 0.0;
	for (int sample = 0; sample <= intervals; ++sample) {
		const double target = p_fit_to_path ?
				(total_length * double(sample) / double(intervals)) :
				(p_spacing * double(sample));
		while (segment < segment_count - 1 &&
				target > distance_before_segment + lengths[segment]) {
			distance_before_segment += lengths[segment];
			++segment;
		}
		// Exact endpoint avoids accumulated roundoff. fit_to_path=false
		// deliberately omits the endpoint when spacing does not divide length.
		if (p_fit_to_path && sample == intervals) {
			result.push_back(p_path_points[count - 1]);
			continue;
		}
		const double segment_length = lengths[segment];
		const double fraction = segment_length > 0.0 ?
				MAX(0.0, MIN(1.0, (target - distance_before_segment) / segment_length)) : 0.0;
		result.push_back(p_path_points[segment].lerp(
				p_path_points[segment + 1], real_t(fraction)));
	}
	return result;
}

Array PCGPolylineSampler3D::sample_transforms(const PackedVector3Array &p_path_points,
		double p_spacing, int p_max_samples, bool p_fit_to_path) const {
	Array result;
	// Share all validation, arc-length spacing, caps and exact endpoints
	// with sample_positions. No per-point scene nodes or physics queries.
	const PackedVector3Array positions = sample_positions(p_path_points,
			p_spacing, p_max_samples, p_fit_to_path);
	if (positions.is_empty()) {
		return result;
	}
	result.resize(positions.size());
	for (int i = 0; i < positions.size(); ++i) {
		const int previous = MAX(0, i - 1);
		const int next = MIN(positions.size() - 1, i + 1);
		// The centered secant approximates the tangent bisector at a bend,
		// avoiding a hard yaw jump at exactly the shared waypoint.
		Vector3 tangent = positions[next] - positions[previous];
		if (tangent.length_squared() <= 1.0e-12) {
			if (i + 1 < positions.size()) {
				tangent = positions[i + 1] - positions[i];
			}
			if (tangent.length_squared() <= 1.0e-12 && i > 0) {
				tangent = positions[i] - positions[i - 1];
			}
		}
		// A fit-disabled short route can yield only one sample, and a
		// closed U-turn can have equal neighboring positions. Fall back to
		// the first usable original path edge, then a stable +Z default.
		if (tangent.length_squared() <= 1.0e-12) {
			for (int segment = 1; segment < p_path_points.size(); ++segment) {
				tangent = p_path_points[segment] - p_path_points[segment - 1];
				if (tangent.length_squared() > 1.0e-12) {
					break;
				}
			}
		}
		if (tangent.length_squared() <= 1.0e-12) {
			tangent = Vector3(0, 0, 1);
		}
		tangent.normalize();

		// For nearly vertical routes Y cannot serve as the reference up;
		// choosing +Z in that case gives a finite, right-handed frame.
		const Vector3 up_reference = Math::abs(double(tangent.y)) >= 0.98 ?
				Vector3(0, 0, 1) : Vector3(0, 1, 0);
		const Vector3 right = up_reference.cross(tangent).normalized();
		const Vector3 up = tangent.cross(right).normalized();
		result[i] = Transform3D(Basis(right, up, tangent), positions[i]);
	}
	return result;
}
