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

#include <algorithm>

void PCGSpatialFilter3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("filter_indices", "candidates", "min_spacing", "max_selected"),
			&PCGSpatialFilter3D::filter_indices, DEFVAL(MAX_SELECTED));
	ClassDB::bind_method(D_METHOD("filter_indices_scaled", "candidates", "scales", "min_spacing", "max_selected", "largest_first"),
			&PCGSpatialFilter3D::filter_indices_scaled, DEFVAL(MAX_SELECTED), DEFVAL(true));
	ClassDB::bind_method(D_METHOD("filter_indices_excluding", "candidates", "exclusion_centers", "exclusion_radii", "min_spacing", "max_selected"),
			&PCGSpatialFilter3D::filter_indices_excluding, DEFVAL(MAX_SELECTED));
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


PackedInt32Array PCGSpatialFilter3D::filter_indices_scaled(const PackedVector3Array &p_candidates,
		const PackedFloat32Array &p_scales, double p_min_spacing, int p_max_selected, bool p_largest_first) const {
	PackedInt32Array result;
	if (p_candidates.size() != p_scales.size() || p_candidates.size() > MAX_CANDIDATES ||
			p_max_selected < 0 || p_max_selected > MAX_SELECTED ||
			!Math::is_finite(p_min_spacing) || p_min_spacing < 0.0 ||
			p_min_spacing > MAX_SPACING ||
			(p_min_spacing > 0.0 && p_min_spacing < MIN_SPACING)) {
		return result;
	}

	// Validate the entire input before admitting any point into a scene.
	for (int i = 0; i < p_candidates.size(); ++i) {
		const Vector3 point = p_candidates[i];
		const double scale = double(p_scales[i]);
		if (!point.is_finite() || Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				Math::abs(double(point.z)) > MAX_COORDINATE ||
				!Math::is_finite(scale) || scale < 0.5 || scale > 2.0) {
			return result;
		}
	}
	if (p_max_selected == 0) {
		return result;
	}
	// Disabled pruning retains the first N candidates, not size order.
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
				return p_scales[a] > p_scales[b] || (p_scales[a] == p_scales[b] && a < b);
			});
		}
	}
	HashMap<Vector3i, Vector<int>> cells;
	for (int visit = 0; visit < p_candidates.size() && result.size() < p_max_selected; ++visit) {
		const int index = p_largest_first ? order[visit] : visit;
		const Vector3 point = p_candidates[index];
		const Vector3i key(int32_t(Math::floor(double(point.x) / p_min_spacing)),
				int32_t(Math::floor(double(point.y) / p_min_spacing)),
				int32_t(Math::floor(double(point.z) / p_min_spacing)));
		bool blocked = false;
		// The maximum radius is 2*spacing, so 5x5x5 buckets cover
		// every possible overlap, including vertical stacks and negatives.
		for (int z = -2; z <= 2 && !blocked; ++z) {
			for (int y = -2; y <= 2 && !blocked; ++y) {
				for (int x = -2; x <= 2 && !blocked; ++x) {
					const Vector<int> *nearby = cells.getptr(key + Vector3i(x, y, z));
					if (nearby == nullptr) {
						continue;
					}
					for (const int other_index : *nearby) {
						const Vector3 other = p_candidates[other_index];
						const double separation = p_min_spacing *
								(double(p_scales[index]) + double(p_scales[other_index])) * 0.5;
						const double dx = double(point.x) - double(other.x);
						const double dy = double(point.y) - double(other.y);
						const double dz = double(point.z) - double(other.z);
						if (dx * dx + dy * dy + dz * dz < separation * separation) {
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
		result.push_back(index);
		Vector<int> *bucket = cells.getptr(key);
		if (bucket == nullptr) {
			cells.insert(key, Vector<int>());
			bucket = cells.getptr(key);
		}
		bucket->push_back(index);
	}
	if (p_largest_first) {
		result.sort(); // Preserve original MultiMesh transform order.
	}
	return result;
}


PackedInt32Array PCGSpatialFilter3D::filter_indices_excluding(
		const PackedVector3Array &p_candidates, const PackedVector3Array &p_exclusion_centers,
		const PackedFloat64Array &p_exclusion_radii, double p_min_spacing,
		int p_max_selected) const {
	PackedInt32Array empty;
	const int zone_count = p_exclusion_centers.size();
	if (p_candidates.size() > MAX_CANDIDATES || zone_count != p_exclusion_radii.size() ||
			zone_count > MAX_EXCLUSION_ZONES || p_max_selected < 0 ||
			p_max_selected > MAX_SELECTED || !Math::is_finite(p_min_spacing) ||
			p_min_spacing < 0.0 || p_min_spacing > MAX_SPACING ||
			(p_min_spacing > 0.0 && p_min_spacing < MIN_SPACING)) {
		return empty;
	}

	// Validate *all* candidates, including points that would be excluded.
	// A malformed late point cannot silently become valid due to masking.
	for (const Vector3 &point : p_candidates) {
		if (!point.is_finite() || Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				Math::abs(double(point.z)) > MAX_COORDINATE) {
			return empty;
		}
	}
	Vector<double> radius_squared;
	radius_squared.resize(zone_count);
	for (int i = 0; i < zone_count; ++i) {
		const Vector3 center = p_exclusion_centers[i];
		const double radius = p_exclusion_radii[i];
		if (!center.is_finite() || Math::abs(double(center.x)) > MAX_COORDINATE ||
				Math::abs(double(center.y)) > MAX_COORDINATE ||
				Math::abs(double(center.z)) > MAX_COORDINATE ||
				!Math::is_finite(radius) || radius < 0.0 || radius > MAX_SPACING) {
			return empty;
		}
		radius_squared.write[i] = radius * radius;
	}
	if (p_max_selected == 0) {
		return empty;
	}

	// O(N * zones) prefilter with at most 128 zones. Reuse the existing
	// O(N) expected spatial-hash thinning and map indices back to source
	// candidates. No scene nodes, physics or callbacks are ever touched.
	PackedVector3Array eligible;
	PackedInt32Array original_indices;
	for (int i = 0; i < p_candidates.size(); ++i) {
		const Vector3 point = p_candidates[i];
		bool excluded = false;
		for (int zone = 0; zone < zone_count; ++zone) {
			const Vector3 center = p_exclusion_centers[zone];
			const double dx = double(point.x) - double(center.x);
			const double dy = double(point.y) - double(center.y);
			const double dz = double(point.z) - double(center.z);
			if (dx * dx + dy * dy + dz * dz <= radius_squared[zone]) {
				excluded = true;
				break;
			}
		}
		if (!excluded) {
			eligible.push_back(point);
			original_indices.push_back(i);
		}
	}
	const PackedInt32Array local = filter_indices(eligible, p_min_spacing, p_max_selected);
	PackedInt32Array result;
	result.resize(local.size());
	for (int i = 0; i < local.size(); ++i) {
		result.set(i, original_indices[local[i]]);
	}
	return result;
}
