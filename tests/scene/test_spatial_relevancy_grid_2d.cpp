/**************************************************************************/
/*  test_spatial_relevancy_grid_2d.cpp                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_spatial_relevancy_grid_2d)

#include "scene/main/spatial_relevancy_grid_2d.h"

namespace TestSpatialRelevancyGrid2D {

TEST_CASE("[SpatialRelevancyGrid2D] Stable input order, exact radius, negative cells") {
	Ref<SpatialRelevancyGrid2D> grid;
	grid.instantiate();
	PackedInt64Array ids = { 91, 7, 222, 2, 31, 19, 8, 44, 3, 54 };
	PackedVector2Array points = {
		Vector2(-100, -100), Vector2(300, 300),
		Vector2(-10, -10), Vector2(-100, -190),
		Vector2(0, 0), Vector2(-50, -50),
		Vector2(100, 100), Vector2(200, 200),
		Vector2(-100, -10), Vector2(500, 500)
	};
	REQUIRE(grid->rebuild(ids, points));
	CHECK(bool(grid->get_stats()["indexed_mode"]));
	const PackedInt64Array nearby = grid->query_ids(Vector2(-100, -100), 90.0);
	const PackedInt64Array expected = { 91, 2, 19, 3 };
	CHECK(nearby == expected); // 90m boundary is inclusive.
	CHECK(grid->query_ids(Vector2(0, 0), 0.0) == PackedInt64Array{ 31 });
	CHECK(grid->query_ids(Vector2(0, 0), 1.0) == PackedInt64Array{ 31 });
	CHECK(grid->query_ids(Vector2(10000, 10000), 90.0).is_empty());
	CHECK(int(grid->get_stats()["buckets"]) > 0);
	CHECK(int(grid->get_stats()["candidates"]) < 10 * 4);
}

TEST_CASE("[SpatialRelevancyGrid2D] Input rejection and safe fallback") {
	Ref<SpatialRelevancyGrid2D> grid;
	grid.instantiate();
	PackedInt64Array ids = { 11, 11 };
	PackedVector2Array points = { Vector2(), Vector2(1, 1) };
	CHECK_FALSE(grid->rebuild(ids, points));
	CHECK(int(grid->get_stats()["entities"]) == 0);
	ids.set(1, 12);
	points.set(1, Vector2(Math::NaN, 1));
	CHECK_FALSE(grid->rebuild(ids, points));
	points.set(1, Vector2(1, 1));
	REQUIRE(grid->rebuild(ids, points));
	CHECK(grid->query_ids(Vector2(), 100000.0) == ids);
	CHECK(int(grid->get_stats()["fallback_scans"]) == 1);
	CHECK(grid->query_ids(Vector2(Math::NaN, 1), 90.0).is_empty());
	CHECK(grid->query_ids(Vector2(), -1.0).is_empty());
	CHECK(grid->query_ids(Vector2(), Math::NaN).is_empty());
	grid->set_cell_size(32.0);
	grid->set_max_indexed_radius(128.0);
	CHECK(grid->query_ids(Vector2(), 1000.0) == ids);
	grid->clear();
	CHECK(int(grid->get_stats()["entities"]) == 0);
	CHECK(int(grid->get_stats()["queries"]) == 0);
}

TEST_CASE("[SpatialRelevancyGrid2D] Multiple viewers match brute-force source order") {
	Ref<SpatialRelevancyGrid2D> grid;
	grid.instantiate();
	PackedInt64Array ids;
	PackedVector2Array points;
	for (int i = 0; i < 320; i++) {
		ids.push_back(10000 + i);
		points.push_back(Vector2((i * 197) % 3100 - 1550, (i * 311) % 2900 - 1450));
	}
	REQUIRE(grid->rebuild(ids, points));
	for (int j = 0; j < 100; j++) {
		const Vector2 viewer((j * 331) % 3400 - 1700, (j * 409) % 3200 - 1600);
		const double radius = j % 2 == 0 ? 90.0 : 320.0;
		PackedInt64Array expected;
		for (int i = 0; i < points.size(); i++) {
			if (viewer.distance_squared_to(points[i]) <= radius * radius) {
				expected.push_back(ids[i]);
			}
		}
		CHECK(grid->query_ids(viewer, radius) == expected);
	}
	CHECK(int(grid->get_stats()["queries"]) == 100);
	CHECK(int(grid->get_stats()["rebuilds"]) == 1);
}

TEST_CASE("[SpatialRelevancyGrid2D] Batched viewers preserve scalar sets and input ordering") {
	Ref<SpatialRelevancyGrid2D> grid;
	grid.instantiate();
	PackedInt64Array ids;
	PackedVector2Array actors;
	for (int i = 0; i < 160; i++) {
		ids.push_back(10000 + i);
		actors.push_back(Vector2((i * 197) % 3100 - 1550, (i * 311) % 2900 - 1450));
	}
	REQUIRE(grid->rebuild(ids, actors));
	PackedVector2Array viewers = {
		Vector2(0, 0), Vector2(-1550, -1450), Vector2(64, -32),
		Vector2(1500, 1300), Vector2(Math::NaN, 0)
	};
	const Array batched = grid->query_many(viewers, 90.0);
	REQUIRE(batched.size() == viewers.size());
	for (int viewer_index = 0; viewer_index < viewers.size(); viewer_index++) {
		const PackedInt64Array actual = batched[viewer_index];
		const PackedInt64Array scalar = grid->query_ids(viewers[viewer_index], 90.0);
		CHECK(actual == scalar);
		PackedInt64Array brute;
		if (viewers[viewer_index].is_finite()) {
			for (int i = 0; i < actors.size(); i++) {
				if (viewers[viewer_index].distance_squared_to(actors[i]) <= 90.0 * 90.0) {
					brute.push_back(ids[i]);
				}
			}
		}
		CHECK(actual == brute);
	}
	CHECK(int(grid->get_stats()["batch_calls"]) == 1);
	CHECK(int(grid->get_stats()["batch_viewers"]) == viewers.size());
	CHECK(int(grid->get_stats()["queries"]) == 8); // Invalid viewer never increments.
	const Array huge = grid->query_many(viewers, 100000.0);
	REQUIRE(huge.size() == viewers.size());
	CHECK(int(grid->get_stats()["batch_calls"]) == 2);
	CHECK(int(grid->get_stats()["fallback_scans"]) >= 4);
	const Array empty = grid->query_many(PackedVector2Array(), 90.0);
	CHECK(empty.is_empty());
	CHECK(int(grid->get_stats()["batch_calls"]) == 3);
	CHECK(int(grid->get_stats()["batch_viewers"]) == 10);
	PackedVector2Array oversized;
	oversized.resize(4097);
	CHECK(grid->query_many(oversized, 90.0).is_empty());
	CHECK(int(grid->get_stats()["batch_calls"]) == 3);
	PackedInt64Array many_ids;
	PackedVector2Array many_actors;
	for (int i = 0; i < 1024; i++) {
		many_ids.push_back(i + 1);
		many_actors.push_back(Vector2(i, i));
	}
	REQUIRE(grid->rebuild(many_ids, many_actors));
	PackedVector2Array expensive_viewers;
	expensive_viewers.resize(2050);
	CHECK(grid->query_many(expensive_viewers, 90.0).is_empty());
	CHECK(int(grid->get_stats()["batch_calls"]) == 0); // Guard before work.
	grid->clear();
	CHECK(int(grid->get_stats()["batch_calls"]) == 0);
	CHECK(int(grid->get_stats()["batch_viewers"]) == 0);
}

TEST_CASE("[SpatialRelevancyGrid2D] Nearest-K is distance sorted with deterministic ID ties") {
	Ref<SpatialRelevancyGrid2D> grid;
	grid.instantiate();
	PackedInt64Array ids = { 50, 8, 90, 3, 15, 600, 29, 70, 11, 12 };
	PackedVector2Array locations = {
		Vector2(0, 0), Vector2(2, 0), Vector2(-2, 0), Vector2(0, 0),
		Vector2(0, -2), Vector2(100, 100), Vector2(1, 0), Vector2(10, 10),
		Vector2(-10, -10), Vector2(999, 0)
	};
	REQUIRE(grid->rebuild(ids, locations));
	CHECK(bool(grid->get_stats()["indexed_mode"]));
	const PackedInt64Array expected = { 3, 50, 29, 8, 15 };
	CHECK(grid->query_nearest_ids(Vector2(), 2.0, 5) == expected);
	CHECK(grid->query_nearest_ids(Vector2(), 0.0, 3) == PackedInt64Array{ 3, 50 });
	CHECK(grid->query_nearest_ids(Vector2(), 2.0, 1) == PackedInt64Array{ 3 });
	CHECK(grid->query_nearest_ids(Vector2(), 2.0, 128) == PackedInt64Array{ 3, 50, 29, 8, 15, 90 });
	CHECK(grid->query_ids(Vector2(), 2.0) == PackedInt64Array{ 50, 8, 90, 3, 15, 29 });
	CHECK(int(grid->get_stats()["nearest_queries"]) == 4);
	const int queries_before = int(grid->get_stats()["queries"]);
	CHECK(grid->query_nearest_ids(Vector2(Math::NaN, 0), 2.0, 5).is_empty());
	CHECK(grid->query_nearest_ids(Vector2(), Math::NaN, 5).is_empty());
	CHECK(grid->query_nearest_ids(Vector2(), -1.0, 5).is_empty());
	CHECK(grid->query_nearest_ids(Vector2(), 2.0, 0).is_empty());
	CHECK(grid->query_nearest_ids(Vector2(), 2.0, 129).is_empty());
	CHECK(int(grid->get_stats()["queries"]) == queries_before);
	CHECK(grid->query_nearest_ids(Vector2(), 1000.0, 3) == PackedInt64Array{ 3, 50, 29 });
	CHECK(int(grid->get_stats()["fallback_scans"]) == 1);
	CHECK(int(grid->get_stats()["nearest_queries"]) == 5);
	grid->set_cell_size(32.0);
	CHECK(grid->query_nearest_ids(Vector2(), 2.0, 5) == expected);
	grid->clear();
	CHECK(grid->query_nearest_ids(Vector2(), 100.0, 12).is_empty());
	CHECK(int(grid->get_stats()["nearest_queries"]) == 1);
	CHECK(int(grid->get_stats()["entities"]) == 0);
}

TEST_CASE("[SpatialRelevancyGrid2D] Nearest-K matches independent brute distance sort") {
	Ref<SpatialRelevancyGrid2D> grid;
	grid.instantiate();
	PackedInt64Array ids;
	PackedVector2Array locations;
	for (int i = 0; i < 220; i++) {
		ids.push_back(1000 + i);
		locations.push_back(Vector2((i * 113) % 1500 - 750, (i * 241) % 1700 - 850));
	}
	REQUIRE(grid->rebuild(ids, locations));
	for (int j = 0; j < 45; j++) {
		const Vector2 center((j * 291) % 1500 - 750, (j * 337) % 1700 - 850);
		const double radius = (j % 3 == 0) ? 48.0 : ((j % 3 == 1) ? 200.0 : 600.0);
		PackedInt64Array expected;
		Vector<double> distances;
		for (int i = 0; i < ids.size(); i++) {
			const double d = double(center.distance_squared_to(locations[i]));
			if (d > radius * radius) {
				continue;
			}
			int insert_index = 0;
			for (; insert_index < expected.size(); insert_index++) {
				if (d < distances[insert_index] || (d == distances[insert_index] && ids[i] < expected[insert_index])) {
					break;
				}
			}
			expected.insert(insert_index, ids[i]);
			distances.insert(insert_index, d);
		}
		if (expected.size() > 7) {
			expected.resize(7);
		}
		CHECK(grid->query_nearest_ids(center, radius, 7) == expected);
	}
	CHECK(int(grid->get_stats()["nearest_queries"]) == 45);
	CHECK(int(grid->get_stats()["candidates"]) < 45 * locations.size());
}

} // namespace TestSpatialRelevancyGrid2D
