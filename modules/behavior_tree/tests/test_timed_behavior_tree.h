/**************************************************************************/
/*  test_timed_behavior_tree.h                                                  */
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
#include "../ai_action_cooldowns.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestTimedBehaviorTree {

TEST_CASE("[BehaviorTreeTimed] Timeout fails and erases a running subtree at its deadline") {
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(5.0);
	Ref<BehaviorTreeTimeout> timeout;
	timeout.instantiate();
	timeout->set_task(wait);
	timeout->set_duration(0.5);
	Dictionary memory;
	Dictionary blackboard;
	CHECK(timeout->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK(memory.has("root"));
	CHECK(memory.has("root/0"));
	CHECK(timeout->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK(timeout->execute(blackboard, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	CHECK(memory.is_empty());
	CHECK(timeout->execute(blackboard, memory, "root", 0.1) == BehaviorTreeTask::RUNNING);
}

TEST_CASE("[BehaviorTreeTimed] Timeout preserves early child success and failure") {
	Ref<BehaviorTreeBlackboardCheck> check;
	check.instantiate();
	check->set_key(SNAME("allowed"));
	check->set_expected_value(true);
	Ref<BehaviorTreeTimeout> timeout;
	timeout.instantiate();
	timeout->set_task(check);
	timeout->set_duration(2.0);
	Dictionary blackboard, memory;
	CHECK(timeout->execute(blackboard, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	CHECK(memory.is_empty());
	blackboard["allowed"] = true;
	CHECK(timeout->execute(blackboard, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(memory.is_empty());
}

TEST_CASE("[BehaviorTreeTimed] Zero timeout fails even for an instant-success child") {
	Ref<BehaviorTreeBlackboardSet> success;
	success.instantiate();
	success->set_key(SNAME("flag"));
	success->set_value(true);
	Ref<BehaviorTreeTimeout> timeout;
	timeout.instantiate();
	timeout->set_task(success);
	timeout->set_duration(0.0);
	Dictionary blackboard, memory;
	CHECK(timeout->execute(blackboard, memory, "root", 0.0) == BehaviorTreeTask::FAILURE);
	CHECK_FALSE(blackboard.has("flag"));
	CHECK(memory.is_empty());
}

TEST_CASE("[BehaviorTreeTimed] Timeout clears only its own branch memory") {
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(3.0);
	Ref<BehaviorTreeTimeout> timeout;
	timeout.instantiate();
	timeout->set_task(wait);
	timeout->set_duration(0.2);
	Dictionary memory, blackboard;
	memory["sibling"] = 900;
	memory["root/0/older"] = 5;
	CHECK(timeout->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::FAILURE);
	CHECK(memory.size() == 1);
	CHECK(memory["sibling"] == 900);
}

TEST_CASE("[BehaviorTreeTimed] Cooldown follows child success and blocks repeat") {
	Ref<BehaviorTreeBlackboardCheck> check;
	check.instantiate();
	check->set_key(SNAME("allowed"));
	check->set_expected_value(true);
	Ref<BehaviorTreeCooldown> cooldown;
	cooldown.instantiate();
	cooldown->set_task(check);
	cooldown->set_duration(1.0);
	Dictionary blackboard, memory;
	blackboard["allowed"] = true;
	CHECK(cooldown->execute(blackboard, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(memory.has("root"));
	CHECK(cooldown->execute(blackboard, memory, "root", 0.25) == BehaviorTreeTask::FAILURE);
	CHECK(double(memory["root"]) == doctest::Approx(0.75));
	CHECK(cooldown->execute(blackboard, memory, "root", 0.75) == BehaviorTreeTask::SUCCESS);
	CHECK(double(memory["root"]) == doctest::Approx(1.0));
}

TEST_CASE("[BehaviorTreeTimed] Child failure does not begin a cooldown") {
	Ref<BehaviorTreeBlackboardCheck> check;
	check.instantiate();
	check->set_key(SNAME("allow"));
	check->set_expected_value(true);
	Ref<BehaviorTreeCooldown> cooldown;
	cooldown.instantiate();
	cooldown->set_task(check);
	cooldown->set_duration(2.0);
	Dictionary blackboard, memory;
	CHECK(cooldown->execute(blackboard, memory, "root", 0.1) == BehaviorTreeTask::FAILURE);
	CHECK(memory.is_empty());
	blackboard["allow"] = true;
	CHECK(cooldown->execute(blackboard, memory, "root", 0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(memory.has("root"));
}

TEST_CASE("[BehaviorTreeTimed] Running child is not interrupted by its own cooldown") {
	Ref<BehaviorTreeWait> wait;
	wait.instantiate();
	wait->set_duration(0.4);
	Ref<BehaviorTreeCooldown> cooldown;
	cooldown.instantiate();
	cooldown->set_task(wait);
	cooldown->set_duration(0.6);
	Dictionary blackboard, memory;
	CHECK(cooldown->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::RUNNING);
	CHECK_FALSE(memory.has("root"));
	CHECK(memory.has("root/0"));
	CHECK(cooldown->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::SUCCESS);
	CHECK_FALSE(memory.has("root/0"));
	CHECK(cooldown->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::FAILURE);
	CHECK(cooldown->execute(blackboard, memory, "root", 0.4) == BehaviorTreeTask::RUNNING);
}

TEST_CASE("[BehaviorTreeTimed] Shared task resources have independent runner memories") {
	Ref<BehaviorTreeBlackboardCheck> check;
	check.instantiate();
	check->set_key(SNAME("can_use"));
	check->set_expected_value(true);
	Ref<BehaviorTreeCooldown> cooldown;
	cooldown.instantiate();
	cooldown->set_task(check);
	cooldown->set_duration(1.0);
	Dictionary blackboard, first, second;
	blackboard["can_use"] = true;
	CHECK(cooldown->execute(blackboard, first, "root/1", 0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(cooldown->execute(blackboard, first, "root/1", 0.2) == BehaviorTreeTask::FAILURE);
	CHECK(cooldown->execute(blackboard, second, "root/1", 0.2) == BehaviorTreeTask::SUCCESS);
	CHECK(second.has("root/1"));
	CHECK(first.has("root/1"));
}

TEST_CASE("[BehaviorTreeTimed] Task graph cycles are rejected through timed decorators") {
	Ref<BehaviorTreeTimeout> timeout;
	timeout.instantiate();
	Ref<BehaviorTreeCooldown> cooldown;
	cooldown.instantiate();
	timeout->set_task(cooldown);
	ERR_PRINT_OFF;
	cooldown->set_task(timeout);
	ERR_PRINT_ON;
	CHECK(cooldown->get_task().is_null());
	CHECK(timeout->get_task() == cooldown);
}

TEST_CASE("[BehaviorTreeTimed] Invalid duration and missing children fail safely") {
	Ref<BehaviorTreeTimeout> timeout;
	timeout.instantiate();
	Ref<BehaviorTreeCooldown> cooldown;
	cooldown.instantiate();
	ERR_PRINT_OFF;
	timeout->set_duration(-1.0);
	timeout->set_duration(Math::NaN);
	cooldown->set_duration(-1.0);
	cooldown->set_duration(Math::INF);
	ERR_PRINT_ON;
	CHECK(timeout->get_duration() == 1.0);
	CHECK(cooldown->get_duration() == 1.0);
	Dictionary blackboard, memory;
	CHECK(timeout->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::FAILURE);
	CHECK(cooldown->execute(blackboard, memory, "root", 0.2) == BehaviorTreeTask::FAILURE);
	CHECK(memory.is_empty());
}

TEST_CASE("[BehaviorTreeTimed] Runner reset intentionally clears cooldown") {
	BehaviorTreeRunner *runner = memnew(BehaviorTreeRunner);
	Ref<BehaviorTreeBlackboardSet> set;
	set.instantiate();
	set->set_key(SNAME("ready"));
	set->set_value(true);
	Ref<BehaviorTreeCooldown> cooldown;
	cooldown.instantiate();
	cooldown->set_task(set);
	cooldown->set_duration(2.0);
	runner->set_root_task(cooldown);
	CHECK(runner->tick(0.1) == BehaviorTreeTask::SUCCESS);
	CHECK(runner->get_debug_snapshot()["finished"] == true);
	runner->reset();
	CHECK(runner->tick(0.1) == BehaviorTreeTask::SUCCESS);
	memdelete(runner);
}

TEST_CASE("[AIActionCooldowns] Same-action gate blocks repeat until simulated time expires") {
	Ref<AIActionCooldowns> actions;
	actions.instantiate();
	CHECK(actions->try_trigger(SNAME("howl"), 1.0));
	CHECK_FALSE(actions->try_trigger(SNAME("howl"), 1.0));
	CHECK(actions->get_remaining(SNAME("howl")) == 1.0);
	actions->advance_time(0.4);
	CHECK_FALSE(actions->try_trigger(SNAME("howl"), 1.0));
	actions->advance_time(0.6);
	CHECK(actions->try_trigger(SNAME("howl"), 1.0));
}

TEST_CASE("[AIActionCooldowns] Independent event keys and instances never interfere") {
	Ref<AIActionCooldowns> a, b;
	a.instantiate();
	b.instantiate();
	CHECK(a->try_trigger(SNAME("howl"), 1.0));
	CHECK(a->try_trigger(SNAME("stagger"), 2.0));
	CHECK(b->try_trigger(SNAME("howl"), 1.0));
	CHECK_FALSE(a->try_trigger(SNAME("howl"), 1.0));
	CHECK(a->get_remaining(SNAME("stagger")) == 2.0);
	CHECK(b->get_remaining(SNAME("stagger")) == 0.0);
}

TEST_CASE("[AIActionCooldowns] Snapshot isolation and reset") {
	Ref<AIActionCooldowns> actions;
	actions.instantiate();
	CHECK(actions->try_trigger(SNAME("howl"), 3.0));
	Dictionary snapshot = actions->get_snapshot();
	snapshot[SNAME("howl")] = 1000.0;
	CHECK(actions->get_remaining(SNAME("howl")) == 3.0);
	actions->reset();
	CHECK(actions->get_remaining(SNAME("howl")) == 0.0);
	CHECK(actions->get_snapshot().is_empty());
	CHECK(actions->try_trigger(SNAME("howl"), 0.0));
	CHECK(actions->get_snapshot().is_empty());
}

TEST_CASE("[AIActionCooldowns] Invalid inputs and bounded event keys fail closed") {
	Ref<AIActionCooldowns> actions;
	actions.instantiate();
	ERR_PRINT_OFF;
	CHECK_FALSE(actions->try_trigger(StringName(), 1.0));
	CHECK_FALSE(actions->try_trigger(SNAME("x"), -1.0));
	CHECK_FALSE(actions->try_trigger(SNAME("x"), Math::NaN));
	CHECK_FALSE(actions->try_trigger(SNAME("x"), 3601.0));
	actions->advance_time(-2.0);
	ERR_PRINT_ON;
	CHECK(actions->get_snapshot().is_empty());
	for (int i = 0; i < 16; ++i) {
		CHECK(actions->try_trigger(StringName("k" + itos(i)), 5.0));
	}
	ERR_PRINT_OFF;
	CHECK_FALSE(actions->try_trigger(SNAME("overflow"), 5.0));
	ERR_PRINT_ON;
	CHECK(actions->get_snapshot().size() == 16);
	actions->advance_time(6.0);
	CHECK(actions->get_snapshot().is_empty());
	CHECK(actions->try_trigger(SNAME("overflow"), 5.0));
}

} // namespace TestTimedBehaviorTree
