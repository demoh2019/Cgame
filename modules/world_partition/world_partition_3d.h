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

	HashMap<Vector2i, ObjectID> active_cells;
	HashMap<Vector2i, String> pending_cells;
	HashSet<String> requested_paths;
	HashMap<String, Ref<PackedScene>> ready_scenes;
	HashSet<Vector2i> failed_cells;

	static bool _within_radius(const Vector2i &p_cell, const Vector2i &p_center, int p_radius);
	String _get_scene_path(const Vector2i &p_cell) const;
	void _unload_cell(const Vector2i &p_cell);
	void _clear_active_cells();
	void _poll_requests();
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

	void set_observer_path(const NodePath &p_path);
	NodePath get_observer_path() const;

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
	int get_loaded_cell_count() const;
	Array get_loaded_cells() const;

	~WorldPartition3D();
};
