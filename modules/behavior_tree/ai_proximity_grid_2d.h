/**************************************************************************/
/*  ai_proximity_grid_2d.h                                                 */
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
/* persons to whom the Software is furnished to do so, subject to the      */
/* following conditions:                                                  */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/variant.h"

// Stateless, deterministic broadphase query for authoritative 2D crowd AI.
// No actors, scene nodes, raycasts, or gameplay decisions are accessed.
// The cell edge must be >= radius, so a query checks at most 3x3 cells.
class AIProximityGrid2D : public RefCounted {
	GDCLASS(AIProximityGrid2D, RefCounted);

private:
	Array _query_impl(const PackedVector2Array &p_positions,
			const PackedInt32Array &p_source_indices, double p_radius,
			double p_cell_size, int p_max_neighbors) const;

protected:
	static void _bind_methods();

public:
	// Result: Array of PackedInt32Array, one per source, containing indices
	// into positions (excluding itself), ascending by input index.
	// All inputs are checked before indexing; invalid requests yield [].
	Array query_radius_batch(const PackedVector2Array &p_positions,
			const PackedInt32Array &p_source_indices,
			double p_radius, double p_cell_size) const;

	// Limited nearest neighbors, ties by input index. Returns chosen indices
	// ascending by input index (not distance) to retain game event order.
	// p_max_neighbors must be 1..64. Invalid queries return [].
	Array query_nearest_batch(const PackedVector2Array &p_positions,
			const PackedInt32Array &p_source_indices,
			double p_radius, double p_cell_size, int p_max_neighbors) const;
};
