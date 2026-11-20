/**************************************************************************/
/*  world_partition_3d.h                                                  */
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

#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "scene/3d/node_3d.h"
#include "scene/resources/packed_scene.h"

// A sparse X/Z grid for streaming sub-scenes around a moving observer.
// Each registered PackedScene root must be a Node3D and use cell-local coordinates.
class WorldPartition3D : public Node3D {
	GDCLASS(WorldPartition3D, Node3D);

	Dictionary cell_scenes;
	NodePath observer_path;
	real_t cell_size = 128.0;
	int load_radius = 1;
	int unload_radius = 2;
	int max_new_requests_per_frame = 2;
	int max_instances_per_frame = 2;
	int max_concurrent_requests = 8;
	bool streaming_enabled = true;
	int detail_radius = -1; // -1 disables dynamic detail levels.
	int detail_hysteresis_cells = 0; // Extra cells tolerated before demoting an already-near scene.
	int max_detail_transitions_per_frame = 2;
	// Optional, bounded future-cell streaming source; velocity is in world units/second.
	Vector3 predictive_velocity;
	real_t predictive_lookahead_seconds = 0.0;
	real_t predictive_max_distance = 32.0;
	Vector2i predicted_cell;
	bool predicted_cell_valid = false;
	Vector2i observer_cell;
	bool observer_cell_valid = false;

	HashMap<Vector2i, ObjectID> active_cells;
	HashMap<Vector2i, int> active_detail_levels; // Only scene roots that opt into set_streaming_lod().
	HashMap<Vector2i, String> pending_cells;
	HashSet<String> requested_paths;
	HashMap<String, Ref<PackedScene>> ready_scenes;
	HashSet<Vector2i> failed_cells;
	// Explicitly retained gameplay cells (camps, quest hubs), independent of camera distance.
	HashSet<Vector2i> pinned_cells;
	static constexpr int MAX_PINNED_CELLS = 128;

	// Additional runtime loading sources: quest objectives, cameras, portals.
	// Bounded in count and radius so misconfigured gameplay cannot fan out.
	struct StreamingSource {
		Vector3 global_position;
		int radius = 0;
	};
	HashMap<String, StreamingSource> streaming_sources;
	static constexpr int MAX_STREAMING_SOURCES = 8;

	static bool _within_radius(const Vector2i &p_cell, const Vector2i &p_center, int p_radius);
	String _get_scene_path(const Vector2i &p_cell) const;
	bool _is_cell_required_by_source(const Vector2i &p_cell, int p_extra_radius) const;
	int _count_source_cells(const String &p_name, int p_kind) const; // 0 registered, 1 active, 2 failed.
	void _unload_cell(const Vector2i &p_cell);
	void _clear_active_cells();
	void _poll_requests();
	void _request_cell(const Vector2i &p_cell, int &r_new_requests, int &r_instances);
	int _cell_detail_level(const Vector2i &p_cell, const Vector2i &p_center, int p_previous_level = -1) const;
	void _refresh_cell_detail(const Vector2i &p_center);
	void _purge_unused_ready_scenes();
	bool _instantiate_cell(const Vector2i &p_cell, const Ref<PackedScene> &p_scene);
	void _refresh_processing();
	void _notification(int p_what);

protected:
	static void _bind_methods();

public:
	void set_cell_size(real_t p_size);
	real_t get_cell_size() const;

	void set_load_radius(int p_radius);
	int get_load_radius() const;

	void set_unload_radius(int p_radius);
	int get_unload_radius() const;

	void set_max_new_requests_per_frame(int p_count);
	int get_max_new_requests_per_frame() const;

	void set_max_instances_per_frame(int p_count);
	int get_max_instances_per_frame() const;

	void set_max_concurrent_requests(int p_count);
	int get_max_concurrent_requests() const;

	void set_streaming_enabled(bool p_enabled);
	bool is_streaming_enabled() const;

	void set_detail_radius(int p_radius);
	int get_detail_radius() const;
	void set_detail_hysteresis_cells(int p_hysteresis);
	int get_detail_hysteresis_cells() const;
	void set_max_detail_transitions_per_frame(int p_budget);
	int get_max_detail_transitions_per_frame() const;
	int get_cell_detail_level(const Vector2i &p_cell) const;
	int get_distant_cell_count() const;

	void set_observer_path(const NodePath &p_path);
	NodePath get_observer_path() const;

	void set_predictive_velocity(const Vector3 &p_velocity);
	Vector3 get_predictive_velocity() const;
	void set_predictive_lookahead_seconds(real_t p_seconds);
	real_t get_predictive_lookahead_seconds() const;
	void set_predictive_max_distance(real_t p_distance);
	real_t get_predictive_max_distance() const;
	bool has_predicted_cell() const;
	Vector2i get_predicted_cell() const;

	bool has_observer_cell() const;
	Vector2i get_observer_cell() const;

	void set_cell_scenes(const Dictionary &p_cells);
	Dictionary get_cell_scenes() const;
	void set_cell_scene(const Vector2i &p_cell, const String &p_scene_path);
	String get_cell_scene(const Vector2i &p_cell) const;
	void remove_cell_scene(const Vector2i &p_cell);
	void clear_cell_scenes();
	int get_configured_cell_count() const;

	bool pin_cell(const Vector2i &p_cell);
	void unpin_cell(const Vector2i &p_cell);
	bool is_cell_pinned(const Vector2i &p_cell) const;
	Array get_pinned_cells() const;
	int get_pinned_cell_count() const;

	bool set_streaming_source(const String &p_name, const Vector3 &p_global_position, int p_radius = 0);
	void remove_streaming_source(const String &p_name);
	void clear_streaming_sources();
	bool has_streaming_source(const String &p_name) const;
	int get_streaming_source_count() const;
	Vector2i get_streaming_source_cell(const String &p_name) const;
	int get_streaming_source_cell_count(const String &p_name) const;
	int get_streaming_source_loaded_cell_count(const String &p_name) const;
	int get_streaming_source_failed_cell_count(const String &p_name) const;
	real_t get_streaming_source_progress(const String &p_name) const;
	bool is_streaming_source_ready(const String &p_name) const;

	Vector2i local_position_to_cell(const Vector3 &p_local_position) const;
	Vector3 cell_to_local_position(const Vector2i &p_cell) const;
	Array get_cells_in_radius(const Vector2i &p_center, int p_radius) const;

	void update_streaming();
	bool is_cell_loaded(const Vector2i &p_cell) const;
	Node3D *get_cell_instance(const Vector2i &p_cell) const;
	int get_loaded_cell_count() const;
	Array get_loaded_cells() const;
	int get_pending_cell_count() const;
	int get_inflight_request_count() const;
	int get_failed_cell_count() const;

	~WorldPartition3D();
};
