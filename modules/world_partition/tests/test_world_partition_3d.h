/**************************************************************************/
/*  test_world_partition_3d.h                                             */
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

#include "../world_partition_3d.h"

#include "core/config/project_settings.h"
#include "core/io/dir_access.h"
#include "core/io/resource_saver.h"
#include "core/os/os.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "tests/test_macros.h"

#include <limits>

namespace TestWorldPartition3D {

TEST_CASE("[WorldPartition3D] Defaults") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	CHECK(partition->get_cell_size() == 128.0);
	CHECK(partition->get_load_radius() == 1);
	CHECK(partition->get_unload_radius() == 2);
	CHECK(partition->get_max_new_requests_per_frame() == 2);
	CHECK(partition->get_max_instances_per_frame() == 2);
	CHECK(partition->get_max_concurrent_requests() == 8);
	CHECK(partition->is_streaming_enabled());
	CHECK(partition->get_configured_cell_count() == 0);
	CHECK(partition->get_loaded_cell_count() == 0);
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Exact positive and negative cell boundaries") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_size(16.0);
	CHECK(partition->local_position_to_cell(Vector3(0, 0, 0)) == Vector2i(0, 0));
	CHECK(partition->local_position_to_cell(Vector3(15.999, 0, 15.999)) == Vector2i(0, 0));
	CHECK(partition->local_position_to_cell(Vector3(16, 0, 16)) == Vector2i(1, 1));
	CHECK(partition->local_position_to_cell(Vector3(32, 0, 48)) == Vector2i(2, 3));
	CHECK(partition->local_position_to_cell(Vector3(-0.001, 0, -0.001)) == Vector2i(-1, -1));
	CHECK(partition->local_position_to_cell(Vector3(-16, 0, -16)) == Vector2i(-1, -1));
	CHECK(partition->local_position_to_cell(Vector3(-16.001, 0, -16.001)) == Vector2i(-2, -2));
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] X and Z coordinates are independent of height") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_size(10.0);
	CHECK(partition->local_position_to_cell(Vector3(21, 0, -11)) == Vector2i(2, -2));
	CHECK(partition->local_position_to_cell(Vector3(21, 10000, -11)) == Vector2i(2, -2));
	CHECK(partition->local_position_to_cell(Vector3(21, -10000, -11)) == Vector2i(2, -2));
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Changing cell size changes mapping") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	CHECK(partition->local_position_to_cell(Vector3(100, 0, 100)) == Vector2i(0, 0));
	partition->set_cell_size(20.0);
	CHECK(partition->local_position_to_cell(Vector3(100, 0, 100)) == Vector2i(5, 5));
	partition->set_cell_size(0.5);
	CHECK(partition->local_position_to_cell(Vector3(1, 0, 1)) == Vector2i(2, 2));
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Cell to local position and back") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_size(12.5);
	for (int x = -4; x <= 4; x++) {
		for (int z = -4; z <= 4; z++) {
			const Vector2i coord(x, z);
			CHECK(partition->local_position_to_cell(partition->cell_to_local_position(coord)) == coord);
		}
	}
	CHECK(partition->cell_to_local_position(Vector2i(-2, 3)) == Vector3(-25, 0, 37.5));
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Radius zero returns center") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	const Array cells = partition->get_cells_in_radius(Vector2i(13, -5), 0);
	REQUIRE(cells.size() == 1);
	CHECK(cells[0] == Vector2i(13, -5));
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Radius one includes all nine neighboring cells") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	const Array cells = partition->get_cells_in_radius(Vector2i(0, 0), 1);
	REQUIRE(cells.size() == 9);
	for (int x = -1; x <= 1; x++) {
		for (int z = -1; z <= 1; z++) {
			CHECK(cells.has(Vector2i(x, z)));
		}
	}
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Radius two has 25 distinct cells") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	const Array cells = partition->get_cells_in_radius(Vector2i(-30, 27), 2);
	REQUIRE(cells.size() == 25);
	for (int i = 0; i < cells.size(); i++) {
		for (int j = i + 1; j < cells.size(); j++) {
			CHECK_FALSE(cells[i] == cells[j]);
		}
	}
	CHECK(cells.has(Vector2i(-32, 25)));
	CHECK(cells.has(Vector2i(-28, 29)));
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Registration, replacement and removal") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_scene(Vector2i(-1, 2), "res://maps/first.tscn");
	CHECK(partition->get_cell_scene(Vector2i(-1, 2)) == "res://maps/first.tscn");
	CHECK(partition->get_configured_cell_count() == 1);
	partition->set_cell_scene(Vector2i(-1, 2), "res://maps/second.tscn");
	CHECK(partition->get_configured_cell_count() == 1);
	CHECK(partition->get_cell_scene(Vector2i(-1, 2)) == "res://maps/second.tscn");
	partition->remove_cell_scene(Vector2i(-1, 2));
	CHECK(partition->get_configured_cell_count() == 0);
	CHECK(partition->get_cell_scene(Vector2i(-1, 2)).is_empty());
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Empty scene paths remove cells") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_scene(Vector2i(0, 0), "res://maps/cell.tscn");
	partition->set_cell_scene(Vector2i(0, 0), "");
	CHECK(partition->get_configured_cell_count() == 0);
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Sparse cells can have different scene paths") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_scene(Vector2i(-200, 5), "res://a.tscn");
	partition->set_cell_scene(Vector2i(0, 0), "res://b.tscn");
	partition->set_cell_scene(Vector2i(800, -900), "res://c.tscn");
	CHECK(partition->get_configured_cell_count() == 3);
	CHECK(partition->get_cell_scene(Vector2i(-200, 5)) == "res://a.tscn");
	CHECK(partition->get_cell_scene(Vector2i(0, 0)) == "res://b.tscn");
	CHECK(partition->get_cell_scene(Vector2i(800, -900)) == "res://c.tscn");
	CHECK(partition->get_cell_scene(Vector2i(0, 1)).is_empty());
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Bulk cell setter validates dictionary entries") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	Dictionary input;
	input[Vector2i(2, 3)] = "res://valid.tscn";
	input[Vector2i(4, 5)] = "";
	input[String("wrong-key")] = "res://invalid.tscn";
	input[Vector2i(6, 7)] = 15;
	partition->set_cell_scenes(input);
	CHECK(partition->get_configured_cell_count() == 1);
	CHECK(partition->get_cell_scene(Vector2i(2, 3)) == "res://valid.tscn");
	CHECK(partition->get_cell_scene(Vector2i(4, 5)).is_empty());
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Cell dictionary getter is a defensive copy") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_scene(Vector2i(0, 0), "res://a.tscn");
	Dictionary snapshot = partition->get_cell_scenes();
	snapshot[Vector2i(0, 0)] = "res://changed.tscn";
	snapshot[Vector2i(1, 0)] = "res://new.tscn";
	CHECK(partition->get_cell_scene(Vector2i(0, 0)) == "res://a.tscn");
	CHECK(partition->get_configured_cell_count() == 1);
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Clearing cells resets registrations") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_scene(Vector2i(1, 1), "res://a.tscn");
	partition->set_cell_scene(Vector2i(2, 2), "res://b.tscn");
	partition->clear_cell_scenes();
	CHECK(partition->get_configured_cell_count() == 0);
	CHECK(partition->get_loaded_cell_count() == 0);
	CHECK(partition->get_loaded_cells().is_empty());
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Load and unload radii enforce hysteresis") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_load_radius(4);
	CHECK(partition->get_load_radius() == 4);
	CHECK(partition->get_unload_radius() == 4);
	partition->set_unload_radius(6);
	CHECK(partition->get_unload_radius() == 6);
	partition->set_load_radius(1);
	CHECK(partition->get_unload_radius() == 6);
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Request, instance and concurrency budgets") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_max_new_requests_per_frame(1);
	partition->set_max_instances_per_frame(7);
	partition->set_max_concurrent_requests(12);
	CHECK(partition->get_max_new_requests_per_frame() == 1);
	CHECK(partition->get_max_instances_per_frame() == 7);
	CHECK(partition->get_max_concurrent_requests() == 12);
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Invalid settings are rejected without mutation") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	ERR_PRINT_OFF;
	partition->set_cell_size(0.0);
	partition->set_cell_size(-10.0);
	partition->set_cell_size(std::numeric_limits<real_t>::infinity());
	partition->set_load_radius(-1);
	partition->set_load_radius(33);
	partition->set_unload_radius(-1);
	partition->set_unload_radius(65);
	partition->set_max_new_requests_per_frame(0);
	partition->set_max_instances_per_frame(0);
	partition->set_max_concurrent_requests(0);
	const Array invalid_cells = partition->get_cells_in_radius(Vector2i(), -1);
	ERR_PRINT_ON;
	CHECK(partition->get_cell_size() == 128.0);
	CHECK(partition->get_load_radius() == 1);
	CHECK(partition->get_unload_radius() == 2);
	CHECK(partition->get_max_new_requests_per_frame() == 2);
	CHECK(partition->get_max_instances_per_frame() == 2);
	CHECK(partition->get_max_concurrent_requests() == 8);
	CHECK(invalid_cells.is_empty());
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Streaming can be disabled without losing cell data") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_scene(Vector2i(1, 2), "res://level.tscn");
	partition->set_streaming_enabled(false);
	CHECK_FALSE(partition->is_streaming_enabled());
	CHECK(partition->get_configured_cell_count() == 1);
	partition->set_streaming_enabled(true);
	CHECK(partition->is_streaming_enabled());
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Observer path is configurable") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_observer_path(NodePath("../Player"));
	CHECK(partition->get_observer_path() == NodePath("../Player"));
	partition->set_observer_path(NodePath());
	CHECK(partition->get_observer_path().is_empty());
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Stream one authored PackedScene and unload it") {
	// A real disk round-trip exercises ResourceLoader and the native streaming node.
	Node3D *template_root = memnew(Node3D);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(template_root) == OK);
	memdelete(template_root);

	const String path = "user://world_partition_doctest_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	REQUIRE(ResourceSaver::save(packed, path) == OK);

	Node3D *observer = memnew(Node3D);
	observer->set_name("WorldPartitionObserver");
	WorldPartition3D *partition = memnew(WorldPartition3D);
	SceneTree::get_singleton()->get_root()->add_child(observer);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_cell_size(16);
	partition->set_load_radius(0);
	partition->set_unload_radius(1);
	partition->set_observer_path(partition->get_path_to(observer));
	partition->set_cell_scene(Vector2i(0, 0), path);

	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(0, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	CHECK(partition->is_cell_loaded(Vector2i(0, 0)));
	CHECK(partition->get_loaded_cell_count() == 1);
	observer->set_position(Vector3(64, 0, 0));
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(0, 0)));
	CHECK(partition->get_loaded_cell_count() == 0);

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(observer);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

} // namespace TestWorldPartition3D
