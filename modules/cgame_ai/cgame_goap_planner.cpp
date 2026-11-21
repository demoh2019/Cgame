/**************************************************************************/
/*  cgame_goap_planner.cpp                                                */
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

#include "cgame_goap_planner.h"

#include "core/math/math_defs.h"
#include "core/math/math_funcs.h"
#include "core/variant/variant_utility.h"

String CgameGOAPPlanner::_key(const Dictionary &p_state) {
	Array keys = p_state.keys();
	keys.sort();
	PackedStringArray parts;
	for (int i = 0; i < keys.size(); i++) {
		parts.push_back(String(keys[i]) + "=" + VariantUtilityFunctions::var_to_str(p_state[keys[i]]));
	}
	return String(";").join(parts);
}

double CgameGOAPPlanner::_h(const Dictionary &p_state, const Dictionary &p_goal) {
	int n = 0;
	const Array keys = p_goal.keys();
	for (int i = 0; i < keys.size(); i++) {
		if (!p_state.has(keys[i]) || !CgameAI::variants_equal(p_state[keys[i]], p_goal[keys[i]])) {
			n++;
		}
	}
	return double(n);
}

PackedStringArray CgameGOAPPlanner::plan(const Array &p_actions, const Dictionary &p_state, const Dictionary &p_goal, int p_max_nodes) {
	PackedStringArray out;
	if (CgameAI::state_holds(p_state, p_goal)) {
		return out;
	}
	double min_cost = 1.0;
	for (int i = 0; i < p_actions.size(); i++) {
		const Dictionary ad = p_actions[i];
		min_cost = MIN(min_cost, double(ad.get("cost", 1.0)));
	}
	min_cost = MAX(min_cost, 0.0);

	// Node arrays are parallel, indexed by insertion order (node id).
	Vector<Dictionary> states;
	Vector<double> gs;
	Vector<int> parents;
	Vector<String> names;
	Vector<int> open;
	HashMap<String, double> best_g;
	states.push_back(p_state.duplicate());
	gs.push_back(0.0);
	parents.push_back(-1);
	names.push_back(String());
	open.push_back(0);
	best_g[_key(p_state)] = 0.0;
	int expanded = 0;

	while (!open.is_empty()) {
		int pick = 0;
		double pick_f = Math::INF;
		for (int i = 0; i < open.size(); i++) {
			const int id = open[i];
			const double f = gs[id] + _h(states[id], p_goal) * min_cost;
			if (f < pick_f - 0.000001) {
				pick_f = f;
				pick = i;
			}
		}
		const int cur = open[pick];
		open.remove_at(pick);
		if (CgameAI::state_holds(states[cur], p_goal)) {
			Vector<String> reversed;
			int node = cur;
			while (parents[node] != -1) {
				reversed.push_back(names[node]);
				node = parents[node];
			}
			for (int i = reversed.size() - 1; i >= 0; i--) {
				out.push_back(reversed[i]);
			}
			return out;
		}
		expanded++;
		if (expanded > p_max_nodes) {
			return PackedStringArray();
		}
		const String cur_key = _key(states[cur]);
		const HashMap<String, double>::ConstIterator known = best_g.find(cur_key);
		const double known_g = known ? known->value : double(Math::INF);
		if (gs[cur] > known_g + 0.000001) {
			continue;
		}
		for (int i = 0; i < p_actions.size(); i++) {
			const Dictionary act = p_actions[i];
			const Dictionary preconditions = act.get("preconditions", Dictionary());
			if (!CgameAI::state_holds(states[cur], preconditions)) {
				continue;
			}
			Dictionary next = states[cur].duplicate();
			const Dictionary effects = act.get("effects", Dictionary());
			const Array effect_keys = effects.keys();
			for (int k = 0; k < effect_keys.size(); k++) {
				next[effect_keys[k]] = effects[effect_keys[k]];
			}
			const double g = gs[cur] + double(act.get("cost", 1.0));
			const String nk = _key(next);
			const HashMap<String, double>::ConstIterator seen = best_g.find(nk);
			if (seen && seen->value <= g + 0.000001) {
				continue;
			}
			best_g[nk] = g;
			states.push_back(next);
			gs.push_back(g);
			parents.push_back(cur);
			names.push_back(String(act.get("name", "")));
			open.push_back(states.size() - 1);
		}
	}
	return PackedStringArray();
}

void CgameGOAPPlanner::_bind_methods() {
	ClassDB::bind_static_method("CgameGOAPPlanner", D_METHOD("plan", "actions", "state", "goal", "max_nodes"), &CgameGOAPPlanner::plan, DEFVAL(2048));
}
