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
	Ref<EnvironmentQuery3D> q = make_query({ Vector3(Math::NaN, 0, 0), Vector3(1, 0, 0) });
	CHECK(q->query().size() == 1);
	CHECK(int(first_result(q)["index"]) == 1);
}

TEST_CASE("[EnvironmentQuery3D] Invalid origin and threat positions are rejected") {
	Ref<EnvironmentQuery3D> q = make_query();
	q->set_origin(Vector3(2, 0, 0));
	q->set_threat_position(Vector3(3, 0, 0));
	ERR_PRINT_OFF
	q->set_origin(Vector3(Math::INF, 0, 0));
	q->set_threat_position(Vector3(Math::NaN, 0, 0));
	ERR_PRINT_ON
	CHECK(q->get_origin() == Vector3(2, 0, 0));
	CHECK(q->get_threat_position() == Vector3(3, 0, 0));
}

TEST_CASE("[EnvironmentQuery3D] Reject invalid limits and weights") {
	Ref<EnvironmentQuery3D> q = make_query();
	ERR_PRINT_OFF
	q->set_min_distance(-1);
	q->set_max_distance(Math::NaN);
	q->set_desired_distance(-3);
	q->set_distance_weight(-2);
	q->set_safety_weight(Math::INF);
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
	q->set_use_threat(true);
	q->set_threat_position(Vector3());
	q->set_safety_weight(2);
	const String path = TestUtils::get_temp_path("environment_query_3d_roundtrip.tres");
	REQUIRE(ResourceSaver::save(q, path) == OK);
	Ref<EnvironmentQuery3D> loaded = ResourceLoader::load(path);
	REQUIRE(loaded.is_valid());
	CHECK(loaded->get_candidates().size() == 2);
	CHECK(loaded->get_desired_distance() == 6);
	CHECK(loaded->is_using_threat());
	CHECK(loaded->get_max_results() == 1);
	CHECK(loaded->query_positions()[0] == Vector3(6, 0, 0));
}

} // namespace TestEnvironmentQuery3D
#endif // MODULE_ENVIRONMENT_QUERY_ENABLED
