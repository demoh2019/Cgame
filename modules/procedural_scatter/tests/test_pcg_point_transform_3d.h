/**************************************************************************/
/*  test_pcg_point_transform_3d.h                                          */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "../pcg_point_transform_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGPointTransform3D {

TEST_CASE("[PCGPointTransform3D] stable IDs keep same scale and yaw through reordering") {
	Ref<PCGPointTransform3D> sampler;
	sampler.instantiate();
	const PackedInt64Array ids = { 99, 15, 48, 7, 99 };
	const PackedVector3Array positions = {
		Vector3(1, 0, 2), Vector3(-4, 2, 6), Vector3(6, 0, 7),
		Vector3(1, 0, -2), Vector3(-8, 0, -10)
	};
	const Array first = sampler->generate_transforms(positions, ids, 2891);
	REQUIRE(first.size() == positions.size());
	CHECK(sampler->generate_transforms(positions, ids, 2891) == first);
	for (int i = 0; i < first.size(); ++i) {
		const Transform3D transform = first[i];
		CHECK(transform.origin == positions[i]);
		CHECK(transform.basis.is_finite());
		const Vector3 scale = transform.basis.get_scale();
		CHECK(scale.x >= 0.85);
		CHECK(scale.x <= 1.15);
		CHECK(scale.y >= 0.85);
		CHECK(scale.y <= 1.15);
		CHECK(Math::is_equal_approx(scale.x, scale.z));
	}
	const PackedInt64Array reorder_ids = { 99, 7, 48, 15 };
	const PackedVector3Array reorder_pos = {
		Vector3(100, 0, 0), positions[3], positions[2], positions[1]
	};
	const Array reordered = sampler->generate_transforms(reorder_pos, reorder_ids, 2891);
	REQUIRE(reordered.size() == 4);
	for (int i = 0; i < reordered.size(); ++i) {
		const Transform3D sample = reordered[i];
		const Transform3D original = first[i == 0 ? 0 : (4 - i)];
		CHECK(sample.basis.is_equal_approx(original.basis));
		CHECK(sample.origin == reorder_pos[i]);
	}
	const Transform3D duplicate = first[4];
	const Transform3D original = first[0];
	CHECK(duplicate.basis == original.basis); // Shared stable ID.
	CHECK(duplicate.origin != original.origin);
}

TEST_CASE("[PCGPointTransform3D] independent stable ranges and seeded variation") {
	Ref<PCGPointTransform3D> sampler;
	sampler.instantiate();
	PackedVector3Array positions;
	PackedInt64Array ids;
	for (int i = 0; i < 512; ++i) {
		positions.push_back(Vector3(i % 17, 1, i / 17));
		ids.push_back(i);
	}
	const Array samples = sampler->generate_transforms(
			positions, ids, 1809, 6.283185307179586, 0.7, 1.3, 0.6, 1.4);
	REQUIRE(samples.size() == 512);
	bool varied_yaw = false;
	bool varied_size = false;
	for (int i = 0; i < samples.size(); ++i) {
		const Transform3D transform = samples[i];
		CHECK(transform.origin == positions[i]);
		const Vector3 scale = transform.basis.get_scale();
		CHECK(scale.x >= 0.7);
		CHECK(scale.x <= 1.3);
		CHECK(scale.y >= 0.6);
		CHECK(scale.y <= 1.4);
		if (!Math::is_equal_approx(scale.x, 1.0)) {
			varied_size = true;
		}
		if (Math::abs(transform.basis.get_column(0).z) > 0.2) {
			varied_yaw = true;
		}
	}
	CHECK(varied_size);
	CHECK(varied_yaw);
	const Array forced = sampler->generate_transforms(
			positions, ids, 1809, 0, 1, 1, 1, 1);
	REQUIRE(forced.size() == 512);
	for (int i = 0; i < forced.size(); ++i) {
		const Transform3D transform = forced[i];
		CHECK(transform.basis == Basis());
	}
	const Array other_seed = sampler->generate_transforms(positions, ids, 1810);
	REQUIRE(other_seed.size() == 512);
	CHECK(other_seed != samples);
}

TEST_CASE("[PCGPointTransform3D] invalid positions IDs and ranges are rejected atomically") {
	Ref<PCGPointTransform3D> sampler;
	sampler.instantiate();
	const PackedVector3Array positions = { Vector3(0, 0, 0), Vector3(1, 0, 0) };
	const PackedInt64Array ids = { 1, 2 };
	CHECK(sampler->generate_transforms(positions, { 1 }).is_empty());
	CHECK(sampler->generate_transforms(positions, { 1, -1 }).is_empty());
	CHECK(sampler->generate_transforms(positions, { 1, 2147483648ll }).is_empty());
	CHECK(sampler->generate_transforms(positions, ids, -1).is_empty());
	CHECK(sampler->generate_transforms(positions, ids, 0, -1).is_empty());
	CHECK(sampler->generate_transforms(positions, ids, 0, 7).is_empty());
	CHECK(sampler->generate_transforms(positions, ids, 0, Math::NaN).is_empty());
	CHECK(sampler->generate_transforms(positions, ids, 0, 1, 0.001).is_empty());
	CHECK(sampler->generate_transforms(positions, ids, 0, 1, 2, 1).is_empty());
	CHECK(sampler->generate_transforms(positions, ids, 0, 1, 1, 1, 4, 2).is_empty());
	CHECK(sampler->generate_transforms(positions, ids, 0, 1, 1, 1, 0.1, Math::INF).is_empty());
	CHECK(sampler->generate_transforms({ Vector3(), Vector3(Math::NaN, 0, 0) }, ids).is_empty());
	CHECK(sampler->generate_transforms({ Vector3(), Vector3(10000001, 0, 0) }, ids).is_empty());
	CHECK(sampler->generate_transforms({}, {}).is_empty()); // Valid empty.
	PackedVector3Array many_points;
	PackedInt64Array many_ids;
	many_points.resize(16385);
	many_ids.resize(16385);
	CHECK(sampler->generate_transforms(many_points, many_ids).is_empty());
	many_points.resize(16384);
	many_ids.resize(16384);
	CHECK(sampler->generate_transforms(many_points, many_ids).size() == 16384);
}

} // namespace TestPCGPointTransform3D
