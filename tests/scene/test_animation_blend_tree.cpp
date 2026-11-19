/**************************************************************************/
/*  test_animation_blend_tree.cpp                                         */
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

TEST_FORCE_LINK(test_animation_blend_tree)

#include "scene/animation/animation_blend_tree.h"

namespace TestAnimationBlendTree {

TEST_CASE("[SceneTree][AnimationBlendTree] Create AnimationBlendTree and add AnimationNode") {
	Ref<AnimationNodeBlendTree> blend_tree;
	blend_tree.instantiate();

	// Test initial state.
	CHECK(blend_tree->has_node("output"));
	CHECK_EQ(blend_tree->get_graph_offset(), Vector2(0, 0));
	CHECK_EQ(blend_tree->get_node_list().size(), 1);

	// Test adding animation node.
	Ref<AnimationNodeAnimation> anim_node;
	anim_node.instantiate();
	anim_node->set_animation(StringName("test_animation"));
	Vector2 position(100, 100);
	blend_tree->add_node("test_node", anim_node, position);

	// Test node existence.
	CHECK(blend_tree->has_node("test_node"));
	CHECK_EQ(blend_tree->get_node("test_node"), anim_node);
	CHECK_EQ(blend_tree->get_node_position("test_node"), position);

	// Test node connection on port 0.
	CHECK_EQ(blend_tree->can_connect_node("output", 0, "test_node"), AnimationNodeBlendTree::CONNECTION_OK);
	blend_tree->connect_node("output", 0, "test_node");

	const LocalVector<StringName> *connections = blend_tree->get_node_connection_array("output");
	CHECK_EQ(connections->size(), 1);
	CHECK_EQ(connections->operator[](0), StringName("test_node"));

	// Test node rename.
	blend_tree->rename_node("test_node", "renamed_node");
	CHECK_FALSE(blend_tree->has_node("test_node"));
	CHECK(blend_tree->has_node("renamed_node"));

	connections = blend_tree->get_node_connection_array("output");
	CHECK_EQ(connections->operator[](0), StringName("renamed_node"));

	// Test node removal.
	blend_tree->remove_node("renamed_node");
	CHECK_FALSE(blend_tree->has_node("renamed_node"));

	connections = blend_tree->get_node_connection_array("output");
	CHECK_EQ(connections->operator[](0), StringName());
}


TEST_CASE("[AnimationBlendTreeFastPath] repeated node position edits preserve exact values") {
	Ref<AnimationNodeBlendTree> blend_tree;
	blend_tree.instantiate();
	Ref<AnimationNodeAnimation> anim_node;
	anim_node.instantiate();
	blend_tree->add_node("position_node", anim_node);
	for (int i = 0; i < 128; ++i) {
		const Vector2 pos(i * 0.5f, -i * 0.25f);
		blend_tree->set_node_position("position_node", pos);
		CHECK_EQ(blend_tree->get_node_position("position_node"), pos);
	}
	CHECK_EQ(blend_tree->get_node("position_node"), anim_node);
}

TEST_CASE("[AnimationBlendTreeFastPath] connecting and disconnecting a node preserves port state") {
	Ref<AnimationNodeBlendTree> blend_tree;
	blend_tree.instantiate();
	Ref<AnimationNodeAnimation> anim_node;
	anim_node.instantiate();
	blend_tree->add_node("sound", anim_node);
	CHECK_EQ(blend_tree->can_connect_node("output", 0, "sound"), AnimationNodeBlendTree::CONNECTION_OK);
	blend_tree->connect_node("output", 0, "sound");
	const LocalVector<StringName> *connections = blend_tree->get_node_connection_array("output");
	REQUIRE(connections != nullptr);
	REQUIRE_EQ(connections->size(), 1);
	CHECK_EQ((*connections)[0], StringName("sound"));
	CHECK_EQ(blend_tree->can_connect_node("output", 0, "sound"), AnimationNodeBlendTree::CONNECTION_ERROR_CONNECTION_EXISTS);
	blend_tree->disconnect_node("output", 0);
	CHECK_EQ((*connections)[0], StringName());
	CHECK_EQ(blend_tree->can_connect_node("output", 0, "sound"), AnimationNodeBlendTree::CONNECTION_OK);
}

TEST_CASE("[AnimationBlendTreeFastPath] absent node and invalid port report explicit error codes") {
	Ref<AnimationNodeBlendTree> blend_tree;
	blend_tree.instantiate();
	Ref<AnimationNodeAnimation> anim_node;
	anim_node.instantiate();
	blend_tree->add_node("valid", anim_node);
	CHECK_EQ(blend_tree->can_connect_node("missing", 0, "valid"), AnimationNodeBlendTree::CONNECTION_ERROR_NO_INPUT);
	CHECK_EQ(blend_tree->can_connect_node("output", 0, "missing"), AnimationNodeBlendTree::CONNECTION_ERROR_NO_OUTPUT);
	CHECK_EQ(blend_tree->can_connect_node("output", 10, "valid"), AnimationNodeBlendTree::CONNECTION_ERROR_NO_INPUT_INDEX);
	CHECK_EQ(blend_tree->can_connect_node("output", 0, "output"), AnimationNodeBlendTree::CONNECTION_ERROR_NO_OUTPUT);
}

TEST_CASE("[AnimationBlendTreeFastPath] exported node property lookups preserve node identity and position") {
	Ref<AnimationNodeBlendTree> blend_tree;
	blend_tree.instantiate();
	Ref<AnimationNodeAnimation> anim_node;
	anim_node.instantiate();
	blend_tree->add_node("my_node", anim_node);
	const Vector2 new_position(18, 49);
	blend_tree->set("nodes/my_node/position", new_position);
	CHECK_EQ(blend_tree->get_node_position("my_node"), new_position);
	CHECK_EQ(blend_tree->get("nodes/my_node/position"), Variant(new_position));
	CHECK_EQ(blend_tree->get("nodes/my_node/node"), Variant(anim_node));
}

} // namespace TestAnimationBlendTree
