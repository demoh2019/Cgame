/**************************************************************************/
/*  terrain_streaming_priority_policy.h                                   */
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
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions: The above copyright notice and this         */
/* permission notice shall be included in all copies or substantial      */
/* portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT    */
/* WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED   */
/* TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE */
/* AND NONINFRINGEMENT.                                                    */
/**************************************************************************/

#pragma once

#include <stdint.h>

// Deterministic per-node terrain mesh candidate order. This is deliberately
// separate from LOD *selection* (which already accounts for screen-pixel
// error); only the order of uncached mesh construction is adjusted.
namespace TerrainStreamingPriorityPolicy {

struct Candidate {
	uint32_t index = 0;
	float score = 0.0f;
	bool missing_visible_mesh = false;
};

struct Less {
	bool operator()(const Candidate &a, const Candidate &b) const {
		// Filling visible holes takes precedence over upgrading a cached LOD.
		if (a.missing_visible_mesh != b.missing_visible_mesh) {
			return a.missing_visible_mesh;
		}
		if (a.score != b.score) {
			return a.score < b.score;
		}
		// Stable scan order on ties prevents camera jitter from randomizing
		// which chunks win the shared per-frame CPU streaming budget.
		return a.index < b.index;
	}
};

// A bounded camera-facing bonus reduces pop-in while moving forward without
// starving a chunk behind the player. Mode 1 is strictly distance-based,
// mode 2 adds a view-alignment term in [-0.35, +0.35].
static inline float score(float p_distance, float p_alignment, int p_mode) {
	const float distance = p_distance > 0.0f ? p_distance : 0.0f;
	if (p_mode < 2) {
		return distance;
	}
	const float alignment = p_alignment < -1.0f ? -1.0f : (p_alignment > 1.0f ? 1.0f : p_alignment);
	return distance * (1.0f - 0.35f * alignment);
}

} // namespace TerrainStreamingPriorityPolicy
