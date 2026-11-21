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

// Limit prediction to the streaming cell size: an outdated velocity hint
// cannot pull the queue far past nearby terrain or increase resident memory.
void prioritize_cells_for_motion(LocalVector<Vector3i> &r_cells, const Vector3 &p_focus,
		const Vector3 &p_velocity, real_t p_lookahead_seconds, real_t p_max_prediction,
		real_t p_cell_size, Axes p_axes) {
	// Always restore nearest-first ordering when motion prediction stops.
	// A queued chunk may have been prioritized during a previous bike ride;
	// simply returning on zero velocity would leave that stale order in place.
	if (r_cells.size() < 2 || !p_focus.is_finite() ||
			!Math::is_finite(p_cell_size) || !(p_cell_size > 0.0)) {
		return;
	}
	Vector3 prediction;
	if (p_velocity.is_finite() && Math::is_finite(p_lookahead_seconds) && p_lookahead_seconds > 0.0 &&
			Math::is_finite(p_max_prediction) && p_max_prediction > 0.0) {
		prediction = p_velocity * MIN(p_lookahead_seconds, real_t(4.0));
		if (p_axes == AXES_XZ) {
			prediction.y = 0.0;
		} else if (p_axes == AXES_XY) {
			prediction.z = 0.0;
		}
		if (!prediction.is_finite() || prediction.length_squared() < real_t(0.01)) {
			prediction = Vector3();
		} else {
			const real_t ahead = MIN(p_max_prediction, p_cell_size);
			if (prediction.length_squared() > ahead * ahead) {
				prediction = prediction.normalized() * ahead;
			}
		}
	}
	const Vector3 future = p_focus + prediction;
	if (!future.is_finite()) {
		return;
	}
	const Vector3i focus_cell = world_to_cell(p_focus, p_cell_size, p_axes);
	struct Priority {
		Vector3i cell;
		real_t score;
		real_t now;
		bool operator<(const Priority &p_other) const {
			if (score != p_other.score) {
				return score < p_other.score;
			}
			if (now != p_other.now) {
				return now < p_other.now;
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
	LocalVector<Priority> sorted;
	sorted.reserve(r_cells.size());
	for (const Vector3i &cell : r_cells) {
		const real_t now = distance_to_cell(p_focus, cell, p_cell_size, p_axes);
		const real_t later = distance_to_cell(future, cell, p_cell_size, p_axes);
		// Keep the focus cell first. Other cells trade a small amount of
		// nearest-first priority for content ahead of actual movement.
		const real_t score = cell == focus_cell ? real_t(-1.0) : now * real_t(0.65) + later * real_t(0.35);
		sorted.push_back({ cell, score, now });
	}
	SortArray<Priority> sorter;
	sorter.sort(sorted.ptr(), sorted.size());
	for (uint32_t i = 0; i < sorted.size(); i++) {
		r_cells[i] = sorted[i].cell;
	}
}

// Unreal-style view-weighted streaming sources, generalized for XZ, XY and
// XYZ grids. Membership stays within the original player-centered radius.
// One sort combines actual distance, capped movement prediction and a
// conservative camera-forward bonus. This replaces (not adds) a sort.
void prioritize_cells_for_motion_and_view(LocalVector<Vector3i> &r_cells, const Vector3 &p_focus,
		const Vector3 &p_velocity, real_t p_lookahead_seconds, real_t p_max_prediction,
		const Vector3 &p_view_direction, real_t p_view_weight, real_t p_cell_size, Axes p_axes,
		real_t p_view_cone_half_angle_degrees) {
	if (r_cells.size() < 2 || !p_focus.is_finite() || !Math::is_finite(p_cell_size) ||
			!(p_cell_size > 0.0)) {
		return;
	}
	if (!p_view_direction.is_finite() || !Math::is_finite(p_view_weight) ||
			p_view_weight <= 0.0) {
		prioritize_cells_for_motion(r_cells, p_focus, p_velocity,
				p_lookahead_seconds, p_max_prediction, p_cell_size, p_axes);
		return;
	}
	Vector3 view = p_view_direction;
	if (p_axes == AXES_XZ) {
		view.y = 0.0;
	} else if (p_axes == AXES_XY) {
		view.z = 0.0;
	}
	if (view.length_squared() < real_t(0.0001)) {
		prioritize_cells_for_motion(r_cells, p_focus, p_velocity,
				p_lookahead_seconds, p_max_prediction, p_cell_size, p_axes);
		return;
	}
	view.normalize();
	const real_t strength = CLAMP(p_view_weight, real_t(0.0), real_t(1.0));
	// Opt-in cone attenuates the camera bonus outside the actual view. The
	// default 180-degree half-angle retains the old direction-only ranking.
	const bool narrow_cone = Math::is_finite(p_view_cone_half_angle_degrees) &&
			p_view_cone_half_angle_degrees < real_t(180.0);
	const real_t cone_cosine = narrow_cone ? Math::cos(Math::deg_to_rad(
			CLAMP(p_view_cone_half_angle_degrees, real_t(1.0), real_t(180.0)))) : real_t(-1.0);
	Vector3 prediction;
	if (p_velocity.is_finite() && Math::is_finite(p_lookahead_seconds) &&
			Math::is_finite(p_max_prediction) && p_lookahead_seconds > 0.0 &&
			p_max_prediction > 0.0) {
		prediction = p_velocity * MIN(p_lookahead_seconds, real_t(4.0));
		if (p_axes == AXES_XZ) {
			prediction.y = 0.0;
		} else if (p_axes == AXES_XY) {
			prediction.z = 0.0;
		}
		if (prediction.is_finite()) {
			const real_t cap = MIN(p_max_prediction, p_cell_size);
			if (prediction.length_squared() > cap * cap) {
				prediction = prediction.normalized() * cap;
			}
		} else {
			prediction = Vector3();
		}
	}
	const Vector3 predicted_focus = p_focus + prediction;
	const Vector3i focus_cell = world_to_cell(p_focus, p_cell_size, p_axes);
	struct RankedCell {
		Vector3i cell;
		real_t score;
		real_t now;
		bool operator<(const RankedCell &p_other) const {
			if (score != p_other.score) {
				return score < p_other.score;
			}
			if (now != p_other.now) {
				return now < p_other.now;
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
	LocalVector<RankedCell> sorted;
	sorted.reserve(r_cells.size());
	for (const Vector3i &cell : r_cells) {
		const real_t now = distance_to_cell(p_focus, cell, p_cell_size, p_axes);
		const real_t later = distance_to_cell(predicted_focus, cell, p_cell_size, p_axes);
		Vector3 toward = cell_center(cell, p_cell_size, p_axes) - p_focus;
		if (p_axes == AXES_XZ) {
			toward.y = 0.0;
		} else if (p_axes == AXES_XY) {
			toward.z = 0.0;
		}
		real_t facing = 0.0;
		if (toward.length_squared() > real_t(0.0001)) {
			const real_t alignment = toward.normalized().dot(view);
			facing = MAX(alignment, real_t(0.0));
			if (narrow_cone) {
				// Smoothly reduce the bonus near the cone boundary; never
				// reprioritize back-facing cells or change residency.
				facing *= CLAMP((alignment - cone_cosine) / (real_t(1.0) - cone_cosine),
						real_t(0.0), real_t(1.0));
			}
		}
		// At most 28% of one cell of forward bias, and at most 40%
		// of the cell's current distance. No starvation or missing chunk
		// suddenly jumping ahead of the cell directly beneath the player.
		const real_t bonus = MIN(p_cell_size * real_t(0.28), now * real_t(0.4)) * facing * strength;
		const real_t priority = cell == focus_cell ? real_t(-1.0) :
				(now * real_t(0.65) + later * real_t(0.35) - bonus);
		sorted.push_back({ cell, priority, now });
	}
	SortArray<RankedCell> sorter;
	sorter.sort(sorted.ptr(), sorted.size());
	for (uint32_t i = 0; i < sorted.size(); i++) {
		r_cells[i] = sorted[i].cell;
	}
}

bool should_refresh_for_view_turn(const Vector3 &p_last_view,
		const Vector3 &p_current_view, real_t p_degrees) {
	if (!p_last_view.is_finite() || !p_current_view.is_finite() ||
			!Math::is_finite(p_degrees) || p_degrees <= real_t(0.0) ||
			p_degrees > real_t(180.0)) {
		return false;
	}
	const real_t last_squared = p_last_view.length_squared();
	const real_t current_squared = p_current_view.length_squared();
	if (last_squared < real_t(1e-6) || current_squared < real_t(1e-6)) {
		return false;
	}
	// Cosine comparison avoids atan/acos on every streaming tick and accepts
	// both normalized and arbitrary finite vectors safely.
	const real_t cosine = CLAMP(p_last_view.dot(p_current_view) /
			Math::sqrt(last_squared * current_squared), real_t(-1.0), real_t(1.0));
	return cosine < Math::cos(Math::deg_to_rad(p_degrees));
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
