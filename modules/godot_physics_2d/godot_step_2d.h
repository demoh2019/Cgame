/**************************************************************************/
/*  godot_step_2d.h                                                       */
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

#include "godot_space_2d.h"

#include "core/templates/a_hash_map.h"
#include "core/templates/local_vector.h"

class GodotStep2D {
	uint64_t _step = 1;

	int iterations = 0;
	real_t delta = 0.0;

	LocalVector<LocalVector<GodotBody2D *>> body_islands;
	LocalVector<LocalVector<GodotConstraint2D *>> constraint_islands;
	LocalVector<GodotConstraint2D *> all_constraints;
	// Filled only when pre_solve removes constraints from some islands.
	// Dense frames use direct island indices with no extra allocation.
	LocalVector<uint32_t> solve_island_indices;
	LocalVector<GodotBody2D *> pending_bodies; // Reused, bounded by the DFS frontier, not island depth.

	// Reused only for the opt-in single-large-island graph coloring path.
	LocalVector<GodotConstraint2D *> colored_constraints;
	LocalVector<uint8_t> constraint_colors;
	AHashMap<GodotBody2D *, uint32_t> occupied_colors;
	uint32_t color_batch_offset = 0;
	uint32_t color_batch_count = 0;
	// Read-only during worker dispatch. Used only when one large island is
	// graph-colored while the remaining islands use normal island jobs.
	uint32_t deferred_large_island_index = UINT32_MAX;

	void _populate_island(GodotBody2D *p_body, LocalVector<GodotBody2D *> &p_body_island, LocalVector<GodotConstraint2D *> &p_constraint_island);
	void _setup_constraint(uint32_t p_constraint_index, void *p_userdata = nullptr);
	void _pre_solve_island(LocalVector<GodotConstraint2D *> &p_constraint_island) const;
	void _solve_island(uint32_t p_island_index, void *p_userdata = nullptr) const;
	void _solve_island_except_large(uint32_t p_island_index, void *p_userdata = nullptr) const;
	void _solve_colored_constraint(uint32_t p_constraint_index, void *p_userdata = nullptr) const;
	void _solve_large_island(const LocalVector<GodotConstraint2D *> &p_constraint_island);
	void _check_suspend(LocalVector<GodotBody2D *> &p_body_island) const;

public:
	void step(GodotSpace2D *p_space, real_t p_delta);
	GodotStep2D();
	~GodotStep2D();
};
