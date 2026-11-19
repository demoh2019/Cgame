/**************************************************************************/
/*  test_visual_shader_unique_reload.h                                    */
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
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF   */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "modules/visual_shader/visual_shader.h"
#include "tests/test_macros.h"

namespace TestVisualShaderUniqueReload {

TEST_CASE("[VisualShader] Serialized node property creates a new node") {
	Ref<VisualShader> shader;
	shader.instantiate();

	Ref<VisualShaderNode> input = memnew(VisualShaderNodeInput);
	bool created = false;
	shader->set("nodes/vertex/19/node", input, &created);
	CHECK(created);
	CHECK(shader->get_node(VisualShader::TYPE_VERTEX, 19) == input);
}

TEST_CASE("[VisualShader] Reapplying serialized node property does not re-add an existing node") {
	Ref<VisualShader> shader;
	shader.instantiate();

	Ref<VisualShaderNode> input = memnew(VisualShaderNodeInput);
	shader->add_node(VisualShader::TYPE_VERTEX, input, Vector2(3, 5), 19);

	Ref<VisualShaderNode> incoming = memnew(VisualShaderNodeInput);

	// A duplicate path is ignored instead of passing into add_node, which
	// rejects an already registered ID and emits editor errors on reload.
	ERR_PRINT_OFF;
	bool inserted_duplicate = false;
	shader->set("nodes/vertex/19/node", incoming, &inserted_duplicate);
	ERR_PRINT_ON;
	CHECK_FALSE(inserted_duplicate);
	CHECK(shader->get_node(VisualShader::TYPE_VERTEX, 19) == input);
	CHECK(shader->get_node_position(VisualShader::TYPE_VERTEX, 19) == Vector2(3, 5));
}

TEST_CASE("[VisualShader] Ignored duplicate does not prevent later node property updates") {
	Ref<VisualShader> shader;
	shader.instantiate();
	Ref<VisualShaderNode> input = memnew(VisualShaderNodeInput);
	shader->add_node(VisualShader::TYPE_VERTEX, input, Vector2(), 21);

	bool inserted_duplicate = false;
	shader->set("nodes/vertex/21/node", input, &inserted_duplicate);
	CHECK_FALSE(inserted_duplicate);
	bool positioned = false;
	shader->set("nodes/vertex/21/position", Vector2(7, 9), &positioned);
	CHECK(positioned);
	CHECK(shader->get_node_position(VisualShader::TYPE_VERTEX, 21) == Vector2(7, 9));

	Ref<VisualShaderNode> second = memnew(VisualShaderNodeInput);
	bool second_created = false;
	shader->set("nodes/vertex/22/node", second, &second_created);
	CHECK(second_created);
	CHECK(shader->get_node(VisualShader::TYPE_VERTEX, 22) == second);
}

} // namespace TestVisualShaderUniqueReload
