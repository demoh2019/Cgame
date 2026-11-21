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

void AIProximityGrid2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("query_radius_batch", "positions", "source_indices", "radius", "cell_size"), &AIProximityGrid2D::query_radius_batch);
	ClassDB::bind_method(D_METHOD("query_nearest_batch", "positions", "source_indices", "radius", "cell_size", "max_neighbors"), &AIProximityGrid2D::query_nearest_batch);
}
