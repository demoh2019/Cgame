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
/* CLAIM, DAMAGES OR OTHER DEALINGS IN THE SOFTWARE.                     */
/**************************************************************************/

#pragma once

#include "../behavior_tree.h"
#include "tests/test_macros.h"

namespace TestBehaviorTree {

Dictionary make_condition(const String &p_key, const Variant &p_expected) {
	Dictionary node;
	node["type"] = "condition";
	node["key"] = p_key;
	node["equals"] = p_expected;
	return node;
}

Dictionary make_set(const String &p_key, const Variant &p_value) {
	Dictionary node;
	node["type"] = "set";
	node["key"] = p_key;
	node["value"] = p_value;
	return node;
}

Dictionary make_wait(int p_ticks) {
	Dictionary node;
	node["type"] = "wait";
	node["ticks"] = p_ticks;
	return node;
}

Dictionary make_composite(const String &p_type, const Array &p_children) {
	Dictionary node;
	node["type"] = p_type;
	node["children"] = p_children;
	return node;
}

TEST_CASE("[BehaviorTree] Empty tree fails without side effects") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	CHECK(bt->tick() == BehaviorTree::FAILURE);
	CHECK_FALSE(bt->has_blackboard_value("anything"));
}

TEST_CASE("[BehaviorTree] Sequence maintains running progress") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array children;
	children.push_back(make_wait(2));
	children.push_back(make_set("action", "attack"));
	REQUIRE(bt->set_tree(make_composite("sequence", children)));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK_FALSE(bt->has_blackboard_value("action"));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("action") == "attack");
	bt->clear_blackboard();
	CHECK(bt->tick() == BehaviorTree::RUNNING); // Starts anew after success.
}

TEST_CASE("[BehaviorTree] Selector short circuits and chooses fallback") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array children;
	children.push_back(make_condition("enemy_visible", true));
	children.push_back(make_set("action", "patrol"));
	REQUIRE(bt->set_tree(make_composite("selector", children)));
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("action") == "patrol");
	bt->clear_blackboard();
	bt->set_blackboard_value("enemy_visible", true);
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK_FALSE(bt->has_blackboard_value("action"));
}

TEST_CASE("[BehaviorTree] Selector fails when every child fails") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array children;
	children.push_back(make_condition("a", true));
	children.push_back(make_condition("b", true));
	REQUIRE(bt->set_tree(make_composite("selector", children)));
	CHECK(bt->tick() == BehaviorTree::FAILURE);
}

TEST_CASE("[BehaviorTree] Sequence fails when a condition fails") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array children;
	children.push_back(make_set("step", 1));
	children.push_back(make_condition("allowed", true));
	children.push_back(make_set("step", 2));
	REQUIRE(bt->set_tree(make_composite("sequence", children)));
	CHECK(bt->tick() == BehaviorTree::FAILURE);
	CHECK(bt->get_blackboard_value("step") == 1);
}

TEST_CASE("[BehaviorTree] Inverter flips success and failure, not running") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Dictionary inverted;
	inverted["type"] = "inverter";
	inverted["child"] = make_condition("enemy_visible", true);
	REQUIRE(bt->set_tree(inverted));
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	bt->set_blackboard_value("enemy_visible", true);
	CHECK(bt->tick() == BehaviorTree::FAILURE);

	inverted["child"] = make_wait(1);
	REQUIRE(bt->set_tree(inverted));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::FAILURE);
}

TEST_CASE("[BehaviorTree] Wait ticks and reset are deterministic") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	REQUIRE(bt->set_tree(make_wait(2)));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	bt->reset();
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	REQUIRE(bt->set_tree(make_wait(0)));
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
}

TEST_CASE("[BehaviorTree] Independent instances never share memory or blackboards") {
	Ref<BehaviorTree> a;
	a.instantiate();
	Ref<BehaviorTree> b;
	b.instantiate();
	const Dictionary definition = make_wait(1);
	REQUIRE(a->set_tree(definition));
	REQUIRE(b->set_tree(definition));
	CHECK(a->tick() == BehaviorTree::RUNNING);
	CHECK(a->tick() == BehaviorTree::SUCCESS);
	CHECK(b->tick() == BehaviorTree::RUNNING);
	a->set_blackboard_value("owner", "a");
	CHECK_FALSE(b->has_blackboard_value("owner"));
}

TEST_CASE("[BehaviorTree] Tree descriptions are deeply copied") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array children;
	children.push_back(make_condition("alive", true));
	Dictionary tree = make_composite("sequence", children);
	REQUIRE(bt->set_tree(tree));
	children.clear();
	CHECK(bt->get_tree().has("children"));
	bt->set_blackboard_value("alive", true);
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	Dictionary retrieved = bt->get_tree();
	retrieved["type"] = "invalid";
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
}

TEST_CASE("[BehaviorTree] Invalid definitions are rejected without replacing previous tree") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	REQUIRE(bt->set_tree(make_set("ok", true)));
	ERR_PRINT_OFF;
	Dictionary wrong_type;
	wrong_type["type"] = "unknown";
	CHECK_FALSE(bt->set_tree(wrong_type));
	Dictionary empty_seq = make_composite("sequence", Array());
	CHECK_FALSE(bt->set_tree(empty_seq));
	CHECK_FALSE(bt->set_tree(make_wait(-1)));
	Dictionary no_key;
	no_key["type"] = "condition";
	CHECK_FALSE(bt->set_tree(no_key));
	ERR_PRINT_ON;
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("ok") == true);
}

TEST_CASE("[BehaviorTree] Excessive nesting is rejected") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Dictionary deepest = make_set("a", 1);
	for (int i = 0; i < 35; i++) {
		Dictionary inverse;
		inverse["type"] = "inverter";
		inverse["child"] = deepest;
		deepest = inverse;
	}
	ERR_PRINT_OFF;
	CHECK_FALSE(bt->set_tree(deepest));
	ERR_PRINT_ON;
}

TEST_CASE("[BehaviorTree] Blackboard fallback and clear") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	CHECK(bt->get_blackboard_value("missing", 42) == 42);
	bt->set_blackboard_value("score", 12);
	CHECK(bt->get_blackboard_value("score", 0) == 12);
	bt->clear_blackboard();
	CHECK_FALSE(bt->has_blackboard_value("score"));
}

} // namespace TestBehaviorTree
