/**************************************************************************/
/*  test_behavior_tree.h                                                  */
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

TEST_CASE("[BehaviorTree] Sequence commits actions in child order") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array actions;
	actions.push_back(make_set("stage", 1));
	actions.push_back(make_condition("stage", 1));
	actions.push_back(make_set("stage", 2));
	actions.push_back(make_condition("stage", 2));
	REQUIRE(bt->set_tree(make_composite("sequence", actions)));
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("stage") == 2);
}

TEST_CASE("[BehaviorTree] Selector does not run later children after success") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array options;
	options.push_back(make_set("chosen", "first"));
	options.push_back(make_set("chosen", "second"));
	REQUIRE(bt->set_tree(make_composite("selector", options)));
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("chosen") == "first");
}

TEST_CASE("[BehaviorTree] A zero-length wait completes immediately on every tick") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	REQUIRE(bt->set_tree(make_wait(0)));
	for (int i = 0; i < 100; i++) {
		CHECK(bt->tick() == BehaviorTree::SUCCESS);
	}
}

TEST_CASE("[BehaviorTree] A running child postpones later sequence actions") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array stages;
	stages.push_back(make_set("phase", "before"));
	stages.push_back(make_wait(3));
	stages.push_back(make_set("phase", "after"));
	REQUIRE(bt->set_tree(make_composite("sequence", stages)));
	for (int i = 0; i < 3; i++) {
		CHECK(bt->tick() == BehaviorTree::RUNNING);
		CHECK(bt->get_blackboard_value("phase") == "before");
	}
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("phase") == "after");
}

TEST_CASE("[BehaviorTree] Selector resumes running child without taking fallback") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array choices;
	choices.push_back(make_wait(2));
	choices.push_back(make_set("fallback", true));
	REQUIRE(bt->set_tree(make_composite("selector", choices)));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK_FALSE(bt->has_blackboard_value("fallback"));
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK_FALSE(bt->has_blackboard_value("fallback"));
}

TEST_CASE("[BehaviorTree] Nested sequences resume across ticks") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array inner;
	inner.push_back(make_wait(1));
	inner.push_back(make_set("inner_done", true));
	Array outer;
	outer.push_back(make_composite("sequence", inner));
	outer.push_back(make_set("outer_done", true));
	REQUIRE(bt->set_tree(make_composite("sequence", outer)));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK_FALSE(bt->has_blackboard_value("inner_done"));
	CHECK_FALSE(bt->has_blackboard_value("outer_done"));
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("inner_done") == true);
	CHECK(bt->get_blackboard_value("outer_done") == true);
}

TEST_CASE("[BehaviorTree] Nested inverter pair preserves leaf status") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Dictionary first;
	first["type"] = "inverter";
	first["child"] = make_condition("ready", true);
	Dictionary second;
	second["type"] = "inverter";
	second["child"] = first;
	REQUIRE(bt->set_tree(second));
	CHECK(bt->tick() == BehaviorTree::FAILURE);
	bt->set_blackboard_value("ready", true);
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
}

TEST_CASE("[BehaviorTree] Missing and explicitly null blackboard values differ") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	REQUIRE(bt->set_tree(make_condition("optional", Variant())));
	CHECK(bt->tick() == BehaviorTree::FAILURE);
	bt->set_blackboard_value("optional", Variant());
	CHECK(bt->has_blackboard_value("optional"));
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	bt->clear_blackboard();
	CHECK(bt->tick() == BehaviorTree::FAILURE);
}

TEST_CASE("[BehaviorTree] Setting a blackboard value replaces the old value") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	bt->set_blackboard_value("mode", "idle");
	REQUIRE(bt->set_tree(make_set("mode", "run")));
	CHECK(bt->get_blackboard_value("mode") == "idle");
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("mode") == "run");
	CHECK(bt->get_blackboard_value("unrelated", "absent") == "absent");
}

TEST_CASE("[BehaviorTree] Reset does not discard blackboard data") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	REQUIRE(bt->set_tree(make_wait(3)));
	bt->set_blackboard_value("target", 123);
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	bt->reset();
	CHECK(bt->get_blackboard_value("target") == 123);
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
}

TEST_CASE("[BehaviorTree] Valid tree replacement discards execution memory") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	REQUIRE(bt->set_tree(make_wait(2)));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	bt->set_blackboard_value("persist", 77);
	REQUIRE(bt->set_tree(make_wait(1)));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("persist") == 77);
}

TEST_CASE("[BehaviorTree] Invalid replacement retains running progress") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	REQUIRE(bt->set_tree(make_wait(1)));
	CHECK(bt->tick() == BehaviorTree::RUNNING);
	Dictionary invalid;
	invalid["type"] = "not-a-node";
	ERR_PRINT_OFF;
	CHECK_FALSE(bt->set_tree(invalid));
	ERR_PRINT_ON;
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
}

TEST_CASE("[BehaviorTree] Invalid recursive children are rejected") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array children;
	children.push_back(make_wait(0));
	children.push_back(12);
	Dictionary invalid = make_composite("sequence", children);
	ERR_PRINT_OFF;
	CHECK_FALSE(bt->set_tree(invalid));
	Dictionary inverter;
	inverter["type"] = "inverter";
	inverter["child"] = 12;
	CHECK_FALSE(bt->set_tree(inverter));
	ERR_PRINT_ON;
	CHECK(bt->tick() == BehaviorTree::FAILURE);
}

TEST_CASE("[BehaviorTree] Invalid leaves are rejected") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Dictionary wrong_wait;
	wrong_wait["type"] = "wait";
	wrong_wait["ticks"] = "three";
	Dictionary wrong_set;
	wrong_set["type"] = "set";
	wrong_set["key"] = "anything";
	Dictionary wrong_condition;
	wrong_condition["type"] = "condition";
	wrong_condition["key"] = 42;
	wrong_condition["equals"] = 42;
	ERR_PRINT_OFF;
	CHECK_FALSE(bt->set_tree(wrong_wait));
	CHECK_FALSE(bt->set_tree(make_wait(1000001)));
	CHECK_FALSE(bt->set_tree(wrong_set));
	CHECK_FALSE(bt->set_tree(wrong_condition));
	ERR_PRINT_ON;
}

TEST_CASE("[BehaviorTree] Excessive child count is rejected") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array too_many;
	for (int i = 0; i < 65; i++) {
		too_many.push_back(make_wait(0));
	}
	ERR_PRINT_OFF;
	CHECK_FALSE(bt->set_tree(make_composite("sequence", too_many)));
	CHECK_FALSE(bt->set_tree(make_composite("selector", too_many)));
	ERR_PRINT_ON;
}

TEST_CASE("[BehaviorTree] Node budget limits large nested graphs") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array leaves;
	for (int i = 0; i < 64; i++) {
		leaves.push_back(make_wait(0));
	}
	Array branches;
	for (int i = 0; i < 33; i++) {
		branches.push_back(make_composite("sequence", leaves));
	}
	ERR_PRINT_OFF;
	CHECK_FALSE(bt->set_tree(make_composite("selector", branches)));
	ERR_PRINT_ON;
}

TEST_CASE("[BehaviorTree] Deep tree accessors isolate caller mutations") {
	Ref<BehaviorTree> bt;
	bt.instantiate();
	Array children;
	children.push_back(make_set("original", 1));
	Dictionary definition = make_composite("sequence", children);
	REQUIRE(bt->set_tree(definition));
	Dictionary fetched = bt->get_tree();
	Array fetched_children = fetched["children"];
	fetched_children.clear();
	CHECK(bt->tick() == BehaviorTree::SUCCESS);
	CHECK(bt->get_blackboard_value("original") == 1);
	Dictionary still_original = bt->get_tree();
	const Array original_children = still_original["children"];
	CHECK(original_children.size() == 1);
}

TEST_CASE("[BehaviorTree] Independent agents can run the same nested tree") {
	Ref<BehaviorTree> one;
	one.instantiate();
	Ref<BehaviorTree> two;
	two.instantiate();
	Array actions;
	actions.push_back(make_wait(1));
	actions.push_back(make_set("done", true));
	const Dictionary definition = make_composite("sequence", actions);
	REQUIRE(one->set_tree(definition));
	REQUIRE(two->set_tree(definition));
	CHECK(one->tick() == BehaviorTree::RUNNING);
	CHECK(one->tick() == BehaviorTree::SUCCESS);
	CHECK_FALSE(two->has_blackboard_value("done"));
	CHECK(two->tick() == BehaviorTree::RUNNING);
	CHECK(two->tick() == BehaviorTree::SUCCESS);
	CHECK(one->get_blackboard_value("done") == true);
	CHECK(two->get_blackboard_value("done") == true);
}

} // namespace TestBehaviorTree
