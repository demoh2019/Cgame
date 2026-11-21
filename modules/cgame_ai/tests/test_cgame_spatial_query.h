/**************************************************************************/
/*  test_cgame_spatial_query.h                                            */
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

#pragma once

#include "test_cgame_ai_helpers.h"

#include "../cgame_spatial_query.h"
#include "../cgame_utility_ai.h"
#include "core/object/callable_mp.h"
#include "tests/test_macros.h"

namespace TestCgameSpatialQuery {

using namespace CgameAITestUtil;

static Array nav_points(Vector3 p_center, double p_radius, int p_count) {
	Array out;
	for (int i = 0; i < p_count; i++) {
		out.push_back(p_center + Vector3(real_t(i), 0, 0));
	}
	return out;
}

static bool trace_cb(Vector3 p_from, Vector3 p_to) {
	return p_to.z <= 10.0;
}

static double path_len_cb(Vector3 p_from, Vector3 p_to) {
	return p_to.z > 12.0 ? -1.0 : 6.0;
}

static double custom_mine(Vector3 p_pos, Dictionary p_ctx, Dictionary p_item) {
	return p_pos.x > 10.0 ? 1.0 : 0.0;
}

static Dictionary make_context() {
	Dictionary ctx = dict({
			{ "querier", Vector3(10, 0, 10) },
			{ "facing", Vector3(1, 0, 0) },
			{ "target", Vector3(30, 0, 10) },
			{ "actors", arr({
								dict({ { "position", Vector3(12, 0, 10) }, { "type", "enemy" }, { "id", "e1" } }),
								dict({ { "position", Vector3(50, 0, 10) }, { "type", "enemy" }, { "id", "far" } }),
								dict({ { "position", Vector3(11, 0, 10) }, { "type", "ally" }, { "id", "a1" } }),
						}) },
	});
	ctx["navmesh_points"] = callable_mp_static(&nav_points);
	return ctx;
}

static Dictionary grid_asset(double p_half, double p_spacing) {
	Dictionary a = CgameSpatialQuery::new_asset();
	CgameSpatialQuery::add_generator(a, CgameSpatialQuery::make_generator("grid", dict({ { "half_extents", p_half }, { "spacing", p_spacing } })));
	return a;
}

TEST_CASE("[CgameSpatialQuery] generators") {
	const Dictionary ctx = make_context();
	Ref<CgameSpatialQuery> q;
	q.instantiate();
	CHECK(q->run(grid_asset(4.0, 2.0), ctx).size() == 25);

	Dictionary a = CgameSpatialQuery::new_asset();
	CgameSpatialQuery::add_generator(a, CgameSpatialQuery::make_generator("ring", dict({ { "radius", 5.0 }, { "count", 12 } })));
	const Array ring = q->run(a, ctx);
	CHECK(ring.size() == 12);
	const Dictionary first = ring[0];
	CHECK(Math::abs(Vector3(first["position"]).distance_to(Vector3(10, 0, 10)) - 5.0) < 0.001);

	a = CgameSpatialQuery::new_asset();
	CgameSpatialQuery::add_generator(a, CgameSpatialQuery::make_generator("navmesh", dict({ { "count", 7 } })));
	CHECK(q->run(a, ctx).size() == 7);

	a = CgameSpatialQuery::new_asset();
	CgameSpatialQuery::add_generator(a, CgameSpatialQuery::make_generator("actors", dict({ { "actor_type", "enemy" }, { "radius", 20.0 } })));
	const Array act = q->run(a, ctx);
	CHECK(act.size() == 1);
	CHECK(String(Dictionary(act[0])["actor"]) == "e1");
	CHECK(CgameSpatialQuery::validate(CgameSpatialQuery::new_asset()).size() == 1);
}

TEST_CASE("[CgameSpatialQuery] tests, filters and scoring") {
	Dictionary ctx = make_context();
	Ref<CgameSpatialQuery> q;
	q.instantiate();
	Dictionary a = grid_asset(6.0, 2.0);
	CgameSpatialQuery::add_test(a, CgameSpatialQuery::make_test("distance", dict({ { "max", 10.0 }, { "invert", true } })));
	const Array scored = q->run(a, ctx);
	CHECK(Math::abs(double(Dictionary(scored[0])["score"]) - 1.0) < 0.001);
	bool sorted_ok = true;
	for (int i = 1; i < scored.size(); i++) {
		if (double(Dictionary(scored[i])["score"]) > double(Dictionary(scored[i - 1])["score"])) {
			sorted_ok = false;
		}
	}
	CHECK(sorted_ok);
	const Dictionary dbg = q->get_debug();
	CHECK(int(Dictionary(Dictionary(dbg["tests"])["distance_0"])["evaluated"]) == 49);

	CgameSpatialQuery::add_test(a, CgameSpatialQuery::make_test("dot", dict({ { "filter_min", 0.0 }, { "score", false } })));
	const Array fwd = q->run(a, ctx);
	bool all_forward = true;
	for (int i = 0; i < fwd.size(); i++) {
		if (Vector3(Dictionary(fwd[i])["position"]).x < 10.0) {
			all_forward = false;
		}
	}
	CHECK(all_forward);
	CHECK(fwd.size() < 49);
	CHECK(fwd.size() > 0);
	CHECK(int(Dictionary(Dictionary(q->get_debug()["filtered_by"]))["dot_1"]) > 0);

	CgameSpatialQuery::add_test(a, CgameSpatialQuery::make_test("trace", dict({ { "filter_min", 0.5 } })));
	ctx["trace"] = callable_mp_static(&trace_cb);
	const Array vis = q->run(a, ctx);
	bool vis_ok = true;
	for (int i = 0; i < vis.size(); i++) {
		if (Vector3(Dictionary(vis[i])["position"]).z > 10.0) {
			vis_ok = false;
		}
	}
	CHECK(vis_ok);
	CHECK(vis.size() > 0);

	Dictionary b = CgameSpatialQuery::new_asset();
	CgameSpatialQuery::add_generator(b, CgameSpatialQuery::make_generator("ring", dict({ { "radius", 5.0 }, { "count", 8 } })));
	CgameSpatialQuery::add_test(b, CgameSpatialQuery::make_test("path_length", dict({ { "max", 10.0 }, { "invert", true }, { "filter_max", 8.0 } })));
	ctx["path_length"] = callable_mp_static(&path_len_cb);
	const Array pathed = q->run(b, ctx);
	CHECK(pathed.size() > 0);
	CHECK(pathed.size() < 8);
	CgameSpatialQuery::add_test(b, CgameSpatialQuery::make_test("custom", dict({ { "callable", "mine" }, { "weight", 2.0 } })));
	ctx["custom"] = dict({ { "mine", callable_mp_static(&custom_mine) } });
	const Array cust = q->run(b, ctx);
	CHECK(cust.size() > 0);
	CHECK(Vector3(Dictionary(cust[0])["position"]).x > 10.0);
	b["combine"] = "iaus";
	b["max_results"] = 2;
	CHECK(q->run(b, ctx).size() == 2);
}

TEST_CASE("[CgameSpatialQuery] time slicing equals a full run") {
	Dictionary ctx = make_context();
	Dictionary c = grid_asset(8.0, 1.0);
	CgameSpatialQuery::add_test(c, CgameSpatialQuery::make_test("distance", dict({ { "max", 12.0 }, { "invert", true }, { "curve", int(CgameUtilityAI::QUADRATIC) } })));
	CgameSpatialQuery::add_test(c, CgameSpatialQuery::make_test("dot", dict({ { "weight", 0.5 } })));
	Ref<CgameSpatialQuery> full_q;
	full_q.instantiate();
	const Array full = full_q->run(c, ctx).duplicate();
	Ref<CgameSpatialQuery> s;
	s.instantiate();
	CHECK(s->start(c, ctx) == 289);
	int steps = 0;
	while (!s->step(40)) {
		steps++;
		CHECK(s->progress() < 1.0);
	}
	CHECK(steps >= 6);
	CHECK(s->is_done());
	const Array sliced = s->get_results();
	REQUIRE(full.size() == sliced.size());
	bool same = true;
	for (int i = 0; i < full.size(); i++) {
		const Dictionary fa = full[i];
		const Dictionary sa = sliced[i];
		if (int(fa["index"]) != int(sa["index"]) || Math::abs(double(fa["score"]) - double(sa["score"])) > 0.00001) {
			same = false;
		}
	}
	CHECK(same);
	CHECK(int(s->get_debug()["steps"]) > 1);
	CHECK(s->get_candidates().size() == 289);
}

} // namespace TestCgameSpatialQuery
