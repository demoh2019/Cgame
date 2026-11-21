/**************************************************************************/
/*  cgame_scene_crdt.h                                                    */
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
#include "core/templates/hash_set.h"
#include "core/templates/vector.h"

// Scene document as an operation-based CRDT for multi-user editing.
//
// Algorithms (published ideas, no code copied):
//  - LWW register / LWW element map and OR-set (add-wins set with tombstones): Shapiro, Preguica, Baquero and
//    Zawirski, "A comprehensive study of Convergent and Commutative Replicated Data Types" (INRIA RR-7506, 2011).
//  - RGA sequence: Roh, Jelasity, Kulkarni et al., "Replicated abstract data type: Building blocks for
//    collaborative applications" (JPDC 2011).
//  - Lamport clocks: Lamport, CACM 1978.
//
// Every node has a stable string id. Properties are LWW registers ordered by (lamport, replica id). Node existence
// is an add-wins set: each add_node creates a unique tag and remove_node tombstones only the tags it observed.
// Parent/child order is an RGA per parent; every placement (add or move) is a sequence element "lamport@replica".
// apply() is idempotent and commutative. Sync uses state_vector() and ops_since(). Presence is a separate
// ephemeral channel.
//
// Op shape (Dictionary): kind, r (replica), seq (per-replica counter), l (lamport) plus
//   add_node    id, parent, after, props, type
//   remove_node id, tags
//   set_prop    id, prop, value
//   move_node   id, parent, after
class CgameSceneCRDT : public RefCounted {
	GDCLASS(CgameSceneCRDT, RefCounted);

	struct Reg {
		Variant value;
		int64_t l = 0;
		String r;
	};

	struct Elem {
		String node;
		String parent;
		String after;
		int64_t l = 0;
		String r;
	};

	struct Presence {
		int64_t l = 0;
		Variant cursor;
		Array selection;
		int64_t t = 0;
	};

	String replica;
	int64_t clock = 0;
	int64_t seq_counter = 0;

	HashMap<String, Dictionary> log;
	Vector<Dictionary> log_order;
	HashMap<String, HashSet<int64_t>> seen;
	HashMap<String, int64_t> contig;
	HashMap<String, Vector<String>> tags; // node id -> ordered tags.
	HashSet<String> tombstones;
	HashMap<String, HashMap<String, Reg>> props;
	HashMap<String, Elem> elems;
	HashMap<String, Vector<String>> by_parent; // parent id -> element ids.
	HashMap<String, String> best; // node id -> winning element id.
	HashMap<String, Presence> presence_map;
	int64_t presence_l = 0;

	static bool _newer(int64_t p_l1, const String &p_r1, int64_t p_l2, const String &p_r2);
	static String _elem_id(int64_t p_l, const String &p_r);

	void _set_reg(const String &p_node, const String &p_prop, const Variant &p_value, int64_t p_l, const String &p_r);
	void _place(const String &p_elem, const String &p_node, const String &p_parent, const String &p_after, int64_t p_l, const String &p_r);
	String _after_for(const String &p_parent, int p_index, const String &p_skip_id) const;
	Dictionary _node_dict(const String &p_node, HashSet<String> &r_visiting) const;
	void _load_node(const Dictionary &p_dict, const String &p_parent, const String &p_path);
	Vector<String> _children(const String &p_parent) const;

protected:
	static void _bind_methods();

public:
	void set_replica(const String &p_replica) { replica = p_replica; }
	String get_replica() const { return replica; }
	void set_clock(int64_t p_clock) { clock = p_clock; }
	int64_t get_clock() const { return clock; }

	bool apply(const Dictionary &p_op);
	Dictionary local_op(const String &p_kind, const Dictionary &p_args);

	bool has_node(const String &p_node) const;
	Variant get_prop(const String &p_node, const String &p_prop, const Variant &p_default = Variant()) const;
	String parent_of(const String &p_node) const;
	Array children_of(const String &p_parent) const;
	Array all_node_ids() const;

	Dictionary state_vector() const;
	Array ops_since(const Dictionary &p_vector) const;
	int merge_ops(const Array &p_ops);

	Dictionary to_scene_dict() const;
	void load_scene_dict(const Dictionary &p_dict);
	static Ref<CgameSceneCRDT> from_packed_scene_dict(const Dictionary &p_dict, const String &p_replica = "local");

	Dictionary local_presence(const Variant &p_cursor, const Array &p_selection, int64_t p_time_msec = 0);
	bool apply_presence(const Dictionary &p_message);
	Dictionary presence() const;
	void remove_presence(const String &p_user);
	Array expire_presence(int64_t p_now_msec, int64_t p_ttl_msec);
};
