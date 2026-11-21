/**************************************************************************/
/*  spatial_point_grid_2d.cpp                                              */
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

#include "spatial_point_grid_2d.h"

#include "core/object/class_db.h"
#include "core/math/math_funcs.h"

void SpatialPointGrid2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &SpatialPointGrid2D::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &SpatialPointGrid2D::get_cell_size);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,4096,1"), "set_cell_size", "get_cell_size");

	ClassDB::bind_method(D_METHOD("set_direct_scan_threshold", "threshold"), &SpatialPointGrid2D::set_direct_scan_threshold);
	ClassDB::bind_method(D_METHOD("get_direct_scan_threshold"), &SpatialPointGrid2D::get_direct_scan_threshold);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "direct_scan_threshold", PROPERTY_HINT_RANGE, "0,1024,1"), "set_direct_scan_threshold", "get_direct_scan_threshold");

	ClassDB::bind_method(D_METHOD("set_max_indexed_radius", "radius"), &SpatialPointGrid2D::set_max_indexed_radius);
	ClassDB::bind_method(D_METHOD("get_max_indexed_radius"), &SpatialPointGrid2D::get_max_indexed_radius);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_indexed_radius", PROPERTY_HINT_RANGE, "1,16384,1"), "set_max_indexed_radius", "get_max_indexed_radius");

	ClassDB::bind_method(D_METHOD("rebuild", "positions"), &SpatialPointGrid2D::rebuild);
	ClassDB::bind_method(D_METHOD("any_within", "point", "radius", "inclusive"), &SpatialPointGrid2D::any_within, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("any_within_batch", "points", "radius", "inclusive"), &SpatialPointGrid2D::any_within_batch, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("snapshot"), &SpatialPointGrid2D::snapshot);
	ClassDB::bind_method(D_METHOD("get_point_count"), &SpatialPointGrid2D::get_point_count);
	ClassDB::bind_method(D_METHOD("clear"), &SpatialPointGrid2D::clear);
}

Vector2i SpatialPointGrid2D::_cell_of(const Vector2 &p_point, real_t p_cell_size) {
	return Vector2i(int32_t(Math::floor(p_point.x / p_cell_size)),
			int32_t(Math::floor(p_point.y / p_cell_size)));
}

bool SpatialPointGrid2D::_safe_for_index(const Vector2 &p_point) const {
	// Queries expand coordinates by max_indexed_radius. Keep cell casts well
	// inside int32 to prevent overflow even for large finite world positions.
	const double limit = (double(INT32_MAX) - 1024.0) * double(cell_size);
	return p_point.is_finite() &&
			Math::abs(double(p_point.x)) + double(max_indexed_radius) < limit &&
			Math::abs(double(p_point.y)) + double(max_indexed_radius) < limit;
}

void SpatialPointGrid2D::_reindex() {
	cells.clear();
	indexed_mode = positions.size() > direct_scan_threshold;
	if (!indexed_mode) {
		return;
	}
	for (const Vector2 &point : positions) {
		if (!_safe_for_index(point)) {
			// No clamping: an outlier outside the integer cell domain must
			// not silently disappear from proximity queries.
			cells.clear();
			indexed_mode = false;
			return;
		}
	}
	for (const Vector2 &point : positions) {
		const Vector2i key = _cell_of(point, cell_size);
		Vector<Vector2> *bucket = cells.getptr(key);
		if (bucket == nullptr) {
			cells.insert(key, Vector<Vector2>());
			bucket = cells.getptr(key);
		}
		bucket->push_back(point);
	}
}

void SpatialPointGrid2D::set_cell_size(real_t p_cell_size) {
	ERR_FAIL_COND(!Math::is_finite(p_cell_size) || p_cell_size < real_t(1.0) || p_cell_size > real_t(4096.0));
	if (cell_size != p_cell_size) {
		cell_size = p_cell_size;
		_reindex();
	}
}

void SpatialPointGrid2D::set_direct_scan_threshold(int p_threshold) {
	ERR_FAIL_COND(p_threshold < 0 || p_threshold > 1024);
	if (direct_scan_threshold != p_threshold) {
		direct_scan_threshold = p_threshold;
		_reindex();
	}
}

void SpatialPointGrid2D::set_max_indexed_radius(real_t p_radius) {
	ERR_FAIL_COND(!Math::is_finite(p_radius) || p_radius < real_t(1.0) || p_radius > real_t(16384.0));
	if (max_indexed_radius != p_radius) {
		max_indexed_radius = p_radius;
		_reindex();
	}
}

void SpatialPointGrid2D::rebuild(const TypedArray<Vector2> &p_positions) {
	positions.clear();
	cells.clear();
	queries = 0;
	batch_calls = 0;
	candidate_checks = 0;
	bucket_lookups = 0;
	for (int i = 0; i < p_positions.size(); i++) {
		const Vector2 point = p_positions[i];
		if (point.is_finite()) {
			positions.push_back(point);
		}
	}
	_reindex();
}

void SpatialPointGrid2D::clear() {
	positions.clear();
	cells.clear();
	indexed_mode = false;
	queries = 0;
	batch_calls = 0;
	candidate_checks = 0;
	bucket_lookups = 0;
}

bool SpatialPointGrid2D::_scan(const Vector2 &p_point, real_t p_radius_squared, bool p_inclusive) {
	for (const Vector2 &candidate : positions) {
		candidate_checks++;
		const real_t distance_squared = p_point.distance_squared_to(candidate);
		if ((p_inclusive && distance_squared <= p_radius_squared) ||
				(!p_inclusive && distance_squared < p_radius_squared)) {
			return true;
		}
	}
	return false;
}

bool SpatialPointGrid2D::any_within(const Vector2 &p_point, real_t p_radius, bool p_inclusive) {
	if (!p_point.is_finite() || !Math::is_finite(p_radius) || p_radius < real_t(0.0)) {
		return false;
	}
	queries++;
	const real_t radius_squared = p_radius * p_radius;
	if (!indexed_mode || p_radius > max_indexed_radius || !_safe_for_index(p_point)) {
		return _scan(p_point, radius_squared, p_inclusive);
	}

	const Vector2 extent(p_radius, p_radius);
	const Vector2i lower = _cell_of(p_point - extent, cell_size);
	const Vector2i upper = _cell_of(p_point + extent, cell_size);
	for (int64_t y = lower.y; y <= upper.y; y++) {
		for (int64_t x = lower.x; x <= upper.x; x++) {
			bucket_lookups++;
			const Vector<Vector2> *bucket = cells.getptr(Vector2i(int32_t(x), int32_t(y)));
			if (bucket == nullptr) {
				continue;
			}
			for (const Vector2 &candidate : *bucket) {
				candidate_checks++;
				const real_t distance_squared = p_point.distance_squared_to(candidate);
				if ((p_inclusive && distance_squared <= radius_squared) ||
						(!p_inclusive && distance_squared < radius_squared)) {
					return true;
				}
			}
		}
	}
	return false;
}

PackedByteArray SpatialPointGrid2D::any_within_batch(const PackedVector2Array &p_points, real_t p_radius, bool p_inclusive) {
	// The existing scalar function is the single source of radius semantics,
	// including invalid positions, strict boundaries and large-radius fallback.
	// No special case for empty batches: stats still account for the API call.
	batch_calls++;
	PackedByteArray result;
	result.resize(p_points.size());
	const Vector2 *points = p_points.ptr();
	uint8_t *flags = result.ptrw();
	for (int i = 0; i < p_points.size(); i++) {
		flags[i] = any_within(points[i], p_radius, p_inclusive) ? uint8_t(1) : uint8_t(0);
	}
	return result;
}

Dictionary SpatialPointGrid2D::snapshot() const {
	Dictionary stats;
	stats["alive_players"] = positions.size();
	stats["occupied_cells"] = cells.size();
	stats["queries"] = queries;
	stats["batch_calls"] = batch_calls;
	stats["candidate_checks"] = candidate_checks;
	stats["bucket_lookups"] = bucket_lookups;
	stats["indexed_mode"] = indexed_mode;
	stats["native_backend"] = true;
	return stats;
}
