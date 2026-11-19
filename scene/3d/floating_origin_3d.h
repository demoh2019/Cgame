/**************************************************************************/
/*  floating_origin_3d.h                                             */
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

#include "scene/3d/node_3d.h"

// Keeps the player near the world origin in very large worlds. Floating point numbers get coarser
// the farther they are from zero: at 10 km a 32 bit float resolves about 1 mm, at 100 km about
// 1 cm, which shows up as jittering meshes, physics and cameras. When the focus node has wandered
// further than `threshold` from the origin, every direct child of `world_root` is moved back by a
// multiple of `snap`, so the focus ends up near zero again while everything keeps its position
// relative to everything else.
class FloatingOrigin3D : public Node {
	GDCLASS(FloatingOrigin3D, Node);

public:
	enum ProcessCallback {
		PROCESS_PHYSICS,
		PROCESS_IDLE,
	};

private:
	NodePath focus;
	NodePath world_root;
	real_t threshold = 2000.0;
	real_t snap = 1000.0;
	bool shift_vertical = false;
	ProcessCallback process_callback = PROCESS_PHYSICS;
	Vector3i origin_cells;
	int shift_count = 0;
	StringName ignore_group = SNAME("floating_origin_ignore");

	void _update_process();
	void _check_and_shift();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	// The shift that brings `p_focus_position` back toward the origin, as a multiple of `p_snap`
	// on each enabled axis, or zero while it is still within `p_threshold` of the origin.
	static Vector3 compute_shift(const Vector3 &p_focus_position, real_t p_threshold, real_t p_snap, bool p_shift_vertical);

	void set_focus(const NodePath &p_focus) { focus = p_focus; }
	NodePath get_focus() const { return focus; }
	void set_world_root(const NodePath &p_root) { world_root = p_root; }
	NodePath get_world_root() const { return world_root; }
	void set_threshold(real_t p_threshold);
	real_t get_threshold() const { return threshold; }
	void set_snap(real_t p_snap);
	real_t get_snap() const { return snap; }
	void set_shift_vertical(bool p_enabled) { shift_vertical = p_enabled; }
	bool is_shift_vertical() const { return shift_vertical; }
	void set_process_callback(ProcessCallback p_callback);
	ProcessCallback get_process_callback() const { return process_callback; }

	// Moves every shiftable child of the world root by -p_offset. Emits origin_shifted.
	void shift_origin(const Vector3 &p_offset);
	// How many `snap` units the world has been moved in total (exact, unlike a float offset).
	Vector3i get_origin_cells() const { return origin_cells; }
	// The total distance the world was moved, as a float. Precision degrades at huge distances,
	// so prefer get_origin_cells() times snap in double arithmetic for absolute positions.
	Vector3 get_origin_offset() const { return Vector3(origin_cells) * snap; }
	int get_shift_count() const { return shift_count; }
	// Position in the unshifted world, i.e. what the position would be had the origin never moved.
	Vector3 to_absolute(const Vector3 &p_local) const { return p_local + get_origin_offset(); }
	Vector3 to_local(const Vector3 &p_absolute) const { return p_absolute - get_origin_offset(); }

	FloatingOrigin3D() {}
};

VARIANT_ENUM_CAST(FloatingOrigin3D::ProcessCallback);
