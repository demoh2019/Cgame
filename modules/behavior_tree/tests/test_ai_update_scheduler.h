/**************************************************************************/
/*  test_ai_update_scheduler.h                                                  */
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

#include "../ai_update_scheduler.h"
#include "tests/test_macros.h"

namespace TestAIUpdateScheduler {

TEST_CASE("[AIUpdateScheduler] Default four-slot assignment is stable across instances") {
	Ref<AIUpdateScheduler> first;
	first.instantiate();
	Ref<AIUpdateScheduler> second;
	second.instantiate();
	CHECK(first->get_slots_per_cycle() == 4);
	for (int64_t id = -20; id <= 200; ++id) {
		const int slot = first->get_agent_slot(id);
		CHECK(slot >= 0);
		CHECK(slot < 4);
		CHECK(slot == second->get_agent_slot(id));
	}
}

TEST_CASE("[AIUpdateScheduler] Every agent is admitted exactly once per cycle") {
	Ref<AIUpdateScheduler> scheduler;
	scheduler.instantiate();
	scheduler->set_slots_per_cycle(7);
	for (int64_t id = 1; id < 150; ++id) {
		int admissions = 0;
		for (int64_t tick = 0; tick < 7; ++tick) {
			admissions += scheduler->is_due(id, tick) ? 1 : 0;
		}
		CHECK(admissions == 1);
		for (int64_t tick = 7; tick < 14; ++tick) {
			CHECK(scheduler->is_due(id, tick) == scheduler->is_due(id, tick - 7));
		}
	}
}

TEST_CASE("[AIUpdateScheduler] Hash distributes a crowd across available slots") {
	Ref<AIUpdateScheduler> scheduler;
	scheduler.instantiate();
	int counts[4] = { 0, 0, 0, 0 };
	for (int64_t id = 10000; id < 10256; ++id) {
		counts[scheduler->get_agent_slot(id)]++;
	}
	for (int i = 0; i < 4; ++i) {
		// This is a distribution sanity check, not an exact quota claim.
		CHECK(counts[i] >= 40);
		CHECK(counts[i] <= 90);
	}
}

TEST_CASE("[AIUpdateScheduler] Urgent decisions bypass slots, but not invalid ticks") {
	Ref<AIUpdateScheduler> scheduler;
	scheduler.instantiate();
	for (int64_t id = 0; id < 10; ++id) {
		for (int64_t tick = 0; tick < 8; ++tick) {
			CHECK(scheduler->is_due(id, tick, true));
		}
	}
	CHECK_FALSE(scheduler->is_due(42, -1, true));
	CHECK_FALSE(scheduler->is_due(42, -1));
	CHECK(scheduler->ticks_until_due(42, -1) == -1);
}

TEST_CASE("[AIUpdateScheduler] Next due tick agrees with current modulo slot") {
	Ref<AIUpdateScheduler> scheduler;
	scheduler.instantiate();
	scheduler->set_slots_per_cycle(9);
	for (int64_t id = -15; id < 15; ++id) {
		for (int64_t tick = 0; tick < 25; ++tick) {
			const int wait = scheduler->ticks_until_due(id, tick);
			CHECK(wait >= 0);
			CHECK(wait < 9);
			CHECK(scheduler->is_due(id, tick + wait));
			if (wait > 0) {
				CHECK_FALSE(scheduler->is_due(id, tick));
			}
		}
	}
}

TEST_CASE("[AIUpdateScheduler] One slot does not delay AI decisions") {
	Ref<AIUpdateScheduler> scheduler;
	scheduler.instantiate();
	scheduler->set_slots_per_cycle(1);
	for (int64_t id = -5; id < 5; ++id) {
		CHECK(scheduler->get_agent_slot(id) == 0);
		for (int64_t tick = 0; tick < 10; ++tick) {
			CHECK(scheduler->is_due(id, tick));
			CHECK(scheduler->ticks_until_due(id, tick) == 0);
		}
	}
}

TEST_CASE("[AIUpdateScheduler] Invalid slot counts preserve the previous configuration") {
	Ref<AIUpdateScheduler> scheduler;
	scheduler.instantiate();
	scheduler->set_slots_per_cycle(64);
	CHECK(scheduler->get_slots_per_cycle() == 64);
	ERR_PRINT_OFF;
	scheduler->set_slots_per_cycle(0);
	scheduler->set_slots_per_cycle(65);
	ERR_PRINT_ON;
	CHECK(scheduler->get_slots_per_cycle() == 64);
	CHECK(scheduler->get_agent_slot(9223372036854775807LL) >= 0);
	CHECK(scheduler->is_due(9223372036854775807LL, 9223372036854775807LL) ==
			(scheduler->ticks_until_due(9223372036854775807LL, 9223372036854775807LL) == 0));
}

} // namespace TestAIUpdateScheduler
