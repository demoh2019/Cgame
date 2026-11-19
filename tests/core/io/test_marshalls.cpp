/**************************************************************************/
/*  test_marshalls.cpp                                                    */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_marshalls)

#include "core/io/marshalls.h"
#include "core/object/script_language.h"

namespace TestMarshalls {

TEST_CASE("[Marshalls] Unsigned 16 bit integer encoding") {
	uint8_t arr[2];

	unsigned int actual_size = encode_uint16(0x1234, arr);
	CHECK(actual_size == sizeof(uint16_t));
	CHECK_MESSAGE(arr[0] == 0x34, "First encoded byte value should be equal to low order byte value.");
	CHECK_MESSAGE(arr[1] == 0x12, "Last encoded byte value should be equal to high order byte value.");
}

TEST_CASE("[Marshalls] Unsigned 32 bit integer encoding") {
	uint8_t arr[4];

	unsigned int actual_size = encode_uint32(0x12345678, arr);
	CHECK(actual_size == sizeof(uint32_t));
	CHECK_MESSAGE(arr[0] == 0x78, "First encoded byte value should be equal to low order byte value.");
	CHECK(arr[1] == 0x56);
	CHECK(arr[2] == 0x34);
	CHECK_MESSAGE(arr[3] == 0x12, "Last encoded byte value should be equal to high order byte value.");
}

TEST_CASE("[Marshalls] Unsigned 64 bit integer encoding") {
	uint8_t arr[8];

	unsigned int actual_size = encode_uint64(0x0f123456789abcdef, arr);
	CHECK(actual_size == sizeof(uint64_t));
	CHECK_MESSAGE(arr[0] == 0xef, "First encoded byte value should be equal to low order byte value.");
	CHECK(arr[1] == 0xcd);
	CHECK(arr[2] == 0xab);
	CHECK(arr[3] == 0x89);
	CHECK(arr[4] == 0x67);
	CHECK(arr[5] == 0x45);
	CHECK(arr[6] == 0x23);
	CHECK_MESSAGE(arr[7] == 0xf1, "Last encoded byte value should be equal to high order byte value.");
}

TEST_CASE("[Marshalls] Unsigned 16 bit integer decoding") {
	uint8_t arr[] = { 0x34, 0x12 };

	CHECK(decode_uint16(arr) == 0x1234);
}

TEST_CASE("[Marshalls] Unsigned 32 bit integer decoding") {
	uint8_t arr[] = { 0x78, 0x56, 0x34, 0x12 };

	CHECK(decode_uint32(arr) == 0x12345678);
}

TEST_CASE("[Marshalls] Unsigned 64 bit integer decoding") {
	uint8_t arr[] = { 0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0xf1 };

	CHECK(decode_uint64(arr) == 0x0f123456789abcdef);
}

TEST_CASE("[Marshalls] Floating point half precision encoding") {
	uint8_t arr[2];

	// Decimal: 0.33325195
	// IEEE 754 half-precision binary floating-point format:
	// sign exponent (5 bits)    fraction (10 bits)
	//  0        01101               0101010101
	// Hexadecimal: 0x3555
	unsigned int actual_size = encode_half(0.33325195f, arr);
	CHECK(actual_size == sizeof(uint16_t));
	CHECK(arr[0] == 0x55);
	CHECK(arr[1] == 0x35);
}

TEST_CASE("[Marshalls] Floating point single precision encoding") {
	uint8_t arr[4];

	// Decimal: 0.15625
	// IEEE 754 single-precision binary floating-point format:
	// sign exponent (8 bits)    fraction (23 bits)
	//  0       01111100      01000000000000000000000
	// Hexadecimal: 0x3E200000
	unsigned int actual_size = encode_float(0.15625f, arr);
	CHECK(actual_size == sizeof(uint32_t));
	CHECK(arr[0] == 0x00);
	CHECK(arr[1] == 0x00);
	CHECK(arr[2] == 0x20);
	CHECK(arr[3] == 0x3e);
}

TEST_CASE("[Marshalls] Floating point double precision encoding") {
	uint8_t arr[8];

	// Decimal: 0.333333333333333314829616256247390992939472198486328125
	// IEEE 754 double-precision binary floating-point format:
	// sign exponent (11 bits)                  fraction (52 bits)
	//  0      01111111101     0101010101010101010101010101010101010101010101010101
	// Hexadecimal: 0x3FD5555555555555
	unsigned int actual_size = encode_double(0.33333333333333333, arr);
	CHECK(actual_size == sizeof(uint64_t));
	CHECK(arr[0] == 0x55);
	CHECK(arr[1] == 0x55);
	CHECK(arr[2] == 0x55);
	CHECK(arr[3] == 0x55);
	CHECK(arr[4] == 0x55);
	CHECK(arr[5] == 0x55);
	CHECK(arr[6] == 0xd5);
	CHECK(arr[7] == 0x3f);
}

TEST_CASE("[Marshalls] Floating point half precision decoding") {
	uint8_t arr[] = { 0x55, 0x35 };

	// See floating point half precision encoding test case for details behind expected values.
	CHECK(decode_half(arr) == 0.33325195f);
}

TEST_CASE("[Marshalls] Floating point single precision decoding") {
	uint8_t arr[] = { 0x00, 0x00, 0x20, 0x3e };

	// See floating point encoding test case for details behind expected values
	CHECK(decode_float(arr) == 0.15625f);
}

TEST_CASE("[Marshalls] Floating point double precision decoding") {
	uint8_t arr[] = { 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0xd5, 0x3f };

	// See floating point encoding test case for details behind expected values
	CHECK(decode_double(arr) == 0.33333333333333333);
}

TEST_CASE("[Marshalls] C string encoding") {
	char cstring[] = "Godot"; // 5 characters
	uint8_t data[6];

	int actual_size = encode_cstring(cstring, data);
	CHECK(actual_size == 6);
	CHECK(data[0] == 'G');
	CHECK(data[1] == 'o');
	CHECK(data[2] == 'd');
	CHECK(data[3] == 'o');
	CHECK(data[4] == 't');
	CHECK(data[5] == '\0');
}

TEST_CASE("[Marshalls] NIL Variant encoding") {
	int r_len;
	Variant variant;
	uint8_t buffer[4];

	CHECK(encode_variant(variant, buffer, r_len) == OK);
	CHECK_MESSAGE(r_len == 4, "Length == 4 bytes for header.");
	CHECK_MESSAGE(buffer[0] == 0x00, "Variant::NIL");
	CHECK(buffer[1] == 0x00);
	CHECK(buffer[2] == 0x00);
	CHECK(buffer[3] == 0x00);
	// No value
}

TEST_CASE("[Marshalls] INT 32 bit Variant encoding") {
	int r_len;
	Variant variant(0x12345678);
	uint8_t buffer[8];

	CHECK(encode_variant(variant, buffer, r_len) == OK);
	CHECK_MESSAGE(r_len == 8, "Length == 4 bytes for header + 4 bytes for `int32_t`.");
	CHECK_MESSAGE(buffer[0] == 0x02, "Variant::INT");
	CHECK(buffer[1] == 0x00);
	CHECK(buffer[2] == 0x00);
	CHECK(buffer[3] == 0x00);
	// Check value
	CHECK(buffer[4] == 0x78);
	CHECK(buffer[5] == 0x56);
	CHECK(buffer[6] == 0x34);
	CHECK(buffer[7] == 0x12);
}

TEST_CASE("[Marshalls] INT 64 bit Variant encoding") {
	int r_len;
	Variant variant(uint64_t(0x0f123456789abcdef));
	uint8_t buffer[12];

	CHECK(encode_variant(variant, buffer, r_len) == OK);
	CHECK_MESSAGE(r_len == 12, "Length == 4 bytes for header + 8 bytes for `int64_t`.");
	CHECK_MESSAGE(buffer[0] == 0x02, "Variant::INT");
	CHECK(buffer[1] == 0x00);
	CHECK_MESSAGE(buffer[2] == 0x01, "HEADER_DATA_FLAG_64");
	CHECK(buffer[3] == 0x00);
	// Check value
	CHECK(buffer[4] == 0xef);
	CHECK(buffer[5] == 0xcd);
	CHECK(buffer[6] == 0xab);
	CHECK(buffer[7] == 0x89);
	CHECK(buffer[8] == 0x67);
	CHECK(buffer[9] == 0x45);
	CHECK(buffer[10] == 0x23);
	CHECK(buffer[11] == 0xf1);
}

TEST_CASE("[Marshalls] FLOAT single precision Variant encoding") {
	int r_len;
	Variant variant(0.15625f);
	uint8_t buffer[8];

	CHECK(encode_variant(variant, buffer, r_len) == OK);
	CHECK_MESSAGE(r_len == 8, "Length == 4 bytes for header + 4 bytes for `float`.");
	CHECK_MESSAGE(buffer[0] == 0x03, "Variant::FLOAT");
	CHECK(buffer[1] == 0x00);
	CHECK(buffer[2] == 0x00);
	CHECK(buffer[3] == 0x00);
	// Check value
	CHECK(buffer[4] == 0x00);
	CHECK(buffer[5] == 0x00);
	CHECK(buffer[6] == 0x20);
	CHECK(buffer[7] == 0x3e);
}

TEST_CASE("[Marshalls] FLOAT double precision Variant encoding") {
	int r_len;
	Variant variant(0.33333333333333333);
	uint8_t buffer[12];

	CHECK(encode_variant(variant, buffer, r_len) == OK);
	CHECK_MESSAGE(r_len == 12, "Length == 4 bytes for header + 8 bytes for `double`.");
	CHECK_MESSAGE(buffer[0] == 0x03, "Variant::FLOAT");
	CHECK(buffer[1] == 0x00);
	CHECK_MESSAGE(buffer[2] == 0x01, "HEADER_DATA_FLAG_64");
	CHECK(buffer[3] == 0x00);
	// Check value
	CHECK(buffer[4] == 0x55);
	CHECK(buffer[5] == 0x55);
	CHECK(buffer[6] == 0x55);
	CHECK(buffer[7] == 0x55);
	CHECK(buffer[8] == 0x55);
	CHECK(buffer[9] == 0x55);
	CHECK(buffer[10] == 0xd5);
	CHECK(buffer[11] == 0x3f);
}

TEST_CASE("[Marshalls] Invalid data Variant decoding") {
	Variant variant;
	int r_len = 0;
	uint8_t some_buffer[1] = { 0x00 };
	uint8_t out_of_range_type_buffer[4] = { 0xff }; // Greater than Variant::VARIANT_MAX

	ERR_PRINT_OFF;
	CHECK(decode_variant(variant, some_buffer, /* less than 4 */ 1, &r_len) == ERR_INVALID_DATA);
	CHECK(r_len == 0);

	CHECK(decode_variant(variant, out_of_range_type_buffer, 4, &r_len) == ERR_INVALID_DATA);
	CHECK(r_len == 0);
	ERR_PRINT_ON;
}

TEST_CASE("[Marshalls] NIL Variant decoding") {
	Variant variant;
	int r_len;
	uint8_t buffer[] = {
		0x00, 0x00, 0x00, 0x00 // Variant::NIL
	};

	CHECK(decode_variant(variant, buffer, 4, &r_len) == OK);
	CHECK(r_len == 4);
	CHECK(variant == Variant());
}

TEST_CASE("[Marshalls] INT 32 bit Variant decoding") {
	Variant variant;
	int r_len;
	uint8_t buffer[] = {
		0x02, 0x00, 0x00, 0x00, // Variant::INT
		0x78, 0x56, 0x34, 0x12 // value
	};

	CHECK(decode_variant(variant, buffer, 8, &r_len) == OK);
	CHECK(r_len == 8);
	CHECK(variant == Variant(0x12345678));
}

TEST_CASE("[Marshalls] INT 64 bit Variant decoding") {
	Variant variant;
	int r_len;
	uint8_t buffer[] = {
		0x02, 0x00, 0x01, 0x00, // Variant::INT, HEADER_DATA_FLAG_64
		0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0xf1 // value
	};

	CHECK(decode_variant(variant, buffer, 12, &r_len) == OK);
	CHECK(r_len == 12);
	CHECK(variant == Variant(uint64_t(0x0f123456789abcdef)));
}

TEST_CASE("[Marshalls] FLOAT single precision Variant decoding") {
	Variant variant;
	int r_len;
	uint8_t buffer[] = {
		0x03, 0x00, 0x00, 0x00, // Variant::FLOAT
		0x00, 0x00, 0x20, 0x3e // value
	};

	CHECK(decode_variant(variant, buffer, 8, &r_len) == OK);
	CHECK(r_len == 8);
	CHECK(variant == Variant(0.15625f));
}

TEST_CASE("[Marshalls] FLOAT double precision Variant decoding") {
	Variant variant;
	int r_len;
	uint8_t buffer[] = {
		0x03, 0x00, 0x01, 0x00, // Variant::FLOAT, HEADER_DATA_FLAG_64
		0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0xd5, 0x3f // value
	};

	CHECK(decode_variant(variant, buffer, 12, &r_len) == OK);
	CHECK(r_len == 12);
	CHECK(variant == Variant(0.33333333333333333));
}

TEST_CASE("[Marshalls] Typed array encoding") {
	int r_len;
	Array array;
	array.set_typed(Variant::INT, StringName(), Ref<Script>());
	array.push_back(Variant(uint64_t(0x0f123456789abcdef)));
	uint8_t buffer[24];

	CHECK(encode_variant(array, buffer, r_len) == OK);
	CHECK_MESSAGE(r_len == 24, "Length == 4 bytes for header + 4 bytes for array type + 4 bytes for array size + 12 bytes for element.");
	CHECK_MESSAGE(buffer[0] == 0x1c, "Variant::ARRAY");
	CHECK(buffer[1] == 0x00);
	CHECK_MESSAGE(buffer[2] == 0x01, "CONTAINER_TYPE_KIND_BUILTIN");
	CHECK(buffer[3] == 0x00);
	// Check array type.
	CHECK_MESSAGE(buffer[4] == 0x02, "Variant::INT");
	CHECK(buffer[5] == 0x00);
	CHECK(buffer[6] == 0x00);
	CHECK(buffer[7] == 0x00);
	// Check array size.
	CHECK(buffer[8] == 0x01);
	CHECK(buffer[9] == 0x00);
	CHECK(buffer[10] == 0x00);
	CHECK(buffer[11] == 0x00);
	// Check element type.
	CHECK_MESSAGE(buffer[12] == 0x02, "Variant::INT");
	CHECK(buffer[13] == 0x00);
	CHECK_MESSAGE(buffer[14] == 0x01, "HEADER_DATA_FLAG_64");
	CHECK(buffer[15] == 0x00);
	// Check element value.
	CHECK(buffer[16] == 0xef);
	CHECK(buffer[17] == 0xcd);
	CHECK(buffer[18] == 0xab);
	CHECK(buffer[19] == 0x89);
	CHECK(buffer[20] == 0x67);
	CHECK(buffer[21] == 0x45);
	CHECK(buffer[22] == 0x23);
	CHECK(buffer[23] == 0xf1);
}

TEST_CASE("[Marshalls] Typed array decoding") {
	Variant variant;
	int r_len;
	uint8_t buffer[] = {
		0x1c, 0x00, 0x01, 0x00, // Variant::ARRAY, CONTAINER_TYPE_KIND_BUILTIN
		0x02, 0x00, 0x00, 0x00, // Array type (Variant::INT).
		0x01, 0x00, 0x00, 0x00, // Array size.
		0x02, 0x00, 0x01, 0x00, // Element type (Variant::INT, HEADER_DATA_FLAG_64).
		0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0xf1 // Element value.
	};

	CHECK(decode_variant(variant, buffer, 24, &r_len) == OK);
	CHECK(r_len == 24);
	CHECK(variant.get_type() == Variant::ARRAY);
	Array array = variant;
	CHECK(array.get_typed_builtin() == Variant::INT);
	CHECK(array.size() == 1);
	CHECK(array[0] == Variant(uint64_t(0x0f123456789abcdef)));
}

TEST_CASE("[Marshalls] Typed dicttionary encoding") {
	int r_len;
	Dictionary dictionary;
	dictionary.set_typed(Variant::INT, StringName(), Ref<Script>(), Variant::INT, StringName(), Ref<Script>());
	dictionary[Variant(uint64_t(0x0f123456789abcdef))] = Variant(uint64_t(0x0f123456789abcdef));
	uint8_t buffer[40];

	CHECK(encode_variant(dictionary, buffer, r_len) == OK);
	CHECK_MESSAGE(r_len == 40, "Length == 4 bytes for header + 8 bytes for dictionary type + 4 bytes for dictionary size + 24 bytes for key-value pair.");
	CHECK_MESSAGE(buffer[0] == 0x1b, "Variant::DICTIONARY");
	CHECK(buffer[1] == 0x00);
	CHECK_MESSAGE(buffer[2] == 0x05, "key: CONTAINER_TYPE_KIND_BUILTIN | value: CONTAINER_TYPE_KIND_BUILTIN");
	CHECK(buffer[3] == 0x00);
	// Check dictionary key type.
	CHECK_MESSAGE(buffer[4] == 0x02, "Variant::INT");
	CHECK(buffer[5] == 0x00);
	CHECK(buffer[6] == 0x00);
	CHECK(buffer[7] == 0x00);
	// Check dictionary value type.
	CHECK_MESSAGE(buffer[8] == 0x02, "Variant::INT");
	CHECK(buffer[9] == 0x00);
	CHECK(buffer[10] == 0x00);
	CHECK(buffer[11] == 0x00);
	// Check dictionary size.
	CHECK(buffer[12] == 0x01);
	CHECK(buffer[13] == 0x00);
	CHECK(buffer[14] == 0x00);
	CHECK(buffer[15] == 0x00);
	// Check key type.
	CHECK_MESSAGE(buffer[16] == 0x02, "Variant::INT");
	CHECK(buffer[17] == 0x00);
	CHECK_MESSAGE(buffer[18] == 0x01, "HEADER_DATA_FLAG_64");
	CHECK(buffer[19] == 0x00);
	// Check key value.
	CHECK(buffer[20] == 0xef);
	CHECK(buffer[21] == 0xcd);
	CHECK(buffer[22] == 0xab);
	CHECK(buffer[23] == 0x89);
	CHECK(buffer[24] == 0x67);
	CHECK(buffer[25] == 0x45);
	CHECK(buffer[26] == 0x23);
	CHECK(buffer[27] == 0xf1);
	// Check value type.
	CHECK_MESSAGE(buffer[28] == 0x02, "Variant::INT");
	CHECK(buffer[29] == 0x00);
	CHECK_MESSAGE(buffer[30] == 0x01, "HEADER_DATA_FLAG_64");
	CHECK(buffer[31] == 0x00);
	// Check value value.
	CHECK(buffer[32] == 0xef);
	CHECK(buffer[33] == 0xcd);
	CHECK(buffer[34] == 0xab);
	CHECK(buffer[35] == 0x89);
	CHECK(buffer[36] == 0x67);
	CHECK(buffer[37] == 0x45);
	CHECK(buffer[38] == 0x23);
	CHECK(buffer[39] == 0xf1);
}

TEST_CASE("[Marshalls] Typed dictionary decoding") {
	Variant variant;
	int r_len;
	uint8_t buffer[] = {
		0x1b, 0x00, 0x05, 0x00, // Variant::DICTIONARY, key: CONTAINER_TYPE_KIND_BUILTIN | value: CONTAINER_TYPE_KIND_BUILTIN
		0x02, 0x00, 0x00, 0x00, // Dictionary key type (Variant::INT).
		0x02, 0x00, 0x00, 0x00, // Dictionary value type (Variant::INT).
		0x01, 0x00, 0x00, 0x00, // Dictionary size.
		0x02, 0x00, 0x01, 0x00, // Key type (Variant::INT, HEADER_DATA_FLAG_64).
		0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0xf1, // Key value.
		0x02, 0x00, 0x01, 0x00, // Value type (Variant::INT, HEADER_DATA_FLAG_64).
		0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0xf1 // Value value.
	};

	CHECK(decode_variant(variant, buffer, 40, &r_len) == OK);
	CHECK(r_len == 40);
	CHECK(variant.get_type() == Variant::DICTIONARY);
	Dictionary dictionary = variant;
	CHECK(dictionary.get_typed_key_builtin() == Variant::INT);
	CHECK(dictionary.get_typed_value_builtin() == Variant::INT);
	CHECK(dictionary.size() == 1);
	CHECK(dictionary.has(Variant(uint64_t(0x0f123456789abcdef))));
	CHECK(dictionary[Variant(uint64_t(0x0f123456789abcdef))] == Variant(uint64_t(0x0f123456789abcdef)));
}

static void check_bulk_variant_roundtrip(const Variant &p_source) {
	int expected_length = 0;
	REQUIRE_EQ(encode_variant(p_source, nullptr, expected_length), OK);
	REQUIRE(expected_length >= 4);
	Vector<uint8_t> encoded;
	REQUIRE_EQ(encoded.resize(expected_length), OK);
	int written = 0;
	REQUIRE_EQ(encode_variant(p_source, encoded.ptrw(), written), OK);
	REQUIRE_EQ(written, expected_length);

	Variant decoded;
	int consumed = 0;
	REQUIRE_EQ(decode_variant(decoded, encoded.ptr(), written, &consumed), OK);
	CHECK_EQ(consumed, written);
	CHECK_EQ(decoded.get_type(), p_source.get_type());
	CHECK(decoded == p_source);
}

TEST_CASE("[Marshalls] Large NodePath and arrays use bounded bulk decoding") {
	String path = "/Root";
	for (int i = 0; i < 96; i++) {
		path += "/child_" + itos(i);
	}
	for (int i = 0; i < 48; i++) {
		path += ":subname_" + itos(i);
	}
	const NodePath long_path(path);
	check_bulk_variant_roundtrip(long_path);

	PackedStringArray strings;
	for (int i = 0; i < 384; i++) {
		strings.push_back("value_" + itos(i) + "_with_extra_text");
	}
	check_bulk_variant_roundtrip(strings);

	Array array;
	for (int i = 0; i < 512; i++) {
		array.push_back(i % 7 == 0 ? Variant("text_" + itos(i)) : Variant(i * 5));
	}
	check_bulk_variant_roundtrip(array);

	Array typed;
	typed.set_typed(Variant::INT, StringName(), Ref<Script>());
	for (int i = 0; i < 256; i++) {
		typed.push_back(i * 11);
	}
	check_bulk_variant_roundtrip(typed);
}

TEST_CASE("[Marshalls] Truncated enormous declared array counts are rejected before allocation") {
	Variant decoded;
	int consumed = 0;
	uint8_t invalid_array[8] = {};
	encode_uint32(Variant::ARRAY, invalid_array);
	encode_uint32(0x7FFFFFFF, invalid_array + 4);

	uint8_t invalid_strings[8] = {};
	encode_uint32(Variant::PACKED_STRING_ARRAY, invalid_strings);
	encode_uint32(0x7FFFFFFF, invalid_strings + 4);

	uint8_t invalid_nodepath[16] = {};
	encode_uint32(Variant::NODE_PATH, invalid_nodepath);
	encode_uint32(0xFFFFFFFF, invalid_nodepath + 4); // New format and too many names.
	encode_uint32(0, invalid_nodepath + 8);
	encode_uint32(0, invalid_nodepath + 12);

	uint8_t overflow_nodepath[16] = {};
	encode_uint32(Variant::NODE_PATH, overflow_nodepath);
	encode_uint32(0x80000000, overflow_nodepath + 4);
	encode_uint32(0xFFFFFFFF, overflow_nodepath + 8); // Overflows with obsolete property field.
	encode_uint32(2, overflow_nodepath + 12);

	ERR_PRINT_OFF;
	CHECK_EQ(decode_variant(decoded, invalid_array, sizeof(invalid_array), &consumed), ERR_INVALID_DATA);
	CHECK_EQ(decode_variant(decoded, invalid_strings, sizeof(invalid_strings), &consumed), ERR_INVALID_DATA);
	CHECK_EQ(decode_variant(decoded, invalid_nodepath, sizeof(invalid_nodepath), &consumed), ERR_INVALID_DATA);
	CHECK_EQ(decode_variant(decoded, overflow_nodepath, sizeof(overflow_nodepath), &consumed), ERR_INVALID_DATA);
	ERR_PRINT_ON;
}

} // namespace TestMarshalls
