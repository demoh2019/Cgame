/**************************************************************************/
/*  cgame_htn_planner.cpp                                                 */
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

#include "cgame_htn_planner.h"

bool CgameHTNPlanner::_solve(const Dictionary &p_domain, const Vector<String> &p_tasks, const Dictionary &p_state, int &r_budget, Vector<String> &r_plan) {
	r_plan.clear();
	if (p_tasks.is_empty()) {
		return true;
	}
	r_budget--;
	if (r_budget < 0) {
		return false;
	}
	const String head = p_tasks[0];
	const Vector<String> rest = p_tasks.slice(1);
	if (!p_domain.has(head)) {
		return false;
	}
	const Variant entry = p_domain[head];
	if (entry.get_type() == Variant::DICTIONARY) {
		const Dictionary prim = entry;
		const Dictionary preconditions = prim.get("preconditions", Dictionary());
		if (!CgameAI::state_holds(p_state, preconditions)) {
			return false;
		}
		Dictionary next_state = p_state.duplicate();
		const Dictionary effects = prim.get("effects", Dictionary());
		const Array effect_keys = effects.keys();
		for (int i = 0; i < effect_keys.size(); i++) {
			next_state[effect_keys[i]] = effects[effect_keys[i]];
		}
		Vector<String> tail;
		if (!_solve(p_domain, rest, next_state, r_budget, tail)) {
			r_plan.clear();
			return false;
		}
		r_plan.push_back(head);
		r_plan.append_array(tail);
		return true;
	}
	if (entry.get_type() == Variant::ARRAY) {
		const Array methods = entry;
		for (int i = 0; i < methods.size(); i++) {
			const Dictionary method = methods[i];
			const Dictionary preconditions = method.get("preconditions", Dictionary());
			if (!CgameAI::state_holds(p_state, preconditions)) {
				continue;
			}
			Vector<String> queue;
			const Array subtasks = method.get("subtasks", Array());
			for (int j = 0; j < subtasks.size(); j++) {
				queue.push_back(String(subtasks[j]));
			}
			queue.append_array(rest);
			Vector<String> result;
			if (_solve(p_domain, queue, p_state, r_budget, result)) {
				r_plan = result;
				return true;
			}
			if (r_budget < 0) {
				return false;
			}
		}
	}
	return false;
}

PackedStringArray CgameHTNPlanner::plan(const Dictionary &p_domain, const String &p_root_task, const Dictionary &p_state, int p_max_steps) {
	int budget = p_max_steps;
	Vector<String> tasks;
	tasks.push_back(p_root_task);
	Vector<String> found;
	PackedStringArray out;
	if (!_solve(p_domain, tasks, p_state, budget, found)) {
		return out;
	}
	out.append_array(found);
	return out;
}

void CgameHTNPlanner::_bind_methods() {
	ClassDB::bind_static_method("CgameHTNPlanner", D_METHOD("plan", "domain", "root_task", "state", "max_steps"), &CgameHTNPlanner::plan, DEFVAL(256));
}
