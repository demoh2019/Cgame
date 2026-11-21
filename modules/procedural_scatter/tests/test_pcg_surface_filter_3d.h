/**************************************************************************/
/*  test_pcg_surface_filter_3d.h                                            */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_surface_filter_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGSurfaceFilter3D {

TEST_CASE("[PCGSurfaceFilter3D] slope and height selection preserves input indices") {
	Ref<PCGSurfaceFilter3D> filter;
	filter.instantiate();
	PackedVector3Array positions;
	PackedVector3Array normals;
	positions.push_back(Vector3(0, 10, 0));
	normals.push_back(Vector3(0, 1, 0)); // flat.
	positions.push_back(Vector3(2, 20, 0));
	normals.push_back(Vector3(0, 0.8660254, 0.5)); // 30 degrees.
	positions.push_back(Vector3(4, 30, 0));
	normals.push_back(Vector3(0, 0.5, 0.8660254)); // 60 degrees.
	positions.push_back(Vector3(6, 40, 0));
	normals.push_back(Vector3(1, 0, 0)); // vertical.
	positions.push_back(Vector3(8, 50, 0));
	normals.push_back(Vector3(0, -1, 0)); // down-facing.
	const PackedVector3Array untouched = positions;
	const PackedInt32Array flat = filter->filter_indices(positions, normals, 0.0, 35.0);
	REQUIRE(flat.size() == 2);
	CHECK(flat[0] == 0);
	CHECK(flat[1] == 1);
	const PackedInt32Array cliffs = filter->filter_indices(positions, normals, 45.0, 90.0, 25.0, 45.0);
	REQUIRE(cliffs.size() == 2);
	CHECK(cliffs[0] == 2);
	CHECK(cliffs[1] == 3);
	CHECK(filter->filter_indices(positions, normals, 0.0, 90.0).size() == 4);
	CHECK(filter->filter_indices(positions, normals, 0.0, 35.0, 20.0, 20.0).size() == 1);
	CHECK(filter->filter_indices(positions, normals, 0.0, 35.0, 20.0, 20.0, 0).is_empty());
	CHECK(positions == untouched);
	CHECK(filter->filter_indices(positions, normals, 0.0, 35.0) == flat);
}

TEST_CASE("[PCGSurfaceFilter3D] invalid inputs fail atomically") {
	Ref<PCGSurfaceFilter3D> filter;
	filter.instantiate();
	PackedVector3Array positions;
	positions.push_back(Vector3(0, 0, 0));
	positions.push_back(Vector3(1, 1, 1));
	PackedVector3Array normals;
	normals.push_back(Vector3(0, 1, 0));
	normals.push_back(Vector3(0, 1, 0));
	CHECK(filter->filter_indices(positions, PackedVector3Array()).is_empty());
	CHECK(filter->filter_indices(positions, normals, -1.0).is_empty());
	CHECK(filter->filter_indices(positions, normals, 0.0, 91.0).is_empty());
	CHECK(filter->filter_indices(positions, normals, 40.0, 30.0).is_empty());
	CHECK(filter->filter_indices(positions, normals, Math::NaN).is_empty());
	CHECK(filter->filter_indices(positions, normals, 0.0, Math::INF).is_empty());
	CHECK(filter->filter_indices(positions, normals, 0.0, 90.0, 2.0, 1.0).is_empty());
	CHECK(filter->filter_indices(positions, normals, 0.0, 90.0, -10000001).is_empty());
	CHECK(filter->filter_indices(positions, normals, 0.0, 90.0, -10000000, 10000001).is_empty());
	CHECK(filter->filter_indices(positions, normals, 0.0, 90.0, -10000000, 10000000, -1).is_empty());
	CHECK(filter->filter_indices(positions, normals, 0.0, 90.0, -10000000, 10000000, 4097).is_empty());
	normals.set(1, Vector3());
	CHECK(filter->filter_indices(positions, normals).is_empty());
	normals.set(1, Vector3(0, Math::NaN, 0));
	CHECK(filter->filter_indices(positions, normals).is_empty());
	normals.set(1, Vector3(0, 1, 0));
	positions.set(1, Vector3(Math::INF, 1, 1));
	CHECK(filter->filter_indices(positions, normals).is_empty());
	positions.set(1, Vector3(10000001, 1, 1));
	CHECK(filter->filter_indices(positions, normals).is_empty());
	positions.resize(16385);
	normals.resize(16385);
	CHECK(filter->filter_indices(positions, normals).is_empty());
}

TEST_CASE("[PCGSurfaceFilter3D] bounded output and normal scale invariance") {
	Ref<PCGSurfaceFilter3D> filter;
	filter.instantiate();
	PackedVector3Array positions;
	PackedVector3Array normals;
	for (int i = 0; i < 4097; ++i) {
		positions.push_back(Vector3(i, 0, 0));
		normals.push_back(Vector3(0, i % 2 == 0 ? 2 : 0.5, 0));
	}
	const PackedInt32Array all = filter->filter_indices(positions, normals);
	REQUIRE(all.size() == 4096);
	CHECK(all[0] == 0);
	CHECK(all[4095] == 4095);
	const PackedInt32Array limited = filter->filter_indices(positions, normals, 0.0, 45.0,
			-10000000.0, 10000000.0, 3);
	REQUIRE(limited.size() == 3);
	CHECK(limited[0] == 0);
	CHECK(limited[1] == 1);
	CHECK(limited[2] == 2);
}

TEST_CASE("[PCGSurfaceFilter3D] surface alignment respects authored yaw scale and tilt cap") {
	Ref<PCGSurfaceFilter3D> filter;
	filter.instantiate();
	Array transforms;
	PackedVector3Array normals;
	const Transform3D flat(Basis(Vector3::UP, 0.3).scaled(Vector3(1.5, 1.5, 1.5)),
			Vector3(7.0, 13.0, -2.0));
	const Transform3D inclined(Basis(Vector3::UP, 0.7).scaled(Vector3(2.0, 2.0, 2.0)),
			Vector3(11.0, 15.0, -8.0));
	transforms.push_back(flat);
	transforms.push_back(inclined);
	normals.push_back(Vector3::UP);
	normals.push_back(Vector3(0.0, 0.70710678, 0.70710678)); // 45-degree slope.

	const Array aligned = filter->align_transforms(transforms, normals, 30.0);
	REQUIRE(aligned.size() == 2);
	const Transform3D first = aligned[0];
	const Transform3D second = aligned[1];
	CHECK(first == flat);
	CHECK(second.origin == inclined.origin);
	CHECK(Math::is_equal_approx(second.basis.get_column(0).length(), real_t(2.0)));
	CHECK(Math::is_equal_approx(second.basis.get_column(1).length(), real_t(2.0)));
	CHECK(Math::is_equal_approx(second.basis.get_column(2).length(), real_t(2.0)));
	CHECK(Math::is_equal_approx(double(second.basis.get_column(1).normalized().y), Math::cos(Math::deg_to_rad(30.0))));
	CHECK(second.basis.get_column(1).normalized().z > 0.0);
	// Left-multiplying the tilt keeps the original authored orientation of
	// the local X and Z axes relative to the selected new up-axis.
	const Transform3D original_again = transforms[1];
	CHECK(original_again == inclined);
	CHECK(filter->align_transforms(transforms, normals, 30.0) == aligned);
	CHECK(filter->align_transforms(transforms, normals, 0.0) == transforms);
}

TEST_CASE("[PCGSurfaceFilter3D] surface alignment clamps vertical terrain safely") {
	Ref<PCGSurfaceFilter3D> filter;
	filter.instantiate();
	Array transforms;
	transforms.push_back(Transform3D());
	PackedVector3Array normals;
	normals.push_back(Vector3(2, 0, 0)); // Unnormalized, exactly vertical.
	const Array aligned = filter->align_transforms(transforms, normals, 20.0);
	REQUIRE(aligned.size() == 1);
	const Transform3D result = aligned[0];
	CHECK(Math::is_equal_approx(double(result.basis.get_column(1).normalized().y), Math::cos(Math::deg_to_rad(20.0))));
	CHECK(result.basis.get_column(1).x > 0);
	CHECK(result.origin == Vector3());
	CHECK(filter->align_transforms(Array(), PackedVector3Array()).is_empty());
}

TEST_CASE("[PCGSurfaceFilter3D] malformed surface alignment buffers fail atomically") {
	Ref<PCGSurfaceFilter3D> filter;
	filter.instantiate();
	Array transforms;
	transforms.push_back(Transform3D());
	transforms.push_back(Transform3D());
	PackedVector3Array normals;
	normals.push_back(Vector3::UP);
	normals.push_back(Vector3::UP);
	CHECK(filter->align_transforms(transforms, PackedVector3Array()).is_empty());
	CHECK(filter->align_transforms(transforms, normals, -1.0).is_empty());
	CHECK(filter->align_transforms(transforms, normals, 91.0).is_empty());
	CHECK(filter->align_transforms(transforms, normals, Math::NaN).is_empty());
	CHECK(filter->align_transforms(transforms, normals, Math::INF).is_empty());
	normals.set(1, Vector3());
	CHECK(filter->align_transforms(transforms, normals).is_empty());
	normals.set(1, Vector3(0, -1, 0));
	CHECK(filter->align_transforms(transforms, normals).is_empty());
	normals.set(1, Vector3(Math::NaN, 1, 0));
	CHECK(filter->align_transforms(transforms, normals).is_empty());
	normals.set(1, Vector3::UP);
	transforms[1] = 12; // Non-transform variants are not silently coerced.
	CHECK(filter->align_transforms(transforms, normals).is_empty());
	transforms[1] = Transform3D(Basis(), Vector3(10000001, 0, 0));
	CHECK(filter->align_transforms(transforms, normals).is_empty());
	transforms[1] = Transform3D();
	for (int i = transforms.size(); i < 16385; ++i) {
		transforms.push_back(Transform3D());
		normals.push_back(Vector3::UP);
	}
	CHECK(filter->align_transforms(transforms, normals).is_empty());
}

} // namespace TestPCGSurfaceFilter3D
