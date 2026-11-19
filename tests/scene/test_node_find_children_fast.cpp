/**************************************************************************/
/*  test_node_find_children_fast.cpp                                      */
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

TEST_FORCE_LINK(test_node_find_children_fast)

#include "scene/2d/node_2d.h"
#include "scene/main/node.h"

namespace TestNodeFindChildrenFast {

TEST_CASE("[NodeFindChildrenFast] Recursive results retain depth-first tree ordering") {
	Node *root = memnew(Node);
	Node *left = memnew(Node);
	Node *left_child = memnew(Node);
	Node *right = memnew(Node);
	Node *right_child = memnew(Node);
	left->set_name("Left");
	left_child->set_name("LeftChild");
	right->set_name("Right");
	right_child->set_name("RightChild");

	root->add_child(left);
	left->add_child(left_child);
	root->add_child(right);
	right->add_child(right_child);

	TypedArray<Node> found = root->find_children("*", "", true, false);
	REQUIRE_EQ(found.size(), 4);
	CHECK_EQ(Object::cast_to<Node>(found[0]), left);
	CHECK_EQ(Object::cast_to<Node>(found[1]), left_child);
	CHECK_EQ(Object::cast_to<Node>(found[2]), right);
	CHECK_EQ(Object::cast_to<Node>(found[3]), right_child);

	memdelete(root);
}

TEST_CASE("[NodeFindChildrenFast] Nonrecursive lookup excludes grandchildren") {
	Node *root = memnew(Node);
	Node *child = memnew(Node);
	Node *grandchild = memnew(Node);
	child->set_name("Child");
	grandchild->set_name("Grandchild");
	root->add_child(child);
	child->add_child(grandchild);

	TypedArray<Node> direct = root->find_children("*", "", false, false);
	REQUIRE_EQ(direct.size(), 1);
	CHECK_EQ(Object::cast_to<Node>(direct[0]), child);
	TypedArray<Node> all = root->find_children("*", "", true, false);
	REQUIRE_EQ(all.size(), 2);
	CHECK_EQ(Object::cast_to<Node>(all[1]), grandchild);
	memdelete(root);
}

TEST_CASE("[NodeFindChildrenFast] Name and built-in type filters work together") {
	Node *root = memnew(Node);
	Node2D *match = memnew(Node2D);
	Node2D *wrong_name = memnew(Node2D);
	Node *wrong_type = memnew(Node);
	match->set_name("EnemyOne");
	wrong_name->set_name("Friendly");
	wrong_type->set_name("EnemyTwo");
	root->add_child(match);
	root->add_child(wrong_name);
	root->add_child(wrong_type);

	TypedArray<Node> found = root->find_children("Enemy*", "Node2D", true, false);
	REQUIRE_EQ(found.size(), 1);
	CHECK_EQ(Object::cast_to<Node>(found[0]), match);
	TypedArray<Node> by_type = root->find_children("", "Node2D", true, false);
	REQUIRE_EQ(by_type.size(), 2);
	CHECK_EQ(Object::cast_to<Node>(by_type[0]), match);
	CHECK_EQ(Object::cast_to<Node>(by_type[1]), wrong_name);
	memdelete(root);
}

TEST_CASE("[NodeFindChildrenFast] Owned-only lookup excludes unowned subtrees") {
	Node *root = memnew(Node);
	Node *owned = memnew(Node);
	Node *unowned = memnew(Node);
	Node *descendant = memnew(Node);
	owned->set_name("Owned");
	unowned->set_name("Unowned");
	descendant->set_name("Descendant");
	root->add_child(owned);
	root->add_child(unowned);
	unowned->add_child(descendant);
	owned->set_owner(root);
	descendant->set_owner(root);

	TypedArray<Node> all = root->find_children("*", "", true, false);
	REQUIRE_EQ(all.size(), 3);
	TypedArray<Node> owned_only = root->find_children("*", "", true, true);
	REQUIRE_EQ(owned_only.size(), 1);
	CHECK_EQ(Object::cast_to<Node>(owned_only[0]), owned);
	memdelete(root);
}

TEST_CASE("[NodeFindChildrenFast] Empty input rejected and missing matches empty") {
	Node *root = memnew(Node);
	Node *child = memnew(Node);
	root->add_child(child);
	ERR_PRINT_OFF;
	TypedArray<Node> invalid = root->find_children("", "", true, false);
	ERR_PRINT_ON;
	CHECK(invalid.is_empty());
	TypedArray<Node> missing = root->find_children("does_not_exist*", "", true, false);
	CHECK(missing.is_empty());
	memdelete(root);
}

TEST_CASE("[NodeFindChildrenFast] Repeated queries and mutations are independent") {
	Node *root = memnew(Node);
	for (int i = 0; i < 128; i++) {
		Node *child = memnew(Node);
		child->set_name("Child" + itos(i));
		root->add_child(child);
	}
	TypedArray<Node> first = root->find_children("Child*", "", true, false);
	REQUIRE_EQ(first.size(), 128);
	TypedArray<Node> second = root->find_children("Child*", "", true, false);
	REQUIRE_EQ(second.size(), 128);
	CHECK_EQ(Object::cast_to<Node>(first[0]), Object::cast_to<Node>(second[0]));

	Node *extra = memnew(Node);
	extra->set_name("ChildExtra");
	root->add_child(extra);
	TypedArray<Node> third = root->find_children("Child*", "", true, false);
	REQUIRE_EQ(third.size(), 129);
	CHECK_EQ(first.size(), 128);
	CHECK_EQ(Object::cast_to<Node>(third[128]), extra);
	memdelete(root);
}

} // namespace TestNodeFindChildrenFast
