/**************************************************************************/
/*  cgame_task_graph.h                                                    */
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

#include "core/object/ref_counted.h"
#include "core/variant/binder_common.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/variant/callable.h"

// Dependency-aware task graph executed on the WorkerThreadPool. Ready tasks run in deterministic
// waves (every task whose dependencies are done); thread-unsafe tasks run on the calling thread
// while the pooled tasks of the same wave execute. A failed task cancels all transitive dependants.
class CgameTaskGraph : public RefCounted {
	GDCLASS(CgameTaskGraph, RefCounted);

public:
	enum TaskState {
		PENDING,
		DONE,
		FAILED,
		CANCELLED,
	};

private:
	struct Task {
		String name;
		Callable callable;
		LocalVector<String> deps;
		bool thread_safe = true;
		int index = 0;
		int state = PENDING;
		Variant result;
		String error;
		uint64_t start_us = 0;
		uint64_t duration_us = 0;
		uint64_t thread_id = 0;
		int wave = -1;
	};

	LocalVector<Task *> tasks;
	HashMap<String, int> by_name;
	uint64_t last_total_us = 0;
	int wave_count = 0;
	int64_t trace_flow_base = 0;
	bool trace_enabled = true;

	LocalVector<LocalVector<int>> dependants;

	bool _reaches(const String &p_from, const String &p_target) const;
	void _exec_task(Task *p_task);
	void _run_wave(const LocalVector<Task *> &p_wave, int p_wave_no);
	double _cost_ms(const Task *p_task) const;
	LocalVector<int> _topological_indices() const;
	LocalVector<int> _critical_indices() const;

protected:
	static void _bind_methods();

public:
	String add_task(const String &p_name, const Callable &p_callable, const PackedStringArray &p_deps = PackedStringArray(), bool p_thread_safe = true);
	bool add_dependency(const String &p_task, const String &p_dep);
	bool has_task(const String &p_name) const;
	int task_count() const { return (int)tasks.size(); }
	PackedStringArray get_task_names() const;
	void clear();
	PackedStringArray validate() const;
	PackedStringArray topological_order() const;
	Dictionary run();

	Variant result_of(const String &p_name) const;
	int state_of(const String &p_name) const;
	String error_of(const String &p_name) const;
	Dictionary timing(const String &p_name) const;
	Dictionary results() const;
	PackedStringArray critical_path() const;
	double critical_path_ms() const;
	String to_dot() const;

	void set_trace_enabled(bool p_enabled) { trace_enabled = p_enabled; }
	bool is_trace_enabled() const { return trace_enabled; }
	int get_wave_count() const { return wave_count; }
	double get_last_total_ms() const { return double(last_total_us) / 1000.0; }

	CgameTaskGraph();
	~CgameTaskGraph();
};

VARIANT_ENUM_CAST(CgameTaskGraph::TaskState);
