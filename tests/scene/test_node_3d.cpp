/**************************************************************************/
/*  test_node_3d.cpp                                                      */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_node_3d)

#ifndef _3D_DISABLED

#include "scene/3d/node_3d.h"
#ifndef PHYSICS_3D_DISABLED
#include "scene/3d/physics/character_body_3d.h"
#endif
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

namespace TestNode3D {

static Node3D *attach_root_node() {
	Node3D *node = memnew(Node3D);
	SceneTree::get_singleton()->get_root()->add_child(node);
	return node;
}

static void free_root_node(Node3D *p_node) {
	SceneTree::get_singleton()->get_root()->remove_child(p_node);
	memdelete(p_node);
}

TEST_CASE("[SceneTree][Node3D] Detached node does not report visible in tree") {
	Node3D *node = memnew(Node3D);
	CHECK(node->is_visible());
	CHECK_FALSE(node->is_visible_in_tree());
	memdelete(node);
}

TEST_CASE("[SceneTree][Node3D] Detached child does not report visible in tree") {
	Node3D *parent = memnew(Node3D);
	Node3D *child = memnew(Node3D);
	parent->add_child(child);
	CHECK_FALSE(parent->is_visible_in_tree());
	CHECK_FALSE(child->is_visible_in_tree());
	memdelete(parent);
}

TEST_CASE("[SceneTree][Node3D] Root becomes visible on entering scene tree") {
	Node3D *parent = attach_root_node();
	CHECK(parent->is_visible_in_tree());
	free_root_node(parent);
}

TEST_CASE("[SceneTree][Node3D] Parent visibility propagates to child") {
	Node3D *parent = attach_root_node();
	Node3D *child = memnew(Node3D);
	parent->add_child(child);
	CHECK(child->is_visible_in_tree());
	parent->hide();
	CHECK_FALSE(child->is_visible_in_tree());
	parent->show();
	CHECK(child->is_visible_in_tree());
	free_root_node(parent);
}

TEST_CASE("[SceneTree][Node3D] Child visibility is independent of parent local state") {
	Node3D *parent = attach_root_node();
	Node3D *child = memnew(Node3D);
	parent->add_child(child);
	child->hide();
	CHECK(parent->is_visible_in_tree());
	CHECK_FALSE(child->is_visible_in_tree());
	child->show();
	CHECK(child->is_visible_in_tree());
	free_root_node(parent);
}

TEST_CASE("[SceneTree][Node3D] Three generations propagate ancestor visibility") {
	Node3D *parent = attach_root_node();
	Node3D *child = memnew(Node3D);
	Node3D *grandchild = memnew(Node3D);
	parent->add_child(child);
	child->add_child(grandchild);
	CHECK(grandchild->is_visible_in_tree());
	parent->hide();
	CHECK_FALSE(grandchild->is_visible_in_tree());
	parent->show();
	CHECK(grandchild->is_visible_in_tree());
	free_root_node(parent);
}

TEST_CASE("[SceneTree][Node3D] Hiding intermediate ancestor keeps grandchild hidden") {
	Node3D *parent = attach_root_node();
	Node3D *child = memnew(Node3D);
	Node3D *grandchild = memnew(Node3D);
	parent->add_child(child);
	child->add_child(grandchild);
	child->hide();
	parent->hide();
	parent->show();
	CHECK_FALSE(grandchild->is_visible_in_tree());
	child->show();
	CHECK(grandchild->is_visible_in_tree());
	free_root_node(parent);
}

TEST_CASE("[SceneTree][Node3D] Detached subtree resets visibility and reenter restores it") {
	Node3D *parent = attach_root_node();
	Node3D *child = memnew(Node3D);
	parent->add_child(child);
	CHECK(child->is_visible_in_tree());
	SceneTree::get_singleton()->get_root()->remove_child(parent);
	CHECK_FALSE(parent->is_visible_in_tree());
	CHECK_FALSE(child->is_visible_in_tree());
	SceneTree::get_singleton()->get_root()->add_child(parent);
	CHECK(parent->is_visible_in_tree());
	CHECK(child->is_visible_in_tree());
	free_root_node(parent);
}

TEST_CASE("[SceneTree][Node3D] Child moved out of scene no longer claims visible") {
	Node3D *parent = attach_root_node();
	Node3D *child = memnew(Node3D);
	parent->add_child(child);
	CHECK(child->is_visible_in_tree());
	parent->remove_child(child);
	CHECK_FALSE(child->is_visible_in_tree());
	memdelete(child);
	free_root_node(parent);
}

TEST_CASE("[SceneTree][Node3D] Deep hierarchy follows hidden root") {
	Node3D *parent = attach_root_node();
	Node3D *node = parent;
	for (int i = 0; i < 64; i++) {
		Node3D *next = memnew(Node3D);
		node->add_child(next);
		node = next;
	}
	CHECK(node->is_visible_in_tree());
	parent->hide();
	CHECK_FALSE(node->is_visible_in_tree());
	parent->show();
	CHECK(node->is_visible_in_tree());
	free_root_node(parent);
}

TEST_CASE("[SceneTree][Node3D] Visibility remains false while parent is hidden and child toggles") {
	Node3D *parent = attach_root_node();
	Node3D *child = memnew(Node3D);
	parent->add_child(child);
	parent->hide();
	child->hide();
	child->show();
	CHECK_FALSE(child->is_visible_in_tree());
	parent->show();
	CHECK(child->is_visible_in_tree());
	free_root_node(parent);
}


#ifndef PHYSICS_3D_DISABLED
TEST_CASE("[CharacterBodySlideFastPath] CharacterBody3D no-collision queries preserve nil semantics") {
	CharacterBody3D *body = memnew(CharacterBody3D);
	CHECK_EQ(body->get_slide_collision_count(), 0);
	Variant last = body->call(SNAME("get_last_slide_collision"));
	CHECK_EQ(last.get_type(), Variant::NIL);
	ERR_PRINT_OFF;
	Variant invalid = body->call(SNAME("get_slide_collision"), 0);
	ERR_PRINT_ON;
	CHECK_EQ(invalid.get_type(), Variant::NIL);
	CHECK_EQ(body->get_slide_collision_count(), 0);
	memdelete(body);
}

TEST_CASE("[CharacterBodySlideFastPath] CharacterBody3D repeated missing collision requests allocate no result") {
	CharacterBody3D *body = memnew(CharacterBody3D);
	ERR_PRINT_OFF;
	for (int i = 0; i < 32; i++) {
		const Variant result = body->call(SNAME("get_slide_collision"), 0);
		CHECK_EQ(result.get_type(), Variant::NIL);
	}
	ERR_PRINT_ON;
	CHECK_EQ(body->get_slide_collision_count(), 0);
	memdelete(body);
}
#endif // PHYSICS_3D_DISABLED

} // namespace TestNode3D

#endif // _3D_DISABLED
