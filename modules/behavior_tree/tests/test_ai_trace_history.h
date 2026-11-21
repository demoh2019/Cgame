/**************************************************************************/
/*  test_ai_trace_history.h                                                  */
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

namespace TestAITraceHistory {

static void record_tick(Ref<AIBehaviorTrace> &r_trace, const String &p_path, int p_status, int p_depth = 1) {
	r_trace->begin_tick();
	const int token = r_trace->begin_step(p_path, "BehaviorTreeWait");
	CHECK(token >= 0);
	CHECK(r_trace->end_step(token, p_status));
}

TEST_CASE("[AITraceHistory] Default off and capacity validation") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	CHECK(trace->get_history_capacity() == 0);
	record_tick(trace, "root", BehaviorTreeTask::RUNNING);
	CHECK(trace->get_history_frames().is_empty());
	ERR_PRINT_OFF;
	trace->set_history_capacity(-1);
	trace->set_history_capacity(33);
	ERR_PRINT_ON;
	CHECK(trace->get_history_capacity() == 0);
	trace->set_history_capacity(1);
	CHECK(trace->get_history_capacity() == 1);
	Array frames = trace->get_history_frames();
	REQUIRE(frames.size() == 1);
	const Dictionary frame = frames[0];
	CHECK(int64_t(frame["tick_index"]) == 1);
}

TEST_CASE("[AITraceHistory] History evicts oldest tick and preserves order") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->set_history_capacity(3);
	for (int i = 0; i < 5; ++i) {
		record_tick(trace, "root/" + itos(i), BehaviorTreeTask::SUCCESS);
	}
	const Array frames = trace->get_history_frames();
	REQUIRE(frames.size() == 3);
	for (int i = 0; i < 3; ++i) {
		const Dictionary frame = frames[i];
		CHECK(int64_t(frame["tick_index"]) == i + 3);
		const Array steps = frame["steps"];
		REQUIRE(steps.size() == 1);
		const Dictionary task = steps[0];
		CHECK(task["path"] == "root/" + itos(i + 2));
	}
}

TEST_CASE("[AITraceHistory] Equivalent execution ignores CPU duration changes") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->set_history_capacity(5);
	record_tick(trace, "root/0", BehaviorTreeTask::RUNNING);
	record_tick(trace, "root/0", BehaviorTreeTask::RUNNING);
	record_tick(trace, "root/0", BehaviorTreeTask::SUCCESS);
	record_tick(trace, "root/0", BehaviorTreeTask::SUCCESS);
	const Array frames = trace->get_history_frames();
	REQUIRE(frames.size() == 4);
	CHECK(Dictionary(frames[0])["changed"] == true);
	CHECK(Dictionary(frames[1])["changed"] == false);
	CHECK(Dictionary(frames[2])["changed"] == true);
	CHECK(Dictionary(frames[3])["changed"] == false);
	const Array changes = trace->get_history_frames(true);
	REQUIRE(changes.size() == 2);
	CHECK(int64_t(Dictionary(changes[0])["tick_index"]) == 1);
	CHECK(int64_t(Dictionary(changes[1])["tick_index"]) == 3);
}

TEST_CASE("[AITraceHistory] Path and truncation differences are relevant changes") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->set_history_capacity(4);
	record_tick(trace, "root/0", BehaviorTreeTask::RUNNING);
	record_tick(trace, "root/1", BehaviorTreeTask::RUNNING);
	trace->set_max_steps(1); // Resets all frames; capacity remains 4.
	CHECK(trace->get_history_capacity() == 4);
	CHECK(trace->get_history_frames().is_empty());
	record_tick(trace, "root/0", BehaviorTreeTask::RUNNING);
	CHECK(trace->begin_step("root/1", "Extra") == -1); // Full tick.
	record_tick(trace, "root/0", BehaviorTreeTask::RUNNING);
	const Array changes = trace->get_history_frames(true);
	REQUIRE(changes.size() == 2);
	CHECK(int64_t(Dictionary(changes[0])["tick_index"]) == 1);
	CHECK(int64_t(Dictionary(changes[1])["tick_index"]) == 2);
}

TEST_CASE("[AITraceHistory] History copies are detached from retained records") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->set_history_capacity(3);
	record_tick(trace, "root/0", BehaviorTreeTask::SUCCESS);
	record_tick(trace, "root/1", BehaviorTreeTask::SUCCESS);
	Array frames = trace->get_history_frames();
	Dictionary oldest = frames[0];
	Array steps = oldest["steps"];
	Dictionary event = steps[0];
	event["path"] = "tampered";
	steps.clear();
	frames.clear();
	const Array fresh = trace->get_history_frames();
	REQUIRE(fresh.size() == 2);
	const Dictionary original = fresh[0];
	const Array original_steps = original["steps"];
	REQUIRE(original_steps.size() == 1);
	const Dictionary original_event = original_steps[0];
	CHECK(original_event["path"] == "root/0");
}

TEST_CASE("[AITraceHistory] Slow task report sorts by inclusive duration and path") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->begin_tick();
	int a = trace->begin_step("root/z", "Z");
	int b = trace->begin_step("root/a", "A");
	CHECK(trace->end_step(a, BehaviorTreeTask::SUCCESS));
	CHECK(trace->end_step(b, BehaviorTreeTask::FAILURE));
	// Both may have equal microsecond durations on a fast machine;
	// independently of that, results must be descending and tie stable.
	const Array hot = trace->get_slowest_nodes(2);
	REQUIRE(hot.size() == 2);
	const Dictionary first = hot[0], second = hot[1];
	CHECK(int64_t(first["duration_usec"]) >= int64_t(second["duration_usec"]));
	if (int64_t(first["duration_usec"]) == int64_t(second["duration_usec"])) {
		CHECK(String(first["path"]) < String(second["path"]));
	}
	CHECK(trace->get_slowest_nodes(1).size() == 1);
	CHECK(trace->get_slowest_nodes(0).is_empty());
	ERR_PRINT_OFF;
	CHECK(trace->get_slowest_nodes(-1).is_empty());
	CHECK(trace->get_slowest_nodes(33).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[AITraceHistory] Unfinished tasks are ignored by slow task report") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->begin_tick();
	const int unfinished = trace->begin_step("root/unfinished", "Wait");
	const int finished = trace->begin_step("root/finished", "Fast");
	CHECK(trace->end_step(finished, BehaviorTreeTask::SUCCESS));
	const Array hot = trace->get_slowest_nodes();
	REQUIRE(hot.size() == 1);
	const Dictionary only = hot[0];
	CHECK(only["path"] == "root/finished");
	CHECK(trace->end_step(unfinished, BehaviorTreeTask::RUNNING));
	CHECK(trace->get_slowest_nodes().size() == 2);
}

TEST_CASE("[AITraceHistory] Shrink and zero capacity release retained memory") {
	Ref<AIBehaviorTrace> trace;
	trace.instantiate();
	trace->set_history_capacity(4);
	for (int i = 0; i < 5; ++i) {
		record_tick(trace, "root", BehaviorTreeTask::RUNNING);
	}
	CHECK(trace->get_history_frames().size() == 4);
	trace->set_history_capacity(2);
	CHECK(trace->get_history_frames().size() == 2);
	trace->set_history_capacity(0);
	CHECK(trace->get_history_frames().is_empty());
	CHECK(trace->get_history_capacity() == 0);
	CHECK(trace->get_snapshot()["tick_index"] == int64_t(5)); // Main trace unaffected.
	trace->reset();
	CHECK(trace->get_history_frames().is_empty());
	CHECK(trace->get_history_capacity() == 0);
}

TEST_CASE("[AITraceHistory] Runner history is isolated and cached ticks are not recorded") {
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(0.1);
	BehaviorTreeRunner *a = memnew(BehaviorTreeRunner);
	BehaviorTreeRunner *b = memnew(BehaviorTreeRunner);
	a->set_root_task(wait);
	b->set_root_task(wait);
	a->set_trace_history_capacity(4);
	CHECK(a->get_trace_history_capacity() == 4);
	CHECK_FALSE(a->is_trace_enabled()); // Buffer alone never enables tracing.
	CHECK(a->get_trace_history_frames().is_empty());
	a->set_trace_enabled(true);
	CHECK(a->tick(0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(a->tick(0.2) == BehaviorTreeTask::SUCCESS); // Cached.
	CHECK(a->get_trace_history_frames().size() == 1);
	CHECK(b->get_trace_history_frames().is_empty());
	a->reset();
	CHECK(a->tick(0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(a->get_trace_history_frames().size() == 2);
	CHECK(a->get_slowest_trace_nodes(1).size() == 1);
	a->set_trace_enabled(false);
	CHECK(a->get_trace_history_frames().is_empty());
	CHECK(a->get_slowest_trace_nodes(1).is_empty());
	memdelete(a);
	memdelete(b);
}

} // namespace TestAITraceHistory
