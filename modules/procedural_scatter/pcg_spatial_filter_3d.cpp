/**************************************************************************/
/*  pcg_spatial_filter_3d.cpp                                               */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_spatial_filter_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"

void PCGSpatialFilter3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("filter_indices", "candidates", "min_spacing", "max_selected"),
			&PCGSpatialFilter3D::filter_indices, DEFVAL(MAX_SELECTED));
}

PackedInt32Array PCGSpatialFilter3D::filter_indices(const PackedVector3Array &p_candidates,
		double p_min_spacing, int p_max_selected) const {
	PackedInt32Array result;
	if (p_candidates.size() > MAX_CANDIDATES || p_max_selected < 0 ||
			p_max_selected > MAX_SELECTED || !Math::is_finite(p_min_spacing) ||
			p_min_spacing < 0.0 || p_min_spacing > MAX_SPACING ||
			(p_min_spacing > 0.0 && p_min_spacing < MIN_SPACING)) {
		return result;
	}
	// Validate all candidates up front; a late invalid point must never
	// produce a partially placed cosmetic batch.
	for (const Vector3 &point : p_candidates) {
		if (!point.is_finite() || Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				Math::abs(double(point.z)) > MAX_COORDINATE) {
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

	const double distance_squared = p_min_spacing * p_min_spacing;
	HashMap<Vector3i, Vector<int>> cells;
	for (int i = 0; i < p_candidates.size() && result.size() < p_max_selected; ++i) {
		const Vector3 point = p_candidates[i];
		// Bounds and minimum spacing keep cell keys, including neighbors, in int32.
		const Vector3i key(int32_t(Math::floor(double(point.x) / p_min_spacing)),
				int32_t(Math::floor(double(point.y) / p_min_spacing)),
				int32_t(Math::floor(double(point.z) / p_min_spacing)));
		bool blocked = false;
		for (int z = -1; z <= 1 && !blocked; ++z) {
			for (int y = -1; y <= 1 && !blocked; ++y) {
				for (int x = -1; x <= 1 && !blocked; ++x) {
					const Vector<int> *nearby = cells.getptr(key + Vector3i(x, y, z));
					if (nearby == nullptr) {
						continue;
					}
					for (const int index : *nearby) {
						const Vector3 other = p_candidates[index];
						const double dx = double(point.x) - double(other.x);
						const double dy = double(point.y) - double(other.y);
						const double dz = double(point.z) - double(other.z);
						if (dx * dx + dy * dy + dz * dz < distance_squared) {
							blocked = true;
							break;
						}
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
