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

} // namespace TestPCGSpatialFilter3D
