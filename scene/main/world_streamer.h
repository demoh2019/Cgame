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
	// Optional hint only affects load order; current focus still controls
	// residency and chunk generation. Disabled unless set by the game.
	Vector3 velocity_hint;
	real_t lookahead_seconds = 0.0;
	// Optional view-source bias: zero preserves motion-only scheduling.
	// These hints reorder eligible work, never grow the resident set.
	Vector3 view_direction;
	real_t view_priority = 0.0;
	// 0 = legacy update cadence. A large camera turn may rebuild the
	// scheduling queue sooner, subject to a 50 ms minimum CPU interval.
	real_t fast_view_refresh_degrees = 0.0;
	Vector3 last_queued_view_direction;
	int max_concurrent_loads = 4;
	int max_instantiations_per_frame = 1;
	// Soft main-thread time slice for procedural generation or scene
	// activation (0 = count-only). Each individual chunk is indivisible.
	int max_chunk_work_usec = 0;
	double update_interval = 0.1;
	String chunk_path_template;
	Callable chunk_provider;
	// Procedural worlds: called on the main thread with the cell, returns the chunk node (or null).
	Callable chunk_generator;
	// Cells waiting for the generator, nearest first. Generation is paced by max_instantiations_per_frame.
	LocalVector<Vector3i> generate_queue;
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
	void _poll_loading(int &r_instantiation_budget, uint64_t p_frame_started_usec);
	bool _finalize_chunk(const Vector3i &p_cell, const String &p_path);
	bool _adopt_chunk(const Vector3i &p_cell, Node *p_chunk);
	void _run_generator_queue(int &r_instantiation_budget, uint64_t p_frame_started_usec);
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
	void set_velocity_hint(const Vector3 &p_velocity);
	Vector3 get_velocity_hint() const { return velocity_hint; }
	void set_lookahead_seconds(real_t p_seconds);
	real_t get_lookahead_seconds() const { return lookahead_seconds; }
	void set_view_direction(const Vector3 &p_direction);
	Vector3 get_view_direction() const { return view_direction; }
	void set_view_priority(real_t p_weight);
	void set_fast_view_refresh_degrees(real_t p_degrees);
	real_t get_fast_view_refresh_degrees() const { return fast_view_refresh_degrees; }
	real_t get_view_priority() const { return view_priority; }
	void set_max_concurrent_loads(int p_count);
	int get_max_concurrent_loads() const { return max_concurrent_loads; }
	void set_max_instantiations_per_frame(int p_count);
	int get_max_instantiations_per_frame() const { return max_instantiations_per_frame; }
	void set_max_chunk_work_usec(int p_usec);
	int get_max_chunk_work_usec() const { return max_chunk_work_usec; }
	void set_update_interval(double p_seconds);
	double get_update_interval() const { return update_interval; }
	void set_chunk_path_template(const String &p_template);
	String get_chunk_path_template() const { return chunk_path_template; }
	void set_chunk_provider(const Callable &p_provider);
	Callable get_chunk_provider() const { return chunk_provider; }
	// Builds chunks in code instead of loading scene files: `generator.call(cell)` must return a Node
	// (or null for an empty cell). Use it for worlds generated from a seed. Takes precedence over the
	// provider and the path template.
	void set_chunk_generator(const Callable &p_generator);
	Callable get_chunk_generator() const { return chunk_generator; }
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
	// Procedural cells queue separately from threaded scene loads.
	// Expose their backlog for streaming telemetry and adaptive game scheduling.
	int get_queued_generation_count() const { return int(generate_queue.size()); }

	// Re-evaluates immediately instead of waiting for the update interval. With `p_retry`, cells
	// that were missing or failed are tried again.
	void refresh(bool p_retry = false);
	// Frees every loaded chunk. Streaming resumes at the next update unless `enabled` is false.
	void unload_all();

	WorldStreamer() {}
};

VARIANT_ENUM_CAST(WorldStreamer::Axes);
