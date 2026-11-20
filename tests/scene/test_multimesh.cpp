/**************************************************************************/
/*  test_multimesh.cpp                                                    */
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

TEST_FORCE_LINK(test_multimesh)

#ifndef _3D_DISABLED

#include "scene/3d/multimesh_instance_3d.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "scene/resources/multimesh.h"

namespace TestMultiMesh {

TEST_CASE("[SceneTree][MultiMesh] Reassigning mesh resources preserves instance data") {
	Ref<MultiMesh> multimesh;
	multimesh.instantiate();
	Ref<BoxMesh> mesh_a;
	mesh_a.instantiate();
	Ref<BoxMesh> mesh_b;
	mesh_b.instantiate();

	multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
	multimesh->set_mesh(mesh_a);
	multimesh->set_instance_count(1);
	multimesh->set_instance_transform(0, Transform3D(Basis(), Vector3(1, 2, 3)));

	multimesh->set_mesh(mesh_a);
	CHECK(multimesh->get_mesh() == mesh_a);
	CHECK(multimesh->get_instance_count() == 1);
	CHECK(multimesh->get_instance_transform(0).origin == Vector3(1, 2, 3));

	multimesh->set_mesh(mesh_b);
	CHECK(multimesh->get_mesh() == mesh_b);
	multimesh->set_mesh(Ref<Mesh>());
	CHECK(multimesh->get_mesh().is_null());
}

TEST_CASE("[SceneTree][MultiMeshInstance3D] Reassigning the same MultiMesh is safe") {
	Ref<MultiMesh> multimesh_a;
	multimesh_a.instantiate();
	Ref<MultiMesh> multimesh_b;
	multimesh_b.instantiate();

	MultiMeshInstance3D *instance = memnew(MultiMeshInstance3D);
	instance->set_multimesh(multimesh_a);
	instance->set_multimesh(multimesh_a);
	CHECK(instance->get_multimesh() == multimesh_a);
	instance->set_multimesh(multimesh_b);
	CHECK(instance->get_multimesh() == multimesh_b);
	instance->set_multimesh(Ref<MultiMesh>());
	CHECK(instance->get_multimesh().is_null());
	memdelete(instance);
}


TEST_CASE("[SceneTree][MultiMesh] Repeated visible instance counts preserve state") {
	Ref<MultiMesh> multimesh;
	multimesh.instantiate();
	multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
	multimesh->set_instance_count(4);
	CHECK(multimesh->get_visible_instance_count() == -1);

	multimesh->set_visible_instance_count(2);
	CHECK(multimesh->get_visible_instance_count() == 2);
	multimesh->set_visible_instance_count(2);
	CHECK(multimesh->get_visible_instance_count() == 2);

	multimesh->set_visible_instance_count(0);
	multimesh->set_visible_instance_count(0);
	CHECK(multimesh->get_visible_instance_count() == 0);
	multimesh->set_visible_instance_count(-1);
	multimesh->set_visible_instance_count(-1);
	CHECK(multimesh->get_visible_instance_count() == -1);
}

TEST_CASE("[SceneTree][MultiMesh] Physics interpolation quality updates only when changed") {
	Ref<MultiMesh> multimesh;
	multimesh.instantiate();

	CHECK(multimesh->get_physics_interpolation_quality() == MultiMesh::INTERP_QUALITY_FAST);
	multimesh->set_physics_interpolation_quality(MultiMesh::INTERP_QUALITY_FAST);
	CHECK(multimesh->get_physics_interpolation_quality() == MultiMesh::INTERP_QUALITY_FAST);
	multimesh->set_physics_interpolation_quality(MultiMesh::INTERP_QUALITY_HIGH);
	multimesh->set_physics_interpolation_quality(MultiMesh::INTERP_QUALITY_HIGH);
	CHECK(multimesh->get_physics_interpolation_quality() == MultiMesh::INTERP_QUALITY_HIGH);
	multimesh->set_physics_interpolation_quality(MultiMesh::INTERP_QUALITY_FAST);
	CHECK(multimesh->get_physics_interpolation_quality() == MultiMesh::INTERP_QUALITY_FAST);
}

TEST_CASE("[SceneTree][MultiMeshInstance3D] Mesh gathering respects visible instance count") {
	Ref<MultiMesh> multimesh;
	multimesh.instantiate();
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
	multimesh->set_mesh(mesh);
	multimesh->set_instance_count(3);
	multimesh->set_instance_transform(0, Transform3D(Basis(), Vector3(1, 0, 0)));
	multimesh->set_instance_transform(1, Transform3D(Basis(), Vector3(2, 0, 0)));
	multimesh->set_instance_transform(2, Transform3D(Basis(), Vector3(3, 0, 0)));

	MultiMeshInstance3D *instance = memnew(MultiMeshInstance3D);
	instance->set_multimesh(multimesh);

	CHECK(instance->get_meshes().size() == 6);
	multimesh->set_visible_instance_count(2);
	CHECK(instance->get_meshes().size() == 4);
	multimesh->set_visible_instance_count(0);
	CHECK(instance->get_meshes().is_empty());
	multimesh->set_visible_instance_count(-1);
	CHECK(instance->get_meshes().size() == 6);

	instance->set_multimesh(Ref<MultiMesh>());
	CHECK(instance->get_meshes().is_empty());
	memdelete(instance);
}

} // namespace TestMultiMesh

#endif // _3D_DISABLED
