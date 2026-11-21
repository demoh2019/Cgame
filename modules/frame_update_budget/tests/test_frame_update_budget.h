#pragma once

#include "../frame_update_budget.h"
#include "tests/test_macros.h"

#include <limits>

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
	CHECK(budget->consume(StringName("a"), std::numeric_limits<double>::infinity()) == 0.0);
	for (int i = 0; i < 12; i++) {
		budget->begin_frame(0.05, 3);
		budget->consume(StringName("a"), 0.05);
		budget->consume(StringName("b"), 0.05);
	}
	CHECK(budget->pressure_percent() >= 40.0);
	CHECK(budget->current_budget() == 2); // Two lanes cap the effective slots.
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


TEST_CASE("[FrameUpdateBudget] Oldest-due reservations prevent lane starvation") {
	Ref<FrameUpdateBudget> b;
	b.instantiate();
	const StringName lanes[] = { StringName("dragonflies"), StringName("dust_devils"), StringName("tumbleweeds"), StringName("dusk_bats") };
	for (int i = 0; i < 4; i++) {
		CHECK(b->register_lane(lanes[i]));
	}
	int counts[4] = { 0, 0, 0, 0 };
	// Begin with an immediate profile refresh for all lanes, like the game.
	b->begin_frame(1.0 / 60.0, 0);
	for (int i = 0; i < 4; i++) {
		CHECK(b->consume(lanes[i], 1.0 / 60.0) > 0.0);
	}
	const int call_order[] = { 1, 0, 2, 3 }; // Gameplay invokes dust devils first.
	for (int frame = 0; frame < 240; frame++) {
		b->begin_frame(1.0 / 60.0, 0);
		for (int i = 0; i < 4; i++) {
			const int lane = call_order[i];
			if (b->consume(lanes[lane], 1.0 / 60.0) > 0.0) {
				counts[lane]++;
			}
		}
		CHECK(b->last_frame_counts().x <= 1); // Low-tier CPU cap.
	}
	int min_count = counts[0];
	int max_count = counts[0];
	for (int i = 0; i < 4; i++) {
		CHECK(counts[i] >= 40); // At most one update per lane per ~5 frames.
		min_count = MIN(min_count, counts[i]);
		max_count = MAX(max_count, counts[i]);
	}
	CHECK(max_count - min_count <= 2); // No lane wins by registration/call order.
}

TEST_CASE("[FrameUpdateBudget] Reserved slots are single-use and force refresh bypasses them") {
	Ref<FrameUpdateBudget> b;
	b.instantiate();
	CHECK(b->register_lane("first"));
	CHECK(b->register_lane("second"));
	b->begin_frame(0.01, 0); // Initial quality change allows both.
	CHECK(b->consume("first", 0.01) > 0.0);
	CHECK(b->consume("second", 0.01) > 0.0);
	b->begin_frame(0.1, 0); // Only one regular lane is allowed.
	int regular = 0;
	if (b->consume("first", 0.1) > 0.0) {
		regular++;
	}
	if (b->consume("first", 0.1) > 0.0) {
		regular++; // A second call must not reuse the first reservation.
	}
	if (b->consume("second", 0.1) > 0.0) {
		regular++;
	}
	CHECK(regular == 1);
	CHECK(b->consume("second", 0.1, true) > 0.0);
	CHECK(b->last_frame_counts().x == 2);
}

TEST_CASE("[FrameUpdateBudget] Recorded CPU microseconds bound optional work") {
	Ref<FrameUpdateBudget> b;
	b.instantiate();
	CHECK(b->register_lane(StringName("first")));
	CHECK(b->register_lane(StringName("second")));
	CHECK(b->get_frame_time_budget_us() == 2500);
	CHECK(b->set_frame_time_budget_us(250));
	CHECK_FALSE(b->set_frame_time_budget_us(-1));
	CHECK_FALSE(b->set_frame_time_budget_us(1000001));
	CHECK(b->get_frame_time_budget_us() == 250);
	CHECK_FALSE(b->record_cost(StringName("unregistered"), 100));
	CHECK_FALSE(b->record_cost(StringName("first"), -1));
	CHECK_FALSE(b->record_cost(StringName("first"), 10000001));

	b->begin_frame(0.01, 3);
	CHECK(b->consume(StringName("first"), 0.01) > 0.0);
	CHECK(b->consume(StringName("second"), 0.01) > 0.0);
	CHECK(b->record_cost(StringName("first"), 350));
	CHECK(b->current_frame_cost_us() == 350);
	b->begin_frame(0.1, 3);
	CHECK(b->last_frame_cost_us() == 350);
	CHECK(b->current_frame_cost_us() == 0);
	CHECK(b->consume(StringName("first"), 0.1) > 0.0);
	CHECK(b->record_cost(StringName("first"), 300));
	CHECK(b->consume(StringName("second"), 0.1) == 0.0);
	// Scene visibility transitions may still force a refresh when over budget.
	CHECK(b->consume(StringName("second"), 0.1, true) > 0.0);

	CHECK(b->set_frame_time_budget_us(0));
	b->begin_frame(0.1, 3);
	CHECK(b->record_cost(StringName("first"), 10000));
	CHECK(b->consume(StringName("second"), 0.1) > 0.0);
	b->reset();
	CHECK(b->current_frame_cost_us() == 0);
	CHECK(b->last_frame_cost_us() == 0);
	CHECK(b->get_frame_time_budget_us() == 0);
}

} // namespace TestFrameUpdateBudget
