/**************************************************************************/
/*  world_streamer.h                                             */
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

#include "scene/main/node.h"
#include "scene/main/world_streaming_grid.h"

#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"

// Streams the parts ("chunks") of a big world in and out around a focus point, so an open world
// only keeps the nearby scenes in memory. The world is split into a grid of square (or cubic)
// cells; the scene for a cell is found with a path template or a callback, loaded on background
// threads, instantiated a few per frame, and freed again once the focus has moved far enough away.
class WorldStreamer : public Node {
	GDCLASS(WorldStreamer, Node);

public:
	enum Axes {
		AXES_XZ,
		AXES_XY,
		AXES_XYZ,
	};

private:
	NodePath focus;
	Vector3 focus_position;
	Axes axes = AXES_XZ;
	real_t cell_size = 64.0;
	real_t load_radius = 128.0;
	real_t unload_radius = 192.0;
	int max_concurrent_loads = 4;
	int max_instantiations_per_frame = 1;
	double update_interval = 0.1;
	String chunk_path_template;
	Callable chunk_provider;
	NodePath chunk_parent;
	bool position_chunks = true;
	bool enabled = true;

	HashMap<Vector3i, ObjectID> loaded;
	HashMap<Vector3i, String> loading;
	// Cells without a chunk scene, and cells whose scene failed to load. Not asked again until
	// refresh(true) or a change of the grid or the path template.
	HashSet<Vector3i> missing;
	HashSet<Vector3i> failed;
	double time_since_update = 1e9;
	bool truncated_warned = false;

	WorldStreamingGrid::Axes _grid_axes() const { return WorldStreamingGrid::Axes(axes); }
	bool _get_focus_position(Vector3 &r_position) const;
	String _path_for_cell(const Vector3i &p_cell) const;
	Node *_get_parent_for_chunks() const;
	void _forget_dead_chunks();
	void _update_streaming();
	void _poll_loading();
	bool _finalize_chunk(const Vector3i &p_cell, const String &p_path);
	void _unload_cell(const Vector3i &p_cell);
	void _reset_state();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_focus(const NodePath &p_focus);
	NodePath get_focus() const { return focus; }
	void set_focus_position(const Vector3 &p_position);
	Vector3 get_focus_position() const { return focus_position; }
	void set_axes(Axes p_axes);
	Axes get_axes() const { return axes; }
	void set_cell_size(real_t p_size);
	real_t get_cell_size() const { return cell_size; }
	void set_load_radius(real_t p_radius);
	real_t get_load_radius() const { return load_radius; }
	void set_unload_radius(real_t p_radius);
	real_t get_unload_radius() const { return unload_radius; }
	void set_max_concurrent_loads(int p_count);
	int get_max_concurrent_loads() const { return max_concurrent_loads; }
	void set_max_instantiations_per_frame(int p_count);
	int get_max_instantiations_per_frame() const { return max_instantiations_per_frame; }
	void set_update_interval(double p_seconds);
	double get_update_interval() const { return update_interval; }
	void set_chunk_path_template(const String &p_template);
	String get_chunk_path_template() const { return chunk_path_template; }
	void set_chunk_provider(const Callable &p_provider);
	Callable get_chunk_provider() const { return chunk_provider; }
	void set_chunk_parent(const NodePath &p_parent);
	NodePath get_chunk_parent() const { return chunk_parent; }
	void set_position_chunks(bool p_enabled) { position_chunks = p_enabled; }
	bool get_position_chunks() const { return position_chunks; }
	void set_enabled(bool p_enabled);
	bool is_enabled() const { return enabled; }

	Vector3i world_to_cell(const Vector3 &p_position) const;
	Vector3 cell_to_world(const Vector3i &p_cell) const;
	bool is_cell_loaded(const Vector3i &p_cell) const { return loaded.has(p_cell); }
	Node *get_chunk(const Vector3i &p_cell) const;
	TypedArray<Vector3i> get_loaded_cells() const;
	int get_loaded_count() const { return int(loaded.size()); }
	int get_pending_count() const { return int(loading.size()); }

	// Re-evaluates immediately instead of waiting for the update interval. With `p_retry`, cells
	// that were missing or failed are tried again.
	void refresh(bool p_retry = false);
	// Frees every loaded chunk. Streaming resumes at the next update unless `enabled` is false.
	void unload_all();

	WorldStreamer() {}
};

VARIANT_ENUM_CAST(WorldStreamer::Axes);
