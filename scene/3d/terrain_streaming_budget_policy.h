/**************************************************************************/
/*  terrain_streaming_budget_policy.h                                     */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, merge, publish, distribute, */
/* sublicense, and/or sell copies of the Software, and to permit persons  */
/* to whom the Software is furnished to do so, subject to the following   */
/* conditions: The above copyright notice and this permission notice     */
/* shall be included in all copies or substantial portions of the        */
/* Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY   */
/* KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES */
/* OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/**************************************************************************/

#pragma once

#include <stdint.h>

// Shared, deterministic streaming policy; does not own clocks or renderer
// state. Callers supply time elapsed in the *current* main-thread frame.
namespace TerrainStreamingBudgetPolicy {

// One complete mesh is always permitted at the start of a frame, so extremely
// expensive source assets cannot permanently starve the streaming queue.
// A zero limit preserves the old eager mesh-generation behavior.
static inline bool may_build(uint64_t p_elapsed_usec, uint32_t p_budget_usec,
		uint32_t p_completed_this_frame) {
	return p_budget_usec == 0 || p_completed_this_frame == 0 ||
			p_elapsed_usec < uint64_t(p_budget_usec);
}

} // namespace TerrainStreamingBudgetPolicy
