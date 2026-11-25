/**************************************************************************/
/*  test_cgame_formations.h                                               */
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

#include "../cgame_formations.h"
#include "core/math/random_number_generator.h"
#include "core/object/callable_mp.h"
#include "tests/test_macros.h"

namespace TestCgameFormations {

static double brute(const PackedVector2Array &p_slots, const PackedVector2Array &p_members, int p_i, Vector<bool> &r_used) {
	if (p_i == p_members.size()) {
		return 0.0;
	}
	double best = Math::INF;
	for (int j = 0; j < p_slots.size(); j++) {
		if (r_used[j]) {
			continue;
		}
		r_used.write[j] = true;
		best = MIN(best, double(p_members[p_i].distance_to(p_slots[j])) + brute(p_slots, p_members, p_i + 1, r_used));
		r_used.write[j] = false;
	}
	return best;
}

static double brute_best(const PackedVector2Array &p_slots, const PackedVector2Array &p_members) {
	Vector<bool> used;
	used.resize(p_slots.size());
	used.fill(false);
	return brute(p_slots, p_members, 0, used);
}

static bool valid_assignment(const PackedInt32Array &p_a, int p_slot_count) {
	HashSet<int> seen;
	for (int i = 0; i < p_a.size(); i++) {
		const int s = p_a[i];
		if (s < 0) {
			continue;
		}
		if (s >= p_slot_count || seen.has(s)) {
			return false;
		}
		seen.insert(s);
	}
	return true;
}

static bool wall_walkable(Vector2 p_pt) {
	return !(p_pt.x > -3.0 && p_pt.x < 3.0 && p_pt.y > -1.0 && p_pt.y < 12.0);
}

static bool tiny_walkable(Vector2 p_pt) {
	return p_pt.distance_to(Vector2(-10, 0)) < 0.5;
}

TEST_CASE("[CgameFormations] slot layouts keep spacing and counts") {
	const PackedStringArray kinds = CgameFormations::get_kinds();
	CHECK(kinds.size() == 4);
	const int counts[] = { 1, 2, 5, 9, 16 };
	for (int k = 0; k < kinds.size(); k++) {
		for (int n : counts) {
			const PackedVector2Array sl = CgameFormations::slots(kinds[k], n, 2.0);
			CHECK(sl.size() == n);
			double min_d = Math::INF;
			for (int i = 0; i < sl.size(); i++) {
				for (int j = i + 1; j < sl.size(); j++) {
					min_d = MIN(min_d, double(sl[i].distance_to(sl[j])));
				}
			}
			if (n > 1) {
				CHECK(min_d >= 2.0 - 0.001);
			}
		}
	}
	const PackedVector2Array col = CgameFormations::slots("column", 4, 3.0);
	CHECK(Math::abs(col[3].x + 9.0) < 0.001);
	const PackedVector2Array tg = CgameFormations::targets(Vector2(10, 10), Math::PI * 0.5, "column", 3, 2.0);
	CHECK(Math::abs(tg[1].x - 10.0) < 0.001);
	CHECK(Math::abs(tg[1].y - 8.0) < 0.001);
	const PackedVector2Array lin = CgameFormations::slots("line", 3, 2.0);
	CHECK(Math::abs(lin[0].y + lin[2].y) < 0.001);
	CHECK(CgameFormations::slots("wedge", 0, 2.0).size() == 0);
}

TEST_CASE("[CgameFormations] Hungarian assignment is optimal, greedy fallback is valid") {
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed(4242);
	bool optimal = true;
	for (int trial = 0; trial < 25; trial++) {
		const int nn = 2 + trial % 5;
		PackedVector2Array sw;
		PackedVector2Array mm;
		for (int i = 0; i < nn; i++) {
			const real_t sx = rng->randf_range(0, 50);
			const real_t sy = rng->randf_range(0, 50);
			sw.push_back(Vector2(sx, sy));
			const real_t mx = rng->randf_range(0, 50);
			const real_t my = rng->randf_range(0, 50);
			mm.push_back(Vector2(mx, my));
		}
		const PackedInt32Array asg = CgameFormations::assign(sw, mm);
		if (!valid_assignment(asg, nn)) {
			optimal = false;
		} else if (Math::abs(CgameFormations::assignment_cost(sw, mm, asg) - brute_best(sw, mm)) > 0.0001) {
			optimal = false;
		}
	}
	CHECK(optimal);

	PackedVector2Array sw2;
	sw2.push_back(Vector2(0, 0));
	sw2.push_back(Vector2(10, 0));
	sw2.push_back(Vector2(20, 0));
	PackedVector2Array mm2;
	mm2.push_back(Vector2(19, 1));
	mm2.push_back(Vector2(1, 1));
	mm2.push_back(Vector2(11, 1));
	const PackedInt32Array asg2 = CgameFormations::assign(sw2, mm2);
	REQUIRE(asg2.size() == 3);
	CHECK(asg2[0] == 2);
	CHECK(asg2[1] == 0);
	CHECK(asg2[2] == 1);

	PackedVector2Array sw3;
	sw3.push_back(Vector2(0, 0));
	sw3.push_back(Vector2(10, 0));
	PackedVector2Array mm3;
	mm3.push_back(Vector2(0, 1));
	mm3.push_back(Vector2(10, 1));
	mm3.push_back(Vector2(500, 500));
	const PackedInt32Array asg3 = CgameFormations::assign(sw3, mm3);
	REQUIRE(asg3.size() == 3);
	CHECK(asg3[0] == 0);
	CHECK(asg3[1] == 1);
	CHECK(asg3[2] == -1);

	const int big_n = 100;
	const PackedVector2Array big_s = CgameFormations::slots("circle", big_n, 1.5);
	PackedVector2Array big_m;
	for (int i = 0; i < big_n; i++) {
		const real_t x = rng->randf_range(-60, 60);
		const real_t y = rng->randf_range(-60, 60);
		big_m.push_back(Vector2(x, y));
	}
	const PackedInt32Array big_a = CgameFormations::assign(big_s, big_m);
	CHECK(valid_assignment(big_a, big_n));
	bool all_assigned = true;
	for (int i = 0; i < big_a.size(); i++) {
		if (big_a[i] < 0) {
			all_assigned = false;
		}
	}
	CHECK(all_assigned);
	PackedVector2Array first64;
	for (int i = 0; i < 64; i++) {
		first64.push_back(big_m[i]);
	}
	CHECK(valid_assignment(CgameFormations::assign(CgameFormations::slots("line", 64, 1.0), first64), 64));
}

TEST_CASE("[CgameFormations] Invalid costs cannot stall assignment") {
	PackedVector2Array slots;
	slots.push_back(Vector2());
	slots.push_back(Vector2(5, 0));
	PackedVector2Array members;
	members.push_back(Vector2(Math::NaN, 0));
	members.push_back(Vector2(5, 0));
	PackedInt32Array rejected = CgameFormations::assign(slots, members);
	REQUIRE(rejected.size() == 2);
	CHECK(rejected[0] == -1);
	CHECK(rejected[1] == -1);
	members.write[0] = Vector2(1.0e20, 0);
	rejected = CgameFormations::assign(slots, members);
	CHECK(rejected[0] == -1);
	CHECK(rejected[1] == -1);
	members.write[0] = Vector2();
	const PackedInt32Array valid = CgameFormations::assign(slots, members);
	CHECK(valid[0] == 0);
	CHECK(valid[1] == 1);
	slots.write[0] = Vector2(Math::INF, 0);
	CHECK(CgameFormations::assign(slots, members)[0] == -1);
}

TEST_CASE("[CgameFormations] blending and smoothing") {
	const PackedVector2Array from_s = CgameFormations::slots("line", 4, 2.0);
	const PackedVector2Array to_s = CgameFormations::slots("column", 4, 2.0);
	const PackedVector2Array mid = CgameFormations::blend(from_s, to_s, 0.5);
	CHECK(mid[0].distance_to(from_s[0].lerp(to_s[0], 0.5)) < 0.0001);
	PackedVector2Array cur = from_s;
	for (int i = 0; i < 120; i++) {
		cur = CgameFormations::smooth(cur, to_s, 0.05);
	}
	CHECK(cur[3].distance_to(to_s[3]) < 0.01);
	CHECK(CgameFormations::smooth(from_s, CgameFormations::slots("line", 6, 2.0), 0.0).size() == 6);
}

TEST_CASE("[CgameFormations] obstacle-aware slot shifting") {
	const Callable wall = callable_mp_static(&wall_walkable);
	const PackedVector2Array base = CgameFormations::targets(Vector2(0, 0), 0.0, "line", 7, 2.0);
	int blocked_before = 0;
	for (int i = 0; i < base.size(); i++) {
		if (!wall_walkable(base[i])) {
			blocked_before++;
		}
	}
	CHECK(blocked_before > 0);
	const PackedVector2Array fixed = CgameFormations::shift_slots(base, wall, Vector2(-10, 0), 2.0);
	REQUIRE(fixed.size() == base.size());
	bool all_walkable = true;
	bool untouched = true;
	for (int i = 0; i < fixed.size(); i++) {
		if (!wall_walkable(fixed[i])) {
			all_walkable = false;
		}
		if (wall_walkable(base[i]) && base[i] != fixed[i]) {
			untouched = false;
		}
	}
	CHECK(all_walkable);
	CHECK(untouched);
	PackedVector2Array lone;
	lone.push_back(Vector2(5, 5));
	const PackedVector2Array squeezed = CgameFormations::shift_slots(lone, callable_mp_static(&tiny_walkable), Vector2(-10, 0), 2.0, 2);
	REQUIRE(squeezed.size() == 1);
	CHECK(tiny_walkable(squeezed[0]));
}

} // namespace TestCgameFormations
