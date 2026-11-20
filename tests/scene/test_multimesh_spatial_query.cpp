/**************************************************************************/
/*  test_multimesh_spatial_query.cpp                                      */
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
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_multimesh_spatial_query)

#ifndef _3D_DISABLED

#include "scene/3d/multimesh_instance_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "scene/resources/multimesh.h"

namespace TestMultiMeshSpatialQuery {

TEST_CASE("[SceneTree][MultiMeshInstance3D] Nearest 3D instance query honors radius and visible prefix") {
	Ref<MultiMesh> multimesh;
	multimesh.instantiate();
	Ref<BoxMesh> box;
	box.instantiate();
	multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
	multimesh->set_mesh(box);
	multimesh->set_instance_count(3);
	multimesh->set_instance_transform(0, Transform3D(Basis(), Vector3(0, 0, 0)));
	multimesh->set_instance_transform(1, Transform3D(Basis(), Vector3(4, 0, 0)));
	multimesh->set_instance_transform(2, Transform3D(Basis(), Vector3(9, 0, 0)));

	MultiMeshInstance3D *node = memnew(MultiMeshInstance3D);
	SceneTree::get_singleton()->get_root()->add_child(node);
	node->set_multimesh(multimesh);
	node->set_position(Vector3(10, 0, 5));

	CHECK(node->find_nearest_visible_instance(Vector3(14, 0, 5), 0) == 1);
	CHECK(node->find_nearest_visible_instance(Vector3(14, 0, 6), 1) == 1);
	CHECK(node->find_nearest_visible_instance(Vector3(14, 0, 6), 0.5) == -1);
	CHECK(node->find_nearest_visible_instance(Vector3(19, 0, 5), 0) == 2);

	PackedInt32Array within = node->find_visible_instances_in_radius(Vector3(14, 0, 5), 4);
	REQUIRE(within.size() == 2);
	CHECK(within[0] == 0);
	CHECK(within[1] == 1);
	CHECK(node->find_visible_instances_in_radius(Vector3(14, 0, 5), 0).size() == 1);
	CHECK(node->find_visible_instances_in_radius(Vector3(19, 0, 5), 0).size() == 1);

	multimesh->set_visible_instance_count(2);
	CHECK(node->find_visible_instances_in_radius(Vector3(19, 0, 5), 1).is_empty());
	multimesh->set_visible_instance_count(0);
	CHECK(node->find_visible_instances_in_radius(Vector3(14, 0, 5), 100).is_empty());
	multimesh->set_visible_instance_count(-1);
	CHECK(node->find_visible_instances_in_radius(Vector3(19, 0, 5), 0).size() == 1);

	ERR_PRINT_OFF;
	CHECK(node->find_visible_instances_in_radius(Vector3(), -1).is_empty());
	ERR_PRINT_ON;

	multimesh->set_visible_instance_count(2);
	CHECK(node->find_nearest_visible_instance(Vector3(19, 0, 5), 2) == -1);
	CHECK(node->find_nearest_visible_instance(Vector3(14, 0, 5), 0.1) == 1);
	multimesh->set_visible_instance_count(0);
	CHECK(node->find_nearest_visible_instance(Vector3(10, 0, 5), 100) == -1);
	multimesh->set_visible_instance_count(-1);
	CHECK(node->find_nearest_visible_instance(Vector3(19, 0, 5), 0) == 2);

	ERR_PRINT_OFF;
	CHECK(node->find_nearest_visible_instance(Vector3(), -1) == -1);
	ERR_PRINT_ON;
	node->queue_free();
}

TEST_CASE("[SceneTree][MultiMeshInstance3D] Missing MultiMesh cannot be queried") {
	MultiMeshInstance3D *node = memnew(MultiMeshInstance3D);
	SceneTree::get_singleton()->get_root()->add_child(node);
	CHECK(node->find_nearest_visible_instance(Vector3(), 100) == -1);
	CHECK(node->find_visible_instances_in_radius(Vector3(), 100).is_empty());
	node->queue_free();
}

} // namespace TestMultiMeshSpatialQuery

#endif // _3D_DISABLED
