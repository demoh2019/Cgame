/**************************************************************************/
/*  cgame_replication_graph.cpp                                           */
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

#include "cgame_replication_graph.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/variant/array.h"

Vector2i CgameReplicationGraph::_cell_of(const Vector3 &p_pos) const {
	return Vector2i((int32_t)Math::floor(p_pos.x / cell_size), (int32_t)Math::floor(p_pos.z / cell_size));
}

void CgameReplicationGraph::_cell_add(int64_t p_id, const Vector3 &p_pos) {
	cells[_cell_of(p_pos)].insert(p_id);
}

void CgameReplicationGraph::_cell_remove(int64_t p_id, const Vector3 &p_pos) {
	Vector2i key = _cell_of(p_pos);
	HashMap<Vector2i, HashSet<int64_t>>::Iterator it = cells.find(key);
	if (it) {
		it->value.erase(p_id);
		if (it->value.is_empty()) {
			cells.remove(it);
		}
	}
}

void CgameReplicationGraph::set_cell_size(double p_size) {
	ERR_FAIL_COND_MSG(p_size <= 0.0, "cell_size must be greater than zero.");
	cell_size = p_size;
	cells.clear();
	for (const KeyValue<int64_t, Entity> &kv : entities) {
		_cell_add(kv.key, kv.value.position);
	}
}

void CgameReplicationGraph::set_class_config(const StringName &p_class, double p_priority, double p_interval, int64_t p_bytes) {
	ClassConfig cfg;
	cfg.priority = p_priority;
	cfg.interval = p_interval;
	cfg.bytes = p_bytes;
	class_cfg[p_class] = cfg;
}

void CgameReplicationGraph::advance(double p_dt) {
	clock += p_dt;
}

void CgameReplicationGraph::add_entity(int64_t p_id, const StringName &p_class, const Vector3 &p_position, int64_t p_owner_id, bool p_always_relevant, bool p_owner_only) {
	if (entities.has(p_id)) {
		remove_entity(p_id);
	}
	Entity e;
	e.id = p_id;
	e.cls = p_class;
	e.position = p_position;
	e.owner = p_owner_id;
	e.always_relevant = p_always_relevant;
	e.owner_only = p_owner_only;
	entities[p_id] = e;
	_cell_add(p_id, p_position);
	if (p_always_relevant || p_owner_only) {
		special.insert(p_id);
	}
}

void CgameReplicationGraph::remove_entity(int64_t p_id) {
	HashMap<int64_t, Entity>::Iterator it = entities.find(p_id);
	if (!it) {
		return;
	}
	_cell_remove(p_id, it->value.position);
	special.erase(p_id);
	entities.remove(it);
	// Differs from the GDScript version: stale per-connection state is dropped so a
	// re-added id is not throttled by its previous incarnation.
	for (KeyValue<int64_t, ConnectionState> &kv : connections) {
		kv.value.last_sent.erase(p_id);
		kv.value.starve.erase(p_id);
		kv.value.wake_seen.erase(p_id);
	}
}

void CgameReplicationGraph::set_position(int64_t p_id, const Vector3 &p_position) {
	HashMap<int64_t, Entity>::Iterator it = entities.find(p_id);
	if (!it) {
		return;
	}
	Vector3 old = it->value.position;
	if (_cell_of(old) != _cell_of(p_position)) {
		_cell_remove(p_id, old);
		_cell_add(p_id, p_position);
	}
	it->value.position = p_position;
}

Vector3 CgameReplicationGraph::get_position(int64_t p_id) const {
	HashMap<int64_t, Entity>::ConstIterator it = entities.find(p_id);
	ERR_FAIL_COND_V_MSG(!it, Vector3(), "Unknown entity id.");
	return it->value.position;
}

void CgameReplicationGraph::set_dormant(int64_t p_id, bool p_dormant) {
	HashMap<int64_t, Entity>::Iterator it = entities.find(p_id);
	if (it) {
		it->value.dormant = p_dormant;
	}
}

bool CgameReplicationGraph::is_dormant(int64_t p_id) const {
	HashMap<int64_t, Entity>::ConstIterator it = entities.find(p_id);
	return it && it->value.dormant;
}

void CgameReplicationGraph::wake(int64_t p_id) {
	HashMap<int64_t, Entity>::Iterator it = entities.find(p_id);
	if (it) {
		it->value.dormant = false;
		wake_counter++;
		it->value.wake = wake_counter;
	}
}

void CgameReplicationGraph::remove_connection(int64_t p_conn_id) {
	connections.erase(p_conn_id);
}

void CgameReplicationGraph::clear() {
	entities.clear();
	cells.clear();
	special.clear();
	connections.clear();
	wake_counter = 0;
}

void CgameReplicationGraph::_collect_candidates(int64_t p_conn_id, const Vector3 &p_pos, double p_radius, HashSet<int64_t> &r_out) const {
	for (const int64_t &id : special) {
		const Entity &e = entities[id];
		// Owner-only is a privacy constraint, not a distance hint. It wins
		// over always-relevant when both flags are set.
		if (e.owner_only ? e.owner == p_conn_id : e.always_relevant) {
			r_out.insert(id);
		}
	}
	Vector2i lo = _cell_of(p_pos - Vector3(p_radius, 0.0, p_radius));
	Vector2i hi = _cell_of(p_pos + Vector3(p_radius, 0.0, p_radius));
	int64_t range_cells = (int64_t(hi.x) - lo.x + 1) * (int64_t(hi.y) - lo.y + 1);
	LocalVector<const HashSet<int64_t> *> buckets;
	if (range_cells > (int64_t)cells.size()) {
		// Huge view radius: walking the occupied cells is cheaper than walking the range.
		for (const KeyValue<Vector2i, HashSet<int64_t>> &kv : cells) {
			if (kv.key.x >= lo.x && kv.key.x <= hi.x && kv.key.y >= lo.y && kv.key.y <= hi.y) {
				buckets.push_back(&kv.value);
			}
		}
	} else {
		for (int32_t cx = lo.x; cx <= hi.x; cx++) {
			for (int32_t cz = lo.y; cz <= hi.y; cz++) {
				HashMap<Vector2i, HashSet<int64_t>>::ConstIterator it = cells.find(Vector2i(cx, cz));
				if (it) {
					buckets.push_back(&it->value);
				}
			}
		}
	}
	for (const HashSet<int64_t> *b : buckets) {
		for (const int64_t &id : *b) {
			const Entity &e = entities[id];
			if (e.owner_only && e.owner != p_conn_id) {
				continue;
			}
			if (e.position.distance_to(p_pos) <= p_radius) {
				r_out.insert(id);
			}
		}
	}
}

Array CgameReplicationGraph::gather_for(const Dictionary &p_connection) {
	int64_t cid = int64_t(p_connection.get("id", 0));
	Vector3 pos = p_connection.get("position", Vector3());
	double radius = MAX(double(p_connection.get("view_radius", 100.0)), 0.001);
	int64_t budget = int64_t(p_connection.get("bandwidth_bytes", int64_t(1) << 30));

	ConnectionState &st = connections[cid];
	HashSet<int64_t> candidates;
	_collect_candidates(cid, pos, radius, candidates);

	LocalVector<Due> due;
	for (const int64_t &id : candidates) {
		const Entity &e = entities[id];
		int64_t seen = 0;
		HashMap<int64_t, int64_t>::Iterator ws = st.wake_seen.find(id);
		if (ws) {
			seen = ws->value;
		}
		bool woken = e.wake > seen;
		if (e.dormant && !woken) {
			continue;
		}
		ClassConfig cfg;
		HashMap<StringName, ClassConfig>::ConstIterator cc = class_cfg.find(e.cls);
		if (cc) {
			cfg = cc->value;
		}
		HashMap<int64_t, double>::Iterator ls = st.last_sent.find(id);
		if (!woken && ls && clock - ls->value < cfg.interval) {
			continue;
		}
		double near = 1.0;
		if (!e.always_relevant) {
			near = MAX(1.0 - double(e.position.distance_to(pos)) / radius, 0.1);
		}
		double starve = 0.0;
		HashMap<int64_t, double>::Iterator sv = st.starve.find(id);
		if (sv) {
			starve = sv->value;
		}
		double score = cfg.priority * near * (1.0 + starve);
		if (woken) {
			score += 1000.0;
		}
		Due d;
		d.id = id;
		d.cls = e.cls;
		d.priority = score;
		d.bytes = cfg.bytes;
		due.push_back(d);
	}
	due.sort_custom<DueComparator>();

	Array result;
	int64_t used = 0;
	for (const Due &d : due) {
		if (used + d.bytes <= budget) {
			used += d.bytes;
			Dictionary item;
			item["id"] = d.id;
			item["class"] = d.cls;
			item["priority"] = d.priority;
			item["bytes"] = d.bytes;
			result.push_back(item);
			st.last_sent[d.id] = clock;
			st.starve.erase(d.id);
			st.wake_seen[d.id] = entities[d.id].wake;
		} else {
			st.starve[d.id] = (st.starve.has(d.id) ? st.starve[d.id] : 0.0) + 1.0;
		}
	}
	return result;
}

void CgameReplicationGraph::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &CgameReplicationGraph::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &CgameReplicationGraph::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_clock", "clock"), &CgameReplicationGraph::set_clock);
	ClassDB::bind_method(D_METHOD("get_clock"), &CgameReplicationGraph::get_clock);
	ClassDB::bind_method(D_METHOD("set_class_config", "entity_class", "priority", "interval", "bytes"), &CgameReplicationGraph::set_class_config);
	ClassDB::bind_method(D_METHOD("advance", "dt"), &CgameReplicationGraph::advance);
	ClassDB::bind_method(D_METHOD("add_entity", "id", "entity_class", "position", "owner_id", "always_relevant", "owner_only"), &CgameReplicationGraph::add_entity, DEFVAL(-1), DEFVAL(false), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("remove_entity", "id"), &CgameReplicationGraph::remove_entity);
	ClassDB::bind_method(D_METHOD("has_entity", "id"), &CgameReplicationGraph::has_entity);
	ClassDB::bind_method(D_METHOD("get_entity_count"), &CgameReplicationGraph::get_entity_count);
	ClassDB::bind_method(D_METHOD("get_cell_count"), &CgameReplicationGraph::get_cell_count);
	ClassDB::bind_method(D_METHOD("set_position", "id", "position"), &CgameReplicationGraph::set_position);
	ClassDB::bind_method(D_METHOD("get_position", "id"), &CgameReplicationGraph::get_position);
	ClassDB::bind_method(D_METHOD("set_dormant", "id", "dormant"), &CgameReplicationGraph::set_dormant);
	ClassDB::bind_method(D_METHOD("is_dormant", "id"), &CgameReplicationGraph::is_dormant);
	ClassDB::bind_method(D_METHOD("wake", "id"), &CgameReplicationGraph::wake);
	ClassDB::bind_method(D_METHOD("remove_connection", "connection_id"), &CgameReplicationGraph::remove_connection);
	ClassDB::bind_method(D_METHOD("clear"), &CgameReplicationGraph::clear);
	ClassDB::bind_method(D_METHOD("gather_for", "connection"), &CgameReplicationGraph::gather_for);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "0.001,100000,0.001,or_greater"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "clock"), "set_clock", "get_clock");
}
