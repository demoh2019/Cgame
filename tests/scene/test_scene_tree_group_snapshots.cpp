/**************************************************************************/
/*  test_scene_tree_group_snapshots.cpp                                   */
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

TEST_FORCE_LINK(test_scene_tree_group_snapshots)

#include "core/templates/vector.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

namespace TestSceneTreeGroupSnapshots {

static constexpr int GROUP_TEST_NOTIFICATION = 25111;

class GroupProbe : public Node {
	GDCLASS(GroupProbe, Node);

protected:
	static void _bind_methods() {}

	void _notification(int p_what) {
		if (p_what != GROUP_TEST_NOTIFICATION) {
			return;
		}
		notification_count++;
		if (order) {
			order->push_back(index);
		}
		if (!did_mutate && remove_target && add_target) {
			did_mutate = true;
			remove_target->remove_from_group(group_name);
			add_target->add_to_group(group_name);
		}
	}

public:
	int index = 0;
	int notification_count = 0;
	Vector<int> *order = nullptr;
	GroupProbe *remove_target = nullptr;
	GroupProbe *add_target = nullptr;
	StringName group_name;
	bool did_mutate = false;
};

TEST_CASE("[SceneTreeGroupCOW] Script-visible group snapshot retains order and type") {
	SceneTree *tree = SceneTree::get_singleton();
	Node *parent = memnew(Node);
	tree->get_root()->add_child(parent);
	const StringName group = "test_group_snapshot_typed_linear";
	Vector<Node *> nodes;
	for (int i = 0; i < 256; i++) {
		Node *node = memnew(Node);
		node->set_name("GroupItem" + itos(i));
		parent->add_child(node);
		node->add_to_group(group);
		nodes.push_back(node);
	}

	// The script-exposed method builds a TypedArray<Node>, unlike the
	// native get_nodes_in_group() method, which returns Vector<Node *>.
	Array snapshot = tree->call("get_nodes_in_group", group);
	REQUIRE_EQ(snapshot.size(), 256);
	CHECK(snapshot.is_typed());
	for (int i = 0; i < 256; i++) {
		CHECK_EQ(Object::cast_to<Node>(snapshot[i]), nodes[i]);
	}

	nodes[100]->remove_from_group(group);
	Array updated = tree->call("get_nodes_in_group", group);
	REQUIRE_EQ(updated.size(), 255);
	for (int i = 0; i < updated.size(); i++) {
		CHECK_EQ(Object::cast_to<Node>(updated[i]), nodes[i < 100 ? i : i + 1]);
	}
	// The old returned array still contains the original snapshot.
	CHECK_EQ(Object::cast_to<Node>(snapshot[100]), nodes[100]);
	memdelete(parent);
	CHECK_EQ(tree->get_node_count_in_group(group), 0);
}

TEST_CASE("[SceneTreeGroupCOW] Snapshot reads share backing storage until a mutation") {
	Vector<int> nodes;
	for (int i = 0; i < 4096; i++) {
		nodes.push_back(i);
	}
	Vector<int> snapshot = nodes;

	// A const read should not allocate or copy the group's underlying array.
	CHECK(snapshot.ptr() == nodes.ptr());
	CHECK(snapshot[0] == 0);
	CHECK(snapshot[4095] == 4095);
	CHECK(snapshot.ptr() == nodes.ptr());

	// A membership change forks only the source while preserving the snapshot.
	nodes.push_back(4096);
	CHECK(snapshot.ptr() != nodes.ptr());
	CHECK(snapshot.size() == 4096);
	CHECK(nodes.size() == 4097);
	for (int i = 0; i < snapshot.size(); i++) {
		CHECK(snapshot[i] == i);
	}
}

TEST_CASE("[SceneTreeGroupCOW] Dispatch skips removed members and defers new members") {
	SceneTree *tree = SceneTree::get_singleton();
	Node *root = tree->get_root();
	const StringName group = "test_group_cow_mutation";

	GroupProbe *first = memnew(GroupProbe);
	GroupProbe *removed = memnew(GroupProbe);
	GroupProbe *added = memnew(GroupProbe);
	root->add_child(first);
	root->add_child(removed);
	root->add_child(added);
	first->add_to_group(group);
	removed->add_to_group(group);

	first->group_name = group;
	first->remove_target = removed;
	first->add_target = added;

	tree->notify_group(group, GROUP_TEST_NOTIFICATION);
	CHECK(first->notification_count == 1);
	CHECK(removed->notification_count == 0);
	CHECK(added->notification_count == 0);
	CHECK(tree->get_node_count_in_group(group) == 2);

	tree->notify_group(group, GROUP_TEST_NOTIFICATION);
	CHECK(first->notification_count == 2);
	CHECK(removed->notification_count == 0);
	CHECK(added->notification_count == 1);

	memdelete(first);
	memdelete(removed);
	memdelete(added);
	CHECK(tree->get_node_count_in_group(group) == 0);
}

TEST_CASE("[SceneTreeGroupCOW] Reverse and forward notifications keep tree order") {
	SceneTree *tree = SceneTree::get_singleton();
	Node *root = tree->get_root();
	const StringName group = "test_group_cow_order";
	GroupProbe *nodes[3] = { memnew(GroupProbe), memnew(GroupProbe), memnew(GroupProbe) };
	Vector<int> order;
	for (int i = 0; i < 3; i++) {
		root->add_child(nodes[i]);
		nodes[i]->add_to_group(group);
		nodes[i]->index = i;
		nodes[i]->order = &order;
	}

	tree->notify_group_flags(SceneTree::GROUP_CALL_DEFAULT, group, GROUP_TEST_NOTIFICATION);
	CHECK(order.size() == 3);
	for (int i = 0; i < 3; i++) {
		CHECK(order[i] == i);
	}

	order.clear();
	tree->notify_group_flags(SceneTree::GROUP_CALL_REVERSE, group, GROUP_TEST_NOTIFICATION);
	CHECK(order.size() == 3);
	for (int i = 0; i < 3; i++) {
		CHECK(order[i] == 2 - i);
	}
	for (GroupProbe *node : nodes) {
		memdelete(node);
	}
}

TEST_CASE("[SceneTreeGroupCOW] Repeated call_group and set_group dispatch") {
	SceneTree *tree = SceneTree::get_singleton();
	Node *root = tree->get_root();
	const StringName group = "test_group_cow_set_and_call";
	GroupProbe *nodes[3] = { memnew(GroupProbe), memnew(GroupProbe), memnew(GroupProbe) };
	for (GroupProbe *node : nodes) {
		root->add_child(node);
		node->add_to_group(group);
	}

	tree->set_group(group, "process_priority", 17);
	for (GroupProbe *node : nodes) {
		CHECK(node->get_process_priority() == 17);
	}
	tree->call_group(group, "set_process_priority", 23);
	for (GroupProbe *node : nodes) {
		CHECK(node->get_process_priority() == 23);
	}
	for (GroupProbe *node : nodes) {
		memdelete(node);
	}
	CHECK(tree->get_node_count_in_group(group) == 0);
}

} // namespace TestSceneTreeGroupSnapshots
