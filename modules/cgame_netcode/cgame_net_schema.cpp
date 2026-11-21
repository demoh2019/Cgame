/**************************************************************************/
/*  cgame_net_schema.cpp                                                  */
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

#include "cgame_net_schema.h"

#include "core/object/class_db.h"
#include "core/variant/array.h"

static bool _parse_type(const String &p_name, CgameNetSchema::FieldType &r_type) {
	if (p_name == "int") {
		r_type = CgameNetSchema::FIELD_INT;
	} else if (p_name == "float") {
		r_type = CgameNetSchema::FIELD_FLOAT;
	} else if (p_name == "vec3") {
		r_type = CgameNetSchema::FIELD_VEC3;
	} else if (p_name == "quat") {
		r_type = CgameNetSchema::FIELD_QUAT;
	} else if (p_name == "bool") {
		r_type = CgameNetSchema::FIELD_BOOL;
	} else if (p_name == "string") {
		r_type = CgameNetSchema::FIELD_STRING;
	} else if (p_name == "enum") {
		r_type = CgameNetSchema::FIELD_ENUM;
	} else {
		return false;
	}
	return true;
}

static bool _parse_condition(const String &p_name, CgameNetSchema::Condition &r_cond) {
	if (p_name == "always") {
		r_cond = CgameNetSchema::COND_ALWAYS;
	} else if (p_name == "owner_only") {
		r_cond = CgameNetSchema::COND_OWNER_ONLY;
	} else if (p_name == "initial_only") {
		r_cond = CgameNetSchema::COND_INITIAL_ONLY;
	} else if (p_name == "on_change") {
		r_cond = CgameNetSchema::COND_ON_CHANGE;
	} else {
		return false;
	}
	return true;
}

bool CgameNetSchema::set_schema(const Dictionary &p_schema) {
	fields.clear();
	schema_dict = Dictionary();
	hash_value = 0;

	ERR_FAIL_COND_V_MSG(!p_schema.has("fields") || p_schema["fields"].get_type() != Variant::ARRAY, false, "Schema needs a \"fields\" Array.");
	Array src = p_schema["fields"];
	LocalVector<Field> parsed;
	Array normalized;
	String joined;
	for (int i = 0; i < src.size(); i++) {
		ERR_FAIL_COND_V_MSG(src[i].get_type() != Variant::DICTIONARY, false, "Schema field entries must be Dictionaries.");
		Dictionary d = src[i];
		ERR_FAIL_COND_V_MSG(!d.has("name") || !d.has("type"), false, "Schema field needs \"name\" and \"type\".");
		Field f;
		f.name = String(d["name"]);
		f.type_name = String(d["type"]);
		ERR_FAIL_COND_V_MSG(!_parse_type(f.type_name, f.type), false, vformat("Unknown field type \"%s\".", f.type_name));
		f.cond_name = String(d.get("condition", "on_change"));
		ERR_FAIL_COND_V_MSG(!_parse_condition(f.cond_name, f.cond), false, vformat("Unknown field condition \"%s\".", f.cond_name));
		f.raw_bits = int(d.get("bits", 0));
		f.min = double(d.get("min", 0.0));
		f.max = double(d.get("max", 0.0));
		f.bits = f.type == FIELD_BOOL ? 1 : CLAMP(f.raw_bits, 1, 32);
		parsed.push_back(f);
		normalized.push_back(make_field(f.name, f.type_name, f.raw_bits, f.min, f.max, f.cond_name));
		if (i > 0) {
			joined += "|";
		}
		joined += vformat("%s:%s:%d:%.6f:%.6f:%s", f.name, f.type_name, f.raw_bits, f.min, f.max, f.cond_name);
	}
	fields = parsed;
	schema_dict["fields"] = normalized;
	hash_value = joined.hash();
	return true;
}

CgameNetSchema::QValue CgameNetSchema::_quant(const Field &p_f, const Variant &p_v) const {
	QValue out;
	switch (p_f.type) {
		case FIELD_BOOL:
			out.q[0] = bool(p_v) ? 1 : 0;
			break;
		case FIELD_INT:
		case FIELD_ENUM: {
			int64_t span = (int64_t(1) << p_f.bits) - 1;
			out.q[0] = CLAMP(int64_t(p_v) - int64_t(p_f.min), int64_t(0), span);
		} break;
		case FIELD_FLOAT:
			out.q[0] = CgameNetQuant::quantize_float(double(p_v), p_f.min, p_f.max, p_f.bits);
			break;
		case FIELD_VEC3: {
			Vector3 v = p_v;
			out.q[0] = CgameNetQuant::quantize_float(v.x, p_f.min, p_f.max, p_f.bits);
			out.q[1] = CgameNetQuant::quantize_float(v.y, p_f.min, p_f.max, p_f.bits);
			out.q[2] = CgameNetQuant::quantize_float(v.z, p_f.min, p_f.max, p_f.bits);
		} break;
		case FIELD_QUAT: {
			Quaternion q = p_v;
			out.q[0] = CgameNetQuant::quantize_float(q.x, -1.0, 1.0, p_f.bits);
			out.q[1] = CgameNetQuant::quantize_float(q.y, -1.0, 1.0, p_f.bits);
			out.q[2] = CgameNetQuant::quantize_float(q.z, -1.0, 1.0, p_f.bits);
			out.q[3] = CgameNetQuant::quantize_float(q.w, -1.0, 1.0, p_f.bits);
		} break;
		case FIELD_STRING: {
			// Matches str(v).substr(0, 255) followed by the 255-byte UTF-8 cap on the wire.
			out.s = String(p_v).substr(0, 255);
		} break;
	}
	return out;
}

Variant CgameNetSchema::_dequant(const Field &p_f, const QValue &p_q) const {
	switch (p_f.type) {
		case FIELD_BOOL:
			return p_q.q[0] == 1;
		case FIELD_INT:
		case FIELD_ENUM:
			return int64_t(p_q.q[0] + int64_t(p_f.min));
		case FIELD_FLOAT:
			return CgameNetQuant::dequantize_float(p_q.q[0], p_f.min, p_f.max, p_f.bits);
		case FIELD_VEC3:
			return Vector3(CgameNetQuant::dequantize_float(p_q.q[0], p_f.min, p_f.max, p_f.bits),
					CgameNetQuant::dequantize_float(p_q.q[1], p_f.min, p_f.max, p_f.bits),
					CgameNetQuant::dequantize_float(p_q.q[2], p_f.min, p_f.max, p_f.bits));
		case FIELD_QUAT: {
			Quaternion r(CgameNetQuant::dequantize_float(p_q.q[0], -1.0, 1.0, p_f.bits),
					CgameNetQuant::dequantize_float(p_q.q[1], -1.0, 1.0, p_f.bits),
					CgameNetQuant::dequantize_float(p_q.q[2], -1.0, 1.0, p_f.bits),
					CgameNetQuant::dequantize_float(p_q.q[3], -1.0, 1.0, p_f.bits));
			return r.length() > 0.0001f ? r.normalized() : Quaternion();
		}
		case FIELD_STRING:
			return p_q.s;
	}
	return Variant();
}

void CgameNetSchema::_write_field(CgameBitWriter &p_w, const Field &p_f, const QValue &p_q) const {
	switch (p_f.type) {
		case FIELD_BOOL:
			p_w.write_bits(p_q.q[0], 1);
			break;
		case FIELD_STRING: {
			CharString utf8 = p_q.s.utf8();
			int n = MIN((int)utf8.length(), 255);
			p_w.write_bits(n, 8);
			for (int i = 0; i < n; i++) {
				p_w.write_bits((uint8_t)utf8[i], 8);
			}
		} break;
		case FIELD_VEC3:
			for (int i = 0; i < 3; i++) {
				p_w.write_bits(p_q.q[i], p_f.bits);
			}
			break;
		case FIELD_QUAT:
			for (int i = 0; i < 4; i++) {
				p_w.write_bits(p_q.q[i], p_f.bits);
			}
			break;
		default:
			p_w.write_bits(p_q.q[0], p_f.bits);
			break;
	}
}

CgameNetSchema::QValue CgameNetSchema::_read_field(CgameBitReader &p_r, const Field &p_f) const {
	QValue out;
	switch (p_f.type) {
		case FIELD_BOOL:
			out.q[0] = p_r.read_bits(1);
			break;
		case FIELD_STRING: {
			int n = (int)p_r.read_bits(8);
			Vector<uint8_t> raw;
			for (int i = 0; i < n; i++) {
				raw.push_back((uint8_t)p_r.read_bits(8));
			}
			if (raw.size() > 0) {
				out.s.append_utf8((const char *)raw.ptr(), raw.size());
			}
		} break;
		case FIELD_VEC3:
			for (int i = 0; i < 3; i++) {
				out.q[i] = p_r.read_bits(p_f.bits);
			}
			break;
		case FIELD_QUAT:
			for (int i = 0; i < 4; i++) {
				out.q[i] = p_r.read_bits(p_f.bits);
			}
			break;
		default:
			out.q[0] = p_r.read_bits(p_f.bits);
			break;
	}
	return out;
}

bool CgameNetSchema::_should_send(const Field &p_f, const Dictionary &p_state, const Dictionary &p_baseline, bool p_is_owner) const {
	if (!p_state.has(p_f.name)) {
		return false;
	}
	if (p_f.cond == COND_OWNER_ONLY && !p_is_owner) {
		return false;
	}
	if (p_f.cond == COND_INITIAL_ONLY) {
		return p_baseline.is_empty() || !p_baseline.has(p_f.name);
	}
	if (p_f.cond == COND_ALWAYS) {
		return true;
	}
	if (!p_baseline.has(p_f.name)) {
		return true;
	}
	return !(_quant(p_f, p_state[p_f.name]) == _quant(p_f, p_baseline[p_f.name]));
}

PackedByteArray CgameNetSchema::serialize(const Dictionary &p_state, const Dictionary &p_baseline, bool p_is_owner) const {
	Ref<CgameBitWriter> w;
	w.instantiate();
	LocalVector<bool> send;
	send.resize(fields.size());
	for (uint32_t i = 0; i < fields.size(); i++) {
		send[i] = _should_send(fields[i], p_state, p_baseline, p_is_owner);
		w->write_bits(send[i] ? 1 : 0, 1);
	}
	for (uint32_t i = 0; i < fields.size(); i++) {
		if (send[i]) {
			_write_field(**w, fields[i], _quant(fields[i], p_state[fields[i].name]));
		}
	}
	return w->get_bytes();
}

Dictionary CgameNetSchema::deserialize(const PackedByteArray &p_bytes, const Dictionary &p_baseline) const {
	Ref<CgameBitReader> r = CgameBitReader::create(p_bytes);
	LocalVector<bool> present;
	present.resize(fields.size());
	for (uint32_t i = 0; i < fields.size(); i++) {
		present[i] = r->read_bits(1) == 1;
	}
	Dictionary out = p_baseline.duplicate();
	for (uint32_t i = 0; i < fields.size(); i++) {
		if (present[i]) {
			out[fields[i].name] = _dequant(fields[i], _read_field(**r, fields[i]));
		}
	}
	return out;
}

PackedByteArray CgameNetSchema::serialize_versioned(const Dictionary &p_state, const Dictionary &p_baseline, bool p_is_owner) const {
	PackedByteArray body = serialize(p_state, p_baseline, p_is_owner);
	PackedByteArray out;
	out.resize(4 + body.size());
	uint8_t *w = out.ptrw();
	w[0] = hash_value & 0xFF;
	w[1] = (hash_value >> 8) & 0xFF;
	w[2] = (hash_value >> 16) & 0xFF;
	w[3] = (hash_value >> 24) & 0xFF;
	if (body.size() > 0) {
		memcpy(w + 4, body.ptr(), body.size());
	}
	return out;
}

Dictionary CgameNetSchema::deserialize_versioned(const PackedByteArray &p_bytes, const Dictionary &p_baseline) const {
	Dictionary res;
	res["ok"] = false;
	res["state"] = Dictionary();
	if (p_bytes.size() < 4) {
		return res;
	}
	const uint8_t *p = p_bytes.ptr();
	uint32_t h = uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
	if (h != hash_value) {
		return res;
	}
	PackedByteArray body;
	body.resize(p_bytes.size() - 4);
	if (body.size() > 0) {
		memcpy(body.ptrw(), p + 4, body.size());
	}
	res["ok"] = true;
	res["state"] = deserialize(body, p_baseline);
	return res;
}

Dictionary CgameNetSchema::make_field(const String &p_name, const String &p_type, int p_bits, double p_min, double p_max, const String &p_condition) {
	Dictionary d;
	d["name"] = p_name;
	d["type"] = p_type;
	d["bits"] = p_bits;
	d["min"] = p_min;
	d["max"] = p_max;
	d["condition"] = p_condition;
	return d;
}

int CgameNetSchema::bits_for_range(double p_min, double p_max) {
	int64_t count = int64_t(p_max - p_min) + 1;
	int b = 1;
	while ((int64_t(1) << b) < count && b < 32) {
		b++;
	}
	return b;
}

void CgameNetSchema::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_schema", "schema"), &CgameNetSchema::set_schema);
	ClassDB::bind_method(D_METHOD("get_schema"), &CgameNetSchema::get_schema);
	ClassDB::bind_method(D_METHOD("get_field_count"), &CgameNetSchema::get_field_count);
	ClassDB::bind_method(D_METHOD("get_schema_hash"), &CgameNetSchema::get_schema_hash);
	ClassDB::bind_method(D_METHOD("serialize", "state", "baseline", "is_owner"), &CgameNetSchema::serialize);
	ClassDB::bind_method(D_METHOD("deserialize", "bytes", "baseline"), &CgameNetSchema::deserialize);
	ClassDB::bind_method(D_METHOD("serialize_versioned", "state", "baseline", "is_owner"), &CgameNetSchema::serialize_versioned);
	ClassDB::bind_method(D_METHOD("deserialize_versioned", "bytes", "baseline"), &CgameNetSchema::deserialize_versioned);
	ClassDB::bind_static_method("CgameNetSchema", D_METHOD("make_field", "name", "type", "bits", "min_value", "max_value", "condition"), &CgameNetSchema::make_field, DEFVAL(0), DEFVAL(0.0), DEFVAL(0.0), DEFVAL("on_change"));
	ClassDB::bind_static_method("CgameNetSchema", D_METHOD("bits_for_range", "min_value", "max_value"), &CgameNetSchema::bits_for_range);
}
