/**************************************************************************/
/*  cgame_crowd_avoidance.cpp                                             */
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

#include "cgame_crowd_avoidance.h"

#include "core/object/class_db.h"
#include "core/object/worker_thread_pool.h"
#include "core/templates/hash_map.h"

// Invalid agents are isolated before constructing any velocity constraints.
static bool crowd_agent_valid(const Vector2 &p_position, const Vector2 &p_velocity) {
	return p_position.is_finite() && p_velocity.is_finite() &&
			Math::abs(p_position.x) <= 10000000.0 && Math::abs(p_position.y) <= 10000000.0;
}

static Vector2 crowd_bounded_preference(const Vector2 &p_preferred, real_t p_max_speed) {
	return p_preferred.is_finite() ? p_preferred.limit_length(p_max_speed) : Vector2();
}

// Uniform spatial hash: agent indices sorted by cell, with a cell -> range map.
struct CgameCrowdAvoidance::Grid {
	struct Range {
		uint32_t start = 0;
		uint32_t count = 0;
	};

	struct Entry {
		int64_t key = 0;
		uint32_t index = 0;
	};

	struct EntryLess {
		bool operator()(const Entry &p_a, const Entry &p_b) const {
			if (p_a.key != p_b.key) {
				return p_a.key < p_b.key;
			}
			return p_a.index < p_b.index;
		}
	};

	real_t cell = 1.0;
	LocalVector<uint32_t> sorted;
	HashMap<int64_t, Range> ranges;

	static int32_t cell_coord(real_t p_value, real_t p_cell) {
		const real_t c = Math::floor(p_value / p_cell);
		if (!Math::is_finite(c)) {
			return 0;
		}
		return (int32_t)CLAMP(c, (real_t)-1073741824.0, (real_t)1073741824.0);
	}

	static int64_t key(int32_t p_x, int32_t p_y) {
		return int64_t(p_x) * INT64_C(4294967296) + int64_t(uint32_t(p_y));
	}

	void build(const Vector2 *p_positions, const Vector2 *p_velocities, uint32_t p_count, real_t p_cell) {
		cell = p_cell;
		LocalVector<Entry> entries;
		for (uint32_t i = 0; i < p_count; i++) {
			if (!crowd_agent_valid(p_positions[i], p_velocities[i])) {
				continue;
			}
			Entry entry;
			entry.key = key(cell_coord(p_positions[i].x, cell), cell_coord(p_positions[i].y, cell));
			entry.index = i;
			entries.push_back(entry);
		}
		// Total order on (key, index): fully deterministic.
		entries.sort_custom<EntryLess>();
		sorted.resize(entries.size());
		uint32_t i = 0;
		while (i < entries.size()) {
			uint32_t j = i;
			const int64_t k = entries[i].key;
			while (j < entries.size() && entries[j].key == k) {
				sorted[j] = entries[j].index;
				j++;
			}
			Range r;
			r.start = i;
			r.count = j - i;
			ranges.insert(k, r);
			i = j;
		}
	}
};

struct CgameCrowdAvoidance::ThreadData {
	const Vector2 *positions = nullptr;
	const Vector2 *velocities = nullptr;
	const Vector2 *preferred = nullptr;
	Vector2 *out = nullptr;
	uint32_t count = 0;
	Params params;
	const Grid *grid = nullptr;
};

bool CgameCrowdAvoidance::_linear_program1(const LocalVector<Line> &p_lines, uint32_t p_line_no, real_t p_radius, const Vector2 &p_opt, bool p_direction_opt, Vector2 &r_result) {
	const Vector2 pt = p_lines[p_line_no].point;
	const Vector2 dr = p_lines[p_line_no].direction;
	const real_t dot = pt.dot(dr);
	const real_t disc = dot * dot + p_radius * p_radius - pt.length_squared();
	if (disc < 0.0) {
		return false;
	}
	const real_t sd = Math::sqrt(disc);
	real_t t_left = -dot - sd;
	real_t t_right = -dot + sd;
	for (uint32_t i = 0; i < p_line_no; i++) {
		const real_t denom = _det(dr, p_lines[i].direction);
		const real_t numer = _det(p_lines[i].direction, pt - p_lines[i].point);
		if (Math::abs(denom) <= EPSILON) {
			if (numer < 0.0) {
				return false;
			}
			continue;
		}
		const real_t t = numer / denom;
		if (denom >= 0.0) {
			t_right = MIN(t_right, t);
		} else {
			t_left = MAX(t_left, t);
		}
		if (t_left > t_right) {
			return false;
		}
	}
	if (p_direction_opt) {
		r_result = pt + (p_opt.dot(dr) > 0.0 ? t_right : t_left) * dr;
	} else {
		r_result = pt + CLAMP(dr.dot(p_opt - pt), t_left, t_right) * dr;
	}
	return true;
}

// Returns the index of the first infeasible line, or the line count when all are satisfied.
uint32_t CgameCrowdAvoidance::_linear_program2(const LocalVector<Line> &p_lines, real_t p_radius, const Vector2 &p_opt, bool p_direction_opt, Vector2 &r_result) {
	if (p_direction_opt) {
		r_result = p_opt * p_radius;
	} else if (p_opt.length_squared() > p_radius * p_radius) {
		r_result = p_opt.normalized() * p_radius;
	} else {
		r_result = p_opt;
	}
	for (uint32_t i = 0; i < p_lines.size(); i++) {
		if (_det(p_lines[i].direction, p_lines[i].point - r_result) > 0.0) {
			const Vector2 backup = r_result;
			if (!_linear_program1(p_lines, i, p_radius, p_opt, p_direction_opt, r_result)) {
				r_result = backup;
				return i;
			}
		}
	}
	return p_lines.size();
}

// Fallback when no feasible velocity exists: minimise the maximum constraint violation
// (a 3D linear program over the velocity disc and the violation distance).
void CgameCrowdAvoidance::_linear_program3(const LocalVector<Line> &p_lines, uint32_t p_begin, real_t p_radius, Vector2 &r_result) {
	real_t distance = 0.0;
	LocalVector<Line> projected;
	for (uint32_t i = p_begin; i < p_lines.size(); i++) {
		if (_det(p_lines[i].direction, p_lines[i].point - r_result) > distance) {
			projected.clear();
			for (uint32_t j = 0; j < i; j++) {
				Line line;
				const real_t d = _det(p_lines[i].direction, p_lines[j].direction);
				if (Math::abs(d) <= EPSILON) {
					if (p_lines[i].direction.dot(p_lines[j].direction) > 0.0) {
						continue;
					}
					line.point = 0.5 * (p_lines[i].point + p_lines[j].point);
				} else {
					line.point = p_lines[i].point + (_det(p_lines[j].direction, p_lines[i].point - p_lines[j].point) / d) * p_lines[i].direction;
				}
				line.direction = (p_lines[j].direction - p_lines[i].direction).normalized();
				projected.push_back(line);
			}
			const Vector2 backup = r_result;
			const Vector2 opt = Vector2(-p_lines[i].direction.y, p_lines[i].direction.x);
			if (_linear_program2(projected, p_radius, opt, true, r_result) < projected.size()) {
				r_result = backup;
			}
			distance = _det(p_lines[i].direction, p_lines[i].point - r_result);
		}
	}
}

void CgameCrowdAvoidance::_compute_range(const ThreadData &p_data, uint32_t p_begin, uint32_t p_end) {
	const Params &prm = p_data.params;
	const Grid &grid = *p_data.grid;
	const real_t cell = grid.cell;
	const real_t nd_sq = prm.neighbor_dist * prm.neighbor_dist;
	const real_t inv_t = 1.0 / MAX(prm.time_horizon, EPSILON);
	const real_t inv_dt = 1.0 / MAX(prm.time_step, (real_t)0.0001);
	const real_t combined = prm.radius * 2.0;
	const real_t combined_sq = combined * combined;
	const uint32_t max_neighbors = (uint32_t)MAX(prm.max_neighbors, 0);

	LocalVector<uint32_t> neigh_idx;
	LocalVector<real_t> neigh_d;
	LocalVector<Line> lines;

	for (uint32_t i = p_begin; i < p_end; i++) {
		const Vector2 pi = p_data.positions[i];
		const Vector2 vi = p_data.velocities[i];
		if (!crowd_agent_valid(pi, vi)) {
			p_data.out[i] = Vector2();
			continue;
		}
		const Vector2 pref = crowd_bounded_preference(p_data.preferred[i], prm.max_speed);
		neigh_idx.clear();
		neigh_d.clear();
		const int32_t cx = Grid::cell_coord(pi.x, cell);
		const int32_t cy = Grid::cell_coord(pi.y, cell);
		if (max_neighbors > 0) {
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					const Grid::Range *range = grid.ranges.getptr(Grid::key(cx + dx, cy + dy));
					if (!range) {
						continue;
					}
					for (uint32_t b = 0; b < range->count; b++) {
						const uint32_t j = grid.sorted[range->start + b];
						if (j == i) {
							continue;
						}
						const real_t dsq = pi.distance_squared_to(p_data.positions[j]);
						if (!(dsq < nd_sq)) {
							continue;
						}
						// Sorted insertion by (distance, index), capped at max_neighbors.
						if (neigh_idx.size() >= max_neighbors) {
							const uint32_t last = neigh_idx.size() - 1;
							if (dsq > neigh_d[last] || (dsq == neigh_d[last] && j > neigh_idx[last])) {
								continue;
							}
						}
						uint32_t at = neigh_idx.size();
						while (at > 0 && (neigh_d[at - 1] > dsq || (neigh_d[at - 1] == dsq && neigh_idx[at - 1] > j))) {
							at--;
						}
						neigh_idx.insert(at, j);
						neigh_d.insert(at, dsq);
						if (neigh_idx.size() > max_neighbors) {
							neigh_idx.resize(max_neighbors);
							neigh_d.resize(max_neighbors);
						}
					}
				}
			}
		}

		if (neigh_idx.is_empty()) {
			p_data.out[i] = pref;
			continue;
		}
		lines.clear();
		for (uint32_t k = 0; k < neigh_idx.size(); k++) {
			const uint32_t j = neigh_idx[k];
			const Vector2 rel_pos = p_data.positions[j] - pi;
			const Vector2 rel_vel = vi - p_data.velocities[j];
			const real_t dist_sq = rel_pos.length_squared();
			Vector2 dir;
			Vector2 u;
			if (dist_sq > combined_sq) {
				const Vector2 w = rel_vel - inv_t * rel_pos;
				const real_t w_sq = w.length_squared();
				const real_t dot1 = w.dot(rel_pos);
				if (dot1 < 0.0 && dot1 * dot1 > combined_sq * w_sq) {
					const real_t w_len = Math::sqrt(w_sq);
					const Vector2 unit_w = w / w_len;
					dir = Vector2(unit_w.y, -unit_w.x);
					u = (combined * inv_t - w_len) * unit_w;
				} else {
					const real_t leg = Math::sqrt(dist_sq - combined_sq);
					if (_det(rel_pos, w) > 0.0) {
						dir = Vector2(rel_pos.x * leg - rel_pos.y * combined, rel_pos.x * combined + rel_pos.y * leg) / dist_sq;
					} else {
						dir = -Vector2(rel_pos.x * leg + rel_pos.y * combined, -rel_pos.x * combined + rel_pos.y * leg) / dist_sq;
					}
					u = rel_vel.dot(dir) * dir - rel_vel;
				}
			} else {
				// Already overlapping: resolve within one time step.
				const Vector2 w = rel_vel - inv_dt * rel_pos;
				const real_t w_len = w.length();
				const Vector2 unit_w = w_len < EPSILON ? Vector2(1.0, 0.0) : w / w_len;
				dir = Vector2(unit_w.y, -unit_w.x);
				u = (combined * inv_dt - w_len) * unit_w;
			}
			Line line;
			line.point = vi + 0.5 * u;
			line.direction = dir;
			lines.push_back(line);
		}

		Vector2 result;
		const uint32_t fail = _linear_program2(lines, prm.max_speed, pref, false, result);
		if (fail < lines.size()) {
			_linear_program3(lines, fail, prm.max_speed, result);
		}
		p_data.out[i] = result.is_finite() ? result.limit_length(prm.max_speed) : pref;
	}
}

void CgameCrowdAvoidance::_task(void *p_userdata, uint32_t p_task) {
	const ThreadData &data = *static_cast<const ThreadData *>(p_userdata);
	const uint32_t begin = p_task * AGENTS_PER_TASK;
	const uint32_t end = MIN(begin + AGENTS_PER_TASK, data.count);
	_compute_range(data, begin, end);
}

void CgameCrowdAvoidance::compute(const Vector2 *p_positions, const Vector2 *p_velocities, const Vector2 *p_preferred, uint32_t p_count, const Params &p_params, Vector2 *r_out) {
	if (p_count == 0) {
		return;
	}
	if (!Math::is_finite(p_params.max_speed) || p_params.max_speed <= 0.0 ||
			!Math::is_finite(p_params.radius) || p_params.radius < 0.0 ||
			!Math::is_finite(p_params.neighbor_dist) || !Math::is_finite(p_params.time_horizon) ||
			!Math::is_finite(p_params.time_step)) {
		for (uint32_t i = 0; i < p_count; i++) {
			r_out[i] = Vector2();
		}
		return;
	}
	if (p_count == 1 || p_params.max_neighbors <= 0 || p_params.neighbor_dist <= 0.0 ||
			p_params.time_horizon <= 0.0 || p_params.time_step <= 0.0 || p_params.radius <= 0.0) {
		for (uint32_t i = 0; i < p_count; i++) {
			r_out[i] = crowd_agent_valid(p_positions[i], p_velocities[i]) ?
					crowd_bounded_preference(p_preferred[i], p_params.max_speed) : Vector2();
		}
		return;
	}
	Grid grid;
	grid.build(p_positions, p_velocities, p_count, MAX(p_params.neighbor_dist, (real_t)0.001));
	ThreadData data;
	data.positions = p_positions;
	data.velocities = p_velocities;
	data.preferred = p_preferred;
	data.out = r_out;
	data.count = p_count;
	data.params = p_params;
	data.grid = &grid;

	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	if (p_count < PARALLEL_THRESHOLD || pool == nullptr) {
		_compute_range(data, 0, p_count);
		return;
	}
	const int tasks = (int)((p_count + AGENTS_PER_TASK - 1) / AGENTS_PER_TASK);
	WorkerThreadPool::GroupID group = pool->add_native_group_task(&CgameCrowdAvoidance::_task, &data, tasks, -1, true, "CgameCrowdAvoidance");
	pool->wait_for_group_task_completion(group);
}

PackedVector2Array CgameCrowdAvoidance::compute_velocities(const PackedVector2Array &p_positions, const PackedVector2Array &p_velocities, const PackedVector2Array &p_preferred, real_t p_radius, real_t p_max_speed, real_t p_time_horizon, real_t p_neighbor_dist, int p_max_neighbors, real_t p_time_step) {
	const int n = p_positions.size();
	PackedVector2Array out;
	out.resize(n);
	if (n == 0) {
		return out;
	}
	if (p_velocities.size() != n || p_preferred.size() != n) {
		out.fill(Vector2());
		return out;
	}
	Params params;
	params.radius = p_radius;
	params.max_speed = p_max_speed;
	params.time_horizon = p_time_horizon;
	params.neighbor_dist = p_neighbor_dist;
	params.max_neighbors = p_max_neighbors;
	params.time_step = p_time_step;
	compute(p_positions.ptr(), p_velocities.ptr(), p_preferred.ptr(), (uint32_t)n, params, out.ptrw());
	return out;
}

void CgameCrowdAvoidance::_bind_methods() {
	ClassDB::bind_static_method("CgameCrowdAvoidance", D_METHOD("compute_velocities", "positions", "velocities", "preferred", "radius", "max_speed", "time_horizon", "neighbor_dist", "max_neighbors", "time_step"), &CgameCrowdAvoidance::compute_velocities, DEFVAL(0.1));
}
