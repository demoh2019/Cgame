/**************************************************************************/
/*  test_behavior_tree.cpp                                                */
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

TEST_FORCE_LINK(test_behavior_tree)

#include "modules/modules_enabled.gen.h"

#ifdef MODULE_BEHAVIOR_TREE_ENABLED

#include "modules/behavior_tree/behavior_tree.h"

#include "core/io/resource_loader.h"
#include "core/io/resource_saver.h"
#include "scene/main/scene_tree.h"
#include "tests/signal_watcher.h"
#include "tests/test_utils.h"

namespace TestBehaviorTree {

// Node-derived objects must be constructed with memnew so ObjectDB and
// signal dispatch are initialized, even for headless/manual-tick tests.
struct RunnerHolder {
	BehaviorTreeRunner *node = memnew(BehaviorTreeRunner);

	~RunnerHolder() {
		memdelete(node);
	}

	void set_root_task(const Ref<BehaviorTreeTask> &p_task) { node->set_root_task(p_task); }
	void set_blackboard(const Dictionary &p_blackboard) { node->set_blackboard(p_blackboard); }
	Dictionary get_blackboard() const { return node->get_blackboard(); }
	BehaviorTreeTask::Status tick(double p_delta) { return node->tick(p_delta); }
	void reset() { node->reset(); }
	bool is_finished() const { return node->is_finished(); }
};

static Ref<BehaviorTreeBlackboardCheck> check(const StringName &p_key, const Variant &p_expected) {
	Ref<BehaviorTreeBlackboardCheck> task;
	task.instantiate();
	task->set_key(p_key);
	task->set_expected_value(p_expected);
	return task;
}

static Ref<BehaviorTreeBlackboardSet> assign(const StringName &p_key, const Variant &p_value) {
	Ref<BehaviorTreeBlackboardSet> task;
	task.instantiate();
	task->set_key(p_key);
	task->set_value(p_value);
	return task;
}

static Ref<BehaviorTreeWait> wait(double p_duration) {
	Ref<BehaviorTreeWait> task;
	task.instantiate();
	task->set_duration(p_duration);
	return task;
}

TEST_CASE("[BehaviorTree] Empty sequence succeeds and empty selector fails") {
	Ref<BehaviorTreeSequence> seq;
	seq.instantiate();
	Ref<BehaviorTreeSelector> sel;
	sel.instantiate();
	RunnerHolder runner;
	runner.set_root_task(seq);
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	runner.set_root_task(sel);
	CHECK(runner.tick(0) == BehaviorTreeTask::FAILURE);
}

TEST_CASE("[BehaviorTree] Blackboard checks distinguish missing, false and matching values") {
	Ref<BehaviorTreeBlackboardCheck> task = check("has_target", false);
	RunnerHolder runner;
	runner.set_root_task(task);
	CHECK(runner.tick(0) == BehaviorTreeTask::FAILURE);
	runner.reset();
	Dictionary bb;
	bb["has_target"] = false;
	runner.set_blackboard(bb);
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	runner.reset();
	bb["has_target"] = true;
	CHECK(runner.tick(0) == BehaviorTreeTask::FAILURE);
}

TEST_CASE("[BehaviorTree] Blackboard setter changes the runner's shared dictionary") {
	RunnerHolder runner;
	runner.set_root_task(assign("ammo", 42));
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	CHECK(int(runner.get_blackboard()["ammo"]) == 42);
}

TEST_CASE("[BehaviorTree] A missing blackboard key prevents assignment") {
	RunnerHolder runner;
	Ref<BehaviorTreeBlackboardSet> setter = assign("", 42);
	runner.set_root_task(setter);
	CHECK(runner.tick(0) == BehaviorTreeTask::FAILURE);
	CHECK(runner.get_blackboard().is_empty());
}

TEST_CASE("[BehaviorTree] Sequence evaluates children in order and short-circuits on failure") {
	Ref<BehaviorTreeSequence> seq;
	seq.instantiate();
	seq->add_task(assign("step", 1));
	seq->add_task(check("allowed", true));
	seq->add_task(assign("step", 2));
	RunnerHolder runner;
	runner.set_root_task(seq);
	CHECK(runner.tick(0) == BehaviorTreeTask::FAILURE);
	CHECK(int(runner.get_blackboard()["step"]) == 1);
	CHECK(seq->get_task_count() == 3);
}

TEST_CASE("[BehaviorTree] Sequence completes all tasks on success") {
	Ref<BehaviorTreeSequence> seq;
	seq.instantiate();
	seq->add_task(assign("item", "key"));
	seq->add_task(check("item", "key"));
	seq->add_task(assign("door_open", true));
	RunnerHolder runner;
	runner.set_root_task(seq);
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	CHECK(bool(runner.get_blackboard()["door_open"]));
}

TEST_CASE("[BehaviorTree] Selector skips failing branches and runs the first successful branch") {
	Ref<BehaviorTreeSelector> sel;
	sel.instantiate();
	sel->add_task(check("health", 1));
	sel->add_task(assign("strategy", "retreat"));
	sel->add_task(assign("strategy", "fight"));
	RunnerHolder runner;
	runner.set_root_task(sel);
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	CHECK(String(runner.get_blackboard()["strategy"]) == "retreat");
}

TEST_CASE("[BehaviorTree] Inverter flips success and failure") {
	Ref<BehaviorTreeInverter> inv;
	inv.instantiate();
	inv->set_task(check("target_visible", true));
	RunnerHolder runner;
	runner.set_root_task(inv);
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	runner.reset();
	Dictionary bb;
	bb["target_visible"] = true;
	runner.set_blackboard(bb);
	CHECK(runner.tick(0) == BehaviorTreeTask::FAILURE);
}

TEST_CASE("[BehaviorTree] Inverter preserves RUNNING") {
	Ref<BehaviorTreeInverter> inv;
	inv.instantiate();
	inv->set_task(wait(1));
	RunnerHolder runner;
	runner.set_root_task(inv);
	CHECK(runner.tick(0.5) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.5) == BehaviorTreeTask::FAILURE);
}

TEST_CASE("[BehaviorTree] A wait resumes using accumulated delta") {
	RunnerHolder runner;
	runner.set_root_task(wait(1.0));
	CHECK(runner.tick(0.25) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.3) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.449) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.0011) == BehaviorTreeTask::SUCCESS);
	CHECK(runner.is_finished());
}

TEST_CASE("[BehaviorTree] Zero-duration waits complete without advancing time") {
	RunnerHolder runner;
	runner.set_root_task(wait(0));
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] Sequence resumes a running child without replaying earlier actions") {
	Ref<BehaviorTreeSequence> seq;
	seq.instantiate();
	seq->add_task(assign("flag", 1));
	seq->add_task(wait(1.0));
	seq->add_task(check("flag", 1));
	RunnerHolder runner;
	runner.set_root_task(seq);
	CHECK(runner.tick(0.4) == BehaviorTreeTask::RUNNING);
	// A completed predecessor must not be re-executed on subsequent ticks.
	runner.get_blackboard()["flag"] = 9;
	CHECK(runner.tick(0.4) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.2) == BehaviorTreeTask::FAILURE);
	CHECK(int(runner.get_blackboard()["flag"]) == 9);
}

TEST_CASE("[BehaviorTree] Selector resumes a running branch instead of reconsidering predecessors") {
	Ref<BehaviorTreeSelector> sel;
	sel.instantiate();
	sel->add_task(check("ready", true));
	sel->add_task(wait(0.5));
	sel->add_task(assign("fallback", true));
	RunnerHolder runner;
	runner.set_root_task(sel);
	CHECK(runner.tick(0.2) == BehaviorTreeTask::RUNNING);
	runner.get_blackboard()["ready"] = true;
	CHECK(runner.tick(0.3) == BehaviorTreeTask::SUCCESS);
	CHECK_FALSE(runner.get_blackboard().has("fallback"));
}

TEST_CASE("[BehaviorTree] Nested sequences and selectors compose correctly") {
	Ref<BehaviorTreeSequence> root;
	root.instantiate();
	Ref<BehaviorTreeSelector> sel;
	sel.instantiate();
	sel->add_task(check("has_path", true));
	sel->add_task(assign("found_path", true));
	root->add_task(sel);
	root->add_task(check("found_path", true));
	RunnerHolder runner;
	runner.set_root_task(root);
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] Separate agents do not share running-state cursors") {
	Ref<BehaviorTreeWait> shared_wait = wait(1.0);
	RunnerHolder first;
	RunnerHolder second;
	first.set_root_task(shared_wait);
	second.set_root_task(shared_wait);
	CHECK(first.tick(0.8) == BehaviorTreeTask::RUNNING);
	CHECK(second.tick(0.2) == BehaviorTreeTask::RUNNING);
	CHECK(first.tick(0.2) == BehaviorTreeTask::SUCCESS);
	CHECK(second.tick(0.2) == BehaviorTreeTask::RUNNING);
	CHECK(second.tick(0.6) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] The same subresource can run in separate paths") {
	Ref<BehaviorTreeWait> shared_wait = wait(0.5);
	Ref<BehaviorTreeSequence> seq;
	seq.instantiate();
	seq->add_task(shared_wait);
	seq->add_task(shared_wait);
	RunnerHolder runner;
	runner.set_root_task(seq);
	CHECK(runner.tick(0.3) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.2) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.3) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.2) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] Reset cancels a running task and restarts its elapsed time") {
	RunnerHolder runner;
	runner.set_root_task(wait(1.0));
	CHECK(runner.tick(0.9) == BehaviorTreeTask::RUNNING);
	runner.reset();
	CHECK_FALSE(runner.is_finished());
	CHECK(runner.tick(0.2) == BehaviorTreeTask::RUNNING);
	CHECK(runner.tick(0.8) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] Completed trees do not repeat side effects until reset") {
	RunnerHolder runner;
	runner.set_root_task(assign("counter", 1));
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	runner.get_blackboard()["counter"] = 7;
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	CHECK(int(runner.get_blackboard()["counter"]) == 7);
	runner.reset();
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	CHECK(int(runner.get_blackboard()["counter"]) == 1);
}

TEST_CASE("[BehaviorTree] Changing the root resets execution state") {
	RunnerHolder runner;
	runner.set_root_task(wait(1.0));
	CHECK(runner.tick(0.9) == BehaviorTreeTask::RUNNING);
	runner.set_root_task(assign("changed", true));
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	CHECK(bool(runner.get_blackboard()["changed"]));
}

TEST_CASE("[BehaviorTree] Null task roots fail without finishing the runner") {
	RunnerHolder runner;
	CHECK(runner.tick(0) == BehaviorTreeTask::FAILURE);
	CHECK_FALSE(runner.is_finished());
	runner.set_root_task(assign("available", true));
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] Reject self-reference and indirect cycles") {
	Ref<BehaviorTreeSequence> first;
	first.instantiate();
	Ref<BehaviorTreeSequence> second;
	second.instantiate();
	Ref<BehaviorTreeInverter> inverter;
	inverter.instantiate();

	ERR_PRINT_OFF
	first->add_task(first);
	ERR_PRINT_ON
	CHECK(first->get_task_count() == 0);
	first->add_task(second);
	ERR_PRINT_OFF
	second->add_task(first);
	ERR_PRINT_ON
	CHECK(second->get_task_count() == 0);
	inverter->set_task(first);
	ERR_PRINT_OFF
	first->add_task(inverter);
	ERR_PRINT_ON
	CHECK(first->get_task_count() == 1);
}

TEST_CASE("[BehaviorTree] Typed children array cannot bypass cycle validation") {
	Ref<BehaviorTreeSequence> seq;
	seq.instantiate();
	TypedArray<BehaviorTreeTask> children;
	children.push_back(assign("a", 1));
	seq->set_tasks(children);
	TypedArray<BehaviorTreeTask> obtained = seq->get_tasks();
	obtained.clear();
	CHECK(seq->get_task_count() == 1);

	children.clear();
	children.push_back(seq);
	ERR_PRINT_OFF
	seq->set_tasks(children);
	ERR_PRINT_ON
	CHECK(seq->get_task_count() == 1);
}

TEST_CASE("[BehaviorTree] Removing tasks updates the composite") {
	Ref<BehaviorTreeSequence> seq;
	seq.instantiate();
	seq->add_task(assign("a", 1));
	seq->add_task(assign("b", 2));
	seq->remove_task(0);
	CHECK(seq->get_task_count() == 1);
	RunnerHolder runner;
	runner.set_root_task(seq);
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	CHECK_FALSE(runner.get_blackboard().has("a"));
	CHECK(int(runner.get_blackboard()["b"]) == 2);
	seq->clear_tasks();
	CHECK(seq->get_task_count() == 0);
}

TEST_CASE("[BehaviorTree] Auto tick progresses when the node is processing") {
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	SceneTree::get_singleton()->get_root()->add_child(runner);
	runner->set_root_task(wait(0));
	runner->set_auto_tick(true);
	SceneTree::get_singleton()->process(0);
	CHECK(runner->is_finished());
	CHECK(runner->get_last_status() == BehaviorTreeTask::SUCCESS);
	memdelete(runner);
}

TEST_CASE("[BehaviorTree] Completion emits a signal exactly once") {
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	SIGNAL_WATCH(runner, "tree_finished");
	runner->set_root_task(wait(0));
	CHECK(runner->tick(0) == BehaviorTreeTask::SUCCESS);
	SIGNAL_CHECK("tree_finished", { { int(BehaviorTreeTask::SUCCESS) } });
	CHECK(runner->tick(0) == BehaviorTreeTask::SUCCESS);
	SIGNAL_CHECK_FALSE("tree_finished");
	SIGNAL_UNWATCH(runner, "tree_finished");
	memdelete(runner);
}

TEST_CASE("[BehaviorTree] Resources and their subresources survive a save/load roundtrip") {
	Ref<BehaviorTreeSequence> seq;
	seq.instantiate();
	seq->add_task(assign("mode", 3));
	seq->add_task(check("mode", 3));
	const String path = TestUtils::get_temp_path("behavior_tree_roundtrip.tres");
	REQUIRE(ResourceSaver::save(seq, path) == OK);
	Ref<BehaviorTreeSequence> loaded = ResourceLoader::load(path);
	REQUIRE(loaded.is_valid());
	CHECK(loaded->get_task_count() == 2);
	RunnerHolder runner;
	runner.set_root_task(loaded);
	CHECK(runner.tick(0) == BehaviorTreeTask::SUCCESS);
	CHECK(int(runner.get_blackboard()["mode"]) == 3);
}

} // namespace TestBehaviorTree

#endif // MODULE_BEHAVIOR_TREE_ENABLED
