/**************************************************************************/
/*  behavior_tree.cpp                                                     */
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

#include "behavior_tree.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void BehaviorTreeTask::_bind_methods() {
	GDVIRTUAL_BIND(_tick, "blackboard", "delta");

	BIND_ENUM_CONSTANT(SUCCESS);
	BIND_ENUM_CONSTANT(FAILURE);
	BIND_ENUM_CONSTANT(RUNNING);
}

BehaviorTreeTask::Status BehaviorTreeTask::execute(const Dictionary &p_blackboard, Dictionary &, const String &, double p_delta) {
	int result = FAILURE;
	if (GDVIRTUAL_CALL(_tick, p_blackboard, p_delta, result)) {
		if (result >= SUCCESS && result <= RUNNING) {
			return static_cast<Status>(result);
		}
		ERR_PRINT("BehaviorTreeTask._tick() must return SUCCESS, FAILURE, or RUNNING.");
	}
	return FAILURE;
}

BehaviorTreeTask::Status BehaviorTreeTask::execute_traced(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) {
	// A single cheap Dictionary key test for normal non-debug gameplay;
	// only explicitly traced runners read clocks or construct step records.
	if (!r_memory.has(SNAME("__bt_trace_sink"))) {
		return execute(p_blackboard, r_memory, p_path, p_delta);
	}
	Ref<AIBehaviorTrace> trace = r_memory.get(SNAME("__bt_trace_sink"), Variant());
	if (trace.is_null()) {
		return execute(p_blackboard, r_memory, p_path, p_delta);
	}
	const int token = trace->begin_step(p_path, String(get_class()));
	const Status status = execute(p_blackboard, r_memory, p_path, p_delta);
	if (token >= 0) {
		trace->end_step(token, int(status));
	}
	return status;
}

bool BehaviorTreeTask::contains_task(const BehaviorTreeTask *p_target, int p_depth) const {
	return this == p_target || p_depth >= 64;
}

void BehaviorTreeComposite::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_tasks", "tasks"), &BehaviorTreeComposite::set_tasks);
	ClassDB::bind_method(D_METHOD("get_tasks"), &BehaviorTreeComposite::get_tasks);
	ClassDB::bind_method(D_METHOD("add_task", "task"), &BehaviorTreeComposite::add_task);
	ClassDB::bind_method(D_METHOD("remove_task", "index"), &BehaviorTreeComposite::remove_task);
	ClassDB::bind_method(D_METHOD("clear_tasks"), &BehaviorTreeComposite::clear_tasks);
	ClassDB::bind_method(D_METHOD("get_task_count"), &BehaviorTreeComposite::get_task_count);
	ClassDB::bind_method(D_METHOD("get_task", "index"), &BehaviorTreeComposite::get_task);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "tasks", PROPERTY_HINT_ARRAY_TYPE, "BehaviorTreeTask"), "set_tasks", "get_tasks");
}

void BehaviorTreeComposite::set_tasks(const TypedArray<BehaviorTreeTask> &p_tasks) {
	for (int i = 0; i < p_tasks.size(); i++) {
		Ref<BehaviorTreeTask> task = p_tasks[i];
		ERR_FAIL_COND_MSG(task.is_null(), "A behavior tree cannot contain null tasks.");
		ERR_FAIL_COND_MSG(task->contains_task(this), "A behavior tree cannot contain itself through a descendant.");
	}
	tasks.clear();
	for (int i = 0; i < p_tasks.size(); i++) {
		tasks.push_back(p_tasks[i]);
	}
	emit_changed();
}

TypedArray<BehaviorTreeTask> BehaviorTreeComposite::get_tasks() const {
	// Do not expose the mutable backing array: all updates must validate cycles.
	TypedArray<BehaviorTreeTask> result;
	for (int i = 0; i < tasks.size(); i++) {
		result.push_back(tasks[i]);
	}
	return result;
}

void BehaviorTreeComposite::add_task(const Ref<BehaviorTreeTask> &p_task) {
	ERR_FAIL_COND_MSG(p_task.is_null(), "A behavior tree cannot contain null tasks.");
	ERR_FAIL_COND_MSG(p_task->contains_task(this), "A behavior tree cannot contain itself through a descendant.");
	tasks.push_back(p_task);
	emit_changed();
}

void BehaviorTreeComposite::remove_task(int p_index) {
	ERR_FAIL_INDEX(p_index, tasks.size());
	tasks.remove_at(p_index);
	emit_changed();
}

void BehaviorTreeComposite::clear_tasks() {
	if (tasks.is_empty()) {
		return;
	}
	tasks.clear();
	emit_changed();
}

Ref<BehaviorTreeTask> BehaviorTreeComposite::get_task(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, tasks.size(), Ref<BehaviorTreeTask>());
	return tasks[p_index];
}

bool BehaviorTreeComposite::contains_task(const BehaviorTreeTask *p_target, int p_depth) const {
	if (BehaviorTreeTask::contains_task(p_target, p_depth)) {
		return true;
	}
	for (int i = 0; i < tasks.size(); i++) {
		Ref<BehaviorTreeTask> task = tasks[i];
		if (task.is_valid() && task->contains_task(p_target, p_depth + 1)) {
			return true;
		}
	}
	return false;
}

void BehaviorTreeComposite::clear_memory(Dictionary &r_memory, const String &p_path) {
	// Remove cursors in this subtree without affecting sibling branches.
	const Array keys = r_memory.keys();
	for (int i = 0; i < keys.size(); i++) {
		const String path = keys[i];
		if (path == p_path || path.begins_with(p_path + "/")) {
			r_memory.erase(path);
		}
	}
}

BehaviorTreeTask::Status BehaviorTreeSequence::execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) {
	const int count = get_task_count();
	int index = static_cast<int>(r_memory.get(p_path, 0));
	if (index < 0 || index >= count) {
		index = 0;
	}

	for (; index < count; index++) {
		const Ref<BehaviorTreeTask> task = get_task(index);
		if (task.is_null()) {
			clear_memory(r_memory, p_path);
			return FAILURE;
		}
		const Status status = task->execute_traced(p_blackboard, r_memory, p_path + "/" + itos(index), p_delta);
		if (status == RUNNING) {
			r_memory[p_path] = index;
			return RUNNING;
		}
		if (status == FAILURE) {
			clear_memory(r_memory, p_path);
			return FAILURE;
		}
	}
	clear_memory(r_memory, p_path);
	return SUCCESS;
}

BehaviorTreeTask::Status BehaviorTreeSelector::execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) {
	const int count = get_task_count();
	int index = static_cast<int>(r_memory.get(p_path, 0));
	if (index < 0 || index >= count) {
		index = 0;
	}

	for (; index < count; index++) {
		const Ref<BehaviorTreeTask> task = get_task(index);
		if (task.is_null()) {
			clear_memory(r_memory, p_path);
			return FAILURE;
		}
		const Status status = task->execute_traced(p_blackboard, r_memory, p_path + "/" + itos(index), p_delta);
		if (status == RUNNING) {
			r_memory[p_path] = index;
			return RUNNING;
		}
		if (status == SUCCESS) {
			clear_memory(r_memory, p_path);
			return SUCCESS;
		}
	}
	clear_memory(r_memory, p_path);
	return FAILURE;
}

BehaviorTreeTask::Status BehaviorTreeReactiveSequence::execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) {
	const int count = get_task_count();
	const int previous_running = static_cast<int>(r_memory.get(p_path, -1));
	for (int i = 0; i < count; i++) {
		const Ref<BehaviorTreeTask> task = get_task(i);
		if (task.is_null()) {
			clear_memory(r_memory, p_path);
			return FAILURE;
		}
		const Status status = task->execute_traced(p_blackboard, r_memory, p_path + "/" + itos(i), p_delta);
		if (status == RUNNING) {
			if (previous_running >= 0 && previous_running != i) {
				clear_memory(r_memory, p_path + "/" + itos(previous_running));
			}
			r_memory[p_path] = i;
			return RUNNING;
		}
		if (status == FAILURE) {
			clear_memory(r_memory, p_path);
			return FAILURE;
		}
	}
	clear_memory(r_memory, p_path);
	return SUCCESS;
}

BehaviorTreeTask::Status BehaviorTreeReactiveSelector::execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) {
	const int count = get_task_count();
	const int previous_running = static_cast<int>(r_memory.get(p_path, -1));
	for (int i = 0; i < count; i++) {
		const Ref<BehaviorTreeTask> task = get_task(i);
		if (task.is_null()) {
			clear_memory(r_memory, p_path);
			return FAILURE;
		}
		const Status status = task->execute_traced(p_blackboard, r_memory, p_path + "/" + itos(i), p_delta);
		if (status == RUNNING) {
			if (previous_running >= 0 && previous_running != i) {
				clear_memory(r_memory, p_path + "/" + itos(previous_running));
			}
			r_memory[p_path] = i;
			return RUNNING;
		}
		if (status == SUCCESS) {
			clear_memory(r_memory, p_path);
			return SUCCESS;
		}
	}
	clear_memory(r_memory, p_path);
	return FAILURE;
}

void BehaviorTreeInverter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_task", "task"), &BehaviorTreeInverter::set_task);
	ClassDB::bind_method(D_METHOD("get_task"), &BehaviorTreeInverter::get_task);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "task", PROPERTY_HINT_RESOURCE_TYPE, "BehaviorTreeTask"), "set_task", "get_task");
}

void BehaviorTreeInverter::set_task(const Ref<BehaviorTreeTask> &p_task) {
	ERR_FAIL_COND_MSG(p_task.is_valid() && p_task->contains_task(this), "A behavior tree cannot contain itself through a descendant.");
	task = p_task;
	emit_changed();
}

bool BehaviorTreeInverter::contains_task(const BehaviorTreeTask *p_target, int p_depth) const {
	return BehaviorTreeTask::contains_task(p_target, p_depth) || (task.is_valid() && task->contains_task(p_target, p_depth + 1));
}

BehaviorTreeTask::Status BehaviorTreeInverter::execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) {
	if (task.is_null()) {
		return FAILURE;
	}
	const Status status = task->execute_traced(p_blackboard, r_memory, p_path + "/0", p_delta);
	if (status == SUCCESS) {
		return FAILURE;
	}
	if (status == FAILURE) {
		return SUCCESS;
	}
	return RUNNING;
}

void BehaviorTreeDecorator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_task", "task"), &BehaviorTreeDecorator::set_task);
	ClassDB::bind_method(D_METHOD("get_task"), &BehaviorTreeDecorator::get_task);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "task", PROPERTY_HINT_RESOURCE_TYPE, "BehaviorTreeTask"), "set_task", "get_task");
}

void BehaviorTreeDecorator::set_task(const Ref<BehaviorTreeTask> &p_task) {
	ERR_FAIL_COND_MSG(p_task.is_valid() && p_task->contains_task(this), "A decorator cannot contain itself through a descendant.");
	task = p_task;
	emit_changed();
}

bool BehaviorTreeDecorator::contains_task(const BehaviorTreeTask *p_target, int p_depth) const {
	const Ref<BehaviorTreeTask> child = task;
	return BehaviorTreeTask::contains_task(p_target, p_depth) ||
			(child.is_valid() && child->contains_task(p_target, p_depth + 1));
}

void BehaviorTreeDecorator::clear_branch_memory(Dictionary &r_memory, const String &p_path) {
	// Forget only this decorator and its descendants; never touch sibling
	// instances of the same shared Resource used elsewhere in a tree.
	const Array keys = r_memory.keys();
	for (int i = 0; i < keys.size(); ++i) {
		const String key = keys[i];
		if (key == p_path || key.begins_with(p_path + "/")) {
			r_memory.erase(key);
		}
	}
}

void BehaviorTreeTimeout::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_duration", "duration"), &BehaviorTreeTimeout::set_duration);
	ClassDB::bind_method(D_METHOD("get_duration"), &BehaviorTreeTimeout::get_duration);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "duration", PROPERTY_HINT_RANGE, "0,3600,0.01,or_greater,suffix:s"), "set_duration", "get_duration");
}

void BehaviorTreeTimeout::set_duration(double p_duration) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_duration) || p_duration < 0.0, "BehaviorTreeTimeout.duration must be finite and nonnegative.");
	duration = p_duration;
	emit_changed();
}

BehaviorTreeTask::Status BehaviorTreeTimeout::execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) {
	const Ref<BehaviorTreeTask> child = get_task();
	if (child.is_null()) {
		clear_branch_memory(r_memory, p_path);
		return FAILURE;
	}
	const double safe_delta = Math::is_finite(p_delta) ? MAX(0.0, p_delta) : 0.0;
	const double elapsed = double(r_memory.get(p_path, 0.0)) + safe_delta;
	// A deadline at exactly duration expires before evaluating the child;
	// a zero-second limit always fails, including for instant children.
	if (elapsed >= duration) {
		clear_branch_memory(r_memory, p_path);
		return FAILURE;
	}
	const Status status = child->execute_traced(p_blackboard, r_memory, p_path + "/0", safe_delta);
	if (status == RUNNING) {
		r_memory[p_path] = elapsed;
	} else {
		clear_branch_memory(r_memory, p_path);
	}
	return status;
}

void BehaviorTreeCooldown::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_duration", "duration"), &BehaviorTreeCooldown::set_duration);
	ClassDB::bind_method(D_METHOD("get_duration"), &BehaviorTreeCooldown::get_duration);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "duration", PROPERTY_HINT_RANGE, "0,3600,0.01,or_greater,suffix:s"), "set_duration", "get_duration");
}

void BehaviorTreeCooldown::set_duration(double p_duration) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_duration) || p_duration < 0.0, "BehaviorTreeCooldown.duration must be finite and nonnegative.");
	duration = p_duration;
	emit_changed();
}

BehaviorTreeTask::Status BehaviorTreeCooldown::execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) {
	const Ref<BehaviorTreeTask> child = get_task();
	if (child.is_null()) {
		clear_branch_memory(r_memory, p_path);
		return FAILURE;
	}
	const double safe_delta = Math::is_finite(p_delta) ? MAX(0.0, p_delta) : 0.0;
	if (r_memory.has(p_path)) {
		const double remaining = MAX(0.0, double(r_memory[p_path]) - safe_delta);
		if (remaining > 0.0) {
			r_memory[p_path] = remaining;
			return FAILURE;
		}
		r_memory.erase(p_path);
	}
	const Status status = child->execute_traced(p_blackboard, r_memory, p_path + "/0", safe_delta);
	if (status != RUNNING) {
		clear_branch_memory(r_memory, p_path);
		if (status == SUCCESS && duration > 0.0) {
			r_memory[p_path] = duration;
		}
	}
	return status;
}

void BehaviorTreeBlackboardCheck::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_key", "key"), &BehaviorTreeBlackboardCheck::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &BehaviorTreeBlackboardCheck::get_key);
	ClassDB::bind_method(D_METHOD("set_expected_value", "value"), &BehaviorTreeBlackboardCheck::set_expected_value);
	ClassDB::bind_method(D_METHOD("get_expected_value"), &BehaviorTreeBlackboardCheck::get_expected_value);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "key"), "set_key", "get_key");
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "expected_value", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT), "set_expected_value", "get_expected_value");
}

BehaviorTreeTask::Status BehaviorTreeBlackboardCheck::execute(const Dictionary &p_blackboard, Dictionary &, const String &, double) {
	if (key.is_empty() || !p_blackboard.has(key)) {
		return FAILURE;
	}
	return p_blackboard[key] == expected_value ? SUCCESS : FAILURE;
}

void BehaviorTreeBlackboardCompare::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_key", "key"), &BehaviorTreeBlackboardCompare::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &BehaviorTreeBlackboardCompare::get_key);
	ClassDB::bind_method(D_METHOD("set_other_key", "key"), &BehaviorTreeBlackboardCompare::set_other_key);
	ClassDB::bind_method(D_METHOD("get_other_key"), &BehaviorTreeBlackboardCompare::get_other_key);
	ClassDB::bind_method(D_METHOD("set_value", "value"), &BehaviorTreeBlackboardCompare::set_value);
	ClassDB::bind_method(D_METHOD("get_value"), &BehaviorTreeBlackboardCompare::get_value);
	ClassDB::bind_method(D_METHOD("set_comparison", "comparison"), &BehaviorTreeBlackboardCompare::set_comparison);
	ClassDB::bind_method(D_METHOD("get_comparison"), &BehaviorTreeBlackboardCompare::get_comparison);
	ClassDB::bind_method(D_METHOD("set_use_other_key", "enabled"), &BehaviorTreeBlackboardCompare::set_use_other_key);
	ClassDB::bind_method(D_METHOD("is_using_other_key"), &BehaviorTreeBlackboardCompare::is_using_other_key);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "key"), "set_key", "get_key");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "comparison", PROPERTY_HINT_ENUM, "Equal,Not Equal,Less,Less or Equal,Greater,Greater or Equal,Exists,Not Exists"), "set_comparison", "get_comparison");
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "value", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT), "set_value", "get_value");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_other_key"), "set_use_other_key", "is_using_other_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "other_key"), "set_other_key", "get_other_key");

	BIND_ENUM_CONSTANT(EQUAL);
	BIND_ENUM_CONSTANT(NOT_EQUAL);
	BIND_ENUM_CONSTANT(LESS);
	BIND_ENUM_CONSTANT(LESS_OR_EQUAL);
	BIND_ENUM_CONSTANT(GREATER);
	BIND_ENUM_CONSTANT(GREATER_OR_EQUAL);
	BIND_ENUM_CONSTANT(EXISTS);
	BIND_ENUM_CONSTANT(NOT_EXISTS);
}

void BehaviorTreeBlackboardCompare::set_comparison(Comparison p_comparison) {
	ERR_FAIL_COND_MSG(p_comparison < EQUAL || p_comparison > NOT_EXISTS, "Invalid blackboard comparison.");
	comparison = p_comparison;
	emit_changed();
}

BehaviorTreeTask::Status BehaviorTreeBlackboardCompare::execute(const Dictionary &p_blackboard, Dictionary &, const String &, double) {
	if (key.is_empty()) {
		return FAILURE;
	}
	if (comparison == EXISTS) {
		return p_blackboard.has(key) ? SUCCESS : FAILURE;
	}
	if (comparison == NOT_EXISTS) {
		return p_blackboard.has(key) ? FAILURE : SUCCESS;
	}
	if (!p_blackboard.has(key) || (use_other_key && (other_key.is_empty() || !p_blackboard.has(other_key)))) {
		return FAILURE;
	}
	const Variant left = p_blackboard[key];
	const Variant right = use_other_key ? p_blackboard[other_key] : value;

	if (comparison == EQUAL) {
		return left == right ? SUCCESS : FAILURE;
	}
	if (comparison == NOT_EQUAL) {
		return left != right ? SUCCESS : FAILURE;
	}

	// Only numeric ordering is defined here. Never coerce arbitrary strings,
	// objects, dictionaries or null into numbers for AI decision making.
	const bool left_numeric = left.get_type() == Variant::INT || left.get_type() == Variant::FLOAT;
	const bool right_numeric = right.get_type() == Variant::INT || right.get_type() == Variant::FLOAT;
	if (!left_numeric || !right_numeric) {
		return FAILURE;
	}
	const double a = (double)left;
	const double b = (double)right;
	if (!Math::is_finite(a) || !Math::is_finite(b)) {
		return FAILURE;
	}
	bool matched = false;
	switch (comparison) {
		case LESS: matched = a < b; break;
		case LESS_OR_EQUAL: matched = a <= b; break;
		case GREATER: matched = a > b; break;
		case GREATER_OR_EQUAL: matched = a >= b; break;
		default: return FAILURE;
	}
	return matched ? SUCCESS : FAILURE;
}

void BehaviorTreeBlackboardSet::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_key", "key"), &BehaviorTreeBlackboardSet::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &BehaviorTreeBlackboardSet::get_key);
	ClassDB::bind_method(D_METHOD("set_value", "value"), &BehaviorTreeBlackboardSet::set_value);
	ClassDB::bind_method(D_METHOD("get_value"), &BehaviorTreeBlackboardSet::get_value);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "key"), "set_key", "get_key");
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "value", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT), "set_value", "get_value");
}

BehaviorTreeTask::Status BehaviorTreeBlackboardSet::execute(const Dictionary &p_blackboard, Dictionary &, const String &, double) {
	if (key.is_empty()) {
		return FAILURE;
	}
	// Dictionary is reference counted, so this updates the runner's blackboard
	// without allowing the task to replace the blackboard instance.
	Dictionary writable_blackboard = p_blackboard;
	return writable_blackboard.set(key, value) ? SUCCESS : FAILURE;
}

void BehaviorTreeWait::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_duration", "duration"), &BehaviorTreeWait::set_duration);
	ClassDB::bind_method(D_METHOD("get_duration"), &BehaviorTreeWait::get_duration);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "duration", PROPERTY_HINT_RANGE, "0,3600,0.01,or_greater,suffix:s"), "set_duration", "get_duration");
}

void BehaviorTreeWait::set_duration(double p_duration) {
	ERR_FAIL_COND_MSG(p_duration < 0.0, "BehaviorTreeWait.duration must be nonnegative.");
	duration = p_duration;
	emit_changed();
}

BehaviorTreeTask::Status BehaviorTreeWait::execute(const Dictionary &, Dictionary &r_memory, const String &p_path, double p_delta) {
	const double elapsed = static_cast<double>(r_memory.get(p_path, 0.0)) + MAX(0.0, p_delta);
	if (elapsed >= duration) {
		r_memory.erase(p_path);
		return SUCCESS;
	}
	r_memory[p_path] = elapsed;
	return RUNNING;
}

void BehaviorTreeRunner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_root_task", "task"), &BehaviorTreeRunner::set_root_task);
	ClassDB::bind_method(D_METHOD("get_root_task"), &BehaviorTreeRunner::get_root_task);
	ClassDB::bind_method(D_METHOD("set_blackboard", "blackboard"), &BehaviorTreeRunner::set_blackboard);
	ClassDB::bind_method(D_METHOD("get_blackboard"), &BehaviorTreeRunner::get_blackboard);
	ClassDB::bind_method(D_METHOD("set_auto_tick", "enabled"), &BehaviorTreeRunner::set_auto_tick);
	ClassDB::bind_method(D_METHOD("is_auto_tick_enabled"), &BehaviorTreeRunner::is_auto_tick_enabled);
	ClassDB::bind_method(D_METHOD("tick", "delta"), &BehaviorTreeRunner::tick);
	ClassDB::bind_method(D_METHOD("reset"), &BehaviorTreeRunner::reset);
	ClassDB::bind_method(D_METHOD("is_finished"), &BehaviorTreeRunner::is_finished);
	ClassDB::bind_method(D_METHOD("get_last_status"), &BehaviorTreeRunner::get_last_status);
	ClassDB::bind_method(D_METHOD("get_debug_snapshot"), &BehaviorTreeRunner::get_debug_snapshot);
	ClassDB::bind_method(D_METHOD("set_profiling_enabled", "enabled"), &BehaviorTreeRunner::set_profiling_enabled);
	ClassDB::bind_method(D_METHOD("is_profiling_enabled"), &BehaviorTreeRunner::is_profiling_enabled);
	ClassDB::bind_method(D_METHOD("get_profile_snapshot"), &BehaviorTreeRunner::get_profile_snapshot);
	ClassDB::bind_method(D_METHOD("reset_profile"), &BehaviorTreeRunner::reset_profile);
	ClassDB::bind_method(D_METHOD("set_trace_enabled", "enabled"), &BehaviorTreeRunner::set_trace_enabled);
	ClassDB::bind_method(D_METHOD("is_trace_enabled"), &BehaviorTreeRunner::is_trace_enabled);
	ClassDB::bind_method(D_METHOD("get_trace_snapshot"), &BehaviorTreeRunner::get_trace_snapshot);
	ClassDB::bind_method(D_METHOD("get_tree_snapshot"), &BehaviorTreeRunner::get_tree_snapshot);
	ClassDB::bind_method(D_METHOD("reset_trace"), &BehaviorTreeRunner::reset_trace);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "root_task", PROPERTY_HINT_RESOURCE_TYPE, "BehaviorTreeTask"), "set_root_task", "get_root_task");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "blackboard"), "set_blackboard", "get_blackboard");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_tick"), "set_auto_tick", "is_auto_tick_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "profiling_enabled"), "set_profiling_enabled", "is_profiling_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "trace_enabled"), "set_trace_enabled", "is_trace_enabled");
	ADD_SIGNAL(MethodInfo("tree_finished", PropertyInfo(Variant::INT, "status", PROPERTY_HINT_ENUM, "Success,Failure,Running")));
}

void BehaviorTreeRunner::_notification(int p_what) {
	if (p_what == NOTIFICATION_PROCESS && auto_tick && !finished && root_task.is_valid()) {
		tick(get_process_delta_time());
	}
}

void BehaviorTreeRunner::set_root_task(const Ref<BehaviorTreeTask> &p_task) {
	if (root_task == p_task) {
		return;
	}
	root_task = p_task;
	reset();
}

void BehaviorTreeRunner::set_auto_tick(bool p_enabled) {
	auto_tick = p_enabled;
	set_process(auto_tick);
}

BehaviorTreeTask::Status BehaviorTreeRunner::tick(double p_delta) {
	ERR_FAIL_COND_V_MSG(p_delta < 0.0, BehaviorTreeTask::FAILURE, "BehaviorTreeRunner.tick() requires a nonnegative delta.");
	if (finished) {
		return last_status;
	}
	if (root_task.is_null()) {
		return BehaviorTreeTask::FAILURE;
	}
	// Zero timing overhead on ordinary runners: no clock calls when profiling
	// is disabled. This measures the root execution, including child tasks.
	const bool profiling = execution_profiler.is_valid() && execution_profiler->is_enabled();
	if (profiling) {
		execution_profiler->begin_sample(SNAME("behavior_tree"));
	}
	if (trace_enabled && execution_trace.is_valid()) {
		execution_trace->begin_tick();
		execution_memory[SNAME("__bt_trace_sink")] = execution_trace;
	}
	last_status = root_task->execute_traced(blackboard, execution_memory, "root", p_delta);
	// The context is transient: it never survives in normal execution memory
	// nor appears in snapshots or serialized game state.
	if (trace_enabled) {
		execution_memory.erase(SNAME("__bt_trace_sink"));
	}
	if (profiling) {
		execution_profiler->end_sample(SNAME("behavior_tree"));
	}
	if (last_status != BehaviorTreeTask::RUNNING) {
		finished = true;
		execution_memory.clear();
		emit_signal(SNAME("tree_finished"), int(last_status));
	}
	return last_status;
}

Dictionary BehaviorTreeRunner::get_debug_snapshot() const {
	Dictionary result;
	result["status"] = int(last_status);
	result["finished"] = finished;
	result["auto_tick"] = auto_tick;
	result["root_task_class"] = root_task.is_valid() ? String(root_task->get_class()) : String();
	// Snapshots are made on demand, without bookkeeping on each tick.
	// Nested Dictionaries/Arrays are cloned; Object values still share references.
	// The inspection API is read-only by contract for such Object values.
	result["blackboard"] = blackboard.duplicate(true);
	result["execution_memory"] = execution_memory.duplicate(true);
	result["trace"] = get_trace_snapshot();
	return result;
}

void BehaviorTreeRunner::set_profiling_enabled(bool p_enabled) {
	if (p_enabled && execution_profiler.is_null()) {
		execution_profiler.instantiate();
	}
	if (execution_profiler.is_valid()) {
		execution_profiler->set_enabled(p_enabled);
	}
}

bool BehaviorTreeRunner::is_profiling_enabled() const {
	return execution_profiler.is_valid() && execution_profiler->is_enabled();
}

Dictionary BehaviorTreeRunner::get_profile_snapshot() const {
	if (execution_profiler.is_null()) {
		Dictionary snapshot;
		snapshot["enabled"] = false;
		snapshot["budget_usec"] = int64_t(2000);
		snapshot["total_samples"] = int64_t(0);
		snapshot["categories"] = Dictionary();
		return snapshot;
	}
	return execution_profiler->get_snapshot();
}

void BehaviorTreeRunner::reset_profile() {
	if (execution_profiler.is_valid()) {
		execution_profiler->reset();
	}
}

void BehaviorTreeRunner::set_trace_enabled(bool p_enabled) {
	if (p_enabled && execution_trace.is_null()) {
		execution_trace.instantiate();
	}
	trace_enabled = p_enabled;
	if (!trace_enabled && execution_trace.is_valid()) {
		execution_trace->reset();
	}
}

Dictionary BehaviorTreeRunner::get_trace_snapshot() const {
	Dictionary snapshot;
	if (execution_trace.is_valid()) {
		snapshot = execution_trace->get_snapshot();
	} else {
		snapshot["tick_index"] = int64_t(0);
		snapshot["max_steps"] = 128;
		snapshot["truncated"] = 0;
		snapshot["steps"] = Array();
	}
	snapshot["enabled"] = trace_enabled;
	return snapshot;
}

// Snapshot construction is on demand: no graph traversal during normal NPC
// ticks. One entry per Resource occurrence, including paths never executed in
// the latest tick. Guarded against overdeep and oversized custom graphs.
static void _append_behavior_tree_node(const Ref<BehaviorTreeTask> &p_task, const String &p_path, int p_depth,
		Array &r_nodes, const Dictionary &p_trace_by_path, bool &r_truncated) {
	if (p_task.is_null() || r_truncated) {
		return;
	}
	if (r_nodes.size() >= 256 || p_depth > 64) {
		r_truncated = true;
		return;
	}
	Dictionary node;
	node["path"] = p_path;
	node["task_class"] = String(p_task->get_class());
	node["depth"] = p_depth;
	node["executed"] = false;
	node["status"] = -1;
	node["duration_usec"] = int64_t(0);
	if (p_trace_by_path.has(p_path)) {
		const Dictionary step = p_trace_by_path[p_path];
		node["executed"] = true;
		node["status"] = step.get("status", -1);
		node["duration_usec"] = step.get("duration_usec", int64_t(0));
	}
	r_nodes.push_back(node);

	const Ref<BehaviorTreeComposite> composite = p_task;
	if (composite.is_valid()) {
		for (int index = 0; index < composite->get_task_count(); ++index) {
			_append_behavior_tree_node(composite->get_task(index),
					p_path + "/" + itos(index), p_depth + 1, r_nodes, p_trace_by_path, r_truncated);
			if (r_truncated) {
				break;
			}
		}
	} else {
		Ref<BehaviorTreeTask> child;
		const Ref<BehaviorTreeDecorator> decorator = p_task;
		if (decorator.is_valid()) {
			child = decorator->get_task();
		} else {
			const Ref<BehaviorTreeInverter> inverter = p_task;
			if (inverter.is_valid()) {
				child = inverter->get_task();
			}
		}
		if (child.is_valid()) {
			_append_behavior_tree_node(child, p_path + "/0", p_depth + 1, r_nodes, p_trace_by_path, r_truncated);
		}
	}
}

Dictionary BehaviorTreeRunner::get_tree_snapshot() const {
	Dictionary result;
	Array nodes;
	Dictionary trace_by_path;
	int64_t trace_tick = 0;
	int trace_truncated = 0;
	if (trace_enabled && execution_trace.is_valid()) {
		const Dictionary trace = execution_trace->get_snapshot();
		trace_tick = trace.get("tick_index", int64_t(0));
		trace_truncated = trace.get("truncated", 0);
		const Array steps = trace.get("steps", Array());
		for (int i = 0; i < steps.size(); ++i) {
			const Dictionary step = steps[i];
			trace_by_path[step.get("path", String())] = step;
		}
	}
	bool graph_truncated = false;
	if (root_task.is_valid()) {
		_append_behavior_tree_node(root_task, "root", 0, nodes, trace_by_path, graph_truncated);
	}
	result["nodes"] = nodes;
	result["node_count"] = nodes.size();
	result["truncated"] = graph_truncated;
	result["trace_truncated"] = trace_truncated;
	result["trace_enabled"] = trace_enabled;
	result["tick_index"] = trace_tick;
	return result;
}

void BehaviorTreeRunner::reset_trace() {
	if (execution_trace.is_valid()) {
		execution_trace->reset();
	}
}

void BehaviorTreeRunner::reset() {
	execution_memory.clear();
	finished = false;
	last_status = BehaviorTreeTask::RUNNING;
}

BehaviorTreeRunner::BehaviorTreeRunner() {
	set_process(false);
}
