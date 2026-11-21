/**************************************************************************/
/*  cgame_task_graph.cpp                                                  */
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

#include "cgame_task_graph.h"

#include "cgame_trace.h"

#include "core/object/class_db.h"
#include "core/object/worker_thread_pool.h"
#include "core/os/os.h"
#include "core/os/thread.h"
#include "core/templates/hash_set.h"

#include <atomic>

namespace {
std::atomic<int64_t> flow_counter{ 0 };
}

CgameTaskGraph::CgameTaskGraph() {
	// Each graph gets its own flow-id range so arrows of different graphs never collide.
	trace_flow_base = flow_counter.fetch_add(1) << 40;
}

CgameTaskGraph::~CgameTaskGraph() {
	clear();
}

String CgameTaskGraph::add_task(const String &p_name, const Callable &p_callable, const PackedStringArray &p_deps, bool p_thread_safe) {
	if (p_name.is_empty() || by_name.has(p_name)) {
		ERR_PRINT(vformat("CgameTaskGraph: invalid or duplicate task '%s'.", p_name));
		return String();
	}
	for (const String &d : p_deps) {
		if (d == p_name || _reaches(d, p_name)) {
			ERR_PRINT(vformat("CgameTaskGraph: task '%s' would create a dependency cycle.", p_name));
			return String();
		}
	}
	Task *t = memnew(Task);
	t->name = p_name;
	t->callable = p_callable;
	for (const String &d : p_deps) {
		t->deps.push_back(d);
	}
	t->thread_safe = p_thread_safe;
	t->index = (int)tasks.size();
	by_name[p_name] = t->index;
	tasks.push_back(t);
	return p_name;
}

bool CgameTaskGraph::add_dependency(const String &p_task, const String &p_dep) {
	if (!by_name.has(p_task) || !by_name.has(p_dep) || p_task == p_dep) {
		return false;
	}
	if (_reaches(p_dep, p_task)) {
		return false;
	}
	Task *t = tasks[by_name[p_task]];
	if (!t->deps.has(p_dep)) {
		t->deps.push_back(p_dep);
	}
	return true;
}

bool CgameTaskGraph::has_task(const String &p_name) const {
	return by_name.has(p_name);
}

PackedStringArray CgameTaskGraph::get_task_names() const {
	PackedStringArray out;
	for (const Task *t : tasks) {
		out.push_back(t->name);
	}
	return out;
}

void CgameTaskGraph::clear() {
	for (Task *t : tasks) {
		memdelete(t);
	}
	tasks.clear();
	by_name.clear();
	dependants.clear();
	last_total_us = 0;
	wave_count = 0;
}

// True when `p_from` depends (transitively) on `p_target`.
bool CgameTaskGraph::_reaches(const String &p_from, const String &p_target) const {
	LocalVector<String> stack;
	stack.push_back(p_from);
	HashSet<String> seen;
	while (!stack.is_empty()) {
		const String cur = stack[stack.size() - 1];
		stack.remove_at(stack.size() - 1);
		if (cur == p_target) {
			return true;
		}
		if (seen.has(cur)) {
			continue;
		}
		const int *idx = by_name.getptr(cur);
		if (idx == nullptr) {
			continue;
		}
		seen.insert(cur);
		for (const String &d : tasks[*idx]->deps) {
			stack.push_back(d);
		}
	}
	return false;
}

PackedStringArray CgameTaskGraph::validate() const {
	PackedStringArray errors;
	for (const Task *t : tasks) {
		for (const String &d : t->deps) {
			if (!by_name.has(d)) {
				errors.push_back(vformat("%s depends on unknown task %s", t->name, d));
			}
		}
	}
	return errors;
}

// Deterministic topological order (Kahn; ties broken by insertion order).
LocalVector<int> CgameTaskGraph::_topological_indices() const {
	const int n = (int)tasks.size();
	LocalVector<int> indeg;
	indeg.resize(n);
	LocalVector<LocalVector<int>> dependants_of;
	dependants_of.resize(n);
	for (int i = 0; i < n; i++) {
		int c = 0;
		for (const String &d : tasks[i]->deps) {
			const int *di = by_name.getptr(d);
			if (di) {
				c++;
				dependants_of[*di].push_back(i);
			}
		}
		indeg[i] = c;
	}
	LocalVector<int> ready;
	for (int i = 0; i < n; i++) {
		if (indeg[i] == 0) {
			ready.push_back(i);
		}
	}
	LocalVector<int> out;
	while (!ready.is_empty()) {
		// Pick the lowest insertion index.
		uint32_t best = 0;
		for (uint32_t k = 1; k < ready.size(); k++) {
			if (ready[k] < ready[best]) {
				best = k;
			}
		}
		const int idx = ready[best];
		ready.remove_at(best);
		out.push_back(idx);
		for (int dn : dependants_of[idx]) {
			if (--indeg[dn] == 0) {
				ready.push_back(dn);
			}
		}
	}
	return out;
}

PackedStringArray CgameTaskGraph::topological_order() const {
	PackedStringArray out;
	for (int idx : _topological_indices()) {
		out.push_back(tasks[idx]->name);
	}
	return out;
}

void CgameTaskGraph::_exec_task(Task *p_task) {
	p_task->thread_id = Thread::get_caller_id();
	const bool tracing = trace_enabled && CgameTrace::is_active();
	p_task->start_us = OS::get_singleton()->get_ticks_usec();
	if (tracing) {
		CgameTrace::scope_begin(CgameTrace::intern(p_task->name), "task");
		for (const String &d : p_task->deps) {
			if (const int *di = by_name.getptr(d)) {
				CgameTrace::emit_flow(false, trace_flow_base + ((int64_t)*di << 20) + p_task->index, "dependency");
			}
		}
	}
	if (!p_task->callable.is_valid()) {
		p_task->error = "invalid callable";
	} else {
		Variant r;
		Callable::CallError ce;
		p_task->callable.callp(nullptr, 0, r, ce);
		p_task->result = r;
		if (ce.error != Callable::CallError::CALL_OK) {
			p_task->error = "call failed";
		} else if (r.get_type() == Variant::BOOL && !(bool)r) {
			p_task->error = "task returned false";
		} else if (r.get_type() == Variant::DICTIONARY && Dictionary(r).has("error")) {
			p_task->error = String(Dictionary(r)["error"]);
		}
	}
	p_task->duration_us = OS::get_singleton()->get_ticks_usec() - p_task->start_us;
	if (tracing) {
		if ((uint32_t)p_task->index < dependants.size()) {
			for (int dn : dependants[p_task->index]) {
				CgameTrace::emit_flow(true, trace_flow_base + ((int64_t)p_task->index << 20) + dn, "dependency");
			}
		}
		CgameTrace::scope_end();
	}
}

void CgameTaskGraph::_run_wave(const LocalVector<Task *> &p_wave, int p_wave_no) {
	LocalVector<WorkerThreadPool::TaskID> ids;
	LocalVector<Task *> local;
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	for (Task *t : p_wave) {
		t->wave = p_wave_no;
		if (t->thread_safe && p_wave.size() > 1 && pool) {
			ids.push_back(pool->add_template_task(this, &CgameTaskGraph::_exec_task, t, false, t->name));
		} else {
			local.push_back(t);
		}
	}
	for (Task *t : local) {
		_exec_task(t);
	}
	for (WorkerThreadPool::TaskID id : ids) {
		pool->wait_for_task_completion(id);
	}
	for (Task *t : p_wave) {
		t->state = t->error.is_empty() ? DONE : FAILED;
	}
}

Dictionary CgameTaskGraph::run() {
	Dictionary out;
	out["ok"] = false;
	out["order"] = PackedStringArray();
	out["failed"] = PackedStringArray();
	out["cancelled"] = PackedStringArray();
	out["waves"] = 0;
	out["total_ms"] = 0.0;
	out["error"] = "";

	PackedStringArray problems = validate();
	if (!problems.is_empty()) {
		out["error"] = problems[0];
		return out;
	}
	const LocalVector<int> order = _topological_indices();
	if (order.size() != tasks.size()) {
		out["error"] = "cycle detected";
		return out;
	}
	dependants.clear();
	dependants.resize(tasks.size());
	for (Task *t : tasks) {
		t->state = PENDING;
		t->result = Variant();
		t->error = String();
		t->duration_us = 0;
		t->start_us = 0;
		t->wave = -1;
		for (const String &d : t->deps) {
			dependants[by_name[d]].push_back(t->index);
		}
	}

	const uint64_t t_begin = OS::get_singleton()->get_ticks_usec();
	int wave_no = 0;
	while (true) {
		LocalVector<Task *> wave;
		for (int idx : order) {
			Task *t = tasks[idx];
			if (t->state != PENDING) {
				continue;
			}
			bool blocked = false;
			bool dead = false;
			for (const String &d : t->deps) {
				const int ds = tasks[by_name[d]]->state;
				if (ds == FAILED || ds == CANCELLED) {
					dead = true;
				} else if (ds == PENDING) {
					blocked = true;
				}
			}
			if (dead) {
				t->state = CANCELLED;
			} else if (!blocked) {
				wave.push_back(t);
			}
		}
		if (wave.is_empty()) {
			break;
		}
		_run_wave(wave, wave_no);
		wave_no++;
	}
	wave_count = wave_no;
	last_total_us = OS::get_singleton()->get_ticks_usec() - t_begin;

	PackedStringArray order_names;
	PackedStringArray failed;
	PackedStringArray cancelled;
	for (int idx : order) {
		const Task *t = tasks[idx];
		order_names.push_back(t->name);
		if (t->state == FAILED) {
			failed.push_back(t->name);
		} else if (t->state == CANCELLED) {
			cancelled.push_back(t->name);
		}
	}
	out["ok"] = failed.is_empty() && cancelled.is_empty();
	out["order"] = order_names;
	out["failed"] = failed;
	out["cancelled"] = cancelled;
	out["waves"] = wave_no;
	out["total_ms"] = double(last_total_us) / 1000.0;
	return out;
}

Variant CgameTaskGraph::result_of(const String &p_name) const {
	const int *i = by_name.getptr(p_name);
	return i ? tasks[*i]->result : Variant();
}

int CgameTaskGraph::state_of(const String &p_name) const {
	const int *i = by_name.getptr(p_name);
	return i ? tasks[*i]->state : -1;
}

String CgameTaskGraph::error_of(const String &p_name) const {
	const int *i = by_name.getptr(p_name);
	return i ? tasks[*i]->error : String();
}

Dictionary CgameTaskGraph::timing(const String &p_name) const {
	Dictionary d;
	const int *i = by_name.getptr(p_name);
	if (!i) {
		return d;
	}
	const Task *t = tasks[*i];
	d["start_us"] = (int64_t)t->start_us;
	d["end_us"] = (int64_t)(t->start_us + t->duration_us);
	d["duration_ms"] = double(t->duration_us) / 1000.0;
	d["wave"] = t->wave;
	d["thread_id"] = (int64_t)t->thread_id;
	d["thread_safe"] = t->thread_safe;
	return d;
}

Dictionary CgameTaskGraph::results() const {
	Dictionary out;
	for (int idx : _topological_indices()) {
		out[tasks[idx]->name] = tasks[idx]->result;
	}
	return out;
}

double CgameTaskGraph::_cost_ms(const Task *p_task) const {
	if (p_task->duration_us > 0) {
		return double(p_task->duration_us) / 1000.0;
	}
	return p_task->state == PENDING ? 1.0 : 0.001;
}

// Longest dependency chain by measured duration (cost 1.0 ms when a task has not run).
LocalVector<int> CgameTaskGraph::_critical_indices() const {
	const LocalVector<int> order = _topological_indices();
	LocalVector<double> dist;
	LocalVector<int> prev;
	dist.resize(tasks.size());
	prev.resize(tasks.size());
	int best_end = -1;
	double best = -1.0;
	for (int idx : order) {
		const Task *t = tasks[idx];
		double base = 0.0;
		int from = -1;
		for (const String &d : t->deps) {
			const int *di = by_name.getptr(d);
			if (di && dist[*di] > base) {
				base = dist[*di];
				from = *di;
			}
		}
		dist[idx] = base + _cost_ms(t);
		prev[idx] = from;
		if (dist[idx] > best) {
			best = dist[idx];
			best_end = idx;
		}
	}
	LocalVector<int> reversed;
	for (int cur = best_end; cur >= 0; cur = prev[cur]) {
		reversed.push_back(cur);
	}
	LocalVector<int> path;
	for (int i = (int)reversed.size() - 1; i >= 0; i--) {
		path.push_back(reversed[i]);
	}
	return path;
}

PackedStringArray CgameTaskGraph::critical_path() const {
	PackedStringArray out;
	for (int idx : _critical_indices()) {
		out.push_back(tasks[idx]->name);
	}
	return out;
}

double CgameTaskGraph::critical_path_ms() const {
	double total = 0.0;
	for (int idx : _critical_indices()) {
		total += _cost_ms(tasks[idx]);
	}
	return total;
}

// Graphviz DOT; critical path nodes/edges are red, failed tasks filled, cancelled dashed.
String CgameTaskGraph::to_dot() const {
	const LocalVector<int> crit = _critical_indices();
	auto crit_pos = [&](int p_idx) -> int {
		for (uint32_t i = 0; i < crit.size(); i++) {
			if (crit[i] == p_idx) {
				return (int)i;
			}
		}
		return -1;
	};
	String s = "digraph TaskGraph {\n\trankdir=LR;\n\tnode [shape=box];\n";
	for (const Task *t : tasks) {
		String attrs = vformat("label=\"%s\\n%.2f ms\"", t->name, double(t->duration_us) / 1000.0);
		if (!t->thread_safe) {
			attrs += ", shape=octagon";
		}
		if (t->state == FAILED) {
			attrs += ", style=filled, fillcolor=tomato";
		} else if (t->state == CANCELLED) {
			attrs += ", style=dashed";
		} else if (crit_pos(t->index) >= 0) {
			attrs += ", color=red";
		}
		s += vformat("\t\"%s\" [%s];\n", t->name, attrs);
	}
	for (const Task *t : tasks) {
		const int tp = crit_pos(t->index);
		for (const String &d : t->deps) {
			const int *di = by_name.getptr(d);
			const int dp = di ? crit_pos(*di) : -1;
			const bool on_crit = tp >= 0 && dp >= 0 && tp == dp + 1;
			s += vformat("\t\"%s\" -> \"%s\"%s;\n", d, t->name, on_crit ? " [color=red]" : "");
		}
	}
	return s + "}\n";
}

void CgameTaskGraph::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_task", "name", "callable", "deps", "thread_safe"), &CgameTaskGraph::add_task, DEFVAL(PackedStringArray()), DEFVAL(true));
	ClassDB::bind_method(D_METHOD("add_dependency", "task", "dep"), &CgameTaskGraph::add_dependency);
	ClassDB::bind_method(D_METHOD("has_task", "name"), &CgameTaskGraph::has_task);
	ClassDB::bind_method(D_METHOD("task_count"), &CgameTaskGraph::task_count);
	ClassDB::bind_method(D_METHOD("get_task_names"), &CgameTaskGraph::get_task_names);
	ClassDB::bind_method(D_METHOD("clear"), &CgameTaskGraph::clear);
	ClassDB::bind_method(D_METHOD("validate"), &CgameTaskGraph::validate);
	ClassDB::bind_method(D_METHOD("topological_order"), &CgameTaskGraph::topological_order);
	ClassDB::bind_method(D_METHOD("run"), &CgameTaskGraph::run);
	ClassDB::bind_method(D_METHOD("result_of", "name"), &CgameTaskGraph::result_of);
	ClassDB::bind_method(D_METHOD("state_of", "name"), &CgameTaskGraph::state_of);
	ClassDB::bind_method(D_METHOD("error_of", "name"), &CgameTaskGraph::error_of);
	ClassDB::bind_method(D_METHOD("timing", "name"), &CgameTaskGraph::timing);
	ClassDB::bind_method(D_METHOD("results"), &CgameTaskGraph::results);
	ClassDB::bind_method(D_METHOD("critical_path"), &CgameTaskGraph::critical_path);
	ClassDB::bind_method(D_METHOD("critical_path_ms"), &CgameTaskGraph::critical_path_ms);
	ClassDB::bind_method(D_METHOD("to_dot"), &CgameTaskGraph::to_dot);
	ClassDB::bind_method(D_METHOD("set_trace_enabled", "enabled"), &CgameTaskGraph::set_trace_enabled);
	ClassDB::bind_method(D_METHOD("is_trace_enabled"), &CgameTaskGraph::is_trace_enabled);
	ClassDB::bind_method(D_METHOD("get_wave_count"), &CgameTaskGraph::get_wave_count);
	ClassDB::bind_method(D_METHOD("get_last_total_ms"), &CgameTaskGraph::get_last_total_ms);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "trace_enabled"), "set_trace_enabled", "is_trace_enabled");

	BIND_ENUM_CONSTANT(PENDING);
	BIND_ENUM_CONSTANT(DONE);
	BIND_ENUM_CONSTANT(FAILED);
	BIND_ENUM_CONSTANT(CANCELLED);
}
