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

#define BODY_ISLAND_COUNT_RESERVE 128
#define ISLAND_COUNT_RESERVE 128
#define CONSTRAINT_COUNT_RESERVE 1024

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
	if (total_constraint_count == 1) {
		// Dispatching a thread group for a single constraint costs more than
		// running the setup inline on the already active physics thread.
		_setup_constraint(0, nullptr);
	} else if (total_constraint_count > 1) {
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

	// Avoid an extra index buffer when all islands have work. For sparse
	// scenes, compact only active indices, not the island vectors themselves.
	solve_island_indices.clear();
	if (solve_island_count != island_count) {
		for (uint32_t island_index = 0; island_index < island_count; ++island_index) {
			if (!constraint_islands[island_index].is_empty()) {
				solve_island_indices.push_back(island_index);
			}
		}
	}

	/* SOLVE CONSTRAINT ISLANDS */

	// WARNING: `_solve_island` modifies the constraint islands for optimization purpose,
	// their content is not reliable after these calls and shouldn't be used anymore.
	if (solve_island_count == 1) {
		// A single island cannot be solved in parallel with another island.
		// Avoid queueing workers and immediately waiting for them.
		_solve_island(0, nullptr);
	} else if (solve_island_count > 1) {
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
