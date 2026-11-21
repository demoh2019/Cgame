/**************************************************************************/
/*  test_pcg_spatial_filter_3d.h                                            */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_spatial_filter_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGSpatialFilter3D {

TEST_CASE("[PCGSpatialFilter3D] stable ordering, height-aware spacing and exact boundary") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	PackedVector3Array p;
	for (const Vector3 &point : { Vector3(0, 0, 0), Vector3(0.25, 0, 0),
				Vector3(0.25, 3, 0), Vector3(2, 0, 0), Vector3(0, 0, 2),
				Vector3(-2, 0, 0), Vector3(0.25, 3, 0), Vector3(2, 0, 2) }) {
		p.push_back(point);
	}
	const PackedVector3Array original = p;
	const PackedInt32Array out = filter->filter_indices(p, 2.0);
	REQUIRE(out.size() == 6);
	CHECK(out[0] == 0);
	CHECK(out[1] == 2);
	CHECK(out[2] == 3);
	CHECK(out[3] == 4);
	CHECK(out[4] == 5);
	CHECK(out[5] == 7);
	CHECK(p == original);
	CHECK(filter->filter_indices(p, 2.0) == out);
	CHECK(filter->filter_indices(p, 0.0).size() == p.size());
	const PackedInt32Array capped = filter->filter_indices(p, 2.0, 2);
	REQUIRE(capped.size() == 2);
	CHECK(capped[0] == 0);
	CHECK(capped[1] == 2);
}

TEST_CASE("[PCGSpatialFilter3D] negative and adjacent spatial cells") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	PackedVector3Array p;
	for (const Vector3 &point : { Vector3(0.95, 0.95, 0.95),
				Vector3(1.05, 1.05, 1.05), Vector3(-0.1, -0.1, -0.1),
				Vector3(-0.25, -0.2, -0.2), Vector3(3, 3, 3) }) {
		p.push_back(point);
	}
	const PackedInt32Array out = filter->filter_indices(p, 1.0);
	REQUIRE(out.size() == 3);
	CHECK(out[0] == 0);
	CHECK(out[1] == 2);
	CHECK(out[2] == 4);
}

TEST_CASE("[PCGSpatialFilter3D] atomic invalid input rejection and bounded output") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	PackedVector3Array p;
	p.push_back(Vector3(0, 0, 0));
	p.push_back(Vector3(1, 0, 0));
	CHECK(filter->filter_indices(p, -1.0).is_empty());
	CHECK(filter->filter_indices(p, 0.01).is_empty());
	CHECK(filter->filter_indices(p, Math::NaN).is_empty());
	CHECK(filter->filter_indices(p, Math::INF).is_empty());
	CHECK(filter->filter_indices(p, 10001.0).is_empty());
	CHECK(filter->filter_indices(p, 1.0, -1).is_empty());
	CHECK(filter->filter_indices(p, 1.0, 4097).is_empty());
	CHECK(filter->filter_indices(p, 1.0, 0).is_empty());
	p.push_back(Vector3(0, Math::NaN, 0));
	CHECK(filter->filter_indices(p, 1.0).is_empty());
	p.remove_at(2);
	p.push_back(Vector3(0, 0, 10000001));
	CHECK(filter->filter_indices(p, 1.0).is_empty());
	p.resize(16385);
	CHECK(filter->filter_indices(p, 1.0).is_empty());
	p.resize(0);
	for (int i = 0; i < 16384; ++i) {
		p.push_back(Vector3(i * 2.0, 0, 0));
	}
	const PackedInt32Array capped = filter->filter_indices(p, 1.0);
	REQUIRE(capped.size() == 4096);
	CHECK(capped[0] == 0);
	CHECK(capped[4095] == 4095);
}


TEST_CASE("[PCGSpatialFilter3D] scaled footprints respect vertical terraces and original-order indices") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array points = { Vector3(0, 0, 0), Vector3(0.9, 0, 0),
		Vector3(3, 0, 0), Vector3(3.8, 0, 0), Vector3(-2.6, 0, 0),
		Vector3(0.9, 3, 0) };
	const PackedFloat32Array scales = { 0.5f, 2.0f, 1.0f, 0.5f, 1.2f, 2.0f };
	const PackedInt32Array large_first = filter->filter_indices_scaled(points, scales, 1.0);
	REQUIRE(large_first.size() == 5);
	CHECK(large_first[0] == 1); // Larger bush wins over the smaller neighbour.
	CHECK(large_first[1] == 2);
	CHECK(large_first[2] == 3); // Exactly enough room after a smaller footprint.
	CHECK(large_first[3] == 4);
	CHECK(large_first[4] == 5); // Same horizontal position, but higher terrace.
	const PackedInt32Array original_first = filter->filter_indices_scaled(points, scales, 1.0, 4096, false);
	REQUIRE(original_first.size() == 5);
	CHECK(original_first[0] == 0);
	CHECK(original_first[1] == 2);
	CHECK(original_first[4] == 5);
	const PackedInt32Array zero = filter->filter_indices_scaled(points, scales, 0.0, 2);
	REQUIRE(zero.size() == 2);
	CHECK(zero[0] == 0);
	CHECK(zero[1] == 1);

	PackedFloat32Array ones;
	ones.resize(points.size());
	for (int i = 0; i < points.size(); ++i) {
		ones.set(i, 1.0f);
	}
	CHECK(filter->filter_indices_scaled(points, ones, 1.0) == filter->filter_indices(points, 1.0));
	CHECK(filter->filter_indices_scaled(points, scales, 1.0) == large_first);
	CHECK(points[0] == Vector3(0, 0, 0));
	CHECK(scales[0] == 0.5f);
}

TEST_CASE("[PCGSpatialFilter3D] scaled 5x5x5 bucket boundaries and all-or-nothing validation") {
	Ref<PCGSpatialFilter3D> filter;
	filter.instantiate();
	const PackedVector3Array crossing = {
		Vector3(0.99, -1.0, 0.99), Vector3(2.01, -1.0, 0.99), Vector3(0.99, 1.2, 0.99)
	};
	const PackedFloat32Array big = { 2.0f, 2.0f, 2.0f };
	const PackedInt32Array picked = filter->filter_indices_scaled(crossing, big, 1.0, 4096, false);
	REQUIRE(picked.size() == 2);
	CHECK(picked[0] == 0);
	CHECK(picked[1] == 2); // Height difference > 2*spacing is allowed.
	const PackedVector3Array edge = { Vector3(0, 0, 0), Vector3(1.25, 0, 0) };
	CHECK(filter->filter_indices_scaled(edge, { 0.5f, 2.0f }, 1.0).size() == 2);
	ERR_PRINT_OFF
	CHECK(filter->filter_indices_scaled(crossing, { 1.0f }, 1.0).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, -1.0).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, 0.01).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, Math::INF).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, 1.0, -1).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, big, 1.0, 4097).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, { 2.0f, Math::NaN, 1.0f }, 1.0).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, { 2.0f, 0.49f, 1.0f }, 1.0).is_empty());
	CHECK(filter->filter_indices_scaled(crossing, { 2.0f, 2.01f, 1.0f }, 1.0).is_empty());
	const PackedVector3Array invalid = { Vector3(0, 0, 0), Vector3(0, Math::NaN, 0) };
	CHECK(filter->filter_indices_scaled(invalid, { 1.0f, 1.0f }, 1.0).is_empty());
	ERR_PRINT_ON
}

} // namespace TestPCGSpatialFilter3D
