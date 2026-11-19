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
#include "core/io/file_access_packed_byte_array.h"
#include "tests/test_utils.h"

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


TEST_CASE("[FileAccessPackedByteArray] Zero-length reads preserve state") {
	PackedByteArray bytes;
	for (int i = 0; i < 4096; i++) {
		bytes.push_back(uint8_t(i & 0xFF));
	}

	Ref<FileAccessPackedByteArray> file;
	file.instantiate();
	REQUIRE(file->open_custom(bytes) == OK);
	REQUIRE(file->get_length() == 4096);

	uint8_t sentinel = 0xA5;
	CHECK(file->get_buffer(&sentinel, 0) == 0);
	CHECK(file->get_position() == 0);
	CHECK(sentinel == 0xA5);

	file->seek(2048);
	CHECK(file->get_buffer(&sentinel, 0) == 0);
	CHECK(file->get_position() == 2048);
	CHECK(sentinel == 0xA5);

	file->seek_end(0);
	CHECK(file->eof_reached());
	CHECK(file->get_buffer(&sentinel, 0) == 0);
	CHECK(file->get_position() == 4096);
	CHECK(sentinel == 0xA5);

	uint8_t output[4096] = {};
	file->seek(0);
	CHECK(file->get_buffer(output, 4096) == 4096);
	CHECK(output[0] == 0);
	CHECK(output[255] == 255);
	CHECK(output[4095] == 255);
	CHECK(file->eof_reached());
	CHECK(file->get_buffer(&sentinel, 0) == 0);
	CHECK(file->get_position() == 4096);
}

TEST_CASE("[FileAccessPackedByteArray] Reads around 4096-byte page boundaries") {
	const int sizes[] = { 0, 1, 4095, 4096, 4097, 8192 };

	for (int size : sizes) {
		PackedByteArray bytes;
		for (int i = 0; i < size; i++) {
			bytes.push_back(uint8_t(i & 0xFF));
		}
		Ref<FileAccessPackedByteArray> file;
		file.instantiate();
		REQUIRE(file->open_custom(bytes) == OK);

		uint8_t buffer[4096] = {};
		int full_pages = size / 4096;
		for (int page = 0; page < full_pages; page++) {
			CHECK(file->get_buffer(buffer, 4096) == 4096);
		}

		uint64_t remaining = size % 4096;
		uint8_t sentinel = 0xD3;
		if (remaining > 0) {
			CHECK(file->get_buffer(buffer, remaining) == remaining);
		}
		CHECK(file->get_position() == (uint64_t)size);
		CHECK(file->get_buffer(&sentinel, 0) == 0);
		CHECK(file->get_position() == (uint64_t)size);
		CHECK(sentinel == 0xD3);
	}
}

TEST_CASE("[FileAccessPackedByteArray] Empty files allow zero-byte reads") {
	Ref<FileAccessPackedByteArray> file;
	file.instantiate();
	REQUIRE(file->open_custom(PackedByteArray()) == OK);
	CHECK(file->get_length() == 0);
	CHECK(file->eof_reached());
	uint8_t sentinel = 0x51;
	for (int i = 0; i < 10; i++) {
		CHECK(file->get_buffer(&sentinel, 0) == 0);
		CHECK(file->get_position() == 0);
		CHECK(sentinel == 0x51);
	}
}

TEST_CASE("[FileAccessPackedByteArray] Reading one byte after zero reads") {
	Ref<FileAccessPackedByteArray> file;
	file.instantiate();
	PackedByteArray input;
	input.push_back(0x3D);
	REQUIRE(file->open_custom(input) == OK);
	uint8_t value = 0xA5;
	for (int i = 0; i < 10; i++) {
		CHECK(file->get_buffer(&value, 0) == 0);
		CHECK(file->get_position() == 0);
		CHECK_FALSE(file->eof_reached());
	}
	CHECK(file->get_buffer(&value, 1) == 1);
	CHECK(value == 0x3D);
	CHECK(file->eof_reached());
	CHECK(file->get_buffer(&value, 0) == 0);
	CHECK(value == 0x3D);
}

TEST_CASE("[FileAccessPackedByteArray] Mixed reads preserve byte order") {
	Ref<FileAccessPackedByteArray> file;
	file.instantiate();
	PackedByteArray input;
	for (int i = 0; i < 257; i++) {
		input.push_back(uint8_t(i & 0xFF));
	}
	REQUIRE(file->open_custom(input) == OK);
	uint8_t out[257] = {};
	CHECK(file->get_buffer(out, 100) == 100);
	CHECK(file->get_buffer(out, 0) == 0);
	CHECK(file->get_position() == 100);
	CHECK(file->get_buffer(out + 100, 157) == 157);
	CHECK(file->get_buffer(out, 0) == 0);
	CHECK(file->get_position() == 257);
	for (int i = 0; i < 257; i++) {
		CHECK(out[i] == (i & 0xFF));
	}
}

TEST_CASE("[FileAccessPackedByteArray] Repeated zero reads after seeks") {
	Ref<FileAccessPackedByteArray> file;
	file.instantiate();
	PackedByteArray input;
	input.resize(8192);
	REQUIRE(file->open_custom(input) == OK);
	uint8_t sentinel = 0xA5;
	const int offsets[] = { 8192, 8191, 4096, 4095, 0 };
	for (int offset : offsets) {
		file->seek(offset);
		CHECK(file->get_position() == (uint64_t)offset);
		for (int attempt = 0; attempt < 3; attempt++) {
			CHECK(file->get_buffer(&sentinel, 0) == 0);
			CHECK(file->get_position() == (uint64_t)offset);
			CHECK(sentinel == 0xA5);
		}
	}
}

TEST_CASE("[FileAccessPackedByteArray] Zero reads never change EOF status") {
	Ref<FileAccessPackedByteArray> file;
	file.instantiate();
	PackedByteArray input;
	input.push_back(7);
	input.push_back(8);
	REQUIRE(file->open_custom(input) == OK);
	uint8_t value = 0xAA;
	CHECK(file->get_error() == OK);
	CHECK(file->get_buffer(&value, 0) == 0);
	CHECK(file->get_error() == OK);
	file->seek_end(0);
	CHECK(file->get_error() == ERR_FILE_EOF);
	CHECK(file->get_buffer(&value, 0) == 0);
	CHECK(file->get_error() == ERR_FILE_EOF);
	file->seek_end(-1);
	CHECK(file->get_error() == OK);
	CHECK(file->get_buffer(&value, 0) == 0);
	CHECK(file->get_error() == OK);
}

} // namespace TestFileAccess
