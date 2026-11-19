/**************************************************************************/
/*  world_streaming_grid.cpp                                             */
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

#include "world_streaming_grid.h"

#include "core/templates/sort_array.h"

namespace WorldStreamingGrid {

static _FORCE_INLINE_ int32_t floor_to_cell(real_t p_value, real_t p_cell_size) {
	return int32_t(Math::floor(p_value / p_cell_size));
}

Vector3i world_to_cell(const Vector3 &p_position, real_t p_cell_size, Axes p_axes) {
	ERR_FAIL_COND_V(!(p_cell_size > 0.0), Vector3i());
	Vector3i cell;
	switch (p_axes) {
		case AXES_XZ:
			cell = Vector3i(floor_to_cell(p_position.x, p_cell_size), 0, floor_to_cell(p_position.z, p_cell_size));
			break;
		case AXES_XY:
			cell = Vector3i(floor_to_cell(p_position.x, p_cell_size), floor_to_cell(p_position.y, p_cell_size), 0);
			break;
		case AXES_XYZ:
			cell = Vector3i(floor_to_cell(p_position.x, p_cell_size), floor_to_cell(p_position.y, p_cell_size), floor_to_cell(p_position.z, p_cell_size));
			break;
	}
	return cell;
}

Vector3 cell_origin(const Vector3i &p_cell, real_t p_cell_size) {
	return Vector3(p_cell) * p_cell_size;
}

Vector3 cell_center(const Vector3i &p_cell, real_t p_cell_size, Axes p_axes) {
	Vector3 center = (Vector3(p_cell) + Vector3(0.5, 0.5, 0.5)) * p_cell_size;
	if (p_axes == AXES_XZ) {
		center.y = 0.0;
	} else if (p_axes == AXES_XY) {
		center.z = 0.0;
	}
	return center;
}

static _FORCE_INLINE_ real_t axis_distance(real_t p_position, int32_t p_cell, real_t p_cell_size) {
	const real_t low = real_t(p_cell) * p_cell_size;
	const real_t high = low + p_cell_size;
	if (p_position < low) {
		return low - p_position;
	}
	if (p_position > high) {
		return p_position - high;
	}
	return 0.0;
}

real_t distance_to_cell(const Vector3 &p_position, const Vector3i &p_cell, real_t p_cell_size, Axes p_axes) {
	const real_t dx = axis_distance(p_position.x, p_cell.x, p_cell_size);
	const real_t dy = p_axes == AXES_XZ ? 0.0 : axis_distance(p_position.y, p_cell.y, p_cell_size);
	const real_t dz = p_axes == AXES_XY ? 0.0 : axis_distance(p_position.z, p_cell.z, p_cell_size);
	return Math::sqrt(dx * dx + dy * dy + dz * dz);
}

namespace {
struct CellDistance {
	Vector3i cell;
	real_t distance;
	// Deterministic order: nearest first, ties broken by cell coordinates.
	bool operator<(const CellDistance &p_other) const {
		if (distance != p_other.distance) {
			return distance < p_other.distance;
		}
		if (cell.x != p_other.cell.x) {
			return cell.x < p_other.cell.x;
		}
		if (cell.y != p_other.cell.y) {
			return cell.y < p_other.cell.y;
		}
		return cell.z < p_other.cell.z;
	}
};
} // namespace

void cells_in_radius(const Vector3 &p_position, real_t p_radius, real_t p_cell_size, Axes p_axes, LocalVector<Vector3i> &r_cells, uint32_t p_max_cells, bool *r_truncated) {
	r_cells.clear();
	if (r_truncated) {
		*r_truncated = false;
	}
	ERR_FAIL_COND(!(p_cell_size > 0.0));
	if (!(p_radius >= 0.0) || !p_position.is_finite() || !Math::is_finite(p_radius)) {
		return;
	}

	const Vector3 low = p_position - Vector3(p_radius, p_radius, p_radius);
	const Vector3 high = p_position + Vector3(p_radius, p_radius, p_radius);
	const Vector3i first = world_to_cell(low, p_cell_size, p_axes);
	const Vector3i last = world_to_cell(high, p_cell_size, p_axes);

	// Guard against absurd ranges before iterating at all.
	const int64_t span_x = int64_t(last.x) - first.x + 1;
	const int64_t span_y = int64_t(last.y) - first.y + 1;
	const int64_t span_z = int64_t(last.z) - first.z + 1;
	if (span_x * span_y * span_z > int64_t(p_max_cells) * 64) {
		// Far more candidates than we may return: tighten the radius to the cap's worth of
		// cells and report truncation instead of walking billions of cells.
		if (r_truncated) {
			*r_truncated = true;
		}
		const real_t per_axis = Math::pow(real_t(p_max_cells), p_axes == AXES_XYZ ? real_t(1.0 / 3.0) : real_t(0.5));
		cells_in_radius(p_position, per_axis * p_cell_size * real_t(0.5), p_cell_size, p_axes, r_cells, p_max_cells, nullptr);
		return;
	}

	LocalVector<CellDistance> found;
	for (int32_t z = first.z; z <= last.z; z++) {
		for (int32_t y = first.y; y <= last.y; y++) {
			for (int32_t x = first.x; x <= last.x; x++) {
				const Vector3i cell(x, y, z);
				const real_t distance = distance_to_cell(p_position, cell, p_cell_size, p_axes);
				if (distance <= p_radius) {
					found.push_back({ cell, distance });
				}
			}
		}
	}
	SortArray<CellDistance> sorter;
	sorter.sort(found.ptr(), found.size());

	uint32_t count = found.size();
	if (count > p_max_cells) {
		count = p_max_cells;
		if (r_truncated) {
			*r_truncated = true;
		}
	}
	r_cells.reserve(count);
	for (uint32_t i = 0; i < count; i++) {
		r_cells.push_back(found[i].cell);
	}
}

void cells_to_unload(const Vector3 &p_position, real_t p_unload_radius, real_t p_cell_size, Axes p_axes, const HashSet<Vector3i> &p_loaded, LocalVector<Vector3i> &r_cells) {
	r_cells.clear();
	ERR_FAIL_COND(!(p_cell_size > 0.0));
	for (const Vector3i &cell : p_loaded) {
		if (!(distance_to_cell(p_position, cell, p_cell_size, p_axes) <= p_unload_radius)) {
			r_cells.push_back(cell);
		}
	}
	// Farthest first; deterministic across hash orders.
	LocalVector<CellDistance> ordered;
	for (const Vector3i &cell : r_cells) {
		ordered.push_back({ cell, -distance_to_cell(p_position, cell, p_cell_size, p_axes) });
	}
	SortArray<CellDistance> sorter;
	sorter.sort(ordered.ptr(), ordered.size());
	for (uint32_t i = 0; i < ordered.size(); i++) {
		r_cells[i] = ordered[i].cell;
	}
}

} // namespace WorldStreamingGrid
