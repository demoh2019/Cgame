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
#include "scene/3d/physics/rigid_body_3d.h"
#include "scene/3d/navigation/navigation_region_3d.h"
#include "scene/main/window.h"
#include "tests/test_macros.h"

#include <cstdint>
#include <limits>

namespace TestWorldPartition3DExtra {

TEST_CASE("[WorldPartition3D] Stateful child objects are opt-in and expose snapshot operations") {
	WorldPartition3D world;
	CHECK_FALSE(world.is_persisting_streaming_objects());
	CHECK(world.snapshot_cell_object_states().is_empty());
	CHECK(world.capture_cell_object_states(Vector2i(0, 0)).is_empty());
	CHECK(world.get_cell_object_state_count() == 0);
	CHECK(world.has_signal(SNAME("cell_object_state_changed")));
	world.set_persist_streaming_objects(true);
	CHECK(world.is_persisting_streaming_objects());
	world.set_persist_streaming_objects(false);
	CHECK_FALSE(world.is_persisting_streaming_objects());
}

TEST_CASE("[WorldPartition3D] Object import validates scene paths and serializable value types") {
	WorldPartition3D world;
	Dictionary valid_record;
	valid_record["active"] = true;
	valid_record["uses"] = 3;
	valid_record["caption"] = "opened";
	valid_record["offset"] = Vector3(1, 2, 3);
	Dictionary nested = valid_record.duplicate(true);
	nested["nested"] = Dictionary();
	Dictionary nonfinite = valid_record.duplicate(true);
	nonfinite["bad_float"] = std::numeric_limits<double>::infinity();
	Dictionary invalid_key = valid_record.duplicate(true);
	invalid_key[42] = true;
	Dictionary candidates;
	candidates["TreasureChest"] = valid_record;
	candidates["../External"] = valid_record;
	candidates["/root/External"] = valid_record;
	candidates["TreasureChest:active"] = valid_record;
	candidates["Nested"] = nested;
	candidates["Nonfinite"] = nonfinite;
	candidates["InvalidKey"] = invalid_key;
	candidates[123] = valid_record;
	Dictionary imported;
	imported[Vector2i(0, 0)] = candidates;
	imported["not a cell"] = candidates;
	world.load_cell_object_states(imported);
	CHECK(world.get_cell_object_state_count() == 1);
	const Dictionary result = world.get_cell_object_states(Vector2i(0, 0));
	REQUIRE(result.size() == 1);
	REQUIRE(result.has("TreasureChest"));
	const Dictionary record = result["TreasureChest"];
	CHECK(record["active"] == true);
	CHECK(record["uses"] == 3);
	world.clear_cell_object_states();
	CHECK(world.get_cell_object_state_count() == 0);
}

TEST_CASE("[WorldPartition3D] Stateful object snapshots are deep copies of imports") {
	WorldPartition3D world;
	Dictionary record;
	record["active"] = false;
	record["uses"] = 1;
	Dictionary nodes;
	nodes["ArenaSwitch"] = record;
	Dictionary cells;
	cells[Vector2i(4, 2)] = nodes;
	world.load_cell_object_states(cells);
	record["uses"] = 99;
	nodes["ArenaSwitch"] = Dictionary();
	cells.clear();
	Dictionary stored = world.get_cell_object_states(Vector2i(4, 2));
	const Dictionary again = stored["ArenaSwitch"];
	CHECK(again["uses"] == 1);
	stored.clear();
	const Dictionary after = world.snapshot_cell_object_states();
	REQUIRE(after.has(Vector2i(4, 2)));
	Dictionary cloned = after[Vector2i(4, 2)];
	Dictionary saved = cloned["ArenaSwitch"];
	saved["active"] = true;
	const Dictionary refreshed = world.get_cell_object_states(Vector2i(4, 2));
	const Dictionary original = refreshed["ArenaSwitch"];
	CHECK(original["active"] == false);
}

TEST_CASE("[WorldPartition3D] Stateful object import limits records per cell") {
	WorldPartition3D world;
	Dictionary valid;
	valid["active"] = true;
	Dictionary records;
	for (int i = 0; i < 150; i++) {
		records["Item_" + itos(i)] = valid;
	}
	Dictionary cells;
	cells[Vector2i(1, -1)] = records;
	world.load_cell_object_states(cells);
	CHECK(world.get_cell_object_states(Vector2i(1, -1)).size() == 128);
}

TEST_CASE("[WorldPartition3D] Rigid body snapshots are disabled unless explicitly opted in") {
	WorldPartition3D world;
	CHECK_FALSE(world.is_persisting_rigid_bodies());
	CHECK(world.snapshot_cell_physics_states().is_empty());
	CHECK(world.get_cell_physics_state(Vector2i(0, 0)).is_empty());
	world.set_persist_rigid_bodies(true);
	CHECK(world.is_persisting_rigid_bodies());
	world.set_persist_rigid_bodies(false);
	CHECK_FALSE(world.is_persisting_rigid_bodies());
}

TEST_CASE("[WorldPartition3D] Rigid body save import validates types finite values and paths") {
	WorldPartition3D world;
	Dictionary record;
	record["transform"] = Transform3D(Basis(), Vector3(3, 2, 1));
	record["linear_velocity"] = Vector3(2, 0, 0);
	record["angular_velocity"] = Vector3(0, 0, 1);
	record["sleeping"] = false;
	record["freeze"] = false;
	Dictionary bad_velocity = record.duplicate(true);
	bad_velocity["linear_velocity"] = Vector3(std::numeric_limits<real_t>::infinity(), 0, 0);
	Dictionary bad_missing = record.duplicate(true);
	bad_missing.erase("transform");
	Dictionary candidates;
	candidates["PersistentBox"] = record;
	candidates["../OutsideBody"] = record;
	candidates["/root/OtherBody"] = record;
	candidates["PersistentBox:linear_velocity"] = record;
	candidates["BadVelocity"] = bad_velocity;
	candidates["MissingTransform"] = bad_missing;
	candidates[Vector2i(99, 99)] = record;
	Dictionary raw;
	raw[Vector2i(1, 1)] = candidates;
	raw["wrong cell coordinate"] = candidates;
	world.load_cell_physics_states(raw);
	CHECK(world.get_cell_physics_state_count() == 1);
	Dictionary cached = world.get_cell_physics_state(Vector2i(1, 1));
	CHECK(cached.size() == 1);
	CHECK(cached.has("PersistentBox"));
	Dictionary saved = cached["PersistentBox"];
	CHECK(saved["linear_velocity"] == Vector3(2, 0, 0));
	saved["linear_velocity"] = Vector3(77, 0, 0);
	Dictionary again = world.get_cell_physics_state(Vector2i(1, 1));
	Dictionary body = again["PersistentBox"];
	CHECK(body["linear_velocity"] == Vector3(2, 0, 0));
	world.load_cell_physics_states(Dictionary());
	CHECK(world.get_cell_physics_state_count() == 0);
}

TEST_CASE("[SceneTree][WorldPartition3D] Persisted rigid-body transforms and velocities survive reload") {
	const String path = make_physics_cell_scene("transform_velocity_roundtrip");
	{
		WorldFixture fixture;
		fixture.world->set_persist_rigid_bodies(true);
		const Vector2i cell(0, 0);
		fixture.world->set_cell_scene(cell, path);
		REQUIRE(wait_for_cell(fixture.world, cell));
		Node3D *root = fixture.world->get_cell_instance(cell);
		REQUIRE(root != nullptr);
		RigidBody3D *box = Object::cast_to<RigidBody3D>(root->get_node_or_null(NodePath("PersistentBox")));
		REQUIRE(box != nullptr);
		box->set_position(Vector3(11, 5, 13));
		box->set_linear_velocity(Vector3(1, 2, 3));
		box->set_angular_velocity(Vector3(0, 1, 0));
		const Dictionary snapshot = fixture.world->snapshot_cell_physics_states();
		REQUIRE(snapshot.has(cell));
		const Dictionary box_states = snapshot[cell];
		REQUIRE(box_states.has("PersistentBox"));
		CHECK_FALSE(box_states.has("UnmarkedBox"));
		CHECK(box_states.size() == 1);
		const Dictionary record = box_states["PersistentBox"];
		CHECK(record["linear_velocity"] == Vector3(1, 2, 3));
		CHECK(record["angular_velocity"] == Vector3(0, 1, 0));
		const Transform3D transform = record["transform"];
		CHECK(transform.origin == Vector3(11, 5, 13));
		fixture.observer->set_position(Vector3(1280, 0, 0));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(cell));
		CHECK(fixture.world->get_cell_physics_state_count() == 1);
		fixture.observer->set_position(Vector3(0, 0, 0));
		REQUIRE(wait_for_cell(fixture.world, cell));
		Node3D *again_root = fixture.world->get_cell_instance(cell);
		REQUIRE(again_root != nullptr);
		RigidBody3D *again = Object::cast_to<RigidBody3D>(again_root->get_node_or_null(NodePath("PersistentBox")));
		REQUIRE(again != nullptr);
		CHECK(again->get_position() == Vector3(11, 5, 13));
		CHECK(again->get_linear_velocity() == Vector3(1, 2, 3));
		CHECK(again->get_angular_velocity() == Vector3(0, 1, 0));
		fixture.world->clear_cell_physics_states();
		CHECK(fixture.world->get_cell_physics_state_count() == 0);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Bulk physics snapshot applies to loaded opted-in body") {
	const String path = make_physics_cell_scene("active_import");
	{
		WorldFixture fixture;
		fixture.world->set_persist_rigid_bodies(true);
		const Vector2i cell(0, 0);
		fixture.world->set_cell_scene(cell, path);
		REQUIRE(wait_for_cell(fixture.world, cell));
		Node3D *root = fixture.world->get_cell_instance(cell);
		REQUIRE(root != nullptr);
		RigidBody3D *body = Object::cast_to<RigidBody3D>(root->get_node_or_null(NodePath("PersistentBox")));
		REQUIRE(body != nullptr);
		Dictionary record;
		record["transform"] = Transform3D(Basis(), Vector3(21, 8, 5));
		record["linear_velocity"] = Vector3(0, 4, 0);
		record["angular_velocity"] = Vector3(0, 0, 0.5);
		record["sleeping"] = true;
		record["freeze"] = true;
		Dictionary cell_records;
		cell_records["PersistentBox"] = record;
		Dictionary import;
		import[cell] = cell_records;
		fixture.world->load_cell_physics_states(import);
		CHECK(body->get_position() == Vector3(21, 8, 5));
		CHECK(body->is_freeze_enabled());
		CHECK(body->is_sleeping());
		Dictionary saved = fixture.world->get_cell_physics_state(cell);
		CHECK(saved.size() == 1);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[WorldPartition3D] Navigation gates default to enabled and normalize saved state") {
	WorldPartition3D world;
	CHECK(world.is_cell_navigation_enabled(Vector2i(4, 1)));
	world.set_cell_navigation_enabled(Vector2i(4, 1), true);
	CHECK(world.get_disabled_navigation_cell_count() == 0);
	world.set_cell_navigation_enabled(Vector2i(4, 1), false);
	CHECK_FALSE(world.is_cell_navigation_enabled(Vector2i(4, 1)));
	CHECK(world.get_disabled_navigation_cell_count() == 1);
	Dictionary input;
	input[Vector2i(1, 0)] = false;
	input[Vector2i(2, 0)] = true;
	input[Vector2i(3, 0)] = "not a bool";
	input["not a cell"] = false;
	world.set_navigation_cell_states(input);
	CHECK(world.get_disabled_navigation_cell_count() == 1);
	CHECK_FALSE(world.is_cell_navigation_enabled(Vector2i(1, 0)));
	CHECK(world.is_cell_navigation_enabled(Vector2i(4, 1)));
	CHECK(world.is_cell_navigation_enabled(Vector2i(2, 0)));
	Dictionary isolated = world.get_navigation_cell_states();
	isolated[Vector2i(1, 0)] = true;
	CHECK_FALSE(world.is_cell_navigation_enabled(Vector2i(1, 0)));
	world.set_navigation_cell_states(Dictionary());
	CHECK(world.is_cell_navigation_enabled(Vector2i(1, 0)));
	CHECK(world.get_disabled_navigation_cell_count() == 0);
}

TEST_CASE("[WorldPartition3D] Navigation gates prevent atomic route reservations") {
	WorldPartition3D world;
	world.set_cell_navigation_enabled(Vector2i(1, 0), false);
	const Array path = world.get_cell_route(Vector2i(0, 0), Vector2i(2, 0));
	CHECK(path.size() == 3); // Map geometry is still inspectable.
	CHECK(world.acquire_cell_route(Vector2i(0, 0), Vector2i(2, 0)).is_empty());
	CHECK(world.get_cell_lease_count_total() == 0);
	world.set_cell_navigation_enabled(Vector2i(1, 0), true);
	const Array tokens = world.acquire_cell_route(Vector2i(0, 0), Vector2i(2, 0));
	REQUIRE(tokens.size() == 3);
	world.set_cell_navigation_enabled(Vector2i(1, 0), false);
	CHECK(world.get_cell_lease_count_total() == 3); // Existing owners stay valid.
	CHECK(world.release_cell_route(tokens) == 3);
	CHECK(world.get_cell_lease_count_total() == 0);
}

TEST_CASE("[WorldPartition3D] Navigation gate signal exists and bulk import keeps defaults") {
	WorldPartition3D world;
	CHECK(world.has_signal(SNAME("cell_navigation_state_changed")));
	CHECK(world.is_cell_navigation_enabled(Vector2i(-2, -1)));
	Dictionary stored;
	stored[Vector2i(-2, -1)] = false;
	world.set_navigation_cell_states(stored);
	CHECK_FALSE(world.is_cell_navigation_enabled(Vector2i(-2, -1)));
	world.set_cell_navigation_enabled(Vector2i(-2, -1), false);
	CHECK(world.get_navigation_cell_states().size() == 1);
	world.set_cell_navigation_enabled(Vector2i(-2, -1), true);
	CHECK(world.get_navigation_cell_states().is_empty());
}

TEST_CASE("[SceneTree][WorldPartition3D] Navigation gate disables loaded region and survives reload") {
	const String path = make_nav_gate_cell_scene("region_toggle");
	{
		WorldFixture fixture;
		const Vector2i cell(0, 0);
		fixture.world->set_cell_scene(cell, path);
		REQUIRE(wait_for_cell(fixture.world, cell));
		Node3D *root = fixture.world->get_cell_instance(cell);
		REQUIRE(root != nullptr);
		NavigationRegion3D *region = Object::cast_to<NavigationRegion3D>(root->get_node_or_null(NodePath("WalkableRegion")));
		REQUIRE(region != nullptr);
		CHECK(region->is_enabled());
		fixture.world->set_cell_navigation_enabled(cell, false);
		CHECK_FALSE(region->is_enabled());
		fixture.observer->set_position(Vector3(1280, 0, 0));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(cell));
		fixture.observer->set_position(Vector3(0, 0, 0));
		REQUIRE(wait_for_cell(fixture.world, cell));
		Node3D *reloaded = fixture.world->get_cell_instance(cell);
		REQUIRE(reloaded != nullptr);
		NavigationRegion3D *region_again = Object::cast_to<NavigationRegion3D>(reloaded->get_node_or_null(NodePath("WalkableRegion")));
		REQUIRE(region_again != nullptr);
		CHECK_FALSE(region_again->is_enabled());
		Dictionary imported;
		imported[cell] = false;
		fixture.world->set_navigation_cell_states(imported);
		CHECK_FALSE(region_again->is_enabled());
		fixture.world->set_navigation_cell_states(Dictionary());
		CHECK(region_again->is_enabled());
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[WorldPartition3D] Navigation corridor route includes edge-adjacent cells") {
	WorldPartition3D world;
	const Array route = world.get_cell_route(Vector2i(0, 0), Vector2i(3, 2));
	REQUIRE(route.size() == 6);
	CHECK(route[0] == Vector2i(0, 0));
	CHECK(route[5] == Vector2i(3, 2));
	for (int i = 1; i < route.size(); i++) {
		const Vector2i a = route[i - 1];
		const Vector2i b = route[i];
		const int dx = ABS(a.x - b.x);
		const int dz = ABS(a.y - b.y);
		CHECK(dx + dz == 1);
	}
	const Array reverse = world.get_cell_route(Vector2i(3, 2), Vector2i(0, 0));
	CHECK(reverse.size() == route.size());
	CHECK(world.get_cell_route(Vector2i(4, 9), Vector2i(4, 9)).size() == 1);
	const Array negatives = world.get_cell_route(Vector2i(-2, -3), Vector2i(-5, -3));
	CHECK(negatives.size() == 4);
	CHECK(negatives[3] == Vector2i(-5, -3));
}

TEST_CASE("[WorldPartition3D] Navigation corridor rejects oversized and extreme routes") {
	WorldPartition3D world;
	CHECK(world.get_cell_route(Vector2i(0, 0), Vector2i(63, 0)).size() == 64);
	ERR_PRINT_OFF;
	CHECK(world.get_cell_route(Vector2i(0, 0), Vector2i(64, 0)).is_empty());
	CHECK(world.get_cell_route(Vector2i(-1000000000, -1000000000), Vector2i(1000000000, 1000000000)).is_empty());
	ERR_PRINT_ON;
	CHECK(world.get_cell_lease_count_total() == 0);
}

TEST_CASE("[WorldPartition3D] Navigation corridor atomically acquires and releases cells") {
	WorldPartition3D world;
	Array route = world.get_cell_route(Vector2i(0, 0), Vector2i(2, 1));
	Array tokens = world.acquire_cell_route(Vector2i(0, 0), Vector2i(2, 1));
	REQUIRE(tokens.size() == route.size());
	CHECK(world.get_cell_lease_count_total() == tokens.size());
	for (int i = 0; i < route.size(); i++) {
		CHECK(world.get_cell_lease_count(route[i]) == 1);
	}
	Array second = world.acquire_cell_route(Vector2i(0, 0), Vector2i(2, 1));
	CHECK(second.size() == tokens.size());
	CHECK(world.get_cell_lease_count(Vector2i(0, 0)) == 2);
	CHECK(world.release_cell_route(tokens) == tokens.size());
	CHECK(world.get_cell_lease_count(Vector2i(0, 0)) == 1);
	CHECK(world.release_cell_route(tokens) == 0);
	CHECK(world.release_cell_route(second) == second.size());
	CHECK(world.get_cell_lease_count_total() == 0);
}

TEST_CASE("[WorldPartition3D] Navigation corridor disabled layer fails without claiming tokens") {
	WorldPartition3D world;
	world.set_cell_layer(Vector2i(1, 0), "locked");
	world.set_layer_enabled("locked", false);
	CHECK(world.acquire_cell_route(Vector2i(0, 0), Vector2i(3, 0)).is_empty());
	CHECK(world.get_cell_lease_count_total() == 0);
	world.set_layer_enabled("locked", true);
	Array tokens = world.acquire_cell_route(Vector2i(0, 0), Vector2i(3, 0));
	REQUIRE(tokens.size() == 4);
	CHECK(world.release_cell_route(tokens) == 4);
}

TEST_CASE("[WorldPartition3D] Navigation corridor respects token capacity atomically") {
	WorldPartition3D world;
	Vector<int> reserved;
	for (int i = 0; i < 254; i++) {
		const int token = world.acquire_cell_lease(Vector2i(i, 9));
		REQUIRE(token > 0);
		reserved.push_back(token);
	}
	ERR_PRINT_OFF;
	CHECK(world.acquire_cell_route(Vector2i(0, 0), Vector2i(3, 0)).is_empty());
	ERR_PRINT_ON;
	CHECK(world.get_cell_lease_count_total() == 254);
	Array tokens = world.acquire_cell_route(Vector2i(0, 0), Vector2i(1, 0));
	REQUIRE(tokens.size() == 2);
	CHECK(world.get_cell_lease_count_total() == 256);
	CHECK(world.release_cell_route(tokens) == 2);
	for (int token : reserved) {
		CHECK(world.release_cell_lease(token));
	}
	CHECK(world.get_cell_lease_count_total() == 0);
}

TEST_CASE("[SceneTree][WorldPartition3D] Navigation corridor streams a distant target with no observer") {
	const String path = make_cell_scene("corridor_prefetch");
	{
		WorldFixture fixture;
		fixture.world->set_observer_path(NodePath());
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->set_cell_scene(Vector2i(1, 0), path);
		fixture.world->set_max_new_requests_per_frame(1);
		const Array tokens = fixture.world->acquire_cell_route(Vector2i(0, 0), Vector2i(1, 0));
		REQUIRE(tokens.size() == 2);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(1, 0)));
		CHECK(fixture.world->release_cell_route(tokens) == 2);
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(1, 0)));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[WorldPartition3D] Simulation diagnostics for missing cells return zero counts") {
	WorldPartition3D world;
	const Dictionary counts = world.get_cell_simulation_stats(Vector2i(999, -999));
	CHECK(counts["collision_objects"] == 0);
	CHECK(counts["collision_shapes"] == 0);
	CHECK(counts["navigation_regions"] == 0);
}

TEST_CASE("[WorldPartition3D] Streaming lifecycle callbacks are registered as native signals") {
	WorldPartition3D world;
	CHECK(world.has_signal(SNAME("cell_activated")));
	CHECK(world.has_signal(SNAME("cell_deactivating")));
	CHECK(world.has_signal(SNAME("cell_loaded")));
	CHECK(world.has_signal(SNAME("cell_unloaded")));
}

TEST_CASE("[SceneTree][WorldPartition3D] Lifecycle and simulation statistics work with ordinary scenes") {
	const String path = make_cell_scene("simulation_lifecycle");
	{
		WorldFixture fixture;
		const Vector2i cell(0, 0);
		fixture.world->set_cell_scene(cell, path);
		REQUIRE(wait_for_cell(fixture.world, cell));
		const Dictionary counts = fixture.world->get_cell_simulation_stats(cell);
		CHECK(counts["collision_objects"] == 0);
		CHECK(counts["collision_shapes"] == 0);
		CHECK(counts["navigation_regions"] == 0);
		fixture.observer->set_position(Vector3(128, 0, 0));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(cell));
		const Dictionary unloaded = fixture.world->get_cell_simulation_stats(cell);
		CHECK(unloaded["collision_objects"] == 0);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[WorldPartition3D] Cell lease tokens isolate independent owners") {
	WorldPartition3D world;
	const Vector2i arena(4, 2);
	const int quest_token = world.acquire_cell_lease(arena);
	const int cinematic_token = world.acquire_cell_lease(arena);
	CHECK(quest_token > 0);
	CHECK(cinematic_token > 0);
	CHECK(quest_token != cinematic_token);
	CHECK(world.get_cell_lease_count(arena) == 2);
	CHECK(world.get_cell_lease_count_total() == 2);
	CHECK(world.get_leased_cell_count() == 1);
	CHECK(world.release_cell_lease(quest_token));
	CHECK_FALSE(world.release_cell_lease(quest_token));
	CHECK(world.get_cell_lease_count(arena) == 1);
	CHECK(world.get_cell_lease_count_total() == 1);
	CHECK(world.release_cell_lease(cinematic_token));
	CHECK(world.get_cell_lease_count(arena) == 0);
	CHECK(world.get_leased_cell_count() == 0);
}

TEST_CASE("[WorldPartition3D] Cell leases coexist with manual pins and clear independently") {
	WorldPartition3D world;
	const Vector2i hub(0, 0);
	world.pin_cell(hub);
	const int token = world.acquire_cell_lease(hub);
	world.clear_pinned_cells();
	CHECK_FALSE(world.is_cell_pinned(hub));
	CHECK(world.get_cell_lease_count(hub) == 1);
	world.pin_cell(hub);
	world.clear_cell_leases();
	CHECK(world.is_cell_pinned(hub));
	CHECK(world.get_cell_lease_count_total() == 0);
	CHECK_FALSE(world.release_cell_lease(token));
	world.unpin_cell(hub);
	CHECK(world.get_pinned_cell_count() == 0);
}

TEST_CASE("[WorldPartition3D] Lease token cap is guarded without losing existing owners") {
	WorldPartition3D world;
	Vector<int> tokens;
	for (int i = 0; i < 256; i++) {
		const int token = world.acquire_cell_lease(Vector2i(i, 0));
		REQUIRE(token > 0);
		tokens.push_back(token);
	}
	ERR_PRINT_OFF;
	CHECK(world.acquire_cell_lease(Vector2i(999, 0)) == 0);
	ERR_PRINT_ON;
	CHECK(world.get_cell_lease_count_total() == 256);
	CHECK(world.get_cell_lease_count(Vector2i(999, 0)) == 0);
	CHECK(world.release_cell_lease(tokens[0]));
	const int new_token = world.acquire_cell_lease(Vector2i(999, 0));
	CHECK(new_token > 0);
	CHECK(new_token != tokens[0]);
	CHECK(world.get_cell_lease_count_total() == 256);
}

TEST_CASE("[SceneTree][WorldPartition3D] Two leases retain distant cell until both release") {
	const String path = make_cell_scene("lease_two_systems");
	{
		WorldFixture fixture;
		const Vector2i arena(5, -2);
		fixture.world->set_cell_scene(arena, path);
		fixture.world->set_observer_path(NodePath());
		const int quest = fixture.world->acquire_cell_lease(arena);
		const int cutscene = fixture.world->acquire_cell_lease(arena);
		REQUIRE(wait_for_cell(fixture.world, arena));
		CHECK(fixture.world->release_cell_lease(quest));
		fixture.world->update_streaming();
		CHECK(fixture.world->is_cell_loaded(arena));
		CHECK(fixture.world->release_cell_lease(cutscene));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(arena));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Releasing manual pin does not override independent lease") {
	const String path = make_cell_scene("lease_survives_pin_release");
	{
		WorldFixture fixture;
		const Vector2i cell(7, -3);
		fixture.world->set_cell_scene(cell, path);
		fixture.world->set_observer_path(NodePath());
		fixture.world->pin_cell(cell);
		const int lease = fixture.world->acquire_cell_lease(cell);
		REQUIRE(lease > 0);
		REQUIRE(wait_for_cell(fixture.world, cell));
		fixture.world->unpin_cell(cell);
		fixture.world->update_streaming();
		CHECK(fixture.world->is_cell_loaded(cell));
		CHECK(fixture.world->get_cell_lease_count(cell) == 1);
		CHECK(fixture.world->release_cell_lease(lease));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(cell));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Data Layer deactivation overrides leased cells") {
	const String path = make_cell_scene("lease_layer_gate");
	{
		WorldFixture fixture;
		const Vector2i arena(0, 0);
		fixture.world->set_cell_scene(arena, path);
		fixture.world->set_cell_layer(arena, "combat");
		const int lease = fixture.world->acquire_cell_lease(arena);
		REQUIRE(wait_for_cell(fixture.world, arena));
		fixture.world->set_layer_enabled("combat", false);
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(arena));
		CHECK(fixture.world->get_cell_lease_count(arena) == 1);
		fixture.world->set_layer_enabled("combat", true);
		REQUIRE(wait_for_cell(fixture.world, arena));
		CHECK(fixture.world->release_cell_lease(lease));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Lease request uses global streaming request budget") {
	const String near_path = make_cell_scene("lease_budget_near");
	const String leased_path = make_cell_scene("lease_budget_far");
	{
		WorldFixture fixture;
		fixture.world->set_max_new_requests_per_frame(1);
		fixture.world->set_cell_scene(Vector2i(0, 0), near_path);
		fixture.world->set_cell_scene(Vector2i(5, 0), leased_path);
		fixture.world->acquire_cell_lease(Vector2i(5, 0));
		fixture.world->update_streaming();
		CHECK(ResourceLoader::load_threaded_get_status(leased_path) != ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
		CHECK(ResourceLoader::load_threaded_get_status(near_path) == ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(5, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
	}
	CHECK(DirAccess::remove_absolute(near_path) == OK);
	CHECK(DirAccess::remove_absolute(leased_path) == OK);
}

TEST_CASE("[WorldPartition3D] Reactive world signals are exposed to scripts") {
	WorldPartition3D world;
	CHECK(world.has_signal(SNAME("cell_state_changed")));
	CHECK(world.has_signal(SNAME("layer_state_changed")));
	CHECK(world.has_signal(SNAME("cell_loaded")));
	CHECK(world.has_signal(SNAME("cell_unloaded")));
}

TEST_CASE("[WorldPartition3D] Layer events retain default enabled semantics") {
	WorldPartition3D world;
	CHECK(world.is_layer_enabled("quest"));
	world.set_layer_enabled("quest", true);
	CHECK(world.is_layer_enabled("quest"));
	world.set_layer_enabled("quest", false);
	CHECK_FALSE(world.is_layer_enabled("quest"));
	world.set_layer_enabled("quest", false);
	CHECK_FALSE(world.is_layer_enabled("quest"));
	Dictionary imported;
	imported["quest"] = false;
	imported["arena"] = true;
	world.set_layer_states(imported);
	CHECK_FALSE(world.is_layer_enabled("quest"));
	CHECK(world.is_layer_enabled("arena"));
	world.set_layer_states(Dictionary());
	CHECK(world.is_layer_enabled("quest"));
}

TEST_CASE("[WorldPartition3D] Layer dictionaries normalize keys and protect getters") {
	WorldPartition3D world;
	Dictionary membership;
	membership[Vector2i(0, 0)] = "hub";
	membership[Vector2i(0, 0)] = "hub";
	membership[Vector2i(4, 2)] = "combat";
	membership[String("invalid")] = "combat";
	membership[Vector2i(3, 2)] = 42;
	world.set_cell_layers(membership);
	CHECK(world.get_cell_layers().size() == 2);
	CHECK(world.get_cell_layer(Vector2i(4, 2)) == "combat");
	Dictionary copy = world.get_cell_layers();
	copy.clear();
	CHECK(world.get_cell_layers().size() == 2);
	CHECK(world.is_cell_layer_enabled(Vector2i(4, 2)));
	Dictionary states;
	states["combat"] = false;
	states["hub"] = true;
	states[Vector2i(0, 0)] = false;
	states["bad"] = String("not boolean");
	world.set_layer_states(states);
	CHECK(world.get_layer_states().size() == 2);
	CHECK_FALSE(world.is_cell_layer_enabled(Vector2i(4, 2)));
	CHECK(world.is_cell_layer_enabled(Vector2i(0, 0)));
	CHECK(world.is_cell_layer_enabled(Vector2i(15, 15)));
	Dictionary state_copy = world.get_layer_states();
	state_copy.clear();
	CHECK(world.get_layer_states().size() == 2);
	world.set_cell_layer(Vector2i(3, 2), "combat");
	CHECK_FALSE(world.is_cell_layer_enabled(Vector2i(3, 2)));
	world.clear_cell_layer(Vector2i(3, 2));
	CHECK(world.is_cell_layer_enabled(Vector2i(3, 2)));
	world.set_layer_enabled("combat", true);
	CHECK(world.is_layer_enabled("combat"));
	world.set_layer_states(Dictionary());
	CHECK(world.is_cell_layer_enabled(Vector2i(4, 2)));
}

TEST_CASE("[SceneTree][WorldPartition3D] Disabled layer prevents pinned load and preserves pin") {
	const String path = make_cell_scene("layer_pin_gate");
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->set_cell_layer(Vector2i(0, 0), "combat");
		fixture.world->pin_cell(Vector2i(0, 0));
		fixture.world->set_layer_enabled("combat", false);
		for (int i = 0; i < 3; i++) {
			fixture.world->update_streaming();
		}
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		CHECK(fixture.world->is_cell_pinned(Vector2i(0, 0)));
		fixture.world->set_layer_enabled("combat", true);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		fixture.world->set_layer_enabled("combat", false);
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		CHECK(fixture.world->is_cell_pinned(Vector2i(0, 0)));
		fixture.world->clear_cell_layer(Vector2i(0, 0));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Layer deactivates without any observer and avoids unrelated unload") {
	const String path = make_cell_scene("layer_without_observer");
	{
		WorldFixture fixture;
		fixture.world->set_load_radius(1);
		fixture.world->set_unload_radius(2);
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->set_cell_scene(Vector2i(1, 0), path);
		fixture.world->set_cell_layer(Vector2i(0, 0), "mission");
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(1, 0)));
		fixture.world->set_observer_path(NodePath());
		fixture.world->set_layer_enabled("mission", false);
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		CHECK(fixture.world->is_cell_loaded(Vector2i(1, 0)));
		fixture.world->set_layer_enabled("mission", true);
		fixture.world->pin_cell(Vector2i(0, 0));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[WorldPartition3D] Cell state setters and getters isolate nested dictionaries") {
	WorldPartition3D world;
	Dictionary nested;
	nested["claimed"] = false;
	Dictionary initial;
	initial["quest"] = nested;
	world.set_cell_state(Vector2i(2, -3), initial);
	CHECK(world.has_cell_state(Vector2i(2, -3)));
	CHECK(world.get_cell_state_count() == 1);

	// Caller changes never mutate the streamer's saved copy.
	nested["claimed"] = true;
	Dictionary saved = world.get_cell_state(Vector2i(2, -3));
	Dictionary saved_quest = saved["quest"];
	CHECK(saved_quest["claimed"] == false);
	saved_quest["claimed"] = true;
	Dictionary again = world.get_cell_state(Vector2i(2, -3));
	Dictionary restored_quest = again["quest"];
	CHECK(restored_quest["claimed"] == false);

	world.set_cell_state(Vector2i(2, -3), Dictionary());
	CHECK_FALSE(world.has_cell_state(Vector2i(2, -3)));
	CHECK(world.get_cell_state(Vector2i(99, 99)).is_empty());
	CHECK(world.get_cell_state_count() == 0);
}

TEST_CASE("[WorldPartition3D] Snapshots transfer cell state and reject unsupported entries") {
	WorldPartition3D source;
	Dictionary hub;
	hub["reward_claimed"] = true;
	hub["visits"] = 7;
	source.set_cell_state(Vector2i(0, 0), hub);
	Dictionary arena;
	arena["wins"] = 3;
	source.set_cell_state(Vector2i(4, 2), arena);
	Dictionary snapshot = source.snapshot_cell_states();
	CHECK(snapshot.size() == 2);
	Dictionary invalid;
	invalid["bad string key"] = arena;
	invalid[Vector2i(10, 10)] = String("not a dictionary");
	invalid[Vector2i(0, 0)] = snapshot[Vector2i(0, 0)];
	invalid[Vector2i(4, 2)] = snapshot[Vector2i(4, 2)];
	WorldPartition3D destination;
	destination.load_cell_states(invalid);
	CHECK(destination.get_cell_state_count() == 2);
	CHECK(destination.get_cell_state(Vector2i(0, 0))["reward_claimed"] == true);
	CHECK(destination.get_cell_state(Vector2i(4, 2))["wins"] == 3);
	invalid.clear();
	CHECK(destination.get_cell_state_count() == 2);
	destination.load_cell_states(Dictionary());
	CHECK(destination.get_cell_state_count() == 0);
}

TEST_CASE("[WorldPartition3D] Cell data survives scene mapping removal and pin changes") {
	WorldPartition3D world;
	const Vector2i hub(0, 0);
	Dictionary state;
	state["unlocked"] = true;
	world.set_cell_scene(hub, "res://test_scene.tscn");
	world.pin_cell(hub);
	world.set_cell_state(hub, state);
	world.remove_cell_scene(hub);
	CHECK(world.has_cell_state(hub));
	CHECK(world.is_cell_pinned(hub));
	world.unpin_cell(hub);
	world.erase_cell_state(hub);
	CHECK_FALSE(world.has_cell_state(hub));
	world.set_cell_state(Vector2i(3, 3), state);
	world.set_cell_state(Vector2i(4, 4), state);
	world.clear_cell_states();
	CHECK(world.get_cell_state_count() == 0);
}

TEST_CASE("[WorldPartition3D] Inspector pinned cell array filters duplicates and invalid values") {
	WorldPartition3D world;
	Array cells;
	cells.push_back(Vector2i(3, -1));
	cells.push_back(Vector2i(3, -1));
	cells.push_back(String("not a cell"));
	cells.push_back(Vector2i(0, 0));
	world.set_pinned_cells(cells);
	CHECK(world.get_pinned_cell_count() == 2);
	const Array normalized = world.get_pinned_cells();
	REQUIRE(normalized.size() == 2);
	CHECK(normalized[0] == Vector2i(3, -1));
	CHECK(normalized[1] == Vector2i(0, 0));
	Array oversized;
	for (int i = 0; i < 129; i++) {
		oversized.push_back(Vector2i(i, 0));
	}
	ERR_PRINT_OFF;
	world.set_pinned_cells(oversized);
	ERR_PRINT_ON;
	CHECK(world.get_pinned_cell_count() == 2);
	world.set_pinned_cells(Array());
	CHECK(world.get_pinned_cell_count() == 0);
}

TEST_CASE("[WorldPartition3D] Pinned cells are unique, ordered and capped") {
	WorldPartition3D world;
	CHECK(world.get_pinned_cell_count() == 0);
	world.pin_cell(Vector2i(5, -2));
	world.pin_cell(Vector2i(5, -2));
	world.pin_cell(Vector2i(-1, 0));
	CHECK(world.get_pinned_cell_count() == 2);
	const Array pinned = world.get_pinned_cells();
	REQUIRE(pinned.size() == 2);
	CHECK(pinned[0] == Vector2i(5, -2));
	CHECK(pinned[1] == Vector2i(-1, 0));
	Array copy = pinned;
	copy.clear();
	CHECK(world.get_pinned_cell_count() == 2);
	CHECK(world.is_cell_pinned(Vector2i(5, -2)));
	world.unpin_cell(Vector2i(5, -2));
	world.unpin_cell(Vector2i(5, -2));
	CHECK_FALSE(world.is_cell_pinned(Vector2i(5, -2)));
	world.clear_pinned_cells();
	CHECK(world.get_pinned_cell_count() == 0);
	for (int i = 0; i < 128; i++) {
		world.pin_cell(Vector2i(i, 0));
	}
	ERR_PRINT_OFF;
	world.pin_cell(Vector2i(999, 0));
	ERR_PRINT_ON;
	CHECK(world.get_pinned_cell_count() == 128);
	CHECK_FALSE(world.is_cell_pinned(Vector2i(999, 0)));
}

TEST_CASE("[WorldPartition3D] Unload budget defaults and validates") {
	WorldPartition3D world;
	CHECK(world.get_max_unloads_per_frame() == 32);
	world.set_max_unloads_per_frame(7);
	CHECK(world.get_max_unloads_per_frame() == 7);
	ERR_PRINT_OFF;
	world.set_max_unloads_per_frame(0);
	world.set_max_unloads_per_frame(129);
	ERR_PRINT_ON;
	CHECK(world.get_max_unloads_per_frame() == 7);
}

TEST_CASE("[WorldPartition3D] Unloaded cells have no accessible scene instance") {
	WorldPartition3D world;
	world.set_cell_scene(Vector2i(7, -3), "res://unloaded.tscn");
	CHECK(world.get_cell_instance(Vector2i(7, -3)) == nullptr);
	CHECK(world.get_cell_instance(Vector2i(100, 100)) == nullptr);
	CHECK_FALSE(world.is_cell_loaded(Vector2i(7, -3)));
}

TEST_CASE("[WorldPartition3D] Additional observers are normalized and getter is defensive") {
	WorldPartition3D world;
	Array input;
	input.push_back(NodePath("../CameraA"));
	input.push_back(NodePath("../CameraA"));
	input.push_back(NodePath());
	input.push_back(String("../StringIsNotNodePath"));
	input.push_back(NodePath("../CameraB"));
	world.set_additional_observer_paths(input);
	const Array saved = world.get_additional_observer_paths();
	REQUIRE(saved.size() == 2);
	CHECK(saved[0] == NodePath("../CameraA"));
	CHECK(saved[1] == NodePath("../CameraB"));
	Array copy = saved;
	copy.clear();
	CHECK(world.get_additional_observer_paths().size() == 2);
	Array too_many;
	for (int i = 0; i < 17; i++) {
		too_many.push_back(NodePath("../Camera" + itos(i)));
	}
	ERR_PRINT_OFF;
	world.set_additional_observer_paths(too_many);
	ERR_PRINT_ON;
	CHECK(world.get_additional_observer_paths().size() == 2);
}


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

static String make_nav_gate_cell_scene(const String &p_id) {
	Node3D *root = memnew(Node3D);
	root->set_name("NavigationCell");
	NavigationRegion3D *region = memnew(NavigationRegion3D);
	region->set_name("WalkableRegion");
	root->add_child(region);
	region->set_owner(root);
	Ref<PackedScene> packed;
	packed.instantiate();
	CHECK(packed->pack(root) == OK);
	memdelete(root);
	const String path = "user://partition_navigation_gate_" + p_id + "_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	CHECK(ResourceSaver::save(packed, path) == OK);
	return path;
}

static String make_physics_cell_scene(const String &p_id) {
	Node3D *root = memnew(Node3D);
	root->set_name("PhysicsCell");
	RigidBody3D *body = memnew(RigidBody3D);
	body->set_name("PersistentBox");
	body->set_gravity_scale(0);
	body->set_meta(SNAME("streaming_persistent"), true);
	body->set_position(Vector3(9, 4, 7));
	root->add_child(body);
	body->set_owner(root);
	// An ordinary unmarked physics body must never bloat the saved state.
	RigidBody3D *unmarked = memnew(RigidBody3D);
	unmarked->set_name("UnmarkedBox");
	unmarked->set_gravity_scale(0);
	root->add_child(unmarked);
	unmarked->set_owner(root);
	Ref<PackedScene> packed;
	packed.instantiate();
	CHECK(packed->pack(root) == OK);
	memdelete(root);
	const String path = "user://partition_physics_" + p_id + "_" + itos(OS::get_singleton()->get_process_id()) + ".tscn";
	CHECK(ResourceSaver::save(packed, path) == OK);
	return path;
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

TEST_CASE("[SceneTree][WorldPartition3D] Pin prevents unloading after observer moves away") {
	const String path = make_cell_scene("persistent_hub");
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->pin_cell(Vector2i(0, 0));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		fixture.observer->set_position(Vector3(256, 0, 0));
		fixture.world->update_streaming();
		CHECK(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		fixture.world->unpin_cell(Vector2i(0, 0));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] A pin can load a cell with no valid observer") {
	const String path = make_cell_scene("pin_without_observer");
	{
		WorldFixture fixture;
		fixture.world->set_observer_path(NodePath());
		fixture.world->set_cell_scene(Vector2i(-3, 4), path);
		fixture.world->pin_cell(Vector2i(-3, 4));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(-3, 4)));
		CHECK(fixture.world->is_cell_loaded(Vector2i(-3, 4)));
		fixture.world->set_observer_path(fixture.world->get_path_to(fixture.observer));
		fixture.world->clear_pinned_cells();
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(-3, 4)));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Releasing the only pin unloads with no observer") {
	const String path = make_cell_scene("last_pin_cleanup");
	{
		WorldFixture fixture;
		fixture.world->set_observer_path(NodePath());
		fixture.world->set_cell_scene(Vector2i(6, -4), path);
		fixture.world->pin_cell(Vector2i(6, -4));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(6, -4)));
		fixture.world->unpin_cell(Vector2i(6, -4));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(6, -4)));
		CHECK(fixture.world->get_pinned_cell_count() == 0);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Pinned request is prioritized before primary observer") {
	const String near_path = make_cell_scene("pin_priority_near");
	const String pin_path = make_cell_scene("pin_priority_far");
	{
		WorldFixture fixture;
		fixture.world->set_max_new_requests_per_frame(1);
		fixture.world->set_cell_scene(Vector2i(0, 0), near_path);
		fixture.world->set_cell_scene(Vector2i(5, 0), pin_path);
		fixture.world->pin_cell(Vector2i(5, 0));
		fixture.world->update_streaming();
		// The single-frame request budget is assigned to the pinned cell.
		CHECK(ResourceLoader::load_threaded_get_status(pin_path) != ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
		CHECK(ResourceLoader::load_threaded_get_status(near_path) == ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(5, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
	}
	CHECK(DirAccess::remove_absolute(near_path) == OK);
	CHECK(DirAccess::remove_absolute(pin_path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Pins keep their registration while streaming is disabled") {
	const String path = make_cell_scene("pause_pin");
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->pin_cell(Vector2i(0, 0));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		fixture.world->set_streaming_enabled(false);
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		CHECK(fixture.world->is_cell_pinned(Vector2i(0, 0)));
		fixture.world->set_streaming_enabled(true);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Unload budget spreads teleport cleanup over frames") {
	const String path = make_cell_scene("budgeted_unload");
	{
		WorldFixture fixture;
		fixture.world->set_load_radius(1);
		fixture.world->set_unload_radius(2);
		fixture.world->set_max_unloads_per_frame(1);
		fixture.world->set_cell_scene(Vector2i(-1, 0), path);
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->set_cell_scene(Vector2i(1, 0), path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(-1, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(1, 0)));
		CHECK(fixture.world->get_loaded_cell_count() == 3);

		fixture.observer->set_position(Vector3(1280, 0, 0));
		fixture.world->update_streaming();
		CHECK(fixture.world->get_loaded_cell_count() == 2);
		fixture.world->update_streaming();
		CHECK(fixture.world->get_loaded_cell_count() == 1);
		fixture.world->update_streaming();
		CHECK(fixture.world->get_loaded_cell_count() == 0);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Cell instance lookup tracks streaming lifetime") {
	const String path = make_cell_scene("instance_lookup");
	{
		WorldFixture fixture;
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		Node3D *instance = fixture.world->get_cell_instance(Vector2i(0, 0));
		REQUIRE(instance != nullptr);
		CHECK(instance->get_parent() == fixture.world);
		CHECK(instance->get_name() == "AuthoredCell");
		CHECK(fixture.world->get_cell_instance(Vector2i(1, 0)) == nullptr);
		fixture.observer->set_position(Vector3(96, 0, 0));
		fixture.world->update_streaming();
		CHECK(fixture.world->get_cell_instance(Vector2i(0, 0)) == nullptr);
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Two observers stream and retain distant cells") {
	const String path = make_cell_scene("two_sources");
	{
		WorldFixture fixture;
		fixture.world->set_unload_radius(0);
		Node3D *secondary = memnew(Node3D);
		secondary->set_name("SecondaryStreamingObserver");
		SceneTree::get_singleton()->get_root()->add_child(secondary);
		secondary->set_position(Vector3(64, 0, 0));
		Array additional;
		additional.push_back(fixture.world->get_path_to(secondary));
		fixture.world->set_additional_observer_paths(additional);
		fixture.world->set_cell_scene(Vector2i(0, 0), path);
		fixture.world->set_cell_scene(Vector2i(4, 0), path);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(4, 0)));
		CHECK(fixture.world->get_loaded_cell_count() == 2);
		fixture.observer->set_position(Vector3(128, 0, 0));
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(0, 0)));
		CHECK(fixture.world->is_cell_loaded(Vector2i(4, 0)));
		fixture.world->set_additional_observer_paths(Array());
		fixture.world->update_streaming();
		CHECK_FALSE(fixture.world->is_cell_loaded(Vector2i(4, 0)));
		SceneTree::get_singleton()->get_root()->remove_child(secondary);
		memdelete(secondary);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Secondary center loads before primary outer ring") {
	const String primary_path = make_cell_scene("priority_primary");
	const String ring_path = make_cell_scene("priority_ring");
	const String secondary_path = make_cell_scene("priority_secondary");
	{
		WorldFixture fixture;
		fixture.world->set_load_radius(1);
		fixture.world->set_unload_radius(2);
		fixture.world->set_max_new_requests_per_frame(1);
		Node3D *secondary = memnew(Node3D);
		secondary->set_name("NearestStreamingObserver");
		SceneTree::get_singleton()->get_root()->add_child(secondary);
		secondary->set_position(Vector3(64, 0, 0));
		Array extra_sources;
		extra_sources.push_back(fixture.world->get_path_to(secondary));
		fixture.world->set_additional_observer_paths(extra_sources);
		fixture.world->set_cell_scene(Vector2i(0, 0), primary_path);
		fixture.world->set_cell_scene(Vector2i(1, 0), ring_path);
		fixture.world->set_cell_scene(Vector2i(4, 0), secondary_path);

		fixture.world->update_streaming();
		// Primary radius-0 has priority on the first frame.
		CHECK(ResourceLoader::load_threaded_get_status(primary_path) != ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
		CHECK(ResourceLoader::load_threaded_get_status(secondary_path) == ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);

		fixture.world->update_streaming();
		// Secondary radius-0 must beat primary radius-1 on the next frame.
		CHECK(ResourceLoader::load_threaded_get_status(secondary_path) != ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
		CHECK(ResourceLoader::load_threaded_get_status(ring_path) == ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);

		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(4, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(1, 0)));
		SceneTree::get_singleton()->get_root()->remove_child(secondary);
		memdelete(secondary);
	}
	CHECK(DirAccess::remove_absolute(primary_path) == OK);
	CHECK(DirAccess::remove_absolute(ring_path) == OK);
	CHECK(DirAccess::remove_absolute(secondary_path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Streaming sources share a single request budget") {
	const String primary_path = make_cell_scene("source_budget_primary");
	const String secondary_path = make_cell_scene("source_budget_secondary");
	{
		WorldFixture fixture;
		fixture.world->set_max_new_requests_per_frame(1);
		Node3D *secondary = memnew(Node3D);
		secondary->set_name("BudgetStreamingObserver");
		SceneTree::get_singleton()->get_root()->add_child(secondary);
		secondary->set_position(Vector3(64, 0, 0));
		Array additional;
		additional.push_back(fixture.world->get_path_to(secondary));
		fixture.world->set_additional_observer_paths(additional);
		fixture.world->set_cell_scene(Vector2i(0, 0), primary_path);
		fixture.world->set_cell_scene(Vector2i(4, 0), secondary_path);
		fixture.world->update_streaming();
		// A single update may start only one resource request across all sources.
		CHECK(ResourceLoader::load_threaded_get_status(primary_path) != ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
		CHECK(ResourceLoader::load_threaded_get_status(secondary_path) == ResourceLoader::THREAD_LOAD_INVALID_RESOURCE);
		REQUIRE(wait_for_cell(fixture.world, Vector2i(0, 0)));
		REQUIRE(wait_for_cell(fixture.world, Vector2i(4, 0)));
		SceneTree::get_singleton()->get_root()->remove_child(secondary);
		memdelete(secondary);
	}
	CHECK(DirAccess::remove_absolute(primary_path) == OK);
	CHECK(DirAccess::remove_absolute(secondary_path) == OK);
}

TEST_CASE("[SceneTree][WorldPartition3D] Additional observer works without primary observer") {
	const String path = make_cell_scene("secondary_only");
	{
		WorldFixture fixture;
		fixture.world->set_observer_path(NodePath());
		Node3D *secondary = memnew(Node3D);
		secondary->set_name("SecondaryOnlyObserver");
		SceneTree::get_singleton()->get_root()->add_child(secondary);
		secondary->set_position(Vector3(-32, 0, 16));
		Array additional;
		additional.push_back(fixture.world->get_path_to(secondary));
		fixture.world->set_additional_observer_paths(additional);
		fixture.world->set_cell_scene(Vector2i(-2, 1), path);
		CHECK(wait_for_cell(fixture.world, Vector2i(-2, 1)));
		CHECK(fixture.world->is_cell_loaded(Vector2i(-2, 1)));
		SceneTree::get_singleton()->get_root()->remove_child(secondary);
		memdelete(secondary);
	}
	CHECK(DirAccess::remove_absolute(path) == OK);
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
