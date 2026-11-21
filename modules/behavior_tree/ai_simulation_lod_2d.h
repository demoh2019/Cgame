/**************************************************************************/
/*  ai_simulation_lod_2d.h                                                  */
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

#include "core/object/ref_counted.h"

// Stateless per-agent simulation LOD policy. Games supply distances to their
// already authorized viewers and decide which AI work may be time-sliced.
// Never throttles physics, attacks, timers, damage, or network authority.
class AISimulationLOD2D : public RefCounted {
	GDCLASS(AISimulationLOD2D, RefCounted);

	real_t near_interval = 0.25;
	real_t medium_interval = 0.5;
	real_t far_interval = 1.0;

protected:
	static void _bind_methods();

public:
	// Atomic configuration prevents incoherent interval tiers.
	// Bounds: 0 < near <= medium <= far <= 2 seconds.
	bool configure_intervals(real_t p_near, real_t p_medium, real_t p_far);

	real_t get_near_interval() const;
	real_t get_medium_interval() const;
	real_t get_far_interval() const;

	// Distances are metres in the caller's 2D world. Positive infinity means
	// there are no eligible viewers; invalid inputs fail closed to near rate.
	real_t get_interval(real_t p_distance, real_t p_near_distance, real_t p_far_distance, bool p_urgent = false) const;

	// Stable simulation LOD for moving viewers. The caller stores the last
	// chosen nominal interval; the engine itself stays stateless and sharable.
	// Entering the near range immediately restores full responsiveness.
	real_t get_hysteretic_interval(real_t p_distance, real_t p_near_distance, real_t p_far_distance,
			real_t p_previous_interval, real_t p_hysteresis, bool p_urgent = false) const;

	// One-time deterministic startup phase for distant inactive agents, spread
	// over 16 bins based on a stable non-negative ID. Do not call every tick.
	real_t get_staggered_interval(int64_t p_agent_id, real_t p_distance, real_t p_near_distance, real_t p_far_distance, bool p_urgent = false) const;
};
