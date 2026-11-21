/**************************************************************************/
/*  cgame_procedural_caves.h                                              */
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
#include "core/variant/typed_array.h"

class CgameProceduralCaves : public RefCounted {
	GDCLASS(CgameProceduralCaves, RefCounted);

	static PackedByteArray _smooth(const PackedByteArray &p_grid, int p_w, int p_h);
	static Vector<Vector<int32_t>> _regions(const uint8_t *p_grid, int p_w, int p_h);
	static void _connect_regions(PackedByteArray &r_grid, int p_w, int p_h);
	static void _carve(uint8_t *r_grid, int p_w, int p_a, int p_b);

protected:
	static void _bind_methods();

public:
	static PackedByteArray generate(int p_width, int p_height, int64_t p_seed, double p_fill = 0.47, int p_steps = 5);
	static Array regions(const PackedByteArray &p_grid, int p_w, int p_h);
	static Array chambers(const PackedByteArray &p_grid, int p_w, int p_h, int p_min_size);
};
