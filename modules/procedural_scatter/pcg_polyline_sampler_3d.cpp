/**************************************************************************/
/*  pcg_polyline_sampler_3d.cpp                                             */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_polyline_sampler_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/vector.h"

void PCGPolylineSampler3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sample_positions", "path_points", "spacing", "max_samples", "fit_to_path"),
			&PCGPolylineSampler3D::sample_positions, DEFVAL(MAX_SAMPLES), DEFVAL(true));
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
