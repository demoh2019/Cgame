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
#include "core/os/os.h"
#include "servers/physics_constraint_color.h"
#include "servers/physics_island_storage.h"

#define BODY_ISLAND_COUNT_RESERVE 128
#define ISLAND_COUNT_RESERVE 128
#define CONSTRAINT_COUNT_RESERVE 1024

// Avoid worker pool task/wakeup overhead when the workload is smaller than a batch.
static constexpr uint32_t MIN_PARALLEL_SETUP_CONSTRAINTS = 32;
// Amortize thread-pool callback dispatch across independent constraints.
static constexpr uint32_t MIN_PARALLEL_SETUP_BATCH_SIZE = 16;
static constexpr uint32_t MIN_PARALLEL_SOLVE_ISLANDS = 16;

// Parallel graph coloring only pays off for large connected rigid-body groups.
static constexpr uint32_t MIN_PARALLEL_LARGE_ISLAND = 256;
static constexpr uint32_t MIN_PARALLEL_COLOR_CONSTRAINTS = 64;
// Limit scheduler callbacks while preserving the per-color barrier. A
// color requires at least 8 constraints per worker call; large colors use
// proportionally larger batches based on the available worker pool size.
static constexpr uint32_t MIN_PARALLEL_COLOR_BATCH_SIZE = 8;
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
			for (const Pair<GodotConstraint3D *, int> &E : body->get_constraint_list()) {
				GodotConstraint3D *constraint = E.first;
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

void GodotStep3D::_integrate_forces_block(uint32_t p_block_index, void *p_userdata) {
	const uint32_t begin = p_block_index * PARALLEL_INTEGRATE_BLOCK_SIZE;
	const uint32_t end = MIN(begin + PARALLEL_INTEGRATE_BLOCK_SIZE, integrate_bodies->size());
	for (uint32_t body_index = begin; body_index < end; ++body_index) {
		// Broadphase updates for swept shapes are deferred: the broadphase is not thread safe.
		(*integrate_bodies)[body_index]->integrate_forces(delta, true);
	}
}

void GodotStep3D::_setup_constraint(uint32_t p_constraint_index, void *p_userdata) {
	GodotConstraint3D *constraint = all_constraints[p_constraint_index];
	constraint->setup(delta);
}

void GodotStep3D::_setup_constraint_batch(uint32_t p_batch_index, void *p_userdata) {
	const uint32_t begin = p_batch_index * setup_batch_size;
	const uint32_t end = begin + MIN(setup_batch_size, all_constraints.size() - begin);
	for (uint32_t constraint_index = begin; constraint_index < end; ++constraint_index) {
		_setup_constraint(constraint_index, nullptr);
	}
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
	const uint32_t first = p_constraint_index * color_batch_size;
	// The remaining-count form avoids overflow at very large 32-bit counts.
	const uint32_t end = first + MIN(color_batch_size, color_batch_count - first);
	for (uint32_t i = first; i < end; ++i) {
		colored_constraints[color_batch_offset + i]->solve(delta);
	}
}

bool GodotStep3D::_can_reuse_color_cache(const LocalVector<GodotConstraint3D *> &p_constraint_island, bool p_contact_only) const {
	const uint32_t count = p_constraint_island.size();
	if (!cached_color_valid || cached_color_contact_only != p_contact_only ||
			cached_color_topology.size() != count || colored_constraints.size() != count) {
		return false;
	}
	for (uint32_t i = 0; i < count; ++i) {
		GodotConstraint3D *constraint = p_constraint_island[i];
		const ColorCacheEntry &entry = cached_color_topology[i];
		if (entry.constraint != constraint) {
			return false;
		}
		const int body_count = constraint->get_body_count();
		if (body_count < 0 || body_count > 2 || entry.body_count != body_count) {
			return false;
		}
		GodotBody3D **bodies = constraint->get_body_ptr();
		if (body_count > 0 && bodies == nullptr) {
			return false;
		}
		GodotBody3D *body_A = body_count > 0 ? bodies[0] : nullptr;
		GodotBody3D *body_B = body_count > 1 ? bodies[1] : nullptr;
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

void GodotStep3D::_run_colored_batches(const uint32_t *p_sizes, const uint32_t *p_starts) {
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	const uint32_t worker_count = static_cast<uint32_t>(MAX(1, pool->get_thread_count()));
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
				// At most four worker chunks per thread, capped at 128 per color,
				// regardless of the number of contacts sharing this color.
				const uint32_t desired_batch_size = count / target_tasks + uint32_t(count % target_tasks != 0);
				color_batch_size = MAX(MIN_PARALLEL_COLOR_BATCH_SIZE, desired_batch_size);
				const uint32_t task_count = count / color_batch_size + uint32_t(count % color_batch_size != 0);
				WorkerThreadPool::GroupID group = pool->add_template_group_task(
						this, &GodotStep3D::_solve_colored_constraint, nullptr, task_count, -1, true, SNAME("Physics3DLargeIslandColor"));
				pool->wait_for_group_task_completion(group);
			} else {
				for (uint32_t i = start; i < start + count; ++i) {
					colored_constraints[i]->solve(delta);
				}
			}
		}
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

	// Exact-topology cache hits avoid rebuilding the conflict graph.
	if (_can_reuse_color_cache(p_constraint_island, contact_only_island)) {
		_run_colored_batches(cached_color_sizes, cached_color_starts);
		return true;
	}
	cached_color_valid = false;

	// Greedy coloring remains exclusive for every dynamic body and for
	// ALL bodies in mixed joint/contact islands. Overflow stays serial.
	// Reuse the previous step's allocation for dense contact workloads.
	// Release exceptionally oversized hash buffers when the island shrinks.
	if (occupied_colors.get_capacity() > MAX(uint32_t(1024), constraint_count * uint32_t(4))) {
		occupied_colors.reset();
	} else {
		occupied_colors.clear();
	}
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

		// Match the previous greedy color ordering with one bit scan.
		// The sentinel is unchanged when all 16 colors are occupied.
		const uint32_t color = godot_physics_first_available_constraint_color<MAX_LARGE_ISLAND_COLORS>(forbidden);
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

	// Save exact constraint identities and endpoints. Pointer equality alone
	// is insufficient because the endpoints of a joint can be reassigned.
	bool cacheable = true;
	if (cached_color_topology.get_capacity() > MAX(uint32_t(1024), constraint_count * uint32_t(4))) {
		cached_color_topology.reset();
	}
	cached_color_topology.resize(constraint_count);
	for (uint32_t i = 0; i < constraint_count; ++i) {
		GodotConstraint3D *constraint = p_constraint_island[i];
		const int body_count = constraint->get_body_count();
		GodotBody3D **bodies = constraint->get_body_ptr();
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

	const SelfList<GodotSoftBody3D>::List *soft_body_list = &p_space->get_active_soft_body_list();

	/* INTEGRATE FORCES */

	uint64_t profile_begtime = OS::get_singleton()->get_ticks_usec();
	uint64_t profile_endtime = 0;

	int active_count = 0;

	const LocalVector<GodotBody3D *> *active_bodies = &p_space->get_active_bodies();
	active_count = (int)active_bodies->size();

	if (active_bodies->size() < PARALLEL_INTEGRATE_MIN_BODIES) {
		for (GodotBody3D *body : *active_bodies) {
			body->integrate_forces(p_delta);
		}
	} else {
		integrate_bodies = active_bodies;
		const uint32_t block_count = (active_bodies->size() + PARALLEL_INTEGRATE_BLOCK_SIZE - 1) / PARALLEL_INTEGRATE_BLOCK_SIZE;
		WorkerThreadPool::GroupID group_task = WorkerThreadPool::get_singleton()->add_template_group_task(this, &GodotStep3D::_integrate_forces_block, nullptr, block_count, -1, true, SNAME("Physics3DIntegrateForces"));
		WorkerThreadPool::get_singleton()->wait_for_group_task_completion(group_task);
		for (GodotBody3D *body : *active_bodies) {
			body->apply_deferred_motion(p_delta);
		}
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

	// Activations during the broadphase update (e.g. kinematic bodies entering areas) rebuild the snapshot.
	active_bodies = &p_space->get_active_bodies();

	uint32_t body_island_count = 0;

	for (GodotBody3D *body : *active_bodies) {

		// Unconnected rigid bodies need no solver island. Avoid keeping
		// millions of tiny island vectors for sparse simulations.
		if (body->get_island_step() != _step && !body->get_constraint_list().is_empty()) {
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
	WorkerThreadPool *setup_pool = WorkerThreadPool::get_singleton();
	const uint32_t setup_workers = static_cast<uint32_t>(MAX(1, setup_pool->get_thread_count()));
	if (total_constraint_count < MIN_PARALLEL_SETUP_CONSTRAINTS || setup_workers == 1) {
		for (uint32_t constraint_index = 0; constraint_index < total_constraint_count; ++constraint_index) {
			_setup_constraint(constraint_index, nullptr);
		}
	} else {
		// Adapt contiguous setup chunks to the worker count. Keep the queue
		// bounded to 128 tasks in large scenes without changing setup order
		// inside a batch or the barrier before pre_solve.
		const uint32_t target_tasks = MIN(setup_workers, uint32_t(32)) * 4;
		const uint32_t desired_batch_size = total_constraint_count / target_tasks + uint32_t(total_constraint_count % target_tasks != 0);
		setup_batch_size = MAX(MIN_PARALLEL_SETUP_BATCH_SIZE, desired_batch_size);
		const uint32_t batch_count = total_constraint_count / setup_batch_size + uint32_t(total_constraint_count % setup_batch_size != 0);
		WorkerThreadPool::GroupID group_task = setup_pool->add_template_group_task(this, &GodotStep3D::_setup_constraint_batch, nullptr, batch_count, -1, true, SNAME("Physics3DConstraintSetup"));
		setup_pool->wait_for_group_task_completion(group_task);
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

	if (large_island_count != 1 && (!colored_constraints.is_empty() || !constraint_colors.is_empty() || !occupied_colors.is_empty())) {
		// No graph-colored island this frame. Release the previous giant
		// island's scratch to keep peak memory from lingering in light scenes.
		colored_constraints.reset();
		constraint_colors.reset();
		occupied_colors.reset();
		cached_color_topology.reset();
		cached_color_valid = false;
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

	active_bodies = &p_space->get_active_bodies();
	for (GodotBody3D *body : *active_bodies) {
		body->integrate_velocities(p_delta);
		// Unconnected rigid bodies can be suspended individually after
		// integration. The connected islands still use _check_suspend().
		if (body->get_island_step() != _step && body->get_mode() > PS3DE::BODY_MODE_KINEMATIC && body->get_constraint_list().is_empty()) {
			const bool can_sleep = body->sleep_test(p_delta);
			if (body->is_active() == can_sleep) {
				body->set_active(!can_sleep);
			}
		}
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

	// Experimental soft-body/soft-body vertex-face contacts. This runs only
	// AFTER all body-local XPBD constraints, so both sides have finalized
	// positions/velocities. Zero thickness skips the entire O(body^2) loop.
	// Limit not only successful contacts but also AABB pair checks: many
	// separated soft bodies must never cause unbounded quadratic CPU work.
	const real_t pair_thickness = p_space->get_soft_body_pair_collision_thickness();
	const bool pair_ccd = p_space->is_soft_body_pair_collision_ccd_enabled();
	if (pair_thickness > real_t(0.0) && soft_body_list->first() != nullptr &&
			soft_body_list->first()->next() != nullptr) {
		const real_t pair_compliance = p_space->get_soft_body_pair_collision_compliance();
		const real_t pair_friction = p_space->get_soft_body_pair_collision_friction();
		const uint32_t max_contacts = uint32_t(p_space->get_soft_body_pair_max_contacts());
		const uint32_t max_pairs = uint32_t(p_space->get_soft_body_pair_max_pairs());
		const uint32_t max_pair_checks = 16384;
		const uint32_t max_contacts_per_vertex = 8;
		uint32_t checked_pairs = 0;
		uint32_t candidate_pairs = 0;
		bool budget_exhausted = false;
		const SelfList<GodotSoftBody3D> *first = soft_body_list->first();
		while (first && !budget_exhausted) {
			const SelfList<GodotSoftBody3D> *second = first->next();
			while (second) {
				if (checked_pairs >= max_pair_checks || candidate_pairs >= max_pairs) {
					budget_exhausted = true;
					break;
				}
				++checked_pairs;
				GodotSoftBody3D *a = first->self();
				GodotSoftBody3D *b = second->self();
				second = second->next();
				if (!a->interacts_with(b) ||
						a->has_exception(b->get_self()) || b->has_exception(a->get_self())) {
					continue;
				}
				AABB expanded = pair_ccd ? a->get_pair_swept_bounds() : a->get_bounds();
				expanded.grow_by(pair_thickness);
				if (!expanded.intersects(pair_ccd ? b->get_pair_swept_bounds() : b->get_bounds())) {
					continue;
				}
				++candidate_pairs;
				a->solve_pair_contacts(*b, p_delta, pair_thickness,
						pair_compliance, pair_friction, max_contacts, max_contacts_per_vertex);
			}
			first = first->next();
		}
	}

	{ //profile
		profile_endtime = OS::get_singleton()->get_ticks_usec();
		p_space->set_elapsed_time(GodotSpace3D::ELAPSED_TIME_INTEGRATE_VELOCITIES, profile_endtime - profile_begtime);
		profile_begtime = profile_endtime;
	}

	all_constraints.clear();

	// All constraint/soft-body work and parallel workers have finished.
	// Bounded reclamation releases old peak scratch memory only during
	// sustained low-island workloads, never from active solver workers.
	godot_physics_reclaim_idle_island_storage(body_islands, body_island_count, body_island_idle_steps);
	godot_physics_reclaim_idle_island_storage(constraint_islands, island_count, constraint_island_idle_steps);

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
