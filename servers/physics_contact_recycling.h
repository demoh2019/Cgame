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

// A deliberately conservative first step toward Box2D-style manifold
// recycling. Exact shape/pose generations allow the narrow phase to be
// skipped without approximating rotation, surface separation or contact
// normals. Revision 0 is reserved for a not-yet-computed manifold.
struct GodotPhysicsContactRecycling {
	uint64_t geometry_version_a = 0;
	uint64_t geometry_version_b = 0;

	inline bool can_reuse(uint64_t p_current_a, uint64_t p_current_b, bool p_collided, int p_contact_count, bool p_ccd) const {
		return p_collided && p_contact_count > 0 && !p_ccd &&
				geometry_version_a != 0 && geometry_version_b != 0 &&
				geometry_version_a == p_current_a && geometry_version_b == p_current_b;
	}

	inline void remember(uint64_t p_current_a, uint64_t p_current_b) {
		geometry_version_a = p_current_a;
		geometry_version_b = p_current_b;
	}
};
