/**************************************************************************/
/*  test_spatial_point_grid_2d.cpp                                              */
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

TEST_FORCE_LINK(test_spatial_point_grid_2d)

#include "scene/main/spatial_point_grid_2d.h"

namespace TestSpatialPointGrid2D {

TEST_CASE("[SpatialPointGrid2D] Empty, strict and inclusive radius boundaries") {
	Ref<SpatialPointGrid2D> grid;
	grid.instantiate();
	CHECK_FALSE(grid->any_within(Vector2(), 12.0));
	TypedArray<Vector2> points;
	points.push_back(Vector2(-64.0, -1.0));
	points.push_back(Vector2(Math::INF, 1));
	grid->rebuild(points);
	CHECK(grid->get_point_count() == 1);
	CHECK_FALSE(bool(grid->snapshot()["indexed_mode"]));
	CHECK(grid->any_within(Vector2(-64.0, -1.0), 0.0));
	CHECK_FALSE(grid->any_within(Vector2(-64.0, -1.0), 0.0, false));
	CHECK(grid->any_within(Vector2(-52.0, -1.0), 12.0));
	CHECK_FALSE(grid->any_within(Vector2(-52.0, -1.0), 12.0, false));
	CHECK(grid->any_within(Vector2(-52.01, -1.0), 12.0, false));
	CHECK_FALSE(grid->any_within(Vector2(Math::NaN, 0), 12.0));
	CHECK_FALSE(grid->any_within(Vector2(), Math::NaN));
	CHECK_FALSE(grid->any_within(Vector2(), -1.0));
	CHECK(grid->any_within(Vector2(66.0, -1.0), 130.0));
	CHECK_FALSE(grid->any_within(Vector2(66.0, -1.0), 130.0, false));
	CHECK(grid->snapshot()["queries"] == Variant(7));
	CHECK(grid->snapshot()["bucket_lookups"] == Variant(0));
}

TEST_CASE("[SpatialPointGrid2D] Hashed queries exactly match direct brute force") {
	Ref<SpatialPointGrid2D> grid;
	grid.instantiate();
	TypedArray<Vector2> points;
	for (int i = 0; i < 40; i++) {
		const int x = ((i * 137) % 3300) - 1650;
		const int y = ((i * 313) % 3300) - 1650;
		points.push_back(Vector2(x, y));
	}
	grid->rebuild(points);
	CHECK(bool(grid->snapshot()["indexed_mode"]));
	CHECK(int(grid->snapshot()["occupied_cells"]) > 1);
	for (int i = 0; i < 120; i++) {
		const Vector2 q(((i * 337) % 3600) - 1800, ((i * 159) % 3600) - 1800);
		for (const real_t radius : { real_t(0.0), real_t(12.0), real_t(64.0), real_t(130.0), real_t(256.0) }) {
			for (bool inclusive : { true, false }) {
				bool expected = false;
				for (int j = 0; j < points.size(); j++) {
					const Vector2 player = points[j];
					const real_t d = q.distance_squared_to(player);
					if ((inclusive && d <= radius * radius) || (!inclusive && d < radius * radius)) {
						expected = true;
						break;
					}
				}
				CHECK(grid->any_within(q, radius, inclusive) == expected);
			}
		}
	}
	CHECK(int(grid->snapshot()["queries"]) == 1200);
	CHECK(int(grid->snapshot()["bucket_lookups"]) > 0);
	CHECK(int(grid->snapshot()["candidate_checks"]) < 1200 * points.size());
	const int buckets_before = grid->snapshot()["bucket_lookups"];
	CHECK(grid->any_within(Vector2(), 1000000.0));
	CHECK(int(grid->snapshot()["bucket_lookups"]) == buckets_before);
	grid->clear();
	CHECK(grid->get_point_count() == 0);
	CHECK(grid->snapshot()["queries"] == Variant(0));
}

TEST_CASE("[SpatialPointGrid2D] Rebuild and configured grid preserve exactness") {
	Ref<SpatialPointGrid2D> grid;
	grid.instantiate();
	grid->set_cell_size(32.0);
	grid->set_direct_scan_threshold(0);
	grid->set_max_indexed_radius(2048.0);
	TypedArray<Vector2> first;
	first.push_back(Vector2(-32.0, -32.0));
	first.push_back(Vector2(64.0, 64.0));
	grid->rebuild(first);
	CHECK(bool(grid->snapshot()["indexed_mode"]));
	CHECK(grid->any_within(Vector2(-32.0, -32.0), 0.0));
	CHECK_FALSE(grid->any_within(Vector2(-31.0, -32.0), 1.0, false));
	CHECK(grid->any_within(Vector2(-31.0, -32.0), 1.0));
	grid->set_cell_size(64.0); // Reindex existing points, no false negatives.
	CHECK(grid->any_within(Vector2(64.0, 64.0), 0.0));
	TypedArray<Vector2> after;
	after.push_back(Vector2(800.0, 800.0));
	grid->rebuild(after);
	CHECK_FALSE(grid->any_within(Vector2(-32.0, -32.0), 20.0));
	CHECK(grid->any_within(Vector2(800.0, 800.0), 0.0));
	CHECK(grid->get_point_count() == 1);
	CHECK(grid->snapshot()["queries"] == Variant(2));
}


TEST_CASE("[SpatialPointGrid2D] Batch proximity equals scalar with ordered results and statistics") {
	Ref<SpatialPointGrid2D> grid;
	grid.instantiate();
	TypedArray<Vector2> positions;
	positions.push_back(Vector2(0, 0));
	positions.push_back(Vector2(-128, 0));
	for (int i = 0; i < 30; i++) {
		positions.push_back(Vector2(real_t(1000 + i * 77), real_t(i * 91)));
	}
	grid->rebuild(positions);
	PackedVector2Array probes;
	probes.push_back(Vector2(0, 0));
	probes.push_back(Vector2(12, 0));
	probes.push_back(Vector2(-128, 0));
	probes.push_back(Vector2(-116, 0));
	probes.push_back(Vector2(500, 500));
	probes.push_back(Vector2(Math::NaN, 0));

	const PackedByteArray exact = grid->any_within_batch(probes, real_t(12.0), false);
	REQUIRE(exact.size() == probes.size());
	CHECK(exact[0] == 1);
	CHECK(exact[1] == 0); // Strict boundary excludes exactly 12 m.
	CHECK(exact[2] == 1);
	CHECK(exact[3] == 0);
	CHECK(exact[4] == 0);
	CHECK(exact[5] == 0); // Invalid probes fail closed.
	CHECK(grid->snapshot()["batch_calls"] == Variant(1));
	CHECK(grid->snapshot()["queries"] == Variant(5)); // Invalid probe doesn't count.

	const PackedByteArray inclusive = grid->any_within_batch(probes, real_t(12.0), true);
	CHECK(inclusive[1] == 1);
	CHECK(inclusive[3] == 1);
	CHECK(grid->snapshot()["batch_calls"] == Variant(2));
	CHECK(grid->snapshot()["queries"] == Variant(10));

	PackedVector2Array empty;
	const PackedByteArray none = grid->any_within_batch(empty, real_t(130.0));
	CHECK(none.is_empty());
	CHECK(grid->snapshot()["batch_calls"] == Variant(3));
	CHECK(grid->snapshot()["queries"] == Variant(10));

	const PackedByteArray huge = grid->any_within_batch(probes, real_t(1000000.0));
	CHECK(huge[0] == 1);
	CHECK(huge[5] == 0);
	grid->rebuild(positions);
	CHECK(grid->snapshot()["batch_calls"] == Variant(0));
	CHECK(grid->snapshot()["queries"] == Variant(0));
}

} // namespace TestSpatialPointGrid2D
