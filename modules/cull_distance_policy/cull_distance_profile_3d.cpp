/**************************************************************************/
/*  cull_distance_profile_3d.cpp                                            */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "cull_distance_profile_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void CullDistanceProfile3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_cull_distance", "bounds", "sizes", "ranges", "authored_distance"),
			&CullDistanceProfile3D::get_cull_distance, DEFVAL(0.0));
}

double CullDistanceProfile3D::get_cull_distance(const AABB &p_bounds,
		const PackedFloat32Array &p_sizes, const PackedFloat32Array &p_ranges,
		double p_authored_distance) const {
	// -1 is unambiguous failure: zero is a legitimate "never cull" distance.
	if (p_sizes.size() == 0 || p_sizes.size() != p_ranges.size() ||
			p_sizes.size() > MAX_PAIRS || !Math::is_finite(p_authored_distance) ||
			p_authored_distance < 0.0 || p_authored_distance > MAX_VALUE ||
			!p_bounds.position.is_finite() || !p_bounds.size.is_finite() ||
			Math::abs(double(p_bounds.position.x)) > MAX_COORDINATE ||
			Math::abs(double(p_bounds.position.y)) > MAX_COORDINATE ||
			Math::abs(double(p_bounds.position.z)) > MAX_COORDINATE ||
			p_bounds.size.x < 0.0 || p_bounds.size.y < 0.0 || p_bounds.size.z < 0.0 ||
			p_bounds.size.x > MAX_VALUE || p_bounds.size.y > MAX_VALUE || p_bounds.size.z > MAX_VALUE) {
		return -1.0;
	}

	for (int i = 0; i < p_sizes.size(); ++i) {
		const double size = double(p_sizes[i]);
		const double distance = double(p_ranges[i]);
		if (!Math::is_finite(size) || !Math::is_finite(distance) ||
				size < 0.0 || size > MAX_VALUE ||
				distance < 0.0 || distance > MAX_VALUE) {
			return -1.0;
		}
	}

	const double longest_dimension = MAX(double(p_bounds.size.x),
			MAX(double(p_bounds.size.y), double(p_bounds.size.z)));
	double nearest_delta = Math::INF;
	double selected_range = 0.0;
	for (int i = 0; i < p_sizes.size(); ++i) {
		const double candidate_range = double(p_ranges[i]);
		const double delta = Math::abs(longest_dimension - double(p_sizes[i]));
		// Multiple equally-close pairs: pick the strongest positive cull.
		// Zero is "no extra culling", not the most aggressive distance.
		if (delta < nearest_delta ||
				(delta == nearest_delta && candidate_range > 0.0 &&
						(selected_range == 0.0 || candidate_range < selected_range))) {
			nearest_delta = delta;
			selected_range = candidate_range;
		}
	}
	if (selected_range == 0.0) {
		return p_authored_distance;
	}
	return p_authored_distance > 0.0 ?
			MIN(selected_range, p_authored_distance) : selected_range;
}
