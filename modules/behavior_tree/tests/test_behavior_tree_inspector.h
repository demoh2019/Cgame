/**************************************************************************/
/*  test_behavior_tree_inspector.h                                                  */
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

#include "../behavior_tree.h"
#include "tests/test_macros.h"

namespace TestBehaviorTreeInspector {

TEST_CASE("[BehaviorTreeInspector] Untraced tree includes every native child") {
	Ref<BehaviorTreeReactiveSelector> root;
	root.instantiate();
	Ref<BehaviorTreeSequence> branch;
	branch.instantiate();
	Ref<BehaviorTreeBlackboardCheck> guard;
	guard.instantiate();
	guard->set_key(SNAME("ready"));
	guard->set_expected_value(true);
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(1.0);
	branch->add_task(guard);
	branch->add_task(wait);
	Ref<BehaviorTreeBlackboardSet> fallback;
	fallback.instantiate();
	fallback->set_key(SNAME("action"));
	fallback->set_value(String("idle"));
	root->add_task(branch);
	root->add_task(fallback);
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(root);
	const Dictionary snapshot = runner->get_tree_snapshot();
	const Array nodes = snapshot["nodes"];
	REQUIRE(nodes.size() == 5);
	const Dictionary root_node = nodes[0], branch_node = nodes[1], guard_node = nodes[2], wait_node = nodes[3], fallback_node = nodes[4];
	CHECK(root_node["path"] == Variant("root"));
	CHECK(int(root_node["depth"]) == 0);
	CHECK(root_node["task_class"] == Variant("BehaviorTreeReactiveSelector"));
	CHECK(branch_node["path"] == Variant("root/0"));
	CHECK(guard_node["path"] == Variant("root/0/0"));
	CHECK(wait_node["path"] == Variant("root/0/1"));
	CHECK(fallback_node["path"] == Variant("root/1"));
	CHECK(int(wait_node["depth"]) == 2);
	CHECK(wait_node["executed"] == Variant(false));
	CHECK(int(wait_node["status"]) == -1);
	CHECK(snapshot["trace_enabled"] == Variant(false));
	CHECK(snapshot["truncated"] == Variant(false));
	memdelete(runner);
}

TEST_CASE("[BehaviorTreeInspector] Opt-in trace identifies visited and unvisited tasks") {
	Ref<BehaviorTreeReactiveSelector> root;
	root.instantiate();
	Ref<BehaviorTreeBlackboardCheck> priority;
	priority.instantiate();
	priority->set_key(SNAME("priority"));
	priority->set_expected_value(true);
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(1.0);
	Ref<BehaviorTreeWait> skipped;
	skipped.instantiate();
	skipped->set_duration(1.0);
	root->add_task(priority);
	root->add_task(wait);
	root->add_task(skipped);
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(root);
	runner->set_trace_enabled(true);
	CHECK(runner->tick(0.2) == BehaviorTreeTask::RUNNING);
	const Dictionary snapshot = runner->get_tree_snapshot();
	const Array nodes = snapshot["nodes"];
	REQUIRE(nodes.size() == 4);
	const Dictionary root_node = nodes[0], rejected = nodes[1], running = nodes[2], untouched = nodes[3];
	CHECK(root_node["executed"] == Variant(true));
	CHECK(int(root_node["status"]) == BehaviorTreeTask::RUNNING);
	CHECK(rejected["executed"] == Variant(true));
	CHECK(int(rejected["status"]) == BehaviorTreeTask::FAILURE);
	CHECK(running["executed"] == Variant(true));
	CHECK(int(running["status"]) == BehaviorTreeTask::RUNNING);
	CHECK(int64_t(running["duration_usec"]) >= 0);
	CHECK(untouched["executed"] == Variant(false));
	CHECK(int(untouched["status"]) == -1);
	CHECK(snapshot["trace_enabled"] == Variant(true));
	CHECK(int64_t(snapshot["tick_index"]) == 1);
	CHECK(int(snapshot["trace_truncated"]) == 0);
	memdelete(runner);
}

TEST_CASE("[BehaviorTreeInspector] Shared task resource renders at different paths") {
	Ref<BehaviorTreeSequence> root;
	root.instantiate();
	Ref<BehaviorTreeBlackboardSet> shared;
	shared.instantiate();
	shared->set_key(SNAME("hit"));
	shared->set_value(true);
	root->add_task(shared);
	root->add_task(shared);
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(root);
	runner->set_trace_enabled(true);
	CHECK(runner->tick(0.1) == BehaviorTreeTask::SUCCESS);
	const Dictionary snapshot = runner->get_tree_snapshot();
	const Array nodes = snapshot["nodes"];
	REQUIRE(nodes.size() == 3);
	const Dictionary left = nodes[1], right = nodes[2];
	CHECK(left["path"] == Variant("root/0"));
	CHECK(right["path"] == Variant("root/1"));
	CHECK(left["executed"] == Variant(true));
	CHECK(right["executed"] == Variant(true));
	CHECK(int(right["status"]) == BehaviorTreeTask::SUCCESS);
	memdelete(runner);
}

TEST_CASE("[BehaviorTreeInspector] Inverter and decorator children are visible") {
	Ref<BehaviorTreeWait> leaf;
	leaf.instantiate();
	Ref<BehaviorTreeTimeout> timeout;
	timeout.instantiate();
	timeout->set_task(leaf);
	Ref<BehaviorTreeInverter> inverter;
	inverter.instantiate();
	inverter->set_task(timeout);
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(inverter);
	const Dictionary snapshot = runner->get_tree_snapshot();
	const Array nodes = snapshot["nodes"];
	REQUIRE(nodes.size() == 3);
	const Dictionary a = nodes[0], b = nodes[1], c = nodes[2];
	CHECK(a["task_class"] == Variant("BehaviorTreeInverter"));
	CHECK(b["task_class"] == Variant("BehaviorTreeTimeout"));
	CHECK(c["task_class"] == Variant("BehaviorTreeWait"));
	CHECK(c["path"] == Variant("root/0/0"));
	memdelete(runner);
}

TEST_CASE("[BehaviorTreeInspector] Graph size is capped and reports truncation") {
	Ref<BehaviorTreeSelector> root;
	root.instantiate();
	Ref<BehaviorTreeBlackboardCheck> leaf;
	leaf.instantiate();
	for (int i = 0; i < 300; ++i) {
		root->add_task(leaf);
	}
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(root);
	const Dictionary snapshot = runner->get_tree_snapshot();
	const Array nodes = snapshot["nodes"];
	CHECK(nodes.size() == 256);
	CHECK(int(snapshot["node_count"]) == 256);
	CHECK(snapshot["truncated"] == Variant(true));
	memdelete(runner);
}

TEST_CASE("[BehaviorTreeInspector] Optional inspection does not edit execution memory") {
	Ref<BehaviorTreeWait> leaf;
	leaf.instantiate();
	leaf->set_duration(2.0);
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(leaf);
	CHECK(runner->tick(0.2) == BehaviorTreeTask::RUNNING);
	const Dictionary before = runner->get_debug_snapshot()["execution_memory"];
	CHECK(before.has("root"));
	const Dictionary snapshot = runner->get_tree_snapshot();
	Array nodes = snapshot["nodes"];
	nodes.clear(); // Snapshot is detached from the actual tree.
	const Dictionary after = runner->get_debug_snapshot()["execution_memory"];
	CHECK(after == before);
	const Dictionary second_snapshot = runner->get_tree_snapshot();
	const Array fresh_nodes = second_snapshot["nodes"];
	CHECK(fresh_nodes.size() == 1);
	memdelete(runner);
}

TEST_CASE("[BehaviorTreeInspector] Clearing tracing preserves visible graph") {
	Ref<BehaviorTreeWait> leaf;
	leaf.instantiate();
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	runner->set_root_task(leaf);
	runner->set_trace_enabled(true);
	CHECK(runner->tick(0.1) == BehaviorTreeTask::RUNNING);
	runner->set_trace_enabled(false);
	const Dictionary snapshot = runner->get_tree_snapshot();
	const Array nodes = snapshot["nodes"];
	REQUIRE(nodes.size() == 1);
	const Dictionary only = nodes[0];
	CHECK(only["executed"] == Variant(false));
	CHECK(int(only["status"]) == -1);
	CHECK(snapshot["trace_enabled"] == Variant(false));
	memdelete(runner);
}

TEST_CASE("[BehaviorTreeInspector] Null root returns a safe empty graph") {
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	const Dictionary snapshot = runner->get_tree_snapshot();
	const Array nodes = snapshot["nodes"];
	CHECK(nodes.is_empty());
	CHECK(int(snapshot["node_count"]) == 0);
	CHECK(snapshot["truncated"] == Variant(false));
	memdelete(runner);
}

} // namespace TestBehaviorTreeInspector
