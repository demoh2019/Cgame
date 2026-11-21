/**************************************************************************/
/*  test_ai_behavior_trace.h                                                  */
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

#include "../ai_behavior_trace.h"
#include "../behavior_tree.h"
#include "tests/test_macros.h"

namespace TestAIBehaviorTrace {

TEST_CASE("[AIBehaviorTrace] Empty optional timeline has stable diagnostic keys") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	Dictionary before = trace->get_snapshot();
	CHECK(int64_t(before["tick_index"]) == 0);
	CHECK(int(before["max_steps"]) == 128);
	CHECK(int(before["truncated"]) == 0);
	const Array empty_steps = before["steps"];
	CHECK(empty_steps.is_empty());
}

TEST_CASE("[AIBehaviorTrace] Nesting returns start order and inclusive task durations") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->begin_tick();
	const int root = trace->begin_step("root", "BehaviorTreeSequence");
	const int child = trace->begin_step("root/0", "BehaviorTreeWait");
	REQUIRE(root == 0);
	REQUIRE(child == 1);
	CHECK(trace->end_step(child, BehaviorTreeTask::RUNNING));
	CHECK(trace->end_step(root, BehaviorTreeTask::RUNNING));
	const Dictionary snapshot = trace->get_snapshot();
	const Array steps = snapshot["steps"];
	REQUIRE(steps.size() == 2);
	Dictionary parent = steps[0];
	Dictionary leaf = steps[1];
	CHECK(parent["path"] == "root");
	CHECK(parent["task_class"] == "BehaviorTreeSequence");
	CHECK(int(parent["depth"]) == 0);
	CHECK(int(parent["status"]) == BehaviorTreeTask::RUNNING);
	CHECK(int64_t(parent["duration_usec"]) >= 0);
	CHECK(leaf["path"] == "root/0");
	CHECK(int(leaf["depth"]) == 1);
	CHECK(int(leaf["status"]) == BehaviorTreeTask::RUNNING);
	CHECK(int64_t(leaf["duration_usec"]) >= 0);
	CHECK(int64_t(snapshot["tick_index"]) == 1);
}

TEST_CASE("[AIBehaviorTrace] Bounded record budget reports truncation") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->set_max_steps(2);
	trace->begin_tick();
	int a = trace->begin_step("root", "A");
	int b = trace->begin_step("root/0", "B");
	int c = trace->begin_step("root/1", "C");
	CHECK(a == 0);
	CHECK(b == 1);
	CHECK(c == -1);
	CHECK(trace->end_step(b, 0));
	CHECK(trace->end_step(a, 2));
	CHECK_FALSE(trace->end_step(c, 1));
	const Dictionary snap = trace->get_snapshot();
	CHECK(int(snap["truncated"]) == 1);
	const Array steps = snap["steps"];
	CHECK(steps.size() == 2);
	CHECK(int(steps[0]["status"]) == BehaviorTreeTask::RUNNING);
}

TEST_CASE("[AIBehaviorTrace] Tick lifecycle clears only prior events") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->begin_tick();
	CHECK(trace->begin_step("root", "First") == 0);
	trace->begin_tick();
	CHECK(trace->begin_step("root", "Second") == 0);
	const Dictionary snap = trace->get_snapshot();
	CHECK(int64_t(snap["tick_index"]) == 2);
	const Array steps = snap["steps"];
	REQUIRE(steps.size() == 1);
	Dictionary item = steps[0];
	CHECK(item["task_class"] == "Second");
	trace->reset();
	const Dictionary reset = trace->get_snapshot();
	CHECK(int64_t(reset["tick_index"]) == 0);
	const Array reset_steps = reset["steps"];
	CHECK(reset_steps.is_empty());
}

TEST_CASE("[AIBehaviorTrace] Malformed events do not corrupt timeline state") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->begin_tick();
	ERR_PRINT_OFF;
	CHECK(trace->begin_step("", "Task") == -1);
	CHECK(trace->begin_step("root", "") == -1);
	trace->set_max_steps(0);
	trace->set_max_steps(257);
	ERR_PRINT_ON;
	CHECK(trace->get_max_steps() == 128);
	CHECK(trace->begin_step("root", "Task") == 0);
	ERR_PRINT_OFF;
	CHECK_FALSE(trace->end_step(0, -1));
	CHECK_FALSE(trace->end_step(0, 99));
	ERR_PRINT_ON;
	CHECK(trace->end_step(0, BehaviorTreeTask::SUCCESS));
	CHECK_FALSE(trace->end_step(0, BehaviorTreeTask::FAILURE));
	CHECK_FALSE(trace->end_step(5, BehaviorTreeTask::SUCCESS));
}

TEST_CASE("[AIBehaviorTrace] Snapshot is detached from the recording") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->begin_tick();
	int token = trace->begin_step("root", "Original");
	CHECK(trace->end_step(token, BehaviorTreeTask::SUCCESS));
	Dictionary snapshot = trace->get_snapshot();
	Array copied = snapshot["steps"];
	Dictionary event = copied[0];
	event["path"] = "altered";
	copied.clear();
	Dictionary actual = trace->get_snapshot();
	Array events = actual["steps"];
	REQUIRE(events.size() == 1);
	Dictionary entry = events[0];
	CHECK(entry["path"] == "root");
}

TEST_CASE("[AIBehaviorTrace] Runner emits task-by-task pre-order with parent statuses") {
	Ref<BehaviorTreeReactiveSequence> root;
	root.instantiate();
	Ref<BehaviorTreeBlackboardCheck> check;
	check.instantiate();
	check->set_key(SNAME("allowed"));
	check->set_expected_value(true);
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(1.0);
	root->add_task(check);
	root->add_task(wait);

	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(root);
	Dictionary blackboard;
	blackboard["allowed"] = true;
	runner->set_blackboard(blackboard);
	runner->set_trace_enabled(true);
	CHECK(runner->tick(0.2) == BehaviorTreeTask::RUNNING);
	const Dictionary snapshot = runner->get_trace_snapshot();
	CHECK(snapshot["enabled"] == true);
	CHECK(int64_t(snapshot["tick_index"]) == 1);
	Array steps = snapshot["steps"];
	REQUIRE(steps.size() == 3);
	Dictionary top = steps[0], guard = steps[1], timer = steps[2];
	CHECK(top["path"] == "root");
	CHECK(top["task_class"] == "BehaviorTreeReactiveSequence");
	CHECK(int(top["status"]) == BehaviorTreeTask::RUNNING);
	CHECK(guard["path"] == "root/0");
	CHECK(int(guard["status"]) == BehaviorTreeTask::SUCCESS);
	CHECK(timer["path"] == "root/1");
	CHECK(int(timer["status"]) == BehaviorTreeTask::RUNNING);
	const Dictionary runner_memory = runner->get_debug_snapshot()["execution_memory"];
	CHECK_FALSE(runner_memory.has("__bt_trace_sink"));
	CHECK(runner->tick(0.2) == BehaviorTreeTask::RUNNING);
	CHECK(int64_t(runner->get_trace_snapshot()["tick_index"]) == 2);
	memdelete(runner);
}

TEST_CASE("[AIBehaviorTrace] Nested decorators trace every executed child") {
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(2.0);
	Ref<BehaviorTreeTimeout> timeout;
	timeout.instantiate();
	timeout->set_duration(1.0);
	timeout->set_task(wait);
	Ref<BehaviorTreeCooldown> cooldown;
	cooldown.instantiate();
	cooldown->set_task(timeout);
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(cooldown);
	runner->set_trace_enabled(true);
	CHECK(runner->tick(0.2) == BehaviorTreeTask::RUNNING);
	Array steps = runner->get_trace_snapshot()["steps"];
	REQUIRE(steps.size() == 3);
	Dictionary a = steps[0], b = steps[1], c = steps[2];
	CHECK(a["path"] == "root");
	CHECK(b["path"] == "root/0");
	CHECK(c["path"] == "root/0/0");
	CHECK(int(c["status"]) == BehaviorTreeTask::RUNNING);
	memdelete(runner);
}

TEST_CASE("[AIBehaviorTrace] Disabled runners do not retain trace contexts") {
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(0.5);
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(wait);
	CHECK_FALSE(runner->is_trace_enabled());
	CHECK(runner->tick(0.2) == BehaviorTreeTask::RUNNING);
	CHECK(runner->get_trace_snapshot()["enabled"] == false);
	const Array no_steps = runner->get_trace_snapshot()["steps"];
	CHECK(no_steps.is_empty());
	const Dictionary runner_memory = runner->get_debug_snapshot()["execution_memory"];
	CHECK_FALSE(runner_memory.has("__bt_trace_sink"));
	runner->set_trace_enabled(true);
	CHECK(runner->tick(0.3) == BehaviorTreeTask::SUCCESS);
	const Array last_steps = runner->get_trace_snapshot()["steps"];
	CHECK(last_steps.size() == 1);
	CHECK(runner->tick(0.5) == BehaviorTreeTask::SUCCESS); // cached result
	const Array last_steps = runner->get_trace_snapshot()["steps"];
	CHECK(last_steps.size() == 1);
	runner->set_trace_enabled(false);
	const Array no_steps = runner->get_trace_snapshot()["steps"];
	CHECK(no_steps.is_empty());
	memdelete(runner);
}

} // namespace TestAIBehaviorTrace
