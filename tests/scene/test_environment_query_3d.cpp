/**************************************************************************/
/*  test_environment_query_3d.cpp                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_environment_query_3d)

#include "modules/modules_enabled.gen.h"

#ifdef MODULE_ENVIRONMENT_QUERY_ENABLED

#include "modules/environment_query/environment_query_3d.h"

#include "core/io/resource_loader.h"
#include "core/io/resource_saver.h"
#include "core/math/math_funcs.h"
#include "tests/test_utils.h"

namespace TestEnvironmentQuery3D {

static Ref<EnvironmentQuery3D> make_query(const PackedVector3Array &p_points = PackedVector3Array()) {
	Ref<EnvironmentQuery3D> result;
	result.instantiate();
	result->set_candidates(p_points);
	return result;
}

static Dictionary first_result(const Ref<EnvironmentQuery3D> &p_query) {
	const Array result = p_query->query();
	return result[0];
}

TEST_CASE("[EnvironmentQuery3D] Empty input produces no results") {
	Ref<EnvironmentQuery3D> q = make_query();
	CHECK(q->query().is_empty());
	CHECK(q->query_positions().is_empty());
}

TEST_CASE("[EnvironmentQuery3D] Nearest-first ranking by default") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(9, 0, 0), Vector3(2, 0, 0), Vector3(6, 0, 0) });
	PackedVector3Array result = q->query_positions();
	REQUIRE(result.size() == 3);
	CHECK(result[0] == Vector3(2, 0, 0));
	CHECK(result[1] == Vector3(6, 0, 0));
	CHECK(result[2] == Vector3(9, 0, 0));
}

TEST_CASE("[EnvironmentQuery3D] Stable source-index order for equal scores") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0) });
	Array result = q->query();
	REQUIRE(result.size() == 3);
	for (int i = 0; i < 3; i++) {
		Dictionary item = result[i];
		CHECK(int(item["index"]) == i);
	}
}

TEST_CASE("[EnvironmentQuery3D] Duplicate candidates retain separate indices") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(1, 0, 0) });
	Array result = q->query();
	REQUIRE(result.size() == 2);
	const Dictionary first = result[0];
	const Dictionary second = result[1];
	CHECK(int(first["index"]) == 0);
	CHECK(int(second["index"]) == 1);
}

TEST_CASE("[EnvironmentQuery3D] Minimum distance filtering") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(5, 0, 0) });
	q->set_min_distance(3);
	CHECK(q->query_positions() == PackedVector3Array({ Vector3(5, 0, 0) }));
}

TEST_CASE("[EnvironmentQuery3D] Maximum distance filtering") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(5, 0, 0) });
	q->set_max_distance(3);
	CHECK(q->query_positions() == PackedVector3Array({ Vector3(1, 0, 0) }));
}

TEST_CASE("[EnvironmentQuery3D] Distance thresholds include exact boundaries") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(2, 0, 0), Vector3(4, 0, 0) });
	q->set_min_distance(2);
	q->set_max_distance(4);
	CHECK(q->query().size() == 2);
}

TEST_CASE("[EnvironmentQuery3D] Inverted distance range returns zero results") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(3, 0, 0) });
	q->set_min_distance(8);
	q->set_max_distance(1);
	CHECK(q->query().is_empty());
}

TEST_CASE("[EnvironmentQuery3D] Vertical terrain difference filters all ranking modes") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(4, 5, 0), Vector3(5, 7, 0), Vector3(6, -1, 0), Vector3(7, 8, 0)
	});
	q->set_origin(Vector3(0, 5, 0));
	q->set_horizontal_only(true);
	q->set_max_distance(10.0);
	CHECK(q->get_max_vertical_difference() == 0.0);
	CHECK(q->query_positions().size() == 4);
	q->set_max_vertical_difference(2.0);
	const PackedVector3Array expected = { Vector3(4, 5, 0), Vector3(5, 7, 0) };
	CHECK(q->query_positions() == expected); // Exact height boundary is inclusive.
	CHECK(q->query().size() == 2);
	CHECK(q->query_top_positions(2) == expected);
	CHECK(q->query_spread_positions(2, 0.0) == expected);
	ERR_PRINT_OFF
	q->set_max_vertical_difference(-1.0);
	q->set_max_vertical_difference(Math::NaN);
	q->set_max_vertical_difference(Math::INF);
	ERR_PRINT_ON
	CHECK(q->get_max_vertical_difference() == 2.0);
	q->set_horizontal_only(false);
	CHECK(q->query_positions().size() == 2);
	q->set_max_vertical_difference(0.0);
	CHECK(q->query_positions().size() == 4);
}

TEST_CASE("[EnvironmentQuery3D] Desired-distance ranking") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(10, 0, 0) });
	q->set_desired_distance(5);
	CHECK(q->query_positions()[0] == Vector3(5, 0, 0));
}

TEST_CASE("[EnvironmentQuery3D] Changing origin recalculates candidate ranking") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(0, 0, 0), Vector3(10, 0, 0) });
	CHECK(q->query_positions()[0] == Vector3(0, 0, 0));
	q->set_origin(Vector3(10, 0, 0));
	CHECK(q->query_positions()[0] == Vector3(10, 0, 0));
}

TEST_CASE("[EnvironmentQuery3D] Threat safety ranking") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(8, 0, 0) });
	q->set_use_threat(true);
	q->set_threat_position(Vector3());
	q->set_distance_weight(0);
	q->set_safety_weight(1);
	CHECK(q->query_positions()[0] == Vector3(8, 0, 0));
}

TEST_CASE("[EnvironmentQuery3D] Minimum threat clearance") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(6, 0, 0) });
	q->set_use_threat(true);
	q->set_min_threat_distance(3);
	CHECK(q->query_positions() == PackedVector3Array({ Vector3(6, 0, 0) }));
}

TEST_CASE("[EnvironmentQuery3D] Threat clearance boundary is inclusive") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(3, 0, 0) });
	q->set_use_threat(true);
	q->set_min_threat_distance(3);
	CHECK(q->query().size() == 1);
}

TEST_CASE("[EnvironmentQuery3D] Disabled threat ignores safety filtering") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0) });
	q->set_min_threat_distance(100);
	q->set_safety_weight(10);
	CHECK(q->query().size() == 1);
	CHECK(double(first_result(q)["threat_distance"]) == -1.0);
}

TEST_CASE("[EnvironmentQuery3D] Full 3D mode measures vertical distance") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(0, 10, 0) });
	q->set_max_distance(5);
	CHECK(q->query().is_empty());
}

TEST_CASE("[EnvironmentQuery3D] Horizontal-only mode ignores candidate height") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(0, 10, 0) });
	q->set_horizontal_only(true);
	q->set_max_distance(5);
	CHECK(q->query().size() == 1);
	CHECK(double(first_result(q)["distance"]) == 0.0);
}

TEST_CASE("[EnvironmentQuery3D] Horizontal threat distance ignores height") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(0, 10, 0) });
	q->set_use_threat(true);
	q->set_horizontal_only(true);
	q->set_min_threat_distance(1);
	CHECK(q->query().is_empty());
}

TEST_CASE("[EnvironmentQuery3D] Maximum result count truncates ranked results") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(3, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0) });
	q->set_max_results(2);
	CHECK(q->query_positions() == PackedVector3Array({ Vector3(1, 0, 0), Vector3(2, 0, 0) }));
}

TEST_CASE("[EnvironmentQuery3D] Bounded top-K matches full sorted positions") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(9, 0, 0), Vector3(1, 0, 0), Vector3(6, 0, 0),
		Vector3(2, 0, 0), Vector3(7, 0, 0)
	});
	const PackedVector3Array full = q->query_positions();
	for (int k = 1; k <= full.size(); k++) {
		PackedVector3Array top = q->query_top_positions(k);
		REQUIRE(top.size() == k);
		for (int i = 0; i < k; i++) {
			CHECK(top[i] == full[i]);
		}
	}
}

TEST_CASE("[EnvironmentQuery3D] Bounded top-K preserves deterministic ties") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)
	});
	CHECK(q->query_top_positions(2) ==
			PackedVector3Array({ Vector3(1, 0, 0), Vector3(0, 0, 1) }));
}

TEST_CASE("[EnvironmentQuery3D] Top-K honors max results and safety") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(4, 0, 0), Vector3(8, 0, 0)
	});
	q->set_max_results(1);
	CHECK(q->query_top_positions(3) ==
			PackedVector3Array({ Vector3(1, 0, 0) }));
	q->set_max_results(0);
	q->set_use_threat(true);
	q->set_threat_position(Vector3());
	q->set_min_threat_distance(3.0);
	CHECK(q->query_top_positions(3) ==
			PackedVector3Array({ Vector3(4, 0, 0), Vector3(8, 0, 0) }));
}

TEST_CASE("[EnvironmentQuery3D] Bounded top-K rejects unsafe requests and malformed points") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(NaN, 0, 0), Vector3(5, 0, 0)
	});
	ERR_PRINT_OFF
	CHECK(q->query_top_positions(0).is_empty());
	CHECK(q->query_top_positions(65).is_empty());
	ERR_PRINT_ON
	CHECK(q->query_top_positions(3) ==
			PackedVector3Array({ Vector3(5, 0, 0) }));
	q->set_min_distance(8.0);
	CHECK(q->query_top_positions(3).is_empty());
}

TEST_CASE("[EnvironmentQuery3D] Spread selection scans past close high-ranked points") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(1.5, 0, 0), Vector3(6, 0, 0), Vector3(10, 0, 0)
	});
	CHECK(q->query_spread_positions(2, 3.0) ==
			PackedVector3Array({ Vector3(1, 0, 0), Vector3(6, 0, 0) }));
	q->set_max_results(1);
	CHECK(q->query_spread_positions(2, 3.0) ==
			PackedVector3Array({ Vector3(1, 0, 0) }));
}

TEST_CASE("[EnvironmentQuery3D] Spread zero separation preserves stable top-K order") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)
	});
	CHECK(q->query_spread_positions(3, 0.0) == q->query_top_positions(3));
	CHECK(q->query_spread_positions(4, 2.0) ==
			PackedVector3Array({ Vector3(1, 0, 0), Vector3(-1, 0, 0) }));
}

TEST_CASE("[EnvironmentQuery3D] Spread spacing respects horizontal mode and inclusive boundary") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(1, 4, 0), Vector3(5, 0, 0)
	});
	CHECK(q->query_spread_positions(3, 3.0).size() == 3);
	q->set_horizontal_only(true);
	CHECK(q->query_spread_positions(3, 3.0) ==
			PackedVector3Array({ Vector3(1, 0, 0), Vector3(5, 0, 0) }));
	q->set_candidates({ Vector3(0, 0, 0), Vector3(3, 0, 0) });
	CHECK(q->query_spread_positions(2, 3.0).size() == 2); // Boundary is inclusive.
}

TEST_CASE("[EnvironmentQuery3D] Spread honors multiple threats and safety filters") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(0, 0, -10), Vector3(0, 0, 10), Vector3(0, 0, -12)
	});
	q->set_horizontal_only(true);
	q->set_use_threat(true);
	q->set_max_distance(64.0);
	q->set_distance_weight(0.0);
	q->set_safety_weight(1.0);
	q->set_threat_positions({ Vector3(0, 0, 0), Vector3(0, 0, 9) });
	CHECK(q->query_spread_positions(2, 5.0) ==
			PackedVector3Array({ Vector3(0, 0, -12), Vector3(1, 0, 0) }));
	q->set_min_threat_distance(5.0);
	CHECK(q->query_spread_positions(2, 5.0) ==
			PackedVector3Array({ Vector3(0, 0, -12) }));
}

TEST_CASE("[EnvironmentQuery3D] Spread rejects invalid requests without corrupting query state") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(NaN, 0, 0), Vector3(2, 0, 0) });
	ERR_PRINT_OFF
	CHECK(q->query_spread_positions(0, 2.0).is_empty());
	CHECK(q->query_spread_positions(65, 2.0).is_empty());
	CHECK(q->query_spread_positions(2, -1.0).is_empty());
	CHECK(q->query_spread_positions(2, INF).is_empty());
	ERR_PRINT_ON
	CHECK(q->query_spread_positions(2, 2.0) == PackedVector3Array({ Vector3(2, 0, 0) }));
}


TEST_CASE("[EnvironmentQuery3D] Occupancy exclusions affect full, top-K and spread queries") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(4, 0, 0), Vector3(8, 0, 0), Vector3(12, 0, 0)
	});
	q->set_exclusion_positions({ Vector3(0, 0, 0) });
	q->set_min_exclusion_distance(4.0);
	const PackedVector3Array permitted = { Vector3(4, 0, 0), Vector3(8, 0, 0), Vector3(12, 0, 0) };
	CHECK(q->query_positions() == permitted);
	CHECK(q->query_top_positions(2) == PackedVector3Array({ Vector3(4, 0, 0), Vector3(8, 0, 0) }));
	CHECK(q->query_spread_positions(2, 5.0) == PackedVector3Array({ Vector3(4, 0, 0), Vector3(12, 0, 0) }));
	CHECK(q->query().size() == 3);
	q->set_min_exclusion_distance(0.0);
	CHECK(q->query_positions().size() == 4);
}

TEST_CASE("[EnvironmentQuery3D] Occupancy exclusions honor XZ mode and preserve valid state") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(6, 0, 0) });
	q->set_exclusion_positions({ Vector3(1, 30, 0) });
	q->set_min_exclusion_distance(3.0);
	CHECK(q->query_positions().size() == 2);
	q->set_horizontal_only(true);
	CHECK(q->query_positions() == PackedVector3Array({ Vector3(6, 0, 0) }));
	const PackedVector3Array original = q->get_exclusion_positions();
	PackedVector3Array too_many;
	too_many.resize(129);
	ERR_PRINT_OFF
	q->set_exclusion_positions(too_many);
	q->set_exclusion_positions({ Vector3(NaN, 0, 0) });
	q->set_min_exclusion_distance(-1.0);
	q->set_min_exclusion_distance(INF);
	ERR_PRINT_ON
	CHECK(q->get_exclusion_positions() == original);
	CHECK(q->get_min_exclusion_distance() == 3.0);
	q->set_exclusion_positions(PackedVector3Array());
	CHECK(q->query_positions().size() == 2);
}

TEST_CASE("[EnvironmentQuery3D] Directional dot filter is shared by full, top-K and spread queries") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(-4, 0, 0), Vector3(0, 0, -4), Vector3(0, 0, 4), Vector3(4, 0, 0)
	});
	q->set_horizontal_only(true);
	q->set_direction_origin(Vector3());
	q->set_direction_axis(Vector3(1, 0, 0));
	q->set_min_direction_dot(0.0);
	q->set_use_direction(true);
	const PackedVector3Array expected = {
		Vector3(0, 0, -4), Vector3(0, 0, 4), Vector3(4, 0, 0)
	};
	CHECK(q->query_positions() == expected);
	CHECK(q->query().size() == 3);
	CHECK(q->query_top_positions(2) == PackedVector3Array({ Vector3(0, 0, -4), Vector3(0, 0, 4) }));
	CHECK(q->query_spread_positions(2, 5.0) == PackedVector3Array({ Vector3(0, 0, -4), Vector3(0, 0, 4) }));
	q->set_min_direction_dot(1.0);
	CHECK(q->query_positions() == PackedVector3Array({ Vector3(4, 0, 0) }));
	q->set_use_direction(false);
	CHECK(q->query_positions().size() == 4);
}

TEST_CASE("[EnvironmentQuery3D] Inclusive directional band selects lateral positions in every query mode") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(-4, 0, 0), Vector3(0, 0, -4), Vector3(0, 0, 4), Vector3(4, 0, 0)
	});
	q->set_horizontal_only(true);
	q->set_use_direction(true);
	q->set_direction_axis(Vector3(1, 0, 0));
	CHECK(q->get_max_direction_dot() == 1.0); // Backwards-compatible cone default.
	CHECK(q->query_positions().size() == 4);
	q->set_min_direction_dot(-0.25);
	q->set_max_direction_dot(0.75);
	const PackedVector3Array sides = { Vector3(0, 0, -4), Vector3(0, 0, 4) };
	CHECK(q->query_positions() == sides);
	CHECK(q->query().size() == 2);
	CHECK(q->query_top_positions(2) == sides);
	CHECK(q->query_spread_positions(2, 5.0) == sides);
	// Inclusive upper and lower boundaries, including the exact cosine 0.
	q->set_min_direction_dot(0.0);
	q->set_max_direction_dot(0.0);
	CHECK(q->query_positions() == sides);
	q->set_use_direction(false);
	CHECK(q->query_positions().size() == 4);
}

TEST_CASE("[EnvironmentQuery3D] Directional band rejects inverted and nonfinite bounds") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(4, 0, 0), Vector3(0, 0, 4) });
	q->set_direction_axis(Vector3(1, 0, 0));
	q->set_use_direction(true);
	q->set_min_direction_dot(-0.25);
	q->set_max_direction_dot(0.75);
	ERR_PRINT_OFF
	q->set_min_direction_dot(0.8);
	q->set_max_direction_dot(-0.5);
	q->set_max_direction_dot(Math::NaN);
	q->set_max_direction_dot(Math::INF);
	q->set_max_direction_dot(-1.01);
	q->set_max_direction_dot(1.01);
	ERR_PRINT_ON
	CHECK(q->get_min_direction_dot() == -0.25);
	CHECK(q->get_max_direction_dot() == 0.75);
	CHECK(q->query_positions() == PackedVector3Array({ Vector3(0, 0, 4) }));
}

TEST_CASE("[EnvironmentQuery3D] Directional filter uses its own context and validates parameters") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(2, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 3)
	});
	q->set_direction_origin(Vector3(3, 0, 0));
	q->set_direction_axis(Vector3(1, 0, 0));
	q->set_min_direction_dot(0.0);
	q->set_use_direction(true);
	CHECK(q->query_positions() == PackedVector3Array({ Vector3(5, 0, 0), Vector3(5, 0, 3) }));
	q->set_horizontal_only(true);
	q->set_direction_axis(Vector3(0, 1, 0)); // No XZ-facing direction: fail closed.
	CHECK(q->query_positions().is_empty());
	q->set_direction_axis(Vector3(1, 0, 0));
	const Vector3 original_axis = q->get_direction_axis();
	ERR_PRINT_OFF
	q->set_direction_axis(Vector3());
	q->set_direction_axis(Vector3(NaN, 0, 0));
	q->set_direction_origin(Vector3(INF, 0, 0));
	q->set_min_direction_dot(INF);
	q->set_min_direction_dot(-1.01);
	q->set_min_direction_dot(1.01);
	ERR_PRINT_ON
	CHECK(q->get_direction_axis() == original_axis);
	CHECK(q->get_direction_origin() == Vector3(3, 0, 0));
	CHECK(q->get_min_direction_dot() == 0.0);
	CHECK(q->query_positions().size() == 2);
	q->set_candidates({ Vector3(3, 0, 0) });
	CHECK(q->query_positions().is_empty()); // Undefined facing at the directional origin.
}

TEST_CASE("[EnvironmentQuery3D] Zero result cap means unlimited") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(2, 0, 0) });
	CHECK(q->get_max_results() == 0);
	CHECK(q->query().size() == 2);
}

TEST_CASE("[EnvironmentQuery3D] Result metadata has complete fields") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(5, 0, 0) });
	Dictionary entry = first_result(q);
	CHECK(entry.has("position"));
	CHECK(entry.has("index"));
	CHECK(entry.has("score"));
	CHECK(entry.has("distance"));
	CHECK(entry.has("threat_distance"));
	CHECK(double(entry["distance"]) == 5.0);
}

TEST_CASE("[EnvironmentQuery3D] Weighted scoring combines distance and safety") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3() });
	q->set_max_distance(10);
	q->set_distance_weight(2);
	q->set_safety_weight(3);
	q->set_use_threat(true);
	q->set_threat_position(Vector3(10, 0, 0));
	CHECK(Math::is_equal_approx(double(first_result(q)["score"]), 5.0));
}

TEST_CASE("[EnvironmentQuery3D] Nonfinite candidate positions are skipped") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(NaN, 0, 0), Vector3(1, 0, 0) });
	CHECK(q->query().size() == 1);
	CHECK(int(first_result(q)["index"]) == 1);
}

TEST_CASE("[EnvironmentQuery3D] Invalid origin and threat positions are rejected") {
	Ref<EnvironmentQuery3D> q = make_query();
	q->set_origin(Vector3(2, 0, 0));
	q->set_threat_position(Vector3(3, 0, 0));
	ERR_PRINT_OFF
	q->set_origin(Vector3(INF, 0, 0));
	q->set_threat_position(Vector3(NaN, 0, 0));
	ERR_PRINT_ON
	CHECK(q->get_origin() == Vector3(2, 0, 0));
	CHECK(q->get_threat_position() == Vector3(3, 0, 0));
}

TEST_CASE("[EnvironmentQuery3D] Reject invalid limits and weights") {
	Ref<EnvironmentQuery3D> q = make_query();
	ERR_PRINT_OFF
	q->set_min_distance(-1);
	q->set_max_distance(NaN);
	q->set_desired_distance(-3);
	q->set_distance_weight(-2);
	q->set_safety_weight(INF);
	q->set_min_threat_distance(-1);
	q->set_max_results(-1);
	ERR_PRINT_ON
	CHECK(q->get_min_distance() == 0);
	CHECK(q->get_max_distance() == 100);
	CHECK(q->get_desired_distance() == 0);
	CHECK(q->get_distance_weight() == 1);
	CHECK(q->get_safety_weight() == 0);
	CHECK(q->get_min_threat_distance() == 0);
	CHECK(q->get_max_results() == 0);
}

TEST_CASE("[EnvironmentQuery3D] Multi-threat contexts score against the nearest actor") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 10), Vector3(0, 0, -10)
	});
	q->set_use_threat(true);
	q->set_horizontal_only(true);
	q->set_max_distance(64.0);
	q->set_distance_weight(0.0);
	q->set_safety_weight(1.0);
	q->set_threat_positions({ Vector3(0, 0, 0), Vector3(0, 0, 9) });
	CHECK(q->get_threat_positions().size() == 2);
	const PackedVector3Array full = q->query_positions();
	REQUIRE(full.size() == 4);
	CHECK(full[0] == Vector3(0, 0, -10));
	CHECK(full[1] == Vector3(1, 0, 0));
	CHECK(full[2] == Vector3(-1, 0, 0));
	CHECK(full[3] == Vector3(0, 0, 10));
	const Dictionary first = first_result(q);
	CHECK(double(first["threat_distance"]) == doctest::Approx(10.0));
	CHECK(double(first["score"]) == doctest::Approx(10.0 / 64.0));
	const PackedVector3Array top = q->query_top_positions(2);
	REQUIRE(top.size() == 2);
	CHECK(top[0] == full[0]);
	CHECK(top[1] == full[1]);

	// The order of threat actors is irrelevant, not the order of candidate
	// positions. The nearest one is always used for safety.
	q->set_threat_positions({ Vector3(0, 0, 9), Vector3(0, 0, 0) });
	CHECK(q->query_positions() == full);
}

TEST_CASE("[EnvironmentQuery3D] Multi-threat clearance applies to every actor") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(0, 0, 3), Vector3(0, 0, 7), Vector3(0, 0, -7)
	});
	q->set_use_threat(true);
	q->set_horizontal_only(true);
	q->set_max_distance(20);
	q->set_min_threat_distance(3);
	q->set_threat_positions({ Vector3(), Vector3(0, 100, 9) });
	const PackedVector3Array result = q->query_positions();
	CHECK(result == PackedVector3Array({ Vector3(0, 0, 3), Vector3(0, 0, -7) }));
	q->set_min_threat_distance(2);
	CHECK(q->query_positions().size() == 3);
	q->set_use_threat(false);
	q->set_min_threat_distance(100);
	CHECK(q->query_positions().size() == 3);
}

TEST_CASE("[EnvironmentQuery3D] Multi-threat limits, invalid actors, and legacy fallback") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(8, 0, 0)
	});
	q->set_use_threat(true);
	q->set_threat_position(Vector3(100, 0, 0));
	q->set_threat_positions({ Vector3(0, 0, 0), Vector3(6, 0, 0) });
	const PackedVector3Array baseline = q->query_positions();
	CHECK(baseline.size() == 3);
	PackedVector3Array too_many;
	too_many.resize(33);
	ERR_PRINT_OFF
	q->set_threat_positions(too_many);
	q->set_threat_positions({ Vector3(0, NaN, 0) });
	ERR_PRINT_ON
	CHECK(q->get_threat_positions().size() == 2);
	CHECK(q->query_positions() == baseline);
	q->set_threat_positions(PackedVector3Array());
	CHECK(q->get_threat_positions().is_empty());
	const Array legacy = q->query();
	REQUIRE(legacy.size() == 3);
	const Dictionary nearest = legacy[0];
	CHECK(double(nearest["threat_distance"]) == doctest::Approx(96.0));
}

TEST_CASE("[EnvironmentQuery3D] Random-best run modes honor score percentage cutoffs") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(10, 0, 0), Vector3(30, 0, 0), Vector3(40, 0, 0) });
	q->set_max_distance(100.0);
	const PackedVector3Array best5 = q->query_random_best_positions(5, 123);
	REQUIRE(best5.size() == 1);
	CHECK(best5[0] == Vector3(10, 0, 0)); // 0.9 best; cutoff 0.855.
	const PackedVector3Array best25 = q->query_random_best_positions(25, 123);
	REQUIRE(best25.size() == 1);
	CHECK(best25[0] == Vector3(10, 0, 0) || best25[0] == Vector3(30, 0, 0));
	CHECK(q->query_random_best_positions(25, 123) == best25);
	q->set_max_results(1);
	CHECK(q->query_random_best_positions(25, 123) == best25); // Cap is output-only.
	CHECK(q->query_random_best_positions(0, -3) == best5);
	const PackedVector3Array any = q->query_random_best_positions(100, -3);
	REQUIRE(any.size() == 1);
	CHECK(any[0] == Vector3(10, 0, 0) || any[0] == Vector3(30, 0, 0) || any[0] == Vector3(40, 0, 0));
}

TEST_CASE("[EnvironmentQuery3D] Random-best varies seed across tied scores without gameplay RNG") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)
	});
	q->set_max_distance(10);
	const PackedVector3Array baseline = q->query_positions();
	REQUIRE(baseline.size() == 4);
	bool saw_another = false;
	const PackedVector3Array first = q->query_random_best_positions(5, 0);
	REQUIRE(first.size() == 1);
	for (int seed = 1; seed < 64; seed++) {
		const PackedVector3Array selected = q->query_random_best_positions(5, seed);
		REQUIRE(selected.size() == 1);
		if (selected[0] != first[0]) {
			saw_another = true;
		}
		CHECK(selected == q->query_random_best_positions(5, seed));
	}
	CHECK(saw_another);
	CHECK(q->query_positions() == baseline); // No query configuration mutation.
}

TEST_CASE("[EnvironmentQuery3D] Random-best keeps all safety filters and fails closed") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 8), Vector3(NaN, 0, 0)
	});
	q->set_max_distance(10.0);
	q->set_horizontal_only(true);
	q->set_use_direction(true);
	q->set_direction_origin(Vector3());
	q->set_direction_axis(Vector3(1, 0, 0));
	q->set_min_direction_dot(0.5);
	CHECK(q->query_random_best_positions(25, 1) == PackedVector3Array({ Vector3(1, 0, 0) }));
	q->set_min_exclusion_distance(2.0);
	q->set_exclusion_positions({ Vector3(1, 0, 0) });
	CHECK(q->query_random_best_positions(25, 1).is_empty());
	q->set_exclusion_positions(PackedVector3Array());
	q->set_use_direction(false);
	q->set_use_threat(true);
	q->set_threat_positions({ Vector3(0, 0, 0), Vector3(0, 0, 7) });
	q->set_min_threat_distance(2.0);
	CHECK(q->query_random_best_positions(25, 1).is_empty());
	q->set_use_threat(false);
	CHECK(!q->query_random_best_positions(25, 1).is_empty());
	ERR_PRINT_OFF
	CHECK(q->query_random_best_positions(-1, 4).is_empty());
	CHECK(q->query_random_best_positions(101, 4).is_empty());
	ERR_PRINT_ON
	q->set_min_distance(11.0);
	CHECK(q->query_random_best_positions(25, 4).is_empty());
}

TEST_CASE("[EnvironmentQuery3D] Four ring samples cover cardinal directions") {
	PackedVector3Array p = EnvironmentQuery3D::sample_ring(Vector3(), 2, 4);
	REQUIRE(p.size() == 4);
	CHECK(p[0].is_equal_approx(Vector3(2, 0, 0)));
	CHECK(p[1].is_equal_approx(Vector3(0, 0, 2)));
	CHECK(p[2].is_equal_approx(Vector3(-2, 0, 0)));
	CHECK(p[3].is_equal_approx(Vector3(0, 0, -2)));
}

TEST_CASE("[EnvironmentQuery3D] Ring generation is deterministic") {
	PackedVector3Array a = EnvironmentQuery3D::sample_ring(Vector3(1, 2, 3), 4, 17, 0.4);
	PackedVector3Array b = EnvironmentQuery3D::sample_ring(Vector3(1, 2, 3), 4, 17, 0.4);
	CHECK(a == b);
}

TEST_CASE("[EnvironmentQuery3D] Ring phase rotates the first sample") {
	PackedVector3Array p = EnvironmentQuery3D::sample_ring(Vector3(), 1, 4, Math::PI / 2.0);
	REQUIRE(p.size() == 4);
	CHECK(p[0].is_equal_approx(Vector3(0, 0, 1)));
}

TEST_CASE("[EnvironmentQuery3D] Zero-radius rings generate collocated points") {
	PackedVector3Array p = EnvironmentQuery3D::sample_ring(Vector3(10, 3, 5), 0, 3);
	REQUIRE(p.size() == 3);
	CHECK(p[0] == Vector3(10, 3, 5));
	CHECK(p[2] == Vector3(10, 3, 5));
}

TEST_CASE("[EnvironmentQuery3D] Invalid ring parameters are bounded") {
	ERR_PRINT_OFF
	CHECK(EnvironmentQuery3D::sample_ring(Vector3(), 1, 0).is_empty());
	CHECK(EnvironmentQuery3D::sample_ring(Vector3(), -1, 5).is_empty());
	CHECK(EnvironmentQuery3D::sample_ring(Vector3(), 1, 4097).is_empty());
	ERR_PRINT_ON
}

TEST_CASE("[EnvironmentQuery3D] Donut samples concentric radii and preserves stable angle order") {
	const Vector3 center(10, 5, 20);
	const PackedVector3Array points = EnvironmentQuery3D::sample_donut(center, 2.0, 4.0, 3, 4);
	REQUIRE(points.size() == 12);
	CHECK(points[0].is_equal_approx(Vector3(12, 5, 20)));
	CHECK(points[1].is_equal_approx(Vector3(10, 5, 22)));
	CHECK(points[4].is_equal_approx(Vector3(13, 5, 20)));
	CHECK(points[8].is_equal_approx(Vector3(14, 5, 20)));
	CHECK(points[11].is_equal_approx(Vector3(10, 5, 16)));
	CHECK(EnvironmentQuery3D::sample_donut(center, 2.0, 4.0, 3, 4) == points);
	CHECK(EnvironmentQuery3D::sample_donut(center, 1.0, 4.0, 1, 4) ==
			EnvironmentQuery3D::sample_ring(center, 4.0, 4));
}

TEST_CASE("[EnvironmentQuery3D] Donut spiral stagger and phase are deterministic") {
	const PackedVector3Array spokes = EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 2.0, 2, 4);
	const PackedVector3Array spiral = EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 2.0, 2, 4, 0.0, true);
	REQUIRE(spokes.size() == 8);
	REQUIRE(spiral.size() == 8);
	CHECK(spokes[0] == spiral[0]); // First ring has no extra phase.
	CHECK(!spiral[4].is_equal_approx(spokes[4]));
	CHECK(spiral[4].is_equal_approx(Vector3(Math::sqrt(2.0), 0, Math::sqrt(2.0))));
	CHECK(spiral == EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 2.0, 2, 4, 0.0, true));
	const PackedVector3Array rotated = EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 1.0, 1, 4, Math::PI / 2.0);
	REQUIRE(rotated.size() == 4);
	CHECK(rotated[0].is_equal_approx(Vector3(0, 0, 1)));
}

TEST_CASE("[EnvironmentQuery3D] Donut rejects invalid geometry and respects hard allocation cap") {
	ERR_PRINT_OFF
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), -1.0, 4.0, 3, 4).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 5.0, 4.0, 3, 4).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(NaN, 0, 0), 1.0, 4.0, 3, 4).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 0.0, Math::INF, 3, 4).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 4.0, 3, 4, NaN).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 4.0, 0, 4).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 4.0, 257, 4).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 4.0, 3, 0).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 4.0, 3, 4097).is_empty());
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 4.0, 17, 4096).is_empty());
	ERR_PRINT_ON
	CHECK(EnvironmentQuery3D::sample_donut(Vector3(), 1.0, 4.0, 16, 4096).size() == 65536);
}

TEST_CASE("[EnvironmentQuery3D] Cone produces deterministic oriented radial sectors") {
	const Vector3 center(10, 3, 20);
	const PackedVector3Array points = EnvironmentQuery3D::sample_cone(center, Vector3(1, 2, 0), 2.0, 4.0, 2, 3, 90.0);
	REQUIRE(points.size() == 6);
	CHECK(points[0].is_equal_approx(center + Vector3(Math::sqrt(2.0), 0, -Math::sqrt(2.0))));
	CHECK(points[1].is_equal_approx(Vector3(12, 3, 20)));
	CHECK(points[2].is_equal_approx(center + Vector3(Math::sqrt(2.0), 0, Math::sqrt(2.0))));
	CHECK(points[4].is_equal_approx(Vector3(14, 3, 20)));
	CHECK(EnvironmentQuery3D::sample_cone(center, Vector3(1, 2, 0), 2.0, 4.0, 2, 3, 90.0) == points);
}

TEST_CASE("[EnvironmentQuery3D] Cone supports centered single ray, one ring and optional center") {
	const Vector3 center(10, 7, 20);
	const PackedVector3Array points = EnvironmentQuery3D::sample_cone(center, Vector3(0, 0, 5), 2.0, 4.0, 1, 1, 120.0, true);
	REQUIRE(points.size() == 2);
	CHECK(points[0] == center);
	CHECK(points[1].is_equal_approx(Vector3(10, 7, 24)));
	const PackedVector3Array zero_angle = EnvironmentQuery3D::sample_cone(center, Vector3(0, 0, 1), 2.0, 4.0, 2, 3, 0.0);
	REQUIRE(zero_angle.size() == 6);
	CHECK(zero_angle[0].is_equal_approx(Vector3(10, 7, 22)));
	CHECK(zero_angle[5].is_equal_approx(Vector3(10, 7, 24)));
	CHECK(EnvironmentQuery3D::sample_cone(center, Vector3(0, 0, 1), 0.0, 0.0, 1, 1, 0.0, true).size() == 2);
}

TEST_CASE("[EnvironmentQuery3D] Cone invalid geometry fails closed before allocation") {
	ERR_PRINT_OFF
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(), 1.0, 4.0, 2, 3).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(0, 1, 0), 1.0, 4.0, 2, 3).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(NaN, 0, 0), Vector3(1, 0, 0), 1.0, 4.0, 2, 3).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(INF, 0, 0), 1.0, 4.0, 2, 3).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), -1.0, 4.0, 2, 3).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 5.0, 4.0, 2, 3).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 1.0, 4.0, 2, 3, 361.0).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 1.0, 4.0, 2, 3, -0.1).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 1.0, 4.0, 2, 3, NaN).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 1.0, 4.0, 0, 3).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 1.0, 4.0, 2, 4097).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 1.0, 4.0, 17, 4096).is_empty());
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 1.0, 4.0, 16, 4096, 90.0, true).is_empty());
	ERR_PRINT_ON
	CHECK(EnvironmentQuery3D::sample_cone(Vector3(), Vector3(1, 0, 0), 1.0, 4.0, 16, 4096).size() == 65536);
}

TEST_CASE("[EnvironmentQuery3D] Grid produces deterministic XZ lattice") {
	PackedVector3Array p = EnvironmentQuery3D::sample_grid(Vector3(5, 7, 9), Vector2(1, 1), 1);
	REQUIRE(p.size() == 9);
	CHECK(p[0] == Vector3(4, 7, 8));
	CHECK(p[4] == Vector3(5, 7, 9));
	CHECK(p[8] == Vector3(6, 7, 10));
}

TEST_CASE("[EnvironmentQuery3D] Degenerate grid has one point") {
	PackedVector3Array p = EnvironmentQuery3D::sample_grid(Vector3(5, 7, 9), Vector2(), 2);
	REQUIRE(p.size() == 1);
	CHECK(p[0] == Vector3(5, 7, 9));
}

TEST_CASE("[EnvironmentQuery3D] Grid allocation limit prevents oversized generation") {
	ERR_PRINT_OFF
	CHECK(EnvironmentQuery3D::sample_grid(Vector3(), Vector2(10, 10), 0.1, 20).is_empty());
	ERR_PRINT_ON
}

TEST_CASE("[EnvironmentQuery3D] Reject invalid grid parameters") {
	ERR_PRINT_OFF
	CHECK(EnvironmentQuery3D::sample_grid(Vector3(), Vector2(-1, 1), 1).is_empty());
	CHECK(EnvironmentQuery3D::sample_grid(Vector3(), Vector2(1, 1), 0).is_empty());
	CHECK(EnvironmentQuery3D::sample_grid(Vector3(), Vector2(1, 1), 1, 0).is_empty());
	ERR_PRINT_ON
}

TEST_CASE("[EnvironmentQuery3D] Oriented grid preserves axis-aligned legacy order") {
	const Vector3 center(5, 7, 9);
	const PackedVector3Array baseline = EnvironmentQuery3D::sample_grid(center, Vector2(1, 1), 1);
	const PackedVector3Array oriented = EnvironmentQuery3D::sample_oriented_grid(center, Vector3(0, 0, 9), Vector2(1, 1), 1);
	REQUIRE(oriented.size() == 9);
	CHECK(oriented == baseline);
	CHECK(oriented[0] == Vector3(4, 7, 8));
	CHECK(oriented[4] == center);
	CHECK(oriented[8] == Vector3(6, 7, 10));
}

TEST_CASE("[EnvironmentQuery3D] Oriented grid rotates 90 degrees and stays deterministic") {
	const Vector3 center(5, 7, 9);
	const PackedVector3Array points = EnvironmentQuery3D::sample_oriented_grid(center, Vector3(4, 1, 0), Vector2(1, 1), 1);
	REQUIRE(points.size() == 9);
	CHECK(points[0].is_equal_approx(Vector3(4, 7, 10)));
	CHECK(points[4] == center);
	CHECK(points[8].is_equal_approx(Vector3(6, 7, 8)));
	CHECK(EnvironmentQuery3D::sample_oriented_grid(center, Vector3(4, 1, 0), Vector2(1, 1), 1) == points);
	const PackedVector3Array collapsed = EnvironmentQuery3D::sample_oriented_grid(center, Vector3(0, 0, 1), Vector2(), 2);
	REQUIRE(collapsed.size() == 1);
	CHECK(collapsed[0] == center);
}

TEST_CASE("[EnvironmentQuery3D] Oriented grid validates input and enforces memory budget") {
	ERR_PRINT_OFF
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(), Vector2(1, 1), 1).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(0, 1, 0), Vector2(1, 1), 1).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(INF, 0, 0), Vector3(0, 0, 1), Vector2(1, 1), 1).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(NaN, 0, 1), Vector2(1, 1), 1).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(0, 0, 1), Vector2(-1, 1), 1).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(0, 0, 1), Vector2(1, INF), 1).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(0, 0, 1), Vector2(1, 1), 0).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(0, 0, 1), Vector2(1, 1), 1, 0).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(0, 0, 1), Vector2(1, 1), 1, 65537).is_empty());
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(0, 0, 1), Vector2(20, 20), 0.1, 100).is_empty());
	ERR_PRINT_ON
	CHECK(EnvironmentQuery3D::sample_oriented_grid(Vector3(), Vector3(0, 0, 1), Vector2(127.5, 127.5), 1, 65536).size() == 65536);
}

TEST_CASE("[EnvironmentQuery3D] Fibonacci annulus samples bounded area-uniform rings deterministically") {
	const Vector3 center(10, 3, 20);
	const PackedVector3Array samples = EnvironmentQuery3D::sample_fibonacci_annulus(center, 2.0, 6.0, 4);
	REQUIRE(samples.size() == 4);
	CHECK(samples == EnvironmentQuery3D::sample_fibonacci_annulus(center, 2.0, 6.0, 4));
	for (int i = 0; i < 4; i++) {
		const Vector3 point = samples[i];
		CHECK(point.y == center.y);
		const double radius_square = (point.x - center.x) * (point.x - center.x) + (point.z - center.z) * (point.z - center.z);
		CHECK(radius_square == doctest::Approx(4.0 + 32.0 * (double(i) + 0.5) / 4.0).epsilon(0.0001));
	}
	CHECK(samples[0].is_equal_approx(Vector3(10 + Math::sqrt(8.0), 3, 20)));
	const PackedVector3Array rotated = EnvironmentQuery3D::sample_fibonacci_annulus(center, 2.0, 6.0, 4, Math::PI / 2.0);
	REQUIRE(rotated.size() == 4);
	CHECK(rotated[0].is_equal_approx(center + Vector3(0, 0, Math::sqrt(8.0))));
	CHECK(!samples[1].is_equal_approx(samples[0])); // No duplicate radial spokes.
}

TEST_CASE("[EnvironmentQuery3D] Fibonacci annulus accepts zero-radius and thin annuli") {
	const Vector3 center(10, 7, 20);
	const PackedVector3Array zero = EnvironmentQuery3D::sample_fibonacci_annulus(center, 0.0, 0.0, 3);
	REQUIRE(zero.size() == 3);
	CHECK(zero[0] == center);
	CHECK(zero[2] == center);
	const PackedVector3Array thin = EnvironmentQuery3D::sample_fibonacci_annulus(center, 4.0, 4.0, 13);
	REQUIRE(thin.size() == 13);
	for (const Vector3 &point : thin) {
		CHECK(Math::is_equal_approx((point - center).length(), 4.0));
	}
}

TEST_CASE("[EnvironmentQuery3D] Fibonacci annulus rejects invalid geometry before allocation") {
	ERR_PRINT_OFF
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(INF, 0, 0), 1, 4, 8).is_empty());
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(), -1, 4, 8).is_empty());
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(), 5, 4, 8).is_empty());
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(), 1, INF, 8).is_empty());
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(), 1, 4, 8, NaN).is_empty());
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(), 1, 4, 0).is_empty());
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(), 1, 4, 65537).is_empty());
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(), 1, 1e250, 8).is_empty());
	ERR_PRINT_ON
	CHECK(EnvironmentQuery3D::sample_fibonacci_annulus(Vector3(), 1, 4, 65536).size() == 65536);
}

TEST_CASE("[EnvironmentQuery3D] EQS query budget rotates a fixed cohort fairly") {
	const int count = 80;
	const int budget = 8;
	PackedByteArray visited;
	visited.resize(count);
	for (int tick = 0; tick < 10; tick++) {
		const PackedByteArray mask = EnvironmentQuery3D::schedule_query_mask(count, tick, budget);
		REQUIRE(mask.size() == count);
		int admitted = 0;
		for (int i = 0; i < count; i++) {
			CHECK(mask[i] <= 1);
			if (mask[i] != 0) {
				admitted++;
				CHECK(visited[i] == 0);
				visited.set(i, 1);
			}
		}
		CHECK(admitted == budget);
		CHECK(EnvironmentQuery3D::schedule_query_mask(count, tick, budget) == mask);
	}
	for (int i = 0; i < count; i++) {
		CHECK(visited[i] == 1);
	}
	CHECK(EnvironmentQuery3D::schedule_query_mask(5, 9999999999LL, 3).size() == 5);
}

TEST_CASE("[EnvironmentQuery3D] EQS query budget urgent bypass preserves regular quota") {
	PackedByteArray urgent;
	urgent.resize(10);
	urgent.set(7, 1);
	urgent.set(9, 1);
	const PackedByteArray result = EnvironmentQuery3D::schedule_query_mask(10, 0, 3, urgent);
	REQUIRE(result.size() == 10);
	int admitted = 0;
	for (int i = 0; i < result.size(); i++) {
		admitted += int(result[i]);
	}
	CHECK(admitted == 5);
	CHECK(result[7] == 1);
	CHECK(result[9] == 1);
	CHECK(EnvironmentQuery3D::schedule_query_mask(10, 0, 0, urgent) == urgent);
	CHECK(EnvironmentQuery3D::schedule_query_mask(3, 1, 64) == PackedByteArray({ 1, 1, 1 }));
	CHECK(EnvironmentQuery3D::schedule_query_mask(0, 0, 0).is_empty());
}

TEST_CASE("[EnvironmentQuery3D] EQS query budget invalid requests fail closed") {
	ERR_PRINT_OFF
	CHECK(EnvironmentQuery3D::schedule_query_mask(-1, 0, 2).is_empty());
	CHECK(EnvironmentQuery3D::schedule_query_mask(4097, 0, 2).is_empty());
	CHECK(EnvironmentQuery3D::schedule_query_mask(10, -1, 2).is_empty());
	CHECK(EnvironmentQuery3D::schedule_query_mask(10, 0, -1).is_empty());
	CHECK(EnvironmentQuery3D::schedule_query_mask(10, 0, 65).is_empty());
	CHECK(EnvironmentQuery3D::schedule_query_mask(10, 0, 2, PackedByteArray({ 1, 0 })).is_empty());
	CHECK(EnvironmentQuery3D::schedule_query_mask(2, 0, 2, PackedByteArray({ 1, 2 })).is_empty());
	ERR_PRINT_ON
	CHECK(EnvironmentQuery3D::schedule_query_mask(4096, 0, 64).size() == 4096);
}

TEST_CASE("[EnvironmentQuery3D] Incremental top-K matches one-shot ranking and exact indices") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(3, 0, 0), Vector3(1, 0, 0), Vector3(3, 0, 0),
		Vector3(8, 0, 0), Vector3(5, 0, 0), Vector3(NaN, 0, 0),
		Vector3(4, 0, 0), Vector3(9, 0, 0)
	});
	q->set_max_distance(8);
	q->set_max_results(3);
	const PackedInt32Array expected_ids = q->query_top_indices(7);
	const PackedVector3Array expected_positions = q->query_top_positions(7);
	REQUIRE(expected_ids.size() == 3);
	REQUIRE(q->begin_incremental_top_positions(7));
	CHECK(!q->is_incremental_top_complete());
	CHECK(!q->step_incremental_top_positions(2));
	CHECK(q->get_incremental_processed_count() == 2);
	CHECK(q->get_incremental_top_indices().is_empty());
	CHECK(q->get_incremental_top_positions().is_empty());
	CHECK(!q->step_incremental_top_positions(3));
	CHECK(q->get_incremental_processed_count() == 5);
	CHECK(q->step_incremental_top_positions(3));
	CHECK(q->is_incremental_top_complete());
	CHECK(q->get_incremental_processed_count() == 8);
	CHECK(q->get_incremental_top_indices() == expected_ids);
	CHECK(q->get_incremental_top_positions() == expected_positions);
	CHECK(q->step_incremental_top_positions(1));
	CHECK(q->get_incremental_top_indices() == expected_ids);
	q->cancel_incremental_top_positions();
	CHECK(!q->is_incremental_top_complete());
	CHECK(q->get_incremental_top_indices().is_empty());
	CHECK(q->get_incremental_processed_count() == 0);
}

TEST_CASE("[EnvironmentQuery3D] Incremental seeded random-best reuses completed scoring") {
	Ref<EnvironmentQuery3D> q = make_query({
		Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(4, 0, 0),
		Vector3(-4, 0, 0), Vector3(5, 0, 0), Vector3(-5, 0, 0), Vector3(8, 0, 0)
	});
	q->set_max_distance(10);
	REQUIRE(q->begin_incremental_top_positions(8));
	CHECK(!q->step_incremental_top_positions(3));
	CHECK(q->get_incremental_random_best_positions(25, 5).is_empty());
	CHECK(!q->step_incremental_top_positions(3));
	CHECK(q->step_incremental_top_positions(3));
	for (int percent : { 0, 5, 25, 100 }) {
		for (int seed = 0; seed < 32; seed++) {
			CHECK(q->get_incremental_random_best_positions(percent, seed) ==
					q->query_random_best_positions(percent, seed));
		}
	}
	ERR_PRINT_OFF
	CHECK(q->get_incremental_random_best_positions(-1, 3).is_empty());
	CHECK(q->get_incremental_random_best_positions(101, 3).is_empty());
	ERR_PRINT_ON
	q->cancel_incremental_top_positions();
	CHECK(q->get_incremental_random_best_positions(25, 5).is_empty());
}

TEST_CASE("[EnvironmentQuery3D] Incremental snapshot isolates live parameter mutation and restarts") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(1, 0, 0), Vector3(4, 0, 0), Vector3(8, 0, 0) });
	const PackedVector3Array before = q->query_top_positions(2);
	REQUIRE(q->begin_incremental_top_positions(2));
	CHECK(!q->step_incremental_top_positions(1));
	q->set_origin(Vector3(10, 0, 0));
	q->set_candidates({ Vector3(100, 0, 0) });
	CHECK(q->step_incremental_top_positions(2));
	CHECK(q->get_incremental_top_positions() == before);
	CHECK(q->begin_incremental_top_positions(2));
	CHECK(q->get_incremental_processed_count() == 0);
	CHECK(q->step_incremental_top_positions(1));
	CHECK(q->get_incremental_top_positions() == q->query_top_positions(2));
}

TEST_CASE("[EnvironmentQuery3D] Incremental query handles empty and filtered scenes, invalid budgets") {
	Ref<EnvironmentQuery3D> q = make_query();
	REQUIRE(q->begin_incremental_top_positions(3));
	CHECK(q->is_incremental_top_complete());
	CHECK(q->get_incremental_top_positions().is_empty());
	q->set_candidates({ Vector3(2, 0, 0), Vector3(5, 0, 0) });
	q->set_min_distance(10);
	REQUIRE(q->begin_incremental_top_positions(3));
	CHECK(q->step_incremental_top_positions(1) == false);
	CHECK(q->step_incremental_top_positions(1));
	CHECK(q->get_incremental_top_indices().is_empty());
	ERR_PRINT_OFF
	CHECK(!q->begin_incremental_top_positions(0));
	CHECK(!q->begin_incremental_top_positions(65));
	CHECK(!q->step_incremental_top_positions(1));
	CHECK(q->begin_incremental_top_positions(3));
	CHECK(!q->step_incremental_top_positions(0));
	CHECK(!q->step_incremental_top_positions(4097));
	ERR_PRINT_ON
	CHECK(q->get_incremental_processed_count() == 0);
	CHECK(q->step_incremental_top_positions(2));
	CHECK(q->get_incremental_top_indices().is_empty());
}

TEST_CASE("[EnvironmentQuery3D] Evaluation does not mutate input candidates") {
	PackedVector3Array points = { Vector3(7, 0, 0), Vector3(1, 0, 0) };
	Ref<EnvironmentQuery3D> q = make_query(points);
	q->query();
	CHECK(q->get_candidates() == points);
}

TEST_CASE("[EnvironmentQuery3D] Resource roundtrip preserves parameters") {
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(6, 0, 0), Vector3(2, 0, 0) });
	q->set_desired_distance(6);
	q->set_max_distance(50);
	q->set_max_results(1);
	q->set_max_vertical_difference(2.5);
	q->set_max_direction_dot(0.8); // Serialized even when the filter is disabled.
	q->set_use_threat(true);
	q->set_threat_position(Vector3());
	q->set_threat_positions({ Vector3(0, 0, 0), Vector3(1, 0, 0) });
	q->set_safety_weight(2);
	const String path = TestUtils::get_temp_path("environment_query_3d_roundtrip.tres");
	REQUIRE(ResourceSaver::save(q, path) == OK);
	Ref<EnvironmentQuery3D> loaded = ResourceLoader::load(path);
	REQUIRE(loaded.is_valid());
	CHECK(loaded->get_candidates().size() == 2);
	CHECK(loaded->get_desired_distance() == 6);
	CHECK(loaded->is_using_threat());
	CHECK(loaded->get_threat_positions() == q->get_threat_positions());
	CHECK(loaded->get_max_results() == 1);
	CHECK(loaded->get_max_vertical_difference() == doctest::Approx(2.5));
	CHECK(loaded->get_max_direction_dot() == doctest::Approx(0.8));
	CHECK(loaded->query_positions()[0] == Vector3(6, 0, 0));
}

} // namespace TestEnvironmentQuery3D
#endif // MODULE_ENVIRONMENT_QUERY_ENABLED
