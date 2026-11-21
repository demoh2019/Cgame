/**************************************************************************/
/*  test_ai_execution_profiler.h                                                  */
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

#include "../ai_execution_profiler.h"
#include "../behavior_tree.h"
#include "tests/test_macros.h"

namespace TestAIExecutionProfiler {

TEST_CASE("[AIExecutionProfiler] Disabled by default and rejects recording") {
	Ref<AIExecutionProfiler> profile;
	profile.instantiate();
	CHECK_FALSE(profile->is_enabled());
	CHECK(profile->get_budget_usec() == 2000);
	CHECK_FALSE(profile->record_sample(SNAME("decision"), 500));
	CHECK_FALSE(profile->begin_sample(SNAME("decision")));
	CHECK(profile->end_sample(SNAME("decision")) == -1);
	Dictionary snap = profile->get_snapshot();
	CHECK(snap["total_samples"] == 0);
	CHECK(Dictionary(snap["categories"]).is_empty());
}

TEST_CASE("[AIExecutionProfiler] Records independent named category statistics") {
	Ref<AIExecutionProfiler> profile;
	profile.instantiate();
	profile->set_enabled(true);
	CHECK(profile->record_sample(SNAME("decision"), 100));
	CHECK(profile->record_sample(SNAME("decision"), 200));
	CHECK(profile->record_sample(SNAME("vision"), 50));
	Dictionary all = profile->get_snapshot();
	CHECK(all["total_samples"] == 3);
	Dictionary categories = all["categories"];
	Dictionary decision = categories[SNAME("decision")];
	Dictionary vision = categories[SNAME("vision")];
	CHECK(decision["count"] == 2);
	CHECK(decision["total_usec"] == 300);
	CHECK(decision["min_usec"] == 100);
	CHECK(decision["max_usec"] == 200);
	CHECK(decision["last_usec"] == 200);
	CHECK(decision["mean_usec"] == 150.0);
	CHECK(vision["count"] == 1);
	CHECK(vision["last_usec"] == 50);
}

TEST_CASE("[AIExecutionProfiler] Budget counts slow samples without losing timings") {
	Ref<AIExecutionProfiler> profile;
	profile.instantiate();
	profile->set_enabled(true);
	profile->set_budget_usec(150);
	CHECK(profile->record_sample(SNAME("ai"), 150));
	CHECK(profile->record_sample(SNAME("ai"), 151));
	CHECK(profile->record_sample(SNAME("ai"), 300));
	Dictionary snap = profile->get_snapshot();
	Dictionary categories = snap["categories"];
	Dictionary entry = categories[SNAME("ai")];
	CHECK(entry["count"] == 3);
	CHECK(entry["over_budget"] == 2);
	CHECK(entry["max_usec"] == 300);
}

TEST_CASE("[AIExecutionProfiler] Manual spans use monotonic elapsed time") {
	Ref<AIExecutionProfiler> profile;
	profile.instantiate();
	profile->set_enabled(true);
	CHECK(profile->begin_sample(SNAME("navigation")));
	ERR_PRINT_OFF;
	CHECK_FALSE(profile->begin_sample(SNAME("navigation")));
	ERR_PRINT_ON;
	CHECK(profile->end_sample(SNAME("navigation")) >= 0);
	CHECK(profile->end_sample(SNAME("navigation")) == -1);
	Dictionary snap = profile->get_snapshot();
	Dictionary categories = snap["categories"];
	Dictionary entry = categories[SNAME("navigation")];
	CHECK(entry["count"] == 1);
	CHECK(int64_t(entry["last_usec"]) >= 0);
}

TEST_CASE("[AIExecutionProfiler] Snapshot isolation and reset preserve settings") {
	Ref<AIExecutionProfiler> profile;
	profile.instantiate();
	profile->set_enabled(true);
	profile->set_budget_usec(500);
	CHECK(profile->record_sample(SNAME("brain"), 200));
	Dictionary old = profile->get_snapshot();
	Dictionary rows = old["categories"];
	Dictionary brain = rows[SNAME("brain")];
	brain["count"] = 777;
	Dictionary current = profile->get_snapshot();
	Dictionary current_categories = current["categories"];
	Dictionary current_brain = current_categories[SNAME("brain")];
	CHECK(current_brain["count"] == 1);
	profile->reset();
	Dictionary reset = profile->get_snapshot();
	CHECK(reset["total_samples"] == 0);
	CHECK(Dictionary(reset["categories"]).is_empty());
	CHECK(profile->is_enabled());
	CHECK(profile->get_budget_usec() == 500);
}

TEST_CASE("[AIExecutionProfiler] Invalid category and duration fail safely") {
	Ref<AIExecutionProfiler> profile;
	profile.instantiate();
	profile->set_enabled(true);
	CHECK_FALSE(profile->record_sample(StringName(), 100));
	ERR_PRINT_OFF;
	CHECK_FALSE(profile->record_sample(SNAME("ai"), -1));
	CHECK_FALSE(profile->record_sample(SNAME("ai"), 1000000000001LL));
	profile->set_budget_usec(0);
	ERR_PRINT_ON;
	CHECK(profile->get_budget_usec() == 2000);
	CHECK(profile->get_snapshot()["total_samples"] == 0);
}

TEST_CASE("[AIExecutionProfiler] Bounded categories and disabled span reset") {
	Ref<AIExecutionProfiler> profile;
	profile.instantiate();
	profile->set_enabled(true);
	for (int i = 0; i < 32; ++i) {
		CHECK(profile->record_sample(StringName(String("phase_") + itos(i)), 1));
	}
	ERR_PRINT_OFF;
	CHECK_FALSE(profile->record_sample(SNAME("phase_32"), 1));
	ERR_PRINT_ON;
	CHECK(profile->get_snapshot()["total_samples"] == 32);
	CHECK(profile->begin_sample(SNAME("phase_0")));
	profile->set_enabled(false);
	CHECK(profile->end_sample(SNAME("phase_0")) == -1);
	profile->set_enabled(true);
	CHECK(profile->end_sample(SNAME("phase_0")) == -1);
}

TEST_CASE("[BehaviorTreeRunner] Opt-in profiling records decision ticks only") {
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	Ref<BehaviorTreeWait> task;
	task.instantiate();
	task->set_duration(0.4);
	runner->set_root_task(task);
	CHECK_FALSE(runner->is_profiling_enabled());
	CHECK(runner->tick(0.1) == BehaviorTreeTask::RUNNING);
	CHECK(runner->get_profile_snapshot()["total_samples"] == 0);
	runner->set_profiling_enabled(true);
	CHECK(runner->tick(0.1) == BehaviorTreeTask::RUNNING);
	CHECK(runner->tick(0.2) == BehaviorTreeTask::SUCCESS);
	Dictionary snap = runner->get_profile_snapshot();
	CHECK(snap["total_samples"] == 2);
	Dictionary categories = snap["categories"];
	Dictionary row = categories[SNAME("behavior_tree")];
	CHECK(row["count"] == 2);
	CHECK(runner->tick(0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(runner->get_profile_snapshot()["total_samples"] == 2);
	runner->reset_profile();
	CHECK(runner->get_profile_snapshot()["total_samples"] == 0);
	CHECK(runner->is_profiling_enabled());
	runner->set_profiling_enabled(false);
	runner->reset();
	CHECK(runner->tick(0.1) == BehaviorTreeTask::RUNNING);
	CHECK(runner->get_profile_snapshot()["total_samples"] == 0);
	memdelete(runner);
}

} // namespace TestAIExecutionProfiler
