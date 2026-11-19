/**************************************************************************/
/*  godot_step_2d.cpp                                                     */
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

#include "godot_step_2d.h"

#include "godot_constraint_2d.h"

#include "core/object/worker_thread_pool.h"
#include "core/templates/a_hash_map.h"
#include "core/os/os.h"

#define BODY_ISLAND_COUNT_RESERVE 128
#define ISLAND_COUNT_RESERVE 128
#define CONSTRAINT_COUNT_RESERVE 1024

// Prefer inline work for small batches; avoid thread pool wake-ups and barriers.
static constexpr uint32_t MIN_PARALLEL_SETUP_CONSTRAINTS = 32;
static constexpr uint32_t MIN_PARALLEL_SETUP_BATCH_SIZE = 16;
static constexpr uint32_t MIN_PARALLEL_SOLVE_ISLANDS = 16;
// Coloring is valuable only for large connected graphs. Small groups still run
// inline to avoid a thread-pool barrier per color and solver iteration.
static constexpr uint32_t MIN_PARALLEL_LARGE_ISLAND = 256;
static constexpr uint32_t MIN_PARALLEL_COLOR_CONSTRAINTS = 64;
// All constraints in a color have disjoint bodies. Keep at least 8 per
// worker invocation and increase the chunk size for very large colors.
static constexpr uint32_t MIN_PARALLEL_COLOR_BATCH_SIZE = 8;
static constexpr uint32_t MAX_LARGE_ISLAND_COLORS = 16;

void GodotStep2D::_populate_island(GodotBody2D *p_body, LocalVector<GodotBody2D *> &p_body_island, LocalVector<GodotConstraint2D *> &p_constraint_island) {
	// A recursive flood fill over a long chain of joints can exhaust the
	// physics thread's stack. Keep a reusable explicit DFS frontier instead.
	// Mark at enqueue time to avoid inserting the same body multiple times.
	pending_bodies.clear();
	p_body->set_island_step(_step);
	pending_bodies.push_back(p_body);

	while (!pending_bodies.is_empty()) {
		GodotBody2D *body = pending_bodies[pending_bodies.size() - 1];
		pending_bodies.remove_at(pending_bodies.size() - 1);

		if (body->get_mode() > PS2DE::BODY_MODE_KINEMATIC) {
			p_body_island.push_back(body);
		}

		for (const Pair<GodotConstraint2D *, int> &E : body->get_constraint_list()) {
			GodotConstraint2D *constraint = E.first;
			if (constraint->get_island_step() == _step) {
				continue;
			}
			constraint->set_island_step(_step);
			p_constraint_island.push_back(constraint);
			all_constraints.push_back(constraint);

			for (int i = 0; i < constraint->get_body_count(); i++) {
				if (i == E.second) {
					continue;
				}
				GodotBody2D *other_body = constraint->get_body_ptr()[i];
				if (other_body->get_island_step() == _step || other_body->get_mode() == PS2DE::BODY_MODE_STATIC) {
					continue;
				}
				other_body->set_island_step(_step);
				pending_bodies.push_back(other_body);
			}
		}
	}
}

void GodotStep2D::_integrate_forces_block(uint32_t p_block_index, void *p_userdata) {
	const uint32_t begin = p_block_index * PARALLEL_INTEGRATE_BLOCK_SIZE;
	const uint32_t end = MIN(begin + PARALLEL_INTEGRATE_BLOCK_SIZE, active_bodies.size());
	for (uint32_t body_index = begin; body_index < end; ++body_index) {
		// Broadphase updates for swept shapes are deferred: the broadphase is not thread safe.
		active_bodies[body_index]->integrate_forces(delta, true);
	}
}

void GodotStep2D::_setup_constraint(uint32_t p_constraint_index, void *p_userdata) {
	GodotConstraint2D *constraint = all_constraints[p_constraint_index];
	constraint->setup(delta);
}

void GodotStep2D::_setup_constraint_batch(uint32_t p_batch_index, void *p_userdata) {
	const uint32_t first = p_batch_index * setup_batch_size;
	const uint32_t end = first + MIN(setup_batch_size, all_constraints.size() - first);
	for (uint32_t i = first; i < end; ++i) {
		_setup_constraint(i, nullptr);
	}
}

void GodotStep2D::_pre_solve_island(LocalVector<GodotConstraint2D *> &p_constraint_island) const {
	uint32_t constraint_count = p_constraint_island.size();
	uint32_t valid_constraint_count = 0;
	for (uint32_t constraint_index = 0; constraint_index < constraint_count; ++constraint_index) {
		GodotConstraint2D *constraint = p_constraint_island[constraint_index];
		if (p_constraint_island[constraint_index]->pre_solve(delta)) {
			// Keep this constraint for solving.
			p_constraint_island[valid_constraint_count++] = constraint;
		}
	}
	p_constraint_island.resize(valid_constraint_count);
}

void GodotStep2D::_solve_island(uint32_t p_island_index, void *p_userdata) const {
	// Most frames have no pruned islands: the empty map retains direct indexing.
	const uint32_t island_index = solve_island_indices.is_empty() ? p_island_index : solve_island_indices[p_island_index];
	const LocalVector<GodotConstraint2D *> &constraint_island = constraint_islands[island_index];

	for (int i = 0; i < iterations; i++) {
		uint32_t constraint_count = constraint_island.size();
		for (uint32_t constraint_index = 0; constraint_index < constraint_count; ++constraint_index) {
			constraint_island[constraint_index]->solve(delta);
		}
	}
}

void GodotStep2D::_solve_island_except_large(uint32_t p_island_index, void *p_userdata) const {
	// Preserve ordinary island-level parallelism while one large island
	// is deferred to the graph-colored solver on the physics step thread.
	const uint32_t island_index = solve_island_indices.is_empty() ? p_island_index : solve_island_indices[p_island_index];
	if (island_index != deferred_large_island_index) {
		_solve_island(p_island_index, p_userdata);
	}
}

void GodotStep2D::_solve_colored_constraint(uint32_t p_constraint_index, void *p_userdata) const {
	const uint32_t first = p_constraint_index * color_batch_size;
	// Work out the end relative to the remaining elements; this also avoids
	// overflowing a 32-bit index at extreme constraint counts.
	const uint32_t end = first + MIN(color_batch_size, color_batch_count - first);
	for (uint32_t i = first; i < end; ++i) {
		colored_constraints[color_batch_offset + i]->solve(delta);
	}
}

bool GodotStep2D::_can_reuse_color_cache(const LocalVector<GodotConstraint2D *> &p_constraint_island, bool p_contact_only) const {
	const uint32_t count = p_constraint_island.size();
	if (!cached_color_valid || cached_color_contact_only != p_contact_only ||
			cached_color_topology.size() != count || colored_constraints.size() != count) {
		return false;
	}
	for (uint32_t i = 0; i < count; ++i) {
		GodotConstraint2D *constraint = p_constraint_island[i];
		const ColorCacheEntry &entry = cached_color_topology[i];
		if (entry.constraint != constraint) {
			return false;
		}
		const int body_count = constraint->get_body_count();
		if (body_count < 0 || body_count > 2 || entry.body_count != body_count) {
			return false;
		}
		GodotBody2D **bodies = constraint->get_body_ptr();
		if (body_count > 0 && bodies == nullptr) {
			return false;
		}
		GodotBody2D *body_A = body_count > 0 ? bodies[0] : nullptr;
		GodotBody2D *body_B = body_count > 1 ? bodies[1] : nullptr;
		if (entry.body_A != body_A || entry.body_B != body_B) {
			return false;
		}
		const uint8_t mode_A = body_A ? static_cast<uint8_t>(body_A->get_mode()) : 0;
		const uint8_t mode_B = body_B ? static_cast<uint8_t>(body_B->get_mode()) : 0;
		if (entry.mode_A != mode_A || entry.mode_B != mode_B) {
			return false;
		}
	}
	return true;
}

void GodotStep2D::_run_colored_batches(const uint32_t *p_sizes, const uint32_t *p_starts) {
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	const uint32_t worker_count = static_cast<uint32_t>(MAX(1, pool->get_thread_count()));
	// Limit scheduling to roughly four chunks per pool worker. The upper
	// bound prevents massive colors from producing thousands of tiny jobs
	// and keeps queue pressure bounded on machines with many logical CPUs.
	const uint32_t target_tasks = MIN(worker_count, uint32_t(32)) * 4;
	for (int iteration = 0; iteration < iterations; ++iteration) {
		for (uint32_t color = 0; color <= MAX_LARGE_ISLAND_COLORS; ++color) {
			const uint32_t count = p_sizes[color];
			if (count == 0) {
				continue;
			}
			const uint32_t start = p_starts[color];
			if (color != MAX_LARGE_ISLAND_COLORS && count >= MIN_PARALLEL_COLOR_CONSTRAINTS && worker_count > 1) {
				color_batch_offset = start;
				color_batch_count = count;
				// Ceiling division without count + divisor - 1 overflow.
				const uint32_t desired_batch_size = count / target_tasks + uint32_t(count % target_tasks != 0);
				color_batch_size = MAX(MIN_PARALLEL_COLOR_BATCH_SIZE, desired_batch_size);
				const uint32_t task_count = count / color_batch_size + uint32_t(count % color_batch_size != 0);
				WorkerThreadPool::GroupID group = pool->add_template_group_task(
						this, &GodotStep2D::_solve_colored_constraint, nullptr, task_count, -1, true, SNAME("Physics2DLargeIslandColor"));
				pool->wait_for_group_task_completion(group);
			} else {
				for (uint32_t i = start; i < start + count; ++i) {
					colored_constraints[i]->solve(delta);
				}
			}
		}
	}
}

void GodotStep2D::_solve_large_island(const LocalVector<GodotConstraint2D *> &p_constraint_island) {
	const uint32_t constraint_count = p_constraint_island.size();
	if (constraint_count < MIN_PARALLEL_LARGE_ISLAND) {
		for (int iteration = 0; iteration < iterations; ++iteration) {
			for (uint32_t i = 0; i < constraint_count; ++i) {
				p_constraint_island[i]->solve(delta);
			}
		}
		return;
	}

	// The rigid contact solver never writes to static or kinematic bodies.
	// A contact-only island can therefore share those read-only objects
	// between colors. Do not relax ownership for mixed islands containing
	// joints or user constraints: their solver semantics may be different.
	bool contact_only_island = true;
	for (uint32_t i = 0; i < constraint_count; ++i) {
		if (!p_constraint_island[i]->permits_parallel_immovable_body_sharing()) {
			contact_only_island = false;
			break;
		}
	}

	// Reuse the exact previous schedule when no constraint, endpoint or
	// body mode has changed. This skips hash lookups and counting sort.
	if (_can_reuse_color_cache(p_constraint_island, contact_only_island)) {
		_run_colored_batches(cached_color_sizes, cached_color_starts);
		return;
	}
	cached_color_valid = false;

	// Greedy constraint coloring: each dynamic body may be written by at
	// most one constraint within a color. The serial overflow handles hubs.
	// Reuse scratch allocations in persistent high-contact scenes.
	// Shrink after a drastic drop in size to avoid retaining the peak hash
	// table capacity when a million-body scene is replaced by a small one.
	if (occupied_colors.get_capacity() > MAX(uint32_t(1024), constraint_count * uint32_t(4))) {
		occupied_colors.reset();
	} else {
		occupied_colors.clear();
	}
	constraint_colors.resize(constraint_count);
	uint32_t group_sizes[MAX_LARGE_ISLAND_COLORS + 1] = {};

	for (uint32_t i = 0; i < constraint_count; ++i) {
		GodotConstraint2D *constraint = p_constraint_island[i];
		const int body_count = constraint->get_body_count();
		GodotBody2D **bodies = constraint->get_body_ptr();
		uint32_t forbidden = 0;
		uint32_t color = MAX_LARGE_ISLAND_COLORS;

		if (body_count > 0 && bodies != nullptr) {
			for (int body_idx = 0; body_idx < body_count; ++body_idx) {
				GodotBody2D *body = bodies[body_idx];
				if (body != nullptr && (!contact_only_island || body->get_mode() > PS2DE::BODY_MODE_KINEMATIC)) {
					const uint32_t *mask = occupied_colors.getptr(body);
					if (mask != nullptr) {
						forbidden |= *mask;
					}
				}
			}

			for (uint32_t candidate = 0; candidate < MAX_LARGE_ISLAND_COLORS; ++candidate) {
				if ((forbidden & (uint32_t(1) << candidate)) == 0) {
					color = candidate;
					break;
				}
			}

			if (color < MAX_LARGE_ISLAND_COLORS) {
				const uint32_t bit = uint32_t(1) << color;
				for (int body_idx = 0; body_idx < body_count; ++body_idx) {
					GodotBody2D *body = bodies[body_idx];
					if (body == nullptr || (contact_only_island && body->get_mode() <= PS2DE::BODY_MODE_KINEMATIC)) {
						continue;
					}
					uint32_t *mask = occupied_colors.getptr(body);
					if (mask != nullptr) {
						*mask |= bit;
					} else {
						occupied_colors.insert(body, bit);
					}
				}
			}
		}

		constraint_colors[i] = static_cast<uint8_t>(color);
		++group_sizes[color];
	}

	uint32_t parallelizable_count = 0;
	for (uint32_t color = 0; color < MAX_LARGE_ISLAND_COLORS; ++color) {
		if (group_sizes[color] >= MIN_PARALLEL_COLOR_CONSTRAINTS) {
			parallelizable_count += group_sizes[color];
		}
	}
	if (parallelizable_count < MIN_PARALLEL_LARGE_ISLAND) {
		// Too little independent work to amortize graph construction and
		// thread-pool wakeups. Preserve sequential constraint ordering.
		for (int iteration = 0; iteration < iterations; ++iteration) {
			for (uint32_t i = 0; i < constraint_count; ++i) {
				p_constraint_island[i]->solve(delta);
			}
		}
		return;
	}

	// Stable counting sort keeps the constraint order within each color.
	// The scratch array is a member reused across physics steps.
	uint32_t starts[MAX_LARGE_ISLAND_COLORS + 1];
	uint32_t cursors[MAX_LARGE_ISLAND_COLORS + 1];
	uint32_t offset = 0;
	for (uint32_t color = 0; color <= MAX_LARGE_ISLAND_COLORS; ++color) {
		starts[color] = offset;
		cursors[color] = offset;
		offset += group_sizes[color];
	}
	colored_constraints.resize(constraint_count);
	for (uint32_t i = 0; i < constraint_count; ++i) {
		colored_constraints[cursors[constraint_colors[i]]++] = p_constraint_island[i];
	}

	// A cache hit is valid only for the exact same constraint and body
	// topology. Avoid pointer-only equality: joint endpoints can be rebound
	// without the constraint object itself changing.
	bool cacheable = true;
	// Keep peak-cache RAM bounded when a once-huge island becomes small.
	if (cached_color_topology.get_capacity() > MAX(uint32_t(1024), constraint_count * uint32_t(4))) {
		cached_color_topology.reset();
	}
	cached_color_topology.resize(constraint_count);
	for (uint32_t i = 0; i < constraint_count; ++i) {
		GodotConstraint2D *constraint = p_constraint_island[i];
		const int body_count = constraint->get_body_count();
		GodotBody2D **bodies = constraint->get_body_ptr();
		if (body_count < 0 || body_count > 2 || (body_count > 0 && bodies == nullptr)) {
			cacheable = false;
			break;
		}
		ColorCacheEntry &entry = cached_color_topology[i];
		entry.constraint = constraint;
		entry.body_count = static_cast<uint8_t>(body_count);
		entry.body_A = body_count > 0 ? bodies[0] : nullptr;
		entry.body_B = body_count > 1 ? bodies[1] : nullptr;
		entry.mode_A = entry.body_A ? static_cast<uint8_t>(entry.body_A->get_mode()) : 0;
		entry.mode_B = entry.body_B ? static_cast<uint8_t>(entry.body_B->get_mode()) : 0;
	}
	if (cacheable) {
		cached_color_contact_only = contact_only_island;
		for (uint32_t color = 0; color <= MAX_LARGE_ISLAND_COLORS; ++color) {
			cached_color_sizes[color] = group_sizes[color];
			cached_color_starts[color] = starts[color];
		}
		cached_color_valid = true;
	} else {
		cached_color_topology.clear();
	}

	_run_colored_batches(group_sizes, starts);
}

void GodotStep2D::_check_suspend(LocalVector<GodotBody2D *> &p_body_island) const {
	bool can_sleep = true;

	uint32_t body_count = p_body_island.size();
	for (uint32_t body_index = 0; body_index < body_count; ++body_index) {
		GodotBody2D *body = p_body_island[body_index];

		if (!body->sleep_test(delta)) {
			can_sleep = false;
		}
	}

	// Put all to sleep or wake up everyone.
	for (uint32_t body_index = 0; body_index < body_count; ++body_index) {
		GodotBody2D *body = p_body_island[body_index];

		bool active = body->is_active();

		if (active == can_sleep) {
			body->set_active(!can_sleep);
		}
	}
}

void GodotStep2D::step(GodotSpace2D *p_space, real_t p_delta) {
	p_space->lock(); // can't access space during this

	p_space->setup(); //update inertias, etc

	p_space->set_last_step(p_delta);

	iterations = p_space->get_solver_iterations();
	delta = p_delta;

	const SelfList<GodotBody2D>::List *body_list = &p_space->get_active_body_list();

	/* INTEGRATE FORCES */

	uint64_t profile_begtime = OS::get_singleton()->get_ticks_usec();
	uint64_t profile_endtime = 0;

	int active_count = 0;

	const SelfList<GodotBody2D> *b = body_list->first();
	active_bodies.clear();
	while (b) {
		active_bodies.push_back(b->self());
		b = b->next();
		active_count++;
	}

	if (active_bodies.size() < PARALLEL_INTEGRATE_MIN_BODIES) {
		for (GodotBody2D *body : active_bodies) {
			body->integrate_forces(p_delta);
		}
	} else {
		const uint32_t block_count = (active_bodies.size() + PARALLEL_INTEGRATE_BLOCK_SIZE - 1) / PARALLEL_INTEGRATE_BLOCK_SIZE;
		WorkerThreadPool::GroupID group_task = WorkerThreadPool::get_singleton()->add_template_group_task(this, &GodotStep2D::_integrate_forces_block, nullptr, block_count, -1, true, SNAME("Physics2DIntegrateForces"));
		WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group_task);
		for (GodotBody2D *body : active_bodies) {
			body->apply_deferred_motion();
		}
	}

	p_space->set_active_objects(active_count);

	// Update the broadphase to register collision pairs.
	p_space->update();

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace2D::ELAPSED_TIME_INTEGRATE_FORCES, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	/* GENERATE CONSTRAINT ISLANDS FOR MOVING AREAS */

	uint32_t island_count = 0;

	const SelfList<GodotArea2D>::List &aml = p_space->get_moved_area_list();

	while (aml.first()) {
		for (GodotConstraint2D *E : aml.first()->self()->get_constraints()) {
			GodotConstraint2D *constraint = E;
			if (constraint->get_island_step() == _step) {
				continue;
			}
			constraint->set_island_step(_step);

			// Each constraint can be on a separate island for areas as there's no solving phase.
			++island_count;
			if (constraint_islands.size() < island_count) {
				constraint_islands.resize(island_count);
			}
			LocalVector<GodotConstraint2D *> &constraint_island = constraint_islands[island_count - 1];
			constraint_island.clear();

			all_constraints.push_back(constraint);
			constraint_island.push_back(constraint);
		}
		p_space->area_remove_from_moved_list((SelfList<GodotArea2D> *)aml.first()); //faster to remove here
	}

	/* GENERATE CONSTRAINT ISLANDS FOR ACTIVE RIGID BODIES */

	b = body_list->first();

	uint32_t body_island_count = 0;

	while (b) {
		GodotBody2D *body = b->self();

		// Unconnected active bodies need no constraint islands.
		// Avoid a heap allocation per body in large sparse simulations.
		if (body->get_island_step() != _step && !body->get_constraint_list().is_empty()) {
			++body_island_count;
			if (body_islands.size() < body_island_count) {
				body_islands.resize(body_island_count);
			}
			LocalVector<GodotBody2D *> &body_island = body_islands[body_island_count - 1];
			body_island.clear();
			// Allow sparse islands to allocate only the bodies they contain.

			++island_count;
			if (constraint_islands.size() < island_count) {
				constraint_islands.resize(island_count);
			}
			LocalVector<GodotConstraint2D *> &constraint_island = constraint_islands[island_count - 1];
			constraint_island.clear();
			// Most islands have few (or zero) constraints; grow on demand.

			_populate_island(body, body_island, constraint_island);

			if (body_island.is_empty()) {
				--body_island_count;
			}

			if (constraint_island.is_empty()) {
				--island_count;
			}
		}
		b = b->next();
	}

	p_space->set_island_count((int)island_count);

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace2D::ELAPSED_TIME_GENERATE_ISLANDS, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	/* SETUP CONSTRAINTS / PROCESS COLLISIONS */

	const uint32_t total_constraint_count = all_constraints.size();
	WorkerThreadPool *setup_pool = WorkerThreadPool::get_singleton();
	const uint32_t setup_workers = static_cast<uint32_t>(MAX(1, setup_pool->get_thread_count()));
	if (total_constraint_count < MIN_PARALLEL_SETUP_CONSTRAINTS || setup_workers == 1) {
		for (uint32_t constraint_index = 0; constraint_index < total_constraint_count; ++constraint_index) {
			_setup_constraint(constraint_index, nullptr);
		}
	} else {
		// Jolt-style setup batching. At most 4 callbacks per available worker
		// and 128 callbacks overall, even for a million active constraints.
		const uint32_t target_tasks = MIN(setup_workers, uint32_t(32)) * 4;
		const uint32_t desired_batch_size = total_constraint_count / target_tasks + uint32_t(total_constraint_count % target_tasks != 0);
		setup_batch_size = MAX(MIN_PARALLEL_SETUP_BATCH_SIZE, desired_batch_size);
		const uint32_t batch_count = total_constraint_count / setup_batch_size + uint32_t(total_constraint_count % setup_batch_size != 0);
		WorkerThreadPool::GroupID group_task = setup_pool->add_template_group_task(this, &GodotStep2D::_setup_constraint_batch, nullptr, batch_count, -1, true, SNAME("Physics2DConstraintSetup"));
		setup_pool->wait_for_group_task_completion(group_task);
	}

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace2D::ELAPSED_TIME_SETUP_CONSTRAINTS, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	/* PRE-SOLVE CONSTRAINT ISLANDS */

	// Pre-solve may disable every constraint in an island (e.g. moved
	// areas or non-contacting pairs). Do not schedule solver work for these.
	// Keep the full island list intact for sleeping and process metrics.
	uint32_t solve_island_count = 0;
	for (uint32_t island_index = 0; island_index < island_count; ++island_index) {
		_pre_solve_island(constraint_islands[island_index]);
		if (!constraint_islands[island_index].is_empty()) {
			++solve_island_count;
		}
	}

	// A compact index list pays for itself only when many jobs would be
	// empty. For dense scenes with just a few empty islands, dispatching
	// the no-op jobs is cheaper than allocating and indirection per task.
	solve_island_indices.clear();
	const uint32_t empty_island_count = island_count - solve_island_count;
	if (solve_island_count == 0) {
		// Nothing to dispatch, irrespective of how many islands existed.
	} else if (empty_island_count >= 32 && empty_island_count >= island_count / 4) {
		for (uint32_t island_index = 0; island_index < island_count; ++island_index) {
			if (!constraint_islands[island_index].is_empty()) {
				solve_island_indices.push_back(island_index);
			}
		}
	} else {
		// Keep direct indexing and avoid retaining a large index allocation
		// to skip only a handful of empty islands.
		solve_island_count = island_count;
	}

	/* SOLVE CONSTRAINT ISLANDS */

	// Preserve regular scheduling when the experimental option is disabled.
	// With multiple large *independent* islands, schedule islands in parallel
	// instead of paying a thread-pool barrier for every color/iteration in
	// each island. This follows Jolt's island-first scheduling strategy.
	// Graph coloring is useful when one large island would monopolize a
	// worker, even if there are other small islands in the space.
	uint32_t large_island_count = 0;
	uint32_t large_island_index = UINT32_MAX;
	if (p_space->is_parallel_large_islands_enabled()) {
		for (uint32_t i = 0; i < solve_island_count; ++i) {
			const uint32_t index = solve_island_indices.is_empty() ? i : solve_island_indices[i];
			if (constraint_islands[index].size() >= MIN_PARALLEL_LARGE_ISLAND) {
				large_island_index = index;
				++large_island_count;
				if (large_island_count == 2) {
					break; // Only need to distinguish zero, one or multiple.
				}
			}
		}
	}

	if (large_island_count != 1 && (!colored_constraints.is_empty() || !constraint_colors.is_empty() || !occupied_colors.is_empty())) {
		// Island-level jobs need no graph-color scratch. Free peak buffers
		// when a previously dominating island disappears or separates into
		// multiple independent islands, keeping idle RAM bounded.
		colored_constraints.reset();
		constraint_colors.reset();
		occupied_colors.reset();
		cached_color_topology.reset();
		cached_color_valid = false;
	}

	if (large_island_count == 1) {
		// Keep small islands on the existing scheduler, then solve the large
		// island by colors. No worker group overlaps the color solver, so
		// its shared scratch state is never accessed concurrently.
		deferred_large_island_index = large_island_index;
		if (solve_island_count >= MIN_PARALLEL_SOLVE_ISLANDS) {
			WorkerThreadPool::GroupID group_task = WorkerThreadPool::get_singleton()->add_template_group_task(this, &GodotStep2D::_solve_island_except_large, nullptr, solve_island_count, -1, true, SNAME("Physics2DOtherConstraintIslands"));
			WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group_task);
		} else {
			for (uint32_t island_index = 0; island_index < solve_island_count; ++island_index) {
				_solve_island_except_large(island_index, nullptr);
			}
		}
		_solve_large_island(constraint_islands[large_island_index]);
		deferred_large_island_index = UINT32_MAX;
	} else if (solve_island_count < MIN_PARALLEL_SOLVE_ISLANDS && large_island_count < 2) {
		// Few ordinary islands: retain the low-overhead sequential path.
		for (uint32_t island_index = 0; island_index < solve_island_count; ++island_index) {
			_solve_island(island_index, nullptr);
		}
	} else {
		// With at least two large islands, use one worker group for the full
		// solve, even if there are fewer than 16 islands. Each worker iterates
		// its island locally without color barriers or nested worker jobs.
		WorkerThreadPool::GroupID group_task = WorkerThreadPool::get_singleton()->add_template_group_task(this, &GodotStep2D::_solve_island, nullptr, solve_island_count, -1, true, SNAME("Physics2DConstraintSolveIslands"));
		WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group_task);
	}

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace2D::ELAPSED_TIME_SOLVE_CONSTRAINTS, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	/* INTEGRATE VELOCITIES */

	b = body_list->first();
	while (b) {
		const SelfList<GodotBody2D> *n = b->next();
		GodotBody2D *body = b->self();
		body->integrate_velocities(p_delta);
		// An unconnected rigid body is a one-body island. Evaluate its sleep
		// state without keeping a separate island allocation for it.
		// Constrained bodies still sleep together in _check_suspend().
		if (body->get_island_step() != _step && body->get_mode() > PS2DE::BODY_MODE_KINEMATIC && body->get_constraint_list().is_empty()) {
			const bool can_sleep = body->sleep_test(p_delta);
			if (body->is_active() == can_sleep) {
				body->set_active(!can_sleep);
			}
		}
		b = n; // in case it shuts itself down
	}

	/* SLEEP / WAKE UP ISLANDS */

	for (uint32_t island_index = 0; island_index < body_island_count; ++island_index) {
		_check_suspend(body_islands[island_index]);
	}

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace2D::ELAPSED_TIME_INTEGRATE_VELOCITIES, profile_endtime - profile_begtime);
		//profile_begtime=profile_endtime;
	}

	all_constraints.clear();

	p_space->unlock();
	_step++;
}

GodotStep2D::GodotStep2D() {
	body_islands.reserve(BODY_ISLAND_COUNT_RESERVE);
	constraint_islands.reserve(ISLAND_COUNT_RESERVE);
	all_constraints.reserve(CONSTRAINT_COUNT_RESERVE);
}

GodotStep2D::~GodotStep2D() {
}
