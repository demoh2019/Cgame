/**************************************************************************/
/*  test_pcg_polygon_mask_3d.h                                             */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_polygon_mask_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGPolygonMask3D {

TEST_CASE("[PCGPolygonMask3D] smooth density covers closed edges, outside distance and inversion") {
	Ref<PCGPolygonMask3D> sampler;
	sampler.instantiate();
	const PackedVector3Array polygon = {
		Vector3(-2, 0, -2), Vector3(2, 0, -2),
		Vector3(2, 0, 2), Vector3(-2, 0, 2)
	};
	const PackedVector3Array points = {
		Vector3(0, 100, 0), Vector3(2, 0, 0),
		Vector3(4, 0, 0), Vector3(6, 0, 0),
		Vector3(2, 50, 2), Vector3(-4, -200, 0),
		Vector3(100, 0, 100)
	};
	const PackedFloat32Array density = sampler->sample_factors(points, polygon, 4.0);
	REQUIRE(density.size() == points.size());
	CHECK(density[0] == 0.0f);
	CHECK(density[1] == 0.0f);
	CHECK(Math::is_equal_approx(density[2], 0.5f));
	CHECK(density[3] == 1.0f);
	CHECK(density[4] == 0.0f);
	CHECK(Math::is_equal_approx(density[5], 0.5f));
	CHECK(density[6] == 1.0f);
	const PackedFloat32Array inside = sampler->sample_factors(points, polygon, 4.0, true);
	REQUIRE(inside.size() == density.size());
	for (int i = 0; i < density.size(); ++i) {
		CHECK(Math::is_equal_approx(density[i] + inside[i], 1.0f));
	}
	CHECK(sampler->sample_factors(points, polygon, 4.0) == density);
	CHECK(points[0] == Vector3(0, 100, 0)); // Never edit caller-owned positions.
	const PackedFloat32Array hard = sampler->sample_factors(points, polygon, 0.0);
	REQUIRE(hard.size() == points.size());
	CHECK(hard[0] == 0.0f);
	CHECK(hard[1] == 0.0f);
	CHECK(hard[2] == 1.0f);
	CHECK(hard[3] == 1.0f);
	CHECK(hard[4] == 0.0f);
}

TEST_CASE("[PCGPolygonMask3D] concave polygon retains true interior without convex-hull filling") {
	Ref<PCGPolygonMask3D> sampler;
	sampler.instantiate();
	// A simple concave pocket: the notch above (4,4) is outside.
	const PackedVector3Array concave = {
		Vector3(0, 0, 0), Vector3(8, 0, 0),
		Vector3(8, 0, 8), Vector3(4, 0, 4), Vector3(0, 0, 8)
	};
	const PackedVector3Array reversed = {
		Vector3(0, 0, 8), Vector3(4, 0, 4),
		Vector3(8, 0, 8), Vector3(8, 0, 0), Vector3(0, 0, 0)
	};
	const PackedVector3Array points = {
		Vector3(4, 0, 3), Vector3(4, 200, 4),
		Vector3(4, 0, 6), Vector3(4, 0, 8),
		Vector3(10, 0, 5)
	};
	const PackedFloat32Array factors = sampler->sample_factors(points, concave, 2.0);
	REQUIRE(factors.size() == points.size());
	CHECK(factors[0] == 0.0f);
	CHECK(factors[1] == 0.0f);
	CHECK((factors[2] > 0.7f && factors[2] < 0.9f));
	CHECK(factors[3] == 1.0f);
	CHECK(factors[4] == 1.0f);
	CHECK(sampler->sample_factors(points, reversed, 2.0) == factors);
}

TEST_CASE("[PCGPolygonMask3D] invalid polygons and late malformed points reject atomically") {
	Ref<PCGPolygonMask3D> sampler;
	sampler.instantiate();
	const PackedVector3Array rect = {
		Vector3(-2, 0, -2), Vector3(2, 0, -2),
		Vector3(2, 0, 2), Vector3(-2, 0, 2)
	};
	const PackedVector3Array point = { Vector3(0, 0, 0) };
	CHECK(sampler->sample_factors(point, {}).is_empty());
	CHECK(sampler->sample_factors(point, {
		Vector3(0, 0, 0), Vector3(1, 0, 0) }).is_empty());
	CHECK(sampler->sample_factors(point, rect, -1.0).is_empty());
	CHECK(sampler->sample_factors(point, rect, 10001.0).is_empty());
	CHECK(sampler->sample_factors(point, rect, Math::NaN).is_empty());
	CHECK(sampler->sample_factors(point, rect, Math::INF).is_empty());
	const PackedVector3Array crossed = {
		Vector3(0, 0, 0), Vector3(4, 0, 4),
		Vector3(0, 0, 4), Vector3(4, 0, 0)
	};
	CHECK(sampler->sample_factors(point, crossed, 1.0).is_empty());
	const PackedVector3Array repeated_end = {
		Vector3(-2, 0, -2), Vector3(2, 0, -2),
		Vector3(2, 0, 2), Vector3(-2, 0, 2), Vector3(-2, 0, -2)
	};
	CHECK(sampler->sample_factors(point, repeated_end, 1.0).is_empty());
	const PackedVector3Array zero_edge = {
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(4, 0, 0), Vector3(0, 0, 4)
	};
	CHECK(sampler->sample_factors(point, zero_edge).is_empty());
	const PackedVector3Array collapsed = {
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)
	};
	CHECK(sampler->sample_factors(point, collapsed).is_empty());
	const PackedVector3Array bad_vertex = {
		Vector3(-2, 0, -2), Vector3(2, Math::INF, -2),
		Vector3(2, 0, 2), Vector3(-2, 0, 2)
	};
	CHECK(sampler->sample_factors(point, bad_vertex).is_empty());
	const PackedVector3Array huge_vertex = {
		Vector3(-2, 0, -2), Vector3(10000001, 0, -2),
		Vector3(2, 0, 2), Vector3(-2, 0, 2)
	};
	CHECK(sampler->sample_factors(point, huge_vertex).is_empty());
	CHECK(sampler->sample_factors({
		Vector3(0, 0, 0), Vector3(0, Math::NaN, 0)
	}, rect).is_empty());
	CHECK(sampler->sample_factors({
		Vector3(0, 0, 0), Vector3(10000001, 0, 0)
	}, rect).is_empty());
	PackedVector3Array excessive_vertices;
	for (int i = 0; i < 257; ++i) {
		const double angle = 6.283185307179586 * i / 257.0;
		excessive_vertices.push_back(Vector3(Math::cos(angle) * 10.0,
				0, Math::sin(angle) * 10.0));
	}
	CHECK(sampler->sample_factors(point, excessive_vertices).is_empty());
	PackedVector3Array excessive_points;
	for (int i = 0; i < 16385; ++i) {
		excessive_points.push_back(Vector3(i, 0, 0));
	}
	CHECK(sampler->sample_factors(excessive_points, rect).is_empty());
	excessive_points.resize(16384);
	const PackedFloat32Array full = sampler->sample_factors(excessive_points, rect);
	REQUIRE(full.size() == 16384);
	CHECK(full[0] == 0.0f);
	CHECK(full[16383] == 1.0f);
	CHECK(sampler->sample_factors({}, rect).is_empty());
}

} // namespace TestPCGPolygonMask3D
