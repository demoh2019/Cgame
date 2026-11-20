/**************************************************************************/
/*  test_multimesh_transform_batches.cpp                                  */
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

TEST_FORCE_LINK(test_multimesh_transform_batches)

#ifndef _3D_DISABLED

#include "scene/resources/multimesh.h"

namespace TestMultiMeshTransformBatches {

TEST_CASE("[SceneTree][MultiMesh] Sparse 3D transforms update selected slots") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_instance_count(4);
	mm->set_visible_instance_count(2);
	PackedInt32Array indices;
	indices.push_back(3);
	indices.push_back(0);
	TypedArray<Transform3D> transforms;
	transforms.push_back(Transform3D(Basis(), Vector3(30, 0, 0)));
	transforms.push_back(Transform3D(Basis(), Vector3(10, 0, 0)));

	CHECK(mm->set_instance_transforms_batch(indices, transforms));
	CHECK(mm->get_instance_transform(3).origin == Vector3(30, 0, 0));
	CHECK(mm->get_instance_transform(0).origin == Vector3(10, 0, 0));
	CHECK(mm->get_visible_instance_count() == 2);
	CHECK(mm->get_instance_count() == 4);
	PackedInt32Array empty;
	TypedArray<Transform3D> empty_transforms;
	CHECK(mm->set_instance_transforms_batch(empty, empty_transforms));
}

TEST_CASE("[SceneTree][MultiMesh] Sparse 3D transform batch validates before mutation") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_instance_count(3);
	mm->set_instance_transform(0, Transform3D(Basis(), Vector3(2, 3, 4)));
	PackedInt32Array duplicates;
	duplicates.push_back(0);
	duplicates.push_back(0);
	PackedInt32Array outside;
	outside.push_back(0);
	outside.push_back(3);
	PackedInt32Array valid_one;
	valid_one.push_back(0);
	TypedArray<Transform3D> transforms;
	transforms.push_back(Transform3D(Basis(), Vector3(11, 0, 0)));
	transforms.push_back(Transform3D(Basis(), Vector3(20, 0, 0)));
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_transforms_batch(duplicates, transforms));
	CHECK_FALSE(mm->set_instance_transforms_batch(outside, transforms));
	CHECK_FALSE(mm->set_instance_transforms_batch(valid_one, transforms));
	ERR_PRINT_ON;
	CHECK(mm->get_instance_transform(0).origin == Vector3(2, 3, 4));
}

TEST_CASE("[SceneTree][MultiMesh] Sparse 2D transform batches reject format mismatches") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_2D);
	mm->set_instance_count(3);
	PackedInt32Array indices;
	indices.push_back(2);
	indices.push_back(0);
	TypedArray<Transform2D> transforms;
	transforms.push_back(Transform2D(0.0, Vector2(12, 9)));
	transforms.push_back(Transform2D(0.0, Vector2(4, 3)));
	CHECK(mm->set_instance_transforms_2d_batch(indices, transforms));
	CHECK(mm->get_instance_transform_2d(2).get_origin() == Vector2(12, 9));
	CHECK(mm->get_instance_transform_2d(0).get_origin() == Vector2(4, 3));
	TypedArray<Transform3D> wrong;
	wrong.push_back(Transform3D());
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_transforms_batch(indices, wrong));
	ERR_PRINT_ON;
	CHECK(mm->get_instance_transform_2d(2).get_origin() == Vector2(12, 9));
}

} // namespace TestMultiMeshTransformBatches

#endif // _3D_DISABLED
