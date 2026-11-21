/**************************************************************************/
/*  origin_rebasing.h                                                     */
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
#include "core/templates/local_vector.h"
#include "core/variant/callable.h"

class Node3D;

// Floating-origin world rebasing helper (shifts are multiples of `grid_step`).
class OriginRebasing : public RefCounted {
	GDCLASS(OriginRebasing, RefCounted);

	double threshold = 2048.0;
	double grid_step = 512.0;
	bool horizontal_only = true;
	Vector3i origin_cells;
	int shift_count = 0;
	LocalVector<Callable> listeners;

protected:
	static void _bind_methods();

public:
	static StringName get_exclude_group() { return StringName("origin_rebase_exclude"); }

	void set_threshold(double p_threshold);
	double get_threshold() const;
	void set_grid_step(double p_step);
	double get_grid_step() const;
	void set_horizontal_only(bool p_enabled);
	bool is_horizontal_only() const;
	void set_origin_cells(const Vector3i &p_cells);
	Vector3i get_origin_cells() const;
	int get_shift_count() const;

	Vector3 check(const Vector3 &p_camera_world_pos) const;
	int apply(Node3D *p_root, const Vector3 &p_shift);
	void commit(const Vector3 &p_shift);
	void add_listener(const Callable &p_callback);
	void remove_listener(const Callable &p_callback);

	Vector3 to_global_world(const Vector3 &p_pos) const;
	Vector3 to_local_world(const Vector3 &p_pos) const;
	Dictionary to_global_split(const Vector3 &p_pos) const;
	Vector3 from_global_split(const Vector3i &p_cell, const Vector3 &p_rem) const;
	Vector3 noise_offset(double p_period) const;
};
