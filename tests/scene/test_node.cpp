/**************************************************************************/
/*  test_node.cpp                                                         */
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

TEST_FORCE_LINK(test_node)

#include "core/config/project_settings.h"
#include "core/io/file_access.h"
#include "core/io/resource_saver.h"
#include "core/object/class_db.h"
#include "core/object/callable_mp.h"
#include "core/object/undo_redo.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/packed_scene.h"
#include "tests/test_utils.h"

namespace TestNode {

class TestNode : public Node {
	GDCLASS(TestNode, Node);

protected:
	void _notification(int p_what) {
		switch (p_what) {
			case NOTIFICATION_INTERNAL_PROCESS: {
				internal_process_counter++;
				push_self();
			} break;
			case NOTIFICATION_INTERNAL_PHYSICS_PROCESS: {
				internal_physics_process_counter++;
				push_self();
			} break;
			case NOTIFICATION_PROCESS: {
				process_counter++;
				push_self();
			} break;
			case NOTIFICATION_PHYSICS_PROCESS: {
				physics_process_counter++;
				push_self();
			} break;
		}
	}

	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("set_exported_node", "node"), &TestNode::set_exported_node);
		ClassDB::bind_method(D_METHOD("get_exported_node"), &TestNode::get_exported_node);
		ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "exported_node", PROPERTY_HINT_NODE_TYPE, "Node"), "set_exported_node", "get_exported_node");

		ClassDB::bind_method(D_METHOD("set_exported_nodes", "node"), &TestNode::set_exported_nodes);
		ClassDB::bind_method(D_METHOD("get_exported_nodes"), &TestNode::get_exported_nodes);
		ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "exported_nodes", PROPERTY_HINT_TYPE_STRING, "24/34:Node"), "set_exported_nodes", "get_exported_nodes");
	}

private:
	void push_self() {
		if (callback_list) {
			callback_list->push_back(this);
		}
	}

public:
	int internal_process_counter = 0;
	int internal_physics_process_counter = 0;
	int process_counter = 0;
	int physics_process_counter = 0;

	Node *exported_node = nullptr;
	Array exported_nodes;

	List<Node *> *callback_list = nullptr;

	void set_exported_node(Node *p_node) { exported_node = p_node; }
	Node *get_exported_node() const { return exported_node; }

	void set_exported_nodes(const Array &p_nodes) { exported_nodes = p_nodes; }
	Array get_exported_nodes() const { return exported_nodes; }

	TestNode() {
		Node *internal = memnew(Node);
		add_child(internal, false, INTERNAL_MODE_FRONT);
		internal = memnew(Node);
		add_child(internal, false, INTERNAL_MODE_BACK);
	}
};

TEST_CASE("[SceneTree][Node] Testing node operations with a very simple scene tree") {
	Node *node = memnew(Node);

	// Check initial scene tree setup.
	CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 0);
	CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 1);

	// Check initial node setup.
	CHECK(node->get_name() == StringName());
	CHECK_FALSE(node->is_inside_tree());
	CHECK_EQ(node->get_parent(), nullptr);
	ERR_PRINT_OFF;
	CHECK(node->get_path().is_empty());
	ERR_PRINT_ON;
	CHECK_EQ(node->get_child_count(), 0);

	SceneTree::get_singleton()->get_root()->add_child(node);

	CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 1);
	CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 2);

	CHECK(node->get_name() != StringName());
	CHECK(node->is_inside_tree());
	CHECK_EQ(SceneTree::get_singleton()->get_root(), node->get_parent());
	CHECK_FALSE(node->get_path().is_empty());
	CHECK_EQ(node->get_child_count(), 0);

	SUBCASE("Node should be accessible as first child") {
		Node *child = SceneTree::get_singleton()->get_root()->get_child(0);
		CHECK_EQ(child, node);
	}

	SUBCASE("Node should be accessible via the node path") {
		Node *child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(node->get_path());
		CHECK_EQ(child_by_path, node);

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(NodePath("Node"));
		CHECK_EQ(child_by_path, nullptr);

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(NodePath("/root/Node"));
		CHECK_EQ(child_by_path, nullptr);

		node->set_name("Node");

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(node->get_path());
		CHECK_EQ(child_by_path, node);

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(NodePath("Node"));
		CHECK_EQ(child_by_path, node);

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(NodePath("/root/Node"));
		CHECK_EQ(child_by_path, node);
	}

	SUBCASE("Node should be accessible via group") {
		Vector<Node *> nodes = SceneTree::get_singleton()->get_nodes_in_group("nodes");
		CHECK(nodes.is_empty());

		node->add_to_group("nodes");

		nodes = SceneTree::get_singleton()->get_nodes_in_group("nodes");
		CHECK_EQ(nodes.size(), 1);
		Node *E = nodes.get(0);
		CHECK_EQ(E, node);
	}

	SUBCASE("Node should be possible to find") {
		Node *child = SceneTree::get_singleton()->get_root()->find_child("Node", true, false);
		CHECK_EQ(child, nullptr);

		node->set_name("Node");

		child = SceneTree::get_singleton()->get_root()->find_child("Node", true, false);
		CHECK_EQ(child, node);
	}

	SUBCASE("Node should be possible to remove") {
		SceneTree::get_singleton()->get_root()->remove_child(node);

		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 0);
		CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 1);

		CHECK_FALSE(node->is_inside_tree());
		CHECK_EQ(node->get_parent(), nullptr);
		ERR_PRINT_OFF;
		CHECK(node->get_path().is_empty());
		ERR_PRINT_ON;
	}

	SUBCASE("Node should be possible to move") {
		SceneTree::get_singleton()->get_root()->move_child(node, 0);

		Node *child = SceneTree::get_singleton()->get_root()->get_child(0);
		CHECK_EQ(child, node);
		CHECK(node->is_inside_tree());
	}

	SUBCASE("Node should be possible to reparent") {
		node->reparent(SceneTree::get_singleton()->get_root());

		Node *child = SceneTree::get_singleton()->get_root()->get_child(0);
		CHECK_EQ(child, node);
		CHECK(node->is_inside_tree());
	}

	SUBCASE("Node should be possible to duplicate") {
		node->set_name("MyName");

		Node *duplicate = node->duplicate();

		CHECK_FALSE(node == duplicate);
		CHECK_FALSE(duplicate->is_inside_tree());
		CHECK_EQ(duplicate->get_name(), node->get_name());

		memdelete(duplicate);
	}

	memdelete(node);
}

TEST_CASE("[SceneTree][Node] Testing node operations with a more complex simple scene tree") {
	Node *node1 = memnew(Node);
	Node *node2 = memnew(Node);
	Node *node1_1 = memnew(Node);
	Node *root = SceneTree::get_singleton()->get_root();

	root->add_child(node1);
	root->add_child(node2);

	node1->add_child(node1_1);

	CHECK(node1_1->is_inside_tree());
	CHECK_EQ(node1_1->get_parent(), node1);
	CHECK_EQ(node1->get_child_count(), 1);

	CHECK_EQ(root->is_ancestor_of(node1), true);
	CHECK_EQ(root->is_ancestor_of(node2), true);
	CHECK_EQ(root->is_ancestor_of(node1_1), true);
	CHECK_EQ(node1->is_ancestor_of(node1), false);
	CHECK_EQ(node1->is_ancestor_of(node1_1), true);
	CHECK_EQ(node2->is_ancestor_of(node1_1), false);
	CHECK_EQ(node2->is_ancestor_of(node1), false);

	CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 2);
	CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 4);

	SUBCASE("Nodes should be accessible via get_child(..)") {
		Node *child1 = SceneTree::get_singleton()->get_root()->get_child(0);
		CHECK_EQ(child1, node1);

		Node *child2 = SceneTree::get_singleton()->get_root()->get_child(1);
		CHECK_EQ(child2, node2);

		Node *child1_1 = node1->get_child(0);
		CHECK_EQ(child1_1, node1_1);
	}

	SUBCASE("Removed nodes should also remove their children from the scene tree") {
		// Should also remove node1_1 from the scene tree.
		SceneTree::get_singleton()->get_root()->remove_child(node1);

		CHECK_EQ(node1->get_child_count(), 1);

		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 1);
		CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 2);

		// First child should now be the second node.
		Node *child1 = SceneTree::get_singleton()->get_root()->get_child(0);
		CHECK_EQ(child1, node2);
	}

	SUBCASE("Removed children nodes should not affect their parent in the scene tree") {
		node1->remove_child(node1_1);

		CHECK_EQ(node1_1->get_parent(), nullptr);
		CHECK_EQ(node1->get_child_count(), 0);

		CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 3);
	}

	SUBCASE("Nodes should be in the expected order when a node is moved to the back") {
		SceneTree::get_singleton()->get_root()->move_child(node1, 1);

		Node *child1 = SceneTree::get_singleton()->get_root()->get_child(0);
		CHECK_EQ(child1, node2);

		Node *child2 = SceneTree::get_singleton()->get_root()->get_child(1);
		CHECK_EQ(child2, node1);
	}

	SUBCASE("Nodes should be in the expected order when a node is moved to the front") {
		SceneTree::get_singleton()->get_root()->move_child(node2, 0);

		Node *child1 = SceneTree::get_singleton()->get_root()->get_child(0);
		CHECK_EQ(child1, node2);

		Node *child2 = SceneTree::get_singleton()->get_root()->get_child(1);
		CHECK_EQ(child2, node1);
	}

	SUBCASE("Nodes should be in the expected order when reparented (remove/add)") {
		CHECK_EQ(node2->get_child_count(), 0);

		node1->remove_child(node1_1);
		CHECK_EQ(node1->get_child_count(), 0);
		CHECK_EQ(node1_1->get_parent(), nullptr);

		node2->add_child(node1_1);
		CHECK_EQ(node2->get_child_count(), 1);
		CHECK_EQ(node1_1->get_parent(), node2);

		Node *child = node2->get_child(0);
		CHECK_EQ(child, node1_1);

		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 2);
		CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 4);
	}

	SUBCASE("Nodes should be in the expected order when reparented") {
		CHECK_EQ(node2->get_child_count(), 0);

		node1_1->reparent(node2);

		CHECK_EQ(node1->get_child_count(), 0);
		CHECK_EQ(node2->get_child_count(), 1);
		CHECK_EQ(node1_1->get_parent(), node2);

		Node *child = node2->get_child(0);
		CHECK_EQ(child, node1_1);

		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 2);
		CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 4);
	}

	SUBCASE("Nodes should be possible to find") {
		Node *child = SceneTree::get_singleton()->get_root()->find_child("NestedNode", true, false);
		CHECK_EQ(child, nullptr);

		TypedArray<Node> children = SceneTree::get_singleton()->get_root()->find_children("NestedNode", "", true, false);
		CHECK_EQ(children.size(), 0);

		node1->set_name("Node1");
		node2->set_name("Node2");
		node1_1->set_name("NestedNode");

		child = SceneTree::get_singleton()->get_root()->find_child("NestedNode", true, false);
		CHECK_EQ(child, node1_1);

		children = SceneTree::get_singleton()->get_root()->find_children("NestedNode", "", true, false);
		CHECK_EQ(children.size(), 1);
		CHECK_EQ(Object::cast_to<Node>(children[0]), node1_1);

		// First node that matches with the name is node1.
		child = SceneTree::get_singleton()->get_root()->find_child("Node?", true, false);
		CHECK_EQ(child, node1);

		children = SceneTree::get_singleton()->get_root()->find_children("Node?", "", true, false);
		CHECK_EQ(children.size(), 2);
		CHECK_EQ(Object::cast_to<Node>(children[0]), node1);
		CHECK_EQ(Object::cast_to<Node>(children[1]), node2);

		SceneTree::get_singleton()->get_root()->move_child(node2, 0);

		// It should be node2, as it is now the first one in the tree.
		child = SceneTree::get_singleton()->get_root()->find_child("Node?", true, false);
		CHECK_EQ(child, node2);

		children = SceneTree::get_singleton()->get_root()->find_children("Node?", "", true, false);
		CHECK_EQ(children.size(), 2);
		CHECK_EQ(Object::cast_to<Node>(children[0]), node2);
		CHECK_EQ(Object::cast_to<Node>(children[1]), node1);
	}

	SUBCASE("Nodes should be accessible via their node path") {
		Node *child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(node1->get_path());
		CHECK_EQ(child_by_path, node1);

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(node2->get_path());
		CHECK_EQ(child_by_path, node2);

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(node1_1->get_path());
		CHECK_EQ(child_by_path, node1_1);

		node1->set_name("Node1");
		node1_1->set_name("NestedNode");

		child_by_path = node1->get_node_or_null(NodePath("NestedNode"));
		CHECK_EQ(child_by_path, node1_1);

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(NodePath("/root/Node1/NestedNode"));
		CHECK_EQ(child_by_path, node1_1);

		child_by_path = SceneTree::get_singleton()->get_root()->get_node_or_null(NodePath("Node1/NestedNode"));
		CHECK_EQ(child_by_path, node1_1);
	}

	SUBCASE("Nodes should be accessible via their groups") {
		Vector<Node *> nodes = SceneTree::get_singleton()->get_nodes_in_group("nodes");
		CHECK(nodes.is_empty());

		nodes = SceneTree::get_singleton()->get_nodes_in_group("other_nodes");
		CHECK(nodes.is_empty());

		node1->add_to_group("nodes");
		node2->add_to_group("other_nodes");
		node1_1->add_to_group("nodes");
		node1_1->add_to_group("other_nodes");

		nodes = SceneTree::get_singleton()->get_nodes_in_group("nodes");
		CHECK_EQ(nodes.size(), 2);

		Node *E = nodes.get(0);
		CHECK_EQ(E, node1);
		E = nodes.get(1);
		CHECK_EQ(E, node1_1);

		// Clear and try again with the other group.
		nodes.clear();

		nodes = SceneTree::get_singleton()->get_nodes_in_group("other_nodes");
		CHECK_EQ(nodes.size(), 2);

		E = nodes.get(0);
		CHECK_EQ(E, node1_1);
		E = nodes.get(1);
		CHECK_EQ(E, node2);

		// Clear and try again with the other group and one node removed.
		nodes.clear();

		node1->remove_from_group("nodes");
		nodes = SceneTree::get_singleton()->get_nodes_in_group("nodes");
		CHECK_EQ(nodes.size(), 1);

		E = nodes.get(0);
		CHECK_EQ(E, node1_1);
	}

	SUBCASE("Nodes added as siblings of another node should be right next to it") {
		node1->remove_child(node1_1);

		node1->add_sibling(node1_1);

		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 3);
		CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 4);

		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child(0), node1);
		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child(1), node1_1);
		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child(2), node2);
	}

	SUBCASE("Replaced nodes should be be removed and the replacing node added") {
		SceneTree::get_singleton()->get_root()->remove_child(node2);

		node1->replace_by(node2);

		CHECK_EQ(SceneTree::get_singleton()->get_root()->get_child_count(), 1);
		CHECK_EQ(SceneTree::get_singleton()->get_node_count(), 3);

		CHECK_FALSE(node1->is_inside_tree());
		CHECK(node2->is_inside_tree());

		CHECK_EQ(node1->get_parent(), nullptr);
		CHECK_EQ(node2->get_parent(), SceneTree::get_singleton()->get_root());
		CHECK_EQ(node2->get_child_count(), 1);
		CHECK_EQ(node2->get_child(0), node1_1);
	}

	SUBCASE("Replacing nodes should keep the groups of the replaced nodes") {
		SceneTree::get_singleton()->get_root()->remove_child(node2);

		node1->add_to_group("nodes");
		node1->replace_by(node2, true);

		Vector<Node *> nodes = SceneTree::get_singleton()->get_nodes_in_group("nodes");
		CHECK_EQ(nodes.size(), 1);

		Node *E = nodes.get(0);
		CHECK_EQ(E, node2);
	}

	SUBCASE("Duplicating a node should also duplicate the children") {
		node1->set_name("MyName1");
		node1_1->set_name("MyName1_1");
		Node *duplicate1 = node1->duplicate();

		CHECK_EQ(duplicate1->get_child_count(), node1->get_child_count());
		Node *duplicate1_1 = duplicate1->get_child(0);

		CHECK_EQ(duplicate1_1->get_child_count(), node1_1->get_child_count());

		CHECK_EQ(duplicate1->get_name(), node1->get_name());
		CHECK_EQ(duplicate1_1->get_name(), node1_1->get_name());

		CHECK_FALSE(duplicate1->is_inside_tree());
		CHECK_FALSE(duplicate1_1->is_inside_tree());

		memdelete(duplicate1_1);
		memdelete(duplicate1);
	}

	memdelete(node1_1);
	memdelete(node1);
	memdelete(node2);
}

TEST_CASE("[SceneTree][Node] Duplicating node with internal children") {
	GDREGISTER_CLASS(TestNode);

	TestNode *node = memnew(TestNode);
	Node *child = memnew(Node);
	child->set_name("Child");
	node->add_child(child);

	int child_count = node->get_child_count();

	Node *dup = node->duplicate();
	CHECK(dup->get_child_count() == child_count);
	CHECK(dup->has_node(String("Child")));

	memdelete(node);
	memdelete(dup);
}

TEST_CASE("[SceneTree][Node]Exported node checks") {
	TestNode *node = memnew(TestNode);
	SceneTree::get_singleton()->get_root()->add_child(node);

	Node *child = memnew(Node);
	child->set_name("Child");
	node->add_child(child);
	child->set_owner(node);

	Node *child2 = memnew(Node);
	child2->set_name("Child2");
	node->add_child(child2);
	child2->set_owner(node);

	Array children;
	children.append(child);

	node->set("exported_node", child);
	node->set("exported_nodes", children);

	SUBCASE("Property of duplicated node should point to duplicated child") {
		GDREGISTER_CLASS(TestNode);

		TestNode *dup = Object::cast_to<TestNode>(node->duplicate());
		Node *new_exported = Object::cast_to<Node>(dup->get("exported_node"));
		CHECK(new_exported == dup->get_child(0, false));

		memdelete(dup);
	}

#ifdef TOOLS_ENABLED
	SUBCASE("Saving instance with exported nodes should not store the unchanged property") {
		Ref<PackedScene> ps;
		ps.instantiate();
		ps->pack(node);

		String scene_path = TestUtils::get_temp_path("test_scene.tscn");
		ps->set_path(scene_path);

		Node *root = memnew(Node);

		Node *sub_child = ps->instantiate(PackedScene::GEN_EDIT_STATE_MAIN);
		root->add_child(sub_child);
		sub_child->set_owner(root);

		Ref<PackedScene> ps2;
		ps2.instantiate();
		ps2->pack(root);

		scene_path = TestUtils::get_temp_path("new_test_scene.tscn");
		ResourceSaver::save(ps2, scene_path);
		memdelete(root);

		bool is_wrong = false;
		Ref<FileAccess> fa = FileAccess::open(scene_path, FileAccess::READ);
		while (!fa->eof_reached()) {
			const String line = fa->get_line();
			if (line.begins_with("exported_node")) {
				// The property was saved, while it shouldn't.
				is_wrong = true;
				break;
			}
		}
		CHECK_FALSE(is_wrong);
	}

	SUBCASE("Saving instance with exported nodes should store property if changed") {
		Ref<PackedScene> ps;
		ps.instantiate();
		ps->pack(node);

		String scene_path = TestUtils::get_temp_path("test_scene.tscn");
		ps->set_path(scene_path);

		Node *root = memnew(Node);

		Node *sub_child = ps->instantiate(PackedScene::GEN_EDIT_STATE_MAIN);
		root->add_child(sub_child);
		sub_child->set_owner(root);

		sub_child->set("exported_node", sub_child->get_child(1, false));

		children = Array();
		children.append(sub_child->get_child(1, false));
		sub_child->set("exported_nodes", children);

		Ref<PackedScene> ps2;
		ps2.instantiate();
		ps2->pack(root);

		scene_path = TestUtils::get_temp_path("new_test_scene2.tscn");
		ResourceSaver::save(ps2, scene_path);
		memdelete(root);

		int stored_properties = 0;
		Ref<FileAccess> fa = FileAccess::open(scene_path, FileAccess::READ);
		while (!fa->eof_reached()) {
			const String line = fa->get_line();
			if (line.begins_with("exported_node")) {
				stored_properties++;
			}
		}
		CHECK_EQ(stored_properties, 2);
	}
#endif // TOOLS_ENABLED

	memdelete(node);
}

TEST_CASE("[Node] Processing checks") {
	Node *node = memnew(Node);

	SUBCASE("Processing") {
		CHECK_FALSE(node->is_processing());

		node->set_process(true);

		CHECK(node->is_processing());

		node->set_process(false);

		CHECK_FALSE(node->is_processing());
	}

	SUBCASE("Physics processing") {
		CHECK_FALSE(node->is_physics_processing());

		node->set_physics_process(true);

		CHECK(node->is_physics_processing());

		node->set_physics_process(false);

		CHECK_FALSE(node->is_physics_processing());
	}

	SUBCASE("Unhandled input processing") {
		CHECK_FALSE(node->is_processing_unhandled_input());

		node->set_process_unhandled_input(true);

		CHECK(node->is_processing_unhandled_input());

		node->set_process_unhandled_input(false);

		CHECK_FALSE(node->is_processing_unhandled_input());
	}

	SUBCASE("Input processing") {
		CHECK_FALSE(node->is_processing_input());

		node->set_process_input(true);

		CHECK(node->is_processing_input());

		node->set_process_input(false);

		CHECK_FALSE(node->is_processing_input());
	}

	SUBCASE("Unhandled key input processing") {
		CHECK_FALSE(node->is_processing_unhandled_key_input());

		node->set_process_unhandled_key_input(true);

		CHECK(node->is_processing_unhandled_key_input());

		node->set_process_unhandled_key_input(false);

		CHECK_FALSE(node->is_processing_unhandled_key_input());
	}

	SUBCASE("Shortcut input processing") {
		CHECK_FALSE(node->is_processing_shortcut_input());

		node->set_process_shortcut_input(true);

		CHECK(node->is_processing_shortcut_input());

		node->set_process_shortcut_input(false);

		CHECK_FALSE(node->is_processing_shortcut_input());
	}

	SUBCASE("Internal processing") {
		CHECK_FALSE(node->is_processing_internal());

		node->set_process_internal(true);

		CHECK(node->is_processing_internal());

		node->set_process_internal(false);

		CHECK_FALSE(node->is_processing_internal());
	}

	SUBCASE("Process priority") {
		CHECK_EQ(0, node->get_process_priority());

		node->set_process_priority(1);

		CHECK_EQ(1, node->get_process_priority());
	}

	SUBCASE("Physics process priority") {
		CHECK_EQ(0, node->get_physics_process_priority());

		node->set_physics_process_priority(1);

		CHECK_EQ(1, node->get_physics_process_priority());
	}

	memdelete(node);
}

TEST_CASE("[SceneTree][Node] Test the processing") {
	TestNode *node = memnew(TestNode);
	SceneTree::get_singleton()->get_root()->add_child(node);

	SUBCASE("No process") {
		CHECK_EQ(0, node->process_counter);
		CHECK_EQ(0, node->physics_process_counter);
	}

	SUBCASE("Process") {
		node->set_process(true);
		SceneTree::get_singleton()->process(0);

		CHECK_EQ(1, node->process_counter);
		CHECK_EQ(0, node->physics_process_counter);
		CHECK_EQ(0, node->internal_process_counter);
		CHECK_EQ(0, node->internal_physics_process_counter);
	}

	SUBCASE("Physics process") {
		node->set_physics_process(true);
		SceneTree::get_singleton()->physics_process(0);

		CHECK_EQ(0, node->process_counter);
		CHECK_EQ(1, node->physics_process_counter);
		CHECK_EQ(0, node->internal_process_counter);
		CHECK_EQ(0, node->internal_physics_process_counter);
	}

	SUBCASE("Normal and physics process") {
		node->set_process(true);
		node->set_physics_process(true);
		SceneTree::get_singleton()->process(0);
		SceneTree::get_singleton()->physics_process(0);

		CHECK_EQ(1, node->process_counter);
		CHECK_EQ(1, node->physics_process_counter);
		CHECK_EQ(0, node->internal_process_counter);
		CHECK_EQ(0, node->internal_physics_process_counter);
	}

	SUBCASE("Internal, normal and physics process") {
		node->set_process_internal(true);
		node->set_physics_process_internal(true);
		SceneTree::get_singleton()->process(0);
		SceneTree::get_singleton()->physics_process(0);

		CHECK_EQ(0, node->process_counter);
		CHECK_EQ(0, node->physics_process_counter);
		CHECK_EQ(1, node->internal_process_counter);
		CHECK_EQ(1, node->internal_physics_process_counter);
	}

	SUBCASE("All processing") {
		node->set_process(true);
		node->set_physics_process(true);
		node->set_process_internal(true);
		node->set_physics_process_internal(true);
		SceneTree::get_singleton()->process(0);
		SceneTree::get_singleton()->physics_process(0);

		CHECK_EQ(1, node->process_counter);
		CHECK_EQ(1, node->physics_process_counter);
		CHECK_EQ(1, node->internal_process_counter);
		CHECK_EQ(1, node->internal_physics_process_counter);
	}

	SUBCASE("All processing twice") {
		node->set_process(true);
		node->set_physics_process(true);
		node->set_process_internal(true);
		node->set_physics_process_internal(true);
		SceneTree::get_singleton()->process(0);
		SceneTree::get_singleton()->physics_process(0);
		SceneTree::get_singleton()->process(0);
		SceneTree::get_singleton()->physics_process(0);

		CHECK_EQ(2, node->process_counter);
		CHECK_EQ(2, node->physics_process_counter);
		CHECK_EQ(2, node->internal_process_counter);
		CHECK_EQ(2, node->internal_physics_process_counter);
	}

	SUBCASE("Enable and disable processing") {
		node->set_process(true);
		node->set_physics_process(true);
		node->set_process_internal(true);
		node->set_physics_process_internal(true);
		SceneTree::get_singleton()->process(0);
		SceneTree::get_singleton()->physics_process(0);

		node->set_process(false);
		node->set_physics_process(false);
		node->set_process_internal(false);
		node->set_physics_process_internal(false);
		SceneTree::get_singleton()->process(0);
		SceneTree::get_singleton()->physics_process(0);

		CHECK_EQ(1, node->process_counter);
		CHECK_EQ(1, node->physics_process_counter);
		CHECK_EQ(1, node->internal_process_counter);
		CHECK_EQ(1, node->internal_physics_process_counter);
	}

	memdelete(node);
}

static Node *make_node(const StringName &p_name, Node *p_parent, Node *p_owner = nullptr) {
	Node *n = memnew(Node);
	n->set_name(p_name);
	if (p_parent) {
		p_parent->add_child(n);
	}
	if (p_owner) {
		n->set_owner(p_owner);
	}
	return n;
}

TEST_CASE("[SceneTree][Node] get_path_to") {
	/*
		root              Scene 1 [   C0
		 |                        [   |
		 A1         B1            [   C1
		 |          |             [   |
		 A2         B2            [   %C2
		/  \       /  \           [  /  \
	   A3  A4     B3  B4          [ C3  C4 ] Scene 2
	   |    |     |    |          [ |    | ]
	   A5  A6     B5  B6          [ %C5 C6 ]
	*/
	Node *a1 = make_node("A1", SceneTree::get_singleton()->get_root());
	Node *a2 = make_node("A2", a1);
	Node *a3 = make_node("A3", a2);
	Node *a4 = make_node("A4", a2);
	Node *a5 = make_node("A5", a3);
	Node *a6 = make_node("A6", a4);

	Node *b1 = make_node("B1", nullptr);
	Node *b2 = make_node("B2", b1);
	Node *b3 = make_node("B3", b2);
	Node *b4 = make_node("B4", b2);
	Node *b5 = make_node("B5", b3);
	Node *b6 = make_node("B6", b4);

	Node *c0 = make_node("C0", nullptr);
	Node *c1 = make_node("C1", c0, c0);
	Node *c2 = make_node("C2", c1, c0);
	c2->set_unique_name_in_owner(true);
	Node *c3 = make_node("C3", c2, c0);
	Node *c4 = make_node("C4", c2, c0);
	Node *c5 = make_node("C5", c3, c0);
	c5->set_unique_name_in_owner(true);
	Node *c6 = make_node("C6", c4, c4);

	SUBCASE("Path to self") {
		CHECK_EQ(a1->get_path_to(a1), NodePath("."));
		CHECK_EQ(b3->get_path_to(b3), NodePath("."));
		CHECK_EQ(c6->get_path_to(c6, true), NodePath("."));
		CHECK_EQ(c2->get_path_to(c2, true), NodePath("."));
	}

	SUBCASE("Path to child") {
		CHECK_EQ(b1->get_path_to(b5), NodePath("B2/B3/B5"));
		CHECK_EQ(b2->get_path_to(b6), NodePath("B4/B6"));
		CHECK_EQ(b4->get_path_to(b6), NodePath("B6"));

		CHECK_EQ(a1->get_path_to(a5), NodePath("A2/A3/A5"));
		CHECK_EQ(a2->get_path_to(a6), NodePath("A4/A6"));
		CHECK_EQ(a4->get_path_to(a6), NodePath("A6"));

		CHECK_EQ(c1->get_path_to(c3, true), NodePath("%C2/C3"));
		CHECK_EQ(c1->get_path_to(c6, true), NodePath("%C2/C4/C6"));

		CHECK_EQ(c1->get_path_to(c5, true), NodePath("%C5"));
		CHECK_EQ(c2->get_path_to(c5, true), NodePath("%C5"));
		CHECK_EQ(c3->get_path_to(c5, true), NodePath("%C5"));
	}

	SUBCASE("Path to parent") {
		CHECK_EQ(b5->get_path_to(b1), NodePath("../../.."));
		CHECK_EQ(b6->get_path_to(b2), NodePath("../.."));
		CHECK_EQ(b6->get_path_to(b4), NodePath(".."));

		CHECK_EQ(a5->get_path_to(a1), NodePath("../../.."));
		CHECK_EQ(a6->get_path_to(a2), NodePath("../.."));
		CHECK_EQ(a6->get_path_to(a4), NodePath(".."));

		// Questionable behavior, but that's how it was originally implemented.
		CHECK_EQ(c5->get_path_to(c2, true), NodePath("%C5/../.."));
		CHECK_EQ(c5->get_path_to(c3, true), NodePath("%C5/.."));

		CHECK_EQ(c6->get_path_to(c2, true), NodePath("../.."));
	}

	SUBCASE("Path to sibling") {
		CHECK_EQ(b3->get_path_to(b4), NodePath("../B4"));
		CHECK_EQ(b4->get_path_to(b5), NodePath("../B3/B5"));
		CHECK_EQ(b5->get_path_to(b6), NodePath("../../B4/B6"));
		CHECK_EQ(b5->get_path_to(b4), NodePath("../../B4"));

		CHECK_EQ(a3->get_path_to(a4), NodePath("../A4"));
		CHECK_EQ(a4->get_path_to(a5), NodePath("../A3/A5"));
		CHECK_EQ(a5->get_path_to(a6), NodePath("../../A4/A6"));
		CHECK_EQ(a5->get_path_to(a4), NodePath("../../A4"));

		// Questionable behavior, but that's how it was originally implemented.
		CHECK_EQ(c5->get_path_to(c6, true), NodePath("%C5/../../C4/C6"));

		CHECK_EQ(c6->get_path_to(c5, true), NodePath("../../C3/C5"));
		CHECK_EQ(c3->get_path_to(c4, true), NodePath("../C4"));
		CHECK_EQ(c4->get_path_to(c3, true), NodePath("../C3"));
		CHECK_EQ(c4->get_path_to(c5, true), NodePath("%C5"));
	}

	SUBCASE("No common ancestor") {
		ERR_PRINT_OFF
		CHECK_EQ(b1->get_path_to(a1), NodePath());
		CHECK_EQ(a1->get_path_to(b2, true), NodePath());
		CHECK_EQ(b6->get_path_to(a2), NodePath());
		CHECK_EQ(a5->get_path_to(b1, true), NodePath());
		CHECK_EQ(b3->get_path_to(SceneTree::get_singleton()->get_root()), NodePath());
		CHECK_EQ(b1->get_path_to(SceneTree::get_singleton()->get_root(), true), NodePath());
		CHECK_EQ(c1->get_path_to(b1), NodePath());
		CHECK_EQ(b3->get_path_to(c6), NodePath());
		ERR_PRINT_ON
	}

	memdelete(c0);
	memdelete(a1);
	memdelete(b1);
}


TEST_CASE("[SceneTree][Node] find_common_parent_with") {
	Node *a = memnew(Node);
	a->set_name("Root");
	Node *left = make_node("Left", a);
	Node *right = make_node("Right", a);
	Node *deep = make_node("Deep", left);
	Node *b = memnew(Node);
	Node *different = make_node("Different", b);

	CHECK(deep->find_common_parent_with(right) == a);
	CHECK(right->find_common_parent_with(deep) == a);
	CHECK(deep->find_common_parent_with(left) == left);
	CHECK(left->find_common_parent_with(deep) == left);
	CHECK(deep->find_common_parent_with(deep) == deep);
	CHECK(deep->find_common_parent_with(different) == nullptr);
	CHECK(different->find_common_parent_with(deep) == nullptr);
	CHECK(a->find_common_parent_with(nullptr) == nullptr);
	CHECK_EQ(a->calculate_depth(), 1);
	CHECK_EQ(left->calculate_depth(), 2);
	CHECK_EQ(deep->calculate_depth(), 3);
	CHECK_EQ(different->calculate_depth(), 2);

	memdelete(a);
	memdelete(b);
}

TEST_CASE("[SceneTree][Node] get_path_to supports 128-level chains without HashSet") {
	Node *root = memnew(Node);
	root->set_name("Root");
	Node *leaf = root;
	String child_path;
	String parent_path;
	for (int i = 0; i < 128; i++) {
		leaf = make_node("Child", leaf);
		if (i > 0) {
			child_path += "/";
			parent_path += "/";
		}
		child_path += "Child";
		parent_path += "..";
	}
	CHECK_EQ(leaf->calculate_depth(), 129);
	CHECK_EQ(root->get_path_to(leaf), NodePath(child_path));
	CHECK_EQ(leaf->get_path_to(root), NodePath(parent_path));
	memdelete(root);
}

TEST_CASE("[SceneTree][Node] Test the process priority") {
	List<Node *> process_order;

	TestNode *node = memnew(TestNode);
	node->callback_list = &process_order;
	SceneTree::get_singleton()->get_root()->add_child(node);

	TestNode *node2 = memnew(TestNode);
	node2->callback_list = &process_order;
	SceneTree::get_singleton()->get_root()->add_child(node2);

	TestNode *node3 = memnew(TestNode);
	node3->callback_list = &process_order;
	SceneTree::get_singleton()->get_root()->add_child(node3);

	TestNode *node4 = memnew(TestNode);
	node4->callback_list = &process_order;
	SceneTree::get_singleton()->get_root()->add_child(node4);

	SUBCASE("Process priority") {
		node->set_process(true);
		node->set_process_priority(20);
		node2->set_process(true);
		node2->set_process_priority(10);
		node3->set_process(true);
		node3->set_process_priority(40);
		node4->set_process(true);
		node4->set_process_priority(30);

		SceneTree::get_singleton()->process(0);

		CHECK_EQ(4, process_order.size());
		List<Node *>::Element *E = process_order.front();
		CHECK_EQ(E->get(), node2);
		E = E->next();
		CHECK_EQ(E->get(), node);
		E = E->next();
		CHECK_EQ(E->get(), node4);
		E = E->next();
		CHECK_EQ(E->get(), node3);
	}

	SUBCASE("Physics process priority") {
		node->set_physics_process(true);
		node->set_physics_process_priority(20);
		node2->set_physics_process(true);
		node2->set_physics_process_priority(10);
		node3->set_physics_process(true);
		node3->set_physics_process_priority(40);
		node4->set_physics_process(true);
		node4->set_physics_process_priority(30);

		SceneTree::get_singleton()->physics_process(0);

		CHECK_EQ(4, process_order.size());
		List<Node *>::Element *E = process_order.front();
		CHECK_EQ(E->get(), node2);
		E = E->next();
		CHECK_EQ(E->get(), node);
		E = E->next();
		CHECK_EQ(E->get(), node4);
		E = E->next();
		CHECK_EQ(E->get(), node3);
	}

	memdelete(node);
	memdelete(node2);
	memdelete(node3);
	memdelete(node4);
}


static void commit_placeholder_action(UndoRedo *p_history, Node *p_node, bool p_enabled) {
	p_history->create_action("Toggle Load as Placeholder");
	p_history->add_do_method(callable_mp(p_node, &Node::set_scene_instance_load_placeholder).bind(p_enabled));
	p_history->add_undo_method(callable_mp(p_node, &Node::set_scene_instance_load_placeholder).bind(!p_enabled));
	p_history->commit_action();
}

TEST_CASE("[Node][PlaceholderUndo] Enable placeholder can be undone and redone") {
	Node *node = memnew(Node);
	UndoRedo *history = memnew(UndoRedo);
	CHECK_FALSE(node->get_scene_instance_load_placeholder());
	commit_placeholder_action(history, node, true);
	CHECK(node->get_scene_instance_load_placeholder());
	CHECK(history->get_history_count() == 1);
	history->undo();
	CHECK_FALSE(node->get_scene_instance_load_placeholder());
	history->redo();
	CHECK(node->get_scene_instance_load_placeholder());
	memdelete(history);
	memdelete(node);
}

TEST_CASE("[Node][PlaceholderUndo] Disable placeholder restores previous state on undo") {
	Node *node = memnew(Node);
	node->set_scene_instance_load_placeholder(true);
	UndoRedo *history = memnew(UndoRedo);
	commit_placeholder_action(history, node, false);
	CHECK_FALSE(node->get_scene_instance_load_placeholder());
	history->undo();
	CHECK(node->get_scene_instance_load_placeholder());
	history->redo();
	CHECK_FALSE(node->get_scene_instance_load_placeholder());
	memdelete(history);
	memdelete(node);
}

TEST_CASE("[Node][PlaceholderUndo] Multi-selection toggles atomically") {
	Node *first = memnew(Node);
	Node *second = memnew(Node);
	UndoRedo *history = memnew(UndoRedo);
	history->create_action("Toggle Load as Placeholder", UndoRedo::MERGE_DISABLE);
	Node *nodes[] = { first, second };
	for (Node *node : nodes) {
		history->add_do_method(callable_mp(node, &Node::set_scene_instance_load_placeholder).bind(true));
		history->add_undo_method(callable_mp(node, &Node::set_scene_instance_load_placeholder).bind(false));
	}
	history->commit_action();
	CHECK(first->get_scene_instance_load_placeholder());
	CHECK(second->get_scene_instance_load_placeholder());
	CHECK(history->get_history_count() == 1);
	history->undo();
	CHECK_FALSE(first->get_scene_instance_load_placeholder());
	CHECK_FALSE(second->get_scene_instance_load_placeholder());
	history->redo();
	CHECK(first->get_scene_instance_load_placeholder());
	CHECK(second->get_scene_instance_load_placeholder());
	memdelete(history);
	memdelete(first);
	memdelete(second);
}

TEST_CASE("[Node][PlaceholderUndo] Repeated toggles retain separate undo actions") {
	Node *node = memnew(Node);
	UndoRedo *history = memnew(UndoRedo);
	const uint64_t initial_version = history->get_version();
	commit_placeholder_action(history, node, true);
	commit_placeholder_action(history, node, false);
	CHECK_FALSE(node->get_scene_instance_load_placeholder());
	CHECK(history->get_history_count() == 2);
	CHECK(history->get_version() == initial_version + 2);
	history->undo();
	CHECK(node->get_scene_instance_load_placeholder());
	history->undo();
	CHECK_FALSE(node->get_scene_instance_load_placeholder());
	history->redo();
	CHECK(node->get_scene_instance_load_placeholder());
	memdelete(history);
	memdelete(node);
}

TEST_CASE("[SceneTree][Node] find_children iterative traversal preserves node ordering and ownership") {
	Node *root = memnew(Node);

	Node *front = memnew(Node);
	front->set_name("Front");
	root->add_child(front, false, Node::INTERNAL_MODE_FRONT);

	Node *branch_a = memnew(Node);
	branch_a->set_name("BranchA");
	root->add_child(branch_a);

	Node *leaf_a = memnew(Node);
	leaf_a->set_name("LeafA");
	branch_a->add_child(leaf_a);

	Node *deep_a = memnew(Node);
	deep_a->set_name("DeepA");
	leaf_a->add_child(deep_a);

	Node *branch_b = memnew(Node);
	branch_b->set_name("BranchB");
	root->add_child(branch_b);

	Node *leaf_b = memnew(Node);
	leaf_b->set_name("LeafB");
	branch_b->add_child(leaf_b);

	Node *back = memnew(Node);
	back->set_name("Back");
	root->add_child(back, false, Node::INTERNAL_MODE_BACK);

	TypedArray<Node> all = root->find_children("*", "", true, false);
	REQUIRE(all.size() == 7);
	CHECK(Object::cast_to<Node>(all[0]) == front);
	CHECK(Object::cast_to<Node>(all[1]) == branch_a);
	CHECK(Object::cast_to<Node>(all[2]) == leaf_a);
	CHECK(Object::cast_to<Node>(all[3]) == deep_a);
	CHECK(Object::cast_to<Node>(all[4]) == branch_b);
	CHECK(Object::cast_to<Node>(all[5]) == leaf_b);
	CHECK(Object::cast_to<Node>(all[6]) == back);

	TypedArray<Node> shallow = root->find_children("*", "", false, false);
	REQUIRE(shallow.size() == 4);
	CHECK(Object::cast_to<Node>(shallow[0]) == front);
	CHECK(Object::cast_to<Node>(shallow[1]) == branch_a);
	CHECK(Object::cast_to<Node>(shallow[2]) == branch_b);
	CHECK(Object::cast_to<Node>(shallow[3]) == back);

	branch_a->set_owner(root);
	leaf_a->set_owner(root);
	deep_a->set_owner(root);
	branch_b->set_owner(root);
	// Leave internal nodes and leaf_b unowned.
	TypedArray<Node> owned = root->find_children("*", "", true, true);
	REQUIRE(owned.size() == 4);
	CHECK(Object::cast_to<Node>(owned[0]) == branch_a);
	CHECK(Object::cast_to<Node>(owned[1]) == leaf_a);
	CHECK(Object::cast_to<Node>(owned[2]) == deep_a);
	CHECK(Object::cast_to<Node>(owned[3]) == branch_b);

	TypedArray<Node> name_filtered = root->find_children("Branch*", "", true, false);
	REQUIRE(name_filtered.size() == 2);
	CHECK(Object::cast_to<Node>(name_filtered[0]) == branch_a);
	CHECK(Object::cast_to<Node>(name_filtered[1]) == branch_b);
	CHECK(root->find_children("*", "Node3D", true, false).is_empty());

	memdelete(root);
}

TEST_CASE("[SceneTree][Node] find_children iterative traversal handles deep scene trees") {
	Node *root = memnew(Node);
	Node *parent = root;
	Node *last = nullptr;
	for (int i = 0; i < 320; i++) {
		Node *child = memnew(Node);
		child->set_name("Nested_" + itos(i));
		parent->add_child(child);
		parent = child;
		last = child;
	}

	TypedArray<Node> descendants = root->find_children("Nested_*", "", true, false);
	REQUIRE(descendants.size() == 320);
	CHECK(Object::cast_to<Node>(descendants[0]) == root->get_child(0));
	CHECK(Object::cast_to<Node>(descendants[319]) == last);

	TypedArray<Node> immediate = root->find_children("*", "", false, false);
	REQUIRE(immediate.size() == 1);
	CHECK(Object::cast_to<Node>(immediate[0]) == root->get_child(0));

	memdelete(root);
}


TEST_CASE("[SceneTree][Node] find_children stackless with mixed internal children") {
	Node *root = memnew(Node);
	root->set_name("Root");
	Node *front = memnew(Node);
	front->set_name("ItemFront");
	root->add_child(front, false, Node::INTERNAL_MODE_FRONT);
	Node *a = memnew(Node);
	a->set_name("ItemA");
	root->add_child(a);
	Node *a1 = memnew(Node);
	a1->set_name("ItemA1");
	a->add_child(a1);
	Node *a2 = memnew(Node);
	a2->set_name("ItemA2");
	a->add_child(a2);
	Node *b = memnew(Node);
	b->set_name("ItemB");
	root->add_child(b);
	Node *b1 = memnew(Node);
	b1->set_name("ItemB1");
	b->add_child(b1);
	Node *back = memnew(Node);
	back->set_name("ItemBack");
	root->add_child(back, false, Node::INTERNAL_MODE_BACK);

	TypedArray<Node> recursive = root->find_children("Item*", "", true, false);
	REQUIRE_EQ(recursive.size(), 7);
	CHECK_EQ(Object::cast_to<Node>(recursive[0]), front);
	CHECK_EQ(Object::cast_to<Node>(recursive[1]), a);
	CHECK_EQ(Object::cast_to<Node>(recursive[2]), a1);
	CHECK_EQ(Object::cast_to<Node>(recursive[3]), a2);
	CHECK_EQ(Object::cast_to<Node>(recursive[4]), b);
	CHECK_EQ(Object::cast_to<Node>(recursive[5]), b1);
	CHECK_EQ(Object::cast_to<Node>(recursive[6]), back);

	TypedArray<Node> shallow = root->find_children("Item*", "", false, false);
	REQUIRE_EQ(shallow.size(), 4);
	CHECK_EQ(Object::cast_to<Node>(shallow[0]), front);
	CHECK_EQ(Object::cast_to<Node>(shallow[1]), a);
	CHECK_EQ(Object::cast_to<Node>(shallow[2]), b);
	CHECK_EQ(Object::cast_to<Node>(shallow[3]), back);
	memdelete(root);
}

TEST_CASE("[SceneTree][Node] find_children stackless skips unowned descendants") {
	Node *root = memnew(Node);
	root->set_name("Root");
	Node *owned = memnew(Node);
	owned->set_name("ItemOwned");
	root->add_child(owned);
	owned->set_owner(root);
	Node *nested = memnew(Node);
	nested->set_name("ItemNested");
	owned->add_child(nested);
	nested->set_owner(root);
	Node *hidden = memnew(Node);
	hidden->set_name("ItemUnowned");
	root->add_child(hidden);
	Node *skipped = memnew(Node);
	skipped->set_name("ItemSkipped");
	hidden->add_child(skipped);
	skipped->set_owner(root);
	Node *last = memnew(Node);
	last->set_name("ItemLast");
	root->add_child(last);
	last->set_owner(root);

	TypedArray<Node> owned_only = root->find_children("Item*", "", true, true);
	REQUIRE_EQ(owned_only.size(), 3);
	CHECK_EQ(Object::cast_to<Node>(owned_only[0]), owned);
	CHECK_EQ(Object::cast_to<Node>(owned_only[1]), nested);
	CHECK_EQ(Object::cast_to<Node>(owned_only[2]), last);
	TypedArray<Node> all = root->find_children("Item*", "", true, false);
	CHECK_EQ(all.size(), 5);
	memdelete(root);
}

TEST_CASE("[SceneTree][Node] find_children stackless handles deep branches") {
	Node *root = memnew(Node);
	root->set_name("Root");
	Node *head = memnew(Node);
	head->set_name("ItemHead");
	root->add_child(head);
	Node *leaf = head;
	for (int i = 0; i < 384; ++i) {
		Node *child = memnew(Node);
		child->set_name("Item" + itos(i));
		leaf->add_child(child);
		leaf = child;
	}
	Node *last = memnew(Node);
	last->set_name("ItemLast");
	root->add_child(last);
	TypedArray<Node> nodes = root->find_children("Item*", "", true, false);
	REQUIRE_EQ(nodes.size(), 386);
	CHECK_EQ(Object::cast_to<Node>(nodes[0]), head);
	CHECK_EQ(Object::cast_to<Node>(nodes[nodes.size() - 2]), leaf);
	CHECK_EQ(Object::cast_to<Node>(nodes[nodes.size() - 1]), last);
	memdelete(root);
}


TEST_CASE("[SceneTree][Node] Large mixed-mode children cache preserves index order") {
	Node *root = memnew(Node);
	Vector<Node *> front;
	Vector<Node *> regular;
	Vector<Node *> back;

	// Interleave additions to force the cache to be rebuilt while each
	// internal-mode index range remains dense.
	for (int i = 0; i < 128; i++) {
		Node *ordinary = memnew(Node);
		ordinary->set_name("Regular" + itos(i));
		root->add_child(ordinary);
		regular.push_back(ordinary);

		if (i < 32) {
			Node *internal_front = memnew(Node);
			internal_front->set_name("Front" + itos(i));
			root->add_child(internal_front, false, Node::INTERNAL_MODE_FRONT);
			front.push_back(internal_front);
		}
		if (i < 24) {
			Node *internal_back = memnew(Node);
			internal_back->set_name("Back" + itos(i));
			root->add_child(internal_back, false, Node::INTERNAL_MODE_BACK);
			back.push_back(internal_back);
		}
	}

	REQUIRE_EQ(root->get_child_count(true), 184);
	REQUIRE_EQ(root->get_child_count(false), 128);
	for (int i = 0; i < front.size(); i++) {
		CHECK_EQ(root->get_child(i, true), front[i]);
		CHECK_EQ(front[i]->get_index(), i);
	}
	for (int i = 0; i < regular.size(); i++) {
		CHECK_EQ(root->get_child(front.size() + i, true), regular[i]);
		CHECK_EQ(root->get_child(i, false), regular[i]);
		CHECK_EQ(regular[i]->get_index(), i);
	}
	for (int i = 0; i < back.size(); i++) {
		CHECK_EQ(root->get_child(front.size() + regular.size() + i, true), back[i]);
		CHECK_EQ(back[i]->get_index(), i);
	}

	// Removing middle nodes creates index gaps and triggers the legacy
	// comparison-based fallback, which must compact each mode correctly.
	for (int mode = 0; mode < 3; mode++) {
		Vector<Node *> *group = mode == 0 ? &front : (mode == 1 ? &regular : &back);
		const int middle = group->size() / 2;
		Node *removed = (*group)[middle];
		root->remove_child(removed);
		memdelete(removed);
		group->remove_at(middle);
	}
	REQUIRE_EQ(root->get_child_count(true), 181);
	REQUIRE_EQ(root->get_child_count(false), 127);
	for (int i = 0; i < front.size(); i++) {
		CHECK_EQ(root->get_child(i, true), front[i]);
	}
	for (int i = 0; i < regular.size(); i++) {
		CHECK_EQ(root->get_child(i, false), regular[i]);
		CHECK_EQ(root->get_child(front.size() + i, true), regular[i]);
	}
	for (int i = 0; i < back.size(); i++) {
		CHECK_EQ(root->get_child(front.size() + regular.size() + i, true), back[i]);
	}

	// A cache rebuild after new front-internal nodes should reuse the linear
	// path. Explicit moves continue to respect the public child ordering.
	Node *new_front = memnew(Node);
	new_front->set_name("FrontAppended");
	root->add_child(new_front, false, Node::INTERNAL_MODE_FRONT);
	front.push_back(new_front);
	Node *moved = regular[70];
	root->move_child(moved, 0);
	CHECK_EQ(root->get_child(0, false), moved);
	CHECK_EQ(root->get_child(front.size(), true), moved);
	CHECK_EQ(root->get_child(front.size() + 1, true), regular[0]);
	CHECK_EQ(root->get_child(root->get_child_count(true) - 1, true), back[back.size() - 1]);

	memdelete(root);
}


TEST_CASE("[SceneTree][Node] Move child shifts only the affected range and preserves child indices") {
	Node *root = memnew(Node);
	Vector<Node *> front;
	Vector<Node *> ordinary;
	Vector<Node *> back;
	for (int i = 0; i < 8; i++) {
		Node *child = memnew(Node);
		child->set_name("Front" + itos(i));
		root->add_child(child, false, Node::INTERNAL_MODE_FRONT);
		front.push_back(child);
	}
	for (int i = 0; i < 192; i++) {
		Node *child = memnew(Node);
		child->set_name("Ordinary" + itos(i));
		root->add_child(child);
		ordinary.push_back(child);
	}
	for (int i = 0; i < 8; i++) {
		Node *child = memnew(Node);
		child->set_name("Back" + itos(i));
		root->add_child(child, false, Node::INTERNAL_MODE_BACK);
		back.push_back(child);
	}

	// Use Vector as a simple reference model. Exercise adjacent moves
	// in both directions, distant moves and the one-past-end index.
	auto check_order = [&]() {
		CHECK_EQ(root->get_child_count(true), front.size() + ordinary.size() + back.size());
		CHECK_EQ(root->get_child_count(false), ordinary.size());
		int global_index = 0;
		for (int i = 0; i < front.size(); i++) {
			CHECK_EQ(root->get_child(global_index++, true), front[i]);
			CHECK_EQ(front[i]->get_index(), i);
		}
		for (int i = 0; i < ordinary.size(); i++) {
			CHECK_EQ(root->get_child(global_index++, true), ordinary[i]);
			CHECK_EQ(root->get_child(i, false), ordinary[i]);
			CHECK_EQ(ordinary[i]->get_index(), i);
		}
		for (int i = 0; i < back.size(); i++) {
			CHECK_EQ(root->get_child(global_index++, true), back[i]);
			CHECK_EQ(back[i]->get_index(), i);
		}
	};
	auto move = [&](Vector<Node *> &r_reference, int p_from, int p_to) {
		Node *child = r_reference[p_from];
		root->move_child(child, p_to);
		int normalized_to = p_to < 0 ? p_to + r_reference.size() : p_to;
		if (normalized_to == r_reference.size()) {
			normalized_to--;
		}
		r_reference.remove_at(p_from);
		r_reference.insert(normalized_to, child);
		check_order();
	};

	check_order();
	move(ordinary, 85, 86);
	move(ordinary, 86, 85);
	move(ordinary, 191, 0);
	move(ordinary, 0, 191);
	move(ordinary, 11, -1);
	move(ordinary, 0, ordinary.size());
	move(front, 3, 4);
	move(front, 0, 7);
	move(front, 7, 0);
	move(back, 3, 4);
	move(back, 0, 7);
	move(back, 7, 0);
	memdelete(root);
}

TEST_CASE("[SceneTree][Node] Exact child queries work with dirty traversal cache") {
	Node *root = memnew(Node);
	Vector<Node *> children;
	for (int i = 0; i < 512; i++) {
		Node *child = memnew(Node);
		child->set_name("Candidate" + itos(i));
		root->add_child(child);
		children.push_back(child);
	}

	// Removing a non-tail child invalidates the ordering cache.
	// Exact lookups must still use the authoritative name table.
	Node *deleted = children[3];
	root->remove_child(deleted);
	memdelete(deleted);
	TypedArray<Node> found = root->find_children("Candidate511", "Node", false, false);
	REQUIRE_EQ(found.size(), 1);
	CHECK_EQ(Object::cast_to<Node>(found[0]), children[511]);
	CHECK_EQ(root->find_children("Candidate3", "Node", false, false).size(), 0);
	CHECK_EQ(root->find_children("Missing", "Node", false, false).size(), 0);
	CHECK_EQ(root->find_children("Candidate511", "Node3D", false, false).size(), 0);

	// Ownership filtering must work without visiting unrelated children.
	CHECK_EQ(root->find_children("Candidate100", "Node", false, true).size(), 0);
	children[100]->set_owner(root);
	found = root->find_children("Candidate100", "Node", false, true);
	REQUIRE_EQ(found.size(), 1);
	CHECK_EQ(Object::cast_to<Node>(found[0]), children[100]);

	// Wildcard and recursive lookups still visit the ordered children.
	CHECK_EQ(root->find_children("Candidate51?", "Node", false, false).size(), 2);
	found = root->find_children("Candidate511", "Node", true, false);
	REQUIRE_EQ(found.size(), 1);
	CHECK_EQ(Object::cast_to<Node>(found[0]), children[511]);
	CHECK_EQ(root->get_child_count(), 511);
	CHECK_EQ(root->get_child(3), children[4]);
	memdelete(root);
}

TEST_CASE("[SceneTree][Node] Reparenting a large owned subtree preserves all descendant owners") {
	Node *root = memnew(Node);
	Node *left = memnew(Node);
	Node *right = memnew(Node);
	root->add_child(left);
	root->add_child(right);

	Node *branch = memnew(Node);
	left->add_child(branch);
	branch->set_owner(root);
	Vector<Node *> descendants;
	for (int i = 0; i < 128; i++) {
		Node *child = memnew(Node);
		child->set_name("Owned" + itos(i));
		branch->add_child(child);
		child->set_owner(root);
		descendants.push_back(child);
		Node *grandchild = memnew(Node);
		grandchild->set_name("Leaf");
		child->add_child(grandchild);
		grandchild->set_owner(root);
	}

	branch->reparent(right, false);
	CHECK_EQ(branch->get_parent(), right);
	CHECK_EQ(branch->get_owner(), root);
	CHECK_EQ(left->get_child_count(), 0);
	CHECK_EQ(right->get_child_count(), 1);
	CHECK_EQ(branch->get_child_count(false), 128);
	for (int i = 0; i < descendants.size(); i++) {
		Node *child = descendants[i];
		CHECK_EQ(branch->get_child(i), child);
		CHECK_EQ(child->get_owner(), root);
		CHECK_EQ(child->get_child_count(), 1);
		CHECK_EQ(child->get_child(0)->get_owner(), root);
	}

	memdelete(root);
}

TEST_CASE("[SceneTree][Node] Human-readable names carry long numeric suffixes") {
	Node *root = memnew(Node);
	String separator;
	switch (int(GLOBAL_GET("editor/naming/node_name_num_separator"))) {
		case 0: {
			separator = "";
		} break;
		case 1: {
			separator = " ";
		} break;
		case 2: {
			separator = "_";
		} break;
		case 3: {
			separator = "-";
		} break;
		default: {
			separator = " ";
		} break;
	}

	// A long suffix previously required one new string for every digit.
	const String nines = String("9").repeat(128);
	const String base_name = "OptimizedNode" + separator;
	Node *first = memnew(Node);
	first->set_name(base_name + nines);
	root->add_child(first, true);
	Node *second = memnew(Node);
	second->set_name(base_name + nines);
	root->add_child(second, true);
	CHECK_EQ(String(first->get_name()), base_name + nines);
	CHECK_EQ(String(second->get_name()), base_name + "1" + String("0").repeat(128));

	// Incrementing a suffix must retain its leading zeroes.
	Node *zero_first = memnew(Node);
	zero_first->set_name(base_name + "0099");
	root->add_child(zero_first, true);
	Node *zero_second = memnew(Node);
	zero_second->set_name(base_name + "0099");
	root->add_child(zero_second, true);
	CHECK_EQ(String(zero_second->get_name()), base_name + "0100");

	// No numeric suffix: numbering still starts at 2 and uses the configured
	// separator. Existing sibling names must remain unchanged.
	Node *plain_first = memnew(Node);
	plain_first->set_name("PlainNode");
	root->add_child(plain_first, true);
	Node *plain_second = memnew(Node);
	plain_second->set_name("PlainNode");
	root->add_child(plain_second, true);
	CHECK_EQ(String(plain_second->get_name()), "PlainNode" + separator + "2");

	memdelete(root);
}


TEST_CASE("[SceneTree][Node] Borrowed multi-component NodePath lookup preserves resolution") {
	Node *root = memnew(Node);
	root->set_name("LookupRoot");
	Node *parent = root;
	String relative_path;

	for (int i = 0; i < 96; i++) {
		Node *child = memnew(Node);
		const String name = i == 48 ? String(U"Unicode雪") : "Segment" + itos(i);
		child->set_name(name);
		parent->add_child(child);
		if (i != 0) {
			relative_path += "/";
		}
		relative_path += name;
		parent = child;
	}
	Node *leaf = parent;
	const NodePath deep_path(relative_path);
	const NodePath with_subname(relative_path + ":custom_property");
	const NodePath missing_path(relative_path + "/DoesNotExist");

	for (int repeat = 0; repeat < 256; repeat++) {
		CHECK_EQ(root->get_node_or_null(deep_path), leaf);
		CHECK_EQ(root->get_node_or_null(with_subname), leaf);
		CHECK_EQ(root->get_node_or_null(missing_path), nullptr);
	}
	CHECK_EQ(root->get_node_or_null(NodePath("Segment0")), root->get_child(0));
	CHECK_EQ(leaf->get_node_or_null(NodePath("..")), leaf->get_parent());
	CHECK_EQ(leaf->get_node_or_null(NodePath("../.")), leaf->get_parent());
	CHECK_EQ(root->get_node_or_null(NodePath(".")), root);

	memdelete(root);
}

} // namespace TestNode
