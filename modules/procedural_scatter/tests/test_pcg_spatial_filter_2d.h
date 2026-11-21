/**************************************************************************/
/*  test_pcg_spatial_filter_2d.h                                           */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_spatial_filter_2d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGSpatialFilter2D {

TEST_CASE("[PCGSpatialFilter2D] stable input-order filtering and inclusive distance boundary") {
	Ref<PCGSpatialFilter2D> filter;
	filter.instantiate();
	PackedVector2Array candidates;
	candidates.push_back(Vector2(0, 0));
	candidates.push_back(Vector2(0.5, 0));
	candidates.push_back(Vector2(2, 0));
	candidates.push_back(Vector2(-2, 0));
	candidates.push_back(Vector2(2, 1));
	candidates.push_back(Vector2(0, 0));
	candidates.push_back(Vector2(2, 2));
	const PackedVector2Array original = candidates;

	const PackedInt32Array accepted = filter->filter_indices(candidates, 2.0);
	REQUIRE(accepted.size() == 4);
	CHECK(accepted[0] == 0);
	CHECK(accepted[1] == 2);
	CHECK(accepted[2] == 3);
	CHECK(accepted[3] == 6);
	CHECK(filter->filter_indices(candidates, 2.0) == accepted);
	CHECK(candidates == original);
	CHECK(filter->filter_indices(candidates, 0.0).size() == candidates.size());
	const PackedInt32Array limited_unfiltered = filter->filter_indices(candidates, 0.0, 2);
	REQUIRE(limited_unfiltered.size() == 2);
	CHECK(limited_unfiltered[0] == 0);
	CHECK(limited_unfiltered[1] == 1);
	const PackedInt32Array limited_filtered = filter->filter_indices(candidates, 2.0, 2);
	REQUIRE(limited_filtered.size() == 2);
	CHECK(limited_filtered[0] == 0);
	CHECK(limited_filtered[1] == 2);
}

TEST_CASE("[PCGSpatialFilter2D] spatial buckets check across cell borders and negative coordinates") {
	Ref<PCGSpatialFilter2D> filter;
	filter.instantiate();
	PackedVector2Array candidates;
	candidates.push_back(Vector2(0.95, 0));
	candidates.push_back(Vector2(1.05, 0)); // Adjacent cells but only 0.1 apart.
	candidates.push_back(Vector2(2.5, 0));
	candidates.push_back(Vector2(-1, 0));
	candidates.push_back(Vector2(-1.3, 0)); // Same negative cell neighborhood.
	candidates.push_back(Vector2(4.2, 0));
	const PackedInt32Array chosen = filter->filter_indices(candidates, 1.0);
	REQUIRE(chosen.size() == 4);
	CHECK(chosen[0] == 0);
	CHECK(chosen[1] == 2);
	CHECK(chosen[2] == 3);
	CHECK(chosen[3] == 5);
	for (int i = 0; i < chosen.size(); i++) {
		for (int j = i + 1; j < chosen.size(); j++) {
			CHECK(candidates[chosen[i]].distance_squared_to(candidates[chosen[j]]) >= 1.0);
		}
	}
}

TEST_CASE("[PCGSpatialFilter2D] reject unsafe inputs atomically") {
	Ref<PCGSpatialFilter2D> filter;
	filter.instantiate();
	PackedVector2Array candidates;
	candidates.push_back(Vector2(0, 0));
	candidates.push_back(Vector2(1, 0));
	CHECK(filter->filter_indices(candidates, -1.0).is_empty());
	CHECK(filter->filter_indices(candidates, 0.01).is_empty());
	CHECK(filter->filter_indices(candidates, Math::NaN).is_empty());
	CHECK(filter->filter_indices(candidates, Math::INF).is_empty());
	CHECK(filter->filter_indices(candidates, 10001.0).is_empty());
	CHECK(filter->filter_indices(candidates, 1.0, -1).is_empty());
	CHECK(filter->filter_indices(candidates, 1.0, 4097).is_empty());
	CHECK(filter->filter_indices(candidates, 1.0, 0).is_empty());
	candidates.push_back(Vector2(Math::NaN, 0));
	CHECK(filter->filter_indices(candidates, 1.0).is_empty()); // No prefix output.
	candidates.remove_at(2);
	candidates.push_back(Vector2(10000001, 0));
	CHECK(filter->filter_indices(candidates, 1.0).is_empty());
	candidates.resize(16385);
	CHECK(filter->filter_indices(candidates, 1.0).is_empty());
}

TEST_CASE("[PCGSpatialFilter2D] 16k bounded inputs and maximum output budget") {
	Ref<PCGSpatialFilter2D> filter;
	filter.instantiate();
	PackedVector2Array candidates;
	for (int i = 0; i < 16384; i++) {
		candidates.push_back(Vector2(i * 2.0, 0));
	}
	const PackedInt32Array chosen = filter->filter_indices(candidates, 1.0);
	CHECK(chosen.size() == 4096);
	CHECK(chosen[0] == 0);
	CHECK(chosen[4095] == 4095);
	CHECK(filter->filter_indices(candidates, 1.0, 12).size() == 12);
}

TEST_CASE("[PCGSpatialFilter2D] scale-aware priority with original-index output") {
	Ref<PCGSpatialFilter2D> filter;
	filter.instantiate();
	PackedVector2Array points;
	PackedFloat32Array scales;
	const Vector2 positions[] = { Vector2(0, 0), Vector2(0.9, 0),
		Vector2(3, 0), Vector2(3.8, 0), Vector2(-2.6, 0) };
	const float sizes[] = { 0.5f, 2.0f, 1.0f, 0.5f, 1.2f };
	for (int i = 0; i < 5; ++i) {
		points.push_back(positions[i]);
		scales.push_back(sizes[i]);
	}
	const PackedInt32Array large_first = filter->filter_indices_scaled(points, scales, 1.0);
	REQUIRE(large_first.size() == 4);
	CHECK(large_first[0] == 1);
	CHECK(large_first[1] == 2);
	CHECK(large_first[2] == 3);
	CHECK(large_first[3] == 4);
	const PackedInt32Array input_first = filter->filter_indices_scaled(points, scales, 1.0, 4096, false);
	REQUIRE(input_first.size() == 4);
	CHECK(input_first[0] == 0);
	CHECK(input_first[1] == 2);
	CHECK(input_first[2] == 3);
	CHECK(input_first[3] == 4);
	CHECK(filter->filter_indices_scaled(points, scales, 1.0) == large_first);
	CHECK(points.size() == 5);
	CHECK(scales[0] == 0.5f);

	PackedFloat32Array ones;
	ones.resize(5);
	for (int i = 0; i < 5; ++i) {
		ones.set(i, 1.0f);
	}
	CHECK(filter->filter_indices_scaled(points, ones, 1.0) == filter->filter_indices(points, 1.0));
	CHECK(filter->filter_indices_scaled(points, scales, 0.0, 2).size() == 2);
	CHECK(filter->filter_indices_scaled(points, scales, 0.0, 2)[0] == 0);
}

TEST_CASE("[PCGSpatialFilter2D] scale-aware spatial cells and inclusive footprint boundary") {
	Ref<PCGSpatialFilter2D> filter;
	filter.instantiate();
	PackedVector2Array points;
	PackedFloat32Array scales;
	points.push_back(Vector2(0.99, -1.0));
	points.push_back(Vector2(2.01, -1.0)); // Two cells away but 1.02 < 2.0.
	points.push_back(Vector2(3.0, 1.0));
	scales.push_back(2.0f);
	scales.push_back(2.0f);
	scales.push_back(0.5f);
	const PackedInt32Array accepted = filter->filter_indices_scaled(points, scales, 1.0, 4096, false);
	REQUIRE(accepted.size() == 2);
	CHECK(accepted[0] == 0);
	CHECK(accepted[1] == 2);

	PackedVector2Array boundary_points;
	PackedFloat32Array boundary_scales;
	boundary_points.push_back(Vector2(0, 0));
	boundary_points.push_back(Vector2(1.25, 0));
	boundary_scales.push_back(0.5f);
	boundary_scales.push_back(2.0f);
	CHECK(filter->filter_indices_scaled(boundary_points, boundary_scales, 1.0).size() == 2);
}

TEST_CASE("[PCGSpatialFilter2D] scaled input validates atomically and caps results") {
	Ref<PCGSpatialFilter2D> filter;
	filter.instantiate();
	PackedVector2Array points;
	PackedFloat32Array scales;
	points.push_back(Vector2(0, 0));
	points.push_back(Vector2(10, 0));
	scales.push_back(1.0f);
	CHECK(filter->filter_indices_scaled(points, scales, 1.0).is_empty()); // Mismatch.
	scales.push_back(1.0f);
	CHECK(filter->filter_indices_scaled(points, scales, -1.0).is_empty());
	CHECK(filter->filter_indices_scaled(points, scales, 0.01).is_empty());
	CHECK(filter->filter_indices_scaled(points, scales, Math::NaN).is_empty());
	CHECK(filter->filter_indices_scaled(points, scales, 10001.0).is_empty());
	CHECK(filter->filter_indices_scaled(points, scales, 1.0, -1).is_empty());
	CHECK(filter->filter_indices_scaled(points, scales, 1.0, 4097).is_empty());
	CHECK(filter->filter_indices_scaled(points, scales, 1.0, 0).is_empty());
	scales.set(1, Math::NaN);
	CHECK(filter->filter_indices_scaled(points, scales, 1.0).is_empty());
	scales.set(1, 0.49f);
	CHECK(filter->filter_indices_scaled(points, scales, 1.0).is_empty());
	scales.set(1, 2.01f);
	CHECK(filter->filter_indices_scaled(points, scales, 1.0).is_empty());
	scales.set(1, 1.0f);
	points.set(1, Vector2(Math::INF, 0));
	CHECK(filter->filter_indices_scaled(points, scales, 1.0).is_empty());
	points.set(1, Vector2(10, 0));
	CHECK(filter->filter_indices_scaled(points, scales, 1.0, 1).size() == 1);
	points.resize(16385);
	scales.resize(16385);
	CHECK(filter->filter_indices_scaled(points, scales, 1.0).is_empty());
}


} // namespace TestPCGSpatialFilter2D
