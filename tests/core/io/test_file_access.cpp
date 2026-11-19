/**************************************************************************/
/*  test_file_access.cpp                                                  */
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

TEST_FORCE_LINK(test_file_access)

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/file_access_compressed.h"
#include "core/io/file_access_memory.h"
#include "core/io/file_access_packed_byte_array.h"
#include "tests/test_utils.h"

#include <cstring>

namespace TestFileAccess {

TEST_CASE("[FileAccess] CSV read") {
	Ref<FileAccess> f = FileAccess::open(TestUtils::get_data_path("testdata.csv"), FileAccess::READ);
	REQUIRE(f.is_valid());

	Vector<String> header = f->get_csv_line(); // Default delimiter: ",".
	REQUIRE(header.size() == 4);

	Vector<String> row1 = f->get_csv_line(","); // Explicit delimiter, should be the same.
	REQUIRE(row1.size() == 4);
	CHECK(row1[0] == "GOOD_MORNING");
	CHECK(row1[1] == "Good Morning");
	CHECK(row1[2] == "Guten Morgen");
	CHECK(row1[3] == "Bonjour");

	Vector<String> row2 = f->get_csv_line();
	REQUIRE(row2.size() == 4);
	CHECK(row2[0] == "GOOD_EVENING");
	CHECK(row2[1] == "Good Evening");
	CHECK(row2[2].is_empty()); // Use case: not yet translated!
	// https://github.com/godotengine/godot/issues/44269
	CHECK_MESSAGE(row2[2] != "\"", "Should not parse empty string as a single double quote.");
	CHECK(row2[3] == "\"\""); // Intentionally testing only escaped double quotes.

	Vector<String> row3 = f->get_csv_line();
	REQUIRE(row3.size() == 6);
	CHECK(row3[0] == "Without quotes");
	CHECK(row3[1] == "With, comma");
	CHECK(row3[2] == "With \"inner\" quotes");
	CHECK(row3[3] == "With \"inner\", quotes\",\" and comma");
	CHECK(row3[4] == "With \"inner\nsplit\" quotes and\nline breaks");
	CHECK(row3[5] == "With \\nnewline chars"); // Escaped, not an actual newline.

	Vector<String> row4 = f->get_csv_line("~"); // Custom delimiter, makes inline commas easier.
	REQUIRE(row4.size() == 3);
	CHECK(row4[0] == "Some other");
	CHECK(row4[1] == "delimiter");
	CHECK(row4[2] == "should still work, shouldn't it?");

	Vector<String> row5 = f->get_csv_line("\t"); // Tab separated variables.
	REQUIRE(row5.size() == 3);
	CHECK(row5[0] == "What about");
	CHECK(row5[1] == "tab separated");
	CHECK(row5[2] == "lines, good?");
}

TEST_CASE("[FileAccess][Performance] CSV multiline records scale linearly") {
	// Previously, every continuation line rescanned and recopied the entire
	// accumulated record, causing quadratic work for this common import case.
	const String payload = String("long text with comma, and unicode Ω🌍\n").repeat(2048);
	const String csv = "\"begin\n" + payload + "end\",right,\"say \"\"hello\"\"\"";
	const CharString bytes = csv.utf8();

	Ref<FileAccessMemory> file;
	file.instantiate();
	REQUIRE(file->open_custom(reinterpret_cast<const uint8_t *>(bytes.ptr()), bytes.length()) == OK);

	const Vector<String> fields = file->get_csv_line();
	REQUIRE(fields.size() == 3);
	CHECK(fields[0] == "begin\n" + payload + "end");
	CHECK(fields[1] == "right");
	CHECK(fields[2] == "say \"hello\"");
	CHECK(file->get_position() == uint64_t(bytes.length()));
}

TEST_CASE("[FileAccess][Performance] CSV fields handle delimiters and escaped quotes") {
	const char *const input = ",first,\"comma, inside\",\"double \"\"quote\"\"\",,tail,";
	Ref<FileAccessMemory> file;
	file.instantiate();
	REQUIRE(file->open_custom(reinterpret_cast<const uint8_t *>(input), strlen(input)) == OK);
	const Vector<String> fields = file->get_csv_line();
	REQUIRE(fields.size() == 7);
	CHECK(fields[0] == "");
	CHECK(fields[1] == "first");
	CHECK(fields[2] == "comma, inside");
	CHECK(fields[3] == "double \"quote\"");
	CHECK(fields[4] == "");
	CHECK(fields[5] == "tail");
	CHECK(fields[6] == "");

	const char *const simple = "1~two~3";
	REQUIRE(file->open_custom(reinterpret_cast<const uint8_t *>(simple), strlen(simple)) == OK);
	const Vector<String> alternate = file->get_csv_line("~");
	REQUIRE(alternate.size() == 3);
	CHECK(alternate[0] == "1");
	CHECK(alternate[1] == "two");
	CHECK(alternate[2] == "3");
}

TEST_CASE("[FileAccess][Performance] CSV randomized quoted fields round trip") {
	uint32_t seed = 0xC54183D2;
	static constexpr char32_t alphabet[] = U"Ab1,\"x\nΩ😀";
	Ref<FileAccessMemory> file;
	file.instantiate();
	for (int trial = 0; trial < 128; trial++) {
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		const int count = 1 + int(seed % 9);

		Vector<String> expected;
		String csv;
		for (int field = 0; field < count; field++) {
			seed ^= seed << 13;
			seed ^= seed >> 17;
			seed ^= seed << 5;
			const int size = int(seed % 96);
			String value;
			value.resize_uninitialized(size + 1);
			char32_t *write = value.ptrw();
			for (int i = 0; i < size; i++) {
				seed ^= seed << 13;
				seed ^= seed >> 17;
				seed ^= seed << 5;
				write[i] = alphabet[seed % (sizeof(alphabet) / sizeof(char32_t) - 1)];
			}
			write[size] = 0;
			expected.push_back(value);
			if (field != 0) {
				csv += ",";
			}
			csv += "\"" + value.replace("\"", "\"\"") + "\"";
		}
		const CharString bytes = csv.utf8();
		REQUIRE(file->open_custom(reinterpret_cast<const uint8_t *>(bytes.ptr()), bytes.length()) == OK);
		const Vector<String> fields = file->get_csv_line();
		REQUIRE(fields.size() == count);
		for (int i = 0; i < count; i++) {
			CHECK(fields[i] == expected[i]);
		}
	}
}

TEST_CASE("[FileAccess][Performance] CSV writer matches the legacy byte representation") {
	Ref<FileAccessMemory> file;
	file.instantiate();
	uint32_t seed = 0x5D21C9A7;
	static constexpr char32_t alphabet[] = U"abcXYZ 123,\"é😀\n";

	for (int trial = 0; trial < 192; trial++) {
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		const int count = int(seed % 16);
		const String delimiter = (trial & 1) ? "," : "~";
		Vector<String> values;
		String legacy;
		for (int i = 0; i < count; i++) {
			seed ^= seed << 13;
			seed ^= seed >> 17;
			seed ^= seed << 5;
			const int len = int(seed % 120);
			String value;
			value.resize_uninitialized(len + 1);
			char32_t *write = value.ptrw();
			for (int j = 0; j < len; j++) {
				seed ^= seed << 13;
				seed ^= seed >> 17;
				seed ^= seed << 5;
				write[j] = alphabet[seed % (sizeof(alphabet) / sizeof(alphabet[0]) - 1)];
			}
			write[len] = 0;
			values.push_back(value);

			// Independent oracle: exactly the original ordered operations.
			String old_field = value;
			if (old_field.contains_char('"') || old_field.contains(delimiter) || old_field.contains_char('\n')) {
				old_field = "\"" + old_field.replace("\"", "\"\"") + "\"";
			}
			if (i < count - 1) {
				old_field += delimiter;
			}
			legacy += old_field;
		}

		const CharString expected = (legacy + "\n").utf8();
		Vector<uint8_t> storage;
		REQUIRE(storage.resize_uninitialized(expected.length()) == OK);
		REQUIRE(file->open_custom(storage.ptrw(), storage.size()) == OK);
		REQUIRE(file->store_csv_line(values, delimiter));
		CHECK(file->get_position() == uint64_t(expected.length()));
		CHECK(memcmp(storage.ptr(), expected.ptr(), expected.length()) == 0);
	}
}

TEST_CASE("[FileAccess][Performance] CSV large quoted writer round trips with one buffer") {
	Vector<String> values;
	for (int i = 0; i < 64; i++) {
		values.push_back(String(U"🇵🇱é,\"abc\n").repeat(64) + String::num_int64(i));
	}
	// A generous backing storage for this file avoids any filesystem dependency.
	Vector<uint8_t> storage;
	REQUIRE(storage.resize_initialized(262144) == OK);
	Ref<FileAccessMemory> file;
	file.instantiate();
	REQUIRE(file->open_custom(storage.ptrw(), storage.size()) == OK);
	REQUIRE(file->store_csv_line(values));

	const uint64_t written = file->get_position();
	CHECK(written > 50000);
	file->seek(0);
	const Vector<String> parsed = file->get_csv_line();
	REQUIRE(parsed.size() == values.size());
	for (int i = 0; i < values.size(); i++) {
		CHECK(parsed[i] == values[i]);
	}
}

TEST_CASE("[FileAccess] Get as UTF-8 String") {
	SUBCASE("Newline == \\n (Unix)") {
		Ref<FileAccess> f_lf = FileAccess::open(TestUtils::get_data_path("line_endings_lf.test.txt"), FileAccess::READ);
		REQUIRE(f_lf.is_valid());
		String s_lf = f_lf->get_as_utf8_string();
		CHECK(s_lf == "Hello darkness\nMy old friend\nI've come to talk\nWith you again\n");
		f_lf->seek(0);
		CHECK(f_lf->get_line() == "Hello darkness");
		CHECK(f_lf->get_line() == "My old friend");
		CHECK(f_lf->get_line() == "I've come to talk");
		CHECK(f_lf->get_line() == "With you again");
		CHECK(f_lf->get_error() == Error::OK);
	}

	SUBCASE("Newline == \\r\\n (Windows)") {
		Ref<FileAccess> f_crlf = FileAccess::open(TestUtils::get_data_path("line_endings_crlf.test.txt"), FileAccess::READ);
		REQUIRE(f_crlf.is_valid());
		String s_crlf = f_crlf->get_as_utf8_string();
		CHECK(s_crlf == "Hello darkness\r\nMy old friend\r\nI've come to talk\r\nWith you again\r\n");
		f_crlf->seek(0);
		CHECK(f_crlf->get_line() == "Hello darkness");
		CHECK(f_crlf->get_line() == "My old friend");
		CHECK(f_crlf->get_line() == "I've come to talk");
		CHECK(f_crlf->get_line() == "With you again");
		CHECK(f_crlf->get_error() == Error::OK);
	}

	SUBCASE("Newline == \\r (Legacy macOS)") {
		Ref<FileAccess> f_cr = FileAccess::open(TestUtils::get_data_path("line_endings_cr.test.txt"), FileAccess::READ);
		REQUIRE(f_cr.is_valid());
		String s_cr = f_cr->get_as_utf8_string();
		CHECK(s_cr == "Hello darkness\rMy old friend\rI've come to talk\rWith you again\r");
		f_cr->seek(0);
		CHECK(f_cr->get_line() == "Hello darkness");
		CHECK(f_cr->get_line() == "My old friend");
		CHECK(f_cr->get_line() == "I've come to talk");
		CHECK(f_cr->get_line() == "With you again");
		CHECK(f_cr->get_error() == Error::OK);
	}

	SUBCASE("Newline == Mixed") {
		Ref<FileAccess> f_mix = FileAccess::open(TestUtils::get_data_path("line_endings_mixed.test.txt"), FileAccess::READ);
		REQUIRE(f_mix.is_valid());
		String s_mix = f_mix->get_as_utf8_string();
		CHECK(s_mix == "Hello darkness\nMy old friend\r\nI've come to talk\rWith you again");
		f_mix->seek(0);
		CHECK(f_mix->get_line() == "Hello darkness");
		CHECK(f_mix->get_line() == "My old friend");
		CHECK(f_mix->get_line() == "I've come to talk");
		CHECK(f_mix->get_line() == "With you again");
		CHECK(f_mix->get_error() == Error::ERR_FILE_EOF); // Not a bug; the file lacks a final newline.
	}
}

TEST_CASE("[FileAccess] Get/Store floating point values") {
	// BigEndian Hex: 0x40490E56
	// LittleEndian Hex: 0x560E4940
	float value = 3.1415f;

	SUBCASE("Little Endian") {
		const String file_path = TestUtils::get_data_path("floating_point_little_endian.bin");
		const String file_path_new = TestUtils::get_data_path("floating_point_little_endian_new.bin");

		Ref<FileAccess> f = FileAccess::open(file_path, FileAccess::READ);
		REQUIRE(f.is_valid());
		CHECK_EQ(f->get_float(), value);

		Ref<FileAccess> fw = FileAccess::open(file_path_new, FileAccess::WRITE);
		REQUIRE(fw.is_valid());
		fw->store_float(value);
		fw->close();

		CHECK_EQ(FileAccess::get_sha256(file_path_new), FileAccess::get_sha256(file_path));

		DirAccess::remove_file_or_error(file_path_new);
	}

	SUBCASE("Big Endian") {
		const String file_path = TestUtils::get_data_path("floating_point_big_endian.bin");
		const String file_path_new = TestUtils::get_data_path("floating_point_big_endian_new.bin");

		Ref<FileAccess> f = FileAccess::open(file_path, FileAccess::READ);
		REQUIRE(f.is_valid());
		f->set_big_endian(true);
		CHECK_EQ(f->get_float(), value);

		Ref<FileAccess> fw = FileAccess::open(file_path_new, FileAccess::WRITE);
		REQUIRE(fw.is_valid());
		fw->set_big_endian(true);
		fw->store_float(value);
		fw->close();

		CHECK_EQ(FileAccess::get_sha256(file_path_new), FileAccess::get_sha256(file_path));

		DirAccess::remove_file_or_error(file_path_new);
	}
}

TEST_CASE("[FileAccess] Get/Store floating point half precision values") {
	// IEEE 754 half-precision binary floating-point format:
	// sign exponent (5 bits)    fraction (10 bits)
	//  0        01101               0101010101
	// BigEndian Hex: 0x3555
	// LittleEndian Hex: 0x5535
	float value = 0.33325195f;

	SUBCASE("Little Endian") {
		const String file_path = TestUtils::get_data_path("half_precision_floating_point_little_endian.bin");
		const String file_path_new = TestUtils::get_data_path("half_precision_floating_point_little_endian_new.bin");

		Ref<FileAccess> f = FileAccess::open(file_path, FileAccess::READ);
		REQUIRE(f.is_valid());
		CHECK_EQ(f->get_half(), value);

		Ref<FileAccess> fw = FileAccess::open(file_path_new, FileAccess::WRITE);
		REQUIRE(fw.is_valid());
		fw->store_half(value);
		fw->close();

		CHECK_EQ(FileAccess::get_sha256(file_path_new), FileAccess::get_sha256(file_path));

		DirAccess::remove_file_or_error(file_path_new);
	}

	SUBCASE("Big Endian") {
		const String file_path = TestUtils::get_data_path("half_precision_floating_point_big_endian.bin");
		const String file_path_new = TestUtils::get_data_path("half_precision_floating_point_big_endian_new.bin");

		Ref<FileAccess> f = FileAccess::open(file_path, FileAccess::READ);
		REQUIRE(f.is_valid());
		f->set_big_endian(true);
		CHECK_EQ(f->get_half(), value);

		Ref<FileAccess> fw = FileAccess::open(file_path_new, FileAccess::WRITE);
		REQUIRE(fw.is_valid());
		fw->set_big_endian(true);
		fw->store_half(value);
		fw->close();

		CHECK_EQ(FileAccess::get_sha256(file_path_new), FileAccess::get_sha256(file_path));

		DirAccess::remove_file_or_error(file_path_new);
	}

	SUBCASE("4096 bytes fastlz compressed") {
		const String file_path = TestUtils::get_data_path("exactly_4096_bytes_fastlz.bin");

		Ref<FileAccess> f = FileAccess::open_compressed(file_path, FileAccess::READ, FileAccess::COMPRESSION_FASTLZ);
		const Vector<uint8_t> full_data = f->get_buffer(4096 * 2);
		CHECK(full_data.size() == 4096);
		CHECK(f->eof_reached());

		// Data should be empty.
		PackedByteArray reference;
		reference.resize_initialized(4096);
		CHECK(reference == full_data);

		f->seek(0);
		const Vector<uint8_t> partial_data = f->get_buffer(4095);
		CHECK(partial_data.size() == 4095);
		CHECK(!f->eof_reached());

		reference.resize_initialized(4095);
		CHECK(reference == partial_data);
	}
}

TEST_CASE("[FileAccess] Cursor positioning") {
	Ref<FileAccess> f = FileAccess::open(TestUtils::get_data_path("line_endings_lf.test.txt"), FileAccess::READ);
	REQUIRE(f.is_valid());

	String full = f->get_as_utf8_string();
	int64_t len = full.length();

	SUBCASE("Initial position is zero") {
		f->seek(0);
		CHECK(f->get_position() == 0);
	}

	SUBCASE("seek() moves cursor to absolute position") {
		f->seek(5);
		CHECK(f->get_position() == 5);
	}

	SUBCASE("seek() moves cursor beyond file size") {
		f->seek(len + 10);
		CHECK(f->get_position() == len + 10);
	}

	SUBCASE("seek_end() moves cursor to end of file") {
		f->seek_end(0);
		CHECK(f->get_position() == len);
	}

	SUBCASE("seek_end() with positive offset") {
		f->seek_end(1);
		CHECK(f->get_position() == len + 1);
	}

	SUBCASE("seek_end() with negative offset") {
		f->seek_end(-1);
		CHECK(f->get_position() == len - 1);

		char last_char = full[full.length() - 1];
		CHECK(f->get_8() == last_char);
	}

	SUBCASE("seek_end() beyond file size") {
		f->seek(5);
		f->seek_end(-len - 10); // seeking to a position below 0; ignored.
		CHECK(f->get_position() == 5);
	}
}


TEST_CASE("[FileAccess] PackedByteArray zero-length read at start and end") {
	Ref<FileAccessPackedByteArray> f;
	f.instantiate();
	PackedByteArray bytes;
	bytes.resize_initialized(4096);
	bytes.set(0, 42);
	bytes.set(4095, 99);
	REQUIRE(f->open_custom(bytes) == OK);

	uint8_t sentinel = 0x5a;
	CHECK(f->get_buffer(&sentinel, 0) == 0);
	CHECK(f->get_position() == 0);
	CHECK(sentinel == 0x5a);
	CHECK_FALSE(f->eof_reached());

	uint8_t page[4096] = {};
	CHECK(f->get_buffer(page, 4096) == 4096);
	CHECK(page[0] == 42);
	CHECK(page[4095] == 99);
	CHECK(f->get_position() == 4096);
	CHECK(f->eof_reached());
	CHECK(f->get_error() == ERR_FILE_EOF);
	CHECK(f->get_buffer(&sentinel, 0) == 0);
	CHECK(sentinel == 0x5a);
	CHECK(f->get_position() == 4096);
}

TEST_CASE("[FileAccess] PackedByteArray page-aligned and empty buffer reads") {
	Ref<FileAccessPackedByteArray> f;
	f.instantiate();
	PackedByteArray empty;
	REQUIRE(f->open_custom(empty) == OK);
	uint8_t sentinel = 0x7b;
	CHECK(f->get_buffer(&sentinel, 0) == 0);
	CHECK(sentinel == 0x7b);
	CHECK(f->get_position() == 0);
	CHECK(f->eof_reached());

	PackedByteArray pages;
	pages.resize_initialized(8192);
	pages.set(0, 3);
	pages.set(4096, 7);
	pages.set(8191, 11);
	REQUIRE(f->open_custom(pages) == OK);
	uint8_t block[4096] = {};
	for (int i = 0; i < 2; i++) {
		CHECK(f->get_buffer(block, 4096) == 4096);
		CHECK(f->get_position() == uint64_t((i + 1) * 4096));
		CHECK(f->get_buffer(&sentinel, 0) == 0);
		CHECK(sentinel == 0x7b);
	}
	CHECK(f->get_position() == 8192);
	CHECK(f->eof_reached());
	f->seek(0);
	CHECK(f->get_buffer(block, 4096) == 4096);
	CHECK(block[0] == 3);
	CHECK(f->get_buffer(block, 4096) == 4096);
	CHECK(block[0] == 7);
	CHECK(block[4095] == 11);
}


// Regression coverage for the packed byte-array I/O hot path.
TEST_CASE("[FileAccess] PackedByteArray shrink clamps cursor and prevents overflow") {
	Ref<FileAccessPackedByteArray> f;
	f.instantiate();
	PackedByteArray bytes;
	bytes.resize_initialized(16);
	bytes.set(0, 7);
	bytes.set(7, 23);
	REQUIRE(f->open_custom(bytes) == OK);
	f->seek(16);
	REQUIRE(f->resize(8) == OK);
	CHECK(f->get_length() == 8);
	CHECK(f->get_position() == 8);
	CHECK(f->eof_reached());

	uint8_t sentinel = 0x5a;
	ERR_PRINT_OFF;
	CHECK(f->get_buffer(&sentinel, 1) == 0);
	ERR_PRINT_ON;
	CHECK(sentinel == 0x5a);
	CHECK(f->get_position() == 8);

	f->seek(0);
	uint8_t copied[8] = {};
	CHECK(f->get_buffer(copied, 8) == 8);
	CHECK(copied[0] == 7);
	CHECK(copied[7] == 23);
	CHECK(f->get_position() == 8);
}

TEST_CASE("[FileAccess] PackedByteArray COW stays shared after a failed EOF write") {
	Ref<FileAccessPackedByteArray> f;
	f.instantiate();
	PackedByteArray original;
	original.resize_initialized(4);
	original.set(0, 3);
	original.set(3, 8);
	REQUIRE(f->open_custom(original) == OK);
	f->seek(4);
	const uint8_t value = 19;
	ERR_PRINT_OFF;
	CHECK_FALSE(f->store_buffer(&value, 1));
	ERR_PRINT_ON;
	CHECK(f->get_position() == 4);
	CHECK(original[0] == 3);
	CHECK(original[3] == 8);

	// A successful write must detach from the original shared input.
	f->seek(0);
	CHECK(f->store_buffer(&value, 1));
	CHECK(original[0] == 3);
	uint8_t result = 0;
	f->seek(0);
	CHECK(f->get_buffer(&result, 1) == 1);
	CHECK(result == 19);
}

TEST_CASE("[FileAccess] PackedByteArray partial block I/O preserves bounds") {
	Ref<FileAccessPackedByteArray> f;
	f.instantiate();
	PackedByteArray bytes;
	bytes.resize_initialized(8);
	REQUIRE(f->open_custom(bytes) == OK);
	f->seek(6);
	const uint8_t payload[4] = { 10, 20, 30, 40 };
	ERR_PRINT_OFF;
	CHECK_FALSE(f->store_buffer(payload, 4));
	ERR_PRINT_ON;
	CHECK(f->get_position() == 8);

	f->seek(5);
	uint8_t output[5] = { 0xa5, 0xa5, 0xa5, 0xa5, 0xa5 };
	ERR_PRINT_OFF;
	CHECK(f->get_buffer(output, 5) == 3);
	ERR_PRINT_ON;
	CHECK(output[0] == 0);
	CHECK(output[1] == 10);
	CHECK(output[2] == 20);
	CHECK(output[3] == 0xa5);
	CHECK(output[4] == 0xa5);
	CHECK(f->get_position() == 8);
}

TEST_CASE("[FileAccess] PackedByteArray resize failure preserves position") {
	Ref<FileAccessPackedByteArray> f;
	f.instantiate();
	PackedByteArray bytes;
	bytes.resize_initialized(4);
	REQUIRE(f->open_custom(bytes) == OK);
	f->seek(3);
	ERR_PRINT_OFF;
	CHECK(f->resize(-1) != OK);
	ERR_PRINT_ON;
	CHECK(f->get_position() == 3);
	CHECK(f->get_length() == 4);
}

TEST_CASE("[FileAccess] PackedByteArray reads and writes never cross EOF") {
	Ref<FileAccessPackedByteArray> f;
	f.instantiate();
	PackedByteArray bytes;
	bytes.resize_initialized(257);
	REQUIRE(f->open_custom(bytes) == OK);

	for (int size = 0; size <= 257; size++) {
		REQUIRE(f->resize(size) == OK);
		CHECK(f->get_length() == uint64_t(size));
		f->seek(size);
		uint8_t marker = 0xde;
		// These operations intentionally fail at EOF. Do not emit hundreds
		// of expected warnings during the sweep.
		ERR_PRINT_OFF;
		CHECK(f->get_buffer(&marker, 1) == 0);
		CHECK_FALSE(f->store_buffer(&marker, 1));
		ERR_PRINT_ON;
		CHECK(marker == 0xde);
		CHECK(f->get_position() == uint64_t(size));

		if (size > 0) {
			f->seek(size - 1);
			CHECK(f->store_buffer(&marker, 1));
			CHECK(f->get_position() == uint64_t(size));
			f->seek(size - 1);
			uint8_t value = 0;
			CHECK(f->get_buffer(&value, 1) == 1);
			CHECK(value == 0xde);
		}
	}
}


TEST_CASE("[FileAccess] Memory read-only open shares backing storage and isolates writes") {
	const String file_path = "cgame_file_access_memory_cow_regression.bin";
	Vector<uint8_t> source;
	REQUIRE(source.resize(4) == OK);
	source.ptrw()[0] = 10;
	source.ptrw()[1] = 20;
	source.ptrw()[2] = 30;
	source.ptrw()[3] = 40;
	FileAccessMemory::register_file(file_path, source);

	Ref<FileAccessMemory> reader;
	reader.instantiate();
	REQUIRE(reader->open_internal(file_path, FileAccess::READ) == OK);
	CHECK(reader->is_open());
	uint8_t read_data[4] = {};
	CHECK(reader->get_buffer(read_data, 4) == 4);
	CHECK(read_data[0] == 10);
	CHECK(read_data[3] == 40);
	reader->seek(0);
	uint8_t replacement = 99;
	ERR_PRINT_OFF;
	CHECK_FALSE(reader->store_buffer(&replacement, 1));
	ERR_PRINT_ON;
	CHECK(reader->get_position() == 0);

	// Writing must detach the registered Vector, not mutate the original
	// source buffer or invalidate an already-open read-only snapshot.
	Ref<FileAccessMemory> writer;
	writer.instantiate();
	REQUIRE(writer->open_internal(file_path, FileAccess::READ_WRITE) == OK);
	writer->seek(1);
	CHECK(writer->store_buffer(&replacement, 1));
	CHECK(source[1] == 20);
	CHECK(reader->get_buffer(read_data, 4) == 4);
	CHECK(read_data[1] == 20);

	Ref<FileAccessMemory> after_write;
	after_write.instantiate();
	REQUIRE(after_write->open_internal(file_path, FileAccess::READ) == OK);
	CHECK(after_write->get_buffer(read_data, 4) == 4);
	CHECK(read_data[0] == 10);
	CHECK(read_data[1] == 99);
	CHECK(read_data[2] == 30);
	CHECK(read_data[3] == 40);

	reader->close();
	writer->close();
	after_write->close();
	CHECK_FALSE(reader->is_open());
	CHECK_FALSE(writer->is_open());
	CHECK_FALSE(after_write->is_open());
	CHECK(reader->get_error() == ERR_FILE_EOF);
}

TEST_CASE("[FileAccess] Memory reader survives registration replacement") {
	const String path = "cgame_memory_file_replacement_regression.bin";
	Vector<uint8_t> first;
	REQUIRE(first.resize(3) == OK);
	first.ptrw()[0] = 1;
	first.ptrw()[1] = 2;
	first.ptrw()[2] = 3;
	FileAccessMemory::register_file(path, first);

	Ref<FileAccessMemory> before;
	before.instantiate();
	REQUIRE(before->open_internal(path, FileAccess::READ) == OK);

	Vector<uint8_t> second;
	REQUIRE(second.resize(3) == OK);
	second.ptrw()[0] = 4;
	second.ptrw()[1] = 5;
	second.ptrw()[2] = 6;
	FileAccessMemory::register_file(path, second);

	// Destroying the old caller's buffer must not free the open reader's bytes.
	first.clear();
	uint8_t data[3] = {};
	CHECK(before->get_buffer(data, 3) == 3);
	CHECK(data[0] == 1);
	CHECK(data[1] == 2);
	CHECK(data[2] == 3);

	Ref<FileAccessMemory> now;
	now.instantiate();
	REQUIRE(now->open_internal(path, FileAccess::READ) == OK);
	CHECK(now->get_buffer(data, 3) == 3);
	CHECK(data[0] == 4);
	CHECK(data[1] == 5);
	CHECK(data[2] == 6);
}

TEST_CASE("[FileAccess] Memory empty files and custom buffers retain correct open semantics") {
	const String path = "cgame_file_access_memory_empty_regression.bin";
	Vector<uint8_t> empty;
	FileAccessMemory::register_file(path, empty);
	Ref<FileAccessMemory> file;
	file.instantiate();
	REQUIRE(file->open_internal(path, FileAccess::READ) == OK);
	CHECK(file->is_open());
	CHECK(file->get_length() == 0);
	CHECK(file->eof_reached());
	uint8_t sentinel = 42;
	CHECK(file->get_buffer(&sentinel, 0) == 0);
	ERR_PRINT_OFF;
	CHECK(file->get_buffer(&sentinel, 1) == 0);
	ERR_PRINT_ON;
	CHECK(sentinel == 42);
	file->close();
	CHECK_FALSE(file->is_open());

	uint8_t external[3] = { 5, 6, 7 };
	REQUIRE(file->open_custom(external, 3) == OK);
	CHECK(file->is_open());
	const uint8_t update = 9;
	CHECK(file->store_buffer(&update, 1));
	CHECK(external[0] == 9);
	file->close();
	CHECK_FALSE(file->is_open());
}

TEST_CASE("[FileAccess][Performance] Compressed block tables preserve large roundtrip and seek") {
	// Use a small block size to exercise many table entries without keeping a
	// large decompressed asset resident in memory.
	const String path = TestUtils::get_temp_path("compressed_block_table_perf.bin");
	const int block_size = 64;
	const int byte_count = block_size * 97 + 23;
	Vector<uint8_t> payload;
	REQUIRE(payload.resize(byte_count) == OK);
	uint8_t *payload_bytes = payload.ptrw();
	for (int i = 0; i < byte_count; i++) {
		payload_bytes[i] = uint8_t((i * 37 + (i / block_size) * 19) & 0xff);
	}

	for (Compression::Mode mode : { Compression::MODE_FASTLZ, Compression::MODE_ZSTD }) {
		Ref<FileAccessCompressed> writer;
		writer.instantiate();
		writer->configure("GCPF", mode, block_size);
		REQUIRE(writer->open_internal(path, FileAccess::WRITE) == OK);
		CHECK(writer->store_buffer(payload.ptr(), payload.size()));
		writer->close();

		Ref<FileAccessCompressed> reader;
		reader.instantiate();
		reader->configure("GCPF", mode, block_size);
		REQUIRE(reader->open_internal(path, FileAccess::READ) == OK);
		CHECK(reader->get_length() == byte_count);

		Vector<uint8_t> restored;
		REQUIRE(restored.resize(byte_count) == OK);
		CHECK(reader->get_buffer(restored.ptrw(), byte_count) == uint64_t(byte_count));
		CHECK(restored == payload);

		// Cross a compression block boundary with an unaligned seek.
		reader->seek(block_size * 36 - 7);
		uint8_t subsection[29] = {};
		CHECK(reader->get_buffer(subsection, sizeof(subsection)) == sizeof(subsection));
		for (int i = 0; i < int(sizeof(subsection)); i++) {
			CHECK(subsection[i] == payload[block_size * 36 - 7 + i]);
		}
		reader->close();
	}
	DirAccess::remove_file_or_error(path);
}

TEST_CASE("[FileAccess][Performance] Variant serialization uses small scratch and large fallback") {
	Vector<uint8_t> storage;
	REQUIRE(storage.resize_uninitialized(24000) == OK);
	Ref<FileAccessMemory> file;
	file.instantiate();
	REQUIRE(file->open_custom(storage.ptrw(), storage.size()) == OK);

	Array nested;
	nested.push_back(123);
	nested.push_back(String("hello"));
	Dictionary dictionary;
	dictionary["nested"] = nested;
	dictionary["unicode"] = String::utf8("Привет мир 🌍");

	const Variant values[] = {
		Variant(),
		Variant(true),
		Variant(42),
		Variant(uint64_t(0x7fedcba987654321)),
		Variant(Vector3(1.5, 2.25, -3.5)),
		Variant(String()),
		Variant(String("short")),
		Variant(String::utf8("Привет мир 🌍")),
		Variant(String("x").repeat(496)),
		Variant(String("x").repeat(500)),
		Variant(String("x").repeat(501)),
		Variant(String("x").repeat(512)),
		Variant(String("x").repeat(513)),
		Variant(String("x").repeat(8192)),
		Variant(nested),
		Variant(dictionary),
	};

	for (const Variant &value : values) {
		file->seek(0);
		REQUIRE(file->store_var(value));
		const uint64_t total_bytes = file->get_position();
		CHECK(total_bytes >= 8);
		CHECK(total_bytes < uint64_t(storage.size()));

		// Verify that the same wire header is produced, then decode it.
		file->seek(0);
		CHECK(file->get_32() == uint32_t(total_bytes - 4));
		file->seek(0);
		CHECK(file->get_var() == value);
		CHECK(file->get_position() == total_bytes);
	}

	// Decoding a short buffer must not consume uninitialized scratch memory.
	uint8_t truncated[8] = { 8, 0, 0, 0, 2, 0, 0, 0 };
	REQUIRE(file->open_custom(truncated, sizeof(truncated)) == OK);
	ERR_PRINT_OFF;
	CHECK(file->get_var() == Variant());
	ERR_PRINT_ON;

	// Reject impossible 32-bit lengths before allocating an enormous vector.
	uint8_t invalid_length[4] = { 0xff, 0xff, 0xff, 0xff };
	REQUIRE(file->open_custom(invalid_length, sizeof(invalid_length)) == OK);
	ERR_PRINT_OFF;
	CHECK(file->get_var() == Variant());
	ERR_PRINT_ON;
}


TEST_CASE("[FileAccess][Performance] Small UTF-8 loads avoid a transient heap buffer") {
	Ref<FileAccessMemory> file;
	file.instantiate();
	const int sizes[] = { 0, 1, 31, 255, 511, 512, 513, 1024, 8192 };
	for (int size : sizes) {
		Vector<uint8_t> source;
		REQUIRE(source.resize_uninitialized(size) == OK);
		uint8_t *bytes = source.ptrw();
		for (int i = 0; i < size; i++) {
			bytes[i] = uint8_t('a' + (i % 26));
		}
		REQUIRE(file->open_custom(source.ptr(), source.size()) == OK);

		// String::utf8() intentionally rejects a null pointer, even when
		// the length is zero; use an empty String for that valid file case.
		const String expected = size == 0 ? String() : String::utf8(reinterpret_cast<const char *>(source.ptr()), size);
		CHECK(expected.length() == size);
		CHECK(file->get_as_utf8_string() == expected);
		CHECK(file->get_position() == uint64_t(size));

		// Check repeated reads after an explicit rewind.
		file->seek(0);
		CHECK(file->get_as_utf8_string() == expected);
		file->close();
	}

	const String unicode = String::utf8("Привет, 世界 🌍").repeat(128);
	const CharString encoded = unicode.utf8();
	REQUIRE(file->open_custom(reinterpret_cast<const uint8_t *>(encoded.get_data()), encoded.length()) == OK);
	CHECK(file->get_as_utf8_string() == unicode);

	// A read from a nonzero cursor must report the short read rather than
	// decoding bytes not provided by the underlying file.
	file->seek(1);
	ERR_PRINT_OFF;
	CHECK(file->get_as_utf8_string().is_empty());
	ERR_PRINT_ON;
	file->close();
}

TEST_CASE("[FileAccess][Performance] Reused Zstandard compression context keeps independent frames") {
	Compression::ZstdCompressionContext compressor;
	const int sizes[] = { 1, 4, 16, 64, 127, 512, 4096, 65536 };

	// Exercise the same compressor across many payload sizes and back-to-back
	// frames; the decoder must be able to read every frame independently.
	for (int repeat = 0; repeat < 6; repeat++) {
		for (int size : sizes) {
			Vector<uint8_t> source;
			REQUIRE(source.resize_uninitialized(size) == OK);
			uint8_t *input = source.ptrw();
			for (int i = 0; i < size; i++) {
				input[i] = uint8_t(((uint32_t)i * 37 + (uint32_t)repeat * 19 + (i / 29) * 11) & 255);
			}

			const int64_t capacity = Compression::get_max_compressed_buffer_size(size, Compression::MODE_ZSTD);
			REQUIRE(capacity > 0);
			Vector<uint8_t> compressed;
			REQUIRE(compressed.resize_uninitialized(capacity) == OK);
			const int64_t length = compressor.compress(compressed.ptrw(), source.ptr(), size);
			REQUIRE(length > 0);
			REQUIRE(length <= capacity);

			Vector<uint8_t> decoded;
			REQUIRE(decoded.resize_uninitialized(size) == OK);
			const int64_t decoded_size = Compression::decompress(decoded.ptrw(), size, compressed.ptr(), length, Compression::MODE_ZSTD);
			CHECK(decoded_size == size);
			CHECK(decoded == source);
		}
	}
}

TEST_CASE("[FileAccess][Performance] Multi-block Zstandard compressed file reuses context") {
	const String file_path = TestUtils::get_temp_path("cgame_zstd_context_reuse.bin");
	const int block_size = 512;
	const int bytes = block_size * 384 + 17;

	Vector<uint8_t> source;
	REQUIRE(source.resize_uninitialized(bytes) == OK);
	uint8_t *input = source.ptrw();
	for (int i = 0; i < bytes; i++) {
		input[i] = uint8_t((i * 13 + i / 127) & 255);
	}

	Ref<FileAccessCompressed> writer;
	writer.instantiate();
	writer->configure("GCPF", Compression::MODE_ZSTD, block_size);
	REQUIRE(writer->open_internal(file_path, FileAccess::WRITE) == OK);
	REQUIRE(writer->store_buffer(source.ptr(), source.size()));
	writer->close();

	Ref<FileAccessCompressed> reader;
	reader.instantiate();
	reader->configure("GCPF", Compression::MODE_ZSTD, block_size);
	REQUIRE(reader->open_internal(file_path, FileAccess::READ) == OK);
	CHECK(reader->get_length() == bytes);

	Vector<uint8_t> decoded;
	REQUIRE(decoded.resize_uninitialized(bytes) == OK);
	CHECK(reader->get_buffer(decoded.ptrw(), bytes) == uint64_t(bytes));
	CHECK(decoded == source);
	reader->seek(block_size * 180 - 7);
	uint8_t cross_block[27] = {};
	CHECK(reader->get_buffer(cross_block, sizeof(cross_block)) == sizeof(cross_block));
	for (int i = 0; i < int(sizeof(cross_block)); i++) {
		CHECK(cross_block[i] == source[block_size * 180 - 7 + i]);
	}
	reader->close();
	DirAccess::remove_file_or_error(file_path);
}

TEST_CASE("[FileAccess][Performance] Token scanning reuses stack-first character buffer") {
	const String expected[] = {
		String("simple"),
		String("small"),
		String("x").repeat(255),
		String("y").repeat(256),
		String("z").repeat(257),
		String("long").repeat(1024),
		String::utf8("Привет"),
		String("tail"),
	};
	String contents = "   \t  \n  ";
	for (const String &token : expected) {
		contents += token + " \t\n";
	}
	const CharString bytes = contents.utf8();
	Ref<FileAccessMemory> file;
	file.instantiate();
	REQUIRE(file->open_custom(reinterpret_cast<const uint8_t *>(bytes.get_data()), bytes.length()) == OK);

	for (const String &token : expected) {
		CHECK(file->get_token() == token);
	}
	CHECK(file->get_position() <= file->get_length());
	file->close();

	// Whitespace-only files have no token and should allocate no token bytes.
	const char whitespace[] = " \t\n\r ";
	REQUIRE(file->open_custom(reinterpret_cast<const uint8_t *>(whitespace), sizeof(whitespace) - 1) == OK);
	CHECK(file->get_token().is_empty());
	file->close();
}

TEST_CASE("[FileAccess][Performance] Batched compressed tables preserve all codec headers") {
	const String path = TestUtils::get_temp_path("cgame_compressed_batched_table.bin");
	const int block_size = 64;
	const int byte_count = block_size * 311 + 13;
	const uint32_t block_count = byte_count / block_size + 1;
	Vector<uint8_t> payload;
	REQUIRE(payload.resize_uninitialized(byte_count) == OK);
	uint8_t *bytes = payload.ptrw();
	for (int i = 0; i < byte_count; i++) {
		bytes[i] = uint8_t((i * 29 + (i / 97) * 7) & 255);
	}

	const Compression::Mode modes[] = {
		Compression::MODE_FASTLZ,
		Compression::MODE_DEFLATE,
		Compression::MODE_GZIP,
		Compression::MODE_ZSTD,
	};
	for (Compression::Mode mode : modes) {
		Ref<FileAccessCompressed> writer;
		writer.instantiate();
		writer->configure("GCPF", mode, block_size);
		REQUIRE(writer->open_internal(path, FileAccess::WRITE) == OK);
		CHECK(writer->store_buffer(payload.ptr(), payload.size()));
		writer->close();

		// Parse the file with the ordinary binary reader, rather than relying
		// exclusively on FileAccessCompressed's new table decoder.
		Ref<FileAccess> raw = FileAccess::open(path, FileAccess::READ);
		REQUIRE(raw.is_valid());
		char magic[4];
		REQUIRE(raw->get_buffer(reinterpret_cast<uint8_t *>(magic), 4) == 4);
		CHECK(String::utf8(magic, 4) == "GCPF");
		CHECK(raw->get_32() == uint32_t(mode));
		CHECK(raw->get_32() == uint32_t(block_size));
		CHECK(raw->get_32() == uint32_t(byte_count));
		uint64_t compressed_total = 0;
		for (uint32_t i = 0; i < block_count; i++) {
			const uint32_t compressed_size = raw->get_32();
			CHECK(compressed_size > 0);
			compressed_total += compressed_size;
		}
		CHECK(raw->get_position() == uint64_t(16) + uint64_t(block_count) * 4);
		CHECK(raw->get_length() == raw->get_position() + compressed_total + 4);
		raw->close();

		Ref<FileAccessCompressed> reader;
		reader.instantiate();
		reader->configure("GCPF", mode, block_size);
		REQUIRE(reader->open_internal(path, FileAccess::READ) == OK);
		CHECK(reader->get_length() == uint64_t(byte_count));
		Vector<uint8_t> restored;
		REQUIRE(restored.resize_uninitialized(byte_count) == OK);
		CHECK(reader->get_buffer(restored.ptrw(), byte_count) == uint64_t(byte_count));
		CHECK(restored == payload);
		reader->seek(block_size * 140 - 5);
		uint8_t crossing[28] = {};
		CHECK(reader->get_buffer(crossing, sizeof(crossing)) == sizeof(crossing));
		for (int i = 0; i < int(sizeof(crossing)); i++) {
			CHECK(crossing[i] == payload[block_size * 140 - 5 + i]);
		}
		reader->close();
	}
	DirAccess::remove_file_or_error(path);
}


TEST_CASE("[FileAccess][Performance] Compressed block tables preserve tiny files with large configured blocks") {
	// The decoder used to allocate a full block for every file, even when
	// only a few bytes of decompressed data can ever exist.
	const String path = TestUtils::get_temp_path("compressed_small_payload_large_block.bin");
	constexpr uint32_t block_size = 8 * 1024 * 1024;
	const int byte_counts[] = { 17, 257, 4095, 8191 };
	const Compression::Mode modes[] = {
		Compression::MODE_FASTLZ,
		Compression::MODE_DEFLATE,
		Compression::MODE_GZIP,
		Compression::MODE_ZSTD,
	};

	for (Compression::Mode mode : modes) {
		for (int byte_count : byte_counts) {
			Vector<uint8_t> source;
			REQUIRE(source.resize_uninitialized(byte_count) == OK);
			uint8_t *source_bytes = source.ptrw();
			for (int i = 0; i < byte_count; i++) {
				source_bytes[i] = uint8_t((i * 29 + (i >> 5)) & 255);
			}

			Ref<FileAccessCompressed> writer;
			writer.instantiate();
			writer->configure("GCPF", mode, block_size);
			REQUIRE(writer->open_internal(path, FileAccess::WRITE) == OK);
			REQUIRE(writer->store_buffer(source.ptr(), source.size()));
			writer->close();

			Ref<FileAccessCompressed> reader;
			reader.instantiate();
			reader->configure("GCPF", mode, block_size);
			REQUIRE(reader->open_internal(path, FileAccess::READ) == OK);
			CHECK(reader->get_length() == uint64_t(byte_count));

			Vector<uint8_t> output;
			REQUIRE(output.resize_uninitialized(byte_count) == OK);
			CHECK(reader->get_buffer(output.ptrw(), byte_count) == uint64_t(byte_count));
			CHECK(output == source);

			const uint64_t offset = uint64_t(byte_count / 2);
			reader->seek(offset);
			uint8_t segment[13] = {};
			REQUIRE(reader->get_buffer(segment, sizeof(segment)) == sizeof(segment));
			for (int i = 0; i < int(sizeof(segment)); i++) {
				CHECK(segment[i] == source[int(offset) + i]);
			}
			reader->close();
		}
	}
	DirAccess::remove_file_or_error(path);
}

} // namespace TestFileAccess
