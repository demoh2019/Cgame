/**************************************************************************/
/*  cgame_net_schema.h                                                    */
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

#include "cgame_bit_stream.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

// Native port of scripts/shared/net_schema.gd (byte-compatible wire format, see README.md).
class CgameNetSchema : public RefCounted {
	GDCLASS(CgameNetSchema, RefCounted);

public:
	enum FieldType {
		FIELD_INT,
		FIELD_FLOAT,
		FIELD_VEC3,
		FIELD_QUAT,
		FIELD_BOOL,
		FIELD_STRING,
		FIELD_ENUM,
	};

	enum Condition {
		COND_ALWAYS,
		COND_OWNER_ONLY,
		COND_INITIAL_ONLY,
		COND_ON_CHANGE,
	};

private:
	struct Field {
		String name;
		String type_name;
		String cond_name;
		FieldType type = FIELD_INT;
		Condition cond = COND_ON_CHANGE;
		int raw_bits = 0; // As given (used by the hash).
		int bits = 1; // Effective wire bits.
		double min = 0.0;
		double max = 0.0;
	};

	struct QValue {
		int64_t q[4] = { 0, 0, 0, 0 };
		String s;
		bool operator==(const QValue &p_o) const {
			return q[0] == p_o.q[0] && q[1] == p_o.q[1] && q[2] == p_o.q[2] && q[3] == p_o.q[3] && s == p_o.s;
		}
	};

	LocalVector<Field> fields;
	Dictionary schema_dict;
	uint32_t hash_value = 0;

	QValue _quant(const Field &p_f, const Variant &p_v) const;
	Variant _dequant(const Field &p_f, const QValue &p_q) const;
	void _write_field(CgameBitWriter &p_w, const Field &p_f, const QValue &p_q) const;
	QValue _read_field(CgameBitReader &p_r, const Field &p_f) const;
	bool _should_send(const Field &p_f, const Dictionary &p_state, const Dictionary &p_baseline, bool p_is_owner) const;

protected:
	static void _bind_methods();

public:
	bool set_schema(const Dictionary &p_schema);
	Dictionary get_schema() const { return schema_dict; }
	int get_field_count() const { return fields.size(); }
	int64_t get_schema_hash() const { return hash_value; }

	PackedByteArray serialize(const Dictionary &p_state, const Dictionary &p_baseline, bool p_is_owner) const;
	Dictionary deserialize(const PackedByteArray &p_bytes, const Dictionary &p_baseline) const;
	PackedByteArray serialize_versioned(const Dictionary &p_state, const Dictionary &p_baseline, bool p_is_owner) const;
	Dictionary deserialize_versioned(const PackedByteArray &p_bytes, const Dictionary &p_baseline) const;

	static Dictionary make_field(const String &p_name, const String &p_type, int p_bits = 0, double p_min = 0.0, double p_max = 0.0, const String &p_condition = "on_change");
	static int bits_for_range(double p_min, double p_max);
};
