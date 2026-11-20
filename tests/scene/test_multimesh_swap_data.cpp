/**************************************************************************/
/*  test_multimesh_swap_data.cpp                                          */
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

TEST_FORCE_LINK(test_multimesh_swap_data)

#ifndef _3D_DISABLED

#include "scene/resources/multimesh.h"

namespace TestMultiMeshSwapData {

TEST_CASE("[SceneTree][MultiMesh] Swap full 3D instance payload without altering visible prefix") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_use_colors(true);
	mm->set_use_custom_data(true);
	mm->set_instance_count(3);
	mm->set_instance_transform(0, Transform3D(Basis(), Vector3(1, 0, 0)));
	mm->set_instance_transform(1, Transform3D(Basis(), Vector3(2, 0, 0)));
	mm->set_instance_transform(2, Transform3D(Basis(), Vector3(3, 0, 0)));
	mm->set_instance_color(0, Color(1, 0, 0, 1));
	mm->set_instance_color(1, Color(0, 1, 0, 1));
	mm->set_instance_color(2, Color(0, 0, 1, 1));
	mm->set_instance_custom_data(0, Color(0, 1, 0, 1));
	mm->set_instance_custom_data(1, Color(1, 0, 0, 1));
	mm->set_instance_custom_data(2, Color(0, 1, 1, 1));
	mm->set_visible_instance_count(2);

	CHECK(mm->swap_instance_data(0, 2));
	CHECK(mm->get_instance_transform(0).origin == Vector3(3, 0, 0));
	CHECK(mm->get_instance_transform(2).origin == Vector3(1, 0, 0));
	CHECK(mm->get_instance_color(0) == Color(0, 0, 1, 1));
	CHECK(mm->get_instance_color(2) == Color(1, 0, 0, 1));
	CHECK(mm->get_instance_custom_data(0) == Color(0, 1, 1, 1));
	CHECK(mm->get_instance_custom_data(2) == Color(0, 1, 0, 1));
	CHECK(mm->get_visible_instance_count() == 2);
	CHECK(mm->get_instance_count() == 3);

	CHECK(mm->swap_instance_data(1, 1));
	CHECK(mm->get_instance_transform(1).origin == Vector3(2, 0, 0));

	ERR_PRINT_OFF;
	CHECK_FALSE(mm->swap_instance_data(-1, 1));
	CHECK_FALSE(mm->swap_instance_data(0, 3));
	ERR_PRINT_ON;
	CHECK(mm->get_instance_transform(0).origin == Vector3(3, 0, 0));
}

TEST_CASE("[SceneTree][MultiMesh] Swap supports 2D transforms without optional data") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_2D);
	mm->set_instance_count(2);

	Transform2D first;
	first.columns[2] = Vector2(5, 6);
	Transform2D second;
	second.columns[2] = Vector2(11, 12);
	mm->set_instance_transform_2d(0, first);
	mm->set_instance_transform_2d(1, second);

	CHECK(mm->swap_instance_data(0, 1));
	CHECK(mm->get_instance_transform_2d(0).get_origin() == Vector2(11, 12));
	CHECK(mm->get_instance_transform_2d(1).get_origin() == Vector2(5, 6));
	CHECK(mm->get_visible_instance_count() == -1);
}

TEST_CASE("[SceneTree][MultiMesh] Remove visible instance compacts complete 3D payload") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_use_colors(true);
	mm->set_use_custom_data(true);
	mm->set_instance_count(3);
	mm->set_instance_transform(0, Transform3D(Basis(), Vector3(1, 0, 0)));
	mm->set_instance_transform(1, Transform3D(Basis(), Vector3(2, 0, 0)));
	mm->set_instance_transform(2, Transform3D(Basis(), Vector3(3, 0, 0)));
	mm->set_instance_color(0, Color(1, 0, 0, 1));
	mm->set_instance_color(1, Color(0, 1, 0, 1));
	mm->set_instance_color(2, Color(0, 0, 1, 1));
	mm->set_instance_custom_data(0, Color(1, 0, 0, 0));
	mm->set_instance_custom_data(1, Color(0, 1, 0, 0));
	mm->set_instance_custom_data(2, Color(0, 0, 1, 0));

	CHECK(mm->get_visible_instance_count() == -1);
	CHECK(mm->remove_visible_instance(1));
	CHECK(mm->get_visible_instance_count() == 2);
	CHECK(mm->get_instance_count() == 3);
	CHECK(mm->get_instance_transform(1).origin == Vector3(3, 0, 0));
	CHECK(mm->get_instance_color(1) == Color(0, 0, 1, 1));
	CHECK(mm->get_instance_custom_data(1) == Color(0, 0, 1, 0));

	ERR_PRINT_OFF;
	CHECK_FALSE(mm->remove_visible_instance(2)); // Hidden slot after removal.
	CHECK_FALSE(mm->remove_visible_instance(-1));
	ERR_PRINT_ON;
	CHECK(mm->get_visible_instance_count() == 2);

	CHECK(mm->remove_visible_instance(1)); // Last visible slot, no swap needed.
	CHECK(mm->get_visible_instance_count() == 1);
	CHECK(mm->remove_visible_instance(0));
	CHECK(mm->get_visible_instance_count() == 0);
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->remove_visible_instance(0));
	ERR_PRINT_ON;
	CHECK(mm->get_visible_instance_count() == 0);
}

TEST_CASE("[SceneTree][MultiMesh] Remove from a partial 2D visible prefix") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_2D);
	mm->set_instance_count(3);
	mm->set_instance_transform_2d(0, Transform2D(0.0, Vector2(0, 0)));
	mm->set_instance_transform_2d(1, Transform2D(0.0, Vector2(5, 6)));
	mm->set_instance_transform_2d(2, Transform2D(0.0, Vector2(9, 10)));
	mm->set_visible_instance_count(2);

	CHECK(mm->remove_visible_instance(0));
	CHECK(mm->get_visible_instance_count() == 1);
	CHECK(mm->get_instance_transform_2d(0).get_origin() == Vector2(5, 6));
	CHECK(mm->get_instance_transform_2d(2).get_origin() == Vector2(9, 10));
	CHECK(mm->get_instance_count() == 3);
}

TEST_CASE("[SceneTree][MultiMesh] Reactivate hidden 3D instance with full payload") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_3D);
	mm->set_use_colors(true);
	mm->set_use_custom_data(true);
	mm->set_instance_count(3);
	mm->set_instance_transform(0, Transform3D(Basis(), Vector3(1, 0, 0)));
	mm->set_instance_transform(1, Transform3D(Basis(), Vector3(2, 0, 0)));
	mm->set_instance_transform(2, Transform3D(Basis(), Vector3(3, 0, 0)));
	mm->set_instance_color(0, Color(1, 0, 0));
	mm->set_instance_color(1, Color(0, 1, 0));
	mm->set_instance_color(2, Color(0, 0, 1));
	mm->set_instance_custom_data(0, Color(1, 0, 0));
	mm->set_instance_custom_data(1, Color(0, 1, 0));
	mm->set_instance_custom_data(2, Color(0, 0, 1));
	mm->set_visible_instance_count(1);

	CHECK(mm->activate_hidden_instance(2)); // Swap hidden #2 into first inactive #1.
	CHECK(mm->get_visible_instance_count() == 2);
	CHECK(mm->get_instance_count() == 3);
	CHECK(mm->get_instance_transform(1).origin == Vector3(3, 0, 0));
	CHECK(mm->get_instance_color(1) == Color(0, 0, 1));
	CHECK(mm->get_instance_custom_data(1) == Color(0, 0, 1));
	CHECK(mm->get_instance_transform(2).origin == Vector3(2, 0, 0));

	ERR_PRINT_OFF;
	CHECK_FALSE(mm->activate_hidden_instance(-1));
	CHECK_FALSE(mm->activate_hidden_instance(0)); // Already visible.
	CHECK_FALSE(mm->activate_hidden_instance(3));
	ERR_PRINT_ON;
	CHECK(mm->get_visible_instance_count() == 2);

	CHECK(mm->activate_hidden_instance(2)); // First inactive slot.
	CHECK(mm->get_visible_instance_count() == 3);
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->activate_hidden_instance(2)); // Fully visible.
	ERR_PRINT_ON;
	CHECK(mm->get_visible_instance_count() == 3);
}

TEST_CASE("[SceneTree][MultiMesh] Activate from zero-visible 2D prefix") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_transform_format(MultiMesh::TRANSFORM_2D);
	mm->set_instance_count(3);
	mm->set_instance_transform_2d(0, Transform2D(0.0, Vector2(0, 0)));
	mm->set_instance_transform_2d(1, Transform2D(0.0, Vector2(5, 6)));
	mm->set_instance_transform_2d(2, Transform2D(0.0, Vector2(9, 10)));
	mm->set_visible_instance_count(0);

	CHECK(mm->activate_hidden_instance(2));
	CHECK(mm->get_visible_instance_count() == 1);
	CHECK(mm->get_instance_transform_2d(0).get_origin() == Vector2(9, 10));
	CHECK(mm->get_instance_transform_2d(2).get_origin() == Vector2(0, 0));
	CHECK(mm->remove_visible_instance(0));
	CHECK(mm->get_visible_instance_count() == 0);

	mm->set_visible_instance_count(-1);
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->activate_hidden_instance(0)); // -1 means all visible.
	ERR_PRINT_ON;
	CHECK(mm->get_visible_instance_count() == -1);
}

} // namespace TestMultiMeshSwapData

#endif // _3D_DISABLED
