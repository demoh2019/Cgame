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
	CHECK(policy->get_cull_distance(AABB(Vector3(10000001, 0, 0), Vector3(1, 1, 1)), sizes, ranges) == -1.0);
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


TEST_CASE("[CullDistanceProfile3D] configured profiles match one-off queries across bounds") {
	Ref<CullDistanceProfile3D> policy;
	policy.instantiate();
	CHECK(policy->get_pair_count() == 0);
	CHECK(policy->get_cached_cull_distance(AABB(Vector3(), Vector3(1, 1, 1)), 120.0) == -1.0);

	PackedFloat32Array sizes;
	PackedFloat32Array ranges;
	for (const float size : { 64.0f, 1.0f, 24.0f, 4.0f, 10.0f }) {
		sizes.push_back(size);
	}
	for (const float range : { 0.0f, 45.0f, 160.0f, 75.0f, 105.0f }) {
		ranges.push_back(range);
	}
	CHECK(policy->configure(sizes, ranges));
	CHECK(policy->get_pair_count() == 5);
	CHECK(policy->configure(sizes, ranges)); // Idempotent, no mutation.
	for (int i = 1; i <= 128; i++) {
		const AABB box(Vector3(-100.0, 0, 20.0), Vector3(double(i) * 0.6, 2, 1));
		const double authored = double(i) * 1.3;
		CHECK(policy->get_cached_cull_distance(box, authored) ==
				policy->get_cull_distance(box, sizes, ranges, authored));
		CHECK(policy->get_cached_cull_distance(box) ==
				policy->get_cull_distance(box, sizes, ranges));
	}
	// Packed array copy-on-write means caller mutation cannot silently retune
	// a profile whose inputs were validated at configure() time.
	ranges.set(0, 999.0f);
	CHECK(policy->get_cached_cull_distance(AABB(Vector3(), Vector3(64, 1, 1))) == 0.0);
	CHECK(policy->get_cull_distance(AABB(Vector3(), Vector3(64, 1, 1)), sizes, ranges) == 999.0);

	PackedFloat32Array invalid_ranges;
	invalid_ranges.push_back(Math::NaN);
	CHECK_FALSE(policy->configure(sizes, invalid_ranges)); // Wrong count.
	CHECK(policy->get_pair_count() == 5);
	CHECK(policy->get_cached_cull_distance(AABB(Vector3(), Vector3(64, 1, 1))) == 0.0);
	for (int i = 1; i < 5; ++i) {
		invalid_ranges.push_back(20.0f);
	}
	CHECK_FALSE(policy->configure(sizes, invalid_ranges)); // Non-finite entry.
	CHECK(policy->get_pair_count() == 5);
	CHECK_FALSE(policy->configure(PackedFloat32Array(), PackedFloat32Array()));
	CHECK(policy->get_pair_count() == 5);
	CHECK(policy->get_cached_cull_distance(AABB(Vector3(Math::INF, 0, 0), Vector3(1, 1, 1))) == -1.0);
	CHECK(policy->get_cached_cull_distance(AABB(Vector3(), Vector3(1, 1, 1)), -10.0) == -1.0);
	CHECK(policy->get_cached_cull_distance(AABB(Vector3(), Vector3(1, 1, 1)), 1000001.0) == -1.0);
	policy->clear_profile();
	CHECK(policy->get_pair_count() == 0);
	CHECK(policy->get_cached_cull_distance(AABB(Vector3(), Vector3(1, 1, 1))) == -1.0);
	CHECK(policy->configure(sizes, ranges));
	CHECK(policy->get_pair_count() == 5);
}

TEST_CASE("[CullDistanceProfile3D] independent configured quality presets") {
	Ref<CullDistanceProfile3D> low;
	Ref<CullDistanceProfile3D> high;
	low.instantiate();
	high.instantiate();
	PackedFloat32Array sizes;
	PackedFloat32Array low_ranges;
	PackedFloat32Array high_ranges;
	sizes.push_back(1.0f);
	low_ranges.push_back(24.75f);
	high_ranges.push_back(54.0f);
	CHECK(low->configure(sizes, low_ranges));
	CHECK(high->configure(sizes, high_ranges));
	const AABB small(Vector3(), Vector3(1, 1, 1));
	CHECK(low->get_cached_cull_distance(small, 100.0) == 24.75);
	CHECK(high->get_cached_cull_distance(small, 100.0) == 54.0);
	CHECK(low->get_cached_cull_distance(small, 10.0) == 10.0);
	low->clear_profile();
	CHECK(high->get_cached_cull_distance(small, 100.0) == 54.0);
}



TEST_CASE("[CullDistanceProfile3D] bulk cached profile equals scalar selection with stable ordering") {
	Ref<CullDistanceProfile3D> policy;
	policy.instantiate();
	const PackedFloat32Array pairs = { 1.0f, 4.0f, 10.0f, 24.0f, 64.0f };
	const PackedFloat32Array ranges = { 45.0f, 75.0f, 105.0f, 160.0f, 0.0f };
	CHECK(policy->configure(pairs, ranges));
	PackedVector3Array positions;
	PackedVector3Array sizes;
	PackedFloat64Array authored;
	for (int i = 0; i < 256; ++i) {
		positions.push_back(Vector3(-100.0 + i, 0.0, -12.0));
		sizes.push_back(Vector3(0.5 + i * 0.33, 2.0, 1.0));
		authored.push_back(i % 3 == 0 ? 0.0 : 60.0 + i);
	}
	const PackedFloat64Array output = policy->get_cached_cull_distances(positions, sizes, authored);
	REQUIRE(output.size() == positions.size());
	for (int i = 0; i < output.size(); ++i) {
		CHECK(output[i] == policy->get_cached_cull_distance(AABB(positions[i], sizes[i]), authored[i]));
		CHECK(output[i] == policy->get_cull_distance(AABB(positions[i], sizes[i]), pairs, ranges, authored[i]));
	}
	CHECK(output[0] == 45.0); // Zero authored cap does not mean "always cull".
	CHECK(output[255] == 0.0); // Largest size-pair is unlimited when authored=0.
}

TEST_CASE("[CullDistanceProfile3D] bulk malformed request fails atomically and is bounded") {
	Ref<CullDistanceProfile3D> policy;
	policy.instantiate();
	PackedVector3Array positions;
	PackedVector3Array sizes;
	PackedFloat64Array caps;
	positions.push_back(Vector3());
	sizes.push_back(Vector3(1, 1, 1));
	caps.push_back(75.0);
	CHECK(policy->get_cached_cull_distances(positions, sizes, caps).is_empty()); // Unconfigured.
	CHECK(policy->configure({ 1.0f }, { 45.0f }));
	CHECK(policy->get_cached_cull_distances(positions, sizes, PackedFloat64Array()).is_empty());
	CHECK(policy->get_cached_cull_distances(positions, PackedVector3Array(), caps).is_empty());
	positions.push_back(Vector3(0, 0, 0));
	sizes.push_back(Vector3(2, 2, 2));
	caps.push_back(Math::NaN); // A late error invalidates the whole batch.
	CHECK(policy->get_cached_cull_distances(positions, sizes, caps).is_empty());
	caps.set(1, 100.0);
	CHECK(policy->get_cached_cull_distances(positions, sizes, caps).size() == 2);
	positions.set(1, Vector3(Math::INF, 0, 0));
	CHECK(policy->get_cached_cull_distances(positions, sizes, caps).is_empty());
	positions.set(1, Vector3(0, 0, 0));
	sizes.set(1, Vector3(-1, 1, 1));
	CHECK(policy->get_cached_cull_distances(positions, sizes, caps).is_empty());
	sizes.set(1, Vector3(2, 2, 2));
	for (int i = 2; i < CullDistanceProfile3D::MAX_BATCH; ++i) {
		positions.push_back(Vector3());
		sizes.push_back(Vector3(1, 1, 1));
		caps.push_back(80.0);
	}
	CHECK(policy->get_cached_cull_distances(positions, sizes, caps).size() ==
			CullDistanceProfile3D::MAX_BATCH);
	positions.push_back(Vector3());
	sizes.push_back(Vector3(1, 1, 1));
	caps.push_back(80.0);
	CHECK(policy->get_cached_cull_distances(positions, sizes, caps).is_empty());
	policy->clear_profile();
	CHECK(policy->get_cached_cull_distances(positions, sizes, caps).is_empty());
}

} // namespace TestCullDistanceProfile3D
