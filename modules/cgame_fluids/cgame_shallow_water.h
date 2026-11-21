/**************************************************************************/
/*  cgame_shallow_water.h                                                 */
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

// Shallow-water heightfield solver using the virtual pipes method (Mei, Decaudin,
// Hu 2007, "Fast Hydraulic Erosion Simulation and Visualization on GPU").
// Each cell exchanges water with its 4 neighbours through pipes driven by the
// surface height difference. Outflow is scaled so a cell never gives away more
// than it holds (depth stays >= 0) and boundaries are closed, so volume is
// conserved. Intended for floods and puddles. Row-parallel and deterministic:
// every pass reads the previous pass and writes only its own cell.

#include "cgame_fluids_common.h"

#include "core/io/image.h"
#include "core/math/vector2.h"
#include "core/math/vector2i.h"
#include "core/object/ref_counted.h"

class CgameShallowWater : public RefCounted {
	GDCLASS(CgameShallowWater, RefCounted);

public:
	static constexpr real_t GRAVITY = 9.81;
	static constexpr real_t FLUX_DAMPING = 0.999;
	static constexpr int MAX_SUBSTEPS = 32;

private:
	int width = 0;
	int height = 0;
	real_t cell_size = 1.0;

	Vector<float> terrain;
	Vector<float> depth;
	// Outflow volume rates (m^3/s) toward -x, +x, -y, +y neighbours.
	Vector<float> f_left;
	Vector<float> f_right;
	Vector<float> f_up;
	Vector<float> f_down;

	_FORCE_INLINE_ bool _in_bounds(const Vector2i &p_cell) const {
		return p_cell.x >= 0 && p_cell.y >= 0 && p_cell.x < width && p_cell.y < height;
	}
	void _substep(real_t p_dt);

protected:
	static void _bind_methods();

public:
	void setup(int p_width, int p_height, real_t p_cell_size, const Vector<float> &p_terrain);

	void add_water(const Vector2i &p_cell, real_t p_depth);
	real_t depth_at(const Vector2i &p_cell) const;
	real_t terrain_at(const Vector2i &p_cell) const;
	real_t total_volume() const;
	Vector2 velocity_at(const Vector2i &p_cell) const;
	void step(real_t p_delta);

	Vector<float> get_depth() const { return depth; }
	Vector<float> get_terrain() const { return terrain; }
	// Water depth as a single-channel float image (FORMAT_RF) for shaders.
	Ref<Image> depth_image() const;
	// Water surface height (terrain + depth) as a single-channel float image.
	Ref<Image> surface_image() const;

	CGF_GETTER(int, width)
	CGF_GETTER(int, height)
	CGF_GETTER(real_t, cell_size)

	CgameShallowWater() {}
};
