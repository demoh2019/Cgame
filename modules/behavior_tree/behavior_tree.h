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

#include "ai_execution_profiler.h"
#include "ai_behavior_trace.h"
#include "core/variant/type_info.h"
#include "core/variant/binder_common.h"

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
	// Executes the virtual task normally, but records optional per-node trace.
	// All built-in composites/decorators use this to preserve child paths.
	Status execute_traced(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta);
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

/** Rescans all children every tick, interrupting any abandoned running task. */
class BehaviorTreeReactiveSequence : public BehaviorTreeComposite {
	GDCLASS(BehaviorTreeReactiveSequence, BehaviorTreeComposite);

protected:
	static void _bind_methods() {}

public:
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

/** Rechecks priority from the first child on every tick, preempting old work. */
class BehaviorTreeReactiveSelector : public BehaviorTreeComposite {
	GDCLASS(BehaviorTreeReactiveSelector, BehaviorTreeComposite);

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

/** Single-child decorator with resource-safe cycle detection and runner-local state. */
class BehaviorTreeDecorator : public BehaviorTreeTask {
	GDCLASS(BehaviorTreeDecorator, BehaviorTreeTask);

	Ref<BehaviorTreeTask> task;

protected:
	static void _bind_methods();
	static void clear_branch_memory(Dictionary &r_memory, const String &p_path);

public:
	void set_task(const Ref<BehaviorTreeTask> &p_task);
	Ref<BehaviorTreeTask> get_task() const { return task; }
	virtual bool contains_task(const BehaviorTreeTask *p_target, int p_depth = 0) const override;
};

/** Fails and aborts the child if it does not finish before a time limit. */
class BehaviorTreeTimeout : public BehaviorTreeDecorator {
	GDCLASS(BehaviorTreeTimeout, BehaviorTreeDecorator);

	double duration = 1.0;

protected:
	static void _bind_methods();

public:
	void set_duration(double p_duration);
	double get_duration() const { return duration; }
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

/** Rejects a child for a cooldown window after that child succeeds. */
class BehaviorTreeCooldown : public BehaviorTreeDecorator {
	GDCLASS(BehaviorTreeCooldown, BehaviorTreeDecorator);

	double duration = 1.0;

protected:
	static void _bind_methods();

public:
	void set_duration(double p_duration);
	double get_duration() const { return duration; }
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

/** Configurable Blackboard condition, with optional second-key operand. */
class BehaviorTreeBlackboardCompare : public BehaviorTreeTask {
	GDCLASS(BehaviorTreeBlackboardCompare, BehaviorTreeTask);

public:
	enum Comparison {
		EQUAL,
		NOT_EQUAL,
		LESS,
		LESS_OR_EQUAL,
		GREATER,
		GREATER_OR_EQUAL,
		EXISTS,
		NOT_EXISTS,
	};

private:
	StringName key;
	StringName other_key;
	Variant value;
	Comparison comparison = EQUAL;
	bool use_other_key = false;

protected:
	static void _bind_methods();

public:
	void set_key(const StringName &p_key) { key = p_key; emit_changed(); }
	StringName get_key() const { return key; }
	void set_other_key(const StringName &p_key) { other_key = p_key; emit_changed(); }
	StringName get_other_key() const { return other_key; }
	void set_value(const Variant &p_value) { value = p_value; emit_changed(); }
	Variant get_value() const { return value; }
	void set_comparison(Comparison p_comparison);
	Comparison get_comparison() const { return comparison; }
	void set_use_other_key(bool p_enable) { use_other_key = p_enable; emit_changed(); }
	bool is_using_other_key() const { return use_other_key; }
	virtual Status execute(const Dictionary &p_blackboard, Dictionary &r_memory, const String &p_path, double p_delta) override;
};

VARIANT_ENUM_CAST(BehaviorTreeBlackboardCompare::Comparison);

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
	Ref<AIExecutionProfiler> execution_profiler;
	Ref<AIBehaviorTrace> execution_trace;
	bool trace_enabled = false;

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
	// On-demand diagnostic view; nested containers are copied, Objects stay shared.
	Dictionary get_debug_snapshot() const;
	void set_profiling_enabled(bool p_enabled);
	bool is_profiling_enabled() const;
	Dictionary get_profile_snapshot() const;
	void reset_profile();
	void set_trace_enabled(bool p_enabled);
	bool is_trace_enabled() const { return trace_enabled; }
	Dictionary get_trace_snapshot() const;
	// On-demand hierarchy: all Resource tasks plus latest per-path trace status.
	// Unvisited nodes remain visible with status=-1 and executed=false.
	Dictionary get_tree_snapshot() const;
	void reset_trace();
	// Replay is opt-in even when trace_enabled; 0 retains only current tick.
	void set_trace_history_capacity(int p_capacity);
	int get_trace_history_capacity() const;
	Array get_trace_history_frames(bool p_changes_only = false) const;
	Array get_slowest_trace_nodes(int p_limit = 8) const;

	BehaviorTreeRunner();
};
