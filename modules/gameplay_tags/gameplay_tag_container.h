/**************************************************************************/
/*  gameplay_tag_container.h                                              */
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

#include "core/io/resource.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/variant.h"

/**
 * Unreal-style Gameplay Tags: hierarchical dot-separated tags ("Enemy.Infected.Elite").
 * A non-exact query "Enemy" matches the tag "Enemy.Infected.Elite" (parent match).
 */
class GameplayTagContainer : public Resource {
	GDCLASS(GameplayTagContainer, Resource);

	Vector<StringName> tags; // Unique, insertion order.

protected:
	static void _bind_methods();

public:
	// Pure matching helper. A tag matches a query if equal, or (non-exact) if the query is a parent prefix on a '.' boundary.
	static bool tag_matches(const StringName &p_tag, const StringName &p_query, bool p_exact = false);

	void add_tag(const StringName &p_tag);
	void add_tags(const PackedStringArray &p_tags);
	// Scope operations operate on an entire dotted tag branch, without touching siblings.
	// replace_tag_branch validates every replacement before mutating; true means success
	// (including an unchanged result), false means invalid input and no changes.
	PackedStringArray get_matching_tags(const StringName &p_query, bool p_exact = false) const;
	bool replace_tag_branch(const StringName &p_query, const PackedStringArray &p_replacements);
	void remove_tag(const StringName &p_tag);
	void clear();
	bool has_tag(const StringName &p_tag, bool p_exact = false) const;
	bool has_any(const PackedStringArray &p_tags, bool p_exact = false) const;
	bool has_all(const PackedStringArray &p_tags, bool p_exact = false) const;
	int get_tag_count() const { return tags.size(); }
	bool is_empty() const { return tags.is_empty(); }

	void set_tags(const PackedStringArray &p_tags);
	PackedStringArray get_tags() const;
};

/**
 * Declarative query: every tag in `all_tags` must match, at least one of `any_tags` must match
 * (ignored when empty), and none of `none_tags` may match.
 */
class GameplayTagQuery : public Resource {
	GDCLASS(GameplayTagQuery, Resource);

	PackedStringArray all_tags;
	PackedStringArray any_tags;
	PackedStringArray none_tags;
	bool exact = false;

protected:
	static void _bind_methods();

public:
	void set_all_tags(const PackedStringArray &p_tags) { all_tags = p_tags; emit_changed(); }
	PackedStringArray get_all_tags() const { return all_tags; }
	void set_any_tags(const PackedStringArray &p_tags) { any_tags = p_tags; emit_changed(); }
	PackedStringArray get_any_tags() const { return any_tags; }
	void set_none_tags(const PackedStringArray &p_tags) { none_tags = p_tags; emit_changed(); }
	PackedStringArray get_none_tags() const { return none_tags; }
	void set_exact(bool p_exact) { exact = p_exact; emit_changed(); }
	bool is_exact() const { return exact; }

	bool matches(const Ref<GameplayTagContainer> &p_container) const;
};
