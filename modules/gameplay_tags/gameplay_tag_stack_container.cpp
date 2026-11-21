/**************************************************************************/
/*  gameplay_tag_stack_container.cpp                                      */
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

#include "gameplay_tag_stack_container.h"

#include "gameplay_tag_container.h"

#include "core/object/class_db.h"

bool GameplayTagStackContainer::_valid_tag(const StringName &p_tag) {
	const String name = p_tag;
	return !name.is_empty() && !name.begins_with(".") && !name.ends_with(".") && !name.contains("..");
}

bool GameplayTagStackContainer::add_stacks(const StringName &p_tag, int p_count) {
	if (!_valid_tag(p_tag) || p_count <= 0 || p_count > MAX_STACKS_PER_TAG) {
		return false;
	}
	const int old_count = stacks.get(p_tag, 0);
	if (old_count > MAX_STACKS_PER_TAG - p_count) {
		return false; // Never wrap the counter or partially apply an invalid delta.
	}
	stacks[p_tag] = old_count + p_count;
	emit_changed();
	return true;
}

int GameplayTagStackContainer::remove_stacks(const StringName &p_tag, int p_count) {
	if (!_valid_tag(p_tag) || p_count <= 0 || !stacks.has(p_tag)) {
		return 0;
	}
	const int old_count = stacks[p_tag];
	const int removed = MIN(old_count, p_count);
	if (removed == old_count) {
		stacks.erase(p_tag);
	} else {
		stacks[p_tag] = old_count - removed;
	}
	emit_changed();
	return removed;
}

int64_t GameplayTagStackContainer::get_stack_count(const StringName &p_tag, bool p_exact) const {
	if (!_valid_tag(p_tag)) {
		return 0;
	}
	if (p_exact) {
		return stacks.get(p_tag, 0);
	}
	int64_t result = 0;
	for (const Variant &key : stacks) {
		const StringName tag = key;
		if (GameplayTagContainer::tag_matches(tag, p_tag)) {
			result += int64_t(stacks[key]);
		}
	}
	return result;
}

bool GameplayTagStackContainer::has_tag(const StringName &p_tag, bool p_exact) const {
	return get_stack_count(p_tag, p_exact) > 0;
}

void GameplayTagStackContainer::clear() {
	if (!stacks.is_empty()) {
		stacks.clear();
		emit_changed();
	}
}

bool GameplayTagStackContainer::replace_stacks(const Dictionary &p_stacks) {
	Dictionary validated;
	for (const Variant &key : p_stacks) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName tag = key;
		if (!_valid_tag(tag) || validated.has(tag)) {
			return false; // Reject collisions after String -> StringName normalization.
		}
		const Variant count = p_stacks[key];
		if (count.get_type() != Variant::INT || int64_t(count) <= 0 || int64_t(count) > MAX_STACKS_PER_TAG) {
			return false;
		}
		validated[tag] = count;
	}

	// Dictionary equality is identity-sensitive; compare entries so repeated
	// network snapshots do not emit a changed signal or invalidate the inspector.
	bool modified = stacks.size() != validated.size();
	if (!modified) {
		for (const Variant &key : validated) {
			if (!stacks.has(key) || stacks[key] != validated[key]) {
				modified = true;
				break;
			}
		}
	}
	if (modified) {
		stacks = validated;
		emit_changed();
	}
	return true;
}

void GameplayTagStackContainer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_stacks", "tag", "count"), &GameplayTagStackContainer::add_stacks, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("remove_stacks", "tag", "count"), &GameplayTagStackContainer::remove_stacks, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("get_stack_count", "tag", "exact"), &GameplayTagStackContainer::get_stack_count, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("has_tag", "tag", "exact"), &GameplayTagStackContainer::has_tag, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_tag_count"), &GameplayTagStackContainer::get_tag_count);
	ClassDB::bind_method(D_METHOD("is_empty"), &GameplayTagStackContainer::is_empty);
	ClassDB::bind_method(D_METHOD("clear"), &GameplayTagStackContainer::clear);
	ClassDB::bind_method(D_METHOD("replace_stacks", "stacks"), &GameplayTagStackContainer::replace_stacks);
	ClassDB::bind_method(D_METHOD("set_stacks", "stacks"), &GameplayTagStackContainer::set_stacks);
	ClassDB::bind_method(D_METHOD("get_stacks"), &GameplayTagStackContainer::get_stacks);

	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "stacks"), "set_stacks", "get_stacks");
}
