/**************************************************************************/
/*  cgame_state_tree.cpp                                                  */
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

#include "cgame_state_tree.h"

static const char *const END_SUCCEEDED = "$succeeded";
static const char *const END_FAILED = "$failed";

CgameStateTree::TaskDef CgameStateTree::_norm(const Variant &p_value) {
	TaskDef def;
	if (p_value.get_type() == Variant::DICTIONARY) {
		const Dictionary d = p_value;
		def.fn = String(d.get("fn", ""));
		def.args = d.get("args", Dictionary());
		return def;
	}
	def.fn = String(p_value);
	return def;
}

int CgameStateTree::_parse_trigger(const String &p_trigger) {
	if (p_trigger == "on_completed") {
		return TRIGGER_ON_COMPLETED;
	}
	if (p_trigger == "on_failed") {
		return TRIGGER_ON_FAILED;
	}
	if (p_trigger == "on_tick") {
		return TRIGGER_ON_TICK;
	}
	if (p_trigger == "on_event") {
		return TRIGGER_ON_EVENT;
	}
	return TRIGGER_INVALID;
}

// --- registration ----------------------------------------------------------

void CgameStateTree::register_task(const String &p_name, const Callable &p_enter, const Callable &p_tick, const Callable &p_exit) {
	TaskReg reg;
	reg.enter = p_enter;
	reg.tick = p_tick;
	reg.exit = p_exit;
	tasks[p_name] = reg;
}

void CgameStateTree::register_condition(const String &p_name, const Callable &p_fn) {
	conditions[p_name] = p_fn;
}

void CgameStateTree::register_evaluator(const String &p_name, const Callable &p_fn) {
	evaluators[p_name] = p_fn;
}

void CgameStateTree::register_subtree(const String &p_name, const Dictionary &p_asset) {
	subtrees[p_name] = p_asset;
}

// --- validation and installation -------------------------------------------

PackedStringArray CgameStateTree::validate(const Dictionary &p_asset) const {
	Vector<String> errs;
	HashMap<String, StateNode> out;
	const String root_id = _flatten(p_asset, "", out, 0, errs);
	if (!root_id.is_empty() && errs.is_empty()) {
		HashSet<String> visiting;
		_check_cycles(root_id, out, visiting, errs);
	}
	return errs;
}

bool CgameStateTree::set_asset(const Dictionary &p_asset) {
	errors = validate(p_asset);
	if (!errors.is_empty()) {
		return false;
	}
	asset_evaluators.clear();
	const Array evs = p_asset.get("evaluators", Array());
	for (int i = 0; i < evs.size(); i++) {
		asset_evaluators.push_back(_norm(evs[i]));
	}
	states.clear();
	Vector<String> ignore;
	root = _flatten(p_asset, "", states, 0, ignore);
	_reset_runtime();
	return true;
}

String CgameStateTree::_flatten(const Dictionary &p_asset, const String &p_prefix, HashMap<String, StateNode> &r_out, int p_depth, Vector<String> &r_errs) const {
	if (p_depth > MAX_LINK_DEPTH) {
		r_errs.push_back(vformat("%slinked subtree depth exceeds %d (recursive link?)", p_prefix, (int)MAX_LINK_DEPTH));
		return String();
	}
	if (!p_asset.has("states") || Variant(p_asset["states"]).get_type() != Variant::DICTIONARY) {
		r_errs.push_back(vformat("%sasset has no 'states' dictionary", p_prefix));
		return String();
	}
	const Dictionary state_defs = p_asset["states"];
	const String root_id = String(p_asset.get("root", ""));
	if (root_id.is_empty() || !state_defs.has(root_id)) {
		r_errs.push_back(vformat("%sroot '%s' is not a defined state", p_prefix, root_id));
		return String();
	}
	const Array evs = p_asset.get("evaluators", Array());
	for (int i = 0; i < evs.size(); i++) {
		const TaskDef ev = _norm(evs[i]);
		if (!evaluators.has(ev.fn)) {
			r_errs.push_back(vformat("%sunknown evaluator '%s'", p_prefix, ev.fn));
		}
	}
	const Array state_keys = state_defs.keys();
	for (int ki = 0; ki < state_keys.size(); ki++) {
		const String id = String(state_keys[ki]);
		const Dictionary s = state_defs[state_keys[ki]];
		StateNode node;
		node.id = p_prefix + id;
		node.conditions = s.get("conditions", Array());
		const Array kids = s.get("children", Array());
		for (int i = 0; i < kids.size(); i++) {
			const String cid = String(kids[i]);
			if (!state_defs.has(cid)) {
				r_errs.push_back(vformat("%sstate '%s' lists unknown child '%s'", p_prefix, id, cid));
			} else {
				node.children.push_back(p_prefix + cid);
			}
		}
		const Array task_defs = s.get("tasks", Array());
		for (int i = 0; i < task_defs.size(); i++) {
			const TaskDef task = _norm(task_defs[i]);
			if (!tasks.has(task.fn)) {
				r_errs.push_back(vformat("%sstate '%s' uses unregistered task '%s'", p_prefix, id, task.fn));
			}
			node.tasks.push_back(task);
		}
		_check_cond(s.get("conditions", Array()), p_prefix + id + " enter", r_errs);
		const Array trs = s.get("transitions", Array());
		for (int i = 0; i < trs.size(); i++) {
			const Dictionary tr = trs[i];
			const String trigger = String(tr.get("trigger", "on_completed"));
			const int trigger_kind = _parse_trigger(trigger);
			if (trigger_kind == TRIGGER_INVALID) {
				r_errs.push_back(vformat("%sstate '%s' has transition with invalid trigger '%s'", p_prefix, id, trigger));
			}
			if (trigger_kind == TRIGGER_ON_EVENT && String(tr.get("event", "")).is_empty()) {
				r_errs.push_back(vformat("%sstate '%s' on_event transition has no event name", p_prefix, id));
			}
			const String target = String(tr.get("target", ""));
			if (target != END_SUCCEEDED && target != END_FAILED && !state_defs.has(target)) {
				r_errs.push_back(vformat("%sstate '%s' transition targets unknown state '%s'", p_prefix, id, target));
			}
			_check_cond(tr.get("condition", Array()), p_prefix + id + " transition", r_errs);
			Transition t;
			t.trigger = trigger_kind;
			t.event = String(tr.get("event", ""));
			t.condition = tr.get("condition", Array());
			t.target = target.begins_with("$") ? target : p_prefix + target;
			t.priority = int(tr.get("priority", 0));
			node.transitions.push_back(t);
		}
		if (s.has("link")) {
			const String link = String(s["link"]);
			const HashMap<String, Dictionary>::ConstIterator sub = subtrees.find(link);
			if (!sub) {
				r_errs.push_back(vformat("%sstate '%s' links unknown subtree '%s'", p_prefix, id, link));
			} else {
				const String sub_root = _flatten(sub->value, vformat("%s%s/", p_prefix, id), r_out, p_depth + 1, r_errs);
				if (!sub_root.is_empty()) {
					node.children.push_back(sub_root);
				}
			}
		}
		r_out[p_prefix + id] = node;
	}
	for (KeyValue<String, StateNode> &kv : r_out) {
		const Vector<String> node_children = kv.value.children;
		const String node_id = kv.value.id;
		for (int i = 0; i < node_children.size(); i++) {
			HashMap<String, StateNode>::Iterator child = r_out.find(node_children[i]);
			if (child) {
				child->value.parent = node_id;
			}
		}
	}
	return p_prefix + root_id;
}

void CgameStateTree::_check_cond(const Variant &p_cond, const String &p_where, Vector<String> &r_errs) const {
	switch (p_cond.get_type()) {
		case Variant::ARRAY: {
			const Array arr = p_cond;
			for (int i = 0; i < arr.size(); i++) {
				_check_cond(arr[i], p_where, r_errs);
			}
		} break;
		case Variant::STRING:
		case Variant::STRING_NAME: {
			const String name = String(p_cond);
			if (!name.is_empty() && !conditions.has(name)) {
				r_errs.push_back(vformat("%s: unregistered condition '%s'", p_where, name));
			}
		} break;
		case Variant::DICTIONARY: {
			const Dictionary d = p_cond;
			if (d.has("fn")) {
				const String name = String(d["fn"]);
				if (!conditions.has(name)) {
					r_errs.push_back(vformat("%s: unregistered condition '%s'", p_where, name));
				}
			} else if (!d.has("key")) {
				r_errs.push_back(vformat("%s: condition needs 'fn' or 'key'", p_where));
			}
		} break;
		case Variant::NIL: {
		} break;
		default: {
			r_errs.push_back(vformat("%s: malformed condition", p_where));
		} break;
	}
}

void CgameStateTree::_check_cycles(const String &p_id, const HashMap<String, StateNode> &p_out, HashSet<String> &r_visiting, Vector<String> &r_errs) const {
	if (r_visiting.has(p_id)) {
		r_errs.push_back(vformat("cycle in state hierarchy at '%s'", p_id));
		return;
	}
	r_visiting.insert(p_id);
	const HashMap<String, StateNode>::ConstIterator nd = p_out.find(p_id);
	if (nd) {
		const Vector<String> kids = nd->value.children;
		for (int i = 0; i < kids.size(); i++) {
			if (r_errs.is_empty()) {
				_check_cycles(kids[i], p_out, r_visiting, r_errs);
			}
		}
	}
	r_visiting.erase(p_id);
}

// --- condition evaluation and selection ------------------------------------

bool CgameStateTree::_compare(const Variant &p_a, const String &p_op, const Variant &p_b) {
	if (p_a.get_type() == Variant::NIL) {
		return false;
	}
	Variant::Operator op;
	if (p_op == "==") {
		op = Variant::OP_EQUAL;
	} else if (p_op == "!=") {
		op = Variant::OP_NOT_EQUAL;
	} else if (p_op == "<") {
		op = Variant::OP_LESS;
	} else if (p_op == "<=") {
		op = Variant::OP_LESS_EQUAL;
	} else if (p_op == ">") {
		op = Variant::OP_GREATER;
	} else if (p_op == ">=") {
		op = Variant::OP_GREATER_EQUAL;
	} else {
		return false;
	}
	bool valid = false;
	Variant result;
	Variant::evaluate(op, p_a, p_b, result, valid);
	return valid && bool(result);
}

bool CgameStateTree::_eval_cond(const Variant &p_cond, const Dictionary &p_ctx) const {
	switch (p_cond.get_type()) {
		case Variant::NIL: {
			return true;
		}
		case Variant::ARRAY: {
			const Array arr = p_cond;
			for (int i = 0; i < arr.size(); i++) {
				if (!_eval_cond(arr[i], p_ctx)) {
					return false;
				}
			}
			return true;
		}
		case Variant::DICTIONARY: {
			const Dictionary d = p_cond;
			bool result = true;
			if (d.has("fn")) {
				const HashMap<String, Callable>::ConstIterator fn = conditions.find(String(d["fn"]));
				if (!fn) {
					return false;
				}
				const Dictionary args = d.get("args", Dictionary());
				const Callable callable = fn->value;
				result = bool(callable.call(p_ctx, args));
			} else {
				result = _compare(p_ctx.get(String(d.get("key", "")), Variant()), String(d.get("op", "==")), d.get("value", Variant()));
			}
			if (bool(d.get("not", false))) {
				result = !result;
			}
			return result;
		}
		default: {
		} break;
	}
	const String name = String(p_cond);
	if (name.is_empty()) {
		return true;
	}
	const HashMap<String, Callable>::ConstIterator f = conditions.find(name);
	if (!f) {
		return false;
	}
	const Callable callable = f->value;
	return bool(callable.call(p_ctx, Dictionary()));
}

// Depth-first selection. Returns the path root..leaf, or an empty path when not selectable.
Vector<String> CgameStateTree::_select(const String &p_id, const Dictionary &p_ctx) const {
	const HashMap<String, StateNode>::ConstIterator it = states.find(p_id);
	if (!it) {
		return Vector<String>();
	}
	const Variant node_conditions = it->value.conditions;
	const Vector<String> kids = it->value.children;
	if (!_eval_cond(node_conditions, p_ctx)) {
		return Vector<String>();
	}
	Vector<String> path;
	if (kids.is_empty()) {
		path.push_back(p_id);
		return path;
	}
	for (int i = 0; i < kids.size(); i++) {
		const Vector<String> sub = _select(kids[i], p_ctx);
		if (!sub.is_empty()) {
			path.push_back(p_id);
			path.append_array(sub);
			return path;
		}
	}
	return Vector<String>();
}

// --- runtime ---------------------------------------------------------------

void CgameStateTree::_reset_runtime() {
	active_path.clear();
	running = false;
	tree_status = SUCCEEDED;
	events.clear();
	task_status.clear();
}

bool CgameStateTree::start(const Dictionary &p_context) {
	if (root.is_empty()) {
		return false;
	}
	_reset_runtime();
	const Vector<String> path = _select(root, p_context);
	if (path.is_empty()) {
		tree_status = FAILED;
		return false;
	}
	running = true;
	tree_status = RUNNING;
	_apply_path(path, 0, p_context);
	return true;
}

void CgameStateTree::stop(const Dictionary &p_context) {
	if (running) {
		_exit_from(0, p_context);
	}
	running = false;
}

void CgameStateTree::send_event(const String &p_name, const Variant &p_payload) {
	PendingEvent ev;
	ev.name = p_name;
	ev.payload = p_payload;
	events.push_back(ev);
}

int CgameStateTree::tick(double p_dt, const Dictionary &p_context) {
	if (!running) {
		return tree_status;
	}
	_run_evaluators(p_dt, p_context);
	const Vector<PendingEvent> pending = events;
	events.clear();
	for (int i = 0; i < pending.size(); i++) {
		if (_try_transition(TRIGGER_ON_EVENT, &pending[i], p_context)) {
			if (!running) {
				return tree_status;
			}
		}
	}
	_tick_tasks(p_dt, p_context);
	int trigger = -1;
	int origin = -1;
	for (int i = active_path.size() - 1; i >= 0; i--) {
		const int st = _state_status(active_path[i]);
		if (st != RUNNING) {
			trigger = st == SUCCEEDED ? TRIGGER_ON_COMPLETED : TRIGGER_ON_FAILED;
			origin = i;
			break;
		}
	}
	if (trigger != -1) {
		if (_try_transition(trigger, nullptr, p_context, origin)) {
			return tree_status;
		}
	}
	if (_try_transition(TRIGGER_ON_TICK, nullptr, p_context)) {
		return tree_status;
	}
	if (trigger != -1) {
		// Completed or failed with nothing to transition to: the tree itself finishes.
		_finish(trigger == TRIGGER_ON_COMPLETED ? SUCCEEDED : FAILED, p_context);
	}
	return tree_status;
}

String CgameStateTree::debug_path() const {
	if (active_path.is_empty()) {
		return "(inactive)";
	}
	return String("/").join(active_path);
}

String CgameStateTree::current_state() const {
	return active_path.is_empty() ? String() : active_path[active_path.size() - 1];
}

bool CgameStateTree::is_active(const String &p_state_id) const {
	return active_path.has(p_state_id);
}

void CgameStateTree::_run_evaluators(double p_dt, const Dictionary &p_ctx) {
	Dictionary ctx = p_ctx;
	const Vector<TaskDef> defs = asset_evaluators;
	for (int i = 0; i < defs.size(); i++) {
		const HashMap<String, Callable>::ConstIterator fn = evaluators.find(defs[i].fn);
		if (!fn) {
			continue;
		}
		const Callable callable = fn->value;
		const Variant res = callable.call(p_ctx, p_dt, defs[i].args);
		if (res.get_type() == Variant::DICTIONARY) {
			ctx.merge(Dictionary(res), true);
		}
	}
}

Dictionary CgameStateTree::_params(const TaskDef &p_task, const String &p_id) {
	Dictionary p = p_task.args.duplicate();
	p["_state"] = p_id;
	return p;
}

void CgameStateTree::_tick_tasks(double p_dt, const Dictionary &p_ctx) {
	const PackedStringArray path = active_path;
	for (int pi = 0; pi < path.size(); pi++) {
		const String id = path[pi];
		const HashMap<String, StateNode>::ConstIterator nd = states.find(id);
		if (!nd) {
			continue;
		}
		const Vector<TaskDef> task_defs = nd->value.tasks;
		for (int i = 0; i < task_defs.size(); i++) {
			HashMap<String, Vector<int>>::Iterator statuses = task_status.find(id);
			if (!statuses || i >= statuses->value.size()) {
				break;
			}
			if (statuses->value[i] != RUNNING) {
				continue;
			}
			const HashMap<String, TaskReg>::ConstIterator reg = tasks.find(task_defs[i].fn);
			if (!reg || !reg->value.tick.is_valid()) {
				continue;
			}
			const Callable tick_fn = reg->value.tick;
			const Variant result = tick_fn.call(p_ctx, p_dt, _params(task_defs[i], id));
			statuses = task_status.find(id);
			if (statuses && i < statuses->value.size()) {
				statuses->value.write[i] = int(result);
			}
		}
	}
}

int CgameStateTree::_state_status(const String &p_id) const {
	const HashMap<String, Vector<int>>::ConstIterator it = task_status.find(p_id);
	if (!it || it->value.is_empty()) {
		return RUNNING;
	}
	bool all_ok = true;
	for (int i = 0; i < it->value.size(); i++) {
		if (it->value[i] == FAILED) {
			return FAILED;
		}
		if (it->value[i] != SUCCEEDED) {
			all_ok = false;
		}
	}
	return all_ok ? SUCCEEDED : RUNNING;
}

// Picks the best matching transition (highest priority, then deepest, then declaration order).
bool CgameStateTree::_try_transition(int p_trigger, const PendingEvent *p_event, const Dictionary &p_ctx, int p_origin) {
	Dictionary ctx = p_ctx;
	const int from_idx = p_origin >= 0 ? p_origin : active_path.size() - 1;
	bool has_best = false;
	Transition best;
	int best_priority = INT32_MIN;
	Vector<String> best_path;
	const bool had_event = p_trigger == TRIGGER_ON_EVENT && p_event != nullptr;
	if (had_event) {
		ctx["_event"] = p_event->name;
		ctx["_event_payload"] = p_event->payload;
	}
	for (int i = from_idx; i >= 0; i--) {
		if (i >= active_path.size()) {
			continue;
		}
		const HashMap<String, StateNode>::ConstIterator nd = states.find(active_path[i]);
		if (!nd) {
			continue;
		}
		const Vector<Transition> trs = nd->value.transitions;
		for (int t = 0; t < trs.size(); t++) {
			const Transition &tr = trs[t];
			if (tr.trigger != p_trigger) {
				continue;
			}
			if (had_event && tr.event != p_event->name) {
				continue;
			}
			if (has_best && tr.priority <= best_priority) {
				continue;
			}
			if (!_eval_cond(tr.condition, ctx)) {
				continue;
			}
			Vector<String> path;
			if (!tr.target.begins_with("$")) {
				path = _select(tr.target, ctx);
				if (path.is_empty()) {
					continue;
				}
				path = _full_path(path, tr.target);
			}
			best = tr;
			has_best = true;
			best_priority = tr.priority;
			best_path = path;
		}
	}
	if (had_event) {
		ctx.erase("_event");
		ctx.erase("_event_payload");
	}
	if (!has_best) {
		return false;
	}
	if (best.target == END_SUCCEEDED) {
		_finish(SUCCEEDED, ctx);
	} else if (best.target == END_FAILED) {
		_finish(FAILED, ctx);
	} else {
		int keep = 0;
		while (keep < active_path.size() && keep < best_path.size() && active_path[keep] == best_path[keep]) {
			keep++;
		}
		// Targeting a state that is already active re-enters it.
		const int target_depth = best_path.find(best.target);
		if (keep > target_depth) {
			keep = target_depth;
		}
		_exit_from(keep, ctx);
		_apply_path(best_path, keep, ctx);
	}
	return true;
}

// `_select` returns the path from the target down; prepend the target's ancestors.
Vector<String> CgameStateTree::_full_path(const Vector<String> &p_sub, const String &p_target) const {
	Vector<String> chain;
	HashMap<String, StateNode>::ConstIterator it = states.find(p_target);
	String cur = it ? it->value.parent : String();
	int guard = states.size() + 1;
	while (!cur.is_empty() && guard-- > 0) {
		chain.insert(0, cur);
		it = states.find(cur);
		cur = it ? it->value.parent : String();
	}
	chain.append_array(p_sub);
	return chain;
}

void CgameStateTree::_apply_path(const Vector<String> &p_path, int p_keep, const Dictionary &p_ctx) {
	active_path = p_path;
	for (int i = p_keep; i < p_path.size(); i++) {
		const String id = p_path[i];
		const HashMap<String, StateNode>::ConstIterator nd = states.find(id);
		if (!nd) {
			continue;
		}
		const Vector<TaskDef> task_defs = nd->value.tasks;
		Vector<int> statuses;
		statuses.resize(task_defs.size());
		statuses.fill(RUNNING);
		task_status[id] = statuses;
		trace.push_back("enter:" + id);
		for (int t = 0; t < task_defs.size(); t++) {
			const HashMap<String, TaskReg>::ConstIterator reg = tasks.find(task_defs[t].fn);
			if (reg && reg->value.enter.is_valid()) {
				const Callable fn = reg->value.enter;
				fn.call(p_ctx, _params(task_defs[t], id));
			}
		}
	}
}

// Exits states from the leaf down to (and including) index `p_keep`.
void CgameStateTree::_exit_from(int p_keep, const Dictionary &p_ctx) {
	if (p_keep < 0) {
		p_keep = 0;
	}
	for (int i = active_path.size() - 1; i >= p_keep; i--) {
		const String id = active_path[i];
		const HashMap<String, StateNode>::ConstIterator nd = states.find(id);
		if (nd) {
			const Vector<TaskDef> task_defs = nd->value.tasks;
			for (int j = task_defs.size() - 1; j >= 0; j--) {
				const HashMap<String, TaskReg>::ConstIterator reg = tasks.find(task_defs[j].fn);
				if (reg && reg->value.exit.is_valid()) {
					const Callable fn = reg->value.exit;
					fn.call(p_ctx, _params(task_defs[j], id));
				}
			}
		}
		trace.push_back("exit:" + id);
		task_status.erase(id);
	}
	if (p_keep < active_path.size()) {
		active_path.resize(p_keep);
	}
}

void CgameStateTree::_finish(int p_status, const Dictionary &p_ctx) {
	_exit_from(0, p_ctx);
	running = false;
	tree_status = p_status;
}

void CgameStateTree::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_task", "name", "enter", "tick", "exit"), &CgameStateTree::register_task, DEFVAL(Callable()), DEFVAL(Callable()), DEFVAL(Callable()));
	ClassDB::bind_method(D_METHOD("register_condition", "name", "fn"), &CgameStateTree::register_condition);
	ClassDB::bind_method(D_METHOD("register_evaluator", "name", "fn"), &CgameStateTree::register_evaluator);
	ClassDB::bind_method(D_METHOD("register_subtree", "name", "asset"), &CgameStateTree::register_subtree);
	ClassDB::bind_method(D_METHOD("validate", "asset"), &CgameStateTree::validate);
	ClassDB::bind_method(D_METHOD("set_asset", "asset"), &CgameStateTree::set_asset);
	ClassDB::bind_method(D_METHOD("start", "context"), &CgameStateTree::start);
	ClassDB::bind_method(D_METHOD("stop", "context"), &CgameStateTree::stop);
	ClassDB::bind_method(D_METHOD("send_event", "name", "payload"), &CgameStateTree::send_event, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("tick", "dt", "context"), &CgameStateTree::tick);
	ClassDB::bind_method(D_METHOD("debug_path"), &CgameStateTree::debug_path);
	ClassDB::bind_method(D_METHOD("current_state"), &CgameStateTree::current_state);
	ClassDB::bind_method(D_METHOD("is_active", "state_id"), &CgameStateTree::is_active);
	ClassDB::bind_method(D_METHOD("get_errors"), &CgameStateTree::get_errors);
	ClassDB::bind_method(D_METHOD("get_tree_status"), &CgameStateTree::get_tree_status);
	ClassDB::bind_method(D_METHOD("is_running"), &CgameStateTree::is_running);
	ClassDB::bind_method(D_METHOD("get_active_path"), &CgameStateTree::get_active_path);
	ClassDB::bind_method(D_METHOD("get_trace"), &CgameStateTree::get_trace);
	ClassDB::bind_method(D_METHOD("clear_trace"), &CgameStateTree::clear_trace);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "errors", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_errors");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tree_status", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_tree_status");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "running", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "is_running");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "active_path", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_active_path");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "trace", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_trace");

	BIND_ENUM_CONSTANT(RUNNING);
	BIND_ENUM_CONSTANT(SUCCEEDED);
	BIND_ENUM_CONSTANT(FAILED);
	BIND_CONSTANT(MAX_LINK_DEPTH);
}
