/**************************************************************************/
/*  pcg_spatial_filter_2d.cpp                                               */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_spatial_filter_2d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"

#include <algorithm>

void PCGSpatialFilter2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("filter_indices", "candidates", "min_spacing", "max_selected"),
			&PCGSpatialFilter2D::filter_indices, DEFVAL(MAX_SELECTED));
	ClassDB::bind_method(D_METHOD("filter_indices_scaled", "candidates", "scales", "min_spacing", "max_selected", "largest_first"),
			&PCGSpatialFilter2D::filter_indices_scaled, DEFVAL(MAX_SELECTED), DEFVAL(true));
}

PackedInt32Array PCGSpatialFilter2D::filter_indices(const PackedVector2Array &p_candidates,
		double p_min_spacing, int p_max_selected) const {
	PackedInt32Array result;
	if (p_candidates.size() > MAX_CANDIDATES || p_max_selected < 0 ||
			p_max_selected > MAX_SELECTED || !Math::is_finite(p_min_spacing) ||
			p_min_spacing < 0.0 || p_min_spacing > MAX_SPACING ||
			(p_min_spacing > 0.0 && p_min_spacing < MIN_SPACING)) {
		return result;
	}
	// Check every candidate before returning any indices; later NaNs and
	// out-of-range world cells must not cause partial visual placement.
	for (const Vector2 &point : p_candidates) {
		if (!point.is_finite() ||
				Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE) {
			return result;
		}
	}
	if (p_max_selected == 0) {
		return result;
	}
	if (p_min_spacing == 0.0) {
		for (int i = 0; i < MIN(p_candidates.size(), p_max_selected); ++i) {
			result.push_back(i);
		}
		return result;
	}

	const double spacing_squared = p_min_spacing * p_min_spacing;
	HashMap<Vector2i, Vector<int>> cells;
	for (int i = 0; i < p_candidates.size() && result.size() < p_max_selected; ++i) {
		const Vector2 point = p_candidates[i];
		// MIN_SPACING and MAX_COORDINATE keep the floor/cell range well
		// inside signed 32-bit bounds, including neighboring cells.
		const Vector2i key(int32_t(Math::floor(double(point.x) / p_min_spacing)),
				int32_t(Math::floor(double(point.y) / p_min_spacing)));
		bool blocked = false;
		for (int y = -1; y <= 1 && !blocked; ++y) {
			for (int x = -1; x <= 1 && !blocked; ++x) {
				const Vector<int> *neighbors = cells.getptr(key + Vector2i(x, y));
				if (neighbors == nullptr) {
					continue;
				}
				for (const int index : *neighbors) {
					const Vector2 other = p_candidates[index];
					const double dx = double(point.x) - double(other.x);
					const double dy = double(point.y) - double(other.y);
					if (dx * dx + dy * dy < spacing_squared) {
						blocked = true;
						break;
					}
				}
			}
		}
		if (blocked) {
			continue;
		}
		result.push_back(i);
		Vector<int> *bucket = cells.getptr(key);
		if (bucket == nullptr) {
			cells.insert(key, Vector<int>());
			bucket = cells.getptr(key);
		}
		bucket->push_back(i);
	}
	return result;
}


PackedInt32Array PCGSpatialFilter2D::filter_indices_scaled(const PackedVector2Array &p_candidates,
		const PackedFloat32Array &p_scales, double p_min_spacing, int p_max_selected, bool p_largest_first) const {
	PackedInt32Array result;
	if (p_candidates.size() != p_scales.size() || p_candidates.size() > MAX_CANDIDATES ||
			p_max_selected < 0 || p_max_selected > MAX_SELECTED ||
			!Math::is_finite(p_min_spacing) || p_min_spacing < 0.0 ||
			p_min_spacing > MAX_SPACING ||
			(p_min_spacing > 0.0 && p_min_spacing < MIN_SPACING)) {
		return result;
	}

	// Reject the entire request before choosing any point. Bound scales to
	// [0.5, 2] so all possible overlaps fit in a fixed 5x5 grid neighborhood.
	for (int i = 0; i < p_candidates.size(); ++i) {
		const Vector2 point = p_candidates[i];
		const double scale = double(p_scales[i]);
		if (!point.is_finite() || Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				!Math::is_finite(scale) || scale < 0.5 || scale > 2.0) {
			return result;
		}
	}
	if (p_max_selected == 0) {
		return result;
	}
	if (p_min_spacing == 0.0) {
		for (int i = 0; i < MIN(p_candidates.size(), p_max_selected); ++i) {
			result.push_back(i);
		}
		return result;
	}

	Vector<int> order;
	if (p_largest_first) {
		order.resize(p_candidates.size());
		for (int i = 0; i < order.size(); ++i) {
			order.write[i] = i;
		}
		if (order.size() > 1) {
			std::sort(order.ptrw(), order.ptrw() + order.size(), [&p_scales](int a, int b) {
				if (p_scales[a] == p_scales[b]) {
					return a < b;
				}
				return p_scales[a] > p_scales[b];
			});
		}
	}

	HashMap<Vector2i, Vector<int>> cells;
	for (int visit = 0; visit < p_candidates.size() && result.size() < p_max_selected; ++visit) {
		const int index = p_largest_first ? order[visit] : visit;
		const Vector2 point = p_candidates[index];
		const Vector2i key(int32_t(Math::floor(double(point.x) / p_min_spacing)),
				int32_t(Math::floor(double(point.y) / p_min_spacing)));
		bool blocked = false;
		for (int y = -2; y <= 2 && !blocked; ++y) {
			for (int x = -2; x <= 2 && !blocked; ++x) {
				const Vector<int> *neighbors = cells.getptr(key + Vector2i(x, y));
				if (neighbors == nullptr) {
					continue;
				}
				for (const int other_index : *neighbors) {
					const Vector2 other = p_candidates[other_index];
					const double min_distance = p_min_spacing *
							(double(p_scales[index]) + double(p_scales[other_index])) * 0.5;
					const double dx = double(point.x) - double(other.x);
					const double dy = double(point.y) - double(other.y);
					if (dx * dx + dy * dy < min_distance * min_distance) {
						blocked = true;
						break;
					}
				}
			}
		}
		if (blocked) {
			continue;
		}
		result.push_back(index);
		Vector<int> *bucket = cells.getptr(key);
		if (bucket == nullptr) {
			cells.insert(key, Vector<int>());
			bucket = cells.getptr(key);
		}
		bucket->push_back(index);
	}
	if (p_largest_first) {
		result.sort(); // Stable original candidate ordering for MultiMesh use.
	}
	return result;
}
