/**************************************************************************/
/*  test_cull_distance_profile_3d.h                                         */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../cull_distance_profile_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestCullDistanceProfile3D {

TEST_CASE("[CullDistanceProfile3D] nearest longest-side pair and authored cap") {
	Ref<CullDistanceProfile3D> policy;
	policy.instantiate();
	PackedFloat32Array sizes;
	PackedFloat32Array ranges;
	for (const float v : { 64.0f, 1.0f, 24.0f, 4.0f, 10.0f }) {
		sizes.push_back(v);
	}
	for (const float v : { 0.0f, 45.0f, 160.0f, 75.0f, 105.0f }) {
		ranges.push_back(v);
	}
	// Uses longest dimension (24), NOT the AABB diagonal or smallest side.
	const AABB cluster(Vector3(-100, -20, -5), Vector3(24, 2, 8));
	CHECK(policy->get_cull_distance(cluster, sizes, ranges) == 160.0);
	CHECK(policy->get_cull_distance(cluster, sizes, ranges, 90.0) == 90.0);
	CHECK(policy->get_cull_distance(cluster, sizes, ranges, 190.0) == 160.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(70, 1, 1)), sizes, ranges, 120.0) == 120.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(70, 1, 1)), sizes, ranges) == 0.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(1, 1, 1)), sizes, ranges, 150.0) == 45.0);
}

TEST_CASE("[CullDistanceProfile3D] equal-size ties choose strongest positive range") {
	Ref<CullDistanceProfile3D> policy;
	policy.instantiate();
	PackedFloat32Array sizes;
	PackedFloat32Array ranges;
	sizes.push_back(4.0f);
	ranges.push_back(0.0f);
	sizes.push_back(2.0f);
	ranges.push_back(50.0f);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(3, 2, 1)), sizes, ranges) == 50.0);
	sizes.push_back(2.0f);
	ranges.push_back(35.0f);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(3, 2, 1)), sizes, ranges) == 35.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(3, 2, 1)), sizes, ranges, 20.0) == 20.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(3, 2, 1)), sizes, ranges) == 35.0);
}

TEST_CASE("[CullDistanceProfile3D] invalid input is distinguishable from no cull") {
	Ref<CullDistanceProfile3D> policy;
	policy.instantiate();
	PackedFloat32Array sizes;
	PackedFloat32Array ranges;
	const AABB box(Vector3(), Vector3(2, 2, 2));
	CHECK(policy->get_cull_distance(box, sizes, ranges) == -1.0);
	sizes.push_back(2.0f);
	CHECK(policy->get_cull_distance(box, sizes, ranges) == -1.0);
	ranges.push_back(0.0f);
	CHECK(policy->get_cull_distance(box, sizes, ranges) == 0.0);
	CHECK(policy->get_cull_distance(box, sizes, ranges, 60.0) == 60.0);
	CHECK(policy->get_cull_distance(box, sizes, ranges, -1.0) == -1.0);
	CHECK(policy->get_cull_distance(box, sizes, ranges, Math::NaN) == -1.0);
	CHECK(policy->get_cull_distance(box, sizes, ranges, 1000001.0) == -1.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(Math::INF, 0, 0), Vector3(1, 1, 1)), sizes, ranges) == -1.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(-1, 1, 1)), sizes, ranges) == -1.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(1000001, 1, 1)), sizes, ranges) == -1.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(10000001, 0, 0), Vector3.ONE), sizes, ranges) == -1.0);
	ranges[0] = Math::NaN;
	CHECK(policy->get_cull_distance(box, sizes, ranges) == -1.0);
	ranges[0] = 50.0f;
	sizes[0] = -1.0f;
	CHECK(policy->get_cull_distance(box, sizes, ranges) == -1.0);
	sizes[0] = 2.0f;
	for (int i = 1; i < 129; ++i) {
		sizes.push_back(2.0f);
		ranges.push_back(50.0f);
	}
	CHECK(policy->get_cull_distance(box, sizes, ranges) == -1.0);
}

} // namespace TestCullDistanceProfile3D
