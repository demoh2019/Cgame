/**************************************************************************/
/*  test_pcg_polyline_sampler_3d.h                                          */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_polyline_sampler_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGPolylineSampler3D {

TEST_CASE("[PCGPolylineSampler3D] fit-to-path distributes exact endpoints and equal 3D distances") {
	Ref<PCGPolylineSampler3D> sampler;
	sampler.instantiate();
	const PackedVector3Array route = { Vector3(0, 0, 0), Vector3(10, 0, 0) };
	const PackedVector3Array fitted = sampler->sample_positions(route, 3.0);
	REQUIRE(fitted.size() == 5);
	for (int i = 0; i < 5; ++i) {
		CHECK(fitted[i].distance_to(Vector3(2.5 * i, 0, 0)) < 0.00001);
	}
	CHECK(fitted[0] == route[0]);
	CHECK(fitted[4] == route[1]);
	CHECK(sampler->sample_positions(route, 3.0) == fitted);
	const PackedVector3Array not_fitted = sampler->sample_positions(route, 3.0, 4096, false);
	REQUIRE(not_fitted.size() == 4);
	CHECK(not_fitted[0] == Vector3(0, 0, 0));
	CHECK(not_fitted[1] == Vector3(3, 0, 0));
	CHECK(not_fitted[2] == Vector3(6, 0, 0));
	CHECK(not_fitted[3] == Vector3(9, 0, 0));
	CHECK(sampler->sample_positions(route, 2.5, 4096, false).size() == 5);
}

TEST_CASE("[PCGPolylineSampler3D] corners and height are sampled by full 3D arc length") {
	Ref<PCGPolylineSampler3D> sampler;
	sampler.instantiate();
	const PackedVector3Array route = {
		Vector3(0, 0, 0), Vector3(0, 3, 4), Vector3(5, 3, 4)
	};
	const PackedVector3Array sampled = sampler->sample_positions(route, 2.5);
	REQUIRE(sampled.size() == 5);
	CHECK(sampled[0] == route[0]);
	CHECK(sampled[1].distance_to(Vector3(0, 1.5, 2)) < 0.00001);
	CHECK(sampled[2] == route[1]);
	CHECK(sampled[3].distance_to(Vector3(2.5, 3, 4)) < 0.00001);
	CHECK(sampled[4] == route[2]);
	for (int i = 1; i < sampled.size(); ++i) {
		CHECK(sampled[i].distance_to(sampled[i - 1]) <= 2.50001);
	}
	CHECK(route[0] == Vector3(0, 0, 0));
}

TEST_CASE("[PCGPolylineSampler3D] degenerate segments and singleton paths are safe") {
	Ref<PCGPolylineSampler3D> sampler;
	sampler.instantiate();
	const PackedVector3Array degenerate = {
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(6, 0, 0), Vector3(6, 0, 0)
	};
	const PackedVector3Array samples = sampler->sample_positions(degenerate, 2.0);
	REQUIRE(samples.size() == 4);
	CHECK(samples[0] == Vector3(0, 0, 0));
	CHECK(samples[1] == Vector3(2, 0, 0));
	CHECK(samples[2] == Vector3(4, 0, 0));
	CHECK(samples[3] == Vector3(6, 0, 0));
	const PackedVector3Array one = { Vector3(4, 7, -2) };
	CHECK(sampler->sample_positions(one, 2.0) == one);
	const PackedVector3Array repeated = { Vector3(4, 7, -2), Vector3(4, 7, -2) };
	CHECK(sampler->sample_positions(repeated, 2.0) == one);
	const PackedVector3Array short_path = {
		Vector3(0, 0, 0), Vector3(1, 0, 0)
	};
	CHECK(sampler->sample_positions(short_path, 3.0, 4096, false) ==
			PackedVector3Array({ Vector3(0, 0, 0) }));
	CHECK(sampler->sample_positions(short_path, 3.0) == short_path);
}

TEST_CASE("[PCGPolylineSampler3D] invalid input rejects entire batch without unsafe count casts") {
	Ref<PCGPolylineSampler3D> sampler;
	sampler.instantiate();
	const PackedVector3Array line = { Vector3(0, 0, 0), Vector3(10, 0, 0) };
	CHECK(sampler->sample_positions({}, 1.0).is_empty());
	CHECK(sampler->sample_positions(line, Math::NaN).is_empty());
	CHECK(sampler->sample_positions(line, Math::INF).is_empty());
	CHECK(sampler->sample_positions(line, 0.0).is_empty());
	CHECK(sampler->sample_positions(line, 0.01).is_empty());
	CHECK(sampler->sample_positions(line, 10001.0).is_empty());
	CHECK(sampler->sample_positions(line, 1.0, 0).is_empty());
	CHECK(sampler->sample_positions(line, 1.0, 4097).is_empty());
	CHECK(sampler->sample_positions(line, 1.0, 3).is_empty()); // No truncation.
	CHECK(sampler->sample_positions(
			{ Vector3(0, 0, 0), Vector3(Math::NaN, 0, 0) }, 1.0).is_empty());
	CHECK(sampler->sample_positions(
			{ Vector3(0, 0, 0), Vector3(0, Math::INF, 0) }, 1.0).is_empty());
	CHECK(sampler->sample_positions(
			{ Vector3(0, 0, 0), Vector3(0, 0, 10000001) }, 1.0).is_empty());
	// A 20-million-unit span at 0.05 spacing must fail before int conversion.
	CHECK(sampler->sample_positions(
			{ Vector3(-10000000, 0, 0), Vector3(10000000, 0, 0) }, 0.05).is_empty());
	PackedVector3Array waypoints;
	for (int i = 0; i < 257; ++i) {
		waypoints.push_back(Vector3(i, 0, 0));
	}
	CHECK(sampler->sample_positions(waypoints, 1.0).is_empty());
	waypoints.resize(256);
	CHECK(sampler->sample_positions(waypoints, 1.0).size() == 256);
	const PackedVector3Array exact = {
		Vector3(0, 0, 0), Vector3(4095, 0, 0)
	};
	CHECK(sampler->sample_positions(exact, 1.0).size() == 4096);
	CHECK(sampler->sample_positions(exact, 0.5).is_empty());
}

} // namespace TestPCGPolylineSampler3D
