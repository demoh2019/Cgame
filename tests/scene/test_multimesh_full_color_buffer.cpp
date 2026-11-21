/**************************************************************************/
/*  test_multimesh_full_color_buffer.cpp                                  */
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

TEST_FORCE_LINK(test_multimesh_full_color_buffer)

#ifndef _3D_DISABLED

#include "scene/resources/multimesh.h"

namespace TestMultiMeshFullColorBuffer {

TEST_CASE("[SceneTree][MultiMesh] Whole transform-color upload packs one correct buffer") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_use_colors(true);
	mm->set_instance_count(3);

	Array transforms;
	transforms.push_back(Transform3D(Basis(), Vector3(1, 2, 3)));
	transforms.push_back(Transform3D(Basis().scaled(Vector3(2, 3, 4)), Vector3(5, 6, 7)));
	transforms.push_back(Transform3D(Basis(), Vector3(9, 10, 11)));
	Vector<Color> colors;
	colors.push_back(Color(1, 0, 0, 1));
	colors.push_back(Color(0.25, 0.5, 0.75, 1));
	colors.push_back(Color(0, 0, 1, 1));
	CHECK(mm->set_instance_transform_color_buffer(transforms, colors));
	CHECK(mm->get_instance_count() == 3);
	CHECK(mm->get_visible_instance_count() == -1);
	CHECK(mm->get_instance_transform(1).origin == Vector3(5, 6, 7));
	CHECK(mm->get_instance_color(1) == colors[1]);
	Vector<float> buffer = mm->get_buffer();
	CHECK(buffer.size() == 3 * 16);
	CHECK(buffer[1 * 16 + 0] == 2.0f);
	CHECK(buffer[1 * 16 + 5] == 3.0f);
	CHECK(buffer[1 * 16 + 10] == 4.0f);
	CHECK(buffer[1 * 16 + 3] == 5.0f);
	CHECK(buffer[1 * 16 + 7] == 6.0f);
	CHECK(buffer[1 * 16 + 11] == 7.0f);
	CHECK(buffer[1 * 16 + 12] == 0.25f);
	CHECK(buffer[1 * 16 + 13] == 0.5f);
	CHECK(buffer[1 * 16 + 14] == 0.75f);
	CHECK(buffer[1 * 16 + 15] == 1.0f);
}

TEST_CASE("[SceneTree][MultiMesh] Invalid full buffer input does not modify existing payload") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_use_colors(true);
	mm->set_instance_count(2);

	Array transforms;
	transforms.push_back(Transform3D(Basis(), Vector3(1, 0, 0)));
	transforms.push_back(Transform3D(Basis(), Vector3(2, 0, 0)));
	Vector<Color> colors;
	colors.push_back(Color(1, 0, 0, 1));
	colors.push_back(Color(0, 0, 1, 1));
	CHECK(mm->set_instance_transform_color_buffer(transforms, colors));
	Vector<float> before = mm->get_buffer();
	Array wrong_type = transforms.duplicate();
	wrong_type[1] = Vector3(9, 9, 9);
	Vector<Color> fewer_colors;
	fewer_colors.push_back(Color(0, 1, 0, 1));
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_transform_color_buffer(wrong_type, colors));
	CHECK_FALSE(mm->set_instance_transform_color_buffer(transforms, fewer_colors));
	ERR_PRINT_ON;
	CHECK(mm->get_buffer() == before);
	CHECK(mm->get_instance_transform(1).origin == Vector3(2, 0, 0));
	CHECK(mm->get_instance_color(0) == Color(1, 0, 0, 1));
}

TEST_CASE("[SceneTree][MultiMesh] Full buffer upload refuses incompatible color/custom formats") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_instance_count(1);
	Array transforms;
	transforms.push_back(Transform3D());
	Vector<Color> colors;
	colors.push_back(Color(1, 1, 1, 1));
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_transform_color_buffer(transforms, colors));
	ERR_PRINT_ON;
	mm->set_use_colors(true);
	mm->set_transform_format(MultiMesh::TRANSFORM_2D);
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_transform_color_buffer(transforms, colors));
	ERR_PRINT_ON;
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_use_custom_data(true);
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_transform_color_buffer(transforms, colors));
	ERR_PRINT_ON;
	CHECK(mm->get_instance_count() == 1);
}

TEST_CASE("[SceneTree][MultiMesh] Zero-instance full upload is an allocation-free success") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_use_colors(true);
	CHECK(mm->get_instance_count() == 0);
	Array empty_transforms;
	Vector<Color> empty_colors;
	CHECK(mm->set_instance_transform_color_buffer(empty_transforms, empty_colors));
	CHECK(mm->get_instance_count() == 0);
	CHECK(mm->get_buffer().is_empty());
}

} // namespace TestMultiMeshFullColorBuffer

#endif // _3D_DISABLED
