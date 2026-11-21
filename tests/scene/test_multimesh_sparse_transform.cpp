/**************************************************************************/
/*  test_multimesh_sparse_transform.cpp                                   */
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

TEST_FORCE_LINK(test_multimesh_sparse_transform)

#ifndef _3D_DISABLED

#include "scene/resources/multimesh.h"

namespace TestMultiMeshSparseTransform {

TEST_CASE("[SceneTree][MultiMesh] Sparse batch updates visible and hidden instances") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_instance_count(4);
	mm->set_visible_instance_count(2);
	PackedInt32Array indices;
	indices.push_back(3);
	indices.push_back(0);
	TypedArray<Transform3D> transforms;
	transforms.push_back(Transform3D(Basis(), Vector3(8, 0, 0)));
	transforms.push_back(Transform3D(Basis(), Vector3(2, 0, 0)));
	CHECK(mm->set_instance_transforms_batch(indices, transforms));
	CHECK(mm->get_instance_transform(3).origin == Vector3(8, 0, 0));
	CHECK(mm->get_instance_transform(0).origin == Vector3(2, 0, 0));
	CHECK(mm->get_visible_instance_count() == 2);
	CHECK(mm->get_instance_count() == 4);
}

TEST_CASE("[SceneTree][MultiMesh] Invalid batches leave instances unchanged") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_instance_count(3);
	mm->set_instance_transform(0, Transform3D(Basis(), Vector3(1, 0, 0)));
	PackedInt32Array repeats;
	repeats.push_back(0);
	repeats.push_back(0);
	PackedInt32Array outside;
	outside.push_back(0);
	outside.push_back(3);
	PackedInt32Array one;
	one.push_back(0);
	TypedArray<Transform3D> changes;
	changes.push_back(Transform3D(Basis(), Vector3(4, 0, 0)));
	changes.push_back(Transform3D(Basis(), Vector3(5, 0, 0)));
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_transforms_batch(repeats, changes));
	CHECK_FALSE(mm->set_instance_transforms_batch(outside, changes));
	CHECK_FALSE(mm->set_instance_transforms_batch(one, changes));
	ERR_PRINT_ON;
	CHECK(mm->get_instance_transform(0).origin == Vector3(1, 0, 0));
	PackedInt32Array empty;
	TypedArray<Transform3D> no_changes;
	CHECK(mm->set_instance_transforms_batch(empty, no_changes));
}

TEST_CASE("[SceneTree][MultiMesh] Batch rejects incompatible 2D format") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_2D);
	mm->set_instance_count(2);
	PackedInt32Array ids;
	ids.push_back(0);
	TypedArray<Transform3D> transforms;
	transforms.push_back(Transform3D());
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_transforms_batch(ids, transforms));
	ERR_PRINT_ON;
	CHECK(mm->get_instance_count() == 2);
}

} // namespace TestMultiMeshSparseTransform

#endif // _3D_DISABLED
