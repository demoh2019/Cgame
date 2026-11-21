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
#include "core/templates/vector.h"
#include "scene/3d/node_3d.h"
#include "scene/resources/packed_scene.h"

// A sparse X/Z grid for streaming sub-scenes around a moving observer.
// Each registered PackedScene root must be a Node3D and use cell-local coordinates.
class WorldPartition3D : public Node3D {
	GDCLASS(WorldPartition3D, Node3D);

	Dictionary cell_scenes;
	Dictionary cell_layers;
	Dictionary layer_states;
	bool layer_update_needed = false;
	NodePath observer_path;
	Array additional_observer_paths;
	Vector<Vector2i> pinned_cells;
	HashMap<int, Vector2i> cell_leases;
	HashMap<Vector2i, int> cell_lease_counts;
	int next_cell_lease_token = 1;
	bool unload_after_last_pin_removed = false;
	real_t cell_size = 128.0;
	int load_radius = 1;
	int unload_radius = 2;
	int max_new_requests_per_frame = 2;
	int max_instances_per_frame = 2;
	int max_unloads_per_frame = 32;
	int max_concurrent_requests = 8;
	bool streaming_enabled = true;
	bool persist_rigid_bodies = false;

	HashMap<Vector2i, ObjectID> active_cells;
	HashMap<Vector2i, String> pending_cells;
	HashSet<String> requested_paths;
	HashMap<String, Ref<PackedScene>> ready_scenes;
	HashSet<Vector2i> failed_cells;
	HashMap<Vector2i, Dictionary> saved_cell_states;
	HashMap<Vector2i, Dictionary> saved_cell_physics_states;

	static bool _within_radius(const Vector2i &p_cell, const Vector2i &p_center, int p_radius);
	void _append_source_center(const NodePath &p_path, Vector<Vector2i> &r_centers) const;
	bool _within_any_radius(const Vector2i &p_cell, const Vector<Vector2i> &p_centers, int p_radius) const;
	bool _has_residency_claim(const Vector2i &p_cell) const;
	String _get_scene_path(const Vector2i &p_cell) const;
	bool _is_cell_layer_enabled(const Vector2i &p_cell) const;
	void _notify_cell_activating(const Vector2i &p_cell, Node *p_instance);
	void _notify_cell_deactivating(const Vector2i &p_cell, Node *p_instance);
	void _capture_cell_state(const Vector2i &p_cell, Node *p_instance);
	void _capture_cell_physics_state(const Vector2i &p_cell, Node *p_instance);
	void _restore_cell_physics_state(const Vector2i &p_cell, Node *p_instance);
	static bool _valid_body_state(const Dictionary &p_state);
	static bool _valid_body_path(const String &p_path);
	void _restore_cell_state(const Vector2i &p_cell, Node *p_instance);
	void _unload_cell(const Vector2i &p_cell);
	void _clear_active_cells();
	void _poll_requests();
	void _purge_unused_ready_scenes();
	bool _instantiate_cell(const Vector2i &p_cell, const Ref<PackedScene> &p_scene);
	void _stream_candidate_cell(const Vector2i &p_cell, int &r_new_requests, int &r_instances);
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

	void set_max_unloads_per_frame(int p_count);
	int get_max_unloads_per_frame() const;

	void set_max_concurrent_requests(int p_count);
	int get_max_concurrent_requests() const;

	void set_streaming_enabled(bool p_enabled);
	bool is_streaming_enabled() const;

	void set_observer_path(const NodePath &p_path);
	NodePath get_observer_path() const;

	void set_additional_observer_paths(const Array &p_paths);
	Array get_additional_observer_paths() const;

	void set_pinned_cells(const Array &p_cells);
	void pin_cell(const Vector2i &p_cell);
	void unpin_cell(const Vector2i &p_cell);
	void clear_pinned_cells();
	bool is_cell_pinned(const Vector2i &p_cell) const;
	Array get_pinned_cells() const;
	int get_pinned_cell_count() const;

	int acquire_cell_lease(const Vector2i &p_cell);
	bool release_cell_lease(int p_lease_token);
	void clear_cell_leases();
	int get_cell_lease_count(const Vector2i &p_cell) const;
	int get_cell_lease_count_total() const;
	int get_leased_cell_count() const;
	Array get_cell_route(const Vector2i &p_from, const Vector2i &p_to) const;
	Array acquire_cell_route(const Vector2i &p_from, const Vector2i &p_to);
	int release_cell_route(const Array &p_tokens);

	void set_cell_layers(const Dictionary &p_layers);
	Dictionary get_cell_layers() const;
	void set_cell_layer(const Vector2i &p_cell, const String &p_layer);
	String get_cell_layer(const Vector2i &p_cell) const;
	void clear_cell_layer(const Vector2i &p_cell);
	void set_layer_states(const Dictionary &p_states);
	Dictionary get_layer_states() const;
	void set_layer_enabled(const String &p_layer, bool p_enabled);
	bool is_layer_enabled(const String &p_layer) const;
	bool is_cell_layer_enabled(const Vector2i &p_cell) const;

	void set_cell_state(const Vector2i &p_cell, const Dictionary &p_state);
	Dictionary get_cell_state(const Vector2i &p_cell) const;
	bool has_cell_state(const Vector2i &p_cell) const;
	void erase_cell_state(const Vector2i &p_cell);
	void clear_cell_states();
	Dictionary snapshot_cell_states();
	void load_cell_states(const Dictionary &p_states);
	int get_cell_state_count() const;

	void set_persist_rigid_bodies(bool p_enabled);
	bool is_persisting_rigid_bodies() const;
	Dictionary get_cell_physics_state(const Vector2i &p_cell) const;
	Dictionary snapshot_cell_physics_states();
	void load_cell_physics_states(const Dictionary &p_states);
	void clear_cell_physics_states();
	int get_cell_physics_state_count() const;

	void set_cell_scenes(const Dictionary &p_cells);
	Dictionary get_cell_scenes() const;
	void set_cell_scene(const Vector2i &p_cell, const String &p_scene_path);
	String get_cell_scene(const Vector2i &p_cell) const;
	void remove_cell_scene(const Vector2i &p_cell);
	void clear_cell_scenes();
	int get_configured_cell_count() const;

	Vector2i local_position_to_cell(const Vector3 &p_local_position) const;
	Vector3 cell_to_local_position(const Vector2i &p_cell) const;
	Array get_cells_in_radius(const Vector2i &p_center, int p_radius) const;

	void update_streaming();
	bool is_cell_loaded(const Vector2i &p_cell) const;
	Node3D *get_cell_instance(const Vector2i &p_cell) const;
	int get_loaded_cell_count() const;
	Array get_loaded_cells() const;
	Dictionary get_cell_simulation_stats(const Vector2i &p_cell) const;

	~WorldPartition3D();
};
