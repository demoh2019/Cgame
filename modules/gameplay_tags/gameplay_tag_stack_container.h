/**************************************************************************/
/*  gameplay_tag_stack_container.h                                        */
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
#include "core/variant/dictionary.h"

/**
 * Counted hierarchical gameplay tags, for stacked effects and replicated status.
 * Counts are stored on exact tags; parent lookups sum all matching descendants.
 * Values are bounded to protect games from corrupted or untrusted snapshots.
 */
class GameplayTagStackContainer : public Resource {
	GDCLASS(GameplayTagStackContainer, Resource);

	static constexpr int MAX_STACKS_PER_TAG = 65535;
	Dictionary stacks;

	static bool _valid_tag(const StringName &p_tag);

protected:
	static void _bind_methods();

public:
	bool add_stacks(const StringName &p_tag, int p_count = 1);
	int remove_stacks(const StringName &p_tag, int p_count = 1);
	int64_t get_stack_count(const StringName &p_tag, bool p_exact = false) const;
	bool has_tag(const StringName &p_tag, bool p_exact = false) const;
	int get_tag_count() const { return stacks.size(); }
	bool is_empty() const { return stacks.is_empty(); }
	void clear();

	// Atomic full-snapshot replacement: an invalid entry leaves the old state intact.
	bool replace_stacks(const Dictionary &p_stacks);
	// Atomic scoped snapshot. Preserve stacks outside the requested hierarchy.
	bool replace_stack_branch(const StringName &p_query, const Dictionary &p_replacements);
	void set_stacks(const Dictionary &p_stacks) { replace_stacks(p_stacks); }
	Dictionary get_stacks() const { return stacks.duplicate(); }
};
