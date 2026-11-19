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

} // namespace

void EnvironmentQuery3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_candidates", "candidates"), &EnvironmentQuery3D::set_candidates);
	ClassDB::bind_method(D_METHOD("get_candidates"), &EnvironmentQuery3D::get_candidates);
	ClassDB::bind_method(D_METHOD("set_origin", "origin"), &EnvironmentQuery3D::set_origin);
	ClassDB::bind_method(D_METHOD("get_origin"), &EnvironmentQuery3D::get_origin);
	ClassDB::bind_method(D_METHOD("set_threat_position", "position"), &EnvironmentQuery3D::set_threat_position);
	ClassDB::bind_method(D_METHOD("get_threat_position"), &EnvironmentQuery3D::get_threat_position);
	ClassDB::bind_method(D_METHOD("set_use_threat", "enabled"), &EnvironmentQuery3D::set_use_threat);
	ClassDB::bind_method(D_METHOD("is_using_threat"), &EnvironmentQuery3D::is_using_threat);
	ClassDB::bind_method(D_METHOD("set_horizontal_only", "enabled"), &EnvironmentQuery3D::set_horizontal_only);
	ClassDB::bind_method(D_METHOD("is_horizontal_only"), &EnvironmentQuery3D::is_horizontal_only);
	ClassDB::bind_method(D_METHOD("set_min_distance", "distance"), &EnvironmentQuery3D::set_min_distance);
	ClassDB::bind_method(D_METHOD("get_min_distance"), &EnvironmentQuery3D::get_min_distance);
	ClassDB::bind_method(D_METHOD("set_max_distance", "distance"), &EnvironmentQuery3D::set_max_distance);
	ClassDB::bind_method(D_METHOD("get_max_distance"), &EnvironmentQuery3D::get_max_distance);
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
	ClassDB::bind_static_method("EnvironmentQuery3D", D_METHOD("sample_ring", "center", "radius", "count", "phase"), &EnvironmentQuery3D::sample_ring, DEFVAL(0.0));
	ClassDB::bind_static_method("EnvironmentQuery3D", D_METHOD("sample_grid", "center", "half_extents", "spacing", "max_points"), &EnvironmentQuery3D::sample_grid, DEFVAL(4096));

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "candidates"), "set_candidates", "get_candidates");
	ADD_GROUP("Distance Filter", "");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "origin"), "set_origin", "get_origin");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_distance", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_min_distance", "get_min_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_distance", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_max_distance", "get_max_distance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "desired_distance", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_desired_distance", "get_desired_distance");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "horizontal_only"), "set_horizontal_only", "is_horizontal_only");
	ADD_GROUP("Threat Safety", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_threat"), "set_use_threat", "is_using_threat");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "threat_position"), "set_threat_position", "get_threat_position");
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

void EnvironmentQuery3D::set_threat_position(const Vector3 &p_position) {
	ERR_FAIL_COND_MSG(!p_position.is_finite(), "EnvironmentQuery3D.threat_position must contain finite coordinates.");
	threat_position = p_position;
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
		const Vector3 point = candidates[i];
		if (!point.is_finite()) {
			continue;
		}
		const double distance = point_distance(origin, point, horizontal_only);
		if (!Math::is_finite(distance) || distance < min_distance || distance > max_distance) {
			continue;
		}
		double threat_distance = -1.0;
		if (use_threat) {
			threat_distance = point_distance(threat_position, point, horizontal_only);
			if (!Math::is_finite(threat_distance) || threat_distance < min_threat_distance) {
				continue;
			}
		}
		// Normalization scale is independent of candidate order and input count.
		const double scale = MAX(max_distance, 1.0);
		const double distance_score = 1.0 - MIN(1.0, Math::abs(distance - desired_distance) / scale);
		const double safety_score = use_threat ? MIN(1.0, threat_distance / scale) : 0.0;
		const double score = distance_weight * distance_score + safety_weight * safety_score;
		if (!Math::is_finite(score)) {
			continue;
		}
		QueryHit hit;
		hit.position = point;
		hit.index = i;
		hit.score = score;
		hit.distance = distance;
		hit.threat_distance = threat_distance;
		hits.push_back(hit);
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
