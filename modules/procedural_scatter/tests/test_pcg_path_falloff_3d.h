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

} // namespace TestPCGPathFalloff3D
