/**************************************************************************/
/*  cgame_asset_conflicts.h                                               */
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

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"

// Asset conflict tooling: content scans, three-way scene merge, binary version conflicts, Perforce-style exclusive
// checkout locks and scene-inheritance override conflicts.
//
// Concepts (no code copied): three-way merge as in diff3 / Git (the textbook base/mine/theirs comparison),
// Perforce "exclusive open" (+l) checkout locks, Unreal Multi-User asset locking. SHA-256 comes from
// HashingContext.
//
// Scene dictionary used by three_way(): node path -> {property name: value}. The reserved property "_type" holds
// the node type. parse_tscn() and flatten_scene_dict() produce it.
class CgameAssetConflicts : public RefCounted {
	GDCLASS(CgameAssetConflicts, RefCounted);

public:
	static constexpr int CHUNK = 65536;

private:
	struct Lock {
		String user;
		double expires = 0.0;
	};
	HashMap<String, Lock> locks;

	static void _scan_into(const String &p_dir, Dictionary &r_out);
	static String _entry_hash(const Variant &p_entry);
	static String _attr(const String &p_line, const String &p_key);
	static void _flatten(const Dictionary &p_dict, const String &p_parent_path, Dictionary &r_out);
	static bool _same(bool p_a_has, const Variant &p_a, bool p_b_has, const Variant &p_b);
	static bool _props_equal(const Dictionary &p_a, const Dictionary &p_b);
	static bool _props_same_keys(const Dictionary &p_a, const Dictionary &p_b);
	static Dictionary _merge_props(const String &p_path, const Dictionary &p_base, const Dictionary &p_mine, const Dictionary &p_theirs, Array &r_conflicts, const String &p_kind);
	static double _now();

protected:
	static void _bind_methods();

public:
	// Scanning.
	static Dictionary scan(const String &p_dir);
	static Dictionary hash_file(const String &p_path);
	static Array changed_paths(const Dictionary &p_a, const Dictionary &p_b);
	static Array three_way_binary(const Dictionary &p_base, const Dictionary &p_mine, const Dictionary &p_theirs);

	// Text scenes.
	static Dictionary parse_tscn(const String &p_text);
	static Dictionary flatten_scene_dict(const Dictionary &p_dict);
	static Dictionary merge_scene(const Dictionary &p_base, const Dictionary &p_mine, const Dictionary &p_theirs);
	static Array three_way(const Dictionary &p_base, const Dictionary &p_mine, const Dictionary &p_theirs);

	// Inheritance overrides.
	static Array override_conflicts(const Dictionary &p_instance_overrides, const Dictionary &p_base_changes);

	// Exclusive locks.
	bool lock(const String &p_path, const String &p_user, double p_ttl_sec = 300.0, double p_now = -1.0);
	bool unlock(const String &p_path, const String &p_user, bool p_force = false);
	String owner(const String &p_path, double p_now = -1.0);
	bool can_edit(const String &p_path, const String &p_user, double p_now = -1.0);
	Dictionary active_locks(double p_now = -1.0);
};
