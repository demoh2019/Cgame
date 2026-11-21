/**************************************************************************/
/*  cgame_bit_stream.h                                                    */
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

#include "core/math/math_funcs.h"
#include "core/math/quaternion.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"

// Fixed-point quantization helpers shared by the bit stream and the net schema.
// The math is identical to scripts/shared/net_quantization.gd (round-half-away).
namespace CgameNetQuant {

_FORCE_INLINE_ int64_t levels(int p_bits) {
	return (int64_t(1) << CLAMP(p_bits, 1, 32)) - 1;
}

_FORCE_INLINE_ int64_t quantize_float(double p_v, double p_min, double p_max, int p_bits) {
	double span = p_max - p_min;
	if (span <= 0.0) {
		return 0;
	}
	double t = CLAMP((p_v - p_min) / span, 0.0, 1.0);
	return (int64_t)Math::round(t * double(levels(p_bits)));
}

_FORCE_INLINE_ double dequantize_float(int64_t p_q, double p_min, double p_max, int p_bits) {
	int64_t lv = levels(p_bits);
	double t = double(CLAMP(p_q, int64_t(0), lv)) / double(lv);
	return p_min + t * (p_max - p_min);
}

_FORCE_INLINE_ int64_t quantize_angle(double p_radians, int p_bits) {
	int64_t count = int64_t(1) << CLAMP(p_bits, 1, 32);
	double t = Math::fposmod(p_radians, Math::TAU) / Math::TAU;
	return int64_t(Math::round(t * double(count))) % count;
}

_FORCE_INLINE_ double dequantize_angle(int64_t p_q, int p_bits) {
	int64_t count = int64_t(1) << CLAMP(p_bits, 1, 32);
	int64_t m = p_q % count;
	if (m < 0) {
		m += count;
	}
	return double(m) / double(count) * Math::TAU;
}

} //namespace CgameNetQuant

// LSB-first bit packer. Bit layout matches BitWriter in net_schema.gd.
class CgameBitWriter : public RefCounted {
	GDCLASS(CgameBitWriter, RefCounted);

	LocalVector<uint8_t> bytes;
	int64_t bitpos = 0;

protected:
	static void _bind_methods();

public:
	static constexpr double QUAT_RANGE = 0.70710678118654752;

	void write_bits(int64_t p_value, int p_bits);
	void write_bool(bool p_value);
	void write_varint(int64_t p_value);
	void write_signed_varint(int64_t p_value);
	void write_float(double p_value, double p_min, double p_max, int p_bits);
	void write_angle(double p_radians, int p_bits);
	void write_vector3(const Vector3 &p_value, double p_min, double p_max, int p_bits_per_axis);
	void write_quaternion(const Quaternion &p_value, int p_bits_per_component = 10);
	void write_float32(double p_value);
	void write_string(const String &p_value);
	void write_bytes(const PackedByteArray &p_bytes);
	void align_to_byte();
	void clear();
	PackedByteArray get_bytes() const;
	int64_t get_bit_count() const { return bitpos; }
	int64_t get_byte_count() const { return (bitpos + 7) >> 3; }
};

// Bit reader matching CgameBitWriter. Reading past the end sets the overflow flag and
// yields zero bits (the GDScript reader silently stops; here it is observable).
class CgameBitReader : public RefCounted {
	GDCLASS(CgameBitReader, RefCounted);

	Vector<uint8_t> bytes;
	int64_t bitpos = 0;
	bool overflowed = false;

protected:
	static void _bind_methods();

public:
	void set_bytes(const PackedByteArray &p_bytes);
	PackedByteArray get_bytes() const { return bytes; }
	void set_bit_position(int64_t p_pos);
	int64_t get_bit_position() const { return bitpos; }
	int64_t get_bits_remaining() const;
	bool is_overflowed() const { return overflowed; }

	int64_t read_bits(int p_bits);
	bool read_bool();
	int64_t read_varint();
	int64_t read_signed_varint();
	double read_float(double p_min, double p_max, int p_bits);
	double read_angle(int p_bits);
	Vector3 read_vector3(double p_min, double p_max, int p_bits_per_axis);
	Quaternion read_quaternion(int p_bits_per_component = 10);
	double read_float32();
	String read_string();
	PackedByteArray read_bytes(int p_count);
	void align_to_byte();

	static Ref<CgameBitReader> create(const PackedByteArray &p_bytes);
};
