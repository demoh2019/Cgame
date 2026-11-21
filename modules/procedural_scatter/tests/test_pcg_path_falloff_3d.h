/**************************************************************************/
/*  test_pcg_path_falloff_3d.h                                              */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_path_falloff_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGPathFalloff3D {

TEST_CASE("[PCGPathFalloff3D] smooth XZ falloff along segments and endpoints") {
	Ref<PCGPathFalloff3D> mask;
	mask.instantiate();
	const PackedVector3Array path = {
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)
	};
	const PackedVector3Array samples = {
		Vector3(5, 0, 0), Vector3(5, 0, 1), Vector3(5, 0, 2),
		Vector3(5, 0, 3), Vector3(12, 0, 5), Vector3(5, 100, 2),
		Vector3(5, 0, 4), Vector3(-2, 0, 0), Vector3(10, 0, 5)
	};
	const PackedFloat32Array factors = mask->sample_factors(samples, path, 1.0, 3.0);
	REQUIRE(factors.size() == samples.size());
	CHECK(factors[0] == 0.0f);
	CHECK(factors[1] == 0.0f);
	CHECK(Math::is_equal_approx(factors[2], 0.5f));
	CHECK(factors[3] == 1.0f);
	CHECK(Math::is_equal_approx(factors[4], 0.5f));
	CHECK(Math::is_equal_approx(factors[5], 0.5f));
	CHECK(factors[6] == 1.0f);
	CHECK(Math::is_equal_approx(factors[7], 0.5f));
	CHECK(factors[8] == 0.0f);
	CHECK(mask->sample_factors(samples, path, 1.0, 3.0) == factors);
	CHECK(samples[0] == Vector3(5, 0, 0));
}

TEST_CASE("[PCGPathFalloff3D] degenerate segments, one point, and hard boundaries") {
	Ref<PCGPathFalloff3D> mask;
	mask.instantiate();
	const PackedVector3Array points = {
		Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)
	};
	const PackedVector3Array one = { Vector3(0, 0, 0) };
	const PackedVector3Array repeated = {
		Vector3(0, 0, 0), Vector3(0, 5, 0), Vector3(0, 5, 0)
	};
	const PackedFloat32Array one_factor = mask->sample_factors(points, one, 1.0, 3.0);
	REQUIRE(one_factor.size() == 3);
	CHECK(one_factor[0] == 0.0f);
	CHECK(Math::is_equal_approx(one_factor[1], 0.5f));
	CHECK(one_factor[2] == 1.0f);
	CHECK(mask->sample_factors(points, repeated, 1.0, 3.0) == one_factor);
	const PackedFloat32Array hard = mask->sample_factors(points, one, 2.0, 2.0);
	REQUIRE(hard.size() == 3);
	CHECK(hard[0] == 0.0f);
	CHECK(hard[1] == 0.0f);
	CHECK(hard[2] == 1.0f);
	const PackedFloat32Array zero_radius = mask->sample_factors(points, one, 0.0, 0.0);
	REQUIRE(zero_radius.size() == 3);
	CHECK(zero_radius[0] == 0.0f);
	CHECK(zero_radius[1] == 1.0f);
	CHECK(zero_radius[2] == 1.0f);
}

TEST_CASE("[PCGPathFalloff3D] atomic validation and bounded resource use") {
	Ref<PCGPathFalloff3D> mask;
	mask.instantiate();
	const PackedVector3Array points = { Vector3(0, 0, 0), Vector3(10, 0, 0) };
	const PackedVector3Array path = { Vector3(0, 0, 0) };
	CHECK(mask->sample_factors(points, {}, 1.0, 3.0).is_empty());
	CHECK(mask->sample_factors(points, path, -1.0, 3.0).is_empty());
	CHECK(mask->sample_factors(points, path, 4.0, 3.0).is_empty());
	CHECK(mask->sample_factors(points, path, 0.0, 10001.0).is_empty());
	CHECK(mask->sample_factors(points, path, Math::NaN, 3.0).is_empty());
	CHECK(mask->sample_factors(points, path, 1.0, Math::INF).is_empty());
	CHECK(mask->sample_factors(
			{ Vector3(0, 0, 0), Vector3(0, Math::NaN, 0) },
			path, 1.0, 3.0).is_empty());
	CHECK(mask->sample_factors(
			{ Vector3(0, 0, 0), Vector3(10000001, 0, 0) },
			path, 1.0, 3.0).is_empty());
	CHECK(mask->sample_factors(points,
			{ Vector3(0, Math::INF, 0) }, 1.0, 3.0).is_empty());
	CHECK(mask->sample_factors(points,
			{ Vector3(0, 0, 10000001) }, 1.0, 3.0).is_empty());
	PackedVector3Array too_many_path;
	for (int i = 0; i < 257; ++i) {
		too_many_path.push_back(Vector3(i, 0, 0));
	}
	CHECK(mask->sample_factors(points, too_many_path, 1.0, 3.0).is_empty());
	PackedVector3Array too_many_points;
	for (int i = 0; i < 16385; ++i) {
		too_many_points.push_back(Vector3(i, 0, 0));
	}
	CHECK(mask->sample_factors(too_many_points, path, 1.0, 3.0).is_empty());
	too_many_points.resize(16384);
	const PackedFloat32Array bounded = mask->sample_factors(too_many_points, path, 1.0, 3.0);
	REQUIRE(bounded.size() == 16384);
	CHECK(bounded[0] == 0.0f);
	CHECK(bounded[16383] == 1.0f);
	CHECK(mask->sample_factors({}, path, 1.0, 3.0).is_empty());
}

TEST_CASE("[PCGPathFalloff3D] independent road segments preserve strict clearance and source IDs") {
	Ref<PCGPathFalloff3D> filter;
	filter.instantiate();
	// Two independent (not necessarily connected) XZ road segments.
	const PackedVector3Array roads = {
		Vector3(0, 0, 0), Vector3(10, 0, 0),
		Vector3(10, 0, 0), Vector3(10, 0, 10)
	};
	const PackedVector3Array points = {
		Vector3(5, 0, 0),      // Inside first road.
		Vector3(5, 5, 2),      // Exactly on clearance; Y ignored.
		Vector3(5, 0, 1.99),   // Inside.
		Vector3(10, 0, 5),     // Inside second road.
		Vector3(12, 0, 5),     // Exactly on boundary.
		Vector3(12.01, 0, 5),  // Outside.
		Vector3(0, 0, -2),     // Exactly on endpoint boundary.
		Vector3(0, 0, -1),     // Inside endpoint clearance.
		Vector3(50, 0, 50),    // Outside everything.
	};
	const PackedInt32Array expected = { 1, 4, 5, 6, 8 };
	const PackedInt32Array kept = filter->filter_indices_outside_segments(points, roads, 2.0);
	CHECK(kept == expected);
	CHECK(filter->filter_indices_outside_segments(points, roads, 2.0) == kept);
	const PackedInt32Array two = { 1, 4 };
	CHECK(filter->filter_indices_outside_segments(points, roads, 2.0, 2) == two);
	CHECK(filter->filter_indices_outside_segments(points, roads, 2.0, 0).is_empty());
	CHECK(filter->filter_indices_outside_segments(points, roads, 0.0).size() == points.size());
	CHECK(filter->filter_indices_outside_segments(points, {}, 2.0).size() == points.size());
	CHECK(points[0] == Vector3(5, 0, 0)); // Source is never modified.
}

TEST_CASE("[PCGPathFalloff3D] degenerate road segments use the original scalar epsilon") {
	Ref<PCGPathFalloff3D> filter;
	filter.instantiate();
	const PackedVector3Array roads = {
		Vector3(0, -10, 0), Vector3(0, 10, 0), // XZ-degenerate line.
		Vector3(100, 0, 100), Vector3(100, 0, 100)
	};
	const PackedVector3Array points = {
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1.01, 0, 0), Vector3(100, 0, 100),
		Vector3(102, 0, 100)
	};
	const PackedInt32Array expected = { 1, 2, 4 };
	CHECK(filter->filter_indices_outside_segments(points, roads, 1.0) == expected);
	const PackedInt32Array at_radius_two = { 4 };
	CHECK(filter->filter_indices_outside_segments(
			{ Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(102, 0, 100) },
			roads, 2.0) == at_radius_two);
}

TEST_CASE("[PCGPathFalloff3D] road corridor validation is atomic and bounded") {
	Ref<PCGPathFalloff3D> filter;
	filter.instantiate();
	const PackedVector3Array points = { Vector3(0, 0, 0), Vector3(10, 0, 0) };
	const PackedVector3Array road = { Vector3(0, 0, 0), Vector3(10, 0, 0) };
	CHECK(filter->filter_indices_outside_segments(points, { Vector3() }, 2.0).is_empty());
	CHECK(filter->filter_indices_outside_segments(points, road, -1.0).is_empty());
	CHECK(filter->filter_indices_outside_segments(points, road, 10001.0).is_empty());
	CHECK(filter->filter_indices_outside_segments(points, road, Math::NaN).is_empty());
	CHECK(filter->filter_indices_outside_segments(points, road, Math::INF).is_empty());
	CHECK(filter->filter_indices_outside_segments(points, road, 2.0, -1).is_empty());
	CHECK(filter->filter_indices_outside_segments(points, road, 2.0, 16385).is_empty());
	CHECK(filter->filter_indices_outside_segments(
			{ Vector3(0, 0, 0), Vector3(0, Math::NaN, 0) },
			road, 2.0).is_empty());
	CHECK(filter->filter_indices_outside_segments(
			{ Vector3(0, 0, 0), Vector3(10000001, 0, 0) },
			road, 2.0).is_empty());
	CHECK(filter->filter_indices_outside_segments(points,
			{ Vector3(), Vector3(Math::INF, 0, 0) }, 2.0).is_empty());
	CHECK(filter->filter_indices_outside_segments(points,
			{ Vector3(), Vector3(0, 0, 10000001) }, 2.0).is_empty());
	PackedVector3Array excessive_roads;
	for (int i = 0; i < 257; ++i) {
		excessive_roads.push_back(Vector3(i, 0, 0));
		excessive_roads.push_back(Vector3(i, 0, 1));
	}
	CHECK(filter->filter_indices_outside_segments(points, excessive_roads, 2.0).is_empty());
	PackedVector3Array too_many;
	for (int i = 0; i < 16385; ++i) {
		too_many.push_back(Vector3(i, 0, 0));
	}
	CHECK(filter->filter_indices_outside_segments(too_many, road, 2.0).is_empty());
	too_many.resize(16384);
	const PackedInt32Array capped = filter->filter_indices_outside_segments(too_many,
			{}, 2.0);
	REQUIRE(capped.size() == 16384);
	CHECK(capped[0] == 0);
	CHECK(capped[16383] == 16383);
}

} // namespace TestPCGPathFalloff3D
