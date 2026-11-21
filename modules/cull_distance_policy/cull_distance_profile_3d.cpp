/**************************************************************************/
/*  cull_distance_profile_3d.cpp                                          */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                          */
/**************************************************************************/
#include "cull_distance_profile_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void CullDistanceProfile3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_cull_distance", "bounds", "sizes", "ranges", "authored_distance"),
			&CullDistanceProfile3D::get_cull_distance, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("configure", "sizes", "ranges"), &CullDistanceProfile3D::configure);
	ClassDB::bind_method(D_METHOD("get_pair_count"), &CullDistanceProfile3D::get_pair_count);
	ClassDB::bind_method(D_METHOD("clear_profile"), &CullDistanceProfile3D::clear_profile);
	ClassDB::bind_method(D_METHOD("get_cached_cull_distance", "bounds", "authored_distance"),
			&CullDistanceProfile3D::get_cached_cull_distance, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("get_cached_cull_distances", "positions", "sizes", "authored_distances"),
			&CullDistanceProfile3D::get_cached_cull_distances);
}

bool CullDistanceProfile3D::_valid_pairs(const PackedFloat32Array &p_sizes,
		const PackedFloat32Array &p_ranges) {
	if (p_sizes.is_empty() || p_sizes.size() != p_ranges.size() ||
			p_sizes.size() > MAX_PAIRS) {
		return false;
	}
	for (int i = 0; i < p_sizes.size(); ++i) {
		const double size = double(p_sizes[i]);
		const double distance = double(p_ranges[i]);
		if (!Math::is_finite(size) || !Math::is_finite(distance) ||
				size < 0.0 || size > MAX_VALUE ||
				distance < 0.0 || distance > MAX_VALUE) {
			return false;
		}
	}
	return true;
}

bool CullDistanceProfile3D::_valid_bounds(const AABB &p_bounds,
		double p_authored_distance) {
	return Math::is_finite(p_authored_distance) &&
			p_authored_distance >= 0.0 && p_authored_distance <= MAX_VALUE &&
			p_bounds.position.is_finite() && p_bounds.size.is_finite() &&
			Math::abs(double(p_bounds.position.x)) <= MAX_COORDINATE &&
			Math::abs(double(p_bounds.position.y)) <= MAX_COORDINATE &&
			Math::abs(double(p_bounds.position.z)) <= MAX_COORDINATE &&
			p_bounds.size.x >= 0.0 && p_bounds.size.y >= 0.0 &&
			p_bounds.size.z >= 0.0 && p_bounds.size.x <= MAX_VALUE &&
			p_bounds.size.y <= MAX_VALUE && p_bounds.size.z <= MAX_VALUE;
}

// Shared by one-off and cached APIs: identical order-independent nearest-size
// selection, positive-range tie-breaking and existing authored-distance clamp.
double CullDistanceProfile3D::_resolve_validated(const AABB &p_bounds,
		const PackedFloat32Array &p_sizes, const PackedFloat32Array &p_ranges,
		double p_authored_distance) {
	const double longest_dimension = MAX(double(p_bounds.size.x),
			MAX(double(p_bounds.size.y), double(p_bounds.size.z)));
	double nearest_delta = Math::INF;
	double selected_range = 0.0;
	for (int i = 0; i < p_sizes.size(); ++i) {
		const double candidate_range = double(p_ranges[i]);
		const double delta = Math::abs(longest_dimension - double(p_sizes[i]));
		// Multiple equally-close pairs: choose the shortest positive cull.
		// Zero means "no extra culling", never the most aggressive range.
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

bool CullDistanceProfile3D::configure(const PackedFloat32Array &p_sizes,
		const PackedFloat32Array &p_ranges) {
	// Validate the whole profile before changing its currently usable pairs.
	if (!_valid_pairs(p_sizes, p_ranges)) {
		return false;
	}
	if (configured_sizes == p_sizes && configured_ranges == p_ranges) {
		return true;
	}
	configured_sizes = p_sizes;
	configured_ranges = p_ranges;
	return true;
}

void CullDistanceProfile3D::clear_profile() {
	configured_sizes.clear();
	configured_ranges.clear();
}

double CullDistanceProfile3D::get_cached_cull_distance(const AABB &p_bounds,
		double p_authored_distance) const {
	if (configured_sizes.is_empty() || !_valid_bounds(p_bounds, p_authored_distance)) {
		return -1.0;
	}
	return _resolve_validated(p_bounds, configured_sizes, configured_ranges, p_authored_distance);
}

PackedFloat64Array CullDistanceProfile3D::get_cached_cull_distances(
		const PackedVector3Array &p_positions, const PackedVector3Array &p_sizes,
		const PackedFloat64Array &p_authored_distances) const {
	PackedFloat64Array result;
	const int count = p_positions.size();
	// All-or-nothing validation: no positional result may be returned if a
	// later entry is malformed. The limit bounds work on the main thread.
	if (configured_sizes.is_empty() || count != p_sizes.size() ||
			count != p_authored_distances.size() || count > MAX_BATCH) {
		return result;
	}
	for (int i = 0; i < count; ++i) {
		if (!_valid_bounds(AABB(p_positions[i], p_sizes[i]), p_authored_distances[i])) {
			return result;
		}
	}
	result.resize(count);
	double *values = result.ptrw();
	for (int i = 0; i < count; ++i) {
		values[i] = _resolve_validated(AABB(p_positions[i], p_sizes[i]),
				configured_sizes, configured_ranges, p_authored_distances[i]);
	}
	return result;
}

double CullDistanceProfile3D::get_cull_distance(const AABB &p_bounds,
		const PackedFloat32Array &p_sizes, const PackedFloat32Array &p_ranges,
		double p_authored_distance) const {
	if (!_valid_pairs(p_sizes, p_ranges) || !_valid_bounds(p_bounds, p_authored_distance)) {
		return -1.0;
	}
	return _resolve_validated(p_bounds, p_sizes, p_ranges, p_authored_distance);
}
