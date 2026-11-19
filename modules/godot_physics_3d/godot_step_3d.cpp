/**************************************************************************/
/*  godot_step_3d.cpp                                                     */
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

#include "godot_step_3d.h"

#include "godot_constraint_3d.h"

#include "core/object/worker_thread_pool.h"
#include "core/templates/hash_map.h"
#include "core/os/os.h"

#define BODY_ISLAND_COUNT_RESERVE 128
#define ISLAND_COUNT_RESERVE 128
#define CONSTRAINT_COUNT_RESERVE 1024

// Avoid worker pool task/wakeup overhead when the workload is smaller than a batch.
static constexpr uint32_t MIN_PARALLEL_SETUP_CONSTRAINTS = 32;
static constexpr uint32_t MIN_PARALLEL_SOLVE_ISLANDS = 16;

// Parallel graph coloring only pays off for large connected rigid-body groups.
static constexpr uint32_t MIN_PARALLEL_LARGE_ISLAND = 256;
static constexpr uint32_t MIN_PARALLEL_COLOR_CONSTRAINTS = 64;
// Solve a short contiguous run of independent constraints per worker task.
// This follows the already-batched 2D solver and amortizes task scheduling.
static constexpr uint32_t PARALLEL_COLOR_BATCH_SIZE = 8;
static constexpr uint32_t MAX_LARGE_ISLAND_COLORS = 16;

void GodotStep3D::_populate_island_graph(GodotBody3D *p_body, GodotSoftBody3D *p_soft_body, LocalVector<GodotBody3D *> &p_body_island, LocalVector<GodotConstraint3D *> &p_constraint_island) {
	// Handle rigid and soft bodies in one explicit DFS. Mark when scheduled,
	// not when popped, so cycles and heavily connected islands cannot enqueue
	// the same body repeatedly. Long joint chains no longer consume C++ stack.
	pending_island_tasks.clear();
	if (p_body) {
		p_body->set_island_step(_step);
		pending_island_tasks.push_back(IslandTask{ p_body, nullptr });
	} else {
		p_soft_body->set_island_step(_step);
		pending_island_tasks.push_back(IslandTask{ nullptr, p_soft_body });
	}

	while (!pending_island_tasks.is_empty()) {
		const IslandTask task = pending_island_tasks[pending_island_tasks.size() - 1];
		pending_island_tasks.remove_at(pending_island_tasks.size() - 1);

		if (task.body) {
			GodotBody3D *body = task.body;
			if (body->get_mode() > PS3DE::BODY_MODE_KINEMATIC) {
				p_body_island.push_back(body);
			}
			for (const KeyValue<GodotConstraint3D *, int> &E : body->get_constraint_map()) {
				GodotConstraint3D *constraint = E.key;
				if (constraint->get_island_step() == _step) {
					continue;
				}
				constraint->set_island_step(_step);
				p_constraint_island.push_back(constraint);
				all_constraints.push_back(constraint);

				for (int i = 0; i < constraint->get_body_count(); i++) {
					if (i == E.value) {
						continue;
					}
					GodotBody3D *other = constraint->get_body_ptr()[i];
					if (other->get_island_step() == _step || other->get_mode() == PS3DE::BODY_MODE_STATIC) {
						continue;
					}
					other->set_island_step(_step);
					pending_island_tasks.push_back(IslandTask{ other, nullptr });
				}
				for (int i = 0; i < constraint->get_soft_body_count(); i++) {
					GodotSoftBody3D *other = constraint->get_soft_body_ptr(i);
					if (other->get_island_step() == _step) {
						continue;
					}
					other->set_island_step(_step);
					pending_island_tasks.push_back(IslandTask{ nullptr, other });
				}
			}
		} else {
			for (GodotConstraint3D *constraint : task.soft_body->get_constraints()) {
				if (constraint->get_island_step() == _step) {
					continue;
				}
				constraint->set_island_step(_step);
				p_constraint_island.push_back(constraint);
				all_constraints.push_back(constraint);

				for (int i = 0; i < constraint->get_body_count(); i++) {
					GodotBody3D *other = constraint->get_body_ptr()[i];
					if (other->get_island_step() == _step || other->get_mode() == PS3DE::BODY_MODE_STATIC) {
						continue;
					}
					other->set_island_step(_step);
					pending_island_tasks.push_back(IslandTask{ other, nullptr });
				}
			}
		}
	}
}

void GodotStep3D::_populate_island(GodotBody3D *p_body, LocalVector<GodotBody3D *> &p_body_island, LocalVector<GodotConstraint3D *> &p_constraint_island) {
	_populate_island_graph(p_body, nullptr, p_body_island, p_constraint_island);
}

void GodotStep3D::_populate_island_soft_body(GodotSoftBody3D *p_soft_body, LocalVector<GodotBody3D *> &p_body_island, LocalVector<GodotConstraint3D *> &p_constraint_island) {
	_populate_island_graph(nullptr, p_soft_body, p_body_island, p_constraint_island);
}

void GodotStep3D::_setup_constraint(uint32_t p_constraint_index, void *p_userdata) {
	GodotConstraint3D *constraint = all_constraints[p_constraint_index];
	constraint->setup(delta);
}

void GodotStep3D::_pre_solve_island(LocalVector<GodotConstraint3D *> &p_constraint_island) const {
	uint32_t constraint_count = p_constraint_island.size();
	uint32_t valid_constraint_count = 0;
	for (uint32_t constraint_index = 0; constraint_index < constraint_count; ++constraint_index) {
		GodotConstraint3D *constraint = p_constraint_island[constraint_index];
		if (p_constraint_island[constraint_index]->pre_solve(delta)) {
			// Keep this constraint for solving.
			p_constraint_island[valid_constraint_count++] = constraint;
		}
	}
	p_constraint_island.resize(valid_constraint_count);
}

void GodotStep3D::_solve_island(uint32_t p_island_index, void *p_userdata) {
	// Most frames have no pruned islands: the empty map retains direct indexing.
	const uint32_t island_index = solve_island_indices.is_empty() ? p_island_index : solve_island_indices[p_island_index];
	LocalVector<GodotConstraint3D *> &constraint_island = constraint_islands[island_index];

	int current_priority = 1;

	uint32_t constraint_count = constraint_island.size();
	while (constraint_count > 0) {
		for (int i = 0; i < iterations; i++) {
			// Go through all iterations.
			for (uint32_t constraint_index = 0; constraint_index < constraint_count; ++constraint_index) {
				constraint_island[constraint_index]->solve(delta);
			}
		}

		// Check priority to keep only higher priority constraints.
		uint32_t priority_constraint_count = 0;
		++current_priority;
		for (uint32_t constraint_index = 0; constraint_index < constraint_count; ++constraint_index) {
			GodotConstraint3D *constraint = constraint_island[constraint_index];
			if (constraint->get_priority() >= current_priority) {
				// Keep this constraint for the next iteration.
				constraint_island[priority_constraint_count++] = constraint;
			}
		}
		constraint_count = priority_constraint_count;
	}
}



void GodotStep3D::_solve_island_except_large(uint32_t p_island_index, void *p_userdata) {
	// Resolve the optional compact island mapping before comparing against the
	// physical island index, so empty pre-solve islands do not break the skip.
	const uint32_t island_index = solve_island_indices.is_empty() ? p_island_index : solve_island_indices[p_island_index];
	if (island_index != deferred_large_island_index) {
		_solve_island(p_island_index, p_userdata);
	}
}

void GodotStep3D::_solve_colored_constraint(uint32_t p_constraint_index, void *p_userdata) const {
	const uint32_t first = p_constraint_index * PARALLEL_COLOR_BATCH_SIZE;
	const uint32_t end = MIN(first + PARALLEL_COLOR_BATCH_SIZE, color_batch_count);
	for (uint32_t i = first; i < end; ++i) {
		colored_constraints[color_batch_offset + i]->solve(delta);
	}
}

bool GodotStep3D::_solve_large_island(const LocalVector<GodotConstraint3D *> &p_constraint_island) {
	const uint32_t constraint_count = p_constraint_island.size();
	if (constraint_count < MIN_PARALLEL_LARGE_ISLAND) {
		return false;
	}

	// Preserve the regular solver's priority passes and avoid soft-body races.
	// Both require special scheduling not represented by rigid-body coloring.
	for (uint32_t i = 0; i < constraint_count; ++i) {
		const GodotConstraint3D *constraint = p_constraint_island[i];
		if (constraint->get_priority() != 1 || constraint->get_soft_body_count() != 0 ||
				constraint->get_body_count() == 0 || constraint->get_body_ptr() == nullptr) {
			return false;
		}
	}

	// In a contact-only island static/kinematic bodies are read-only:
	// ordinary rigid contact constraints never apply impulses to them.
	// Do not share these bodies when even one joint is present; such
	// constraints are not guaranteed to keep immovable bodies untouched.
	bool contact_only_island = true;
	for (uint32_t i = 0; i < constraint_count; ++i) {
		if (!p_constraint_island[i]->permits_parallel_immovable_body_sharing()) {
			contact_only_island = false;
			break;
		}
	}

	// Greedy coloring remains exclusive for every dynamic body and for
	// ALL bodies in mixed joint/contact islands. Overflow stays serial.
	HashMap<GodotBody3D *, uint32_t> occupied_colors;
	LocalVector<uint8_t> constraint_colors;
	constraint_colors.resize(constraint_count);
	uint32_t group_sizes[MAX_LARGE_ISLAND_COLORS + 1] = {};

	for (uint32_t i = 0; i < constraint_count; ++i) {
		GodotConstraint3D *constraint = p_constraint_island[i];
		const int body_count = constraint->get_body_count();
		GodotBody3D **bodies = constraint->get_body_ptr();
		uint32_t forbidden = 0;
		for (int body_idx = 0; body_idx < body_count; ++body_idx) {
			GodotBody3D *body = bodies[body_idx];
			if (body != nullptr && (!contact_only_island || body->get_mode() > PS3DE::BODY_MODE_KINEMATIC)) {
				const uint32_t *mask = occupied_colors.getptr(body);
				if (mask != nullptr) {
					forbidden |= *mask;
				}
			}
		}

		uint32_t color = MAX_LARGE_ISLAND_COLORS;
		for (uint32_t candidate = 0; candidate < MAX_LARGE_ISLAND_COLORS; ++candidate) {
			if ((forbidden & (uint32_t(1) << candidate)) == 0) {
				color = candidate;
				break;
			}
		}
		if (color < MAX_LARGE_ISLAND_COLORS) {
			const uint32_t bit = uint32_t(1) << color;
			for (int body_idx = 0; body_idx < body_count; ++body_idx) {
				GodotBody3D *body = bodies[body_idx];
				if (body == nullptr || (contact_only_island && body->get_mode() <= PS3DE::BODY_MODE_KINEMATIC)) {
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
		constraint_colors[i] = color;
		++group_sizes[color];
	}

	uint32_t parallelizable_count = 0;
	for (uint32_t color = 0; color < MAX_LARGE_ISLAND_COLORS; ++color) {
		if (group_sizes[color] >= MIN_PARALLEL_COLOR_CONSTRAINTS) {
			parallelizable_count += group_sizes[color];
		}
	}
	if (parallelizable_count < MIN_PARALLEL_LARGE_ISLAND) {
		// Keep the original sequential ordering if worker wakeups would
		// dominate. Never modify the input constraint island.
		return false;
	}

	// Stable counting sort by color. Reuse the member scratch allocation on
	// subsequent steps, avoiding per-frame allocations for large scenes.
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

	for (int iteration = 0; iteration < iterations; ++iteration) {
		for (uint32_t color = 0; color <= MAX_LARGE_ISLAND_COLORS; ++color) {
			const uint32_t count = group_sizes[color];
			if (count == 0) {
				continue;
			}
			const uint32_t start = starts[color];
			if (color != MAX_LARGE_ISLAND_COLORS && count >= MIN_PARALLEL_COLOR_CONSTRAINTS) {
				color_batch_offset = start;
				color_batch_count = count;
				// Each task handles several constraints of the same color. Their
				// bodies do not overlap; the barrier below prevents cross-color races.
				const uint32_t task_count = count / PARALLEL_COLOR_BATCH_SIZE + (count % PARALLEL_COLOR_BATCH_SIZE != 0);
				WorkerThreadPool::GroupID group = WorkerThreadPool::get_singleton()->add_template_group_task(
						this, &GodotStep3D::_solve_colored_constraint, nullptr, task_count, -1, true, SNAME("Physics3DLargeIslandColor"));
				// Barrier: a later color may touch the bodies updated here.
				WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group);
			} else {
				for (uint32_t i = start; i < start + count; ++i) {
					colored_constraints[i]->solve(delta);
				}
			}
		}
	}
	return true;
}


void GodotStep3D::_check_suspend(const LocalVector<GodotBody3D *> &p_body_island) const {
	bool can_sleep = true;

	uint32_t body_count = p_body_island.size();
	for (uint32_t body_index = 0; body_index < body_count; ++body_index) {
		GodotBody3D *body = p_body_island[body_index];

		if (!body->sleep_test(delta)) {
			can_sleep = false;
		}
	}

	// Put all to sleep or wake up everyone.
	for (uint32_t body_index = 0; body_index < body_count; ++body_index) {
		GodotBody3D *body = p_body_island[body_index];

		bool active = body->is_active();

		if (active == can_sleep) {
			body->set_active(!can_sleep);
		}
	}
}

void GodotStep3D::step(GodotSpace3D *p_space, real_t p_delta) {
	p_space->lock(); // can't access space during this

	p_space->setup(); //update inertias, etc

	p_space->set_last_step(p_delta);

	iterations = p_space->get_solver_iterations();
	delta = p_delta;

	const SelfList<GodotBody3D>::List *body_list = &p_space->get_active_body_list();

	const SelfList<GodotSoftBody3D>::List *soft_body_list = &p_space->get_active_soft_body_list();

	/* INTEGRATE FORCES */

	uint64_t profile_begtime = OS::get_singleton()->get_ticks_usec();
	uint64_t profile_endtime = 0;

	int active_count = 0;

	const SelfList<GodotBody3D> *b = body_list->first();
	while (b) {
		b->self()->integrate_forces(p_delta);
		b = b->next();
		active_count++;
	}

	/* UPDATE SOFT BODY MOTION */

	const SelfList<GodotSoftBody3D> *sb = soft_body_list->first();
	while (sb) {
		sb->self()->predict_motion(p_delta);
		sb = sb->next();
		active_count++;
	}

	p_space->set_active_objects(active_count);

	// Update the broadphase to register collision pairs.
	p_space->update();

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace3D::ELAPSED_TIME_INTEGRATE_FORCES, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	/* GENERATE CONSTRAINT ISLANDS FOR MOVING AREAS */

	uint32_t island_count = 0;

	const SelfList<GodotArea3D>::List &aml = p_space->get_moved_area_list();

	while (aml.first()) {
		for (GodotConstraint3D *E : aml.first()->self()->get_constraints()) {
			GodotConstraint3D *constraint = E;
			if (constraint->get_island_step() == _step) {
				continue;
			}
			constraint->set_island_step(_step);

			// Each constraint can be on a separate island for areas as there's no solving phase.
			++island_count;
			if (constraint_islands.size() < island_count) {
				constraint_islands.resize(island_count);
			}
			LocalVector<GodotConstraint3D *> &constraint_island = constraint_islands[island_count - 1];
			constraint_island.clear();

			all_constraints.push_back(constraint);
			constraint_island.push_back(constraint);
		}
		p_space->area_remove_from_moved_list((SelfList<GodotArea3D> *)aml.first()); //faster to remove here
	}

	/* GENERATE CONSTRAINT ISLANDS FOR ACTIVE RIGID BODIES */

	b = body_list->first();

	uint32_t body_island_count = 0;

	while (b) {
		GodotBody3D *body = b->self();

		// Unconnected rigid bodies need no solver island. Avoid keeping
		// millions of tiny island vectors for sparse simulations.
		if (body->get_island_step() != _step && !body->get_constraint_map().is_empty()) {
			++body_island_count;
			if (body_islands.size() < body_island_count) {
				body_islands.resize(body_island_count);
			}
			LocalVector<GodotBody3D *> &body_island = body_islands[body_island_count - 1];
			body_island.clear();
			// Allow sparse islands to allocate only the bodies they contain.

			++island_count;
			if (constraint_islands.size() < island_count) {
				constraint_islands.resize(island_count);
			}
			LocalVector<GodotConstraint3D *> &constraint_island = constraint_islands[island_count - 1];
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

	/* GENERATE CONSTRAINT ISLANDS FOR ACTIVE SOFT BODIES */

	sb = soft_body_list->first();
	while (sb) {
		GodotSoftBody3D *soft_body = sb->self();

		if (soft_body->get_island_step() != _step) {
			++body_island_count;
			if (body_islands.size() < body_island_count) {
				body_islands.resize(body_island_count);
			}
			LocalVector<GodotBody3D *> &body_island = body_islands[body_island_count - 1];
			body_island.clear();
			// Allow sparse islands to allocate only the bodies they contain.

			++island_count;
			if (constraint_islands.size() < island_count) {
				constraint_islands.resize(island_count);
			}
			LocalVector<GodotConstraint3D *> &constraint_island = constraint_islands[island_count - 1];
			constraint_island.clear();
			// Most islands have few (or zero) constraints; grow on demand.

			_populate_island_soft_body(soft_body, body_island, constraint_island);

			if (body_island.is_empty()) {
				--body_island_count;
			}

			if (constraint_island.is_empty()) {
				--island_count;
			}
		}
		sb = sb->next();
	}

	p_space->set_island_count((int)island_count);

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace3D::ELAPSED_TIME_GENERATE_ISLANDS, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	/* SETUP CONSTRAINTS / PROCESS COLLISIONS */

	const uint32_t total_constraint_count = all_constraints.size();
	if (total_constraint_count < MIN_PARALLEL_SETUP_CONSTRAINTS) {
		for (uint32_t constraint_index = 0; constraint_index < total_constraint_count; ++constraint_index) {
			_setup_constraint(constraint_index, nullptr);
		}
	} else {
		WorkerThreadPool::GroupID group_task = WorkerThreadPool::get_singleton()->add_template_group_task(this, &GodotStep3D::_setup_constraint, nullptr, total_constraint_count, -1, true, SNAME("Physics3DConstraintSetup"));
		WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group_task);
	}

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace3D::ELAPSED_TIME_SETUP_CONSTRAINTS, profile_endtime - profile_begtime);
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

	// WARNING: `_solve_island` modifies the constraint islands for optimization purpose,
	// their content is not reliable after these calls and shouldn't be used anymore.
	// Schedule one dominant island by graph coloring even if other independent
	// islands exist. Process the remaining islands first and wait for their
	// jobs, so graph-color jobs never overlap regular island solver jobs.
	// Multiple large islands are better scheduled directly as independent
	// workers, avoiding per-color barriers on each one.
	uint32_t large_island_count = 0;
	uint32_t large_island_index = UINT32_MAX;
	uint32_t large_island_job_index = UINT32_MAX;
	if (p_space->is_parallel_large_islands_enabled()) {
		for (uint32_t i = 0; i < solve_island_count; ++i) {
			const uint32_t index = solve_island_indices.is_empty() ? i : solve_island_indices[i];
			if (constraint_islands[index].size() >= MIN_PARALLEL_LARGE_ISLAND) {
				if (large_island_count == 0) {
					large_island_index = index;
					large_island_job_index = i;
				}
				if (++large_island_count == 2) {
					break; // We only need to distinguish zero, one and many.
				}
			}
		}
	}

	if (large_island_count == 1) {
		deferred_large_island_index = large_island_index;
		if (solve_island_count >= MIN_PARALLEL_SOLVE_ISLANDS) {
			WorkerThreadPool::GroupID group_task = WorkerThreadPool::get_singleton()->add_template_group_task(
					this, &GodotStep3D::_solve_island_except_large, nullptr, solve_island_count, -1, true, SNAME("Physics3DOtherConstraintIslands"));
			WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group_task);
		} else {
			for (uint32_t i = 0; i < solve_island_count; ++i) {
				_solve_island_except_large(i, nullptr);
			}
		}
		// Priority and soft-body cases retain the original sequential solver.
		if (!_solve_large_island(constraint_islands[large_island_index])) {
			_solve_island(large_island_job_index, nullptr);
		}
		deferred_large_island_index = UINT32_MAX;
	} else if (solve_island_count < MIN_PARALLEL_SOLVE_ISLANDS && large_island_count < 2) {
		for (uint32_t island_index = 0; island_index < solve_island_count; ++island_index) {
			_solve_island(island_index, nullptr);
		}
	} else {
		// At least two large islands have enough independent work to justify
		// worker dispatch even when there are fewer than 16 total islands.
		WorkerThreadPool::GroupID group_task = WorkerThreadPool::get_singleton()->add_template_group_task(this, &GodotStep3D::_solve_island, nullptr, solve_island_count, -1, true, SNAME("Physics3DConstraintSolveIslands"));
		WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group_task);
	}

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace3D::ELAPSED_TIME_SOLVE_CONSTRAINTS, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	/* INTEGRATE VELOCITIES */

	b = body_list->first();
	while (b) {
		const SelfList<GodotBody3D> *n = b->next();
		GodotBody3D *body = b->self();
		body->integrate_velocities(p_delta);
		// Unconnected rigid bodies can be suspended individually after
		// integration. The connected islands still use _check_suspend().
		if (body->get_island_step() != _step && body->get_mode() > PS3DE::BODY_MODE_KINEMATIC && body->get_constraint_map().is_empty()) {
			const bool can_sleep = body->sleep_test(p_delta);
			if (body->is_active() == can_sleep) {
				body->set_active(!can_sleep);
			}
		}
		b = n;
	}

	/* SLEEP / WAKE UP ISLANDS */

	for (uint32_t island_index = 0; island_index < body_island_count; ++island_index) {
		_check_suspend(body_islands[island_index]);
	}

	/* UPDATE SOFT BODY CONSTRAINTS */

	sb = soft_body_list->first();
	while (sb) {
		sb->self()->solve_constraints(p_delta);
		sb = sb->next();
	}

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace3D::ELAPSED_TIME_INTEGRATE_VELOCITIES, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	all_constraints.clear();

	p_space->unlock();
	_step++;
}

GodotStep3D::GodotStep3D() {
	body_islands.reserve(BODY_ISLAND_COUNT_RESERVE);
	constraint_islands.reserve(ISLAND_COUNT_RESERVE);
	all_constraints.reserve(CONSTRAINT_COUNT_RESERVE);
}

GodotStep3D::~GodotStep3D() {
}
