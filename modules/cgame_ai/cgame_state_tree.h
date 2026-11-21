/**************************************************************************/
/*  cgame_state_tree.h                                                    */
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

#include "cgame_ai_common.h"

#include "core/object/ref_counted.h"

// Hierarchical StateTree runtime (states with enter conditions, tasks,
// evaluators, prioritised transitions and linked subtrees). Assets are plain
// Dictionaries; behaviour is supplied through Callables registered by name,
// which acts as a whitelist (see the class reference for the asset layout).
class CgameStateTree : public RefCounted {
	GDCLASS(CgameStateTree, RefCounted);

public:
	enum Status {
		RUNNING,
		SUCCEEDED,
		FAILED,
	};

	enum {
		MAX_LINK_DEPTH = 8,
	};

private:
	enum Trigger {
		TRIGGER_ON_COMPLETED,
		TRIGGER_ON_FAILED,
		TRIGGER_ON_TICK,
		TRIGGER_ON_EVENT,
		TRIGGER_INVALID,
	};

	struct TaskDef {
		String fn;
		Dictionary args;
	};

	struct TaskReg {
		Callable enter;
		Callable tick;
		Callable exit;
	};

	struct Transition {
		int trigger = TRIGGER_INVALID;
		String event;
		Variant condition;
		String target;
		int priority = 0;
	};

	struct StateNode {
		String id;
		String parent;
		Vector<String> children;
		Vector<TaskDef> tasks;
		Variant conditions;
		Vector<Transition> transitions;
	};

	struct PendingEvent {
		String name;
		Variant payload;
	};

	PackedStringArray errors;
	int tree_status = SUCCEEDED;
	bool running = false;
	PackedStringArray active_path;
	PackedStringArray trace;

	HashMap<String, TaskReg> tasks;
	HashMap<String, Callable> conditions;
	HashMap<String, Callable> evaluators;
	HashMap<String, Dictionary> subtrees;
	Vector<TaskDef> asset_evaluators;
	HashMap<String, StateNode> states;
	String root;
	Vector<PendingEvent> events;
	HashMap<String, Vector<int>> task_status;

	static TaskDef _norm(const Variant &p_value);
	static int _parse_trigger(const String &p_trigger);

	String _flatten(const Dictionary &p_asset, const String &p_prefix, HashMap<String, StateNode> &r_out, int p_depth, Vector<String> &r_errs) const;
	void _check_cond(const Variant &p_cond, const String &p_where, Vector<String> &r_errs) const;
	void _check_cycles(const String &p_id, const HashMap<String, StateNode> &p_out, HashSet<String> &r_visiting, Vector<String> &r_errs) const;
	bool _eval_cond(const Variant &p_cond, const Dictionary &p_ctx) const;
	static bool _compare(const Variant &p_a, const String &p_op, const Variant &p_b);
	Vector<String> _select(const String &p_id, const Dictionary &p_ctx) const;
	void _run_evaluators(double p_dt, const Dictionary &p_ctx);
	void _tick_tasks(double p_dt, const Dictionary &p_ctx);
	int _state_status(const String &p_id) const;
	static Dictionary _params(const TaskDef &p_task, const String &p_id);
	bool _try_transition(int p_trigger, const PendingEvent *p_event, const Dictionary &p_ctx, int p_origin = -1);
	Vector<String> _full_path(const Vector<String> &p_sub, const String &p_target) const;
	void _apply_path(const Vector<String> &p_path, int p_keep, const Dictionary &p_ctx);
	void _exit_from(int p_keep, const Dictionary &p_ctx);
	void _finish(int p_status, const Dictionary &p_ctx);
	void _reset_runtime();

protected:
	static void _bind_methods();

public:
	void register_task(const String &p_name, const Callable &p_enter = Callable(), const Callable &p_tick = Callable(), const Callable &p_exit = Callable());
	void register_condition(const String &p_name, const Callable &p_fn);
	void register_evaluator(const String &p_name, const Callable &p_fn);
	void register_subtree(const String &p_name, const Dictionary &p_asset);

	PackedStringArray validate(const Dictionary &p_asset) const;
	bool set_asset(const Dictionary &p_asset);

	bool start(const Dictionary &p_context);
	void stop(const Dictionary &p_context);
	void send_event(const String &p_name, const Variant &p_payload = Variant());
	int tick(double p_dt, const Dictionary &p_context);

	String debug_path() const;
	String current_state() const;
	bool is_active(const String &p_state_id) const;

	PackedStringArray get_errors() const { return errors; }
	int get_tree_status() const { return tree_status; }
	bool is_running() const { return running; }
	PackedStringArray get_active_path() const { return active_path; }
	PackedStringArray get_trace() const { return trace; }
	void clear_trace() { trace.clear(); }
};

VARIANT_ENUM_CAST(CgameStateTree::Status);
