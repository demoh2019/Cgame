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

TEST_CASE("[FrameUpdateBudget] Cost estimates converge and importance is validated") {
	Ref<FrameUpdateBudget> b;
	b.instantiate();
	CHECK(b->register_lane("expensive"));
	CHECK(b->register_lane("cheap"));
	CHECK_FALSE(b->set_lane_importance("missing", 1.0));
	CHECK_FALSE(b->set_lane_importance("expensive", 0.0));
	CHECK_FALSE(b->set_lane_importance("expensive", 4.01));
	CHECK_FALSE(b->set_lane_importance("expensive", std::numeric_limits<double>::infinity()));
	CHECK(b->set_lane_importance("expensive", 0.25));
	CHECK(b->set_lane_importance("cheap", 4.0));
	CHECK(b->get_lane_importance("expensive") == 0.25);
	CHECK(b->get_lane_importance("cheap") == 4.0);
	CHECK(b->get_lane_importance("missing") < 0.0);
	CHECK(b->get_lane_estimated_cost_us("expensive") == 0);
	CHECK(b->get_lane_estimated_cost_us("missing") < 0);
	CHECK(b->record_cost("expensive", 800));
	CHECK(b->get_lane_estimated_cost_us("expensive") == 800);
	CHECK(b->record_cost("expensive", 400));
	CHECK(b->get_lane_estimated_cost_us("expensive") == 700);
	CHECK(b->record_cost("expensive", 0));
	CHECK(b->get_lane_estimated_cost_us("expensive") == 700);
	b->reset();
	CHECK(b->get_lane_importance("cheap") == 4.0);
	CHECK(b->get_lane_estimated_cost_us("expensive") == 700);
}

TEST_CASE("[FrameUpdateBudget] Learned costs reserve affordable lanes first") {
	Ref<FrameUpdateBudget> b;
	b.instantiate();
	CHECK(b->register_lane("heavy"));
	CHECK(b->register_lane("light"));
	CHECK(b->set_frame_time_budget_us(500));
	CHECK(b->set_lane_importance("heavy", 0.25));
	CHECK(b->set_lane_importance("light", 4.0));
	b->begin_frame(0.01, 0);
	CHECK(b->consume("heavy", 0.01) > 0.0);
	CHECK(b->consume("light", 0.01) > 0.0);
	CHECK(b->record_cost("heavy", 1500));
	CHECK(b->record_cost("light", 100));
	b->begin_frame(0.1, 0);
	CHECK(b->get_reserved_estimated_cost_us() == 100);
	CHECK(b->consume("heavy", 0.1) == 0.0);
	CHECK(b->consume("light", 0.1) > 0.0);
	CHECK(b->record_cost("light", 100));

	int heavy_updates = 0;
	for (int frame = 0; frame < 120; frame++) {
		b->begin_frame(0.1, 0);
		if (b->consume("heavy", 0.1) > 0.0) {
			heavy_updates++;
			CHECK(b->record_cost("heavy", 1500));
		}
		if (b->consume("light", 0.1) > 0.0) {
			CHECK(b->record_cost("light", 100));
		}
	}
	CHECK(heavy_updates >= 1); // Expensive lanes cannot starve permanently.
	CHECK(b->get_lane_estimated_cost_us("heavy") == 1500);
}


TEST_CASE("[FrameUpdateBudget] Lane rates reject invalid values and preserve importance") {
	Ref<FrameUpdateBudget> b;
	b.instantiate();
	CHECK(b->register_lane(StringName("visible")));
	CHECK(b->get_lane_rate_scale(StringName("visible")) == 1.0);
	CHECK(b->set_lane_importance(StringName("visible"), 3.0));
	CHECK(b->set_lane_rate_scale(StringName("visible"), 1.5));
	CHECK(b->get_lane_importance(StringName("visible")) == 3.0);
	CHECK(b->get_lane_rate_scale(StringName("visible")) == 1.5);
	CHECK_FALSE(b->set_lane_rate_scale(StringName("visible"), 0.5));
	CHECK_FALSE(b->set_lane_rate_scale(StringName("visible"), 2.1));
	CHECK_FALSE(b->set_lane_rate_scale(StringName("visible"), std::numeric_limits<double>::infinity()));
	CHECK_FALSE(b->set_lane_rate_scale(StringName("visible"), std::numeric_limits<double>::quiet_NaN()));
	CHECK_FALSE(b->set_lane_rate_scale(StringName("missing"), 1.0));
	CHECK(b->get_lane_rate_scale(StringName("missing")) == -1.0);
	CHECK(b->get_lane_rate_scale(StringName("visible")) == 1.5);
	b->reset();
	CHECK(b->get_lane_rate_scale(StringName("visible")) == 1.5);
	CHECK(b->unregister_lane(StringName("visible")));
	CHECK(b->get_lane_rate_scale(StringName("visible")) == -1.0);
}

TEST_CASE("[FrameUpdateBudget] Faster lanes tick more frequently with bounded CPU slots") {
	Ref<FrameUpdateBudget> b;
	b.instantiate();
	CHECK(b->register_lane(StringName("visible")));
	CHECK(b->register_lane(StringName("hidden")));
	CHECK(b->set_lane_rate_scale(StringName("visible"), 1.5));
	CHECK(b->set_lane_rate_scale(StringName("hidden"), 0.75));
	b->begin_frame(1.0 / 60.0, 0);
	CHECK(b->consume(StringName("visible"), 1.0 / 60.0) > 0.0);
	CHECK(b->consume(StringName("hidden"), 1.0 / 60.0) > 0.0);
	int visible_updates = 0;
	int hidden_updates = 0;
	for (int frame = 0; frame < 240; frame++) {
		b->begin_frame(1.0 / 60.0, 0);
		// Fixed call order puts the less relevant system first.
		if (b->consume(StringName("hidden"), 1.0 / 60.0) > 0.0) {
			hidden_updates++;
		}
		if (b->consume(StringName("visible"), 1.0 / 60.0) > 0.0) {
			visible_updates++;
		}
		CHECK(b->last_frame_counts().x <= 1); // One low-quality update per frame.
	}
	CHECK(visible_updates > hidden_updates);
	CHECK(visible_updates >= 50);
	CHECK(hidden_updates >= 25); // Even de-prioritized lanes make progress.
}

TEST_CASE("[FrameUpdateBudget] Paused lanes skip budget, preserve cost, and resume without debt") {
	Ref<FrameUpdateBudget> b;
	b.instantiate();
	CHECK(b->register_lane("ambient"));
	CHECK(b->register_lane("other"));
	CHECK(b->is_lane_enabled("ambient"));
	CHECK_FALSE(b->is_lane_enabled("missing"));
	CHECK_FALSE(b->set_lane_enabled("missing", false));
	CHECK(b->record_cost("ambient", 300));
	CHECK(b->set_lane_enabled("ambient", false));
	CHECK(b->set_lane_enabled("ambient", false)); // Idempotence.
	CHECK_FALSE(b->is_lane_enabled("ambient"));
	b->begin_frame(0.1, 0);
	CHECK(b->consume("ambient", 0.1) == 0.0); // Even a quality refresh cannot run it.
	CHECK(b->consume("other", 0.1) > 0.0);
	CHECK(b->consume("ambient", 0.1, true) > 0.0); // Cleanup is allowed.
	for (int frame = 0; frame < 120; frame++) {
		b->begin_frame(0.1, 0);
		CHECK(b->consume("ambient", 0.1) == 0.0);
		CHECK(b->consume("other", 0.1) > 0.0);
		CHECK(b->last_frame_counts().x == 1);
	}
	CHECK(b->get_lane_estimated_cost_us("ambient") == 300);
	b->reset();
	CHECK_FALSE(b->is_lane_enabled("ambient")); // Reset retains configuration.
	CHECK(b->set_lane_enabled("ambient", true));
	CHECK(b->set_lane_enabled("other", false)); // Keep one eligible lane for the resume assertion.
	b->begin_frame(0.01, 0);
	CHECK(b->consume("ambient", 0.01) > 0.0); // Reset quality refresh.
	b->begin_frame(0.01, 0);
	CHECK(b->consume("ambient", 0.01) == 0.0); // No 120-frame debt.
	b->begin_frame(0.1, 0);
	CHECK(b->consume("ambient", 0.1) > 0.0);
	CHECK(b->get_lane_estimated_cost_us("ambient") == 300);
}

} // namespace TestFrameUpdateBudget
