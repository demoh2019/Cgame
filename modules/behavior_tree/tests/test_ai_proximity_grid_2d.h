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

} // namespace TestAIProximityGrid2D
