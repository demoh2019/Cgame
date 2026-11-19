/**************************************************************************/
/*  godot_step_3d.h                                                       */
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

#pragma once

#include "godot_space_3d.h"

#include "core/templates/a_hash_map.h"
#include "core/templates/local_vector.h"

class GodotStep3D {
	uint64_t _step = 1;

	int iterations = 0;
	real_t delta = 0.0;

	LocalVector<LocalVector<GodotBody3D *>> body_islands;
	LocalVector<LocalVector<GodotConstraint3D *>> constraint_islands;
	// Avoid retaining peak nested island allocations after a large scene unload.
	uint8_t body_island_idle_steps = 0;
	uint8_t constraint_island_idle_steps = 0;
	LocalVector<GodotConstraint3D *> all_constraints;
	// Filled only when pre_solve removes constraints from some islands.
	// Dense frames use direct island indices with no extra allocation.
	LocalVector<uint32_t> solve_island_indices;
	// Reused only by the opt-in large rigid-body island coloring path.
	LocalVector<GodotConstraint3D *> colored_constraints;
	LocalVector<uint8_t> constraint_colors;
	AHashMap<GodotBody3D *, uint32_t> occupied_colors;
	// Cache a color schedule only when the exact constraint/body topology is
	// unchanged. Endpoint modes matter because contact-only islands can share
	// static/kinematic bodies while mixed islands cannot.
	struct ColorCacheEntry {
		GodotConstraint3D *constraint = nullptr;
		GodotBody3D *body_A = nullptr;
		GodotBody3D *body_B = nullptr;
		uint8_t body_count = 0;
		uint8_t mode_A = 0;
		uint8_t mode_B = 0;
	};
	LocalVector<ColorCacheEntry> cached_color_topology;
	uint32_t cached_color_sizes[17] = {};
	uint32_t cached_color_starts[17] = {};
	bool cached_color_contact_only = false;
	bool cached_color_valid = false;
	uint32_t color_batch_offset = 0;
	uint32_t color_batch_count = 0;
	uint32_t color_batch_size = 8; // Worker-aware task granularity, constant during each group.
	uint32_t setup_batch_size = 16; // Adaptive contiguous setup chunk.
	// Read only while other islands run in worker jobs. The colored solver
	// starts only after those jobs have completed.
	uint32_t deferred_large_island_index = UINT32_MAX;

	struct IslandTask {
		GodotBody3D *body = nullptr;
		GodotSoftBody3D *soft_body = nullptr;
	};
	LocalVector<IslandTask> pending_island_tasks; // Reused across bodies and spaces.

	// Force integration is independent per body and runs on worker threads once
	// there are enough active bodies to amortize the dispatch.
	enum {
		PARALLEL_INTEGRATE_MIN_BODIES = 2048,
		PARALLEL_INTEGRATE_BLOCK_SIZE = 128,
	};
	// Body snapshot being integrated by the parallel force-integration job.
	const LocalVector<GodotBody3D *> *integrate_bodies = nullptr;

	void _populate_island_graph(GodotBody3D *p_body, GodotSoftBody3D *p_soft_body, LocalVector<GodotBody3D *> &p_body_island, LocalVector<GodotConstraint3D *> &p_constraint_island);
	void _populate_island(GodotBody3D *p_body, LocalVector<GodotBody3D *> &p_body_island, LocalVector<GodotConstraint3D *> &p_constraint_island);
	void _populate_island_soft_body(GodotSoftBody3D *p_soft_body, LocalVector<GodotBody3D *> &p_body_island, LocalVector<GodotConstraint3D *> &p_constraint_island);
	void _setup_constraint(uint32_t p_constraint_index, void *p_userdata = nullptr);
	void _setup_constraint_batch(uint32_t p_batch_index, void *p_userdata = nullptr);
	void _integrate_forces_block(uint32_t p_block_index, void *p_userdata = nullptr);
	void _pre_solve_island(LocalVector<GodotConstraint3D *> &p_constraint_island) const;
	void _solve_island(uint32_t p_island_index, void *p_userdata = nullptr);
	void _solve_island_except_large(uint32_t p_island_index, void *p_userdata = nullptr);
	void _solve_colored_constraint(uint32_t p_constraint_index, void *p_userdata = nullptr) const;
	bool _can_reuse_color_cache(const LocalVector<GodotConstraint3D *> &p_constraint_island, bool p_contact_only) const;
	void _run_colored_batches(const uint32_t *p_sizes, const uint32_t *p_starts);
	// Returns false when graph coloring is not profitable or safe for this island.
	bool _solve_large_island(const LocalVector<GodotConstraint3D *> &p_constraint_island);
	void _check_suspend(const LocalVector<GodotBody3D *> &p_body_island) const;

public:
	void step(GodotSpace3D *p_space, real_t p_delta);
	GodotStep3D();
	~GodotStep3D();
};
