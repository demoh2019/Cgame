/**************************************************************************/
/*  physics_contact_recycling.h                                           */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include <cstdint>

// Conservative Box2D-style manifold recycling. Generation keys track
// shape geometry, orientation and collision filtering, while the calling
// body pair separately checks exact relative translation. A shared rigid
// translation leaves local contact anchors and world normals unchanged.
// Revision 0 is reserved for a not-yet-computed manifold.
struct GodotPhysicsContactRecycling {
	uint64_t geometry_version_a = 0;
	uint64_t geometry_version_b = 0;
	// SAT/GJK found no overlap at the cached *relative* transform.
	// Kept separately from the solver's collided flag, which can also be
	// reset by contact-report-only and one-way filtering paths.
	bool narrowphase_separated = false;

	inline bool matches_geometry(uint64_t p_current_a, uint64_t p_current_b) const {
		return geometry_version_a != 0 && geometry_version_b != 0 &&
				geometry_version_a == p_current_a && geometry_version_b == p_current_b;
	}

	// Speculative contacts depend on relative velocity, not just geometry.
	// A positive or negative manifold may become invalid when velocity changes
	// without a transform change (e.g. an impulse immediately before stepping).
	// Keep all existing callers source-compatible; only eligible predictive
	// pairs request the velocity-sensitive bypass.
	inline bool can_reuse(uint64_t p_current_a, uint64_t p_current_b, bool p_collided, int p_contact_count, bool p_ccd, bool p_velocity_sensitive = false) const {
		return p_collided && p_contact_count > 0 && !p_ccd && !p_velocity_sensitive && !narrowphase_separated &&
				matches_geometry(p_current_a, p_current_b);
	}

	// Safe only with an exactly identical relative translation and unchanged
	// body orientation/shape revisions, verified by the calling body pair.
	// A coarse-phase overlap is not evidence of an actual shape collision:
	// such persistent near-miss pairs would otherwise rerun SAT/GJK every step.
	inline bool can_reuse_separation(uint64_t p_current_a, uint64_t p_current_b, bool p_ccd, bool p_velocity_sensitive = false) const {
		return narrowphase_separated && !p_ccd && !p_velocity_sensitive && matches_geometry(p_current_a, p_current_b);
	}

	inline void remember(uint64_t p_current_a, uint64_t p_current_b, bool p_narrowphase_collided = true) {
		geometry_version_a = p_current_a;
		geometry_version_b = p_current_b;
		narrowphase_separated = !p_narrowphase_collided;
	}
};
