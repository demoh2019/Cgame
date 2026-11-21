/**************************************************************************/
/*  test_spatial_point_grid_3d.cpp                                        */
/**************************************************************************/

#include "tests/test_macros.h"
TEST_FORCE_LINK(test_spatial_point_grid_3d)

#include "scene/main/spatial_point_grid_3d.h"

namespace TestSpatialPointGrid3D {

TEST_CASE("[SpatialPointGrid3D] True 3D radius, early cap, invalid and empty batches") {
	Ref<SpatialPointGrid3D> grid;
	grid.instantiate();
	CHECK(grid->get_cell_size() == 64.0);
	CHECK(grid->get_point_count() == 0);
	CHECK(grid->count_within(Vector3(), 75.0) == 0);
	TypedArray<Vector3> pts;
	pts.push_back(Vector3(0, 0, 0));
	pts.push_back(Vector3(0, 75, 0)); // Exactly on vertical boundary.
	pts.push_back(Vector3(0, -75, 0));
	pts.push_back(Vector3(0, 76, 0));
	pts.push_back(Vector3(0, 0, 75));
	pts.push_back(Vector3(Math::INF, 0, 0)); // Invalid original never indexed.
	CHECK(grid->rebuild(pts));
	CHECK(grid->get_point_count() == 5);
	CHECK(grid->count_within(Vector3(), 75.0, 20) == 4);
	CHECK(grid->count_within(Vector3(), 75.0, 2) == 2);
	CHECK(grid->count_within(Vector3(), 0.0) == 1);
	CHECK(grid->count_within(Vector3(0, 1000, 0), 75.0) == 0);
	CHECK(grid->count_within(Vector3(Math::NaN, 0, 0), 75.0) == -1);
	CHECK(grid->count_within(Vector3(), Math::INF) == -1);
	CHECK(grid->count_within(Vector3(), -1.0) == -1);
	CHECK(grid->count_within(Vector3(), 75.0, 0) == -1);
	CHECK(grid->count_within(Vector3(), 75.0, 8193) == -1);
	CHECK(int(grid->get_stats()["points"]) == 5);

	PackedVector3Array probes;
	probes.push_back(Vector3());
	probes.push_back(Vector3(0, 1000, 0));
	probes.push_back(Vector3(Math::NaN, 0, 0));
	probes.push_back(Vector3(0, 75, 0));
	const PackedInt32Array counts = grid->count_within_batch(probes, 75.0, 20);
	REQUIRE(counts.size() == 4);
	CHECK(counts[0] == 4);
	CHECK(counts[1] == 0);
	CHECK(counts[2] == 0);
	CHECK(counts[3] == 3); // 0m, 1m and -75m; other points outside sphere.
	CHECK(grid->count_within_batch(PackedVector3Array(), 75.0).is_empty());
	CHECK(grid->count_within_batch(probes, -1.0).is_empty());
	CHECK(grid->count_within_batch(probes, 75.0, 0).is_empty());
	CHECK(int(grid->get_stats()["batch_calls"]) == 2);
}

TEST_CASE("[SpatialPointGrid3D] Indexed mode remains exact across negative and vertical world cells") {
	Ref<SpatialPointGrid3D> grid;
	grid.instantiate();
	TypedArray<Vector3> pts;
	for (int i = 0; i < 96; i++) {
		pts.push_back(Vector3(((i * 131) % 2200) - 1100,
				((i * 337) % 600) - 300, ((i * 211) % 2200) - 1100));
	}
	CHECK(grid->rebuild(pts));
	CHECK(bool(grid->get_stats()["indexed_mode"]));
	CHECK(int(grid->get_stats()["occupied_cells"]) > 8);
	for (int i = 0; i < 90; i++) {
		const Vector3 center(((i * 71) % 1900) - 950,
				((i * 43) % 1000) - 500, ((i * 173) % 1900) - 950);
		for (const real_t radius : { real_t(0.0), real_t(24.0), real_t(75.0), real_t(240.0) }) {
			int expected = 0;
			for (int j = 0; j < pts.size(); j++) {
				const Vector3 point = pts[j];
				if (center.distance_squared_to(point) <= radius * radius) {
					expected++;
				}
			}
			CHECK(grid->count_within(center, radius, 8192) == expected);
			CHECK(grid->count_within(center, radius, 2) == MIN(expected, 2));
		}
	}
	CHECK(int(grid->get_stats()["candidate_checks"]) < 2 * 90 * 4 * pts.size());
	CHECK(int(grid->get_stats()["bucket_lookups"]) > 0);
	const int64_t old_lookups = grid->get_stats()["bucket_lookups"];
	CHECK(grid->set_cell_size(1.0));
	CHECK(grid->count_within(Vector3(), 240.0, 8192) >= 0);
	CHECK(int64_t(grid->get_stats()["bucket_lookups"]) == old_lookups); // 481^3 cells fall back to direct scan.
	CHECK(grid->set_cell_size(64.0));
	CHECK(grid->count_within(Vector3(), 75.0) >= 0);
	CHECK_FALSE(grid->set_cell_size(0.0));
	CHECK(grid->get_cell_size() == 64.0);

	TypedArray<Vector3> oversize;
	for (int i = 0; i < 8193; i++) {
		oversize.push_back(Vector3(i, 0, 0));
	}
	CHECK_FALSE(grid->rebuild(oversize));
	CHECK(grid->get_point_count() == 96); // Atomic on size validation.
	grid->clear();
	CHECK(grid->get_point_count() == 0);
	CHECK(int(grid->get_stats()["queries"]) == 0);
	CHECK(int(grid->get_stats()["occupied_cells"]) == 0);
}

} // namespace TestSpatialPointGrid3D
