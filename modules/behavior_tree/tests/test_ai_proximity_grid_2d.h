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
} // namespace TestAIProximityGrid2D
