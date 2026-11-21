/**************************************************************************/
/*  cgame_mass_entity.cpp                                                 */
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

#include "cgame_mass_entity.h"

#include "core/object/class_db.h"
#include "core/templates/rb_map.h"

// --- Column helpers -------------------------------------------------------------

bool CgameMassEntity::_is_fragment_type(int p_type) {
	return p_type == Variant::PACKED_VECTOR3_ARRAY || p_type == Variant::PACKED_FLOAT32_ARRAY || p_type == Variant::PACKED_INT32_ARRAY;
}

bool CgameMassEntity::_value_fits(Variant::Type p_type, const Variant &p_value) {
	const Variant::Type t = p_value.get_type();
	switch (p_type) {
		case Variant::PACKED_VECTOR3_ARRAY:
			return t == Variant::VECTOR3;
		case Variant::PACKED_FLOAT32_ARRAY:
			return t == Variant::FLOAT || t == Variant::INT;
		case Variant::PACKED_INT32_ARRAY:
			return t == Variant::INT;
		default:
			return false;
	}
}

void CgameMassEntity::_push_value(Column &r_column, const Variant &p_value) {
	switch (r_column.type) {
		case Variant::PACKED_VECTOR3_ARRAY:
			r_column.v3.push_back(p_value);
			break;
		case Variant::PACKED_FLOAT32_ARRAY:
			r_column.f.push_back((float)(double)p_value);
			break;
		default:
			r_column.i.push_back((int32_t)(int64_t)p_value);
			break;
	}
}

void CgameMassEntity::_push_default(Column &r_column) {
	switch (r_column.type) {
		case Variant::PACKED_VECTOR3_ARRAY:
			r_column.v3.push_back(Vector3());
			break;
		case Variant::PACKED_FLOAT32_ARRAY:
			r_column.f.push_back(0.0f);
			break;
		default:
			r_column.i.push_back(0);
			break;
	}
}

void CgameMassEntity::_swap_remove(Column &r_column, int p_row, int p_last) {
	switch (r_column.type) {
		case Variant::PACKED_VECTOR3_ARRAY: {
			Vector3 *w = r_column.v3.ptrw();
			w[p_row] = w[p_last];
			r_column.v3.resize(p_last);
		} break;
		case Variant::PACKED_FLOAT32_ARRAY: {
			float *w = r_column.f.ptrw();
			w[p_row] = w[p_last];
			r_column.f.resize(p_last);
		} break;
		default: {
			int32_t *w = r_column.i.ptrw();
			w[p_row] = w[p_last];
			r_column.i.resize(p_last);
		} break;
	}
}

Variant CgameMassEntity::_read_value(const Column &p_column, int p_row) {
	switch (p_column.type) {
		case Variant::PACKED_VECTOR3_ARRAY:
			ERR_FAIL_INDEX_V(p_row, p_column.v3.size(), Variant());
			return p_column.v3[p_row];
		case Variant::PACKED_FLOAT32_ARRAY:
			ERR_FAIL_INDEX_V(p_row, p_column.f.size(), Variant());
			return (double)p_column.f[p_row];
		default:
			ERR_FAIL_INDEX_V(p_row, p_column.i.size(), Variant());
			return (int64_t)p_column.i[p_row];
	}
}

void CgameMassEntity::_write_value(Column &r_column, int p_row, const Variant &p_value) {
	switch (r_column.type) {
		case Variant::PACKED_VECTOR3_ARRAY:
			ERR_FAIL_INDEX(p_row, r_column.v3.size());
			r_column.v3.write[p_row] = p_value;
			break;
		case Variant::PACKED_FLOAT32_ARRAY:
			ERR_FAIL_INDEX(p_row, r_column.f.size());
			r_column.f.write[p_row] = (float)(double)p_value;
			break;
		default:
			ERR_FAIL_INDEX(p_row, r_column.i.size());
			r_column.i.write[p_row] = (int32_t)(int64_t)p_value;
			break;
	}
}

int CgameMassEntity::_column_size(const Column &p_column) {
	switch (p_column.type) {
		case Variant::PACKED_VECTOR3_ARRAY:
			return p_column.v3.size();
		case Variant::PACKED_FLOAT32_ARRAY:
			return p_column.f.size();
		default:
			return p_column.i.size();
	}
}

void CgameMassEntity::_clear_column(Column &r_column) {
	r_column.v3.clear();
	r_column.f.clear();
	r_column.i.clear();
}

// --- Fragments and archetypes ---------------------------------------------------

void CgameMassEntity::define_fragment(const String &p_name, int p_type) {
	ERR_FAIL_COND_MSG(running, "CgameMassEntity: cannot define fragments while run() is executing.");
	ERR_FAIL_COND_MSG(p_name.is_empty(), "CgameMassEntity: fragment name must not be empty.");
	ERR_FAIL_COND_MSG(!_is_fragment_type(p_type), vformat("CgameMassEntity: unsupported fragment type for '%s'.", p_name));
	const HashMap<String, Variant::Type>::Iterator existing = fragment_types.find(p_name);
	if (existing) {
		ERR_FAIL_COND_MSG(existing->value != (Variant::Type)p_type, vformat("CgameMassEntity: fragment '%s' is already defined with another type.", p_name));
		return;
	}
	fragment_types.insert(p_name, (Variant::Type)p_type);
}

int CgameMassEntity::_archetype_for(const Vector<String> &p_sorted_names) {
	String key;
	for (int k = 0; k < p_sorted_names.size(); k++) {
		if (k > 0) {
			key += ",";
		}
		key += p_sorted_names[k];
	}
	const HashMap<String, int>::Iterator it = archetype_lookup.find(key);
	if (it) {
		return it->value;
	}
	Archetype arch;
	for (int k = 0; k < p_sorted_names.size(); k++) {
		arch.names.push_back(p_sorted_names[k]);
		Column col;
		col.type = fragment_types[p_sorted_names[k]];
		arch.columns.push_back(col);
	}
	archetypes.push_back(arch);
	const int index = (int)archetypes.size() - 1;
	archetype_lookup.insert(key, index);
	return index;
}

bool CgameMassEntity::_archetype_has_all(const Archetype &p_archetype, const PackedStringArray &p_required) const {
	for (int r = 0; r < p_required.size(); r++) {
		if (p_archetype.find(p_required[r]) < 0) {
			return false;
		}
	}
	return true;
}

uint32_t CgameMassEntity::_allocate_slot() {
	if (free_slots.size() > 0) {
		const uint32_t slot = free_slots[free_slots.size() - 1];
		free_slots.resize(free_slots.size() - 1);
		return slot;
	}
	const uint32_t slot = generations.size();
	generations.push_back(1);
	slot_archetype.push_back(-1);
	slot_row.push_back(0);
	return slot;
}

// --- Entities -------------------------------------------------------------------

PackedInt64Array CgameMassEntity::create_many(const Dictionary &p_fragments, int p_count) {
	PackedInt64Array ids;
	ERR_FAIL_COND_V_MSG(running, ids, "CgameMassEntity: cannot create entities while run() is executing.");
	ERR_FAIL_COND_V(p_count < 0, ids);
	RBMap<String, Variant> values;
	const Array keys = p_fragments.keys();
	for (int k = 0; k < keys.size(); k++) {
		const Variant &key = keys[k];
		ERR_FAIL_COND_V_MSG(key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME, ids, "CgameMassEntity: fragment keys must be Strings.");
		const String name = key;
		const HashMap<String, Variant::Type>::Iterator type = fragment_types.find(name);
		ERR_FAIL_COND_V_MSG(!type, ids, vformat("CgameMassEntity: undefined fragment '%s'.", name));
		const Variant &value = p_fragments[key];
		ERR_FAIL_COND_V_MSG(!_value_fits(type->value, value), ids, vformat("CgameMassEntity: wrong value type for fragment '%s'.", name));
		values.insert(name, value);
	}
	Vector<String> names;
	for (const KeyValue<String, Variant> &kv : values) {
		names.push_back(kv.key);
	}
	const int ai = _archetype_for(names);
	ERR_FAIL_COND_V_MSG((int64_t)generations.size() - (int64_t)free_slots.size() + p_count > INDEX_MASK, ids, "CgameMassEntity: entity capacity (2^24) exceeded.");
	ids.resize(p_count);
	int64_t *ids_w = ids.ptrw();
	for (int n = 0; n < p_count; n++) {
		const uint32_t slot = _allocate_slot();
		Archetype &arch = archetypes[ai];
		for (uint32_t c = 0; c < arch.columns.size(); c++) {
			_push_value(arch.columns[c], values[arch.names[c]]);
		}
		arch.slots.push_back((int32_t)slot);
		slot_archetype[slot] = ai;
		slot_row[slot] = arch.count;
		arch.count++;
		alive_count++;
		ids_w[n] = _pack(slot, generations[slot]);
	}
	return ids;
}

int64_t CgameMassEntity::create(const Dictionary &p_fragments) {
	const PackedInt64Array ids = create_many(p_fragments, 1);
	return ids.is_empty() ? -1 : ids[0];
}

bool CgameMassEntity::is_alive(int64_t p_id) const {
	if (p_id < 0) {
		return false;
	}
	const int64_t slot = p_id & INDEX_MASK;
	if (slot >= (int64_t)generations.size()) {
		return false;
	}
	return slot_archetype[slot] >= 0 && (int64_t)generations[slot] == (p_id >> INDEX_BITS);
}

void CgameMassEntity::_destroy_slot(uint32_t p_slot) {
	const int ai = slot_archetype[p_slot];
	const int row = slot_row[p_slot];
	Archetype &arch = archetypes[ai];
	const int last = arch.count - 1;
	const int32_t moved_slot = arch.slots[last];
	for (uint32_t c = 0; c < arch.columns.size(); c++) {
		_swap_remove(arch.columns[c], row, last);
	}
	arch.slots.write[row] = moved_slot;
	arch.slots.resize(last);
	arch.count = last;
	slot_row[moved_slot] = row;
	slot_archetype[p_slot] = -1;
	// Wrap the generation well before the packed id overflows.
	generations[p_slot] = (generations[p_slot] + 1) & MAX_GENERATION;
	if (generations[p_slot] == 0) {
		generations[p_slot] = 1;
	}
	free_slots.push_back(p_slot);
	alive_count--;
}

void CgameMassEntity::destroy(int64_t p_id) {
	ERR_FAIL_COND_MSG(running, "CgameMassEntity: cannot destroy entities while run() is executing.");
	if (!is_alive(p_id)) {
		return;
	}
	_destroy_slot((uint32_t)(p_id & INDEX_MASK));
}

void CgameMassEntity::clear() {
	ERR_FAIL_COND_MSG(running, "CgameMassEntity: cannot clear while run() is executing.");
	for (uint32_t s = 0; s < generations.size(); s++) {
		if (slot_archetype[s] >= 0) {
			slot_archetype[s] = -1;
			generations[s] = (generations[s] + 1) & MAX_GENERATION;
			if (generations[s] == 0) {
				generations[s] = 1;
			}
			free_slots.push_back(s);
		}
	}
	for (uint32_t a = 0; a < archetypes.size(); a++) {
		Archetype &arch = archetypes[a];
		for (uint32_t c = 0; c < arch.columns.size(); c++) {
			_clear_column(arch.columns[c]);
		}
		arch.slots.clear();
		arch.count = 0;
	}
	alive_count = 0;
}

bool CgameMassEntity::has_fragment(int64_t p_id, const String &p_fragment) const {
	if (!is_alive(p_id)) {
		return false;
	}
	return archetypes[slot_archetype[p_id & INDEX_MASK]].find(p_fragment) >= 0;
}

Variant CgameMassEntity::get_value(int64_t p_id, const String &p_fragment) const {
	if (!is_alive(p_id)) {
		return Variant();
	}
	const int64_t slot = p_id & INDEX_MASK;
	const Archetype &arch = archetypes[slot_archetype[slot]];
	const int c = arch.find(p_fragment);
	if (c < 0) {
		return Variant();
	}
	return _read_value(arch.columns[c], slot_row[slot]);
}

void CgameMassEntity::set_value(int64_t p_id, const String &p_fragment, const Variant &p_value) {
	if (!has_fragment(p_id, p_fragment)) {
		return;
	}
	const int64_t slot = p_id & INDEX_MASK;
	Archetype &arch = archetypes[slot_archetype[slot]];
	const int c = arch.find(p_fragment);
	ERR_FAIL_COND_MSG(!_value_fits(arch.columns[c].type, p_value), vformat("CgameMassEntity: wrong value type for fragment '%s'.", p_fragment));
	_write_value(arch.columns[c], slot_row[slot], p_value);
}

// --- Queries --------------------------------------------------------------------

Dictionary CgameMassEntity::_build_chunk(const Archetype &p_archetype) const {
	Dictionary chunk;
	for (uint32_t c = 0; c < p_archetype.columns.size(); c++) {
		const Column &col = p_archetype.columns[c];
		switch (col.type) {
			case Variant::PACKED_VECTOR3_ARRAY:
				chunk[p_archetype.names[c]] = col.v3;
				break;
			case Variant::PACKED_FLOAT32_ARRAY:
				chunk[p_archetype.names[c]] = col.f;
				break;
			default:
				chunk[p_archetype.names[c]] = col.i;
				break;
		}
	}
	chunk["_ids"] = p_archetype.slots;
	chunk["_count"] = p_archetype.count;
	return chunk;
}

Array CgameMassEntity::query(const PackedStringArray &p_required) const {
	Array out;
	for (uint32_t a = 0; a < archetypes.size(); a++) {
		const Archetype &arch = archetypes[a];
		if (arch.count > 0 && _archetype_has_all(arch, p_required)) {
			out.push_back(_build_chunk(arch));
		}
	}
	return out;
}

PackedInt64Array CgameMassEntity::get_entity_ids(const PackedStringArray &p_required) const {
	PackedInt64Array out;
	for (uint32_t a = 0; a < archetypes.size(); a++) {
		const Archetype &arch = archetypes[a];
		if (arch.count == 0 || !_archetype_has_all(arch, p_required)) {
			continue;
		}
		for (int row = 0; row < arch.count; row++) {
			const uint32_t slot = (uint32_t)arch.slots[row];
			out.push_back(_pack(slot, generations[slot]));
		}
	}
	return out;
}

Variant CgameMassEntity::get_column(const String &p_fragment) const {
	const HashMap<String, Variant::Type>::ConstIterator type = fragment_types.find(p_fragment);
	ERR_FAIL_COND_V_MSG(!type, Variant(), vformat("CgameMassEntity: undefined fragment '%s'.", p_fragment));
	PackedVector3Array v3;
	PackedFloat32Array f;
	PackedInt32Array i;
	for (uint32_t a = 0; a < archetypes.size(); a++) {
		const Archetype &arch = archetypes[a];
		const int c = arch.find(p_fragment);
		if (c < 0 || arch.count == 0) {
			continue;
		}
		switch (type->value) {
			case Variant::PACKED_VECTOR3_ARRAY:
				v3.append_array(arch.columns[c].v3);
				break;
			case Variant::PACKED_FLOAT32_ARRAY:
				f.append_array(arch.columns[c].f);
				break;
			default:
				i.append_array(arch.columns[c].i);
				break;
		}
	}
	switch (type->value) {
		case Variant::PACKED_VECTOR3_ARRAY:
			return v3;
		case Variant::PACKED_FLOAT32_ARRAY:
			return f;
		default:
			return i;
	}
}

// --- Processors -----------------------------------------------------------------

void CgameMassEntity::add_processor(const String &p_name, const PackedStringArray &p_required, const Callable &p_callable, const PackedStringArray &p_depends_on, bool p_parallel) {
	ERR_FAIL_COND_MSG(running, "CgameMassEntity: cannot add processors while run() is executing.");
	ERR_FAIL_COND_MSG(p_name.is_empty(), "CgameMassEntity: processor name must not be empty.");
	ERR_FAIL_COND_MSG(!p_callable.is_valid(), vformat("CgameMassEntity: processor '%s' has an invalid Callable.", p_name));
	for (uint32_t k = 0; k < processors.size(); k++) {
		ERR_FAIL_COND_MSG(processors[k].name == p_name, vformat("CgameMassEntity: processor '%s' already exists.", p_name));
	}
	Processor p;
	p.name = p_name;
	p.kind = PROCESSOR_SCRIPT;
	p.required = p_required;
	p.callable = p_callable;
	p.depends_on = p_depends_on;
	p.parallel = p_parallel;
	processors.push_back(p);
	order_dirty = true;
}

void CgameMassEntity::add_integrate_processor(const String &p_name, const String &p_position_fragment, const String &p_velocity_fragment, const PackedStringArray &p_depends_on) {
	ERR_FAIL_COND_MSG(running, "CgameMassEntity: cannot add processors while run() is executing.");
	ERR_FAIL_COND_MSG(p_name.is_empty(), "CgameMassEntity: processor name must not be empty.");
	for (uint32_t k = 0; k < processors.size(); k++) {
		ERR_FAIL_COND_MSG(processors[k].name == p_name, vformat("CgameMassEntity: processor '%s' already exists.", p_name));
	}
	const HashMap<String, Variant::Type>::Iterator pt = fragment_types.find(p_position_fragment);
	const HashMap<String, Variant::Type>::Iterator vt = fragment_types.find(p_velocity_fragment);
	ERR_FAIL_COND_MSG(!pt || !vt || pt->value != Variant::PACKED_VECTOR3_ARRAY || vt->value != Variant::PACKED_VECTOR3_ARRAY, "CgameMassEntity: integrate processor needs two defined PackedVector3Array fragments.");
	Processor p;
	p.name = p_name;
	p.kind = PROCESSOR_INTEGRATE;
	p.position_fragment = p_position_fragment;
	p.velocity_fragment = p_velocity_fragment;
	p.required.push_back(p_position_fragment);
	p.required.push_back(p_velocity_fragment);
	p.depends_on = p_depends_on;
	processors.push_back(p);
	order_dirty = true;
}

void CgameMassEntity::add_crowd_avoidance_processor(const String &p_name, const String &p_position_fragment, const String &p_velocity_fragment, const String &p_preferred_fragment, real_t p_radius, real_t p_max_speed, real_t p_time_horizon, real_t p_neighbor_dist, int p_max_neighbors, const PackedStringArray &p_depends_on, bool p_ground_xz) {
	ERR_FAIL_COND_MSG(running, "CgameMassEntity: cannot add processors while run() is executing.");
	ERR_FAIL_COND_MSG(p_name.is_empty(), "CgameMassEntity: processor name must not be empty.");
	for (uint32_t k = 0; k < processors.size(); k++) {
		ERR_FAIL_COND_MSG(processors[k].name == p_name, vformat("CgameMassEntity: processor '%s' already exists.", p_name));
	}
	const String frags[3] = { p_position_fragment, p_velocity_fragment, p_preferred_fragment };
	for (int k = 0; k < 3; k++) {
		const HashMap<String, Variant::Type>::Iterator t = fragment_types.find(frags[k]);
		ERR_FAIL_COND_MSG(!t || t->value != Variant::PACKED_VECTOR3_ARRAY, "CgameMassEntity: crowd avoidance processor needs three defined PackedVector3Array fragments.");
	}
	ERR_FAIL_COND_MSG(p_position_fragment == p_velocity_fragment || p_velocity_fragment == p_preferred_fragment || p_position_fragment == p_preferred_fragment, "CgameMassEntity: crowd avoidance fragments must be distinct.");
	Processor p;
	p.name = p_name;
	p.kind = PROCESSOR_CROWD_AVOIDANCE;
	p.position_fragment = p_position_fragment;
	p.velocity_fragment = p_velocity_fragment;
	p.preferred_fragment = p_preferred_fragment;
	p.required.push_back(p_position_fragment);
	p.required.push_back(p_velocity_fragment);
	p.required.push_back(p_preferred_fragment);
	p.ground_xz = p_ground_xz;
	p.crowd.radius = p_radius;
	p.crowd.max_speed = p_max_speed;
	p.crowd.time_horizon = p_time_horizon;
	p.crowd.neighbor_dist = p_neighbor_dist;
	p.crowd.max_neighbors = p_max_neighbors;
	p.depends_on = p_depends_on;
	processors.push_back(p);
	order_dirty = true;
}

void CgameMassEntity::remove_processor(const String &p_name) {
	ERR_FAIL_COND_MSG(running, "CgameMassEntity: cannot remove processors while run() is executing.");
	for (uint32_t k = 0; k < processors.size(); k++) {
		if (processors[k].name == p_name) {
			processors.remove_at(k);
			order_dirty = true;
			return;
		}
	}
}

// Kahn topological sort, stable by registration order.
void CgameMassEntity::_rebuild_order() {
	if (!order_dirty) {
		return;
	}
	order_dirty = false;
	order.clear();
	const uint32_t n = processors.size();
	HashMap<String, int> by_name;
	for (uint32_t i = 0; i < n; i++) {
		by_name.insert(processors[i].name, (int)i);
	}
	LocalVector<uint8_t> done;
	done.resize(n);
	for (uint32_t i = 0; i < n; i++) {
		done[i] = 0;
	}
	uint32_t placed = 0;
	while (placed < n) {
		bool progressed = false;
		for (uint32_t i = 0; i < n; i++) {
			if (done[i]) {
				continue;
			}
			bool ready = true;
			const PackedStringArray &deps = processors[i].depends_on;
			for (int d = 0; d < deps.size(); d++) {
				const HashMap<String, int>::Iterator dep = by_name.find(deps[d]);
				if (dep && dep->value != (int)i && !done[dep->value]) {
					ready = false;
					break;
				}
			}
			if (ready) {
				done[i] = 1;
				order.push_back((int)i);
				placed++;
				progressed = true;
			}
		}
		if (!progressed) {
			ERR_PRINT("CgameMassEntity: processor dependency cycle.");
			for (uint32_t i = 0; i < n; i++) {
				if (!done[i]) {
					order.push_back((int)i);
				}
			}
			return;
		}
	}
}

PackedStringArray CgameMassEntity::processor_order() {
	_rebuild_order();
	PackedStringArray out;
	for (uint32_t k = 0; k < order.size(); k++) {
		out.push_back(processors[order[k]].name);
	}
	return out;
}

void CgameMassEntity::_run_script_processor(const Processor &p_processor, double p_delta) {
	for (uint32_t a = 0; a < archetypes.size(); a++) {
		if (archetypes[a].count == 0 || !_archetype_has_all(archetypes[a], p_processor.required)) {
			continue;
		}
		const int count = archetypes[a].count;
		Dictionary chunk = _build_chunk(archetypes[a]);
		p_processor.callable.call(chunk, count, p_delta);
		// Write back arrays the callable replaced (copy-on-write detached them).
		Archetype &arch = archetypes[a];
		for (uint32_t c = 0; c < arch.columns.size(); c++) {
			Column &col = arch.columns[c];
			const Variant &v = chunk[arch.names[c]];
			switch (col.type) {
				case Variant::PACKED_VECTOR3_ARRAY: {
					if (v.get_type() == Variant::PACKED_VECTOR3_ARRAY) {
						const PackedVector3Array arr = v;
						if (arr.ptr() != col.v3.ptr() && arr.size() == count) {
							col.v3 = arr;
						}
					}
				} break;
				case Variant::PACKED_FLOAT32_ARRAY: {
					if (v.get_type() == Variant::PACKED_FLOAT32_ARRAY) {
						const PackedFloat32Array arr = v;
						if (arr.ptr() != col.f.ptr() && arr.size() == count) {
							col.f = arr;
						}
					}
				} break;
				default: {
					if (v.get_type() == Variant::PACKED_INT32_ARRAY) {
						const PackedInt32Array arr = v;
						if (arr.ptr() != col.i.ptr() && arr.size() == count) {
							col.i = arr;
						}
					}
				} break;
			}
		}
	}
}

void CgameMassEntity::_run_integrate(const Processor &p_processor, double p_delta) {
	const real_t dt = (real_t)p_delta;
	for (uint32_t a = 0; a < archetypes.size(); a++) {
		Archetype &arch = archetypes[a];
		if (arch.count == 0) {
			continue;
		}
		const int pi = arch.find(p_processor.position_fragment);
		const int vi = arch.find(p_processor.velocity_fragment);
		if (pi < 0 || vi < 0) {
			continue;
		}
		Vector3 *pos = arch.columns[pi].v3.ptrw();
		const Vector3 *vel = arch.columns[vi].v3.ptr();
		for (int row = 0; row < arch.count; row++) {
			pos[row] += vel[row] * dt;
		}
	}
}

void CgameMassEntity::_run_crowd(const Processor &p_processor, double p_delta) {
	struct Source {
		uint32_t archetype;
		int pos;
		int vel;
		int pref;
	};
	LocalVector<Source> sources;
	uint32_t total = 0;
	for (uint32_t a = 0; a < archetypes.size(); a++) {
		const Archetype &arch = archetypes[a];
		if (arch.count == 0) {
			continue;
		}
		Source s;
		s.archetype = a;
		s.pos = arch.find(p_processor.position_fragment);
		s.vel = arch.find(p_processor.velocity_fragment);
		s.pref = arch.find(p_processor.preferred_fragment);
		if (s.pos < 0 || s.vel < 0 || s.pref < 0) {
			continue;
		}
		sources.push_back(s);
		total += arch.count;
	}
	if (total == 0) {
		return;
	}
	const bool xz = p_processor.ground_xz;
	LocalVector<Vector2> pos;
	LocalVector<Vector2> vel;
	LocalVector<Vector2> pref;
	LocalVector<Vector2> out;
	pos.resize(total);
	vel.resize(total);
	pref.resize(total);
	out.resize(total);
	uint32_t k = 0;
	for (uint32_t s = 0; s < sources.size(); s++) {
		const Archetype &arch = archetypes[sources[s].archetype];
		const Vector3 *p3 = arch.columns[sources[s].pos].v3.ptr();
		const Vector3 *v3 = arch.columns[sources[s].vel].v3.ptr();
		const Vector3 *f3 = arch.columns[sources[s].pref].v3.ptr();
		for (int row = 0; row < arch.count; row++, k++) {
			pos[k] = xz ? Vector2(p3[row].x, p3[row].z) : Vector2(p3[row].x, p3[row].y);
			vel[k] = xz ? Vector2(v3[row].x, v3[row].z) : Vector2(v3[row].x, v3[row].y);
			pref[k] = xz ? Vector2(f3[row].x, f3[row].z) : Vector2(f3[row].x, f3[row].y);
		}
	}
	CgameCrowdAvoidance::Params params = p_processor.crowd;
	if (p_delta > 0.0) {
		params.time_step = (real_t)p_delta;
	}
	CgameCrowdAvoidance::compute(pos.ptr(), vel.ptr(), pref.ptr(), total, params, out.ptr());
	k = 0;
	for (uint32_t s = 0; s < sources.size(); s++) {
		Archetype &arch = archetypes[sources[s].archetype];
		Vector3 *v3 = arch.columns[sources[s].vel].v3.ptrw();
		for (int row = 0; row < arch.count; row++, k++) {
			v3[row].x = out[k].x;
			if (xz) {
				v3[row].z = out[k].y;
			} else {
				v3[row].y = out[k].y;
			}
		}
	}
}

void CgameMassEntity::run(double p_delta) {
	ERR_FAIL_COND_MSG(running, "CgameMassEntity: run() is not re-entrant.");
	_rebuild_order();
	running = true;
	for (uint32_t k = 0; k < order.size(); k++) {
		const Processor &p = processors[order[k]];
		switch (p.kind) {
			case PROCESSOR_SCRIPT:
				_run_script_processor(p, p_delta);
				break;
			case PROCESSOR_INTEGRATE:
				_run_integrate(p, p_delta);
				break;
			case PROCESSOR_CROWD_AVOIDANCE:
				_run_crowd(p, p_delta);
				break;
		}
	}
	running = false;
}

void CgameMassEntity::_bind_methods() {
	ClassDB::bind_method(D_METHOD("define_fragment", "name", "type"), &CgameMassEntity::define_fragment);
	ClassDB::bind_method(D_METHOD("entity_count"), &CgameMassEntity::entity_count);
	ClassDB::bind_method(D_METHOD("archetype_count"), &CgameMassEntity::archetype_count);
	ClassDB::bind_method(D_METHOD("create", "fragments"), &CgameMassEntity::create);
	ClassDB::bind_method(D_METHOD("create_many", "fragments", "count"), &CgameMassEntity::create_many);
	ClassDB::bind_method(D_METHOD("is_alive", "id"), &CgameMassEntity::is_alive);
	ClassDB::bind_method(D_METHOD("destroy", "id"), &CgameMassEntity::destroy);
	ClassDB::bind_method(D_METHOD("clear"), &CgameMassEntity::clear);
	ClassDB::bind_method(D_METHOD("has_fragment", "id", "fragment"), &CgameMassEntity::has_fragment);
	ClassDB::bind_method(D_METHOD("get_value", "id", "fragment"), &CgameMassEntity::get_value);
	ClassDB::bind_method(D_METHOD("set_value", "id", "fragment", "value"), &CgameMassEntity::set_value);
	ClassDB::bind_method(D_METHOD("query", "required"), &CgameMassEntity::query);
	ClassDB::bind_method(D_METHOD("get_entity_ids", "required"), &CgameMassEntity::get_entity_ids);
	ClassDB::bind_method(D_METHOD("get_column", "fragment"), &CgameMassEntity::get_column);
	ClassDB::bind_method(D_METHOD("add_processor", "name", "required", "callable", "depends_on", "parallel"), &CgameMassEntity::add_processor, DEFVAL(PackedStringArray()), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("add_integrate_processor", "name", "position_fragment", "velocity_fragment", "depends_on"), &CgameMassEntity::add_integrate_processor, DEFVAL(PackedStringArray()));
	ClassDB::bind_method(D_METHOD("add_crowd_avoidance_processor", "name", "position_fragment", "velocity_fragment", "preferred_fragment", "radius", "max_speed", "time_horizon", "neighbor_dist", "max_neighbors", "depends_on", "ground_xz"), &CgameMassEntity::add_crowd_avoidance_processor, DEFVAL(PackedStringArray()), DEFVAL(true));
	ClassDB::bind_method(D_METHOD("remove_processor", "name"), &CgameMassEntity::remove_processor);
	ClassDB::bind_method(D_METHOD("processor_order"), &CgameMassEntity::processor_order);
	ClassDB::bind_method(D_METHOD("run", "delta"), &CgameMassEntity::run);
}
