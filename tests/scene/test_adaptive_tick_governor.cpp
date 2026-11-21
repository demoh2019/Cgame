/**************************************************************************/
/*  test_adaptive_tick_governor.cpp                                              */
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

TEST_FORCE_LINK(test_adaptive_tick_governor)

#include "scene/main/adaptive_tick_governor.h"

namespace TestAdaptiveTickGovernor {

TEST_CASE("[AdaptiveTickGovernor] Bounded samples and nearest-rank telemetry") {
	Ref<AdaptiveTickGovernor> governor;
	governor.instantiate();
	CHECK(governor->snapshot()["sample_count"] == 0);
	for (int i = 0; i < 202; i++) {
		governor->observe_tick(int64_t(i) * 1000, 1);
	}
	CHECK(governor->get_history_count() == 200);
	CHECK(governor->get_total_ticks() == 202);
	const PackedFloat64Array ordered = governor->samples_oldest_first();
	REQUIRE(ordered.size() == 200);
	CHECK(ordered[0] == doctest::Approx(2.0));
	CHECK(ordered[199] == doctest::Approx(201.0));
	CHECK(double(governor->snapshot()["tick_max_ms"]) == doctest::Approx(201.0));
	CHECK(double(governor->snapshot()["tick_p95_ms"]) == doctest::Approx(192.0));
	CHECK(governor->snapshot()["native_backend"] == true);
	governor->reset();
	CHECK(governor->get_history_count() == 0);
	CHECK(governor->get_total_ticks() == 0);
	CHECK(governor->get_budget_units() == 10);
}

TEST_CASE("[AdaptiveTickGovernor] Sustained overload, deadband and gradual recovery") {
	Ref<AdaptiveTickGovernor> governor;
	governor.instantiate();
	governor->observe_tick(-1, 1);
	governor->observe_tick(60000001, 1);
	governor->observe_tick(1000, -1);
	CHECK(governor->get_total_ticks() == 0);

	for (int i = 0; i < 40; i++) {
		governor->observe_tick(60000, 1);
	}
	CHECK(governor->get_budget_units() == 10);
	for (int i = 0; i < 20; i++) {
		governor->observe_tick(60000, 1);
	}
	CHECK(governor->get_budget_units() == 8);
	for (int i = 0; i < 20; i++) {
		governor->observe_tick(38000, 1);
	}
	CHECK(governor->get_budget_units() == 8);
	for (int i = 0; i < 100; i++) {
		governor->observe_tick(10000, 1);
	}
	CHECK(governor->get_budget_units() == 9);
	for (int i = 0; i < 600; i++) {
		governor->observe_tick(60000, 1);
	}
	CHECK(governor->get_budget_units() == 2);
	governor->set_enabled(false);
	CHECK(governor->get_budget_units() == 10);
	for (int i = 0; i < 180; i++) {
		governor->observe_tick(60000, 1);
	}
	CHECK(governor->get_budget_units() == 10);
	governor->set_enabled(true);
	CHECK(governor->get_budget_units() == 10);
}

TEST_CASE("[AdaptiveTickGovernor] Idle resets evidence and configurable CPU budget") {
	Ref<AdaptiveTickGovernor> governor;
	governor.instantiate();
	for (int i = 0; i < 40; i++) {
		governor->observe_tick(60000, 1);
	}
	governor->observe_tick(60000, 0);
	for (int i = 0; i < 20; i++) {
		governor->observe_tick(60000, 1);
	}
	CHECK(governor->get_budget_units() == 10); // 1 of 3 windows, not 3.
	CHECK(governor->get_total_ticks() == 61);
	governor->set_target_tick_ms(25.0);
	governor->set_budget_range(1, 4);
	CHECK(governor->get_budget_units() == 4);
	for (int i = 0; i < 60; i++) {
		governor->observe_tick(30000, 1);
	}
	CHECK(governor->get_budget_units() == 2);
	governor->set_budget_range(2, 2);
	CHECK(governor->get_budget_units() == 2);
	governor->reset();
	CHECK(governor->get_target_tick_ms() == doctest::Approx(25.0));
	CHECK(governor->get_budget_units() == 2);
}
} // namespace TestAdaptiveTickGovernor
