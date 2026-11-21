/**************************************************************************/
/*  test_reactive_behavior_tree.h                                                  */
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

namespace TestReactiveBehaviorTree {

TEST_CASE("[BehaviorTree] Reactive sequence reevaluates guards on each tick") {
	Ref<BehaviorTreeReactiveSequence> sequence;
	sequence.instantiate();
	Ref<BehaviorTreeBlackboardCheck> guard;
	guard.instantiate();
	guard->set_key(SNAME("can_chase"));
	guard->set_expected_value(true);
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(0.6);
	sequence->add_task(guard);
	sequence->add_task(wait);

	Dictionary blackboard;
	Dictionary memory;
	blackboard["can_chase"] = true;
	CHECK(sequence->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	blackboard["can_chase"] = false;
	CHECK(sequence->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::FAILURE);
	CHECK(memory.is_empty());

	blackboard["can_chase"] = true;
	CHECK(sequence->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK(sequence->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK(sequence->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::SUCCESS);
	CHECK(memory.is_empty());
}

TEST_CASE("[BehaviorTree] Reactive selector preempts low-priority running wait") {
	Ref<BehaviorTreeReactiveSelector> selector;
	selector.instantiate();
	Ref<BehaviorTreeBlackboardCheck> emergency;
	emergency.instantiate();
	emergency->set_key(SNAME("emergency"));
	emergency->set_expected_value(true);
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(0.5);
	selector->add_task(emergency);
	selector->add_task(wait);

	Dictionary blackboard;
	Dictionary memory;
	CHECK(selector->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	blackboard["emergency"] = true;
	CHECK(selector->execute(blackboard, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(memory.is_empty());

	blackboard["emergency"] = false;
	CHECK(selector->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK(selector->execute(blackboard, memory, "root", 0.3) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] Reactive composites preserve separate runner memories") {
	Ref<BehaviorTreeReactiveSequence> sequence;
	sequence.instantiate();
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(0.5);
	sequence->add_task(wait);

	Dictionary blackboard;
	Dictionary first;
	Dictionary second;
	CHECK(sequence->execute(blackboard, first, "root", 0.3) == BehaviorTreeTask::RUNNING);
	CHECK(sequence->execute(blackboard, first, "root", 0.2) == BehaviorTreeTask::SUCCESS);
	CHECK(sequence->execute(blackboard, second, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK(sequence->execute(blackboard, second, "root", 0.3) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] Reactive selector aborts the previous running subtree") {
	Ref<BehaviorTreeReactiveSelector> selector;
	selector.instantiate();
	Ref<BehaviorTreeReactiveSequence> high_priority;
	high_priority.instantiate();
	Ref<BehaviorTreeBlackboardCheck> guard;
	guard.instantiate();
	guard->set_key(SNAME("priority"));
	guard->set_expected_value(true);
	Ref<BehaviorTreeWait> high_wait;
	high_wait.instantiate();
	high_wait->set_duration(0.5);
	high_priority->add_task(guard);
	high_priority->add_task(high_wait);

	Ref<BehaviorTreeWait> low_wait;
	low_wait.instantiate();
	low_wait->set_duration(0.6);
	selector->add_task(high_priority);
	selector->add_task(low_wait);

	Dictionary blackboard;
	Dictionary memory;
	CHECK(selector->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	blackboard["priority"] = true;
	CHECK(selector->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	blackboard["priority"] = false;
	CHECK(selector->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK(selector->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK(selector->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::SUCCESS);
}

TEST_CASE("[BehaviorTree] Empty reactive composites follow sequence/selector conventions") {
	Ref<BehaviorTreeReactiveSequence> sequence;
	sequence.instantiate();
	Ref<BehaviorTreeReactiveSelector> selector;
	selector.instantiate();
	Dictionary blackboard;
	Dictionary memory;
	CHECK(sequence->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::SUCCESS);
	CHECK(selector->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::FAILURE);
}

} // namespace TestReactiveBehaviorTree
