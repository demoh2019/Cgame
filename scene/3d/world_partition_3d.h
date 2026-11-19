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
#include "core/variant/dictionary.h"
#include "scene/3d/node_3d.h"

class PackedScene;

// Runtime scene-instance streaming across a fixed X/Z grid.
// This node does not bake geometry or implement asynchronous resource I/O.
class WorldPartition3D : public Node3D {
	GDCLASS(WorldPartition3D, Node3D);

	Dictionary cells;
	HashMap<Vector2i, ObjectID> loaded_cells;
	NodePath viewer_path;
	real_t cell_size = 64.0;
	int load_radius = 1;
	Vector2i last_center;
	bool has_last_center = false;

	void _load_cell(const Vector2i &p_coords);
	void _unload_cell(const Vector2i &p_coords);
	void _unload_all_cells();
	void _invalidate_streaming();
	void _update_for_center(const Vector2i &p_center);

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	void set_cells(const Dictionary &p_cells);
	Dictionary get_cells() const;
	void set_cell_scene(const Vector2i &p_coords, const Ref<PackedScene> &p_scene);
	void set_cell_path(const Vector2i &p_coords, const String &p_path);
	void remove_cell(const Vector2i &p_coords);
	Variant get_cell_source(const Vector2i &p_coords) const;

	void set_cell_size(real_t p_size);
	real_t get_cell_size() const;
	void set_load_radius(int p_radius);
	int get_load_radius() const;
	void set_viewer_path(const NodePath &p_path);
	NodePath get_viewer_path() const;

	Vector2i world_to_cell(const Vector3 &p_world_position) const;
	void update_streaming(const Vector3 &p_world_position);
	void unload_all_cells();
	int get_loaded_cell_count() const;
	Node3D *get_loaded_cell(const Vector2i &p_coords) const;

	PackedStringArray get_configuration_warnings() const override;
};
