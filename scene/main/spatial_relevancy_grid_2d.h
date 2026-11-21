/**************************************************************************/
/*  spatial_relevancy_grid_2d.h                                              */
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
#include "core/templates/hash_set.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Reusable spatial relevancy lists for network snapshots and visibility.
// Packed input preserves source order; query_ids returns IDs in that order.
// The caller owns the objects; this class stores only values, never pointers.
class SpatialRelevancyGrid2D : public RefCounted {
	GDCLASS(SpatialRelevancyGrid2D, RefCounted);

	struct Entry {
		int64_t id = 0;
		Vector2 position;
	};
	Vector<Entry> entries;
	HashMap<Vector2i, Vector<int>> buckets;
	double cell_size = 64.0;
	double max_indexed_radius = 2048.0;
	bool indexed_mode = false;
	uint64_t rebuild_count = 0;
	uint64_t query_count = 0;
	uint64_t candidate_checks = 0;
	uint64_t bucket_lookups = 0;
	uint64_t fallback_scans = 0;

	Vector2i _cell_of(const Vector2 &p_point) const;
	bool _safe_cell(const Vector2 &p_point) const;
	void _reindex();

protected:
	static void _bind_methods();

public:
	bool rebuild(const PackedInt64Array &p_ids, const PackedVector2Array &p_positions);
	PackedInt64Array query_ids(const Vector2 &p_center, double p_radius);
	Dictionary get_stats() const;
	void clear();
	void set_cell_size(double p_size);
	double get_cell_size() const { return cell_size; }
	void set_max_indexed_radius(double p_radius);
	double get_max_indexed_radius() const { return max_indexed_radius; }
};
