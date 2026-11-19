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

#include "behavior_tree.h"

#include "core/object/class_db.h"

bool BehaviorTree::_validate_node(const Variant &p_node, int p_depth, int &r_count) const {
	if (p_node.get_type() != Variant::DICTIONARY || p_depth > 32 || ++r_count > 2048) {
		return false;
	}
	const Dictionary node = p_node;
	if (!node.has("type") || node["type"].get_type() != Variant::STRING) {
		return false;
	}
	const String type = node["type"];
	if (type == "sequence" || type == "selector") {
		if (!node.has("children") || node["children"].get_type() != Variant::ARRAY) {
			return false;
		}
		const Array children = node["children"];
		if (children.is_empty() || children.size() > 64) {
			return false;
		}
		for (const Variant &child : children) {
			if (!_validate_node(child, p_depth + 1, r_count)) {
				return false;
			}
		}
		return true;
	}
	if (type == "inverter") {
		return node.has("child") && _validate_node(node["child"], p_depth + 1, r_count);
	}
	if (type == "condition") {
		return node.has("key") && node["key"].get_type() == Variant::STRING && node.has("equals");
	}
	if (type == "set") {
		return node.has("key") && node["key"].get_type() == Variant::STRING && node.has("value");
	}
	if (type == "wait") {
		return node.has("ticks") && node["ticks"].get_type() == Variant::INT && int64_t(node["ticks"]) >= 0 && int64_t(node["ticks"]) <= 1000000;
	}
	return false;
}

bool BehaviorTree::set_tree(const Dictionary &p_tree) {
	int node_count = 0;
	ERR_FAIL_COND_V_MSG(!_validate_node(p_tree, 0, node_count), false, "Invalid behavior tree description.");
	tree = p_tree.duplicate(true);
	memory.clear();
	return true;
}

Dictionary BehaviorTree::get_tree() const {
	return tree.duplicate(true);
}

void BehaviorTree::_clear_memory_prefix(const String &p_path) {
	const Array keys = memory.keys();
	const String prefix = p_path + "/";
	for (const Variant &key : keys) {
		const String key_path = key;
		if (key_path == p_path || key_path.begins_with(prefix)) {
			memory.erase(key);
		}
	}
}

BehaviorTree::Status BehaviorTree::_tick_node(const Dictionary &p_node, const String &p_path) {
	const String type = p_node["type"];

	if (type == "condition") {
		const String key = p_node["key"];
		return blackboard.has(key) && blackboard[key] == p_node["equals"] ? SUCCESS : FAILURE;
	}
	if (type == "set") {
		const String key = p_node["key"];
		blackboard[key] = p_node["value"];
		return SUCCESS;
	}
	if (type == "wait") {
		const int64_t ticks = memory.has(p_path) ? int64_t(memory[p_path]) : int64_t(p_node["ticks"]);
		if (ticks > 0) {
			memory[p_path] = ticks - 1;
			return RUNNING;
		}
		memory.erase(p_path);
		return SUCCESS;
	}
	if (type == "inverter") {
		const Status status = _tick_node(p_node["child"], p_path + "/child");
		if (status != RUNNING) {
			_clear_memory_prefix(p_path);
		}
		return status == SUCCESS ? FAILURE : (status == FAILURE ? SUCCESS : RUNNING);
	}
	const Array children = p_node["children"];
	const bool is_sequence = type == "sequence";
	const int start = memory.has(p_path) ? int(memory[p_path]) : 0;
	for (int i = start; i < children.size(); i++) {
		const Status status = _tick_node(children[i], p_path + "/" + String::num_int64(i));
		if (status == RUNNING) {
			memory[p_path] = i;
			return RUNNING;
		}
		if ((is_sequence && status == FAILURE) || (!is_sequence && status == SUCCESS)) {
			_clear_memory_prefix(p_path);
			return status;
		}
	}
	_clear_memory_prefix(p_path);
	return is_sequence ? SUCCESS : FAILURE;
}

BehaviorTree::Status BehaviorTree::tick() {
	if (tree.is_empty()) {
		return FAILURE;
	}
	return _tick_node(tree, "root");
}

void BehaviorTree::reset() {
	memory.clear();
}

void BehaviorTree::clear_blackboard() {
	blackboard.clear();
}

void BehaviorTree::set_blackboard_value(const String &p_key, const Variant &p_value) {
	blackboard[p_key] = p_value;
}

Variant BehaviorTree::get_blackboard_value(const String &p_key, const Variant &p_default) const {
	return blackboard.get(p_key, p_default);
}

bool BehaviorTree::has_blackboard_value(const String &p_key) const {
	return blackboard.has(p_key);
}

void BehaviorTree::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_tree", "description"), &BehaviorTree::set_tree);
	ClassDB::bind_method(D_METHOD("get_tree"), &BehaviorTree::get_tree);
	ClassDB::bind_method(D_METHOD("tick"), &BehaviorTree::tick);
	ClassDB::bind_method(D_METHOD("reset"), &BehaviorTree::reset);
	ClassDB::bind_method(D_METHOD("clear_blackboard"), &BehaviorTree::clear_blackboard);
	ClassDB::bind_method(D_METHOD("set_blackboard_value", "key", "value"), &BehaviorTree::set_blackboard_value);
	ClassDB::bind_method(D_METHOD("get_blackboard_value", "key", "default"), &BehaviorTree::get_blackboard_value, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("has_blackboard_value", "key"), &BehaviorTree::has_blackboard_value);

	BIND_ENUM_CONSTANT(FAILURE);
	BIND_ENUM_CONSTANT(SUCCESS);
	BIND_ENUM_CONSTANT(RUNNING);
}
