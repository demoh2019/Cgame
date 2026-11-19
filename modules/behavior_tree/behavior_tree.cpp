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
		const Status status = task->execute(p_blackboard, r_memory, p_path + "/" + itos(index), p_delta);
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
		const Status status = task->execute(p_blackboard, r_memory, p_path + "/" + itos(index), p_delta);
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
	const Status status = task->execute(p_blackboard, r_memory, p_path + "/0", p_delta);
	if (status == SUCCESS) {
		return FAILURE;
	}
	if (status == FAILURE) {
		return SUCCESS;
	}
	return RUNNING;
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

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "root_task", PROPERTY_HINT_RESOURCE_TYPE, "BehaviorTreeTask"), "set_root_task", "get_root_task");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "blackboard"), "set_blackboard", "get_blackboard");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_tick"), "set_auto_tick", "is_auto_tick_enabled");
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
	last_status = root_task->execute(blackboard, execution_memory, "root", p_delta);
	if (last_status != BehaviorTreeTask::RUNNING) {
		finished = true;
		execution_memory.clear();
		emit_signal(SNAME("tree_finished"), int(last_status));
	}
	return last_status;
}

void BehaviorTreeRunner::reset() {
	execution_memory.clear();
	finished = false;
	last_status = BehaviorTreeTask::RUNNING;
}

BehaviorTreeRunner::BehaviorTreeRunner() {
	set_process(false);
}
