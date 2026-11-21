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

void PCGSpatialFilter2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("filter_indices", "candidates", "min_spacing", "max_selected"),
			&PCGSpatialFilter2D::filter_indices, DEFVAL(MAX_SELECTED));
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
