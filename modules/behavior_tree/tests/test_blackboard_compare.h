/**************************************************************************/
/*  test_blackboard_compare.h                                                  */
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

namespace TestBehaviorTreeBlackboardCompare {

TEST_CASE("[BehaviorTreeBlackboardCompare] Numeric thresholds are inclusive and typed") {
	Ref<BehaviorTreeBlackboardCompare> condition;
	condition.instantiate();
	condition->set_key(SNAME("health"));
	condition->set_comparison(BehaviorTreeBlackboardCompare::LESS_OR_EQUAL);
	condition->set_value(30);
	Dictionary bb;
	Dictionary memory;
	bb["health"] = 30.0;
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	bb["health"] = 31;
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	condition->set_comparison(BehaviorTreeBlackboardCompare::GREATER);
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	condition->set_comparison(BehaviorTreeBlackboardCompare::GREATER_OR_EQUAL);
	bb["health"] = 30.0;
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	condition->set_comparison(BehaviorTreeBlackboardCompare::LESS);
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	bb["health"] = 29;
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTreeBlackboardCompare] Equality and inequality support nonnumeric data") {
	Ref<BehaviorTreeBlackboardCompare> condition;
	condition.instantiate();
	condition->set_key(SNAME("mode"));
	condition->set_value(String("investigate"));
	Dictionary bb;
	Dictionary memory;
	bb["mode"] = "investigate";
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	condition->set_comparison(BehaviorTreeBlackboardCompare::NOT_EQUAL);
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	bb["mode"] = "patrol";
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	condition->set_comparison(BehaviorTreeBlackboardCompare::GREATER);
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
}

TEST_CASE("[BehaviorTreeBlackboardCompare] Presence differs from null or missing values") {
	Ref<BehaviorTreeBlackboardCompare> condition;
	condition.instantiate();
	condition->set_key(SNAME("target"));
	Dictionary bb;
	Dictionary memory;
	condition->set_comparison(BehaviorTreeBlackboardCompare::EXISTS);
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	bb["target"] = Variant();
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	condition->set_comparison(BehaviorTreeBlackboardCompare::NOT_EXISTS);
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	bb.erase("target");
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTreeBlackboardCompare] Key-to-key comparisons track live values") {
	Ref<BehaviorTreeBlackboardCompare> condition;
	condition.instantiate();
	condition->set_key(SNAME("stamina"));
	condition->set_use_other_key(true);
	condition->set_other_key(SNAME("required_stamina"));
	condition->set_comparison(BehaviorTreeBlackboardCompare::GREATER_OR_EQUAL);
	Dictionary bb;
	Dictionary memory;
	bb["stamina"] = 50;
	bb["required_stamina"] = 40.0;
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	bb["required_stamina"] = 60;
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	bb.erase("required_stamina");
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
}

TEST_CASE("[BehaviorTreeBlackboardCompare] Invalid numeric values and missing keys fail closed") {
	Ref<BehaviorTreeBlackboardCompare> condition;
	condition.instantiate();
	condition->set_key(SNAME("health"));
	condition->set_comparison(BehaviorTreeBlackboardCompare::LESS);
	condition->set_value(40);
	Dictionary bb;
	Dictionary memory;
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	bb["health"] = String("15");
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	bb["health"] = true;
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	bb["health"] = 20.0;
	condition->set_value(String("30"));
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	condition->set_value(30);
	CHECK(condition->execute(bb, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	ERR_PRINT_OFF;
	condition->set_comparison(static_cast<BehaviorTreeBlackboardCompare::Comparison>(100));
	ERR_PRINT_ON;
	CHECK(condition->get_comparison() == BehaviorTreeBlackboardCompare::LESS);
}

TEST_CASE("[BehaviorTree] Debug snapshot is detached from running execution memory") {
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(0.5);
	runner->set_root_task(wait);
	Dictionary bb;
	bb["health"] = 80;
	runner->set_blackboard(bb);
	CHECK(runner->tick(0.2) == BehaviorTreeTask::RUNNING);
	Dictionary snapshot = runner->get_debug_snapshot();
	CHECK(snapshot["status"] == int(BehaviorTreeTask::RUNNING));
	CHECK(snapshot["finished"] == false);
	CHECK(snapshot["root_task_class"] == String("BehaviorTreeWait"));
	Dictionary snapshot_bb = snapshot["blackboard"];
	Dictionary snapshot_memory = snapshot["execution_memory"];
	snapshot_bb["health"] = 1;
	snapshot_memory["root"] = 500.0;
	CHECK(runner->get_blackboard()["health"] == 80);
	CHECK(runner->tick(0.2) == BehaviorTreeTask::RUNNING);
	CHECK(runner->tick(0.2) == BehaviorTreeTask::SUCCESS);
	CHECK(runner->get_debug_snapshot()["finished"] == true);
	memdelete(runner);
}

} // namespace TestBehaviorTreeBlackboardCompare
