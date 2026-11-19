/**************************************************************************/
/*  physics_island_storage.h                                              */
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

#include "core/templates/local_vector.h"

// Both GodotPhysics2D and GodotPhysics3D keep nested island vectors between
// steps to avoid allocations in normal steady-state physics. A one-off burst
// of thousands of separate islands can otherwise keep every *inner* buffer
// allocated for the entire lifetime of the space.
//
// Reclaim only after 16 consecutive quiet steps. Remove at most 1024 island
// slots per step so a million-island scene collapsing to a small scene never
// incurs a single massive destructor/free spike. All calls must happen after
// every solver, sleeping and soft-body pass has finished using the vectors.
//
// r_idle_steps is independent for body and constraint islands.
template <typename T>
static inline void godot_physics_reclaim_idle_island_storage(LocalVector<LocalVector<T>> &r_islands, uint32_t p_live_islands, uint8_t &r_idle_steps) {
	constexpr uint32_t MIN_RETAINED_ISLANDS = 128;
	constexpr uint32_t MAX_RELEASE_PER_STEP = 1024;
	constexpr uint8_t QUIET_STEPS_BEFORE_RECLAIM = 16;

	const uint32_t stored = r_islands.size();
	// Keep the normal scratch reuse path almost free. Dividing avoids
	// overflow from multiplying a potentially huge live-island count.
	if (stored <= MIN_RETAINED_ISLANDS * 4 || p_live_islands >= stored / 4) {
		r_idle_steps = 0;
		return;
	}

	if (r_idle_steps < QUIET_STEPS_BEFORE_RECLAIM) {
		++r_idle_steps;
		if (r_idle_steps < QUIET_STEPS_BEFORE_RECLAIM) {
			return;
		}
	}

	// This cannot overflow: reaching here means live < stored / 4.
	const uint32_t retain = MAX(MIN_RETAINED_ISLANDS, p_live_islands * 2);
	const uint32_t release = MIN(stored - retain, MAX_RELEASE_PER_STEP);
	r_islands.resize(stored - release); // Runs nested LocalVector destructors.

	// Shrink the outer array less frequently, after releasing enough inner
	// buffers. Do not force a large realloc/memmove on every quiet step.
	if (r_islands.get_capacity() / 2 > r_islands.size() || r_islands.size() == retain) {
		r_islands.shrink_to(r_islands.size());
	}
}
