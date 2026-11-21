#pragma once

#include "../frame_update_budget.h"
#include "tests/test_macros.h"

namespace TestFrameUpdateBudget {

TEST_CASE("[FrameUpdateBudget] Lane lifecycle and validation") {
	Ref<FrameUpdateBudget> budget;
	budget.instantiate();
	CHECK(budget->get_lane_count() == 0);
	CHECK(budget->register_lane(StringName("fx")));
	CHECK_FALSE(budget->register_lane(StringName("fx")));
	CHECK_FALSE(budget->register_lane(StringName()));
	CHECK(budget->get_lane_count() == 1);
	CHECK(budget->unregister_lane(StringName("fx")));
	CHECK_FALSE(budget->unregister_lane(StringName("fx")));
	CHECK(budget->get_lane_count() == 0);
}

TEST_CASE("[FrameUpdateBudget] Quality, pressure and bounded updates") {
	Ref<FrameUpdateBudget> budget;
	budget.instantiate();
	CHECK(budget->register_lane(StringName("a")));
	CHECK(budget->register_lane(StringName("b")));
	budget->begin_frame(1.0 / 60.0, 0);
	CHECK(budget->consume(StringName("a"), 1.0 / 60.0) > 0.0);
	CHECK(budget->consume(StringName("b"), 1.0 / 60.0) > 0.0);
	budget->begin_frame(1.0 / 60.0, 0);
	CHECK(budget->consume(StringName("a"), 1.0 / 60.0) == 0.0);
	CHECK(budget->consume(StringName("b"), 1.0 / 60.0) == 0.0);
	CHECK(budget->consume(StringName("absent"), 0.1) == 0.0);
	CHECK(budget->consume(StringName("a"), Math_INF) == 0.0);
	for (int i = 0; i < 12; i++) {
		budget->begin_frame(0.05, 3);
		budget->consume(StringName("a"), 0.05);
		budget->consume(StringName("b"), 0.05);
	}
	CHECK(budget->pressure_percent() >= 40.0);
	CHECK(budget->current_budget() == 1);
	CHECK(budget->consume(StringName("a"), 1.0, true) <= 0.16);
	budget->reset();
	CHECK(budget->pressure_percent() == 0.0);
	CHECK(budget->get_lane_count() == 2);
}

TEST_CASE("[FrameUpdateBudget] Profile changes are atomic") {
	Ref<FrameUpdateBudget> budget;
	budget.instantiate();
	PackedFloat64Array rates;
	PackedInt32Array slots;
	for (int i = 0; i < 4; i++) {
		rates.push_back(10.0 + i * 10.0);
		slots.push_back(i + 1);
	}
	CHECK(budget->configure(rates, slots));
	rates.set(2, 0.0);
	CHECK_FALSE(budget->configure(rates, slots));
	CHECK(budget->register_lane(StringName("vfx")));
	budget->begin_frame(0.01, 3);
	CHECK(budget->consume(StringName("vfx"), 0.01) > 0.0);
}

} // namespace TestFrameUpdateBudget
