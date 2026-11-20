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

#include "core/io/dir_access.h"
#include "core/io/resource_saver.h"
#include "core/math/math_funcs.h"
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
	CHECK(partition->get_prefetch_direction() == Vector2i());
	CHECK(partition->get_prefetch_distance() == 0);
	CHECK(partition->get_max_new_requests_per_frame() == 2);
	CHECK(partition->get_max_instances_per_frame() == 2);
	CHECK(partition->get_max_instantiation_time_ms() == 0.0);
	partition->set_max_instantiation_time_ms(2.5);
	CHECK(partition->get_max_instantiation_time_ms() == 2.5);
	partition->set_max_instantiation_time_ms(0.0);
	CHECK(partition->get_max_instantiation_time_ms() == 0.0);
	CHECK(partition->get_max_concurrent_requests() == 8);
	CHECK(partition->get_prefetch_direction() == Vector2i());
	CHECK(partition->get_prefetch_distance() == 0);
	CHECK(partition->is_streaming_enabled());
	CHECK(partition->get_configured_cell_count() == 0);
	CHECK(partition->get_loaded_cell_count() == 0);
	CHECK_FALSE(partition->are_cells_loaded(Vector2i(0, 0)));
	CHECK_FALSE(partition->are_cells_loaded(Vector2i(0, 0), 1));
	CHECK(partition->get_last_streaming_update_ms() == 0.0);
	CHECK(partition->get_last_instantiation_attempt_count() == 0);
	CHECK(partition->get_pending_cell_count() == 0);
	CHECK(partition->get_inflight_request_count() == 0);
	CHECK(partition->get_failed_cell_count() == 0);
	CHECK(partition->get_pinned_cell_count() == 0);
	CHECK_FALSE(partition->is_cell_pinned(Vector2i(0, 0)));
	memdelete(partition);
}

TEST_CASE("[WorldPartition3D] Pinned cells are registered bounded and lifecycle-safe") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	ERR_PRINT_OFF;
	CHECK_FALSE(partition->pin_cell(Vector2i(200, 200)));
	ERR_PRINT_ON;
	for (int i = 0; i < 17; i++) {
		partition->set_cell_scene(Vector2i(i, 0), "res://valid_test_scene.tscn");
	}
	for (int i = 0; i < 16; i++) {
		CHECK(partition->pin_cell(Vector2i(i, 0)));
	}
	CHECK(partition->get_pinned_cell_count() == 16);
	CHECK(partition->pin_cell(Vector2i(0, 0))); // Idempotent.
	CHECK(partition->get_pinned_cell_count() == 16);
	ERR_PRINT_OFF;
	CHECK_FALSE(partition->pin_cell(Vector2i(16, 0))); // Bounded.
	ERR_PRINT_ON;
	CHECK_FALSE(partition->is_cell_pinned(Vector2i(16, 0)));

	partition->unpin_cell(Vector2i(3, 0));
	CHECK(partition->get_pinned_cell_count() == 15);
	partition->remove_cell_scene(Vector2i(4, 0));
	CHECK_FALSE(partition->is_cell_pinned(Vector2i(4, 0)));
	CHECK(partition->get_pinned_cell_count() == 14);
	partition->set_streaming_enabled(false);
	CHECK(partition->get_pinned_cell_count() == 14);
	partition->set_streaming_enabled(true);

	Dictionary new_cells;
	new_cells[Vector2i(-3, 2)] = "res://next_scene.tscn";
	partition->set_cell_scenes(new_cells);
	CHECK(partition->get_pinned_cell_count() == 0);
	CHECK_FALSE(partition->is_cell_pinned(Vector2i(0, 0)));
	CHECK(partition->pin_cell(Vector2i(-3, 2)));
	partition->clear_cell_scenes();
	CHECK(partition->get_pinned_cell_count() == 0);
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Pinned remote cells load and unload independently of the observer") {
	Node3D *template_root = memnew(Node3D);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(template_root) == OK);
	memdelete(template_root);
	const String path = "user://world_partition_pins_doctest_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	REQUIRE(ResourceSaver::save(packed, path) == OK);

	WorldPartition3D *partition = memnew(WorldPartition3D);
	Node3D *observer = memnew(Node3D);
	observer->set_name("PinObserver");
	SceneTree::get_singleton()->get_root()->add_child(observer);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_cell_size(16);
	partition->set_load_radius(0);
	partition->set_unload_radius(0);
	partition->set_max_instances_per_frame(1);
	partition->set_observer_path(partition->get_path_to(observer));
	partition->set_cell_scene(Vector2i(0, 0), path);
	partition->set_cell_scene(Vector2i(5, 0), path);
	CHECK(partition->pin_cell(Vector2i(5, 0)));

	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(0, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(0, 0)));
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(5, 0))); // Near-first budget.
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(5, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(5, 0)));
	CHECK(partition->get_loaded_cell_count() == 2);

	partition->unpin_cell(Vector2i(5, 0));
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(5, 0)));
	CHECK(partition->get_loaded_cell_count() == 1);
	CHECK(partition->get_cell_scene(Vector2i(5, 0)) == path);

	CHECK(partition->pin_cell(Vector2i(5, 0)));
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(5, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(5, 0)));
	partition->set_streaming_enabled(false);
	CHECK(partition->get_loaded_cell_count() == 0);
	CHECK(partition->is_cell_pinned(Vector2i(5, 0)));
	partition->set_streaming_enabled(true);
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(5, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	CHECK(partition->is_cell_loaded(Vector2i(5, 0)));
	partition->clear_pinned_cells();
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(5, 0)));

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(observer);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[WorldPartition3D] Named streaming sources validate radii priority and bounded count") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	CHECK(partition->get_streaming_source_count() == 0);
	CHECK(partition->get_streaming_source("unknown").is_empty());
	CHECK(partition->get_streaming_source_names().is_empty());
	CHECK_FALSE(partition->is_streaming_source_ready("unknown"));
	CHECK(partition->get_streaming_source_progress("unknown") == 0.0);
	CHECK(partition->has_signal(SNAME("streaming_source_ready")));
	CHECK(partition->has_signal(SNAME("streaming_source_unready")));

	CHECK(partition->set_streaming_source("survey", Vector2i(10, -4), 1, 2, 75));
	CHECK(partition->get_streaming_source_count() == 1);
	Dictionary survey = partition->get_streaming_source("survey");
	CHECK(survey["center"] == Vector2i(10, -4));
	CHECK(survey["load_radius"] == 1);
	CHECK(survey["unload_radius"] == 2);
	CHECK(survey["priority"] == 75);
	CHECK_FALSE(partition->is_streaming_source_ready("survey"));
	CHECK(partition->get_streaming_source_progress("survey") == 0.0);
	CHECK(partition->set_streaming_source("survey", Vector2i(11, -4), 0, 0, 99));
	CHECK(partition->get_streaming_source_count() == 1);
	CHECK(partition->get_streaming_source("survey")["center"] == Vector2i(11, -4));

	ERR_PRINT_OFF;
	CHECK_FALSE(partition->set_streaming_source("", Vector2i(), 0, 0, 1));
	CHECK_FALSE(partition->set_streaming_source("invalid_radius", Vector2i(), -1, 0, 1));
	CHECK_FALSE(partition->set_streaming_source("invalid_hysteresis", Vector2i(), 2, 1, 1));
	CHECK_FALSE(partition->set_streaming_source("invalid_large", Vector2i(), 5, 5, 1));
	CHECK_FALSE(partition->set_streaming_source("invalid_priority", Vector2i(), 0, 0, 101));
	CHECK_FALSE(partition->set_streaming_source("invalid_overflow", Vector2i(INT32_MAX, 0), 0, 1, 1));
	ERR_PRINT_ON;
	CHECK(partition->get_streaming_source_count() == 1);
	for (int i = 1; i < 8; i++) {
		CHECK(partition->set_streaming_source("extra_" + itos(i), Vector2i(i, 0), 0, 0, 0));
	}
	CHECK(partition->get_streaming_source_count() == 8);
	ERR_PRINT_OFF;
	CHECK_FALSE(partition->set_streaming_source("ninth", Vector2i(), 0, 0, 0));
	ERR_PRINT_ON;
	CHECK(partition->get_streaming_source_count() == 8);
	CHECK(partition->set_streaming_source("survey", Vector2i(12, 0), 0, 1, 100));
	CHECK(partition->get_streaming_source_count() == 8);
	Array names = partition->get_streaming_source_names();
	CHECK(names.size() == 8);
	partition->remove_streaming_source("survey");
	CHECK(partition->get_streaming_source_count() == 7);
	partition->remove_streaming_source("survey");
	partition->clear_streaming_sources();
	CHECK(partition->get_streaming_source_count() == 0);
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Named source priority and readiness survive remote streaming") {
	Node3D *template_root = memnew(Node3D);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(template_root) == OK);
	memdelete(template_root);
	const String path = "user://world_partition_multisource_doctest_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	REQUIRE(ResourceSaver::save(packed, path) == OK);

	Node3D *observer = memnew(Node3D);
	observer->set_name("MultiSourceObserver");
	WorldPartition3D *partition = memnew(WorldPartition3D);
	SceneTree::get_singleton()->get_root()->add_child(observer);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_cell_size(16);
	partition->set_load_radius(0);
	partition->set_unload_radius(0);
	partition->set_max_instances_per_frame(1);
	partition->set_observer_path(partition->get_path_to(observer));
	partition->set_cell_scene(Vector2i(), path);
	partition->set_cell_scene(Vector2i(-5, 0), path);
	partition->set_cell_scene(Vector2i(5, 0), path);
	partition->set_cell_scene(Vector2i(7, 0), path);
	CHECK(partition->set_streaming_source("low", Vector2i(-5, 0), 0, 1, 5));
	CHECK(partition->set_streaming_source("high", Vector2i(5, 0), 0, 1, 95));

	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i()); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i()));
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(5, 0)));
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(5, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(5, 0)));
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(-5, 0)));
	CHECK(partition->is_streaming_source_ready("high"));
	CHECK(partition->get_streaming_source_progress("high") == 1.0);
	CHECK_FALSE(partition->is_streaming_source_ready("low"));
	CHECK(partition->get_streaming_source_progress("low") == 0.0);
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(-5, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(-5, 0)));
	CHECK(partition->is_streaming_source_ready("low"));
	CHECK(partition->get_streaming_source_progress("low") == 1.0);
	CHECK(partition->get_loaded_cell_count() == 3);

	CHECK(partition->set_streaming_source("high", Vector2i(7, 0), 0, 1, 95));
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(5, 0)));
	CHECK_FALSE(partition->is_streaming_source_ready("high"));
	for (int i = 0; i < 2000 && !partition->is_streaming_source_ready("high"); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	CHECK(partition->is_cell_loaded(Vector2i(7, 0)));
	partition->remove_streaming_source("high");
	partition->remove_streaming_source("low");
	partition->update_streaming();
	CHECK(partition->get_streaming_source_count() == 0);
	CHECK(partition->get_loaded_cell_count() == 1);

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(observer);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Actor-driven streaming follows Node3D movement and missing targets") {
	Node3D *template_root = memnew(Node3D);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(template_root) == OK);
	memdelete(template_root);
	const String path = "user://world_partition_follow_doctest_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	REQUIRE(ResourceSaver::save(packed, path) == OK);

	Node3D *observer = memnew(Node3D);
	observer->set_name("FollowObserver");
	Node3D *drone = memnew(Node3D);
	drone->set_name("FollowDrone");
	drone->set_position(Vector3(48, 0, 0));
	WorldPartition3D *partition = memnew(WorldPartition3D);
	SceneTree::get_singleton()->get_root()->add_child(observer);
	SceneTree::get_singleton()->get_root()->add_child(drone);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_cell_size(16);
	// The actor is in global space; WorldPartition3D may be translated and
	// rotated, so follow must first convert to partition-local coordinates.
	partition->set_position(Vector3(100, 0, 25));
	partition->set_rotation(Vector3(0, Math::PI / 2, 0));
	observer->set_global_position(partition->to_global(Vector3()));
	drone->set_global_position(partition->to_global(Vector3(48, 0, 0)));
	partition->set_load_radius(0);
	partition->set_unload_radius(0);
	partition->set_max_instances_per_frame(1);
	partition->set_observer_path(partition->get_path_to(observer));
	partition->set_cell_scene(Vector2i(0, 0), path);
	partition->set_cell_scene(Vector2i(3, 0), path);
	partition->set_cell_scene(Vector2i(6, 0), path);

	ERR_PRINT_OFF;
	CHECK_FALSE(partition->set_streaming_source_node("invalid", NodePath(), 0, 0, 80));
	CHECK_FALSE(partition->set_streaming_source_node("invalid", NodePath("../FollowDrone:position"), 0, 0, 80));
	ERR_PRINT_ON;
	CHECK(partition->get_streaming_source_count() == 0);
	CHECK(partition->set_streaming_source_node("drone", partition->get_path_to(drone), 0, 0, 80));
	CHECK(partition->get_streaming_source_count() == 1);

	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(3, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(0, 0)));
	REQUIRE(partition->is_cell_loaded(Vector2i(3, 0)));
	Dictionary info = partition->get_streaming_source("drone");
	CHECK(bool(info["active"]));
	CHECK(info["center"] == Vector2i(3, 0));
	CHECK(info["node_path"] == partition->get_path_to(drone));
	CHECK(partition->is_streaming_source_ready("drone"));
	CHECK(partition->get_streaming_source_progress("drone") == 1.0);

	drone->set_global_position(partition->to_global(Vector3(96, 0, 0)));
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(3, 0)));
	CHECK(partition->get_streaming_source("drone")["center"] == Vector2i(6, 0));
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(6, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(6, 0)));
	CHECK(partition->is_streaming_source_ready("drone"));

	SceneTree::get_singleton()->get_root()->remove_child(drone);
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(6, 0)));
	CHECK_FALSE(partition->is_streaming_source_ready("drone"));
	CHECK(partition->get_streaming_source_progress("drone") == 0.0);
	CHECK_FALSE(bool(partition->get_streaming_source("drone")["active"]));
	CHECK(partition->get_streaming_source_count() == 1);

	SceneTree::get_singleton()->get_root()->add_child(drone);
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(6, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(6, 0)));
	CHECK(partition->is_streaming_source_ready("drone"));

	CHECK(partition->set_streaming_source("drone", Vector2i(3, 0), 0, 0, 80));
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(6, 0)));
	CHECK(partition->get_streaming_source("drone")["node_path"] == NodePath());
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(3, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	CHECK(partition->is_cell_loaded(Vector2i(3, 0)));

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(drone);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(drone);
	memdelete(observer);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Supercover navigation corridor respects streaming and transformed grids") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_cell_size(32.0);
	partition->set_position(Vector3(140.0, 0.0, -50.0));
	partition->set_rotation(Vector3(0.0, Math::PI / 2.0, 0.0));
	const auto global_at = [&](real_t p_x, real_t p_z) {
		return partition->to_global(Vector3(p_x, 0.0, p_z));
	};

	const Array flat = partition->get_navigation_route_cells(global_at(2, 9), global_at(70, 9));
	REQUIRE(flat.size() == 3);
	CHECK(flat[0] == Vector2i(0, 0));
	CHECK(flat[1] == Vector2i(1, 0));
	CHECK(flat[2] == Vector2i(2, 0));
	const Array reverse = partition->get_navigation_route_cells(global_at(70, 9), global_at(2, 9));
	REQUIRE(reverse.size() == 3);
	CHECK(reverse[0] == Vector2i(2, 0));
	CHECK(reverse[2] == Vector2i(0, 0));

	const Array diagonal = partition->get_navigation_route_cells(global_at(1, 1), global_at(65, 65));
	REQUIRE(diagonal.size() == 7);
	CHECK(diagonal[0] == Vector2i(0, 0));
	CHECK(diagonal[1] == Vector2i(1, 0)); // Corner-crossing side tile.
	CHECK(diagonal[2] == Vector2i(0, 1)); // Both neighbors included.
	CHECK(diagonal[3] == Vector2i(1, 1));
	CHECK(diagonal[6] == Vector2i(2, 2));

	const Array same_cell = partition->get_navigation_route_cells(global_at(3, 4), global_at(20, 20), 1);
	REQUIRE(same_cell.size() == 1);
	CHECK(same_cell[0] == Vector2i(0, 0));
	CHECK(partition->get_navigation_route_cells(global_at(1, 1), global_at(65, 65), 6).is_empty());
	CHECK(partition->get_navigation_route_cells(global_at(2, 9), global_at(70, 9), 2).is_empty());
	CHECK(partition->get_navigation_route_cells(global_at(-1, -1), global_at(-65, -1)).size() == 3);

	ERR_PRINT_OFF;
	CHECK(partition->get_navigation_route_cells(global_at(1, 1), global_at(2, 2), 0).is_empty());
	CHECK(partition->get_navigation_route_cells(global_at(1, 1), global_at(2, 2), 257).is_empty());
	ERR_PRINT_ON;
	CHECK(partition->get_navigation_route_cells(Vector3(std::numeric_limits<real_t>::quiet_NaN(), 0, 0), global_at(2, 2)).is_empty());
	CHECK(partition->get_navigation_route_cells(global_at(2, 2), Vector3(std::numeric_limits<real_t>::infinity(), 0, 0)).is_empty());
	CHECK_FALSE(partition->is_navigation_route_ready(global_at(2, 9), global_at(70, 9)));
	CHECK(partition->get_streamed_navigation_path(global_at(2, 9), global_at(70, 9)).is_empty());

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Instantiated cells without navigation remain nav-unready") {
	// A physics-ready PackedScene is NOT sufficient for NavigationServer3D
	// readiness. Every navigation-ready cell must have a real region RID with
	// synced polygon data; unregistered geometry must not be reported ready.
	Node3D *template_root = memnew(Node3D);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(template_root) == OK);
	memdelete(template_root);
	const String path = "user://world_partition_nav_negative_doctest_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	REQUIRE(ResourceSaver::save(packed, path) == OK);

	Node3D *observer = memnew(Node3D);
	observer->set_name("NavObserver");
	WorldPartition3D *partition = memnew(WorldPartition3D);
	SceneTree::get_singleton()->get_root()->add_child(observer);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_load_radius(0);
	partition->set_unload_radius(0);
	partition->set_cell_size(16.0);
	partition->set_observer_path(partition->get_path_to(observer));
	partition->set_cell_scene(Vector2i(), path);
	CHECK(partition->set_streaming_source("nav_test", Vector2i(), 0, 0, 80));
	CHECK(partition->has_signal(SNAME("cell_navigation_ready")));
	CHECK(partition->has_signal(SNAME("cell_navigation_unready")));
	CHECK(partition->get_navigation_pending_cell_count() == 0);
	CHECK_FALSE(partition->is_cell_navigation_ready(Vector2i()));
	CHECK_FALSE(partition->is_streaming_source_navigation_ready("nav_test"));
	CHECK(partition->get_streaming_source_navigation_progress("nav_test") == 0.0);

	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i()); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i()));
	SceneTree::get_singleton()->physics_process(1.0 / 60.0);
	SceneTree::get_singleton()->physics_process(1.0 / 60.0);
	CHECK(partition->is_cell_physics_ready(Vector2i()));
	CHECK(partition->get_navigation_ready_cell_count() == 0);
	CHECK(partition->get_navigation_pending_cell_count() == 0);
	CHECK_FALSE(partition->is_cell_navigation_ready(Vector2i()));
	CHECK_FALSE(partition->are_cells_navigation_ready(Vector2i()));
	CHECK_FALSE(partition->is_streaming_source_navigation_ready("nav_test"));
	CHECK(partition->get_streaming_source_navigation_progress("nav_test") == 0.0);

	observer->set_position(Vector3(256.0, 0.0, 0.0));
	partition->remove_streaming_source("nav_test");
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_navigation_ready(Vector2i()));
	CHECK(partition->get_navigation_ready_cell_count() == 0);

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(observer);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Physics activation barrier resets on unload and re-stream") {
	Node3D *template_root = memnew(Node3D);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(template_root) == OK);
	memdelete(template_root);
	const String path = "user://world_partition_physics_gate_doctest_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	REQUIRE(ResourceSaver::save(packed, path) == OK);

	Node3D *observer = memnew(Node3D);
	observer->set_name("PhysicsReadyObserver");
	WorldPartition3D *partition = memnew(WorldPartition3D);
	SceneTree::get_singleton()->get_root()->add_child(observer);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_cell_size(16);
	partition->set_load_radius(0);
	partition->set_unload_radius(0);
	partition->set_observer_path(partition->get_path_to(observer));
	partition->set_cell_scene(Vector2i(), path);
	CHECK(partition->has_signal(SNAME("cell_physics_ready")));
	CHECK(partition->has_signal(SNAME("cell_physics_unready")));

	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i()); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i()));
	CHECK_FALSE(partition->is_cell_physics_ready(Vector2i()));
	CHECK_FALSE(partition->are_cells_physics_ready(Vector2i()));
	CHECK(partition->get_physics_ready_cell_count() == 0);

	// Simulate actual SceneTree fixed physics processing. Instantiation is NOT
	// activation: at least one physics step must complete before the barrier.
	SceneTree::get_singleton()->physics_process(1.0 / 60.0);
	CHECK_FALSE(partition->is_cell_physics_ready(Vector2i()));
	SceneTree::get_singleton()->physics_process(1.0 / 60.0);
	CHECK(partition->is_cell_physics_ready(Vector2i()));
	CHECK(partition->are_cells_physics_ready(Vector2i(), 0));
	CHECK(partition->get_physics_ready_cell_count() == 1);
	CHECK_FALSE(partition->are_cells_physics_ready(Vector2i(), 1));
	CHECK_FALSE(partition->is_cell_physics_ready(Vector2i(100, 100)));

	observer->set_position(Vector3(64, 0, 0));
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i()));
	CHECK_FALSE(partition->is_cell_physics_ready(Vector2i()));
	CHECK(partition->get_physics_ready_cell_count() == 0);

	observer->set_position(Vector3());
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i()); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i()));
	CHECK_FALSE(partition->is_cell_physics_ready(Vector2i())); // No stale ready state.
	SceneTree::get_singleton()->physics_process(1.0 / 60.0);
	SceneTree::get_singleton()->physics_process(1.0 / 60.0);
	CHECK(partition->is_cell_physics_ready(Vector2i()));

	partition->set_streaming_enabled(false);
	CHECK(partition->get_physics_ready_cell_count() == 0);
	CHECK_FALSE(partition->is_cell_physics_ready(Vector2i()));

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(observer);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Observer cell follows motion and grid changes") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	Node3D *observer = memnew(Node3D);
	observer->set_name("Observer");
	SceneTree::get_singleton()->get_root()->add_child(partition);
	SceneTree::get_singleton()->get_root()->add_child(observer);

	partition->set_cell_size(16.0);
	CHECK_FALSE(partition->has_observer_cell());
	partition->set_observer_path(partition->get_path_to(observer));
	partition->update_streaming();
	CHECK(partition->has_observer_cell());
	CHECK(partition->get_observer_cell() == Vector2i(0, 0));
	CHECK(partition->has_signal(SNAME("observer_cell_changed")));

	observer->set_position(Vector3(-17, 20, 33));
	partition->update_streaming();
	CHECK(partition->get_observer_cell() == Vector2i(-2, 2));

	partition->set_cell_size(32.0);
	CHECK_FALSE(partition->has_observer_cell());
	partition->update_streaming();
	CHECK(partition->get_observer_cell() == Vector2i(-1, 1));

	partition->set_observer_path(NodePath());
	CHECK_FALSE(partition->has_observer_cell());

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(observer);
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
	partition->set_prefetch_direction(Vector2i(2, 0));
	partition->set_prefetch_direction(Vector2i(0, -2));
	partition->set_prefetch_distance(-1);
	partition->set_prefetch_distance(5);
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
	Node3D *authored_child = memnew(Node3D);
	partition->add_child(authored_child);

	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(0, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	CHECK(partition->is_cell_loaded(Vector2i(0, 0)));
	CHECK(partition->get_cell_node(Vector2i(0, 0)) != nullptr);
	CHECK(partition->get_cell_node(Vector2i(100, 100)) == nullptr);
	CHECK(partition->are_cells_loaded(Vector2i(0, 0)));
	CHECK_FALSE(partition->are_cells_loaded(Vector2i(0, 0), 1));
	CHECK(partition->get_loaded_cell_count() == 1);
	CHECK(partition->get_child_count() == 2);
	Node *streamed_child = partition->get_child(1);
	CHECK(streamed_child != authored_child);

	// Hysteresis: do not unload a cell when it has left the load radius
	// but is still within the larger unload radius.
	observer->set_position(Vector3(16, 0, 0));
	partition->update_streaming();
	CHECK(partition->is_cell_loaded(Vector2i(0, 0)));
	CHECK(partition->get_loaded_cell_count() == 1);

	observer->set_position(Vector3(64, 0, 0));
	partition->update_streaming();
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(0, 0)));
	CHECK(partition->get_cell_node(Vector2i(0, 0)) == nullptr);
	CHECK(partition->get_loaded_cell_count() == 0);
	// queue_free() defers removal until the end of the frame.
	CHECK(streamed_child->is_queued_for_deletion());
	CHECK_FALSE(authored_child->is_queued_for_deletion());
	CHECK(authored_child->get_parent() == partition);

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(observer);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Directional corridor prefetch prioritizes observer and unloads stale cells") {
	Node3D *template_root = memnew(Node3D);
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(template_root) == OK);
	memdelete(template_root);

	const String path = "user://world_partition_prefetch_doctest_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	REQUIRE(ResourceSaver::save(packed, path) == OK);

	WorldPartition3D *partition = memnew(WorldPartition3D);
	Node3D *observer = memnew(Node3D);
	observer->set_name("PrefetchObserver");
	SceneTree::get_singleton()->get_root()->add_child(observer);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_cell_size(16);
	partition->set_load_radius(0);
	partition->set_unload_radius(0);
	partition->set_max_instances_per_frame(1);
	partition->set_prefetch_direction(Vector2i(1, 0));
	partition->set_prefetch_distance(2);
	partition->set_observer_path(partition->get_path_to(observer));
	for (int x = -2; x <= 2; x++) {
		partition->set_cell_scene(Vector2i(x, 0), path);
	}

	const Vector2i origin(0, 0);
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(origin); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(origin));
	// The first instantiation always serves the primary observer grid.
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(1, 0)));
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(2, 0)));

	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(2, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	CHECK(partition->is_cell_loaded(Vector2i(1, 0)));
	CHECK(partition->is_cell_loaded(Vector2i(2, 0)));
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(-1, 0)));
	CHECK(partition->get_loaded_cell_count() == 3);

	// Changing direction immediately makes previous prefetch cells eligible
	// for unloading, even though the player has not changed grid cells.
	partition->set_prefetch_direction(Vector2i(-1, 0));
	partition->update_streaming();
	CHECK(partition->is_cell_loaded(origin));
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(1, 0)));
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(2, 0)));
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(-2, 0)); i++) {
		partition->update_streaming();
		OS::get_singleton()->delay_usec(1000);
	}
	CHECK(partition->is_cell_loaded(Vector2i(-1, 0)));
	CHECK(partition->is_cell_loaded(Vector2i(-2, 0)));
	CHECK(partition->are_cells_loaded(origin));

	SceneTree::get_singleton()->get_root()->remove_child(partition);
	SceneTree::get_singleton()->get_root()->remove_child(observer);
	memdelete(partition);
	memdelete(observer);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Automatic streaming respects transforms and authored offsets") {
	Node3D *template_root = memnew(Node3D);
	template_root->set_position(Vector3(2, 3, 5));
	Ref<PackedScene> packed;
	packed.instantiate();
	REQUIRE(packed->pack(template_root) == OK);
	memdelete(template_root);

	const String path = "user://world_partition_transform_doctest_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	REQUIRE(ResourceSaver::save(packed, path) == OK);

	Node3D *parent = memnew(Node3D);
	WorldPartition3D *partition = memnew(WorldPartition3D);
	Node3D *observer = memnew(Node3D);
	observer->set_name("Observer");
	parent->add_child(partition);
	parent->add_child(observer);
	SceneTree::get_singleton()->get_root()->add_child(parent);

	partition->set_cell_size(16);
	partition->set_load_radius(0);
	partition->set_unload_radius(0);
	partition->set_position(Vector3(100, 0, 25));
	partition->set_rotation(Vector3(0, Math::PI / 2, 0));
	observer->set_global_position(partition->to_global(Vector3(20, 0, -4)));
	partition->set_observer_path(partition->get_path_to(observer));
	partition->set_cell_scene(Vector2i(1, -1), path);

	// Drive actual SceneTree processing, rather than calling update_streaming.
	for (int i = 0; i < 2000 && !partition->is_cell_loaded(Vector2i(1, -1)); i++) {
		SceneTree::get_singleton()->process(0);
		OS::get_singleton()->delay_usec(1000);
	}
	REQUIRE(partition->is_cell_loaded(Vector2i(1, -1)));
	REQUIRE_EQ(partition->get_child_count(), 1);
	Node3D *loaded = Object::cast_to<Node3D>(partition->get_child(0));
	REQUIRE(loaded != nullptr);
	CHECK(loaded->get_position().is_equal_approx(Vector3(18, 3, -11)));

	observer->set_global_position(partition->to_global(Vector3(64, 0, -4)));
	SceneTree::get_singleton()->process(0);
	CHECK_FALSE(partition->is_cell_loaded(Vector2i(1, -1)));
	CHECK_EQ(partition->get_loaded_cell_count(), 0);

	SceneTree::get_singleton()->get_root()->remove_child(parent);
	memdelete(parent);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

} // namespace TestWorldPartition3D
