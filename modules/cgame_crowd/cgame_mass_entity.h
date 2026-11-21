/**************************************************************************/
/*  cgame_mass_entity.h                                                   */
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

#pragma once

#include "cgame_crowd_avoidance.h"

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// MassEntity-style data-oriented runtime: archetypes with structure-of-arrays
// fragments, generational entity ids, and processors executed in dependency order.
//
// Design reference (concepts only, no code copied): Unreal Engine MassEntity and the
// generic archetype ECS pattern (Unity DOTS, flecs). Original implementation.
//
// Fragment types: PackedVector3Array (Vector3), PackedFloat32Array (float),
// PackedInt32Array (int). Entities are removed with swap-remove so every archetype
// stays dense.
class CgameMassEntity : public RefCounted {
	GDCLASS(CgameMassEntity, RefCounted);

	static constexpr int INDEX_BITS = 24;
	static constexpr int64_t INDEX_MASK = (1 << INDEX_BITS) - 1;
	static constexpr uint32_t MAX_GENERATION = 0x3FFFFF;

	struct Column {
		Variant::Type type = Variant::NIL;
		PackedVector3Array v3;
		PackedFloat32Array f;
		PackedInt32Array i;
	};

	struct Archetype {
		LocalVector<String> names; // Sorted.
		LocalVector<Column> columns; // Parallel to names.
		PackedInt32Array slots; // Entity slot per row.
		int count = 0;

		int find(const String &p_name) const {
			for (uint32_t k = 0; k < names.size(); k++) {
				if (names[k] == p_name) {
					return (int)k;
				}
			}
			return -1;
		}
	};

	enum ProcessorKind {
		PROCESSOR_SCRIPT,
		PROCESSOR_INTEGRATE,
		PROCESSOR_CROWD_AVOIDANCE,
	};

	struct Processor {
		String name;
		ProcessorKind kind = PROCESSOR_SCRIPT;
		PackedStringArray required;
		PackedStringArray depends_on;
		Callable callable;
		bool parallel = false;
		// Built-in processors.
		String position_fragment;
		String velocity_fragment;
		String preferred_fragment;
		bool ground_xz = true;
		CgameCrowdAvoidance::Params crowd;
	};

	HashMap<String, Variant::Type> fragment_types;
	HashMap<String, int> archetype_lookup;
	LocalVector<Archetype> archetypes;
	LocalVector<uint32_t> generations;
	LocalVector<int32_t> slot_archetype;
	LocalVector<int32_t> slot_row;
	LocalVector<uint32_t> free_slots;
	int alive_count = 0;

	LocalVector<Processor> processors;
	LocalVector<int> order;
	bool order_dirty = true;
	bool running = false;

	static bool _is_fragment_type(int p_type);
	static bool _value_fits(Variant::Type p_type, const Variant &p_value);
	static void _push_value(Column &r_column, const Variant &p_value);
	static void _push_default(Column &r_column);
	static void _swap_remove(Column &r_column, int p_row, int p_last);
	static Variant _read_value(const Column &p_column, int p_row);
	static void _write_value(Column &r_column, int p_row, const Variant &p_value);
	static int _column_size(const Column &p_column);
	static void _clear_column(Column &r_column);

	int64_t _pack(uint32_t p_slot, uint32_t p_generation) const { return ((int64_t)p_generation << INDEX_BITS) | (int64_t)p_slot; }
	int _archetype_for(const Vector<String> &p_sorted_names);
	bool _archetype_has_all(const Archetype &p_archetype, const PackedStringArray &p_required) const;
	uint32_t _allocate_slot();
	Dictionary _build_chunk(const Archetype &p_archetype) const;
	void _run_script_processor(const Processor &p_processor, double p_delta);
	void _run_integrate(const Processor &p_processor, double p_delta);
	void _run_crowd(const Processor &p_processor, double p_delta);
	void _rebuild_order();
	void _destroy_slot(uint32_t p_slot);

protected:
	static void _bind_methods();

public:
	void define_fragment(const String &p_name, int p_type);
	int entity_count() const { return alive_count; }
	int archetype_count() const { return (int)archetypes.size(); }

	int64_t create(const Dictionary &p_fragments);
	PackedInt64Array create_many(const Dictionary &p_fragments, int p_count);
	bool is_alive(int64_t p_id) const;
	void destroy(int64_t p_id);
	void clear();

	bool has_fragment(int64_t p_id, const String &p_fragment) const;
	Variant get_value(int64_t p_id, const String &p_fragment) const;
	void set_value(int64_t p_id, const String &p_fragment, const Variant &p_value);

	Array query(const PackedStringArray &p_required) const;
	PackedInt64Array get_entity_ids(const PackedStringArray &p_required) const;
	Variant get_column(const String &p_fragment) const;

	void add_processor(const String &p_name, const PackedStringArray &p_required, const Callable &p_callable, const PackedStringArray &p_depends_on = PackedStringArray(), bool p_parallel = false);
	void add_integrate_processor(const String &p_name, const String &p_position_fragment, const String &p_velocity_fragment, const PackedStringArray &p_depends_on = PackedStringArray());
	void add_crowd_avoidance_processor(const String &p_name, const String &p_position_fragment, const String &p_velocity_fragment, const String &p_preferred_fragment, real_t p_radius, real_t p_max_speed, real_t p_time_horizon, real_t p_neighbor_dist, int p_max_neighbors, const PackedStringArray &p_depends_on = PackedStringArray(), bool p_ground_xz = true);
	void remove_processor(const String &p_name);
	PackedStringArray processor_order();
	void run(double p_delta);
};
