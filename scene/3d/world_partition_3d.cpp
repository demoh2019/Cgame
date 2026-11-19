/**************************************************************************/
/*  world_partition_3d.cpp                                                */
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

#include "world_partition_3d.h"

#include "core/config/engine.h"
#include "core/io/resource_loader.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "scene/resources/packed_scene.h"

void WorldPartition3D::_load_cell(const Vector2i &p_coords) {
	if (loaded_cells.has(p_coords) || !cells.has(p_coords)) {
		return;
	}

	Variant source = cells[p_coords];
	Ref<PackedScene> scene;
	if (source.get_type() == Variant::STRING) {
		const String path = source;
		scene = ResourceLoader::load(path, "PackedScene");
	} else if (source.get_type() == Variant::OBJECT) {
		scene = source;
	}

	if (scene.is_null()) {
		emit_signal("cell_load_failed", p_coords);
		return;
	}

	Node *instance = scene->instantiate();
	if (!instance) {
		emit_signal("cell_load_failed", p_coords);
		return;
	}

	Node3D *root = Object::cast_to<Node3D>(instance);
	if (!root) {
		memdelete(instance);
		ERR_PRINT(vformat("WorldPartition3D cell (%d, %d) requires a Node3D scene root.", p_coords.x, p_coords.y));
		emit_signal("cell_load_failed", p_coords);
		return;
	}

	// Keep the authored local offset, relative to the cell origin.
	root->set_position(root->get_position() + Vector3(p_coords.x * cell_size, 0, p_coords.y * cell_size));
	add_child(root);
	loaded_cells.insert(p_coords, root->get_instance_id());
	emit_signal("cell_loaded", p_coords, root);
}

void WorldPartition3D::_unload_cell(const Vector2i &p_coords) {
	ObjectID *instance_id = loaded_cells.getptr(p_coords);
	if (!instance_id) {
		return;
	}

	Node3D *root = ObjectDB::get_instance<Node3D>(*instance_id);
	loaded_cells.erase(p_coords);
	emit_signal("cell_unloaded", p_coords);
	if (root && root->get_parent() == this) {
		remove_child(root);
		memdelete(root);
	}
}

void WorldPartition3D::_unload_all_cells() {
	Vector<Vector2i> keys;
	for (const KeyValue<Vector2i, ObjectID> &E : loaded_cells) {
		keys.push_back(E.key);
	}
	for (const Vector2i &coords : keys) {
		_unload_cell(coords);
	}
}

void WorldPartition3D::_invalidate_streaming() {
	_unload_all_cells();
	has_last_center = false;
}

void WorldPartition3D::_update_for_center(const Vector2i &p_center) {
	if (has_last_center && p_center == last_center) {
		return;
	}

	Vector<Vector2i> unload;
	for (const KeyValue<Vector2i, ObjectID> &E : loaded_cells) {
		int64_t dx = int64_t(E.key.x) - p_center.x;
		int64_t dz = int64_t(E.key.y) - p_center.y;
		if (Math::abs(dx) > load_radius || Math::abs(dz) > load_radius || !cells.has(E.key)) {
			unload.push_back(E.key);
		}
	}
	for (const Vector2i &coords : unload) {
		_unload_cell(coords);
	}

	// Iterate nearby coordinates, not all registered world cells.
	for (int dz = -load_radius; dz <= load_radius; dz++) {
		for (int dx = -load_radius; dx <= load_radius; dx++) {
			int64_t x = int64_t(p_center.x) + dx;
			int64_t z = int64_t(p_center.y) + dz;
			if (x < INT32_MIN || x > INT32_MAX || z < INT32_MIN || z > INT32_MAX) {
				continue;
			}
			Vector2i coords(int(x), int(z));
			if (cells.has(coords) && !loaded_cells.has(coords)) {
				_load_cell(coords);
			}
		}
	}
	has_last_center = true;
	last_center = p_center;
}

void WorldPartition3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			set_process(!viewer_path.is_empty() && !Engine::get_singleton()->is_editor_hint());
		} break;
		case NOTIFICATION_PROCESS: {
			Node3D *viewer = Object::cast_to<Node3D>(get_node_or_null(viewer_path));
			if (viewer) {
				update_streaming(viewer->get_global_position());
			}
		} break;
	}
}

void WorldPartition3D::set_cells(const Dictionary &p_cells) {
	Array keys = p_cells.keys();
	for (int i = 0; i < keys.size(); i++) {
		Variant key = keys[i];
		ERR_FAIL_COND_MSG(key.get_type() != Variant::VECTOR2I, "WorldPartition3D cell keys must be Vector2i.");
		Variant value = p_cells[key];
		ERR_FAIL_COND_MSG(value.get_type() != Variant::STRING && value.get_type() != Variant::OBJECT, "WorldPartition3D cells must be PackedScene resources or scene paths.");
		if (value.get_type() == Variant::OBJECT) {
			Ref<PackedScene> packed_scene = value;
			ERR_FAIL_COND_MSG(packed_scene.is_null(), "WorldPartition3D cell resources must be PackedScene.");
		} else {
			ERR_FAIL_COND_MSG(String(value).is_empty(), "WorldPartition3D cell paths must not be empty.");
		}
	}
	cells = p_cells.duplicate();
	_invalidate_streaming();
}

Dictionary WorldPartition3D::get_cells() const {
	return cells.duplicate();
}

void WorldPartition3D::set_cell_scene(const Vector2i &p_coords, const Ref<PackedScene> &p_scene) {
	ERR_FAIL_COND_MSG(p_scene.is_null(), "A cell requires a valid PackedScene.");
	cells[p_coords] = p_scene;
	_invalidate_streaming();
}

void WorldPartition3D::set_cell_path(const Vector2i &p_coords, const String &p_path) {
	ERR_FAIL_COND_MSG(p_path.is_empty(), "A cell requires a non-empty scene path.");
	cells[p_coords] = p_path;
	_invalidate_streaming();
}

void WorldPartition3D::remove_cell(const Vector2i &p_coords) {
	cells.erase(p_coords);
	_invalidate_streaming();
}

Variant WorldPartition3D::get_cell_source(const Vector2i &p_coords) const {
	return cells.get(p_coords, Variant());
}

void WorldPartition3D::set_cell_size(real_t p_size) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_size) || p_size <= 0.0, "Cell size must be finite and greater than zero.");
	if (Math::is_equal_approx(cell_size, p_size)) {
		return;
	}
	cell_size = p_size;
	_invalidate_streaming();
}

real_t WorldPartition3D::get_cell_size() const {
	return cell_size;
}

void WorldPartition3D::set_load_radius(int p_radius) {
	ERR_FAIL_COND_MSG(p_radius < 0 || p_radius > 16, "Load radius must be between 0 and 16 cells.");
	if (load_radius == p_radius) {
		return;
	}
	load_radius = p_radius;
	_invalidate_streaming();
}

int WorldPartition3D::get_load_radius() const {
	return load_radius;
}

void WorldPartition3D::set_viewer_path(const NodePath &p_path) {
	viewer_path = p_path;
	if (is_inside_tree()) {
		set_process(!viewer_path.is_empty() && !Engine::get_singleton()->is_editor_hint());
	}
	update_configuration_warnings();
}

NodePath WorldPartition3D::get_viewer_path() const {
	return viewer_path;
}

Vector2i WorldPartition3D::world_to_cell(const Vector3 &p_world_position) const {
	Vector3 local = to_local(p_world_position);
	return Vector2i(int(Math::floor(local.x / cell_size)), int(Math::floor(local.z / cell_size)));
}

void WorldPartition3D::update_streaming(const Vector3 &p_world_position) {
	ERR_FAIL_COND_MSG(!is_inside_tree(), "WorldPartition3D must be inside SceneTree to stream scenes.");
	ERR_FAIL_COND_MSG(!p_world_position.is_finite(), "Streaming position must contain finite coordinates.");
	_update_for_center(world_to_cell(p_world_position));
}

void WorldPartition3D::unload_all_cells() {
	_unload_all_cells();
	has_last_center = false;
}

int WorldPartition3D::get_loaded_cell_count() const {
	return loaded_cells.size();
}

Node3D *WorldPartition3D::get_loaded_cell(const Vector2i &p_coords) const {
	const ObjectID *instance_id = loaded_cells.getptr(p_coords);
	return instance_id ? ObjectDB::get_instance<Node3D>(*instance_id) : nullptr;
}

PackedStringArray WorldPartition3D::get_configuration_warnings() const {
	PackedStringArray warnings = Node3D::get_configuration_warnings();
	if (viewer_path.is_empty()) {
		warnings.push_back(RTR("Viewer Path is empty; call update_streaming() manually or assign a Node3D viewer."));
	} else if (is_inside_tree() && !Object::cast_to<Node3D>(get_node_or_null(viewer_path))) {
		warnings.push_back(RTR("Viewer Path must point to a Node3D."));
	}
	return warnings;
}

void WorldPartition3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cells", "cells"), &WorldPartition3D::set_cells);
	ClassDB::bind_method(D_METHOD("get_cells"), &WorldPartition3D::get_cells);
	ClassDB::bind_method(D_METHOD("set_cell_scene", "coords", "scene"), &WorldPartition3D::set_cell_scene);
	ClassDB::bind_method(D_METHOD("set_cell_path", "coords", "path"), &WorldPartition3D::set_cell_path);
	ClassDB::bind_method(D_METHOD("remove_cell", "coords"), &WorldPartition3D::remove_cell);
	ClassDB::bind_method(D_METHOD("get_cell_source", "coords"), &WorldPartition3D::get_cell_source);
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &WorldPartition3D::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &WorldPartition3D::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_load_radius", "radius"), &WorldPartition3D::set_load_radius);
	ClassDB::bind_method(D_METHOD("get_load_radius"), &WorldPartition3D::get_load_radius);
	ClassDB::bind_method(D_METHOD("set_viewer_path", "path"), &WorldPartition3D::set_viewer_path);
	ClassDB::bind_method(D_METHOD("get_viewer_path"), &WorldPartition3D::get_viewer_path);
	ClassDB::bind_method(D_METHOD("world_to_cell", "world_position"), &WorldPartition3D::world_to_cell);
	ClassDB::bind_method(D_METHOD("update_streaming", "world_position"), &WorldPartition3D::update_streaming);
	ClassDB::bind_method(D_METHOD("unload_all_cells"), &WorldPartition3D::unload_all_cells);
	ClassDB::bind_method(D_METHOD("get_loaded_cell_count"), &WorldPartition3D::get_loaded_cell_count);
	ClassDB::bind_method(D_METHOD("get_loaded_cell", "coords"), &WorldPartition3D::get_loaded_cell);

	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "cells"), "set_cells", "get_cells");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,10000,1,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "load_radius", PROPERTY_HINT_RANGE, "0,16,1"), "set_load_radius", "get_load_radius");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "viewer_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_viewer_path", "get_viewer_path");

	ADD_SIGNAL(MethodInfo("cell_loaded", PropertyInfo(Variant::VECTOR2I, "coords"), PropertyInfo(Variant::OBJECT, "instance")));
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "coords")));
	ADD_SIGNAL(MethodInfo("cell_load_failed", PropertyInfo(Variant::VECTOR2I, "coords")));
}
