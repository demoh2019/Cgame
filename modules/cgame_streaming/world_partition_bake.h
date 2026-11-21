/**************************************************************************/
/*  world_partition_bake.h                                                */
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
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// World Partition style bake: hierarchical grid cells, always-loaded actors, data layers,
// HLOD clusters, One-File-Per-Actor storage, incremental diffs and predictive streaming.
class WorldPartitionBake : public RefCounted {
	GDCLASS(WorldPartitionBake, RefCounted);

public:
	static constexpr int MAX_LEVEL = 8;

private:
	double lookahead_seconds = 1.5;
	int lookahead_samples = 3;
	Dictionary baked;

	static AABB _actor_bounds(const Dictionary &p_actor);
	static String _group_of(const PackedStringArray &p_layers);
	static int _level_for(double p_extent, double p_cell_size);
	static double _range_for(const PackedStringArray &p_layers, int p_level, double p_cs, const Dictionary &p_ranges);
	static double _dist_to_cell(const Vector3 &p_point, const AABB &p_bounds);
	static Dictionary _actor_to_json(const Dictionary &p_actor);
	static Dictionary _actor_from_json(const Dictionary &p_json);

protected:
	static void _bind_methods();

public:
	void set_lookahead_seconds(double p_seconds);
	double get_lookahead_seconds() const;
	void set_lookahead_samples(int p_samples);
	int get_lookahead_samples() const;

	static String stable_guid(const String &p_seed);

	Dictionary bake(const Array &p_actors, double p_cell_size, const Dictionary &p_loading_range_by_layer);
	Dictionary get_baked() const;
	Array hlod_clusters(const Dictionary &p_cells, int p_cluster_cells) const;

	int split_one_file_per_actor(const Array &p_actors, const String &p_dir_path) const;
	Array load_actors(const String &p_dir_path) const;

	Dictionary diff_bakes(const Dictionary &p_old_bake, const Dictionary &p_new_bake) const;
	Array cells_to_load(const Vector3 &p_source_pos, const Vector3 &p_velocity, const PackedStringArray &p_layers_enabled) const;
};
