/**************************************************************************/
/*  test_world_partition_3d.cpp                                           */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_partition_3d)

#ifndef _3D_DISABLED

#include "core/math/math_funcs.h"
#include "scene/3d/world_partition_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/packed_scene.h"

namespace TestWorldPartition3D {

static Ref<PackedScene> make_cell_scene() {
	Node3D *root = memnew(Node3D);
	root->set_name("CellContent");
	Ref<PackedScene> scene;
	scene.instantiate();
	CHECK_EQ(scene->pack(root), OK);
	memdelete(root);
	return scene;
}

TEST_CASE("[SceneTree][WorldPartition3D] Grid coordinates and negative boundaries") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_size(10.0);
	SceneTree::get_singleton()->get_root()->add_child(partition);

	CHECK_EQ(partition->world_to_cell(Vector3(0, 5, 0)), Vector2i(0, 0));
	CHECK_EQ(partition->world_to_cell(Vector3(9.999, 5, 9.999)), Vector2i(0, 0));
	CHECK_EQ(partition->world_to_cell(Vector3(10, 0, 10)), Vector2i(1, 1));
	CHECK_EQ(partition->world_to_cell(Vector3(-0.001, 0, -0.001)), Vector2i(-1, -1));
	CHECK_EQ(partition->world_to_cell(Vector3(-10, 0, -10)), Vector2i(-1, -1));
	CHECK_EQ(partition->world_to_cell(Vector3(-10.001, 0, -10.001)), Vector2i(-2, -2));

	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Uses local grid coordinates under transforms") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_size(10.0);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->set_position(Vector3(100, 12, -50));
	partition->set_rotation(Vector3(0, Math::PI / 2, 0));
	partition->set_scale(Vector3(2, 1, 2));

	CHECK_EQ(partition->world_to_cell(partition->to_global(Vector3(20, 300, 30))), Vector2i(2, 3));
	CHECK_EQ(partition->world_to_cell(partition->to_global(Vector3(-0.01, -20, 29.9))), Vector2i(-1, 2));
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Streams cells and preserves authored children") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_size(10.0);
	partition->set_load_radius(0);
	Ref<PackedScene> cell = make_cell_scene();
	partition->set_cell_scene(Vector2i(0, 0), cell);
	partition->set_cell_scene(Vector2i(1, 0), cell);
	partition->set_cell_scene(Vector2i(-1, 0), cell);

	Node3D *manual = memnew(Node3D);
	manual->set_name("ManualChild");
	partition->add_child(manual);
	SceneTree::get_singleton()->get_root()->add_child(partition);

	partition->update_streaming(Vector3(2, 0, 3));
	REQUIRE_EQ(partition->get_loaded_cell_count(), 1);
	REQUIRE(partition->get_loaded_cell(Vector2i(0, 0)) != nullptr);
	CHECK_EQ(partition->get_loaded_cell(Vector2i(0, 0))->get_name(), StringName("CellContent"));
	CHECK_EQ(partition->get_loaded_cell(Vector2i(0, 0))->get_position(), Vector3(0, 0, 0));
	CHECK_EQ(partition->get_child_count(), 2);

	// Repeating the update in the same cell does not recreate the scene.
	Node3D *first_instance = partition->get_loaded_cell(Vector2i(0, 0));
	partition->update_streaming(Vector3(9, 500, 9));
	CHECK_EQ(partition->get_loaded_cell(Vector2i(0, 0)), first_instance);

	partition->update_streaming(Vector3(15, 0, 2));
	REQUIRE_EQ(partition->get_loaded_cell_count(), 1);
	CHECK(partition->get_loaded_cell(Vector2i(0, 0)) == nullptr);
	REQUIRE(partition->get_loaded_cell(Vector2i(1, 0)) != nullptr);
	CHECK_EQ(partition->get_loaded_cell(Vector2i(1, 0))->get_position(), Vector3(10, 0, 0));
	CHECK_EQ(partition->get_child_count(), 2);

	partition->update_streaming(Vector3(-1, 0, 0));
	REQUIRE(partition->get_loaded_cell(Vector2i(-1, 0)) != nullptr);
	CHECK_EQ(partition->get_loaded_cell(Vector2i(-1, 0))->get_position(), Vector3(-10, 0, 0));

	partition->update_streaming(Vector3(500, 0, 0));
	CHECK_EQ(partition->get_loaded_cell_count(), 0);
	CHECK_EQ(partition->get_child_count(), 1);
	CHECK_EQ(partition->get_child(0), manual);
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Radius loads all nearby and unloads the rest") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_cell_size(10.0);
	partition->set_load_radius(1);
	Ref<PackedScene> cell = make_cell_scene();
	for (int z = -1; z <= 1; z++) {
		for (int x = -1; x <= 1; x++) {
			partition->set_cell_scene(Vector2i(x, z), cell);
		}
	}
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->update_streaming(Vector3(0, 0, 0));
	CHECK_EQ(partition->get_loaded_cell_count(), 9);
	CHECK(partition->get_loaded_cell(Vector2i(-1, -1)) != nullptr);
	CHECK(partition->get_loaded_cell(Vector2i(1, 1)) != nullptr);

	partition->update_streaming(Vector3(10, 0, 0));
	CHECK_EQ(partition->get_loaded_cell_count(), 6);
	CHECK(partition->get_loaded_cell(Vector2i(-1, 0)) == nullptr);
	CHECK(partition->get_loaded_cell(Vector2i(0, 0)) != nullptr);

	partition->unload_all_cells();
	CHECK_EQ(partition->get_loaded_cell_count(), 0);
	partition->update_streaming(Vector3(10, 0, 0));
	CHECK_EQ(partition->get_loaded_cell_count(), 6);
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Registry changes invalidate loaded instances") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_load_radius(0);
	partition->set_cell_size(10.0);
	Ref<PackedScene> cell = make_cell_scene();
	partition->set_cell_scene(Vector2i(0, 0), cell);
	SceneTree::get_singleton()->get_root()->add_child(partition);
	partition->update_streaming(Vector3());
	REQUIRE_EQ(partition->get_loaded_cell_count(), 1);

	partition->set_cell_size(20.0);
	CHECK_EQ(partition->get_loaded_cell_count(), 0);
	partition->update_streaming(Vector3());
	CHECK_EQ(partition->get_loaded_cell_count(), 1);
	partition->set_load_radius(2);
	CHECK_EQ(partition->get_loaded_cell_count(), 0);
	partition->update_streaming(Vector3());
	CHECK_EQ(partition->get_loaded_cell_count(), 1);

	partition->remove_cell(Vector2i(0, 0));
	CHECK_EQ(partition->get_loaded_cell_count(), 0);
	CHECK(partition->get_cell_source(Vector2i(0, 0)).get_type() == Variant::NIL);
	partition->update_streaming(Vector3());
	CHECK_EQ(partition->get_loaded_cell_count(), 0);
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Dictionary is validated and copied") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	Dictionary entries;
	entries[Vector2i(2, -1)] = "res://world/cell_2_-1.tscn";
	partition->set_cells(entries);
	CHECK_EQ(String(partition->get_cell_source(Vector2i(2, -1))), "res://world/cell_2_-1.tscn");

	// Neither input mutations nor mutations of the returned dictionary affect the node.
	entries.erase(Vector2i(2, -1));
	CHECK(partition->get_cells().has(Vector2i(2, -1)));
	Dictionary copy = partition->get_cells();
	copy.clear();
	CHECK_EQ(partition->get_cells().size(), 1);

	Dictionary invalid;
	invalid["not_a_vector"] = "res://cell.tscn";
	ERR_PRINT_OFF;
	partition->set_cells(invalid);
	partition->set_cell_size(0.0);
	partition->set_cell_size(-1.0);
	partition->set_cell_size(Math::NaN);
	partition->set_load_radius(-1);
	partition->set_load_radius(17);
	ERR_PRINT_ON;
	CHECK_EQ(partition->get_cells().size(), 1);
	CHECK_EQ(partition->get_cell_size(), real_t(64.0));
	CHECK_EQ(partition->get_load_radius(), 1);
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Missing scenes never create loaded cells") {
	WorldPartition3D *partition = memnew(WorldPartition3D);
	partition->set_load_radius(0);
	partition->set_cell_path(Vector2i(0, 0), "res://no_such_world_partition_test_scene.tscn");
	SceneTree::get_singleton()->get_root()->add_child(partition);

	ERR_PRINT_OFF;
	partition->update_streaming(Vector3());
	ERR_PRINT_ON;
	CHECK_EQ(partition->get_loaded_cell_count(), 0);
	CHECK_EQ(partition->get_child_count(), 0);
	memdelete(partition);
}

TEST_CASE("[SceneTree][WorldPartition3D] Viewer path drives automatic updates") {
	Node3D *parent = memnew(Node3D);
	WorldPartition3D *partition = memnew(WorldPartition3D);
	Node3D *viewer = memnew(Node3D);
	viewer->set_name("Viewer");
	partition->set_name("Partition");
	partition->set_cell_size(10.0);
	partition->set_load_radius(0);
	partition->set_cell_scene(Vector2i(0, 0), make_cell_scene());
	partition->set_cell_scene(Vector2i(1, 0), make_cell_scene());
	partition->set_viewer_path(NodePath("../Viewer"));
	parent->add_child(partition);
	parent->add_child(viewer);
	SceneTree::get_singleton()->get_root()->add_child(parent);

	SceneTree::get_singleton()->process(0);
	REQUIRE_EQ(partition->get_loaded_cell_count(), 1);
	CHECK(partition->get_loaded_cell(Vector2i(0, 0)) != nullptr);
	viewer->set_position(Vector3(10, 0, 0));
	SceneTree::get_singleton()->process(0);
	REQUIRE_EQ(partition->get_loaded_cell_count(), 1);
	CHECK(partition->get_loaded_cell(Vector2i(1, 0)) != nullptr);
	memdelete(parent);
}

} // namespace TestWorldPartition3D

#endif // _3D_DISABLED
