/**************************************************************************/
/*  spatial_point_grid_2d.h                                              */
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

#include "core/math/vector2.h"
#include "core/math/vector2i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// Rebuildable point broadphase for world-space 2D/XZ proximity queries.
// Stores data only, no Node or PhysicsServer dependency. Unlike a collider
// broadphase, all accepted points are compared by exact squared distance.
class SpatialPointGrid2D : public RefCounted {
	GDCLASS(SpatialPointGrid2D, RefCounted);

	Vector<Vector2> positions;
	HashMap<Vector2i, Vector<Vector2>> cells;
	real_t cell_size = 64.0;
	real_t max_indexed_radius = 512.0;
	int direct_scan_threshold = 8;
	bool indexed_mode = false;
	uint64_t queries = 0;
	uint64_t candidate_checks = 0;
	uint64_t bucket_lookups = 0;

	bool _safe_for_index(const Vector2 &p_point) const;
	void _reindex();
	bool _scan(const Vector2 &p_point, real_t p_radius_squared, bool p_inclusive);
	static Vector2i _cell_of(const Vector2 &p_point, real_t p_cell_size);

protected:
	static void _bind_methods();

public:
	void set_cell_size(real_t p_cell_size);
	real_t get_cell_size() const { return cell_size; }
	void set_direct_scan_threshold(int p_threshold);
	int get_direct_scan_threshold() const { return direct_scan_threshold; }
	void set_max_indexed_radius(real_t p_radius);
	real_t get_max_indexed_radius() const { return max_indexed_radius; }

	void rebuild(const TypedArray<Vector2> &p_positions);
	bool any_within(const Vector2 &p_point, real_t p_radius, bool p_inclusive = true);
	Dictionary snapshot() const;
	int get_point_count() const { return positions.size(); }
	void clear();
};
