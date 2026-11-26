/**************************************************************************/
/*  test_environment_query_3d.h                                            */
/**************************************************************************/
/*                         This file is part of: GODOT ENGINE             */
/**************************************************************************/

#pragma once

#include "../environment_query_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestEnvironmentQuery3D {

TEST_CASE("[EnvironmentQuery3D] Top-K identities preserve duplicate candidate positions") {
	Ref<EnvironmentQuery3D> query;
	query.instantiate();
	PackedVector3Array positions;
	positions.push_back(Vector3(3, 0, 0));
	positions.push_back(Vector3(3, 0, 0)); // Distinct slot with same geometry.
	positions.push_back(Vector3(10, 0, 0));
	query->set_origin(Vector3());
	query->set_candidates(positions);
	const PackedInt32Array indices = query->query_top_indices(3);
	REQUIRE(indices.size() == 3);
	CHECK(indices[0] == 0);
	CHECK(indices[1] == 1);
	CHECK(indices[2] == 2);
	CHECK(indices == query->query_top_indices(3)); // Stable across calls.
	const PackedVector3Array ranked = query->query_top_positions(3);
	REQUIRE(ranked.size() == indices.size());
	for (int i = 0; i < indices.size(); i++) {
		CHECK(ranked[i] == positions[indices[i]]);
	}
	const Array verbose = query->query();
	REQUIRE(verbose.size() == indices.size());
	for (int i = 0; i < indices.size(); i++) {
		const Dictionary entry = verbose[i];
		CHECK(int(entry["index"]) == indices[i]);
	}
}

TEST_CASE("[EnvironmentQuery3D] Top-K indices respect score, filtering and result budget") {
	Ref<EnvironmentQuery3D> query;
	query.instantiate();
	PackedVector3Array points;
	points.push_back(Vector3(-4, 0, 0)); // Equal-distance tie to index 1.
	points.push_back(Vector3(4, 0, 0));
	points.push_back(Vector3(1, 0, 0)); // Nearest.
	points.push_back(Vector3(200, 0, 0)); // Outside default max_distance.
	query->set_candidates(points);
	const PackedInt32Array all = query->query_top_indices(4);
	REQUIRE(all.size() == 3);
	CHECK(all[0] == 2);
	CHECK(all[1] == 0);
	CHECK(all[2] == 1);
	query->set_max_results(2);
	const PackedInt32Array capped = query->query_top_indices(4);
	REQUIRE(capped.size() == 2);
	CHECK(capped[0] == 2);
	CHECK(capped[1] == 0);
	query->set_max_results(0);
	query->set_horizontal_only(true);
	query->set_direction_origin(Vector3());
	query->set_direction_axis(Vector3(1, 0, 0));
	query->set_min_direction_dot(0.0);
	query->set_use_direction(true);
	const PackedInt32Array forward = query->query_top_indices(4);
	REQUIRE(forward.size() == 2);
	CHECK(forward[0] == 2);
	CHECK(forward[1] == 1); // Negative-X candidate rejected.
	const PackedVector3Array forward_positions = query->query_top_positions(4);
	REQUIRE(forward_positions.size() == forward.size());
	for (int i = 0; i < forward.size(); i++) {
		CHECK(forward_positions[i] == points[forward[i]]);
	}
}

TEST_CASE("[EnvironmentQuery3D] Invalid Top-K counts fail without changing resource state") {
	Ref<EnvironmentQuery3D> query;
	query.instantiate();
	PackedVector3Array positions;
	positions.push_back(Vector3(1, 0, 0));
	query->set_candidates(positions);
	ERR_PRINT_OFF;
	CHECK(query->query_top_indices(0).is_empty());
	CHECK(query->query_top_indices(-1).is_empty());
	CHECK(query->query_top_indices(65).is_empty());
	ERR_PRINT_ON;
	CHECK(query->query_top_indices(1).size() == 1);
	CHECK(query->query_top_indices(1)[0] == 0);
	positions.push_back(Vector3(Math::NaN, 0, 0));
	query->set_candidates(positions);
	CHECK(query->query_top_indices(2).size() == 1); // Invalid candidate rejected.
	CHECK(query->query_top_positions(2).size() == 1);
}

TEST_CASE("[EnvironmentQuery3D] Position-only results preserve verbose ranking and spread limits") {
	Ref<EnvironmentQuery3D> query;
	query.instantiate();
	PackedVector3Array points;
	for (int i = 0; i < 100; i++) {
		points.push_back(Vector3(i % 11 - 5, 0, i % 7 - 3));
	}
	points.push_back(Vector3(Math::NaN, 0, 0));
	query->set_candidates(points);
	query->set_origin(Vector3());
	for (const int cap : { 0, 1, 7, 64, 65, 120 }) {
		query->set_max_results(cap);
		const Array verbose = query->query();
		const PackedVector3Array positions = query->query_positions();
		REQUIRE(positions.size() == verbose.size());
		for (int i = 0; i < positions.size(); i++) {
			const Dictionary entry = verbose[i];
			CHECK(positions[i] == Vector3(entry["position"]));
		}
		CHECK(query->query_spread_positions(1, 5.0) == query->query_top_positions(1));
		CHECK(query->query_spread_positions(16, 0.0) == query->query_top_positions(16));
	}
}

} // namespace TestEnvironmentQuery3D
