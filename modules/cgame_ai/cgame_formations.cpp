/**************************************************************************/
/*  cgame_formations.cpp                                                  */
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

#include "cgame_formations.h"

#include "core/math/math_defs.h"
#include "core/math/math_funcs.h"
#include "core/math/vector2.h"

PackedStringArray CgameFormations::get_kinds() {
	PackedStringArray kinds;
	kinds.push_back("line");
	kinds.push_back("wedge");
	kinds.push_back("circle");
	kinds.push_back("column");
	return kinds;
}

PackedVector2Array CgameFormations::slots(const String &p_kind, int p_count, double p_spacing) {
	PackedVector2Array out;
	if (p_count <= 0) {
		return out;
	}
	out.resize(p_count);
	Vector2 *w = out.ptrw();
	if (p_kind == "line") {
		const double half = double(p_count - 1) * 0.5;
		for (int i = 0; i < p_count; i++) {
			w[i] = Vector2(0.0, (double(i) - half) * p_spacing);
		}
	} else if (p_kind == "wedge") {
		w[0] = Vector2();
		for (int i = 1; i < p_count; i++) {
			const int row = (i + 1) / 2;
			const double side = (i % 2 == 1) ? 1.0 : -1.0;
			w[i] = Vector2(-double(row) * p_spacing * 0.866, side * double(row) * p_spacing * 0.5);
		}
	} else if (p_kind == "circle") {
		if (p_count == 1) {
			w[0] = Vector2();
		} else {
			const double radius = MAX(p_spacing, p_spacing / (2.0 * Math::sin(Math::PI / double(p_count))));
			for (int i = 0; i < p_count; i++) {
				const double a = Math::TAU * double(i) / double(p_count);
				w[i] = Vector2(Math::cos(a), Math::sin(a)) * radius;
			}
		}
	} else {
		// "column" and unknown kinds: single file behind the leader.
		for (int i = 0; i < p_count; i++) {
			w[i] = Vector2(-double(i) * p_spacing, 0.0);
		}
	}
	return out;
}

PackedVector2Array CgameFormations::targets(const Vector2 &p_leader_pos, double p_leader_heading, const String &p_kind, int p_count, double p_spacing) {
	const PackedVector2Array local = slots(p_kind, p_count, p_spacing);
	PackedVector2Array out;
	out.resize(local.size());
	for (int i = 0; i < local.size(); i++) {
		out.write[i] = p_leader_pos + local[i].rotated(p_leader_heading);
	}
	return out;
}

// Standard O(n^2 m) Hungarian algorithm for an n x m cost matrix with n <= m. Returns row -> column.
Vector<int> CgameFormations::_hungarian(const Vector<double> &p_cost, int p_n, int p_m) {
	const double inf = 1.0e18;
	Vector<double> u;
	u.resize_initialized(p_n + 1);
	Vector<double> v;
	v.resize_initialized(p_m + 1);
	Vector<int> p;
	p.resize_initialized(p_m + 1);
	Vector<int> way;
	way.resize_initialized(p_m + 1);
	for (int i = 1; i <= p_n; i++) {
		p.write[0] = i;
		int j0 = 0;
		Vector<double> minv;
		minv.resize(p_m + 1);
		minv.fill(inf);
		Vector<uint8_t> used;
		used.resize_initialized(p_m + 1);
		while (true) {
			used.write[j0] = 1;
			const int i0 = p[j0];
			double delta = inf;
			int j1 = 0;
			for (int j = 1; j <= p_m; j++) {
				if (used[j] == 0) {
					const double cur = p_cost[(i0 - 1) * p_m + (j - 1)] - u[i0] - v[j];
					if (cur < minv[j]) {
						minv.write[j] = cur;
						way.write[j] = j0;
					}
					if (minv[j] < delta) {
						delta = minv[j];
						j1 = j;
					}
				}
			}
			for (int j = 0; j <= p_m; j++) {
				if (used[j] == 1) {
					u.write[p[j]] += delta;
					v.write[j] -= delta;
				} else {
					minv.write[j] -= delta;
				}
			}
			j0 = j1;
			if (p[j0] == 0) {
				break;
			}
		}
		while (true) {
			const int j1b = way[j0];
			p.write[j0] = p[j1b];
			j0 = j1b;
			if (j0 == 0) {
				break;
			}
		}
	}
	Vector<int> row_to_col;
	row_to_col.resize(p_n);
	row_to_col.fill(-1);
	for (int j = 1; j <= p_m; j++) {
		if (p[j] > 0) {
			row_to_col.write[p[j] - 1] = j - 1;
		}
	}
	return row_to_col;
}

// Greedy fallback: members in order each take the nearest free slot.
Vector<int> CgameFormations::_greedy(const Vector<Vector2> &p_slots, const Vector<Vector2> &p_members) {
	const int n = p_members.size();
	const int m = p_slots.size();
	Vector<int> result;
	result.resize(n);
	result.fill(-1);
	Vector<uint8_t> taken;
	taken.resize_initialized(m);
	for (int i = 0; i < n; i++) {
		int best = -1;
		double best_d = Math::INF;
		for (int j = 0; j < m; j++) {
			if (taken[j] == 1) {
				continue;
			}
			const double d = p_members[i].distance_squared_to(p_slots[j]);
			if (d < best_d) {
				best_d = d;
				best = j;
			}
		}
		if (best >= 0) {
			taken.write[best] = 1;
			result.write[i] = best;
		}
	}
	return result;
}

PackedInt32Array CgameFormations::assign(const PackedVector2Array &p_slots_world, const PackedVector2Array &p_members) {
	const int n = p_members.size();
	const int m = p_slots_world.size();
	PackedInt32Array result;
	result.resize(n);
	result.fill(-1);
	if (n == 0 || m == 0) {
		return result;
	}
	// The Hungarian sentinel is 1e18. Reject invalid or out-of-world
	// coordinates before distances can exceed it or become non-finite.
	for (const Vector2 &point : p_members) {
		if (!point.is_finite() || Math::abs(point.x) > 1.0e15 || Math::abs(point.y) > 1.0e15) {
			return result;
		}
	}
	for (const Vector2 &point : p_slots_world) {
		if (!point.is_finite() || Math::abs(point.x) > 1.0e15 || Math::abs(point.y) > 1.0e15) {
			return result;
		}
	}
	if (n <= HUNGARIAN_LIMIT && m <= HUNGARIAN_LIMIT) {
		if (n <= m) {
			Vector<double> cost;
			cost.resize(n * m);
			for (int i = 0; i < n; i++) {
				for (int j = 0; j < m; j++) {
					cost.write[i * m + j] = p_members[i].distance_to(p_slots_world[j]);
				}
			}
			const Vector<int> row_to_col = _hungarian(cost, n, m);
			for (int i = 0; i < n; i++) {
				result.write[i] = row_to_col[i];
			}
		} else {
			// Transpose: rows are slots, columns are members.
			Vector<double> cost_t;
			cost_t.resize(m * n);
			for (int j = 0; j < m; j++) {
				for (int i = 0; i < n; i++) {
					cost_t.write[j * n + i] = p_members[i].distance_to(p_slots_world[j]);
				}
			}
			const Vector<int> slot_to_member = _hungarian(cost_t, m, n);
			for (int j = 0; j < m; j++) {
				result.write[slot_to_member[j]] = j;
			}
		}
		return result;
	}
	const Vector<int> greedy = _greedy(p_slots_world, p_members);
	for (int i = 0; i < n; i++) {
		result.write[i] = greedy[i];
	}
	return result;
}

double CgameFormations::assignment_cost(const PackedVector2Array &p_slots_world, const PackedVector2Array &p_members, const PackedInt32Array &p_assignment) {
	double total = 0.0;
	for (int i = 0; i < p_assignment.size(); i++) {
		if (p_assignment[i] >= 0 && i < p_members.size() && p_assignment[i] < p_slots_world.size()) {
			total += p_members[i].distance_to(p_slots_world[p_assignment[i]]);
		}
	}
	return total;
}

PackedVector2Array CgameFormations::blend(const PackedVector2Array &p_from_slots, const PackedVector2Array &p_to_slots, double p_t) {
	PackedVector2Array out;
	out.resize(p_to_slots.size());
	const real_t weight = CLAMP(p_t, 0.0, 1.0);
	for (int i = 0; i < p_to_slots.size(); i++) {
		const Vector2 a = i < p_from_slots.size() ? p_from_slots[i] : p_to_slots[i];
		out.write[i] = a.lerp(p_to_slots[i], weight);
	}
	return out;
}

PackedVector2Array CgameFormations::smooth(const PackedVector2Array &p_current, const PackedVector2Array &p_goal, double p_dt, double p_rate) {
	const double k = 1.0 - Math::exp(-MAX(0.0, p_rate) * MAX(0.0, p_dt));
	return blend(p_current, p_goal, k);
}

bool CgameFormations::_too_close(const Vector2 &p_c, const Vector<Vector2> &p_placed, double p_min_sep) {
	for (int i = 0; i < p_placed.size(); i++) {
		if (p_placed[i].distance_to(p_c) < p_min_sep) {
			return true;
		}
	}
	return false;
}

PackedVector2Array CgameFormations::shift_slots(const PackedVector2Array &p_slots_world, const Callable &p_walkable, const Vector2 &p_leader_pos, double p_spacing, int p_rings) {
	PackedVector2Array out = p_slots_world;
	const double min_sep = p_spacing * 0.5;
	Vector<Vector2> placed;
	// Walkable slots keep their place first so shifted ones avoid them.
	for (int i = 0; i < out.size(); i++) {
		if (bool(p_walkable.call(out[i]))) {
			placed.push_back(out[i]);
		}
	}
	for (int i = 0; i < out.size(); i++) {
		const Vector2 s = out[i];
		if (bool(p_walkable.call(s))) {
			continue;
		}
		bool found = false;
		const double step = MAX(1.0, p_spacing * 0.5);
		for (int ring = 1; ring <= p_rings; ring++) {
			const double radius = step * double(ring);
			const int samples = 8 + ring * 4;
			Vector2 best = s;
			double best_d = Math::INF;
			for (int k = 0; k < samples; k++) {
				const double a = Math::TAU * double(k) / double(samples);
				const Vector2 c = s + Vector2(Math::cos(a), Math::sin(a)) * radius;
				if (!bool(p_walkable.call(c))) {
					continue;
				}
				if (_too_close(c, placed, min_sep)) {
					continue;
				}
				const double d = c.distance_squared_to(s);
				if (d < best_d) {
					best_d = d;
					best = c;
				}
			}
			if (best_d < Math::INF) {
				out.write[i] = best;
				placed.push_back(best);
				found = true;
				break;
			}
		}
		if (!found) {
			// Pull toward the leader in small steps until something is walkable.
			const Vector2 to_leader = p_leader_pos - s;
			const double dist = to_leader.length();
			const Vector2 dir = to_leader / MAX(0.001, dist);
			double walked = 0.0;
			Vector2 fallback = p_leader_pos;
			while (walked < dist) {
				walked += step;
				const Vector2 c2 = s + dir * MIN(walked, dist);
				if (bool(p_walkable.call(c2))) {
					fallback = c2;
					break;
				}
			}
			out.write[i] = fallback;
			placed.push_back(fallback);
		}
	}
	return out;
}

void CgameFormations::_bind_methods() {
	ClassDB::bind_static_method("CgameFormations", D_METHOD("get_kinds"), &CgameFormations::get_kinds);
	ClassDB::bind_static_method("CgameFormations", D_METHOD("slots", "kind", "count", "spacing"), &CgameFormations::slots);
	ClassDB::bind_static_method("CgameFormations", D_METHOD("targets", "leader_pos", "leader_heading", "kind", "count", "spacing"), &CgameFormations::targets);
	ClassDB::bind_static_method("CgameFormations", D_METHOD("assign", "slots_world", "members"), &CgameFormations::assign);
	ClassDB::bind_static_method("CgameFormations", D_METHOD("assignment_cost", "slots_world", "members", "assignment"), &CgameFormations::assignment_cost);
	ClassDB::bind_static_method("CgameFormations", D_METHOD("blend", "from_slots", "to_slots", "t"), &CgameFormations::blend);
	ClassDB::bind_static_method("CgameFormations", D_METHOD("smooth", "current", "goal", "dt", "rate"), &CgameFormations::smooth, DEFVAL(6.0));
	ClassDB::bind_static_method("CgameFormations", D_METHOD("shift_slots", "slots_world", "walkable", "leader_pos", "spacing", "rings"), &CgameFormations::shift_slots, DEFVAL(6));

	BIND_CONSTANT(HUNGARIAN_LIMIT);
}
