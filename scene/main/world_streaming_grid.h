/**************************************************************************/
/*  world_streaming_grid.h                                             */
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

#include "core/math/vector3.h"
#include "core/math/vector3i.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"

// Pure grid logic of the open world streamer: which cells of an infinite grid are close enough
// to a point to be loaded, and which loaded cells are far enough to be dropped. Contains no
// scene or loading code, so it is cheap to test.
namespace WorldStreamingGrid {

// Which axes span the streaming grid. The ignored axis always has cell index 0.
enum Axes {
	AXES_XZ, // Ground plane of a 3D world (default).
	AXES_XY, // 2D worlds.
	AXES_XYZ, // Fully volumetric worlds (space, caves).
};

// Hard cap on the cells considered in one query, so a huge radius with a tiny cell size cannot
// freeze the game.
inline constexpr uint32_t MAX_CELLS = 16384;

Vector3i world_to_cell(const Vector3 &p_position, real_t p_cell_size, Axes p_axes);
// Corner of the cell with the lowest coordinates, in world space (ignored axes are zero).
Vector3 cell_origin(const Vector3i &p_cell, real_t p_cell_size);
Vector3 cell_center(const Vector3i &p_cell, real_t p_cell_size, Axes p_axes);
// Distance from the point to the closest point of the cell, measured on the active axes only.
// Zero when the point is inside the cell.
real_t distance_to_cell(const Vector3 &p_position, const Vector3i &p_cell, real_t p_cell_size, Axes p_axes);

// Cells within `p_radius` of the point, ordered from nearest to farthest. At most `p_max_cells`
// are returned (the nearest ones). `r_truncated` reports whether the cap cut the result.
void cells_in_radius(const Vector3 &p_position, real_t p_radius, real_t p_cell_size, Axes p_axes, LocalVector<Vector3i> &r_cells, uint32_t p_max_cells = MAX_CELLS, bool *r_truncated = nullptr);

// Loaded cells that are now farther than `p_unload_radius` (hysteresis: it should be at least the
// load radius so cells on the border do not flicker in and out).
void cells_to_unload(const Vector3 &p_position, real_t p_unload_radius, real_t p_cell_size, Axes p_axes, const HashSet<Vector3i> &p_loaded, LocalVector<Vector3i> &r_cells);

} // namespace WorldStreamingGrid
