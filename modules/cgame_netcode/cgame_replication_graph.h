/**************************************************************************/
/*  cgame_replication_graph.h                                             */
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

#include "core/math/vector2i.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"
#include "core/variant/dictionary.h"

// Native port of scripts/shared/replication_graph.gd: spatial-grid relevancy, dormancy,
// per-class priority/frequency and a per-connection bandwidth budget with starvation.
class CgameReplicationGraph : public RefCounted {
	GDCLASS(CgameReplicationGraph, RefCounted);

	struct Entity {
		int64_t id = 0;
		StringName cls;
		Vector3 position;
		int64_t owner = -1;
		bool always_relevant = false;
		bool owner_only = false;
		bool dormant = false;
		int64_t wake = 0;
	};

	struct ClassConfig {
		double priority = 1.0;
		double interval = 0.0;
		int64_t bytes = 32;
	};

	struct ConnectionState {
		HashMap<int64_t, double> last_sent;
		HashMap<int64_t, double> starve;
		HashMap<int64_t, int64_t> wake_seen;
	};

	struct Due {
		int64_t id;
		StringName cls;
		double priority;
		int64_t bytes;
	};

	struct DueComparator {
		_FORCE_INLINE_ bool operator()(const Due &p_a, const Due &p_b) const {
			if (p_a.priority == p_b.priority) {
				return p_a.id < p_b.id;
			}
			return p_a.priority > p_b.priority;
		}
	};

	double cell_size = 64.0;
	double clock = 0.0;
	int64_t wake_counter = 0;
	HashMap<int64_t, Entity> entities;
	HashMap<StringName, ClassConfig> class_cfg;
	HashMap<Vector2i, HashSet<int64_t>> cells;
	HashSet<int64_t> special; // always_relevant or owner_only entities.
	HashMap<int64_t, ConnectionState> connections;

	Vector2i _cell_of(const Vector3 &p_pos) const;
	void _cell_add(int64_t p_id, const Vector3 &p_pos);
	void _cell_remove(int64_t p_id, const Vector3 &p_pos);
	void _collect_candidates(int64_t p_conn_id, const Vector3 &p_pos, double p_radius, HashSet<int64_t> &r_out) const;

protected:
	static void _bind_methods();

public:
	void set_cell_size(double p_size);
	double get_cell_size() const { return cell_size; }
	void set_clock(double p_clock) { clock = p_clock; }
	double get_clock() const { return clock; }

	void set_class_config(const StringName &p_class, double p_priority, double p_interval, int64_t p_bytes);
	void advance(double p_dt);

	void add_entity(int64_t p_id, const StringName &p_class, const Vector3 &p_position, int64_t p_owner_id = -1, bool p_always_relevant = false, bool p_owner_only = false);
	void remove_entity(int64_t p_id);
	bool has_entity(int64_t p_id) const { return entities.has(p_id); }
	int get_entity_count() const { return entities.size(); }
	int get_cell_count() const { return cells.size(); }
	void set_position(int64_t p_id, const Vector3 &p_position);
	Vector3 get_position(int64_t p_id) const;
	void set_dormant(int64_t p_id, bool p_dormant);
	bool is_dormant(int64_t p_id) const;
	void wake(int64_t p_id);

	void remove_connection(int64_t p_conn_id);
	void clear();

	Array gather_for(const Dictionary &p_connection);
};
