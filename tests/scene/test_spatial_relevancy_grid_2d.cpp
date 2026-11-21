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
	const PackedInt64Array expected = { 91, 222, 2, 19, 3 };
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
} // namespace TestSpatialRelevancyGrid2D
