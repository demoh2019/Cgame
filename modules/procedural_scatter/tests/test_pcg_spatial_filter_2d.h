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

} // namespace TestPCGSpatialFilter2D
