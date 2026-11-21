/**************************************************************************/
/*  test_ai_proximity_grid_2d.h                                            */
/**************************************************************************/
/*                         This file is part of: GODOT ENGINE             */
/**************************************************************************/

#pragma once

#include "../ai_proximity_grid_2d.h"
#include "tests/test_macros.h"

namespace TestAIProximityGrid2D {

TEST_CASE("[AIProximityGrid2D] Inclusive XZ radius and stable index ordering") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array sites;
	sites.push_back(Vector2(0, 0));
	sites.push_back(Vector2(3, 4)); // Exactly 5 from origin.
	sites.push_back(Vector2(6, 0));
	sites.push_back(Vector2(-5, 0)); // Negative cell boundary.
	sites.push_back(Vector2(-5.01, 0));
	sites.push_back(Vector2(0, 0)); // Overlapping actor, different index.
	PackedInt32Array sources;
	sources.push_back(0);
	sources.push_back(3);
	const Array batches = grid->query_radius_batch(sites, sources, 5.0, 18.0);
	CHECK(batches.size() == 2);
	const PackedInt32Array first = batches[0];
	CHECK(first.size() == 3);
	CHECK(first[0] == 1);
	CHECK(first[1] == 3);
	CHECK(first[2] == 5);
	const PackedInt32Array second = batches[1];
	CHECK(second.size() == 3);
	CHECK(second[0] == 0);
	CHECK(second[1] == 4);
	CHECK(second[2] == 5);
}

TEST_CASE("[AIProximityGrid2D] Batch duplicates, negative coordinates, and empty cohorts") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array sites;
	sites.push_back(Vector2(-18.0, -18.0));
	sites.push_back(Vector2(-17.0, -17.0));
	sites.push_back(Vector2(-1.0, -1.0));
	PackedInt32Array sources;
	sources.push_back(0);
	sources.push_back(0);
	const Array batches = grid->query_radius_batch(sites, sources, 3.0, 18.0);
	CHECK(batches.size() == 2);
	const PackedInt32Array left = batches[0];
	const PackedInt32Array right = batches[1];
	CHECK(left == right);
	const PackedInt32Array neighbors = batches[0];
	CHECK(neighbors.size() == 1);
	CHECK(neighbors[0] == 1);
	CHECK(grid->query_radius_batch(sites, PackedInt32Array(), 18.0, 18.0).is_empty());
}

TEST_CASE("[AIProximityGrid2D] Invalid positions and oversized requests are atomic") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array sites;
	sites.push_back(Vector2(0, 0));
	sites.push_back(Vector2(1, 0));
	PackedInt32Array sources;
	sources.push_back(0);
	CHECK(grid->query_radius_batch(sites, sources, 1.0, 1.0).size() == 1);
	CHECK(grid->query_radius_batch(sites, sources, -1.0, 18.0).is_empty());
	CHECK(grid->query_radius_batch(sites, sources, 20.0, 18.0).is_empty());
	CHECK(grid->query_radius_batch(sites, sources, 1.0, 0.0).is_empty());
	CHECK(grid->query_radius_batch(sites, sources, 257.0, 257.0).is_empty());
	CHECK(grid->query_radius_batch(sites, sources, Math::INF, 18.0).is_empty());
	sources.push_back(10);
	CHECK(grid->query_radius_batch(sites, sources, 1.0, 18.0).is_empty());
	sources.clear();
	for (int i = 0; i < 1025; i++) {
		sources.push_back(0);
	}
	CHECK(grid->query_radius_batch(sites, sources, 1.0, 18.0).is_empty());
}
TEST_CASE("[AIProximityGrid2D] Nearest cap respects distance, deterministic ties and legacy API") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array points;
	points.push_back(Vector2(0, 0));
	points.push_back(Vector2(5, 0));
	points.push_back(Vector2(-5, 0));
	points.push_back(Vector2(1, 0));
	points.push_back(Vector2(2, 0));
	points.push_back(Vector2(3, 0));
	points.push_back(Vector2(-1, 0));
	PackedInt32Array sources;
	sources.push_back(0);
	sources.push_back(0);
	const Array two = grid->query_nearest_batch(points, sources, 18.0, 18.0, 2);
	CHECK(two.size() == 2);
	const PackedInt32Array nearest = two[0];
	CHECK(nearest.size() == 2);
	CHECK(nearest[0] == 3);
	CHECK(nearest[1] == 6);
	const PackedInt32Array other = two[1];
	CHECK(other == nearest);
	const PackedInt32Array single = grid->query_nearest_batch(points, sources, 18.0, 18.0, 1)[0];
	CHECK(single.size() == 1);
	CHECK(single[0] == 3); // Equal distance breaks tie by input index.
	const PackedInt32Array original = grid->query_radius_batch(points, sources, 18.0, 18.0)[0];
	CHECK(original.size() == 6); // Existing four-argument API is unchanged.
	for (int i = 0; i < original.size(); i++) {
		CHECK(original[i] == i + 1);
	}
	CHECK(grid->query_nearest_batch(points, sources, 18.0, 18.0, 0).is_empty());
	CHECK(grid->query_nearest_batch(points, sources, 18.0, 18.0, 65).is_empty());
}

TEST_CASE("[AIProximityGrid2D] Dense crowd closest-first selection preserves legacy output ordering") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array crowd;
	crowd.push_back(Vector2(0, 0));
	for (int i = 40; i >= 1; i--) {
		crowd.push_back(Vector2(i * 0.25, 0));
	}
	PackedInt32Array sources;
	sources.push_back(0);
	const Array result = grid->query_nearest_batch(crowd, sources, 18.0, 18.0, 12);
	CHECK(result.size() == 1);
	const PackedInt32Array nearest = result[0];
	CHECK(nearest.size() == 12);
	for (int i = 0; i < 12; i++) {
		CHECK(nearest[i] == 29 + i); // 12 closest occupy the last input indices.
	}
	const PackedInt32Array uncapped = grid->query_radius_batch(crowd, sources, 18.0, 18.0)[0];
	CHECK(uncapped.size() == 40);
}

TEST_CASE("[AIProximityGrid2D] Nearest request cannot bypass source, radius or size validation") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array points;
	points.push_back(Vector2(0, 0));
	points.push_back(Vector2(3, 4));
	points.push_back(Vector2(6, 0));
	PackedInt32Array source;
	source.push_back(0);
	const PackedInt32Array boundary = grid->query_nearest_batch(points, source, 5.0, 5.0, 2)[0];
	CHECK(boundary.size() == 1);
	CHECK(boundary[0] == 1); // Inclusive distance, excludes >radius.
	CHECK(grid->query_nearest_batch(points, source, 5.0, 4.0, 2).is_empty());
	CHECK(grid->query_nearest_batch(points, source, Math::INF, 18.0, 2).is_empty());
	PackedInt32Array invalid;
	invalid.push_back(9);
	CHECK(grid->query_nearest_batch(points, invalid, 5.0, 18.0, 2).is_empty());
}


TEST_CASE("[AIProximityGrid2D] Native batch separation pushes close passive agents apart") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array positions;
	positions.push_back(Vector2(0, 0));
	positions.push_back(Vector2(1, 0));
	positions.push_back(Vector2(20, 0));
	PackedInt32Array sources;
	sources.push_back(0);
	sources.push_back(1);
	sources.push_back(2);
	const PackedVector2Array result = grid->query_separation_batch(positions, sources, 2.5, 3.0, 8);
	REQUIRE(result.size() == 3);
	CHECK(result[0].x < real_t(0.0));
	CHECK(result[1].x > real_t(0.0));
	CHECK(result[0].y == real_t(0.0));
	CHECK(result[1].y == real_t(0.0));
	CHECK(result[2] == Vector2());
	CHECK(result[0].length() <= real_t(1.0));
	CHECK(result[1].length() <= real_t(1.0));
	// Return values never depend on HashMap bucket traversal or RNG.
	CHECK(grid->query_separation_batch(positions, sources, 2.5, 3.0, 8) == result);
}

TEST_CASE("[AIProximityGrid2D] Coincident actors diverge deterministically, including negative cells") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array positions;
	positions.push_back(Vector2(-3, -3));
	positions.push_back(Vector2(-3, -3));
	positions.push_back(Vector2(-15, -15));
	PackedInt32Array sources;
	sources.push_back(0);
	sources.push_back(1);
	sources.push_back(0);
	const PackedVector2Array result = grid->query_separation_batch(positions, sources, 2.5, 3.0, 1);
	REQUIRE(result.size() == 3);
	CHECK(result[0] == Vector2(-1, 0));
	CHECK(result[1] == Vector2(1, 0));
	CHECK(result[2] == result[0]);
	const PackedVector2Array edge = grid->query_separation_batch(positions, sources, 0.0, 3.0, 1);
	CHECK(edge.is_empty()); // Zero radius is intentionally rejected.
}

TEST_CASE("[AIProximityGrid2D] Separation requests fail atomically on malformed inputs") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array positions;
	positions.push_back(Vector2(0, 0));
	positions.push_back(Vector2(3, 4));
	PackedInt32Array sources;
	sources.push_back(0);
	CHECK(grid->query_separation_batch(positions, sources, 5.0, 5.0, 1).size() == 1);
	CHECK(grid->query_separation_batch(positions, sources, -1.0, 5.0, 1).is_empty());
	CHECK(grid->query_separation_batch(positions, sources, 6.0, 5.0, 1).is_empty());
	CHECK(grid->query_separation_batch(positions, sources, 5.0, 5.0, 0).is_empty());
	CHECK(grid->query_separation_batch(positions, sources, 5.0, 5.0, 65).is_empty());
	CHECK(grid->query_separation_batch(positions, sources, Math::INF, 5.0, 1).is_empty());
	CHECK(grid->query_separation_batch(positions, sources, 5.0, Math::INF, 1).is_empty());
	PackedInt32Array invalid_sources;
	invalid_sources.push_back(0);
	invalid_sources.push_back(3);
	CHECK(grid->query_separation_batch(positions, invalid_sources, 5.0, 5.0, 2).is_empty());
	positions.push_back(Vector2(Math::NaN, 0));
	CHECK(grid->query_separation_batch(positions, sources, 5.0, 5.0, 1).is_empty());
}

TEST_CASE("[AIProximityGrid2D] Cross-set broadphase preserves inclusive radii and target order") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array sources;
	sources.push_back(Vector2(0, 0));
	sources.push_back(Vector2(-6, -6));
	sources.push_back(Vector2(200, 200));
	PackedVector2Array targets;
	targets.push_back(Vector2(3, 4)); // Inclusive 5m boundary.
	targets.push_back(Vector2(0, 0));
	targets.push_back(Vector2(-9, -10)); // Negative cell boundary.
	targets.push_back(Vector2(6, 0)); // Outside 5m.
	targets.push_back(Vector2(3, 4)); // Two distinct trap identities.
	const Array found = grid->query_cross_radius_batch(sources, targets, 5.0, 5.0);
	REQUIRE(found.size() == 3);
	const PackedInt32Array first = found[0];
	CHECK(first.size() == 3);
	CHECK(first[0] == 0);
	CHECK(first[1] == 1);
	CHECK(first[2] == 4);
	const PackedInt32Array second = found[1];
	CHECK(second.size() == 1);
	CHECK(second[0] == 2);
	const PackedInt32Array third = found[2];
	CHECK(third.is_empty());
	CHECK(grid->query_cross_radius_batch(sources, targets, 5.0, 5.0) == found);
}

TEST_CASE("[AIProximityGrid2D] Cross-set requests reject malformed cohorts atomically") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array sources;
	sources.push_back(Vector2(0, 0));
	PackedVector2Array targets;
	targets.push_back(Vector2(0, 0));
	CHECK(grid->query_cross_radius_batch(sources, targets, 0.0, 1.0).size() == 1);
	CHECK(grid->query_cross_radius_batch(sources, targets, -1.0, 2.0).is_empty());
	CHECK(grid->query_cross_radius_batch(sources, targets, 2.0, 1.0).is_empty());
	CHECK(grid->query_cross_radius_batch(sources, targets, Math::INF, 2.0).is_empty());
	CHECK(grid->query_cross_radius_batch(sources, targets, 2.0, Math::INF).is_empty());
	CHECK(grid->query_cross_radius_batch(PackedVector2Array(), targets, 1.0, 2.0).is_empty());
	CHECK(grid->query_cross_radius_batch(sources, PackedVector2Array(), 1.0, 2.0).is_empty());
	PackedVector2Array invalid_sources = sources;
	invalid_sources.push_back(Vector2(Math::NaN, 0));
	CHECK(grid->query_cross_radius_batch(invalid_sources, targets, 1.0, 2.0).is_empty());
	PackedVector2Array invalid_targets = targets;
	invalid_targets.push_back(Vector2(Math::INF, 0));
	CHECK(grid->query_cross_radius_batch(sources, invalid_targets, 1.0, 2.0).is_empty());
	PackedVector2Array excessive_sources;
	excessive_sources.resize(4097);
	CHECK(grid->query_cross_radius_batch(excessive_sources, targets, 1.0, 2.0).is_empty());
	PackedVector2Array excessive_targets;
	excessive_targets.resize(8193);
	CHECK(grid->query_cross_radius_batch(sources, excessive_targets, 1.0, 2.0).is_empty());
	// Dense matched pairs must also fail atomically to protect memory.
	PackedVector2Array dense_sources;
	dense_sources.resize(513);
	PackedVector2Array dense_targets;
	dense_targets.resize(64);
	CHECK(grid->query_cross_radius_batch(dense_sources, dense_targets, 1.0, 2.0).is_empty());
	CHECK(grid->query_cross_radius_batch(sources, targets, 1.0, 2.0).size() == 1);
}

TEST_CASE("[AIProximityGrid2D] Predictive separation sidesteps head-on crossings") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array positions;
	positions.push_back(Vector2(0, 0));
	positions.push_back(Vector2(2, 0));
	PackedVector2Array velocities;
	velocities.push_back(Vector2(1, 0));
	velocities.push_back(Vector2(-1, 0));
	PackedInt32Array sources;
	sources.push_back(0);
	sources.push_back(1);
	const PackedVector2Array now = grid->query_separation_batch(positions, sources, 1.5, 2.0, 8);
	REQUIRE(now.size() == 2);
	CHECK(now[0] == Vector2());
	CHECK(now[1] == Vector2()); // No static neighbors yet.
	const PackedVector2Array future = grid->query_predictive_separation_batch(
			positions, velocities, sources, 1.5, 2.0, 8, 1.0);
	REQUIRE(future.size() == 2);
	CHECK(future[0].x == real_t(0.0));
	CHECK(future[0].y > real_t(0.0));
	CHECK(future[1].x == real_t(0.0));
	CHECK(future[1].y < real_t(0.0));
	CHECK(future[0].length() <= real_t(1.0));
	CHECK(future[1].length() <= real_t(1.0));
	CHECK(grid->query_predictive_separation_batch(positions, velocities, sources, 1.5, 2.0, 8, 1.0) == future);
	// A near miss (not exact equality) must still sidestep before contact.
	positions.set(1, Vector2(2.2, 0));
	const PackedVector2Array near_miss = grid->query_predictive_separation_batch(
			positions, velocities, sources, 1.5, 2.0, 8, 1.0);
	REQUIRE(near_miss.size() == 2);
	CHECK(near_miss[0].x == real_t(0.0));
	CHECK(near_miss[0].y > real_t(0.5));
	CHECK(near_miss[1].x == real_t(0.0));
	CHECK(near_miss[1].y < real_t(-0.5));
}

TEST_CASE("[AIProximityGrid2D] Predictions retain zero-horizon parity and static overlap ties") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array positions;
	positions.push_back(Vector2(-5, 0));
	positions.push_back(Vector2(-4, 0));
	positions.push_back(Vector2(10, 0));
	PackedVector2Array velocities;
	velocities.push_back(Vector2(-1, 0));
	velocities.push_back(Vector2(1, 0));
	velocities.push_back(Vector2());
	PackedInt32Array sources;
	sources.push_back(0);
	sources.push_back(1);
	const PackedVector2Array static_result = grid->query_separation_batch(positions, sources, 2.5, 3.0, 2);
	const PackedVector2Array zero_horizon = grid->query_predictive_separation_batch(
			positions, velocities, sources, 2.5, 3.0, 2, 0.0);
	CHECK(zero_horizon == static_result);
	const PackedVector2Array moving_apart = grid->query_predictive_separation_batch(
			positions, velocities, sources, 2.5, 3.0, 2, 1.0);
	REQUIRE(moving_apart.size() == 2);
	CHECK(moving_apart[0] == Vector2());
	CHECK(moving_apart[1] == Vector2());
	positions.set(1, Vector2(-5, 0));
	velocities.set(0, Vector2());
	velocities.set(1, Vector2());
	const PackedVector2Array overlapping = grid->query_predictive_separation_batch(
			positions, velocities, sources, 2.5, 3.0, 2, 1.0);
	REQUIRE(overlapping.size() == 2);
	CHECK(overlapping[0] == Vector2(-1, 0));
	CHECK(overlapping[1] == Vector2(1, 0));
}

TEST_CASE("[AIProximityGrid2D] Invalid predictive velocities and horizons fail atomically") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array positions;
	positions.push_back(Vector2(0, 0));
	PackedVector2Array velocity;
	velocity.push_back(Vector2(1, 0));
	PackedInt32Array source;
	source.push_back(0);
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 2.5, 3.0, 2, 0.7).size() == 1);
	CHECK(grid->query_predictive_separation_batch(positions, PackedVector2Array(), source, 2.5, 3.0, 2, 0.7).is_empty());
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 2.5, 3.0, 2, -1.0).is_empty());
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 2.5, 3.0, 2, 2.1).is_empty());
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 2.5, 3.0, 2, Math::INF).is_empty());
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 0.0, 3.0, 2, 0.7).is_empty());
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 2.5, 2.0, 2, 0.7).is_empty());
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 2.5, 3.0, 0, 0.7).is_empty());
	PackedInt32Array invalid_source;
	invalid_source.push_back(3);
	CHECK(grid->query_predictive_separation_batch(positions, velocity, invalid_source, 2.5, 3.0, 2, 0.7).is_empty());
	velocity.set(0, Vector2(60, 0));
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 2.5, 3.0, 2, 0.7).is_empty());
	velocity.set(0, Vector2(Math::NaN, 0));
	CHECK(grid->query_predictive_separation_batch(positions, velocity, source, 2.5, 3.0, 2, 0.7).is_empty());
}


TEST_CASE("[AIProximityGrid2D] EQS cross-nearest chooses closest and stable world ID ties") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array sources;
	sources.push_back(Vector2(0, 0));
	sources.push_back(Vector2(-10, -10));
	sources.push_back(Vector2(300, 300));
	PackedVector2Array targets;
	targets.push_back(Vector2(4, 0));
	targets.push_back(Vector2(-4, 0));
	targets.push_back(Vector2(-13, -14)); // Exactly five meters.
	targets.push_back(Vector2(100, 0));
	PackedInt64Array ids;
	ids.push_back(30);
	ids.push_back(10);
	ids.push_back(50);
	ids.push_back(1);
	const PackedInt32Array found = grid->query_cross_nearest_batch(sources, targets, ids, 5.0, 5.0);
	REQUIRE(found.size() == 3);
	CHECK(found[0] == 1); // Equal distances, smallest world ID.
	CHECK(found[1] == 2); // Inclusive negative-cell radius.
	CHECK(found[2] == -1);
	CHECK(grid->query_cross_nearest_batch(sources, targets, ids, 5.0, 5.0) == found);
	// Duplicate coordinates are distinct items, not conflated actor positions.
	targets.set(0, Vector2(-4, 0));
	const PackedInt32Array duplicate = grid->query_cross_nearest_batch(sources, targets, ids, 5.0, 5.0);
	CHECK(duplicate[0] == 1);
	ids.set(0, 10);
	const PackedInt32Array equal_ids = grid->query_cross_nearest_batch(sources, targets, ids, 5.0, 5.0);
	CHECK(equal_ids[0] == 0); // Original index is stable secondary tie.
}

TEST_CASE("[AIProximityGrid2D] EQS cross-nearest supports zero radius, duplicate sources and negative cells") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array sources;
	sources.push_back(Vector2(-6, -6));
	sources.push_back(Vector2(-6, -6));
	sources.push_back(Vector2(0, 0));
	PackedVector2Array targets;
	targets.push_back(Vector2(-6, -6));
	PackedInt64Array ids;
	ids.push_back(-23);
	const PackedInt32Array nearest = grid->query_cross_nearest_batch(sources, targets, ids, 0.0, 1.0);
	REQUIRE(nearest.size() == 3);
	CHECK(nearest[0] == 0);
	CHECK(nearest[1] == 0);
	CHECK(nearest[2] == -1);
	CHECK(grid->query_cross_nearest_batch(sources, targets, ids, 8.5, 9.0).size() == 3);
}

TEST_CASE("[AIProximityGrid2D] EQS cross-nearest rejects malformed data atomically") {
	Ref<AIProximityGrid2D> grid;
	grid.instantiate();
	PackedVector2Array sources;
	sources.push_back(Vector2(0, 0));
	PackedVector2Array targets;
	targets.push_back(Vector2(1, 0));
	PackedInt64Array ids;
	ids.push_back(1);
	CHECK(grid->query_cross_nearest_batch(sources, targets, ids, 2.0, 2.0).size() == 1);
	CHECK(grid->query_cross_nearest_batch(sources, targets, PackedInt64Array(), 2.0, 2.0).is_empty());
	CHECK(grid->query_cross_nearest_batch(sources, targets, ids, -1.0, 2.0).is_empty());
	CHECK(grid->query_cross_nearest_batch(sources, targets, ids, 3.0, 2.0).is_empty());
	CHECK(grid->query_cross_nearest_batch(sources, targets, ids, Math::INF, 2.0).is_empty());
	CHECK(grid->query_cross_nearest_batch(sources, targets, ids, 2.0, Math::INF).is_empty());
	CHECK(grid->query_cross_nearest_batch(PackedVector2Array(), targets, ids, 2.0, 2.0).is_empty());
	CHECK(grid->query_cross_nearest_batch(sources, PackedVector2Array(), PackedInt64Array(), 2.0, 2.0).is_empty());
	PackedVector2Array invalid_sources = sources;
	invalid_sources.push_back(Vector2(Math::NaN, 0));
	CHECK(grid->query_cross_nearest_batch(invalid_sources, targets, ids, 2.0, 2.0).is_empty());
	PackedVector2Array invalid_targets = targets;
	invalid_targets.push_back(Vector2(Math::INF, 0));
	ids.push_back(2);
	CHECK(grid->query_cross_nearest_batch(sources, invalid_targets, ids, 2.0, 2.0).is_empty());
	PackedVector2Array too_many_sources;
	too_many_sources.resize(4097);
	CHECK(grid->query_cross_nearest_batch(too_many_sources, targets, PackedInt64Array(), 2.0, 2.0).is_empty());
	PackedVector2Array too_many_targets;
	too_many_targets.resize(8193);
	CHECK(grid->query_cross_nearest_batch(sources, too_many_targets, ids, 2.0, 2.0).is_empty());
}

} // namespace TestAIProximityGrid2D
