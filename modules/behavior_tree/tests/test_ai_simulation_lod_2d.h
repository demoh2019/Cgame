/**************************************************************************/
/*  test_ai_simulation_lod_2d.h                                                  */
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

#include "../ai_simulation_lod_2d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestAISimulationLOD2D {

TEST_CASE("[AISimulationLOD2D] Three simulation tiers and inclusive thresholds") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->get_near_interval() == real_t(0.25));
	CHECK(lod->get_medium_interval() == real_t(0.5));
	CHECK(lod->get_far_interval() == real_t(1.0));
	CHECK(lod->get_interval(0.0, 30.0, 60.0) == real_t(0.25));
	CHECK(lod->get_interval(30.0, 30.0, 60.0) == real_t(0.25));
	CHECK(lod->get_interval(30.1, 30.0, 60.0) == real_t(0.5));
	CHECK(lod->get_interval(60.0, 30.0, 60.0) == real_t(0.5));
	CHECK(lod->get_interval(60.1, 30.0, 60.0) == real_t(1.0));
	CHECK(lod->get_interval(Math::INF, 30.0, 60.0) == real_t(1.0));
}

TEST_CASE("[AISimulationLOD2D] Urgent work is never deferred by LOD") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->get_interval(10000.0, 30.0, 60.0, true) == real_t(0.25));
	CHECK(lod->get_staggered_interval(42, Math::INF, 30.0, 60.0, true) == real_t(0.25));
	CHECK(lod->get_staggered_interval(42, 10.0, 30.0, 60.0) == real_t(0.25));
}

TEST_CASE("[AISimulationLOD2D] Stable spread staggers passive agents without randomness") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->get_staggered_interval(0, Math::INF, 30.0, 60.0) == real_t(0.0625));
	CHECK(lod->get_staggered_interval(15, Math::INF, 30.0, 60.0) == real_t(1.0));
	CHECK(lod->get_staggered_interval(16, Math::INF, 30.0, 60.0) == real_t(0.0625));
	CHECK(lod->get_staggered_interval(1, 40.0, 30.0, 60.0) == real_t(0.0625));
	CHECK(lod->get_staggered_interval(1, 40.0, 30.0, 60.0) == lod->get_staggered_interval(17, 40.0, 30.0, 60.0));
}

TEST_CASE("[AISimulationLOD2D] Invalid spatial input fails conservatively fast") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->get_interval(-1.0, 30.0, 60.0) == real_t(0.25));
	CHECK(lod->get_interval(-Math::INF, 30.0, 60.0) == real_t(0.25));
	CHECK(lod->get_interval(Math::NaN, 30.0, 60.0) == real_t(0.25));
	CHECK(lod->get_interval(70.0, 30.0, 30.0) == real_t(0.25));
	CHECK(lod->get_interval(70.0, Math::NaN, 60.0) == real_t(0.25));
	CHECK(lod->get_staggered_interval(-1, 70.0, 30.0, 60.0) == real_t(0.25));
}

TEST_CASE("[AISimulationLOD2D] Atomic interval configuration and rollback") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->configure_intervals(0.1, 0.2, 0.8));
	CHECK(lod->get_interval(100.0, 30.0, 60.0) == real_t(0.8));
	ERR_PRINT_OFF;
	CHECK_FALSE(lod->configure_intervals(0.0, 0.2, 0.8));
	CHECK_FALSE(lod->configure_intervals(0.3, 0.2, 0.8));
	CHECK_FALSE(lod->configure_intervals(0.1, 1.0, 0.8));
	CHECK_FALSE(lod->configure_intervals(0.1, 0.2, 2.01));
	CHECK_FALSE(lod->configure_intervals(Math::NaN, 0.2, 0.8));
	ERR_PRINT_ON;
	CHECK(lod->get_near_interval() == real_t(0.1));
	CHECK(lod->get_medium_interval() == real_t(0.2));
	CHECK(lod->get_far_interval() == real_t(0.8));
}

TEST_CASE("[AISimulationLOD2D] Hysteresis holds medium/far bands but restores near immediately") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	// A passive observer moving 1m across a boundary does not flip its scan
	// frequency. Meaningful movement beyond the hysteresis margin does.
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, 0.5, 4.0) == real_t(0.5));
	CHECK(lod->get_hysteretic_interval(65.0, 30.0, 60.0, 0.5, 4.0) == real_t(1.0));
	CHECK(lod->get_hysteretic_interval(59.0, 30.0, 60.0, 1.0, 4.0) == real_t(1.0));
	CHECK(lod->get_hysteretic_interval(55.0, 30.0, 60.0, 1.0, 4.0) == real_t(0.5));
	// Near is asymmetric: moving away may retain fast scanning briefly;
	// moving into the leash must never retain a slow scan.
	CHECK(lod->get_hysteretic_interval(33.0, 30.0, 60.0, 0.25, 4.0) == real_t(0.25));
	CHECK(lod->get_hysteretic_interval(35.0, 30.0, 60.0, 0.25, 4.0) == real_t(0.5));
	CHECK(lod->get_hysteretic_interval(30.0, 30.0, 60.0, 1.0, 4.0) == real_t(0.25));
	CHECK(lod->get_hysteretic_interval(20.0, 30.0, 60.0, 0.5, 4.0) == real_t(0.25));
	CHECK(lod->get_hysteretic_interval(1000.0, 30.0, 60.0, 1.0, 4.0, true) == real_t(0.25));
	CHECK(lod->get_hysteretic_interval(Math::INF, 30.0, 60.0, 0.5, 4.0) == real_t(1.0));
}

TEST_CASE("[AISimulationLOD2D] Hysteresis fails safe on invalid input and after reconfiguration") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, 0.5, 0.0) == real_t(1.0));
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, 0.123, 4.0) == real_t(1.0));
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, Math::NaN, 4.0) == real_t(1.0));
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, 0.5, Math::NaN) == real_t(1.0));
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, 0.5, -1.0) == real_t(1.0));
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, 0.5, 16.0) == real_t(1.0));
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 30.0, 0.5, 4.0) == real_t(0.25));
	CHECK(lod->get_hysteretic_interval(-Math::INF, 30.0, 60.0, 0.5, 4.0) == real_t(0.25));
	CHECK(lod->get_hysteretic_interval(Math::NaN, 30.0, 60.0, 0.5, 4.0) == real_t(0.25));
	CHECK(lod->configure_intervals(0.1, 0.3, 0.8));
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, 0.3, 4.0) == real_t(0.3));
	CHECK(lod->get_hysteretic_interval(62.0, 30.0, 60.0, 0.5, 4.0) == real_t(0.8));
}


TEST_CASE("[AISimulationLOD2D] combined passive scan plan matches scalar LOD at all tiers") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	const real_t near_distance = 30.0;
	const real_t far_distance = 54.0;
	const real_t hysteresis = 4.0;
	const real_t distances[] = { 0.0, 20.0, 30.0, 30.1, 33.0, 35.0,
		50.0, 54.0, 55.0, 57.0, 60.0, 100.0, real_t(Math::INF),
		-real_t(Math::INF), real_t(Math::NaN), -1.0 };
	const real_t previous[] = { 0.0, 0.25, 0.5, 1.0 };
	for (const real_t distance : distances) {
		for (const real_t last : previous) {
			for (int64_t id : { int64_t(0), int64_t(1), int64_t(15), int64_t(16), int64_t(-1) }) {
				for (bool staggered : { false, true }) {
					for (bool urgent : { false, true }) {
						const Vector2 plan = lod->plan_passive_scan(id, distance,
								near_distance, far_distance, last, hysteresis,
								staggered, urgent);
						const bool first_distant = !staggered && distance > near_distance && !urgent;
						const real_t expected_nominal = first_distant ?
								lod->get_interval(distance, near_distance, far_distance, urgent) :
								lod->get_hysteretic_interval(distance, near_distance,
										far_distance, last, hysteresis, urgent);
						const real_t expected_delay = first_distant ?
								lod->get_staggered_interval(id, distance,
										near_distance, far_distance, false) : expected_nominal;
						CHECK(plan.x == expected_nominal);
						CHECK(plan.y == expected_delay);
						CHECK(plan.x > 0.0);
						CHECK(plan.y > 0.0);
					}
				}
			}
		}
	}
}

TEST_CASE("[AISimulationLOD2D] combined planning honors urgent scans and configured intervals") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->configure_intervals(0.1, 0.3, 0.8));
	const Vector2 first = lod->plan_passive_scan(160, 100.0, 30.0, 54.0,
			0.0, 4.0, false);
	CHECK(first.x == real_t(0.8));
	CHECK(first.y == real_t(0.8 / 16.0));
	const Vector2 repeated = lod->plan_passive_scan(160, 100.0, 30.0, 54.0,
			first.x, 4.0, true);
	CHECK(repeated.x == real_t(0.8));
	CHECK(repeated.y == real_t(0.8));
	const Vector2 near = lod->plan_passive_scan(160, 30.0, 30.0, 54.0,
			first.x, 4.0, true);
	CHECK(near.x == real_t(0.1));
	CHECK(near.y == real_t(0.1));
	const Vector2 urgent = lod->plan_passive_scan(160, 100.0, 30.0, 54.0,
			first.x, 4.0, false, true);
	CHECK(urgent.x == real_t(0.1));
	CHECK(urgent.y == real_t(0.1));
}

} // namespace TestAISimulationLOD2D
