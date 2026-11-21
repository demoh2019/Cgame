/**************************************************************************/
/*  test_cgame_smart_objects.h                                            */
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

#include "../cgame_smart_objects.h"
#include "core/object/callable_mp.h"
#include "tests/test_macros.h"

namespace TestCgameSmartObjects {

using namespace CgameAITestUtil;

static Vector<String> g_effects;

static void on_effect_cb(String p_effect, Variant p_user, String p_object) {
	g_effects.push_back(vformat("%s:%s:%s", p_effect, String(p_user), p_object));
}

static bool reach_cb(Vector3 p_pos) {
	return p_pos.x < 20.0 || p_pos.z > 30.0;
}

static bool unreachable_cb(Vector3 p_pos) {
	return false;
}

static Dictionary make_object(const char *p_id, const Vector3 &p_pos, const Array &p_tags, const char *p_behavior = "sit", int p_slots = 2) {
	Array slots;
	for (int i = 0; i < p_slots; i++) {
		slots.push_back(dict({ { "offset", Vector3(real_t(i) * 0.5f, 0, 0) }, { "behavior", p_behavior }, { "tags", arr({ "seat" }) } }));
	}
	return dict({ { "id", p_id }, { "position", p_pos }, { "tags", p_tags }, { "slots", slots } });
}

TEST_CASE("[CgameSmartObjects] find ranks by distance, tags and behavior") {
	Ref<CgameSmartObjects> so;
	so.instantiate();
	CHECK(so->register_object(make_object("bench_near", Vector3(2, 0, 0), arr({ "public" }))));
	so->register_object(make_object("bench_far", Vector3(20, 0, 0), arr({ "public", "shade" })));
	so->register_object(make_object("fire", Vector3(3, 0, 0), arr({ "warm" }), "warm_up", 1));
	CHECK_FALSE(so->register_object(dict({ { "id", "bad" } })));
	Dictionary q = dict({ { "position", Vector3() }, { "radius", 30.0 }, { "behavior", "sit" } });
	Array res = so->find(q);
	CHECK(res.size() == 4);
	CHECK(String(Dictionary(res[0])["object"]) == "bench_near");
	q["radius"] = 10.0;
	CHECK(so->find(q).size() == 2);
	q["radius"] = 30.0;
	q["required_tags"] = arr({ "shade" });
	res = so->find(q);
	CHECK(res.size() == 2);
	CHECK(String(Dictionary(res[0])["object"]) == "bench_far");
	q["required_tags"] = Array();
	q["preferred_tags"] = arr({ "shade" });
	res = so->find(q);
	CHECK(String(Dictionary(res[0])["object"]) == "bench_far");
	CHECK(so->find(dict({ { "position", Vector3() }, { "radius", 30.0 }, { "behavior", "warm_up" } })).size() == 1);
}

TEST_CASE("[CgameSmartObjects] exclusive claims, release and timeouts") {
	Ref<CgameSmartObjects> so;
	so.instantiate();
	so->register_object(make_object("bench_near", Vector3(2, 0, 0), arr({ "public" })));
	so->register_object(make_object("bench_far", Vector3(20, 0, 0), arr({ "public", "shade" })));
	const int h1 = so->claim("bench_near", 0, "npc1");
	CHECK(h1 > 0);
	CHECK(so->claim("bench_near", 0, "npc2") == 0);
	CHECK(so->claim("bench_near", 1, "npc2") > 0);
	CHECK(so->claim("bench_near", 9, "npc3") == 0);
	CHECK(so->claim("ghost", 0, "npc3") == 0);
	Dictionary q = dict({ { "position", Vector3() }, { "radius", 10.0 }, { "behavior", "sit" } });
	CHECK(so->find(q).size() == 0);
	q["include_claimed"] = true;
	CHECK(so->find(q).size() == 2);
	CHECK(String(so->claim_user(h1)) == "npc1");
	CHECK(so->release(h1));
	CHECK_FALSE(so->release(h1));
	CHECK(so->claim("bench_near", 0, "npc3") > 0);

	const int short_claim = so->claim("bench_far", 0, "npc4", 1.0);
	so->advance(0.6);
	CHECK(so->is_claimed(short_claim));
	so->touch(short_claim);
	so->advance(0.6);
	CHECK(so->is_claimed(short_claim));
	so->advance(0.6);
	CHECK_FALSE(so->is_claimed(short_claim));
	CHECK(so->is_slot_free("bench_far", 0));
	const int forever = so->claim("bench_far", 1, "npc5", 0.0);
	so->advance(1000.0);
	CHECK(so->is_claimed(forever));
	so->unregister_object("bench_far");
	CHECK_FALSE(so->is_claimed(forever));
}

TEST_CASE("[CgameSmartObjects] placement is deterministic, spaced and reachable") {
	const Rect2 area(0, 0, 40, 40);
	const Callable reach = callable_mp_static(&reach_cb);
	const Dictionary rules = dict({ { "min_spacing", 4.0 }, { "density", 2.0 }, { "nav_reachable", reach }, { "candidates", 12 } });
	Ref<CgameSmartObjects> so_a;
	so_a.instantiate();
	Ref<CgameSmartObjects> so_b;
	so_b.instantiate();
	Ref<CgameSmartObjects> so_c;
	so_c.instantiate();
	const Array a = so_a->auto_place(area, 12, rules, 1234);
	const Array b = so_b->auto_place(area, 12, rules, 1234);
	CHECK(a == b);
	CHECK(a != so_c->auto_place(area, 12, rules, 99));
	CHECK(a.size() > 5);
	bool spacing_ok = true;
	bool reach_ok = true;
	bool inside = true;
	for (int i = 0; i < a.size(); i++) {
		const Vector3 p = a[i];
		reach_ok = reach_ok && reach_cb(p);
		inside = inside && area.has_point(Vector2(p.x, p.z));
		for (int j = i + 1; j < a.size(); j++) {
			if (p.distance_to(a[j]) < 4.0) {
				spacing_ok = false;
			}
		}
	}
	CHECK(spacing_ok);
	CHECK(reach_ok);
	CHECK(inside);
	const Callable none = callable_mp_static(&unreachable_cb);
	CHECK(so_a->auto_place(area, 5, dict({ { "nav_reachable", none } }), 1).size() == 0);
	CHECK(so_a->placement_score(Vector3(), none, 2.0) == 0.0);
	CHECK(so_a->placement_score(Vector3(), Callable(), 2.0, arr({ Vector3(1, 0, 0) }), 4.0) == 0.0);
	const double open_score = so_a->placement_score(Vector3(), Callable(), 1.0, Array(), 4.0);
	const double crowded = so_a->placement_score(Vector3(), Callable(), 1.0, arr({ Vector3(6, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 6) }), 4.0);
	CHECK(open_score > crowded);
	CHECK(crowded > 0.0);
}

TEST_CASE("[CgameSmartObjects] interaction graph, effects and completion") {
	g_effects.clear();
	Ref<CgameSmartObjects> so;
	so.instantiate();
	so->set_on_effect(callable_mp_static(&on_effect_cb));
	so->register_behavior("sit", arr({
										 dict({ { "anim", "sit_down" }, { "duration", 1.0 }, { "effect", "" } }),
										 dict({ { "anim", "sit_idle" }, { "duration", 2.0 }, { "effect", "heal" } }),
										 dict({ { "anim", "stand_up" }, { "duration", 0.5 } }),
								 }));
	so->register_object(make_object("bench", Vector3(), Array(), "sit", 1));
	const int h = so->claim("bench", 0, "npc");
	CHECK_FALSE(so->start_interaction(0));
	CHECK(so->start_interaction(h));
	CHECK(String(so->interaction_state(h)["anim"]) == "sit_down");
	so->advance(0.4);
	CHECK(Math::abs(double(so->interaction_state(h)["t"]) - 0.4) < 0.0001);
	so->advance(0.7);
	CHECK(String(so->interaction_state(h)["anim"]) == "sit_idle");
	CHECK(g_effects == psa({ "heal:npc:bench" }));
	Array done = so->advance(2.0);
	CHECK(String(so->interaction_state(h)["anim"]) == "stand_up");
	CHECK(done.size() == 0);
	done = so->advance(5.0);
	REQUIRE(done.size() == 1);
	CHECK(int(done[0]) == h);
	CHECK_FALSE(so->is_claimed(h));
	CHECK(so->is_slot_free("bench", 0));
	CHECK(g_effects.size() == 1);

	so->set_release_on_complete(false);
	const int h2 = so->claim("bench", 0, "npc2", 0.0);
	so->start_interaction(h2);
	so->advance(100.0);
	CHECK(so->is_claimed(h2));
	CHECK(so->claim("bench", 0, "x") == 0);
	so->register_object(dict({ { "id", "plain" }, { "position", Vector3() }, { "slots", arr({ dict({ { "behavior", "unknown" } }) }) } }));
	const int h4 = so->claim("plain", 0, "npc");
	CHECK_FALSE(so->start_interaction(h4));
}

} // namespace TestCgameSmartObjects
