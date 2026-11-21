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

} // namespace TestPCGInstanceCluster3D
