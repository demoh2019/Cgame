/**************************************************************************/
/*  test_pcg_instance_cluster_3d.h                                          */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_instance_cluster_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGInstanceCluster3D {

TEST_CASE("[PCGInstanceCluster3D] sparse inputs stay one draw call") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	CHECK(planner->partition_indices(PackedVector3Array()).size() == 0);
	PackedVector3Array points;
	points.push_back(Vector3(0, 0, 0));
	points.push_back(Vector3(128, 64, 128));
	const Array clusters = planner->partition_indices(points);
	REQUIRE(clusters.size() == 1);
	const PackedInt32Array kept = clusters[0];
	REQUIRE(kept.size() == 2);
	CHECK(kept[0] == 0);
	CHECK(kept[1] == 1);
}

TEST_CASE("[PCGInstanceCluster3D] three-dimensional groups preserve input order") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	PackedVector3Array points;
	for (int i = 0; i < 24; ++i) {
		points.push_back(Vector3(3, 0, 7));
		points.push_back(Vector3(3, 75, 7));
		points.push_back(Vector3(-5, 0, 7));
		points.push_back(Vector3(-5, 75, 7));
	}
	const PackedVector3Array source = points;
	const Array clusters = planner->partition_indices(points, 32.0, 48, 16);
	REQUIRE(clusters.size() == 4);
	int expected_cluster = 0;
	int visited = 0;
	for (int c = 0; c < clusters.size(); ++c) {
		const PackedInt32Array indices = clusters[c];
		CHECK(indices.size() == 24);
		for (int k = 0; k < indices.size(); ++k) {
			CHECK(indices[k] == c + k * 4);
			++visited;
		}
		++expected_cluster;
	}
	CHECK(expected_cluster == 4);
	CHECK(visited == points.size());
	CHECK(points == source);
	CHECK(planner->partition_indices(points, 32.0, 48, 16) == clusters);
}

TEST_CASE("[PCGInstanceCluster3D] bounded clusters fall back to unsplit batch") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	PackedVector3Array points;
	for (int i = 0; i < 96; ++i) {
		points.push_back(Vector3(i * 33.0, 0, 0));
	}
	const Array limited = planner->partition_indices(points, 32.0, 48, 4);
	REQUIRE(limited.size() == 1);
	const PackedInt32Array indices = limited[0];
	REQUIRE(indices.size() == points.size());
	for (int i = 0; i < indices.size(); ++i) {
		CHECK(indices[i] == i);
	}
	const Array normal = planner->partition_indices(points, 32.0, 48, 128);
	CHECK(normal.size() == points.size());
}

TEST_CASE("[PCGInstanceCluster3D] invalid parameters or points fail atomically") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	PackedVector3Array points;
	points.push_back(Vector3(0, 0, 0));
	points.push_back(Vector3(33, 0, 0));
	CHECK(planner->partition_indices(points, 0.1).is_empty());
	CHECK(planner->partition_indices(points, Math::NaN).is_empty());
	CHECK(planner->partition_indices(points, Math::INF).is_empty());
	CHECK(planner->partition_indices(points, 10001).is_empty());
	CHECK(planner->partition_indices(points, 32.0, 0).is_empty());
	CHECK(planner->partition_indices(points, 32.0, 65537).is_empty());
	CHECK(planner->partition_indices(points, 32.0, 1, 0).is_empty());
	CHECK(planner->partition_indices(points, 32.0, 1, 257).is_empty());
	points.push_back(Vector3(0, Math::NaN, 0));
	CHECK(planner->partition_indices(points, 32.0, 1).is_empty());
	points.remove_at(2);
	points.push_back(Vector3(0, 0, 10000001));
	CHECK(planner->partition_indices(points, 32.0, 1).is_empty());
	points.resize(65537);
	CHECK(planner->partition_indices(points, 32.0, 1).is_empty());
}

TEST_CASE("[PCGInstanceCluster3D] adaptive overflow coarsens instead of collapsing the scene") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	PackedVector3Array positions;
	for (int i = 0; i < 80; ++i) {
		positions.push_back(Vector3(i * 33.0, 0, 0));
	}
	// The existing strict API retains its original behavior.
	CHECK(planner->partition_indices(positions, 32.0, 48, 3).size() == 1);
	const Array groups = planner->partition_indices_adaptive(positions, 32.0, 48, 3);
	REQUIRE(groups.size() == 3);
	const PackedInt32Array first = groups[0];
	const PackedInt32Array second = groups[1];
	const PackedInt32Array third = groups[2];
	REQUIRE(first.size() == 32);
	REQUIRE(second.size() == 31);
	REQUIRE(third.size() == 17);
	for (int i = 0; i < 80; ++i) {
		const PackedInt32Array group = groups[i < 32 ? 0 : (i < 63 ? 1 : 2)];
		const int local_index = i < 32 ? i : (i < 63 ? i - 32 : i - 63);
		CHECK(group[local_index] == i);
	}
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 48, 3) == groups);
	// Zero retries preserves the old safety fallback instead of exceeding budget.
	const Array no_retry = planner->partition_indices_adaptive(positions, 32.0, 48, 3, 0);
	REQUIRE(no_retry.size() == 1);
	const PackedInt32Array unsplit = no_retry[0];
	REQUIRE(unsplit.size() == positions.size());
	CHECK(unsplit[79] == 79);
}

TEST_CASE("[PCGInstanceCluster3D] adaptive retains legacy results when under budget") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	PackedVector3Array positions;
	for (int i = 0; i < 80; ++i) {
		positions.push_back(Vector3(i % 2 == 0 ? -4 : 4, i % 2 == 0 ? 0 : 75, 4));
	}
	const Array fixed = planner->partition_indices(positions, 32.0, 48, 4);
	CHECK(fixed.size() == 2);
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 48, 4) == fixed);
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 100, 4).size() == 1);
}

TEST_CASE("[PCGInstanceCluster3D] adaptive retries and invalid inputs are strictly bounded") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	PackedVector3Array positions;
	for (int i = 0; i < 80; ++i) {
		positions.push_back(Vector3(i * 33.0, 0, 0));
	}
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 48, 3, -1).is_empty());
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 48, 3, 9).is_empty());
	CHECK(planner->partition_indices_adaptive(positions, Math::NaN, 48, 3).is_empty());
	CHECK(planner->partition_indices_adaptive(positions, 0.05, 48, 3).is_empty());
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 48, 0).is_empty());
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 48, 257).is_empty());
	const Array few_retries = planner->partition_indices_adaptive(positions, 32.0, 48, 3, 1);
	REQUIRE(few_retries.size() == 1);
	const PackedInt32Array few_indices = few_retries[0];
	CHECK(few_indices.size() == 80);
	positions.push_back(Vector3(0, Math::NaN, 0));
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 48, 3).is_empty());
	positions.remove_at(80);
	positions.push_back(Vector3(10000001, 0, 0));
	CHECK(planner->partition_indices_adaptive(positions, 32.0, 48, 3).is_empty());
	positions.resize(0);
	CHECK(planner->partition_indices_adaptive(positions).is_empty());
}

TEST_CASE("[PCGInstanceCluster3D] anchor bounds are exact, ordered and 3D height-aware") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	const PackedVector3Array points = {
		Vector3(-4, 0, -3), Vector3(4, 2, 2),
		Vector3(0, 75, 0), Vector3(2, 76, 5)
	};
	const Array clusters = {
		PackedInt32Array({ 0, 1 }), PackedInt32Array({ 2, 3 })
	};
	const Array bounds = planner->compute_cluster_bounds(points, clusters);
	REQUIRE(bounds.size() == 2);
	const AABB low = bounds[0];
	const AABB high = bounds[1];
	CHECK(low.position == Vector3(-4, 0, -3));
	CHECK(low.size == Vector3(8, 2, 5));
	CHECK(high.position == Vector3(0, 75, 0));
	CHECK(high.size == Vector3(2, 1, 5));
	CHECK(low.get_end().y < high.position.y);
	CHECK(planner->compute_cluster_bounds(points, clusters) == bounds);
	const Array padded = planner->compute_cluster_bounds(points, clusters, 0.6);
	REQUIRE(padded.size() == 2);
	const AABB padded_low = padded[0];
	CHECK(padded_low.position.distance_to(Vector3(-4.6, -0.6, -3.6)) < 0.00001);
	CHECK(padded_low.size.distance_to(Vector3(9.2, 3.2, 6.2)) < 0.00001);
	CHECK(points[0] == Vector3(-4, 0, -3)); // Caller-owned points unchanged.
}

TEST_CASE("[PCGInstanceCluster3D] computed bounds match adaptive clustering and cover all points") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	PackedVector3Array points;
	for (int i = 0; i < 80; ++i) {
		points.push_back(Vector3(i * 33.0, i % 2 == 0 ? 0.0 : 75.0, i % 5));
	}
	const Array groups = planner->partition_indices_adaptive(points, 32.0, 48, 5);
	REQUIRE(groups.size() > 1);
	const Array bounds = planner->compute_cluster_bounds(points, groups, 0.25);
	REQUIRE(bounds.size() == groups.size());
	int visited = 0;
	for (int g = 0; g < groups.size(); ++g) {
		const AABB group_bounds = bounds[g];
		const PackedInt32Array ids = groups[g];
		for (int index : ids) {
			CHECK(group_bounds.has_point(points[index]));
			++visited;
		}
	}
	CHECK(visited == points.size());
	const Array single = planner->compute_cluster_bounds(points,
			planner->partition_indices(points, 32.0, 48, 1));
	REQUIRE(single.size() == 1);
	const AABB aggregate = single[0];
	CHECK(aggregate.position == points[0]);
	CHECK(aggregate.get_end().x == points[79].x);
	CHECK(aggregate.position.y <= points[0].y);
	CHECK(aggregate.get_end().y >= points[79].y);
}

TEST_CASE("[PCGInstanceCluster3D] cluster bounds validate complete exact-cover partitions") {
	Ref<PCGInstanceCluster3D> planner;
	planner.instantiate();
	const PackedVector3Array points = {
		Vector3(0, 0, 0), Vector3(2, 0, 1), Vector3(4, 0, 2)
	};
	const Array groups = {
		PackedInt32Array({ 0, 2 }), PackedInt32Array({ 1 })
	};
	CHECK(planner->compute_cluster_bounds({}, {}).is_empty());
	CHECK(planner->compute_cluster_bounds(points, groups).size() == 2);
	CHECK(planner->compute_cluster_bounds(points, {}).is_empty());
	CHECK(planner->compute_cluster_bounds({}, groups).is_empty());
	CHECK(planner->compute_cluster_bounds(points, { PackedInt32Array({ 0, 1 }) }).is_empty());
	CHECK(planner->compute_cluster_bounds(points,
			{ PackedInt32Array({ 0, 1, 1, 2 }) }).is_empty());
	CHECK(planner->compute_cluster_bounds(points,
			{ PackedInt32Array({ 0, 1 }), PackedInt32Array({ 1, 2 }) }).is_empty());
	CHECK(planner->compute_cluster_bounds(points,
			{ PackedInt32Array({ 0, 1, 3 }) }).is_empty());
	CHECK(planner->compute_cluster_bounds(points,
			{ PackedInt32Array({ -1, 0, 1, 2 }) }).is_empty());
	CHECK(planner->compute_cluster_bounds(points,
			{ PackedInt32Array({ 0, 1, 2 }), PackedInt32Array() }).is_empty());
	CHECK(planner->compute_cluster_bounds(points, { 7, groups[0] }).is_empty());
	CHECK(planner->compute_cluster_bounds(points, groups, -1.0).is_empty());
	CHECK(planner->compute_cluster_bounds(points, groups, Math::NaN).is_empty());
	CHECK(planner->compute_cluster_bounds(points, groups, 10001.0).is_empty());
	const PackedVector3Array bad_point = {
		Vector3(0, 0, 0), Vector3(Math::INF, 0, 1), Vector3(4, 0, 2)
	};
	CHECK(planner->compute_cluster_bounds(bad_point, groups).is_empty());
	const PackedVector3Array out_of_range = {
		Vector3(0, 0, 0), Vector3(2, 0, 1), Vector3(0, 0, 10000001)
	};
	CHECK(planner->compute_cluster_bounds(out_of_range, groups).is_empty());
	PackedVector3Array huge;
	huge.resize(65537);
	CHECK(planner->compute_cluster_bounds(huge, {}).is_empty());
	// Limit 256 clusters even when individual groups are otherwise well-formed.
	PackedVector3Array many_points;
	Array many_groups;
	for (int i = 0; i < 257; ++i) {
		many_points.push_back(Vector3(i, 0, 0));
		many_groups.push_back(PackedInt32Array({ i }));
	}
	CHECK(planner->compute_cluster_bounds(many_points, many_groups).is_empty());
}

} // namespace TestPCGInstanceCluster3D
