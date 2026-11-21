/**************************************************************************/
/*  test_cgame_crowd_avoidance.h                                          */
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

#pragma once

#include "../cgame_crowd_avoidance.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestCgameCrowdAvoidance {

struct CrossingResult {
	real_t min_distance = 1000.0;
	bool finite = true;
	double checksum = 0.0;
};

// Two opposing blocks swapping sides through each other (mirrors test_mass_crowd.gd).
static CrossingResult run_crossing(int p_per_side, int p_steps) {
	const int n = p_per_side * 2;
	const real_t radius = 0.5;
	PackedVector2Array pos;
	PackedVector2Array goals;
	PackedVector2Array vel;
	for (int i = 0; i < n; i++) {
		const int local = i % p_per_side;
		const int col = local % 10;
		const int row = local / 10;
		const bool east = i < p_per_side;
		const real_t x = -20.0 + col * 1.4;
		const real_t y = -6.3 + row * 1.4 + (east ? 0.1 : -0.1);
		pos.push_back(Vector2(east ? x : -x, y));
		goals.push_back(Vector2(east ? -x : x, y));
		vel.push_back(Vector2());
	}
	CrossingResult result;
	for (int s = 0; s < p_steps; s++) {
		PackedVector2Array pref;
		for (int i = 0; i < n; i++) {
			pref.push_back((goals[i] - pos[i]).limit_length(1.4));
		}
		vel = CgameCrowdAvoidance::compute_velocities(pos, vel, pref, radius, 1.4, 5.0, 6.0, 16, 0.1);
		for (int i = 0; i < n; i++) {
			pos.write[i] += vel[i] * 0.1;
			if (!Math::is_finite(pos[i].x) || !Math::is_finite(pos[i].y)) {
				result.finite = false;
			}
		}
		if (s % 4 == 0) {
			for (int i = 0; i < n; i++) {
				for (int j = i + 1; j < n; j++) {
					result.min_distance = MIN(result.min_distance, pos[i].distance_to(pos[j]));
				}
			}
		}
	}
	for (int i = 0; i < n; i++) {
		result.checksum += pos[i].x * 3.1 + pos[i].y;
	}
	return result;
}

TEST_CASE("[CgameCrowdAvoidance] head-on agents keep distance and reach their goals") {
	const real_t radius = 0.5;
	PackedVector2Array pos;
	pos.push_back(Vector2(-5, 0.2));
	pos.push_back(Vector2(5, -0.2));
	PackedVector2Array vel;
	vel.push_back(Vector2());
	vel.push_back(Vector2());
	PackedVector2Array goals;
	goals.push_back(Vector2(5, 0.2));
	goals.push_back(Vector2(-5, -0.2));
	real_t min_d = 1000.0;
	for (int s = 0; s < 200; s++) {
		PackedVector2Array pref;
		for (int i = 0; i < 2; i++) {
			pref.push_back((goals[i] - pos[i]).limit_length(1.5));
		}
		vel = CgameCrowdAvoidance::compute_velocities(pos, vel, pref, radius, 1.5, 3.0, 10.0, 10, 0.1);
		for (int i = 0; i < 2; i++) {
			pos.write[i] += vel[i] * 0.1;
		}
		min_d = MIN(min_d, pos[0].distance_to(pos[1]));
	}
	CHECK(min_d >= 2.0 * radius * 0.95);
	CHECK(pos[0].distance_to(goals[0]) < 1.0);
	CHECK(pos[1].distance_to(goals[1]) < 1.0);
}

TEST_CASE("[CgameCrowdAvoidance] empty input and lone agent") {
	PackedVector2Array empty;
	CHECK(CgameCrowdAvoidance::compute_velocities(empty, empty, empty, 0.5, 1.5, 3.0, 10.0, 10, 0.1).is_empty());

	PackedVector2Array pos;
	pos.push_back(Vector2(1, 1));
	PackedVector2Array vel;
	vel.push_back(Vector2());
	PackedVector2Array pref;
	pref.push_back(Vector2(0.5, 0.0));
	PackedVector2Array out = CgameCrowdAvoidance::compute_velocities(pos, vel, pref, 0.5, 1.5, 3.0, 10.0, 10, 0.1);
	REQUIRE(out.size() == 1);
	CHECK(out[0].is_equal_approx(Vector2(0.5, 0.0)));

	// The preferred velocity is clamped to max_speed.
	pref.write[0] = Vector2(10, 0);
	out = CgameCrowdAvoidance::compute_velocities(pos, vel, pref, 0.5, 1.5, 3.0, 10.0, 10, 0.1);
	CHECK(out[0].is_equal_approx(Vector2(1.5, 0.0)));
}

TEST_CASE("[CgameCrowdAvoidance] 200 crossing agents do not explode and stay deterministic") {
	const CrossingResult a = run_crossing(100, 260);
	const CrossingResult b = run_crossing(100, 260);
	CHECK(a.min_distance >= 0.5 * 2.0 * 0.6);
	CHECK(a.finite);
	CHECK(a.checksum == b.checksum);
}

TEST_CASE("[CgameCrowdAvoidance] parallel path (600 agents) is deterministic and bounded") {
	const real_t max_speed = 1.4;
	PackedVector2Array pos;
	PackedVector2Array vel;
	PackedVector2Array pref;
	for (int i = 0; i < 600; i++) {
		pos.push_back(Vector2((i % 30) * 0.9, (i / 30) * 0.9));
		vel.push_back(Vector2());
		pref.push_back(Vector2(i % 2 == 0 ? 1.4 : -1.4, 0.0));
	}
	const PackedVector2Array r1 = CgameCrowdAvoidance::compute_velocities(pos, vel, pref, 0.5, max_speed, 5.0, 6.0, 16, 0.1);
	const PackedVector2Array r2 = CgameCrowdAvoidance::compute_velocities(pos, vel, pref, 0.5, max_speed, 5.0, 6.0, 16, 0.1);
	REQUIRE(r1.size() == 600);
	bool identical = true;
	bool bounded = true;
	for (int i = 0; i < 600; i++) {
		identical = identical && r1[i] == r2[i];
		bounded = bounded && Math::is_finite(r1[i].x) && Math::is_finite(r1[i].y) && r1[i].length() <= max_speed + 0.001;
	}
	CHECK(identical);
	CHECK(bounded);
}

TEST_CASE("[CgameCrowdAvoidance] infeasible constraints fall back to the minimum-violation solution") {
	// One agent boxed in by a ring of overlapping neighbours that all stand still.
	PackedVector2Array pos;
	PackedVector2Array vel;
	PackedVector2Array pref;
	pos.push_back(Vector2());
	vel.push_back(Vector2());
	pref.push_back(Vector2(1.0, 0.0));
	for (int k = 0; k < 8; k++) {
		const real_t angle = Math::TAU * k / 8.0;
		pos.push_back(Vector2(Math::cos(angle), Math::sin(angle)) * 0.8);
		vel.push_back(Vector2());
		pref.push_back(Vector2());
	}
	const PackedVector2Array out = CgameCrowdAvoidance::compute_velocities(pos, vel, pref, 0.5, 1.5, 3.0, 10.0, 16, 0.1);
	REQUIRE(out.size() == 9);
	for (int i = 0; i < 9; i++) {
		CHECK(Math::is_finite(out[i].x));
		CHECK(Math::is_finite(out[i].y));
		CHECK(out[i].length() <= 1.5 + 0.001);
	}
}

} // namespace TestCgameCrowdAvoidance
