/**************************************************************************/
/*  pcg_foliage_scalability_3d.cpp                                          */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_foliage_scalability_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void PCGFoliageScalability3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("spread_indices", "count"),
			&PCGFoliageScalability3D::spread_indices);
	ClassDB::bind_method(D_METHOD("plan_visible_counts", "counts", "distances",
					"quality", "near_distance", "far_distance"),
			&PCGFoliageScalability3D::plan_visible_counts, DEFVAL(18.0), DEFVAL(125.0));
}

PackedInt32Array PCGFoliageScalability3D::spread_indices(int p_count) const {
	PackedInt32Array result;
	if (p_count < 0 || p_count > MAX_INSTANCES_PER_CLUSTER) {
		return result;
	}
	int bits = 0;
	int padded = 1;
	while (padded < p_count) {
		padded <<= 1;
		++bits;
	}
	result.resize(p_count);
	int output = 0;
	for (int slot = 0; slot < padded; ++slot) {
		int source = 0;
		for (int bit = 0; bit < bits; ++bit) {
			source = (source << 1) | ((slot >> bit) & 1);
		}
		if (source < p_count) {
			result.set(output++, source);
		}
	}
	return result;
}

PackedInt32Array PCGFoliageScalability3D::plan_visible_counts(
		const PackedInt32Array &p_counts, const PackedFloat32Array &p_distances,
		int p_quality, double p_near_distance, double p_far_distance) const {
	PackedInt32Array result;
	const int cluster_count = p_counts.size();
	if (cluster_count != p_distances.size() || cluster_count > MAX_CLUSTERS ||
			p_quality < 0 || p_quality > 3 ||
			!Math::is_finite(p_near_distance) || !Math::is_finite(p_far_distance) ||
			p_near_distance < 0.0 || p_near_distance >= p_far_distance ||
			p_far_distance > MAX_LOD_DISTANCE) {
		return result;
	}
	// Fully validate before emitting *any* visibility counts, so malformed
	// late clusters cannot make some groups disappear while others update.
	for (int i = 0; i < cluster_count; ++i) {
		if (p_counts[i] < 0 || p_counts[i] > MAX_INSTANCES_PER_CLUSTER ||
				!Math::is_finite(double(p_distances[i])) ||
				p_distances[i] < 0.0f ||
				double(p_distances[i]) > MAX_DISTANCE) {
			return PackedInt32Array();
		}
	}
	static constexpr double NEAR_DENSITY[4] = { 0.42, 0.68, 0.88, 1.0 };
	static constexpr double FAR_DENSITY[4] = { 0.20, 0.42, 0.70, 1.0 };
	result.resize(cluster_count);
	for (int i = 0; i < cluster_count; ++i) {
		const int count = p_counts[i];
		if (count == 0 || p_quality == 3) {
			result.set(i, count);
			continue;
		}
		const double t = Math::clamp((double(p_distances[i]) - p_near_distance) /
				(p_far_distance - p_near_distance), 0.0, 1.0);
		const double smooth = t * t * (3.0 - 2.0 * t);
		const double fraction = NEAR_DENSITY[p_quality] +
				(FAR_DENSITY[p_quality] - NEAR_DENSITY[p_quality]) * smooth;
		// Retain at least one instance in a nonempty decorative cluster.
		const int visible = MAX(1, MIN(count, int(Math::round(double(count) * fraction))));
		result.set(i, visible);
	}
	return result;
}
