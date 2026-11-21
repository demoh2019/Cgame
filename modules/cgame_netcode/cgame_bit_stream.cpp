/**************************************************************************/
/*  cgame_bit_stream.cpp                                                  */
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

#include "cgame_bit_stream.h"

#include "core/object/class_db.h"

// ---------------------------------------------------------------- Writer

void CgameBitWriter::write_bits(int64_t p_value, int p_bits) {
	int n = CLAMP(p_bits, 0, 64);
	uint64_t v = (uint64_t)p_value;
	if (n < 64) {
		v &= (uint64_t(1) << n) - 1;
	}
	while (n > 0) {
		int off = int(bitpos & 7);
		if (off == 0) {
			bytes.push_back(0);
		}
		int take = MIN(8 - off, n);
		bytes[bytes.size() - 1] |= uint8_t((v & ((uint64_t(1) << take) - 1)) << off);
		v >>= take;
		n -= take;
		bitpos += take;
	}
}

void CgameBitWriter::write_bool(bool p_value) {
	write_bits(p_value ? 1 : 0, 1);
}

void CgameBitWriter::write_varint(int64_t p_value) {
	uint64_t v = (uint64_t)p_value;
	do {
		uint64_t group = v & 0x7F;
		v >>= 7;
		if (v != 0) {
			group |= 0x80;
		}
		write_bits((int64_t)group, 8);
	} while (v != 0);
}

void CgameBitWriter::write_signed_varint(int64_t p_value) {
	uint64_t zz = (uint64_t(p_value) << 1) ^ uint64_t(p_value >> 63);
	write_varint((int64_t)zz);
}

void CgameBitWriter::write_float(double p_value, double p_min, double p_max, int p_bits) {
	int bits = CLAMP(p_bits, 1, 32);
	write_bits(CgameNetQuant::quantize_float(p_value, p_min, p_max, bits), bits);
}

void CgameBitWriter::write_angle(double p_radians, int p_bits) {
	int bits = CLAMP(p_bits, 1, 32);
	write_bits(CgameNetQuant::quantize_angle(p_radians, bits), bits);
}

void CgameBitWriter::write_vector3(const Vector3 &p_value, double p_min, double p_max, int p_bits_per_axis) {
	write_float(p_value.x, p_min, p_max, p_bits_per_axis);
	write_float(p_value.y, p_min, p_max, p_bits_per_axis);
	write_float(p_value.z, p_min, p_max, p_bits_per_axis);
}

void CgameBitWriter::write_quaternion(const Quaternion &p_value, int p_bits_per_component) {
	int bits = CLAMP(p_bits_per_component, 1, 32);
	Quaternion q = p_value;
	if (q.length_squared() < 1e-12f) {
		q = Quaternion();
	} else {
		q = q.normalized();
	}
	double c[4] = { q.x, q.y, q.z, q.w };
	int largest = 0;
	for (int i = 1; i < 4; i++) {
		if (Math::abs(c[i]) > Math::abs(c[largest])) {
			largest = i;
		}
	}
	double sign = c[largest] < 0.0 ? -1.0 : 1.0;
	write_bits(largest, 2);
	for (int i = 0; i < 4; i++) {
		if (i != largest) {
			write_bits(CgameNetQuant::quantize_float(c[i] * sign, -QUAT_RANGE, QUAT_RANGE, bits), bits);
		}
	}
}

void CgameBitWriter::write_float32(double p_value) {
	float f = (float)p_value;
	uint32_t u;
	memcpy(&u, &f, 4);
	write_bits(u, 32);
}

void CgameBitWriter::write_string(const String &p_value) {
	CharString utf8 = p_value.utf8();
	int n = MIN((int)utf8.length(), 255);
	write_bits(n, 8);
	for (int i = 0; i < n; i++) {
		write_bits((uint8_t)utf8[i], 8);
	}
}

void CgameBitWriter::write_bytes(const PackedByteArray &p_bytes) {
	for (int i = 0; i < p_bytes.size(); i++) {
		write_bits(p_bytes[i], 8);
	}
}

void CgameBitWriter::align_to_byte() {
	bitpos = (bitpos + 7) & ~int64_t(7);
}

void CgameBitWriter::clear() {
	bytes.clear();
	bitpos = 0;
}

PackedByteArray CgameBitWriter::get_bytes() const {
	PackedByteArray out;
	out.resize(bytes.size());
	if (bytes.size() > 0) {
		memcpy(out.ptrw(), bytes.ptr(), bytes.size());
	}
	return out;
}

void CgameBitWriter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("write_bits", "value", "bits"), &CgameBitWriter::write_bits);
	ClassDB::bind_method(D_METHOD("write_bool", "value"), &CgameBitWriter::write_bool);
	ClassDB::bind_method(D_METHOD("write_varint", "value"), &CgameBitWriter::write_varint);
	ClassDB::bind_method(D_METHOD("write_signed_varint", "value"), &CgameBitWriter::write_signed_varint);
	ClassDB::bind_method(D_METHOD("write_float", "value", "min_value", "max_value", "bits"), &CgameBitWriter::write_float);
	ClassDB::bind_method(D_METHOD("write_angle", "radians", "bits"), &CgameBitWriter::write_angle);
	ClassDB::bind_method(D_METHOD("write_vector3", "value", "min_value", "max_value", "bits_per_axis"), &CgameBitWriter::write_vector3);
	ClassDB::bind_method(D_METHOD("write_quaternion", "value", "bits_per_component"), &CgameBitWriter::write_quaternion, DEFVAL(10));
	ClassDB::bind_method(D_METHOD("write_float32", "value"), &CgameBitWriter::write_float32);
	ClassDB::bind_method(D_METHOD("write_string", "value"), &CgameBitWriter::write_string);
	ClassDB::bind_method(D_METHOD("write_bytes", "bytes"), &CgameBitWriter::write_bytes);
	ClassDB::bind_method(D_METHOD("align_to_byte"), &CgameBitWriter::align_to_byte);
	ClassDB::bind_method(D_METHOD("clear"), &CgameBitWriter::clear);
	ClassDB::bind_method(D_METHOD("get_bytes"), &CgameBitWriter::get_bytes);
	ClassDB::bind_method(D_METHOD("get_bit_count"), &CgameBitWriter::get_bit_count);
	ClassDB::bind_method(D_METHOD("get_byte_count"), &CgameBitWriter::get_byte_count);
}

// ---------------------------------------------------------------- Reader

void CgameBitReader::set_bytes(const PackedByteArray &p_bytes) {
	bytes = p_bytes;
	bitpos = 0;
	overflowed = false;
}

void CgameBitReader::set_bit_position(int64_t p_pos) {
	bitpos = CLAMP(p_pos, int64_t(0), int64_t(bytes.size()) * 8);
}

int64_t CgameBitReader::get_bits_remaining() const {
	return int64_t(bytes.size()) * 8 - bitpos;
}

int64_t CgameBitReader::read_bits(int p_bits) {
	int n = CLAMP(p_bits, 0, 64);
	uint64_t v = 0;
	int got = 0;
	while (n > 0) {
		int64_t byte_i = bitpos >> 3;
		if (byte_i >= bytes.size()) {
			overflowed = true;
			break;
		}
		int off = int(bitpos & 7);
		int take = MIN(8 - off, n);
		uint64_t part = (uint64_t(bytes[byte_i]) >> off) & ((uint64_t(1) << take) - 1);
		v |= part << got;
		got += take;
		n -= take;
		bitpos += take;
	}
	return (int64_t)v;
}

bool CgameBitReader::read_bool() {
	return read_bits(1) == 1;
}

int64_t CgameBitReader::read_varint() {
	uint64_t v = 0;
	for (int i = 0; i < 10; i++) {
		uint64_t group = (uint64_t)read_bits(8);
		v |= (group & 0x7F) << (7 * i);
		if ((group & 0x80) == 0 || overflowed) {
			break;
		}
	}
	return (int64_t)v;
}

int64_t CgameBitReader::read_signed_varint() {
	uint64_t zz = (uint64_t)read_varint();
	return int64_t(zz >> 1) ^ -int64_t(zz & 1);
}

double CgameBitReader::read_float(double p_min, double p_max, int p_bits) {
	int bits = CLAMP(p_bits, 1, 32);
	return CgameNetQuant::dequantize_float(read_bits(bits), p_min, p_max, bits);
}

double CgameBitReader::read_angle(int p_bits) {
	int bits = CLAMP(p_bits, 1, 32);
	return CgameNetQuant::dequantize_angle(read_bits(bits), bits);
}

Vector3 CgameBitReader::read_vector3(double p_min, double p_max, int p_bits_per_axis) {
	double x = read_float(p_min, p_max, p_bits_per_axis);
	double y = read_float(p_min, p_max, p_bits_per_axis);
	double z = read_float(p_min, p_max, p_bits_per_axis);
	return Vector3(x, y, z);
}

Quaternion CgameBitReader::read_quaternion(int p_bits_per_component) {
	int bits = CLAMP(p_bits_per_component, 1, 32);
	int largest = (int)read_bits(2);
	double c[4] = { 0, 0, 0, 0 };
	double sum = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i != largest) {
			c[i] = CgameNetQuant::dequantize_float(read_bits(bits), -CgameBitWriter::QUAT_RANGE, CgameBitWriter::QUAT_RANGE, bits);
			sum += c[i] * c[i];
		}
	}
	c[largest] = Math::sqrt(MAX(0.0, 1.0 - sum));
	Quaternion q(c[0], c[1], c[2], c[3]);
	return q.length_squared() > 1e-12f ? q.normalized() : Quaternion();
}

double CgameBitReader::read_float32() {
	uint32_t u = (uint32_t)read_bits(32);
	float f;
	memcpy(&f, &u, 4);
	return f;
}

String CgameBitReader::read_string() {
	int n = (int)read_bits(8);
	Vector<uint8_t> raw;
	for (int i = 0; i < n; i++) {
		raw.push_back((uint8_t)read_bits(8));
	}
	String s;
	if (raw.size() > 0) {
		s.append_utf8((const char *)raw.ptr(), raw.size());
	}
	return s;
}

PackedByteArray CgameBitReader::read_bytes(int p_count) {
	PackedByteArray out;
	for (int i = 0; i < p_count && !overflowed; i++) {
		out.push_back((uint8_t)read_bits(8));
	}
	return out;
}

void CgameBitReader::align_to_byte() {
	bitpos = MIN((bitpos + 7) & ~int64_t(7), int64_t(bytes.size()) * 8);
}

Ref<CgameBitReader> CgameBitReader::create(const PackedByteArray &p_bytes) {
	Ref<CgameBitReader> r;
	r.instantiate();
	r->set_bytes(p_bytes);
	return r;
}

void CgameBitReader::_bind_methods() {
	ClassDB::bind_static_method("CgameBitReader", D_METHOD("create", "bytes"), &CgameBitReader::create);
	ClassDB::bind_method(D_METHOD("set_bytes", "bytes"), &CgameBitReader::set_bytes);
	ClassDB::bind_method(D_METHOD("get_bytes"), &CgameBitReader::get_bytes);
	ClassDB::bind_method(D_METHOD("set_bit_position", "position"), &CgameBitReader::set_bit_position);
	ClassDB::bind_method(D_METHOD("get_bit_position"), &CgameBitReader::get_bit_position);
	ClassDB::bind_method(D_METHOD("get_bits_remaining"), &CgameBitReader::get_bits_remaining);
	ClassDB::bind_method(D_METHOD("is_overflowed"), &CgameBitReader::is_overflowed);
	ClassDB::bind_method(D_METHOD("read_bits", "bits"), &CgameBitReader::read_bits);
	ClassDB::bind_method(D_METHOD("read_bool"), &CgameBitReader::read_bool);
	ClassDB::bind_method(D_METHOD("read_varint"), &CgameBitReader::read_varint);
	ClassDB::bind_method(D_METHOD("read_signed_varint"), &CgameBitReader::read_signed_varint);
	ClassDB::bind_method(D_METHOD("read_float", "min_value", "max_value", "bits"), &CgameBitReader::read_float);
	ClassDB::bind_method(D_METHOD("read_angle", "bits"), &CgameBitReader::read_angle);
	ClassDB::bind_method(D_METHOD("read_vector3", "min_value", "max_value", "bits_per_axis"), &CgameBitReader::read_vector3);
	ClassDB::bind_method(D_METHOD("read_quaternion", "bits_per_component"), &CgameBitReader::read_quaternion, DEFVAL(10));
	ClassDB::bind_method(D_METHOD("read_float32"), &CgameBitReader::read_float32);
	ClassDB::bind_method(D_METHOD("read_string"), &CgameBitReader::read_string);
	ClassDB::bind_method(D_METHOD("read_bytes", "count"), &CgameBitReader::read_bytes);
	ClassDB::bind_method(D_METHOD("align_to_byte"), &CgameBitReader::align_to_byte);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY, "bytes"), "set_bytes", "get_bytes");
}
