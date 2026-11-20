/**************************************************************************/
/*  test_multimesh_custom_data_batch.cpp                                  */
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

TEST_FORCE_LINK(test_multimesh_custom_data_batch)

#ifndef _3D_DISABLED

#include "scene/resources/multimesh.h"

namespace TestMultiMeshCustomDataBatch {

TEST_CASE("[SceneTree][MultiMesh] Batch custom data supports unsorted and hidden indices") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_use_custom_data(true);
	mm->set_instance_count(4);
	mm->set_visible_instance_count(2);
	PackedInt32Array indices;
	indices.push_back(3);
	indices.push_back(0);
	PackedColorArray colors;
	colors.push_back(Color(0.25, 0.5, 0.75, 1));
	colors.push_back(Color(0.75, 0.5, 0.25, 1));
	CHECK(mm->set_instance_custom_data_batch(indices, colors));
	CHECK(mm->get_instance_custom_data(3) == colors[0]);
	CHECK(mm->get_instance_custom_data(0) == colors[1]);
	CHECK(mm->get_visible_instance_count() == 2);
	CHECK(mm->get_instance_count() == 4);
	PackedInt32Array empty;
	PackedColorArray empty_colors;
	CHECK(mm->set_instance_custom_data_batch(empty, empty_colors));
}

TEST_CASE("[SceneTree][MultiMesh] Batch custom data rejects invalid input without mutation") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_use_custom_data(true);
	mm->set_instance_count(3);
	const Color original(0.25, 0.5, 0.75, 1);
	mm->set_instance_custom_data(0, original);
	PackedInt32Array duplicate;
	duplicate.push_back(0);
	duplicate.push_back(0);
	PackedColorArray payload;
	payload.push_back(Color(1, 0, 0, 1));
	payload.push_back(Color(0, 1, 0, 1));
	PackedInt32Array out_of_range;
	out_of_range.push_back(0);
	out_of_range.push_back(3);
	PackedInt32Array one;
	one.push_back(0);
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_custom_data_batch(duplicate, payload));
	CHECK_FALSE(mm->set_instance_custom_data_batch(out_of_range, payload));
	CHECK_FALSE(mm->set_instance_custom_data_batch(one, payload)); // mismatched size
	ERR_PRINT_ON;
	CHECK(mm->get_instance_custom_data(0) == original);
}

TEST_CASE("[SceneTree][MultiMesh] Custom data disabled fails without allocating") {
	Ref<MultiMesh> mm;
	mm.instantiate();
	mm->set_instance_count(2);
	PackedInt32Array ids;
	ids.push_back(0);
	PackedColorArray colors;
	colors.push_back(Color(1, 1, 1, 1));
	ERR_PRINT_OFF;
	CHECK_FALSE(mm->set_instance_custom_data_batch(ids, colors));
	ERR_PRINT_ON;
	CHECK_FALSE(mm->is_using_custom_data());
	CHECK(mm->get_instance_count() == 2);
}

} // namespace TestMultiMeshCustomDataBatch

#endif // _3D_DISABLED
