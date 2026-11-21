/**************************************************************************/
/*  test_world_partition_3d_extra.h                                       */
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
#include "core/io/resource_loader.h"
#include "core/io/resource_saver.h"
#include "core/os/os.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "tests/test_macros.h"

#include <cstdint>
#include <limits>

namespace TestWorldPartition3DExtra {

struct WorldFixture {
	Node3D *observer = nullptr;
	WorldPartition3D *world = nullptr;

	WorldFixture() {
		observer = memnew(Node3D);
		observer->set_name("PartitionTestObserver");
		world = memnew(WorldPartition3D);
		SceneTree::get_singleton()->get_root()->add_child(observer);
		SceneTree::get_singleton()->get_root()->add_child(world);
		world->set_cell_size(16);
		world->set_load_radius(0);
		world->set_unload_radius(1);
		world->set_observer_path(world->get_path_to(observer));
	}

	~WorldFixture() {
		SceneTree::get_singleton()->get_root()->remove_child(world);
		SceneTree::get_singleton()->get_root()->remove_child(observer);
		memdelete(world);
		memdelete(observer);
	}
};

static String make_cell_scene(const String &p_id, const Vector3 &p_authored_offset = Vector3()) {
	Node3D *root = memnew(Node3D);
	root->set_name("AuthoredCell");
	root->set_position(p_authored_offset);
	Ref<PackedScene> packed;
	packed.instantiate();
	const Error pack_error = packed->pack(root);
	memdelete(root);
	CHECK(pack_error == OK);
	const String file_name = "user://partition_extra_" + p_id + "_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	CHECK(ResourceSaver::save(packed, file_name) == OK);
	return file_name;
}

static bool wait_for_cell(WorldPartition3D *p_world, const Vector2i &p_cell) {
	for (int i = 0; i < 2000; i++) {
		p_world->update_streaming();
		if (p_world->is_cell_loaded(p_cell)) {
			return true;
		}
		OS::get_singleton()->delay_usec(1000);
	}
	return false;
}

TEST_CASE("[WorldPartition3D] Negative fractional positions floor toward minus infinity") {
	WorldPartition3D world;
	world.set_cell_size(2.0);
	CHECK(world.local_position_to_cell(Vector3(-0.0001, 0, 0)) == Vector2i(-1, 0));
	CHECK(world.local_position_to_cell(Vector3(-1.999, 0, -1.999)) == Vector2i(-1, -1));
	CHECK(world.local_position_to_cell(Vector3(-2.0, 0, -2.0)) == Vector2i(-1, -1));
	CHECK(world.local_position_to_cell(Vector3(-2.0001, 0, -2.0001)) == Vector2i(-2, -2));
}

TEST_CASE("[WorldPartition3D] Fractional cell sizes remain consistent") {
	WorldPartition3D world;
	world.set_cell_size(0.25);
	CHECK(world.local_position_to_cell(Vector3(0.249, 0, -0.001)) == Vector2i(0, -1));
	CHECK(world.local_position_to_cell(Vector3(0.25, 0, -0.25)) == Vector2i(1, -1));
	CHECK(world.local_position_to_cell(Vector3(0.5, 0, -0.5)) == Vector2i(2, -2));
}

TEST_CASE("[WorldPartition3D] Very large finite positions do not overflow cell coordinates") {
	WorldPartition3D world;
	world.set_cell_size(1.0);
	CHECK(world.local_position_to_cell(Vector3(1.0e20, 0, 1.0e20)) == Vector2i(1000000000, 1000000000));
	CHECK(world.local_position_to_cell(Vector3(-1.0e20, 0, -1.0e20)) == Vector2i(-1000000000, -1000000000));
}

TEST_CASE("[WorldPartition3D] Nonfinite local positions are not interpreted as cells") {
	WorldPartition3D world;
	const real_t infinity = std::numeric_limits<real_t>::infinity();
	const real_t nan_value = std::numeric_limits<real_t>::quiet_NaN();
	CHECK(world.local_position_to_cell(Vector3(infinity, 0, 0)) == Vector2i());
	CHECK(world.local_position_to_cell(Vector3(0, nan_value, 0)) == Vector2i());
	CHECK(world.local_position_to_cell(Vector3(0, 0, -infinity)) == Vector2i());
}

TEST_CASE("[WorldPartition3D] Cell origins have zero elevation") {
	WorldPartition3D world;
	world.set_cell_size(7.5);
	CHECK(world.cell_to_local_position(Vector2i()) == Vector3());
	CHECK(world.cell_to_local_position(Vector2i(3, 4)) == Vector3(22.5, 0, 30));
	CHECK(world.cell_to_local_position(Vector2i(-3, -4)) == Vector3(-22.5, 0, -30));
}

TEST_CASE("[WorldPartition3D] Exact coordinates round-trip with varied cell sizes") {
	WorldPartition3D world;
	const real_t sizes[] = { 0.5, 1.0, 4.0, 32.0, 128.0 };
	for (real_t size : sizes) {
		world.set_cell_size(size);
		for (int x = -20; x <= 20; x++) {
			for (int y = -20; y <= 20; y++) {
				const Vector2i cell(x, y);
				CHECK(world.local_position_to_cell(world.cell_to_local_position(cell)) == cell);
			}
		}
	}
}

TEST_CASE("[WorldPartition3D] Radius three query has 49 distinct cells") {
	WorldPartition3D world;
	const Array cells = world.get_cells_in_radius(Vector2i(10, -10), 3);
	REQUIRE(cells.size() == 49);
	for (int x = 7; x <= 13; x++) {
		for (int z = -13; z <= -7; z++) {
			CHECK(cells.has(Vector2i(x, z)));
		}
	}
}

TEST_CASE("[WorldPartition3D] Radius four spans the full square") {
	WorldPartition3D world;
	const Array cells = world.get_cells_in_radius(Vector2i(-4, 6), 4);
	REQUIRE(cells.size() == 81);
	CHECK(cells.has(Vector2i(-8, 2)));
	CHECK(cells.has(Vector2i(0, 10)));
	CHECK(cells.has(Vector2i(-4, 6)));
	CHECK_FALSE(cells.has(Vector2i(-9, 6)));
	CHECK_FALSE(cells.has(Vector2i(-4, 11)));
}

TEST_CASE("[WorldPartition3D] Radius query orders cells by grid row") {
	WorldPartition3D world;
	const Array cells = world.get_cells_in_radius(Vector2i(2, 3), 1);
	REQUIRE(cells.size() == 9);
	CHECK(cells[0] == Vector2i(1, 2));
	CHECK(cells[1] == Vector2i(2, 2));
	CHECK(cells[2] == Vector2i(3, 2));
	CHECK(cells[4] == Vector2i(2, 3));
	CHECK(cells[8] == Vector2i(3, 4));
}

TEST_CASE("[WorldPartition3D] Bulk cells can be read back without data loss") {
	WorldPartition3D world;
	Dictionary mapping;
	for (int x = -4; x <= 4; x++) {
		for (int z = -4; z <= 4; z++) {
			mapping[Vector2i(x, z)] = "res://partition/" + itos(x) + "_" + itos(z) + ".tscn";
		}
	}
	world.set_cell_scenes(mapping);
	CHECK(world.get_configured_cell_count() == 81);
	CHECK(world.get_cell_scenes() == mapping);
}

TEST_CASE("[WorldPartition3D] Replacing bulk cell dictionary removes old cells") {
	WorldPartition3D world;
	world.set_cell_scene(Vector2i(0, 0), "res://old.tscn");
	world.set_cell_scene(Vector2i(1, 0), "res://other.tscn");
	Dictionary new_mapping;
	new_mapping[Vector2i(-2, 3)] = "res://new.tscn";
	world.set_cell_scenes(new_mapping);
	CHECK(world.get_configured_cell_count() == 1);
	CHECK(world.get_cell_scene(Vector2i(0, 0)).is_empty());
	CHECK(world.get_cell_scene(Vector2i(1, 0)).is_empty());
	CHECK(world.get_cell_scene(Vector2i(-2, 3)) == "res://new.tscn");
}

TEST_CASE("[WorldPartition3D] Reject radius query overflowing the positive grid boundary") {
	WorldPartition3D world;
	const int edge = std::numeric_limits<int32_t>::max();
	ERR_PRINT_OFF;
	const Array invalid = world.get_cells_in_radius(Vector2i(edge, 0), 1);
	ERR_PRINT_ON;
	CHECK(invalid.is_empty());
	const Array valid = world.get_cells_in_radius(Vector2i(edge - 1, 0), 1);
	REQUIRE(valid.size() == 9);
	CHECK(valid.has(Vector2i(edge, 1)));
}

TEST_CASE("[WorldPartition3D] Reject radius query overflowing the negative grid boundary") {
	WorldPartition3D world;
	const int edge = std::numeric_limits<int32_t>::min();
	ERR_PRINT_OFF;
	const Array invalid = world.get_cells_in_radius(Vector2i(0, edge), 1);
	ERR_PRINT_ON;
	CHECK(invalid.is_empty());
	const Array valid = world.get_cells_in_radius(Vector2i(0, edge + 1), 1);
	REQUIRE(valid.size() == 9);
	CHECK(valid.has(Vector2i(-1, edge)));
}

TEST_CASE("[WorldPartition3D] Zero-radius queries accept extreme grid coordinates") {
	WorldPartition3D world;
	const int max_value = std::numeric_limits<int32_t>::max();
	const int min_value = std::numeric_limits<int32_t>::min();
	const Array cells = world.get_cells_in_radius(Vector2i(min_value, max_value), 0);
	REQUIRE(cells.size() == 1);
	CHECK(cells[0] == Vector2i(min_value, max_value));
}

TEST_CASE("[WorldPartition3D] Invalid dictionaries do not erase valid entries") {
	WorldPartition3D world;
	Dictionary dict;
	dict[Vector2i(-1, -1)] = "res://keep.tscn";
	dict[Vector2i(2, 3)] = Vector3(1, 2, 3);
	dict[String("not a Vector2i")] = "res://bad.tscn";
	dict[10] = "res://bad2.tscn";
	world.set_cell_scenes(dict);
	CHECK(world.get_configured_cell_count() == 1);
	CHECK(world.get_cell_scene(Vector2i(-1, -1)) == "res://keep.tscn");
}

TEST_CASE("[WorldPartition3D] Clear is idempotent") {
	WorldPartition3D world;
	world.clear_cell_scenes();
	world.clear_cell_scenes();
	CHECK(world.get_configured_cell_count() == 0);
	world.set_cell_scene(Vector2i(1, 1), "res://x.tscn");
	world.clear_cell_scenes();
	world.clear_cell_scenes();
	CHECK(world.get_configured_cell_count() == 0);
}

TEST_CASE("[WorldPartition3D] Unregistering a nonexistent cell is harmless") {
	WorldPartition3D world;
	world.set_cell_scene(Vector2i(0, 0), "res://keep.tscn");
	world.remove_cell_scene(Vector2i(800, -900));
	CHECK(world.get_configured_cell_count() == 1);
	CHECK(world.get_cell_scene(Vector2i(0, 0)) == "res://keep.tscn");
}

TEST_CASE("[WorldPartition3D] Duplicate scene paths across cells are supported") {
	WorldPartition3D world;
	for (int i = 0; i < 64; i++) {
		world.set_cell_scene(Vector2i(i, -i), "res://shared.tscn");
	}
	CHECK(world.get_configured_cell_count() == 64);
	for (int i = 0; i < 64; i++) {
		CHECK(world.get_cell_scene(Vector2i(i, -i)) == "res://shared.tscn");
	}
}

TEST_CASE("[WorldPartition3D] Re-registering unchanged paths preserves the mapping") {
	WorldPartition3D world;
	world.set_cell_scene(Vector2i(5, -4), "res://unchanged.tscn");
	world.set_cell_scene(Vector2i(5, -4), "res://unchanged.tscn");
	world.set_cell_scene(Vector2i(5, -4), "res://unchanged.tscn");
	CHECK(world.get_configured_cell_count() == 1);
	CHECK(world.get_cell_scene(Vector2i(5, -4)) == "res://unchanged.tscn");
}

TEST_CASE("[WorldPartition3D] Radius bounds accept maximum supported values") {
	WorldPartition3D world;
	world.set_load_radius(32);
	world.set_unload_radius(64);
	CHECK(world.get_load_radius() == 32);
	CHECK(world.get_unload_radius() == 64);
	world.set_load_radius(0);
	world.set_unload_radius(0);
	CHECK(world.get_load_radius() == 0);
	CHECK(world.get_unload_radius() == 0);
}

TEST_CASE("[WorldPartition3D] All streaming budgets support their maximum") {
	WorldPartition3D world;
	world.set_max_new_requests_per_frame(128);
	world.set_max_instances_per_frame(128);
	world.set_max_concurrent_requests(128);
	CHECK(world.get_max_new_requests_per_frame() == 128);
	CHECK(world.get_max_instances_per_frame() == 128);
	CHECK(world.get_max_concurrent_requests() == 128);
}

TEST_CASE("[WorldPartition3D] Out of range streaming budgets keep previous values") {
	WorldPartition3D world;
	world.set_max_new_requests_per_frame(3);
	world.set_max_instances_per_frame(7);
	world.set_max_concurrent_requests(11);
	ERR_PRINT_OFF;
	world.set_max_new_requests_per_frame(-1);
	world.set_max_new_requests_per_frame(129);
	world.set_max_instances_per_frame(-1);
	world.set_max_instances_per_frame(129);
	world.set_max_concurrent_requests(-1);
	world.set_max_concurrent_requests(129);
	ERR_PRINT_ON;
	CHECK(world.get_max_new_requests_per_frame() == 3);
	CHECK(world.get_max_instances_per_frame() == 7);
	CHECK(world.get_max_concurrent_requests() == 11);
}

TEST_CASE("[WorldPartition3D] Invalid radii never break load-unload ordering") {
	WorldPartition3D world;
	world.set_load_radius(3);
	world.set_unload_radius(5);
	ERR_PRINT_OFF;
	world.set_unload_radius(2);
	world.set_load_radius(33);
	world.set_load_radius(-1);
	world.set_unload_radius(65);
	ERR_PRINT_ON;
	CHECK(world.get_load_radius() == 3);
	CHECK(world.get_unload_radius() == 5);
}

TEST_CASE("[WorldPartition3D] Invalid cell sizes leave configured cells untouched") {
	WorldPartition3D world;
	world.set_cell_scene(Vector2i(1, 1), "res://configured.tscn");
	world.set_cell_size(2);
	ERR_PRINT_OFF;
	world.set_cell_size(0);
	world.set_cell_size(-1);
	world.set_cell_size(std::numeric_limits<real_t>::quiet_NaN());
	ERR_PRINT_ON;
	CHECK(world.get_cell_size() == 2);
	CHECK(world.get_configured_cell_count() == 1);
}

TEST_CASE("[WorldPartition3D] Disabled streaming does not modify configured cells") {
	WorldPartition3D world;
	world.set_observer_path(NodePath("../AbsentObserver"));
	world.set_cell_scene(Vector2i(0, 0), "res://not-loaded.tscn");
	world.set_streaming_enabled(false);
	world.update_streaming();
	world.update_streaming();
	CHECK(world.get_configured_cell_count() == 1);
	CHECK_FALSE(world.is_cell_loaded(Vector2i(0, 0)));
	world.set_streaming_enabled(true);
	CHECK(world.get_configured_cell_count() == 1);
}

TEST_CASE("[WorldPartition3D] Repeated manual updates outside tree are harmless") {
	WorldPartition3D world;
	world.set_cell_scene(Vector2i(0, 0), "res://missing.tscn");
	for (int i = 0; i < 10; i++) {
		world.update_streaming();
	}
	CHECK(world.get_loaded_cell_count() == 0);
	CHECK(world.get_configured_cell_count() == 1);
}

TEST_CASE("[WorldPartition3D] Streaming signals are registered") {
	WorldPartition3D world;
	CHECK(world.has_signal(SNAME("cell_loaded")));
	CHECK(world.has_signal(SNAME("cell_unloaded")));
}

TEST_CASE("[SceneTree][WorldPartition3D] Authored transform is preserved in negative cells") {
	const String path = make_cell_scene("negative_offset", Vector3(2, 3, -4));
	{
		WorldFixture fixture;
		fixture.observer->set_position(Vector3(-32, 0, 48));
		fixture.world->set_cell_scene(Vector2i(-2, 3), path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(-2, 3)));
		REQUIRE(fixture.world->get_child_count() == 1);
		Node3D *loaded = Object::cast_to<Node3D>(fixture.world->get_child(0));
		REQUIRE(loaded != nullptr);
		CHECK(loaded->get_name() == "AuthoredCell");
		CHECK(loaded->get_position() == Vector3(-30, 3, 44));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Hysteresis delays unload until outer boundary") {
	const String path = make_cell_scene("hysteresis");
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		fixture.observer->set_position(Vector3(16, 0, 0));
		fixture.world->update_streaming();
		CHECK(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		fixture.observer->set_position(Vector3(32, 0, 0));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		CHECK(fixture.world->get_loaded_cell_count() == 0);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Disabling streaming unloads instances") {
	const String path = make_cell_scene("disable");
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		fixture.world->set_streaming_enabled(false);
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		CHECK(fixture.world->get_loaded_cell_count() == 0);
		CHECK(fixture.world->get_configured_cell_count() == 1);
		fixture.world->set_streaming_enabled(true);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		CHECK(fixture.world->get_loaded_cell_count() == 1);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Replacing a cell loads a different authored resource") {
	const String first_path = make_cell_scene("replacement_old", Vector3(1, 0, 0));
	const String second_path = make_cell_scene("replacement_new", Vector3(5, 0, 0));
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), first_path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		fixture.world->set_cell_scene(Vector2i(0, 0), second_path);
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		REQUIRE(fixture.world->get_child_count() >= 1);
		Node3D *inst = Object::cast_to<Node3D>(fixture.world->get_child(fixture.world->get_child_count() - 1));
		REQUIRE(inst != nullptr);
		CHECK(inst->get_position() == Vector3(5, 0, 0));
	}
	CHECK(DirAccess::remove_absolute(first_path) == OK);
	CHECK(DirAccess::remove_absolute(second_path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Observer position is measured in partition local space") {
	const String path = make_cell_scene("translated_partition", Vector3(1, 0, -2));
	{
		WorldFixture fixture;
		fixture.world->set_position(Vector3(100, 0, 50));
		fixture.observer->set_position(Vector3(84, 0, 34));
		fixture.world->set_cell_scene(Vector2i(-1, -1), path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(-1, -1)));
		REQUIRE(fixture.world->get_child_count() == 1);
		Node3D *inst = Object::cast_to<Node3D>(fixture.world->get_child(0));
		REQUIRE(inst != nullptr);
		CHECK(inst->get_position() == Vector3(-15, 0, -18));
		CHECK(inst->get_global_position() == Vector3(85, 0, 32));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] One background scene request serves multiple cells") {
	const String path = make_cell_scene("shared_resources");
	{
		WorldFixture fixture;
		fixture.world->set_load_radius(1);
		fixture.world->set_max_new_requests_per_frame(1);
		fixture.world->set_max_instances_per_frame(1);
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->set_cell_scene(Vector2i(1, 0), path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(1, 0)));
		CHECK(fixture.world->get_loaded_cell_count() == 2);
		CHECK(fixture.world->get_loaded_cells().has(Vector2i(0, 0)));
		CHECK(fixture.world->get_loaded_cells().has(Vector2i(1, 0)));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Destroying streamer collects in-flight user load token") {
	const String path = make_cell_scene("pending_destruction");
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->update_streaming();
		// Deliberately do not wait: the destructor must collect even an in-flight load.
	}
	CHECK(ResourceLoader::load_threaded_get_status(path) == ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Failed resources leave no user load tokens") {
	const String missing_path = "user://partition_missing_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), missing_path);
		ERR_PRINT_OFF;
		for (int i = 0; i < 100; i++) {
			fixture.world->update_streaming();
			if (ResourceLoader::load_threaded_get_status(missing_path) == ResourceLoader::THREAD_LOAD_INVALID_RESOURCE) {
				break;
			}
			OS::get_singleton()->delay_usec(1000);
		}
		ERR_PRINT_ON;
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
	}
	CHECK(ResourceLoader::load_threaded_get_status(missing_path) == ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
}

TEST_CASE("[SceneTree][WorldPartition3D] No observer prevents resource requests") {
	WorldFixture fixture;
	fixture.world->set_observer_path(NodePath("../NotAnObserver"));
	fixture.world->set_cell_scene(Vector2i(0, 0), "res://missing-do-not-request.tscn");
	fixture.world->update_streaming();
	CHECK(fixture.world->get_loaded_cell_count() == 0);
	CHECK(fixture.world->get_configured_cell_count() == 1);
}

} // namespace TestWorldPartition3DExtra
