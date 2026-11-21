/**************************************************************************/
/*  environment_query_3d.cpp                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "environment_query_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/sort_array.h"
#include "core/templates/vector.h"

namespace {

struct QueryHit {
	Vector3 position;
	int index = 0;
	double score = 0.0;
	double distance = 0.0;
	double threat_distance = -1.0;
};

struct HitComparator {
	bool operator()(const QueryHit &p_a, const QueryHit &p_b) const {
		if (p_a.score != p_b.score) {
			// Higher scores first.
			return p_a.score > p_b.score;
		}
		// Deterministic/stable ordering even with an unstable sort.
		return p_a.index < p_b.index;
	}
};

static double point_distance(const Vector3 &p_a, const Vector3 &p_b, bool p_horizontal_only) {
	if (p_horizontal_only) {
		return Vector2(p_a.x - p_b.x, p_a.z - p_b.z).length();
	}
	return p_a.distance_to(p_b);
}

// Shared evaluation keeps full and bounded query ranking exactly equivalent.
static bool score_candidate(const Vector3 &p_point, int p_index,
		const Vector3 &p_origin, const Vector3 &p_threat_position,
		const PackedVector3Array &p_threat_positions,
		const PackedVector3Array &p_exclusion_positions, double p_min_exclusion_distance,
		bool p_use_direction, const Vector3 &p_direction_origin, const Vector3 &p_direction_axis, double p_min_direction_dot, double p_max_direction_dot,
		bool p_use_threat, bool p_horizontal_only, double p_min_distance,
		double p_max_distance, double p_max_vertical_difference, double p_desired_distance,
		double p_distance_weight, double p_safety_weight,
		double p_min_threat_distance, QueryHit &r_hit) {
	if (!p_point.is_finite()) {
		return false;
	}
	const double distance = point_distance(p_origin, p_point, p_horizontal_only);
	if (!Math::is_finite(distance) || distance < p_min_distance || distance > p_max_distance) {
		return false;
	}
	// Height is a separate optional terrain test even when travel distance uses XZ.
	if (p_max_vertical_difference > 0.0 && Math::abs(p_point.y - p_origin.y) > p_max_vertical_difference) {
		return false; // The exact height boundary is allowed.
	}
	// Directional EQS test is opt-in and evaluated before multi-actor scoring.
	// The direction context is independent from the travel-distance origin.
	if (p_use_direction) {
		double facing_dot;
		if (p_horizontal_only) {
			const Vector2 to_point(p_point.x - p_direction_origin.x, p_point.z - p_direction_origin.z);
			const Vector2 axis(p_direction_axis.x, p_direction_axis.z);
			if (to_point.length_squared() <= 0.0 || axis.length_squared() <= 0.0) {
				return false; // A zero-length XZ direction has no defined angle.
			}
			facing_dot = to_point.normalized().dot(axis.normalized());
		} else {
			const Vector3 to_point = p_point - p_direction_origin;
			if (to_point.length_squared() <= 0.0) {
				return false;
			}
			facing_dot = to_point.normalized().dot(p_direction_axis.normalized());
		}
		if (!Math::is_finite(facing_dot) || facing_dot < p_min_direction_dot || facing_dot > p_max_direction_dot) {
			return false;
		}
	}
	// Low-cost exclusion contexts are tested before expensive threat scoring.
	// The exact boundary is allowed, matching the min_threat_distance filter.
	if (p_min_exclusion_distance > 0.0) {
		for (int i = 0; i < p_exclusion_positions.size(); i++) {
			const double clearance = point_distance(p_point, p_exclusion_positions[i], p_horizontal_only);
			if (!Math::is_finite(clearance) || clearance < p_min_exclusion_distance) {
				return false;
			}
		}
	}
	double threat_distance = -1.0;
	if (p_use_threat) {
		if (p_threat_positions.is_empty()) {
			// Legacy single-context behavior remains byte-for-byte compatible.
			threat_distance = point_distance(p_threat_position, p_point, p_horizontal_only);
		} else {
			// Multi-context queries use the nearest threat, never the average.
			// This guarantees a safe score against *every* relevant player.
			threat_distance = point_distance(p_threat_positions[0], p_point, p_horizontal_only);
			for (int threat = 1; threat < p_threat_positions.size(); threat++) {
				const double d = point_distance(p_threat_positions[threat], p_point, p_horizontal_only);
				if (!Math::is_finite(d)) {
					return false;
				}
				threat_distance = MIN(threat_distance, d);
			}
		}
		if (!Math::is_finite(threat_distance) || threat_distance < p_min_threat_distance) {
			return false;
		}
	}
	const double scale = MAX(p_max_distance, 1.0);
	const double distance_score = 1.0 - MIN(1.0, Math::abs(distance - p_desired_distance) / scale);
	const double safety_score = p_use_threat ? MIN(1.0, threat_distance / scale) : 0.0;
	const double score = p_distance_weight * distance_score + p_safety_weight * safety_score;
	if (!Math::is_finite(score)) {
		return false;
	}
	r_hit.position = p_point;
	r_hit.index = p_index;
	r_hit.score = score;
	r_hit.distance = distance;
	r_hit.threat_distance = threat_distance;
	return true;
}

} // namespace

void EnvironmentQuery3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_candidates", "candidates"), &EnvironmentQuery3D::set_candidates);
	ClassDB::bind_method(D_METHOD("get_candidates"), &EnvironmentQuery3D::get_candidates);
	ClassDB::bind_method(D_METHOD("set_origin", "origin"), &EnvironmentQuery3D::set_origin);
	ClassDB::bind_method(D_METHOD("get_origin"), &EnvironmentQuery3D::get_origin);
	ClassDB::bind_method(D_METHOD("set_threat_position", "position"), &EnvironmentQuery3D::set_threat_position);
	ClassDB::bind_method(D_METHOD("get_threat_position"), &EnvironmentQuery3D::get_threat_position);
	ClassDB::bind_method(D_METHOD("set_threat_positions", "positions"), &EnvironmentQuery3D::set_threat_positions);
	ClassDB::bind_method(D_METHOD("get_threat_positions"), &EnvironmentQuery3D::get_threat_positions);
	ClassDB::bind_method(D_METHOD("set_exclusion_positions", "positions"), &EnvironmentQuery3D::set_exclusion_positions);
	ClassDB::bind_method(D_METHOD("get_exclusion_positions"), &EnvironmentQuery3D::get_exclusion_positions);
	ClassDB::bind_method(D_METHOD("set_min_exclusion_distance", "distance"), &EnvironmentQuery3D::set_min_exclusion_distance);
	ClassDB::bind_method(D_METHOD("get_min_exclusion_distance"), &EnvironmentQuery3D::get_min_exclusion_distance);
	ClassDB::bind_method(D_METHOD("set_use_direction", "enabled"), &EnvironmentQuery3D::set_use_direction);
	ClassDB::bind_method(D_METHOD("is_using_direction"), &EnvironmentQuery3D::is_using_direction);
	ClassDB::bind_method(D_METHOD("set_direction_origin", "origin"), &EnvironmentQuery3D::set_direction_origin);
	ClassDB::bind_method(D_METHOD("get_direction_origin"), &EnvironmentQuery3D::get_direction_origin);
	ClassDB::bind_method(D_METHOD("set_direction_axis", "axis"), &EnvironmentQuery3D::set_direction_axis);
	ClassDB::bind_method(D_METHOD("get_direction_axis"), &EnvironmentQuery3D::get_direction_axis);
	ClassDB::bind_method(D_METHOD("set_min_direction_dot", "dot"), &EnvironmentQuery3D::set_min_direction_dot);
	ClassDB::bind_method(D_METHOD("get_min_direction_dot"), &EnvironmentQuery3D::get_min_direction_dot);
	ClassDB::bind_method(D_METHOD("set_max_direction_dot", "dot"), &EnvironmentQuery3D::set_max_direction_dot);
	ClassDB::bind_method(D_METHOD("get_max_direction_dot"), &EnvironmentQuery3D::get_max_direction_dot);
	ClassDB::bind_method(D_METHOD("set_use_threat", "enabled"), &EnvironmentQuery3D::set_use_threat);
	ClassDB::bind_method(D_METHOD("is_using_threat"), &EnvironmentQuery3D::is_using_threat);
	ClassDB::bind_method(D_METHOD("set_horizontal_only", "enabled"), &EnvironmentQuery3D::set_horizontal_only);
	ClassDB::bind_method(D_METHOD("is_horizontal_only"), &EnvironmentQuery3D::is_horizontal_only);
	ClassDB::bind_method(D_METHOD("set_min_distance", "distance"), &EnvironmentQuery3D::set_min_distance);
	ClassDB::bind_method(D_METHOD("get_min_distance"), &EnvironmentQuery3D::get_min_distance);
	ClassDB::bind_method(D_METHOD("set_max_distance", "distance"), &EnvironmentQuery3D::set_max_distance);
	ClassDB::bind_method(D_METHOD("get_max_distance"), &EnvironmentQuery3D::get_max_distance);
	ClassDB::bind_method(D_METHOD("set_max_vertical_difference", "height"), &EnvironmentQuery3D::set_max_vertical_difference);
	ClassDB::bind_method(D_METHOD("get_max_vertical_difference"), &EnvironmentQuery3D::get_max_vertical_difference);
	ClassDB::bind_method(D_METHOD("set_desired_distance", "distance"), &EnvironmentQuery3D::set_desired_distance);
	ClassDB::bind_method(D_METHOD("get_desired_distance"), &EnvironmentQuery3D::get_desired_distance);
	ClassDB::bind_method(D_METHOD("set_distance_weight", "weight"), &EnvironmentQuery3D::set_distance_weight);
	ClassDB::bind_method(D_METHOD("get_distance_weight"), &EnvironmentQuery3D::get_distance_weight);
	ClassDB::bind_method(D_METHOD("set_safety_weight", "weight"), &EnvironmentQuery3D::set_safety_weight);
	ClassDB::bind_method(D_METHOD("get_safety_weight"), &EnvironmentQuery3D::get_safety_weight);
	ClassDB::bind_method(D_METHOD("set_min_threat_distance", "distance"), &EnvironmentQuery3D::set_min_threat_distance);
	ClassDB::bind_method(D_METHOD("get_min_threat_distance"), &EnvironmentQuery3D::get_min_threat_distance);
	ClassDB::bind_method(D_METHOD("set_max_results", "max_results"), &EnvironmentQuery3D::set_max_results);
	ClassDB::bind_method(D_METHOD("get_max_results"), &EnvironmentQuery3D::get_max_results);
	ClassDB::bind_method(D_METHOD("query"), &EnvironmentQuery3D::query);
	ClassDB::bind_method(D_METHOD("query_positions"), &EnvironmentQuery3D::query_positions);
	ClassDB::bind_method(D_METHOD("query_top_positions", "count"), &EnvironmentQuery3D::query_top_positions);
	ClassDB::bind_method(D_METHOD("query_top_indices", "count"), &EnvironmentQuery3D::query_top_indices);
	ClassDB::bind_method(D_METHOD("query_spread_positions", "count", "min_separation"), &EnvironmentQuery3D::query_spread_positions);
	ClassDB::bind_static_method("EnvironmentQuery3D", D_METHOD("sample_ring", "center", "radius", "count", "phase"), &EnvironmentQuery3D::sample_ring, DEFVAL(0.0));
	ClassDB::bind_static_method("EnvironmentQuery3D", D_METHOD("sample_donut", "center", "inner_radius", "outer_radius", "ring_count", "points_per_ring", "phase", "spiral"), &EnvironmentQuery3D::sample_donut, DEFVAL(0.0), DEFVAL(false));
	ClassDB::bind_static_method("EnvironmentQuery3D", D_METHOD("sample_cone", "center", "direction", "inner_radius", "outer_radius", "ring_count", "points_per_ring", "cone_degrees", "include_center"), &EnvironmentQuery3D::sample_cone, DEFVAL(90.0), DEFVAL(false));
	ClassDB::bind_static_method("EnvironmentQuery3D", D_METHOD("sample_grid", "center", "half_extents", "spacing", "max_points"), &EnvironmentQuery3D::sample_grid, DEFVAL(4096));
	ClassDB::bind_static_method("EnvironmentQuery3D", D_METHOD("sample_oriented_grid", "center", "forward", "half_extents", "spacing", "max_points"), &EnvironmentQuery3D::sample_oriented_grid, DEFVAL(4096));
	ClassDB::bind_static_method("EnvironmentQuery3D", D_METHOD("sample_fibonacci_annulus", "center", "inner_radius", "outer_radius", "count", "phase"), &EnvironmentQuery3D::sample_fibonacci_annulus, DEFVAL(0.0));

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "candidates"), "set_candidates", "get_candidates");
	ADD_GROUP("Distance Filter", "");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "origin"), "set_origin", "get_origin");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_distance", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_min_distance", "get_min_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_distance", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_max_distance", "get_max_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_vertical_difference", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_max_vertical_difference", "get_max_vertical_difference");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "desired_distance", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_desired_distance", "get_desired_distance");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "horizontal_only"), "set_horizontal_only", "is_horizontal_only");
	ADD_GROUP("Directional Filter", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_direction"), "set_use_direction", "is_using_direction");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "direction_origin"), "set_direction_origin", "get_direction_origin");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "direction_axis"), "set_direction_axis", "get_direction_axis");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_direction_dot", PROPERTY_HINT_RANGE, "-1,1,0.01"), "set_min_direction_dot", "get_min_direction_dot");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_direction_dot", PROPERTY_HINT_RANGE, "-1,1,0.01"), "set_max_direction_dot", "get_max_direction_dot");
	ADD_GROUP("Threat Safety", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_threat"), "set_use_threat", "is_using_threat");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "threat_position"), "set_threat_position", "get_threat_position");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "threat_positions"), "set_threat_positions", "get_threat_positions");
	ADD_GROUP("Occupancy Exclusions", "");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "exclusion_positions"), "set_exclusion_positions", "get_exclusion_positions");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_exclusion_distance", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_min_exclusion_distance", "get_min_exclusion_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_threat_distance", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_min_threat_distance", "get_min_threat_distance");
	ADD_GROUP("Scoring", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "distance_weight", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), "set_distance_weight", "get_distance_weight");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "safety_weight", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), "set_safety_weight", "get_safety_weight");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_results", PROPERTY_HINT_RANGE, "0,4096,1,or_greater"), "set_max_results", "get_max_results");
}

void EnvironmentQuery3D::set_candidates(const PackedVector3Array &p_candidates) {
	candidates = p_candidates;
	emit_changed();
}

void EnvironmentQuery3D::set_origin(const Vector3 &p_origin) {
	ERR_FAIL_COND_MSG(!p_origin.is_finite(), "EnvironmentQuery3D.origin must contain finite coordinates.");
	origin = p_origin;
	emit_changed();
}

void EnvironmentQuery3D::set_direction_origin(const Vector3 &p_origin) {
	ERR_FAIL_COND_MSG(!p_origin.is_finite(), "direction_origin must contain finite coordinates.");
	direction_origin = p_origin;
	emit_changed();
}

void EnvironmentQuery3D::set_direction_axis(const Vector3 &p_axis) {
	ERR_FAIL_COND_MSG(!p_axis.is_finite() || p_axis.length_squared() <= 0.0, "direction_axis must be finite and nonzero.");
	direction_axis = p_axis;
	emit_changed();
}

void EnvironmentQuery3D::set_min_direction_dot(double p_dot) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_dot) || p_dot < -1.0 || p_dot > 1.0 || p_dot > max_direction_dot, "min_direction_dot must be finite, within [-1, 1] and no greater than max_direction_dot.");
	min_direction_dot = p_dot;
	emit_changed();
}

void EnvironmentQuery3D::set_max_direction_dot(double p_dot) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_dot) || p_dot < -1.0 || p_dot > 1.0 || p_dot < min_direction_dot, "max_direction_dot must be finite, within [-1, 1] and no less than min_direction_dot.");
	max_direction_dot = p_dot;
	emit_changed();
}

void EnvironmentQuery3D::set_threat_position(const Vector3 &p_position) {
	ERR_FAIL_COND_MSG(!p_position.is_finite(), "EnvironmentQuery3D.threat_position must contain finite coordinates.");
	threat_position = p_position;
	emit_changed();
}

void EnvironmentQuery3D::set_threat_positions(const PackedVector3Array &p_positions) {
	ERR_FAIL_COND_MSG(p_positions.size() > 32, "EnvironmentQuery3D supports at most 32 threat contexts.");
	for (int i = 0; i < p_positions.size(); i++) {
		ERR_FAIL_COND_MSG(!p_positions[i].is_finite(), "EnvironmentQuery3D threat contexts must contain finite coordinates.");
	}
	threat_positions = p_positions;
	emit_changed();
}

void EnvironmentQuery3D::set_exclusion_positions(const PackedVector3Array &p_positions) {
	ERR_FAIL_COND_MSG(p_positions.size() > 128, "EnvironmentQuery3D supports at most 128 occupancy exclusions.");
	for (int i = 0; i < p_positions.size(); i++) {
		ERR_FAIL_COND_MSG(!p_positions[i].is_finite(), "EnvironmentQuery3D exclusions must have finite coordinates.");
	}
	exclusion_positions = p_positions;
	emit_changed();
}

void EnvironmentQuery3D::set_min_exclusion_distance(double p_distance) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_distance) || p_distance < 0.0, "min_exclusion_distance must be finite and nonnegative.");
	min_exclusion_distance = p_distance;
	emit_changed();
}

void EnvironmentQuery3D::set_min_distance(double p_distance) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_distance) || p_distance < 0.0, "min_distance must be finite and nonnegative.");
	min_distance = p_distance;
	emit_changed();
}

void EnvironmentQuery3D::set_max_distance(double p_distance) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_distance) || p_distance < 0.0, "max_distance must be finite and nonnegative.");
	max_distance = p_distance;
	emit_changed();
}

void EnvironmentQuery3D::set_max_vertical_difference(double p_height) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_height) || p_height < 0.0, "max_vertical_difference must be finite and nonnegative.");
	max_vertical_difference = p_height;
	emit_changed();
}

void EnvironmentQuery3D::set_desired_distance(double p_distance) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_distance) || p_distance < 0.0, "desired_distance must be finite and nonnegative.");
	desired_distance = p_distance;
	emit_changed();
}

void EnvironmentQuery3D::set_distance_weight(double p_weight) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_weight) || p_weight < 0.0, "distance_weight must be finite and nonnegative.");
	distance_weight = p_weight;
	emit_changed();
}

void EnvironmentQuery3D::set_safety_weight(double p_weight) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_weight) || p_weight < 0.0, "safety_weight must be finite and nonnegative.");
	safety_weight = p_weight;
	emit_changed();
}

void EnvironmentQuery3D::set_min_threat_distance(double p_distance) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_distance) || p_distance < 0.0, "min_threat_distance must be finite and nonnegative.");
	min_threat_distance = p_distance;
	emit_changed();
}

void EnvironmentQuery3D::set_max_results(int p_max_results) {
	ERR_FAIL_COND_MSG(p_max_results < 0, "max_results must be nonnegative; zero means unlimited.");
	max_results = p_max_results;
	emit_changed();
}

Array EnvironmentQuery3D::query() const {
	Array output;
	if (!origin.is_finite() || (use_threat && !threat_position.is_finite()) || min_distance > max_distance) {
		return output;
	}
	Vector<QueryHit> hits;
	for (int i = 0; i < candidates.size(); i++) {
		QueryHit hit;
		if (score_candidate(candidates[i], i, origin, threat_position, threat_positions,
					exclusion_positions, min_exclusion_distance,
					use_direction, direction_origin, direction_axis, min_direction_dot, max_direction_dot,
					use_threat, horizontal_only, min_distance, max_distance,
					max_vertical_difference, desired_distance, distance_weight, safety_weight,
					min_threat_distance, hit)) {
			hits.push_back(hit);
		}
	}

	if (hits.size() > 1) {
		SortArray<QueryHit, HitComparator> sorter;
		sorter.sort(hits.ptrw(), hits.size());
	}
	const int count = max_results == 0 ? hits.size() : MIN(max_results, hits.size());
	for (int i = 0; i < count; i++) {
		const QueryHit &hit = hits[i];
		Dictionary entry;
		entry["position"] = hit.position;
		entry["index"] = hit.index;
		entry["score"] = hit.score;
		entry["distance"] = hit.distance;
		entry["threat_distance"] = hit.threat_distance;
		output.push_back(entry);
	}
	return output;
}

PackedVector3Array EnvironmentQuery3D::query_positions() const {
	PackedVector3Array positions;
	const Array results = query();
	for (int i = 0; i < results.size(); i++) {
		const Dictionary entry = results[i];
		positions.push_back(entry["position"]);
	}
	return positions;
}

// Stable top-K: O(N*K) time and O(K) memory; no per-candidate
// dictionaries and no full sort for crowds requesting only 3 goals.
PackedVector3Array EnvironmentQuery3D::query_top_positions(int p_count) const {
	PackedVector3Array output;
	ERR_FAIL_COND_V_MSG(p_count < 1 || p_count > 64, output, "Top-K count must be between 1 and 64.");
	if (!origin.is_finite() || (use_threat && !threat_position.is_finite()) || min_distance > max_distance) {
		return output;
	}
	const int limit = max_results == 0 ? p_count : MIN(p_count, max_results);
	Vector<QueryHit> best;
	HitComparator better;
	for (int i = 0; i < candidates.size(); i++) {
		QueryHit hit;
		if (!score_candidate(candidates[i], i, origin, threat_position, threat_positions,
					exclusion_positions, min_exclusion_distance,
					use_direction, direction_origin, direction_axis, min_direction_dot, max_direction_dot,
					use_threat, horizontal_only, min_distance, max_distance,
					max_vertical_difference, desired_distance, distance_weight, safety_weight,
					min_threat_distance, hit)) {
			continue;
		}
		if (best.size() == limit && !better(hit, best[best.size() - 1])) {
			continue;
		}
		int at = 0;
		while (at < best.size() && !better(hit, best[at])) {
			at++;
		}
		best.insert(at, hit);
		if (best.size() > limit) {
			best.resize(limit);
		}
	}
	output.resize(best.size());
	Vector3 *write = output.ptrw();
	for (int i = 0; i < best.size(); i++) {
		write[i] = best[i].position;
	}
	return output;
}

// Item identity is part of an EQS query result. Geometry alone cannot
// reliably map a ranked position back to a unique gameplay slot, especially
// when two source candidates have identical coordinates. Keep exactly the
// same bounded scorer, stable tie break and max_results cap as top positions.
PackedInt32Array EnvironmentQuery3D::query_top_indices(int p_count) const {
	PackedInt32Array output;
	ERR_FAIL_COND_V_MSG(p_count < 1 || p_count > 64, output, "Top-K count must be between 1 and 64.");
	if (!origin.is_finite() || (use_threat && !threat_position.is_finite()) || min_distance > max_distance) {
		return output;
	}
	const int limit = max_results == 0 ? p_count : MIN(p_count, max_results);
	Vector<QueryHit> best;
	HitComparator better;
	for (int i = 0; i < candidates.size(); i++) {
		QueryHit hit;
		if (!score_candidate(candidates[i], i, origin, threat_position, threat_positions,
					exclusion_positions, min_exclusion_distance,
					use_direction, direction_origin, direction_axis, min_direction_dot, max_direction_dot,
					use_threat, horizontal_only, min_distance, max_distance,
					max_vertical_difference, desired_distance, distance_weight, safety_weight,
					min_threat_distance, hit)) {
			continue;
		}
		if (best.size() == limit && !better(hit, best[best.size() - 1])) {
			continue;
		}
		int at = 0;
		while (at < best.size() && !better(hit, best[at])) {
			at++;
		}
		best.insert(at, hit);
		if (best.size() > limit) {
			best.resize(limit);
		}
	}
	output.resize(best.size());
	int32_t *write = output.ptrw();
	for (int i = 0; i < best.size(); i++) {
		write[i] = best[i].index;
	}
	return output;
}

// Greedy non-maximum suppression after the exact same safety/distance tests
// as query(). Unlike selecting top-K then spacing, this scans ALL scored
// candidates so a nearby runner-up cannot prevent a more distant safe pick.
// Deterministic order: score descending, original candidate index on ties.
PackedVector3Array EnvironmentQuery3D::query_spread_positions(int p_count, double p_min_separation) const {
	PackedVector3Array output;
	ERR_FAIL_COND_V_MSG(p_count < 1 || p_count > 64, output, "Spread count must be between 1 and 64.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_min_separation) || p_min_separation < 0.0, output, "Minimum separation must be finite and nonnegative.");
	if (!origin.is_finite() || (use_threat && !threat_position.is_finite()) || min_distance > max_distance) {
		return output;
	}

	const int limit = max_results == 0 ? p_count : MIN(p_count, max_results);
	Vector<QueryHit> hits;
	for (int i = 0; i < candidates.size(); i++) {
		QueryHit hit;
		if (score_candidate(candidates[i], i, origin, threat_position, threat_positions,
					exclusion_positions, min_exclusion_distance,
					use_direction, direction_origin, direction_axis, min_direction_dot, max_direction_dot,
					use_threat, horizontal_only, min_distance, max_distance,
					max_vertical_difference, desired_distance, distance_weight, safety_weight,
					min_threat_distance, hit)) {
			hits.push_back(hit);
		}
	}
	if (hits.size() > 1) {
		SortArray<QueryHit, HitComparator> sorter;
		sorter.sort(hits.ptrw(), hits.size());
	}

	for (int i = 0; i < hits.size() && output.size() < limit; i++) {
		const Vector3 &point = hits[i].position;
		bool separated = true;
		for (int j = 0; j < output.size(); j++) {
			if (point_distance(point, output[j], horizontal_only) < p_min_separation) {
				separated = false;
				break;
			}
		}
		if (separated) {
			output.push_back(point);
		}
	}
	return output;
}

PackedVector3Array EnvironmentQuery3D::sample_ring(const Vector3 &p_center, double p_radius, int p_count, double p_phase) {
	PackedVector3Array output;
	ERR_FAIL_COND_V_MSG(!p_center.is_finite() || !Math::is_finite(p_radius) || p_radius < 0.0, output, "Ring center and radius must be finite; radius must be nonnegative.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_phase) || p_count < 1 || p_count > 4096, output, "Ring phase must be finite and point count must be between 1 and 4096.");
	output.resize(p_count);
	Vector3 *ptr = output.ptrw();
	for (int i = 0; i < p_count; i++) {
		const double angle = p_phase + Math::TAU * double(i) / double(p_count);
		ptr[i] = p_center + Vector3(Math::cos(angle) * p_radius, 0.0, Math::sin(angle) * p_radius);
	}
	return output;
}

// Native, bounded counterpart to Unreal's EQS Points: Donut generator.
// Candidate generation remains geometric: gameplay validates nav, collision,
// height and occupancy independently before allowing spawns.
PackedVector3Array EnvironmentQuery3D::sample_donut(const Vector3 &p_center, double p_inner_radius, double p_outer_radius, int p_ring_count, int p_points_per_ring, double p_phase, bool p_spiral) {
	PackedVector3Array output;
	ERR_FAIL_COND_V_MSG(!p_center.is_finite() || !Math::is_finite(p_inner_radius) || !Math::is_finite(p_outer_radius) ||
			p_inner_radius < 0.0 || p_outer_radius < p_inner_radius, output,
			"Donut center/radii must be finite and satisfy 0 <= inner_radius <= outer_radius.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_phase) || p_ring_count < 1 || p_ring_count > 256 ||
			p_points_per_ring < 1 || p_points_per_ring > 4096, output,
			"Donut phase must be finite, ring count 1..256 and points per ring 1..4096.");
	const int64_t total = int64_t(p_ring_count) * p_points_per_ring;
	ERR_FAIL_COND_V_MSG(total > 65536, output, "Donut sample budget is limited to 65536 points.");
	output.resize(int(total));
	Vector3 *ptr = output.ptrw();
	for (int ring = 0; ring < p_ring_count; ring++) {
		// With a single ring, match sample_ring(outer_radius).
		const double radius = p_ring_count == 1 ? p_outer_radius :
				p_inner_radius + (p_outer_radius - p_inner_radius) * double(ring) / double(p_ring_count - 1);
		const double ring_offset = p_spiral ? double(ring) / double(p_ring_count) : 0.0;
		for (int index = 0; index < p_points_per_ring; index++) {
			const double angle = p_phase + Math::TAU * (double(index) + ring_offset) / double(p_points_per_ring);
			const Vector3 point = p_center + Vector3(Math::cos(angle) * radius, 0.0, Math::sin(angle) * radius);
			ERR_FAIL_COND_V_MSG(!point.is_finite(), PackedVector3Array(), "Donut sample coordinates must be finite.");
			ptr[ring * p_points_per_ring + index] = point;
		}
	}
	return output;
}

// Geometry-only counterpart to Unreal EQS Points: Cone. Every candidate
// remains untrusted until gameplay validates terrain, navigation and blockers.
PackedVector3Array EnvironmentQuery3D::sample_cone(const Vector3 &p_center, const Vector3 &p_direction, double p_inner_radius, double p_outer_radius, int p_ring_count, int p_points_per_ring, double p_cone_degrees, bool p_include_center) {
	PackedVector3Array output;
	ERR_FAIL_COND_V_MSG(!p_center.is_finite() || !p_direction.is_finite() ||
			!Math::is_finite(p_inner_radius) || !Math::is_finite(p_outer_radius) ||
			p_inner_radius < 0.0 || p_outer_radius < p_inner_radius, output,
			"Cone coordinates and radii must be finite and satisfy 0 <= inner_radius <= outer_radius.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_cone_degrees) || p_cone_degrees < 0.0 || p_cone_degrees > 360.0,
			output, "Cone aperture must be finite and within 0..360 degrees.");
	ERR_FAIL_COND_V_MSG(p_ring_count < 1 || p_ring_count > 256 ||
			p_points_per_ring < 1 || p_points_per_ring > 4096,
			output, "Cone ring count must be 1..256 and points per ring 1..4096.");
	const int64_t count = int64_t(p_ring_count) * p_points_per_ring + (p_include_center ? 1 : 0);
	ERR_FAIL_COND_V_MSG(count > 65536, output, "Cone sample budget is limited to 65536 points.");
	const double axis_length = Math::sqrt(double(p_direction.x) * p_direction.x + double(p_direction.z) * p_direction.z);
	ERR_FAIL_COND_V_MSG(!Math::is_finite(axis_length) || axis_length <= CMP_EPSILON,
			output, "Cone direction must have a finite nonzero XZ projection.");
	const double center_angle = Math::atan2(double(p_direction.z) / axis_length, double(p_direction.x) / axis_length);
	const double aperture = Math::deg_to_rad(p_cone_degrees);
	output.resize(int(count));
	Vector3 *ptr = output.ptrw();
	const int offset = p_include_center ? 1 : 0;
	if (p_include_center) {
		ptr[0] = p_center;
	}
	for (int ring = 0; ring < p_ring_count; ring++) {
		const double radius = p_ring_count == 1 ? p_outer_radius :
				p_inner_radius + (p_outer_radius - p_inner_radius) * double(ring) / double(p_ring_count - 1);
		for (int ray = 0; ray < p_points_per_ring; ray++) {
			const double fraction = p_points_per_ring == 1 ? 0.5 : double(ray) / double(p_points_per_ring - 1);
			const double angle = center_angle + aperture * (fraction - 0.5);
			const Vector3 point = p_center + Vector3(Math::cos(angle) * radius, 0.0, Math::sin(angle) * radius);
			ERR_FAIL_COND_V_MSG(!point.is_finite(), PackedVector3Array(), "Cone sample coordinates must be finite.");
			ptr[offset + ring * p_points_per_ring + ray] = point;
		}
	}
	return output;
}

// Context-facing EQS grid. Unlike the world-aligned sample_grid(), this
// rotates an XZ lattice to the caller's forward axis. No scene or physics work.
PackedVector3Array EnvironmentQuery3D::sample_oriented_grid(const Vector3 &p_center, const Vector3 &p_forward, const Vector2 &p_half_extents, double p_spacing, int p_max_points) {
	PackedVector3Array output;
	ERR_FAIL_COND_V_MSG(!p_center.is_finite() || !p_forward.is_finite() || !p_half_extents.is_finite(),
			output, "Oriented grid center, forward and half extents must be finite.");
	ERR_FAIL_COND_V_MSG(p_half_extents.x < 0.0 || p_half_extents.y < 0.0 ||
			!Math::is_finite(p_spacing) || p_spacing <= 0.0,
			output, "Oriented grid half extents must be nonnegative and spacing positive.");
	ERR_FAIL_COND_V_MSG(p_max_points < 1 || p_max_points > 65536,
			output, "Oriented grid point limit must be between 1 and 65536.");
	const double axis_length = Math::sqrt(double(p_forward.x) * p_forward.x + double(p_forward.z) * p_forward.z);
	ERR_FAIL_COND_V_MSG(!Math::is_finite(axis_length) || axis_length <= CMP_EPSILON,
			output, "Oriented grid forward direction must have a nonzero XZ projection.");
	const double cells_x = Math::floor(2.0 * p_half_extents.x / p_spacing);
	const double cells_z = Math::floor(2.0 * p_half_extents.y / p_spacing);
	ERR_FAIL_COND_V_MSG(!Math::is_finite(cells_x) || !Math::is_finite(cells_z) ||
			cells_x >= p_max_points || cells_z >= p_max_points,
			output, "Oriented grid size exceeds its point limit.");
	const int count_x = int(cells_x) + 1;
	const int count_z = int(cells_z) + 1;
	ERR_FAIL_COND_V_MSG(int64_t(count_x) * count_z > p_max_points,
			output, "Oriented grid size exceeds its point limit.");
	const double forward_x = double(p_forward.x) / axis_length;
	const double forward_z = double(p_forward.z) / axis_length;
	const double right_x = forward_z;
	const double right_z = -forward_x;
	output.resize(count_x * count_z);
	Vector3 *ptr = output.ptrw();
	for (int z = 0; z < count_z; z++) {
		const double local_z = -p_half_extents.y + double(z) * p_spacing;
		for (int x = 0; x < count_x; x++) {
			const double local_x = -p_half_extents.x + double(x) * p_spacing;
			const Vector3 point = p_center + Vector3(
					right_x * local_x + forward_x * local_z, 0.0,
					right_z * local_x + forward_z * local_z);
			ERR_FAIL_COND_V_MSG(!point.is_finite(), PackedVector3Array(), "Oriented grid sample coordinates must be finite.");
			ptr[z * count_x + x] = point;
		}
	}
	return output;
}

// Bounded, area-uniform radial candidates analogous to a procedural scatter
// sampler. Square-radius interpolation avoids the center clustering produced
// by linear radius interpolation; golden-angle rotation reduces axial spokes.
// Gameplay remains responsible for all terrain, occupancy and nav validation.
PackedVector3Array EnvironmentQuery3D::sample_fibonacci_annulus(const Vector3 &p_center, double p_inner_radius, double p_outer_radius, int p_count, double p_phase) {
	PackedVector3Array output;
	ERR_FAIL_COND_V_MSG(!p_center.is_finite() || !Math::is_finite(p_inner_radius) ||
			!Math::is_finite(p_outer_radius) || p_inner_radius < 0.0 ||
			p_outer_radius < p_inner_radius, output,
			"Fibonacci annulus requires finite center and radii, 0 <= inner <= outer.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_phase) || p_count < 1 || p_count > 65536,
			output, "Fibonacci annulus phase must be finite and point count 1..65536.");
	const double min_square = p_inner_radius * p_inner_radius;
	const double max_square = p_outer_radius * p_outer_radius;
	ERR_FAIL_COND_V_MSG(!Math::is_finite(max_square), output, "Fibonacci annulus radii are too large to sample safely.");
	// Explicit constant for stable cross-platform gameplay reference results.
	constexpr double GOLDEN_ANGLE = 2.39996322972865332;
	output.resize(p_count);
	Vector3 *ptr = output.ptrw();
	for (int index = 0; index < p_count; index++) {
		const double fraction = (double(index) + 0.5) / double(p_count);
		const double radius = Math::sqrt(min_square + (max_square - min_square) * fraction);
		const double angle = p_phase + GOLDEN_ANGLE * double(index);
		const Vector3 point = p_center + Vector3(Math::cos(angle) * radius, 0.0, Math::sin(angle) * radius);
		ERR_FAIL_COND_V_MSG(!point.is_finite(), PackedVector3Array(), "Fibonacci annulus generated a nonfinite point.");
		ptr[index] = point;
	}
	return output;
}

PackedVector3Array EnvironmentQuery3D::sample_grid(const Vector3 &p_center, const Vector2 &p_half_extents, double p_spacing, int p_max_points) {
	PackedVector3Array output;
	ERR_FAIL_COND_V_MSG(!p_center.is_finite() || !p_half_extents.is_finite(), output, "Grid center and extents must contain finite coordinates.");
	ERR_FAIL_COND_V_MSG(p_half_extents.x < 0.0 || p_half_extents.y < 0.0 || !Math::is_finite(p_spacing) || p_spacing <= 0.0, output, "Grid half extents must be nonnegative and spacing positive.");
	ERR_FAIL_COND_V_MSG(p_max_points < 1 || p_max_points > 65536, output, "Grid point limit must be between 1 and 65536.");
	const double cells_x = Math::floor(2.0 * p_half_extents.x / p_spacing);
	const double cells_z = Math::floor(2.0 * p_half_extents.y / p_spacing);
	ERR_FAIL_COND_V_MSG(!Math::is_finite(cells_x) || !Math::is_finite(cells_z) || cells_x >= p_max_points || cells_z >= p_max_points, output, "Grid size exceeds the point limit.");
	const int count_x = int(cells_x) + 1;
	const int count_z = int(cells_z) + 1;
	ERR_FAIL_COND_V_MSG(int64_t(count_x) * count_z > p_max_points, output, "Grid size exceeds the point limit.");

	output.resize(count_x * count_z);
	Vector3 *ptr = output.ptrw();
	for (int z = 0; z < count_z; z++) {
		for (int x = 0; x < count_x; x++) {
			ptr[z * count_x + x] = p_center + Vector3(-p_half_extents.x + double(x) * p_spacing, 0, -p_half_extents.y + double(z) * p_spacing);
		}
	}
	return output;
}
