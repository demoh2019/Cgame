/**************************************************************************/
/*  spatial_relevancy_grid_2d.cpp                                              */
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

#include "spatial_relevancy_grid_2d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void SpatialRelevancyGrid2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("rebuild", "ids", "positions"), &SpatialRelevancyGrid2D::rebuild);
	ClassDB::bind_method(D_METHOD("query_ids", "center", "radius"), &SpatialRelevancyGrid2D::query_ids);
	ClassDB::bind_method(D_METHOD("query_many", "centers", "radius"), &SpatialRelevancyGrid2D::query_many);
	ClassDB::bind_method(D_METHOD("get_stats"), &SpatialRelevancyGrid2D::get_stats);
	ClassDB::bind_method(D_METHOD("clear"), &SpatialRelevancyGrid2D::clear);
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &SpatialRelevancyGrid2D::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &SpatialRelevancyGrid2D::get_cell_size);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "8,1024,1"), "set_cell_size", "get_cell_size");
	ClassDB::bind_method(D_METHOD("set_max_indexed_radius", "radius"), &SpatialRelevancyGrid2D::set_max_indexed_radius);
	ClassDB::bind_method(D_METHOD("get_max_indexed_radius"), &SpatialRelevancyGrid2D::get_max_indexed_radius);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_indexed_radius", PROPERTY_HINT_RANGE, "64,4096,1"), "set_max_indexed_radius", "get_max_indexed_radius");
}

Vector2i SpatialRelevancyGrid2D::_cell_of(const Vector2 &p_point) const {
	return Vector2i(int32_t(Math::floor(double(p_point.x) / cell_size)),
			int32_t(Math::floor(double(p_point.y) / cell_size)));
}

bool SpatialRelevancyGrid2D::_safe_cell(const Vector2 &p_point) const {
	// Leave headroom for center +/- radius before casting into Vector2i.
	const double safe_limit = (double(INT32_MAX) - 4096.0) * cell_size;
	return p_point.is_finite() &&
			Math::abs(double(p_point.x)) + max_indexed_radius < safe_limit &&
			Math::abs(double(p_point.y)) + max_indexed_radius < safe_limit;
}

void SpatialRelevancyGrid2D::_reindex() {
	buckets.clear();
	indexed_mode = entries.size() > 8;
	if (!indexed_mode) {
		return;
	}
	for (const Entry &entry : entries) {
		if (!_safe_cell(entry.position)) {
			// Out-of-range finite coordinates remain queryable by linear scan.
			indexed_mode = false;
			return;
		}
	}
	for (int i = 0; i < entries.size(); i++) {
		const Vector2i key = _cell_of(entries[i].position);
		Vector<int> *list = buckets.getptr(key);
		if (list == nullptr) {
			buckets.insert(key, Vector<int>());
			list = buckets.getptr(key);
		}
		list->push_back(i);
	}
}

bool SpatialRelevancyGrid2D::rebuild(const PackedInt64Array &p_ids, const PackedVector2Array &p_positions) {
	clear();
	if (p_ids.size() != p_positions.size() || p_ids.size() > 65536) {
		return false;
	}
	HashSet<int64_t> seen;
	for (int i = 0; i < p_ids.size(); i++) {
		if (!p_positions[i].is_finite() || seen.has(p_ids[i])) {
			// Refuse partial indices; the caller can use its exact legacy scan.
			clear();
			return false;
		}
		seen.insert(p_ids[i]);
		Entry entry;
		entry.id = p_ids[i];
		entry.position = p_positions[i];
		entries.push_back(entry);
	}
	_reindex();
	rebuild_count++;
	return true;
}

PackedInt64Array SpatialRelevancyGrid2D::query_ids(const Vector2 &p_center, double p_radius) {
	PackedInt64Array result;
	if (!p_center.is_finite() || !Math::is_finite(p_radius) || p_radius < 0.0) {
		return result;
	}
	query_count++;
	const double squared_radius = p_radius * p_radius;
	if (!indexed_mode || p_radius > max_indexed_radius || !_safe_cell(p_center)) {
		fallback_scans++;
		for (const Entry &entry : entries) {
			candidate_checks++;
			const double d = double(p_center.distance_squared_to(entry.position));
			if (d <= squared_radius) {
				result.push_back(entry.id);
			}
		}
		return result;
	}

	const Vector2 delta(p_radius, p_radius);
	const Vector2i lower = _cell_of(p_center - delta);
	const Vector2i upper = _cell_of(p_center + delta);
	Vector<int> indices;
	for (int64_t y = lower.y; y <= upper.y; y++) {
		for (int64_t x = lower.x; x <= upper.x; x++) {
			bucket_lookups++;
			const Vector<int> *bucket = buckets.getptr(Vector2i(int32_t(x), int32_t(y)));
			if (bucket == nullptr) {
				continue;
			}
			for (const int index : *bucket) {
				candidate_checks++;
				const double d = double(p_center.distance_squared_to(entries[index].position));
				if (d <= squared_radius) {
					indices.push_back(index);
				}
			}
		}
	}
	// Hash buckets are intentionally unordered. Restore source input order
	// so replicated actor arrays match the previous server traversal exactly.
	indices.sort();
	for (const int index : indices) {
		result.push_back(entries[index].id);
	}
	return result;
}

Array SpatialRelevancyGrid2D::query_many(const PackedVector2Array &p_centers, double p_radius) {
	// Defensively cap the number of per-connection arrays allocated in one
	// call. An empty result signals failure to the caller, which must use
	// the existing full-scan fallback rather than omit replicated actors.
	if (p_centers.size() > 4096 ||
			int64_t(p_centers.size()) * int64_t(entries.size()) > 2097152) {
		return Array();
	}
	batch_calls++;
	batch_viewers += p_centers.size();
	Array results;
	for (int i = 0; i < p_centers.size(); i++) {
		// Keep the established scalar method as the sole authority for
		// radius boundaries, invalid data and source ordering.
		results.push_back(query_ids(p_centers[i], p_radius));
	}
	return results;
}

Dictionary SpatialRelevancyGrid2D::get_stats() const {
	Dictionary result;
	result["entities"] = entries.size();
	result["cells"] = buckets.size();
	result["rebuilds"] = rebuild_count;
	result["queries"] = query_count;
	result["batch_calls"] = batch_calls;
	result["batch_viewers"] = batch_viewers;
	result["candidates"] = candidate_checks;
	result["buckets"] = bucket_lookups;
	result["fallback_scans"] = fallback_scans;
	result["indexed_mode"] = indexed_mode;
	return result;
}

void SpatialRelevancyGrid2D::set_cell_size(double p_size) {
	ERR_FAIL_COND(!Math::is_finite(p_size) || p_size < 8.0 || p_size > 1024.0);
	if (cell_size != p_size) {
		cell_size = p_size;
		_reindex();
	}
}

void SpatialRelevancyGrid2D::set_max_indexed_radius(double p_radius) {
	ERR_FAIL_COND(!Math::is_finite(p_radius) || p_radius < 64.0 || p_radius > 4096.0);
	if (max_indexed_radius != p_radius) {
		max_indexed_radius = p_radius;
		_reindex();
	}
}

void SpatialRelevancyGrid2D::clear() {
	entries.clear();
	buckets.clear();
	indexed_mode = false;
	query_count = 0;
	batch_calls = 0;
	batch_viewers = 0;
	candidate_checks = 0;
	bucket_lookups = 0;
	fallback_scans = 0;
}
