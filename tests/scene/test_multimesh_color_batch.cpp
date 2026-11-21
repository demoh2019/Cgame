/**************************************************************************/
/*  test_multimesh_color_batch.cpp                                        */
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

TEST_FORCE_LINK(test_multimesh_color_batch)

#ifndef _3D_DISABLED

#include "scene/resources/multimesh.h"

namespace TestMultiMeshColorBatch {

TEST_CASE("[SceneTree][MultiMesh] Sparse colors update hidden and visible slots") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_use_colors(true);
	mm->set_instance_count(4);
	mm->set_visible_instance_count(2);
	PackedInt32Array indices;
	indices.push_back(3);
	indices.push_back(0);
	PackedColorArray colors;
	colors.push_back(Color(0, 1, 0, 1));
	colors.push_back(Color(1, 0, 0, 1));
	CHECK(mm->set_instance_colors_batch(indices, colors));
	CHECK(mm->get_instance_color(3) == Color(0, 1, 0, 1));
	CHECK(mm->get_instance_color(0) == Color(1, 0, 0, 1));
	CHECK(mm->get_visible_instance_count() == 2);
	PackedInt32Array empty_indices;
	PackedColorArray empty_colors;
	CHECK(mm->set_instance_colors_batch(empty_indices, empty_colors));
}

TEST_CASE("[SceneTree][MultiMesh] Invalid color batch is an all-or-nothing failure") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_use_colors(true);
	mm->set_instance_count(3);
	mm->set_instance_color(0, Color(0, 0, 1, 1));
	PackedInt32Array duplicates;
	duplicates.push_back(0);
	duplicates.push_back(0);
	PackedInt32Array outside;
	outside.push_back(0);
	outside.push_back(3);
	PackedInt32Array one;
	one.push_back(0);
	PackedColorArray pair;
	pair.push_back(Color(1, 0, 0, 1));
	pair.push_back(Color(0, 1, 0, 1));
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_colors_batch(duplicates, pair));
	CHECK_FALSE(mm->set_instance_colors_batch(outside, pair));
	CHECK_FALSE(mm->set_instance_colors_batch(one, pair));
	ERR_PRINT_ON;
	CHECK(mm->get_instance_color(0) == Color(0, 0, 1, 1));
}

TEST_CASE("[SceneTree][MultiMesh] Colors disabled do not enable automatically") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_instance_count(2);
	PackedInt32Array indices;
	indices.push_back(0);
	PackedColorArray colors;
	colors.push_back(Color(1, 1, 1, 1));
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_colors_batch(indices, colors));
	ERR_PRINT_ON;
	CHECK_FALSE(mm->is_using_colors());
	CHECK(mm->get_instance_count() == 2);
}

} // namespace TestMultiMeshColorBatch

#endif // _3D_DISABLED
