/**************************************************************************/
/*  ai_proximity_grid_2d.cpp                                               */
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
/* persons to whom the Software is furnished to do so, subject to the      */
/* following conditions:                                                  */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR OTHER COPYRIGHT HOLDERS BE LIABLE FOR */
/* ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,*/
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "ai_proximity_grid_2d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hash_map.h"

namespace {
constexpr int MAX_POINTS = 8192;
constexpr int MAX_SOURCES = 1024;
constexpr double MAX_POSITION_ABS = 1000000.0;
constexpr double MAX_QUERY_RADIUS = 256.0;

struct NeighborHit {
	int index = -1;
	real_t squared_distance = 0.0;
};
} // namespace

Array AIProximityGrid2D::_query_impl(const PackedVector2Array &p_positions,
		const PackedInt32Array &p_source_indices,
		double p_radius, double p_cell_size, int p_max_neighbors) const {
	Array result;
	// Reject malformed input *before* building a grid or exposing partial hits.
	if (p_positions.size() > MAX_POINTS || p_source_indices.size() > MAX_SOURCES ||
			!Math::is_finite(p_radius) || p_radius < 0.0 || p_radius > MAX_QUERY_RADIUS ||
			!Math::is_finite(p_cell_size) || p_cell_size < 1.0 ||
			p_cell_size > MAX_QUERY_RADIUS || p_cell_size < p_radius ||
			p_max_neighbors < 0 || p_max_neighbors > 64) {
		return result;
	}
	for (int i = 0; i < p_positions.size(); i++) {
		const Vector2 point = p_positions[i];
		if (!point.is_finite() || Math::abs(point.x) > MAX_POSITION_ABS ||
				Math::abs(point.y) > MAX_POSITION_ABS) {
			return Array();
		}
	}
	for (int i = 0; i < p_source_indices.size(); i++) {
		if (p_source_indices[i] < 0 || p_source_indices[i] >= p_positions.size()) {
			return Array();
		}
	}

	HashMap<Vector2i, Vector<int>> cells;
	Vector<Vector2i> cell_of;
	cell_of.resize(p_positions.size());
	for (int i = 0; i < p_positions.size(); i++) {
		const Vector2 point = p_positions[i];
		const Vector2i cell(int(Math::floor(point.x / p_cell_size)),
				int(Math::floor(point.y / p_cell_size)));
		cell_of.write[i] = cell;
		Vector<int> *bucket = cells.getptr(cell);
		if (bucket) {
			bucket->push_back(i);
		} else {
			Vector<int> first;
			first.push_back(i);
			cells.insert(cell, first);
		}
	}

	const double squared_radius = p_radius * p_radius;
	for (int i = 0; i < p_source_indices.size(); i++) {
		const int source_index = p_source_indices[i];
		const Vector2 center = p_positions[source_index];
		const Vector2i origin = cell_of[source_index];
		Vector<int> hit_indices;
		// Fixed-size top-K accumulator; avoids collecting every dense neighbor
		// when the game only wants a small number of nearby allies.
		Vector<NeighborHit> nearest;
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				const Vector<int> *bucket = cells.getptr(origin + Vector2i(x, y));
				if (!bucket) {
					continue;
				}
				for (int j = 0; j < bucket->size(); j++) {
					const int nearby = (*bucket)[j];
					if (nearby == source_index) {
						continue;
					}
					const real_t squared_distance = center.distance_squared_to(p_positions[nearby]);
					if (squared_distance > squared_radius) {
						continue;
					}
					if (p_max_neighbors == 0) {
						hit_indices.push_back(nearby);
						continue;
					}
					NeighborHit candidate;
					candidate.index = nearby;
					candidate.squared_distance = squared_distance;
					if (nearest.size() < p_max_neighbors) {
						nearest.push_back(candidate);
						continue;
					}
					int worst = 0;
					for (int k = 1; k < nearest.size(); k++) {
						const NeighborHit &a = nearest[k];
						const NeighborHit &b = nearest[worst];
						if (a.squared_distance > b.squared_distance ||
								(a.squared_distance == b.squared_distance && a.index > b.index)) {
							worst = k;
						}
					}
					const NeighborHit &old = nearest[worst];
					if (candidate.squared_distance < old.squared_distance ||
							(candidate.squared_distance == old.squared_distance && candidate.index < old.index)) {
						nearest.write[worst] = candidate;
					}
				}
			}
		}
		for (int j = 0; j < nearest.size(); j++) {
			hit_indices.push_back(nearest[j].index);
		}
		// Bucket traversal order is internal; stable input index order ensures
		// authoritative game effects never depend on HashMap iteration.
		hit_indices.sort();
		PackedInt32Array hits;
		hits.resize(hit_indices.size());
		for (int j = 0; j < hit_indices.size(); j++) {
			hits.set(j, hit_indices[j]);
		}
		result.push_back(hits);
	}
	return result;
}

Array AIProximityGrid2D::query_radius_batch(const PackedVector2Array &p_positions,
		const PackedInt32Array &p_source_indices, double p_radius, double p_cell_size) const {
	return _query_impl(p_positions, p_source_indices, p_radius, p_cell_size, 0);
}

Array AIProximityGrid2D::query_nearest_batch(const PackedVector2Array &p_positions,
		const PackedInt32Array &p_source_indices, double p_radius,
		double p_cell_size, int p_max_neighbors) const {
	if (p_max_neighbors < 1 || p_max_neighbors > 64) {
		return Array();
	}
	return _query_impl(p_positions, p_source_indices, p_radius, p_cell_size, p_max_neighbors);
}

PackedVector2Array AIProximityGrid2D::query_separation_batch(const PackedVector2Array &p_positions,
		const PackedInt32Array &p_source_indices, double p_radius,
		double p_cell_size, int p_max_neighbors) const {
	PackedVector2Array result;
	// A zero separation radius has no steering direction and must not allow
	// division by zero. _query_impl atomically validates all other inputs,
	// including the source indices and the 8192/1024/64 resource limits.
	if (!Math::is_finite(p_radius) || p_radius <= 0.0 ||
			p_max_neighbors < 1 || p_max_neighbors > 64) {
		return result;
	}
	const Array nearest_batches = _query_impl(p_positions, p_source_indices,
			p_radius, p_cell_size, p_max_neighbors);
	if (nearest_batches.size() == 0) {
		return result;
	}
	result.resize(p_source_indices.size());
	for (int i = 0; i < p_source_indices.size(); i++) {
		const int source_index = p_source_indices[i];
		const Vector2 origin = p_positions[source_index];
		const PackedInt32Array neighbors = nearest_batches[i];
		Vector2 separation;
		for (int j = 0; j < neighbors.size(); j++) {
			const int nearby = neighbors[j];
			const Vector2 delta = origin - p_positions[nearby];
			const real_t distance = delta.length();
			if (distance <= real_t(0.0001)) {
				// Equal-position agents would otherwise receive no force.
				// Opposite signs are deterministic without using randomness.
				separation.x += source_index < nearby ? real_t(-1.0) : real_t(1.0);
			} else {
				const real_t weight = real_t(1.0) - distance / real_t(p_radius);
				separation += (delta / distance) * weight;
			}
		}
		if (separation.length_squared() > real_t(1.0)) {
			separation.normalize();
		}
		result.set(i, separation);
	}
	return result;
}

// Stateless short-horizon crowd steering: predict desired locations, use the
// existing nearest-K spatial grid, then return bounded avoidance directions.
// Prediction is not a collision check and cannot teleport or authorize a hit.
PackedVector2Array AIProximityGrid2D::query_predictive_separation_batch(
		const PackedVector2Array &p_positions, const PackedVector2Array &p_velocities,
		const PackedInt32Array &p_source_indices, double p_radius,
		double p_cell_size, int p_max_neighbors, double p_horizon) const {
	PackedVector2Array result;
	constexpr double MAX_SPEED = 50.0;
	constexpr double MAX_HORIZON = 2.0;
	if (p_positions.size() != p_velocities.size() || p_positions.is_empty() ||
			p_positions.size() > MAX_POINTS || p_source_indices.is_empty() ||
			p_source_indices.size() > MAX_SOURCES ||
			!Math::is_finite(p_horizon) || p_horizon < 0.0 || p_horizon > MAX_HORIZON ||
			!Math::is_finite(p_radius) || p_radius <= 0.0 ||
			p_max_neighbors < 1 || p_max_neighbors > 64) {
		return result;
	}
	PackedVector2Array predicted;
	predicted.resize(p_positions.size());
	for (int i = 0; i < p_positions.size(); i++) {
		const Vector2 position = p_positions[i];
		const Vector2 velocity = p_velocities[i];
		if (!position.is_finite() || !velocity.is_finite() ||
				velocity.length_squared() > real_t(MAX_SPEED * MAX_SPEED) ||
				Math::abs(position.x) > MAX_POSITION_ABS ||
				Math::abs(position.y) > MAX_POSITION_ABS) {
			return PackedVector2Array();
		}
		const double x = double(position.x) + double(velocity.x) * p_horizon;
		const double y = double(position.y) + double(velocity.y) * p_horizon;
		if (!Math::is_finite(x) || !Math::is_finite(y) ||
				Math::abs(x) > MAX_POSITION_ABS || Math::abs(y) > MAX_POSITION_ABS) {
			return PackedVector2Array();
		}
		predicted.set(i, Vector2(real_t(x), real_t(y)));
	}
	// The old static result must remain identical at horizon zero, including
	// overlapping-agent deterministic index tie breaking.
	if (p_horizon == 0.0) {
		return query_separation_batch(p_positions, p_source_indices, p_radius, p_cell_size, p_max_neighbors);
	}
	const Array nearest_batches = _query_impl(predicted, p_source_indices,
			p_radius, p_cell_size, p_max_neighbors);
	if (nearest_batches.size() != p_source_indices.size()) {
		return result; // Bad source index or cell request: reject atomically.
	}
	result.resize(p_source_indices.size());
	for (int i = 0; i < p_source_indices.size(); i++) {
		const int source_index = p_source_indices[i];
		const Vector2 center = predicted[source_index];
		const PackedInt32Array neighbors = nearest_batches[i];
		Vector2 separation;
		for (int j = 0; j < neighbors.size(); j++) {
			const int neighbor_index = neighbors[j];
			const Vector2 delta = center - predicted[neighbor_index];
			const real_t distance = delta.length();
			if (distance <= real_t(0.0001)) {
				// A head-on future overlap should sidestep, not stop or push
				// backward. Swapped agents get opposite tangential directions.
				const Vector2 relative = p_velocities[source_index] - p_velocities[neighbor_index];
				if (relative.length_squared() > real_t(0.00000001)) {
					separation += Vector2(-relative.y, relative.x).normalized();
				} else {
					// Truly coincident stationary agents use stable index ties.
					separation.x += source_index < neighbor_index ? real_t(-1.0) : real_t(1.0);
				}
			} else {
				const real_t weight = real_t(1.0) - distance / real_t(p_radius);
				separation += (delta / distance) * weight;
			}
		}
		if (separation.length_squared() > real_t(1.0)) {
			separation.normalize();
		}
		result.set(i, separation);
	}
	return result;
}

// Cross-set hashed broadphase for e.g. NPCs versus world traps.
// Outputs only candidate indices; gameplay must still validate current
// entities, expiry, allegiance and exact trigger collision after this call.
Array AIProximityGrid2D::query_cross_radius_batch(const PackedVector2Array &p_sources,
		const PackedVector2Array &p_targets, double p_radius, double p_cell_size) const {
	Array result;
	constexpr int MAX_CROSS_SOURCES = 4096;
	constexpr int MAX_CROSS_HITS = 32768;
	if (p_sources.is_empty() || p_targets.is_empty() ||
			p_sources.size() > MAX_CROSS_SOURCES || p_targets.size() > MAX_POINTS ||
			!Math::is_finite(p_radius) || p_radius < 0.0 || p_radius > MAX_QUERY_RADIUS ||
			!Math::is_finite(p_cell_size) || p_cell_size < 1.0 ||
			p_cell_size > MAX_QUERY_RADIUS || p_cell_size < p_radius) {
		return result;
	}
	// Validate the complete request before constructing the grid; no partial
	// matches or incorrect negative-cell indexing may escape on bad inputs.
	for (int i = 0; i < p_sources.size(); i++) {
		const Vector2 point = p_sources[i];
		if (!point.is_finite() || Math::abs(point.x) > MAX_POSITION_ABS ||
				Math::abs(point.y) > MAX_POSITION_ABS) {
			return Array();
		}
	}
	for (int i = 0; i < p_targets.size(); i++) {
		const Vector2 point = p_targets[i];
		if (!point.is_finite() || Math::abs(point.x) > MAX_POSITION_ABS ||
				Math::abs(point.y) > MAX_POSITION_ABS) {
			return Array();
		}
	}
	HashMap<Vector2i, Vector<int>> cells;
	for (int i = 0; i < p_targets.size(); i++) {
		const Vector2 point = p_targets[i];
		const Vector2i cell(int(Math::floor(point.x / p_cell_size)),
				int(Math::floor(point.y / p_cell_size)));
		Vector<int> *bucket = cells.getptr(cell);
		if (bucket != nullptr) {
			bucket->push_back(i);
		} else {
			Vector<int> first;
			first.push_back(i);
			cells.insert(cell, first);
		}
	}
	const double squared_radius = p_radius * p_radius;
	int total_hits = 0;
	for (int i = 0; i < p_sources.size(); i++) {
		const Vector2 center = p_sources[i];
		const Vector2i origin(int(Math::floor(center.x / p_cell_size)),
				int(Math::floor(center.y / p_cell_size)));
		Vector<int> hit_indices;
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				const Vector<int> *bucket = cells.getptr(origin + Vector2i(x, y));
				if (bucket == nullptr) {
					continue;
				}
				for (int j = 0; j < bucket->size(); j++) {
					const int target_index = (*bucket)[j];
					if (center.distance_squared_to(p_targets[target_index]) <= squared_radius) {
						hit_indices.push_back(target_index);
						if (++total_hits > MAX_CROSS_HITS) {
							return Array(); // Caller must fall back to exhaustive checks.
						}
					}
				}
			}
		}
		hit_indices.sort(); // Keep original, deterministic trap priority.
		PackedInt32Array hits;
		hits.resize(hit_indices.size());
		for (int j = 0; j < hit_indices.size(); j++) {
			hits.set(j, hit_indices[j]);
		}
		result.push_back(hits);
	}
	return result;
}

void AIProximityGrid2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("query_radius_batch", "positions", "source_indices", "radius", "cell_size"), &AIProximityGrid2D::query_radius_batch);
	ClassDB::bind_method(D_METHOD("query_nearest_batch", "positions", "source_indices", "radius", "cell_size", "max_neighbors"), &AIProximityGrid2D::query_nearest_batch);
	ClassDB::bind_method(D_METHOD("query_separation_batch", "positions", "source_indices", "radius", "cell_size", "max_neighbors"), &AIProximityGrid2D::query_separation_batch);
	ClassDB::bind_method(D_METHOD("query_cross_radius_batch", "sources", "targets", "radius", "cell_size"), &AIProximityGrid2D::query_cross_radius_batch);
	ClassDB::bind_method(D_METHOD("query_predictive_separation_batch", "positions", "velocities", "source_indices", "radius", "cell_size", "max_neighbors", "horizon"), &AIProximityGrid2D::query_predictive_separation_batch);
}
