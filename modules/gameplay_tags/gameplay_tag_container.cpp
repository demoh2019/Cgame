/**************************************************************************/
/*  gameplay_tag_container.cpp                                            */
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


#include "gameplay_tag_container.h"

#include "core/object/class_db.h"

bool GameplayTagContainer::tag_matches(const StringName &p_tag, const StringName &p_query, bool p_exact) {
	const String tag = p_tag;
	const String query = p_query;
	if (query.is_empty() || tag.is_empty()) {
		return false;
	}
	if (tag == query) {
		return true;
	}
	if (p_exact) {
		return false;
	}
	return tag.length() > query.length() && tag.begins_with(query) && tag[query.length()] == '.';
}

void GameplayTagContainer::add_tag(const StringName &p_tag) {
	if (String(p_tag).is_empty() || tags.has(p_tag)) {
		return;
	}
	tags.push_back(p_tag);
	emit_changed();
}

void GameplayTagContainer::add_tags(const PackedStringArray &p_tags) {
	bool changed = false;
	for (const String &s : p_tags) {
		const StringName n = s;
		if (s.is_empty() || tags.has(n)) {
			continue;
		}
		tags.push_back(n);
		changed = true;
	}
	if (changed) {
		emit_changed();
	}
}

PackedStringArray GameplayTagContainer::get_matching_tags(const StringName &p_query, bool p_exact) const {
	PackedStringArray result;
	for (const StringName &tag : tags) {
		if (tag_matches(tag, p_query, p_exact)) {
			result.push_back(String(tag));
		}
	}
	return result;
}

bool GameplayTagContainer::replace_tag_branch(const StringName &p_query, const PackedStringArray &p_replacements) {
	const String query = p_query;
	// Invalid scopes/replacements never partially clear an actor's status.
	if (query.is_empty() || query.begins_with(".") || query.ends_with(".") || query.contains("..")) {
		return false;
	}
	Vector<StringName> replacements;
	for (const String &value : p_replacements) {
		if (value.is_empty() || value.begins_with(".") || value.ends_with(".") || value.contains("..") ||
				!tag_matches(StringName(value), p_query) || replacements.has(StringName(value))) {
			return false;
		}
		replacements.push_back(StringName(value));
	}

	// Frequent network snapshots often repeat the same state. Avoid allocating a
	// second tag vector or firing resource change notifications for a no-op.
	int matched = 0;
	bool unchanged = true;
	for (const StringName &tag : tags) {
		if (!tag_matches(tag, p_query)) {
			continue;
		}
		if (matched >= replacements.size() || tag != replacements[matched]) {
			unchanged = false;
		}
		matched++;
	}
	if (unchanged && matched == replacements.size()) {
		return true;
	}
	Vector<StringName> next;
	for (const StringName &tag : tags) {
		if (!tag_matches(tag, p_query)) {
			next.push_back(tag);
		}
	}
	for (const StringName &tag : replacements) {
		next.push_back(tag);
	}

	bool modified = tags.size() != next.size();
	if (!modified) {
		for (int i = 0; i < tags.size(); ++i) {
			if (tags[i] != next[i]) {
				modified = true;
				break;
			}
		}
	}
	if (modified) {
		tags = next;
		emit_changed();
	}
	return true;
}

void GameplayTagContainer::remove_tag(const StringName &p_tag) {
	int idx = tags.find(p_tag);
	if (idx >= 0) {
		tags.remove_at(idx);
		emit_changed();
	}
}

void GameplayTagContainer::clear() {
	if (!tags.is_empty()) {
		tags.clear();
		emit_changed();
	}
}

bool GameplayTagContainer::has_tag(const StringName &p_tag, bool p_exact) const {
	for (int i = 0; i < tags.size(); i++) {
		if (tag_matches(tags[i], p_tag, p_exact)) {
			return true;
		}
	}
	return false;
}

bool GameplayTagContainer::has_any(const PackedStringArray &p_tags, bool p_exact) const {
	for (const String &s : p_tags) {
		if (has_tag(StringName(s), p_exact)) {
			return true;
		}
	}
	return false;
}

bool GameplayTagContainer::has_all(const PackedStringArray &p_tags, bool p_exact) const {
	for (const String &s : p_tags) {
		if (!has_tag(StringName(s), p_exact)) {
			return false;
		}
	}
	return true;
}

void GameplayTagContainer::set_tags(const PackedStringArray &p_tags) {
	tags.clear();
	for (const String &s : p_tags) {
		const StringName n = s;
		if (!s.is_empty() && !tags.has(n)) {
			tags.push_back(n);
		}
	}
	emit_changed();
}

PackedStringArray GameplayTagContainer::get_tags() const {
	PackedStringArray out;
	for (int i = 0; i < tags.size(); i++) {
		out.push_back(String(tags[i]));
	}
	return out;
}

void GameplayTagContainer::_bind_methods() {
	ClassDB::bind_static_method("GameplayTagContainer", D_METHOD("tag_matches", "tag", "query", "exact"), &GameplayTagContainer::tag_matches, DEFVAL(false));

	ClassDB::bind_method(D_METHOD("add_tag", "tag"), &GameplayTagContainer::add_tag);
	ClassDB::bind_method(D_METHOD("add_tags", "tags"), &GameplayTagContainer::add_tags);
	ClassDB::bind_method(D_METHOD("get_matching_tags", "query", "exact"), &GameplayTagContainer::get_matching_tags, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("replace_tag_branch", "query", "replacements"), &GameplayTagContainer::replace_tag_branch);
	ClassDB::bind_method(D_METHOD("remove_tag", "tag"), &GameplayTagContainer::remove_tag);
	ClassDB::bind_method(D_METHOD("clear"), &GameplayTagContainer::clear);
	ClassDB::bind_method(D_METHOD("has_tag", "tag", "exact"), &GameplayTagContainer::has_tag, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("has_any", "tags", "exact"), &GameplayTagContainer::has_any, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("has_all", "tags", "exact"), &GameplayTagContainer::has_all, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_tag_count"), &GameplayTagContainer::get_tag_count);
	ClassDB::bind_method(D_METHOD("is_empty"), &GameplayTagContainer::is_empty);
	ClassDB::bind_method(D_METHOD("set_tags", "tags"), &GameplayTagContainer::set_tags);
	ClassDB::bind_method(D_METHOD("get_tags"), &GameplayTagContainer::get_tags);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "tags"), "set_tags", "get_tags");
}

bool GameplayTagQuery::matches(const Ref<GameplayTagContainer> &p_container) const {
	Ref<GameplayTagContainer> c = p_container;
	if (c.is_null()) {
		c.instantiate(); // Empty container.
	}
	if (!c->has_all(all_tags, exact)) {
		return false;
	}
	if (!any_tags.is_empty() && !c->has_any(any_tags, exact)) {
		return false;
	}
	if (!none_tags.is_empty() && c->has_any(none_tags, exact)) {
		return false;
	}
	return true;
}

void GameplayTagQuery::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_all_tags", "tags"), &GameplayTagQuery::set_all_tags);
	ClassDB::bind_method(D_METHOD("get_all_tags"), &GameplayTagQuery::get_all_tags);
	ClassDB::bind_method(D_METHOD("set_any_tags", "tags"), &GameplayTagQuery::set_any_tags);
	ClassDB::bind_method(D_METHOD("get_any_tags"), &GameplayTagQuery::get_any_tags);
	ClassDB::bind_method(D_METHOD("set_none_tags", "tags"), &GameplayTagQuery::set_none_tags);
	ClassDB::bind_method(D_METHOD("get_none_tags"), &GameplayTagQuery::get_none_tags);
	ClassDB::bind_method(D_METHOD("set_exact", "exact"), &GameplayTagQuery::set_exact);
	ClassDB::bind_method(D_METHOD("is_exact"), &GameplayTagQuery::is_exact);
	ClassDB::bind_method(D_METHOD("matches", "container"), &GameplayTagQuery::matches);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "all_tags"), "set_all_tags", "get_all_tags");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "any_tags"), "set_any_tags", "get_any_tags");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "none_tags"), "set_none_tags", "get_none_tags");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "exact"), "set_exact", "is_exact");
}
