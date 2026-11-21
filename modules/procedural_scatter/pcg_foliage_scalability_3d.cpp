/**************************************************************************/
/*  pcg_foliage_scalability_3d.cpp                                          */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_foliage_scalability_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/vector.h"

void PCGFoliageScalability3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("spread_indices", "count"),
			&PCGFoliageScalability3D::spread_indices);
	ClassDB::bind_method(D_METHOD("plan_visible_counts", "counts", "distances",
					"quality", "near_distance", "far_distance"),
			&PCGFoliageScalability3D::plan_visible_counts, DEFVAL(18.0), DEFVAL(125.0));
	ClassDB::bind_method(D_METHOD("plan_visible_counts_stable", "counts", "distances",
					"previous_counts", "quality", "deadband", "near_distance", "far_distance"),
			&PCGFoliageScalability3D::plan_visible_counts_stable,
			DEFVAL(2), DEFVAL(18.0), DEFVAL(125.0));
	ClassDB::bind_method(D_METHOD("plan_instance_lods", "positions", "viewer", "previous_tiers",
					"switch_distance", "hysteresis"),
			&PCGFoliageScalability3D::plan_instance_lods, DEFVAL(24.0), DEFVAL(3.0));
	ClassDB::bind_method(D_METHOD("partition_variant_lods", "variants", "lod_tiers", "variant_count"),
			&PCGFoliageScalability3D::partition_variant_lods);
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


PackedInt32Array PCGFoliageScalability3D::plan_visible_counts_stable(
		const PackedInt32Array &p_counts, const PackedFloat32Array &p_distances,
		const PackedInt32Array &p_previous_counts, int p_quality,
		int p_deadband, double p_near_distance, double p_far_distance) const {
	const int count = p_counts.size();
	if (count != p_previous_counts.size() || count > MAX_CLUSTERS ||
			p_deadband < 0 || p_deadband > 8) {
		return PackedInt32Array();
	}
	// Validate the entire prior-state array before any result is returned.
	// -1 means no usable state (new cluster or explicit graphics tier switch).
	for (int i = 0; i < count; ++i) {
		if (p_previous_counts[i] < -1 || p_previous_counts[i] > p_counts[i]) {
			return PackedInt32Array();
		}
	}
	PackedInt32Array result = plan_visible_counts(
			p_counts, p_distances, p_quality, p_near_distance, p_far_distance);
	if (result.size() != count) {
		return PackedInt32Array(); // Existing planner owns quality/range/geometry validation.
	}
	for (int i = 0; i < count; ++i) {
		const int previous = p_previous_counts[i];
		const int desired = result[i];
		// Explicit tier switches pass -1. Zero never persists for a nonempty
		// foliage cluster, preserving at least one visible instance.
		if (previous >= 0 && (p_counts[i] == 0 || previous > 0) &&
				Math::abs(previous - desired) <= p_deadband) {
			result.set(i, previous);
		}
	}
	return result;
}

PackedInt32Array PCGFoliageScalability3D::plan_instance_lods(
		const PackedVector3Array &p_positions, const Vector3 &p_viewer,
		const PackedInt32Array &p_previous_tiers, double p_switch_distance,
		double p_hysteresis) const {
	PackedInt32Array result;
	const int count = p_positions.size();
	if (count > MAX_LOD_INSTANCES ||
			(!p_previous_tiers.is_empty() && p_previous_tiers.size() != count) ||
			!p_viewer.is_finite() ||
			Math::abs(double(p_viewer.x)) > MAX_LOD_COORDINATE ||
			Math::abs(double(p_viewer.y)) > MAX_LOD_COORDINATE ||
			Math::abs(double(p_viewer.z)) > MAX_LOD_COORDINATE ||
			!Math::is_finite(p_switch_distance) || !Math::is_finite(p_hysteresis) ||
			p_switch_distance < 0.1 || p_switch_distance > MAX_LOD_DISTANCE ||
			p_hysteresis < 0.0 || p_hysteresis >= p_switch_distance ||
			p_switch_distance + p_hysteresis > MAX_LOD_DISTANCE) {
		return result;
	}
	// Atomic input validation: a bad last position or tier must not replace
	// any part of a previously working MultiMesh allocation.
	for (int i = 0; i < count; ++i) {
		const Vector3 point = p_positions[i];
		if (!point.is_finite() ||
				Math::abs(double(point.x)) > MAX_LOD_COORDINATE ||
				Math::abs(double(point.y)) > MAX_LOD_COORDINATE ||
				Math::abs(double(point.z)) > MAX_LOD_COORDINATE) {
			return result;
		}
		if (!p_previous_tiers.is_empty() &&
				p_previous_tiers[i] != 0 && p_previous_tiers[i] != 1) {
			return result;
		}
	}
	const double switch_sq = p_switch_distance * p_switch_distance;
	const double to_far = p_switch_distance + p_hysteresis;
	const double to_near = p_switch_distance - p_hysteresis;
	const double far_sq = to_far * to_far;
	const double near_sq = to_near * to_near;
	result.resize(count);
	for (int i = 0; i < count; ++i) {
		const Vector3 point = p_positions[i];
		const double dx = double(point.x) - double(p_viewer.x);
		const double dy = double(point.y) - double(p_viewer.y);
		const double dz = double(point.z) - double(p_viewer.z);
		const double distance_sq = dx * dx + dy * dy + dz * dz;
		int tier = !p_previous_tiers.is_empty() ?
				p_previous_tiers[i] : (distance_sq > switch_sq ? 1 : 0);
		// Strict boundaries retain the previous tier to prevent thrashing.
		if (tier == 0 && distance_sq > far_sq) {
			tier = 1;
		} else if (tier == 1 && distance_sq < near_sq) {
			tier = 0;
		}
		result.set(i, tier);
	}
	return result;
}

Array PCGFoliageScalability3D::partition_variant_lods(
		const PackedInt32Array &p_variants, const PackedInt32Array &p_lod_tiers,
		int p_variant_count) const {
	Array result;
	const int count = p_variants.size();
	if (count != p_lod_tiers.size() || count > MAX_LOD_INSTANCES ||
			p_variant_count < 1 || p_variant_count > MAX_MESH_VARIANTS) {
		return result;
	}
	for (int i = 0; i < count; ++i) {
		if (p_variants[i] < 0 || p_variants[i] >= p_variant_count ||
				p_lod_tiers[i] < 0 || p_lod_tiers[i] > 1) {
			return result;
		}
	}
	Vector<Vector<int>> buckets;
	buckets.resize(p_variant_count * 2);
	for (int i = 0; i < count; ++i) {
		buckets.write[p_variants[i] * 2 + p_lod_tiers[i]].push_back(i);
	}
	for (int group_index = 0; group_index < buckets.size(); ++group_index) {
		const Vector<int> &bucket = buckets[group_index];
		PackedInt32Array indices;
		indices.resize(bucket.size());
		for (int j = 0; j < bucket.size(); ++j) {
			indices.set(j, bucket[j]);
		}
		result.push_back(indices);
	}
	return result;
}
