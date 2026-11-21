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
	CHECK(lod->get_interval(INF, 30.0, 60.0) == real_t(1.0));
}

TEST_CASE("[AISimulationLOD2D] Urgent work is never deferred by LOD") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->get_interval(10000.0, 30.0, 60.0, true) == real_t(0.25));
	CHECK(lod->get_staggered_interval(42, INF, 30.0, 60.0, true) == real_t(0.25));
	CHECK(lod->get_staggered_interval(42, 10.0, 30.0, 60.0) == real_t(0.25));
}

TEST_CASE("[AISimulationLOD2D] Stable spread staggers passive agents without randomness") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->get_staggered_interval(0, INF, 30.0, 60.0) == real_t(0.0625));
	CHECK(lod->get_staggered_interval(15, INF, 30.0, 60.0) == real_t(1.0));
	CHECK(lod->get_staggered_interval(16, INF, 30.0, 60.0) == real_t(0.0625));
	CHECK(lod->get_staggered_interval(1, 40.0, 30.0, 60.0) == real_t(0.0625));
	CHECK(lod->get_staggered_interval(1, 40.0, 30.0, 60.0) == lod->get_staggered_interval(17, 40.0, 30.0, 60.0));
}

TEST_CASE("[AISimulationLOD2D] Invalid spatial input fails conservatively fast") {
	Ref<AISimulationLOD2D> lod;
	lod.instantiate();
	CHECK(lod->get_interval(-1.0, 30.0, 60.0) == real_t(0.25));
	CHECK(lod->get_interval(-INF, 30.0, 60.0) == real_t(0.25));
	CHECK(lod->get_interval(NaN, 30.0, 60.0) == real_t(0.25));
	CHECK(lod->get_interval(70.0, 30.0, 30.0) == real_t(0.25));
	CHECK(lod->get_interval(70.0, NaN, 60.0) == real_t(0.25));
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
	CHECK_FALSE(lod->configure_intervals(NaN, 0.2, 0.8));
	ERR_PRINT_ON;
	CHECK(lod->get_near_interval() == real_t(0.1));
	CHECK(lod->get_medium_interval() == real_t(0.2));
	CHECK(lod->get_far_interval() == real_t(0.8));
}

} // namespace TestAISimulationLOD2D
