/**************************************************************************/
/*  behavior_tree.h                                                       */
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

#include "core/io/resource.h"
#include "core/object/gdvirtual.gen.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"
#include "scene/main/node.h"

/**
 * Stateless behavior task. User-defined tasks override _tick in GDScript.
 * Per-runner execution cursors are held separately by BehaviorTreeRunner.
 */
class BehaviorTreeTask : public Resource {
	GDCLASS(BehaviorTreeTask, Resource);

public:
	enum Status {
		SUCCESS,
		FAILURE,
		RUNNING,
	};

protected:
	static void _bind_methods();
	GDVIRTUAL2R(int, _tick, Dictionary, double);

public:
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta);
	virtual bool contains_task(const BehaviorTreeTask *p_target, int p_depth = 0) const;
};

VARIANT_ENUM_CAST(BehaviorTreeTask::Status);

class BehaviorTreeComposite : public BehaviorTreeTask {
	GDCLASS(BehaviorTreeComposite, BehaviorTreeTask);

	TypedArray<BehaviorTreeTask> tasks;

protected:
	static void _bind_methods();
	static void clear_memory(Dictionary &r_memory, const String &p_path);

public:
	void set_tasks(const TypedArray<BehaviorTreeTask> &p_tasks);
	TypedArray<BehaviorTreeTask> get_tasks() const;
	void add_task(const Ref<BehaviorTreeTask> &p_task);
	void remove_task(int p_index);
	void clear_tasks();
	int get_task_count() const { return tasks.size(); }
	Ref<BehaviorTreeTask> get_task(int p_index) const;
	virtual bool contains_task(const BehaviorTreeTask *p_target, int p_depth = 0) const override;
};

class BehaviorTreeSequence : public BehaviorTreeComposite {
	GDCLASS(BehaviorTreeSequence, BehaviorTreeComposite);

protected:
	static void _bind_methods() {}

public:
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

class BehaviorTreeSelector : public BehaviorTreeComposite {
	GDCLASS(BehaviorTreeSelector, BehaviorTreeComposite);

protected:
	static void _bind_methods() {}

public:
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

class BehaviorTreeInverter : public BehaviorTreeTask {
	GDCLASS(BehaviorTreeInverter, BehaviorTreeTask);

	Ref<BehaviorTreeTask> task;

protected:
	static void _bind_methods();

public:
	void set_task(const Ref<BehaviorTreeTask> &p_task);
	Ref<BehaviorTreeTask> get_task() const { return task; }
	virtual bool contains_task(const BehaviorTreeTask *p_target, int p_depth = 0) const override;
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

/** Built-in leaf that checks a blackboard value. */
class BehaviorTreeBlackboardCheck : public BehaviorTreeTask {
	GDCLASS(BehaviorTreeBlackboardCheck, BehaviorTreeTask);

	StringName key;
	Variant expected_value;

protected:
	static void _bind_methods();

public:
	void set_key(const StringName &p_key) { key = p_key; emit_changed(); }
	StringName get_key() const { return key; }
	void set_expected_value(const Variant &p_value) { expected_value = p_value; emit_changed(); }
	Variant get_expected_value() const { return expected_value; }
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

/** Built-in leaf that writes a blackboard value. */
class BehaviorTreeBlackboardSet : public BehaviorTreeTask {
	GDCLASS(BehaviorTreeBlackboardSet, BehaviorTreeTask);

	StringName key;
	Variant value;

protected:
	static void _bind_methods();

public:
	void set_key(const StringName &p_key) { key = p_key; emit_changed(); }
	StringName get_key() const { return key; }
	void set_value(const Variant &p_value) { value = p_value; emit_changed(); }
	Variant get_value() const { return value; }
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

/** Time-based leaf whose elapsed time is scoped to the owning runner. */
class BehaviorTreeWait : public BehaviorTreeTask {
	GDCLASS(BehaviorTreeWait, BehaviorTreeTask);

	double duration = 1.0;

protected:
	static void _bind_methods();

public:
	void set_duration(double p_duration);
	double get_duration() const { return duration; }
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

class BehaviorTreeRunner : public Node {
	GDCLASS(BehaviorTreeRunner, Node);

	Ref<BehaviorTreeTask> root_task;
	Dictionary blackboard;
	Dictionary execution_memory;
	BehaviorTreeTask::Status last_status = BehaviorTreeTask::RUNNING;
	bool auto_tick = false;
	bool finished = false;

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	void set_root_task(const Ref<BehaviorTreeTask> &p_task);
	Ref<BehaviorTreeTask> get_root_task() const { return root_task; }
	void set_blackboard(const Dictionary &p_blackboard) { blackboard = p_blackboard; }
	Dictionary get_blackboard() const { return blackboard; }
	void set_auto_tick(bool p_enabled);
	bool is_auto_tick_enabled() const { return auto_tick; }
	BehaviorTreeTask::Status tick(double p_delta);
	void reset();
	bool is_finished() const { return finished; }
	BehaviorTreeTask::Status get_last_status() const { return last_status; }

	BehaviorTreeRunner();
};
