/**************************************************************************/
/*  test_pck_packer.cpp                                                   */
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

TEST_FORCE_LINK(test_pck_packer)

#include "core/io/file_access.h"
#include "core/io/pck_packer.h"
#include "core/io/file_access_pack.h"
#include "core/os/os.h"
#include "tests/test_utils.h"

namespace TestPCKPacker {

TEST_CASE("[PCKPacker] Pack an empty PCK file") {
	PCKPacker pck_packer;
	const String output_pck_path = TestUtils::get_temp_path("output_empty.pck");
	CHECK_MESSAGE(
			pck_packer.pck_start(output_pck_path) == OK,
			"Starting a PCK file should return an OK error code.");

	CHECK_MESSAGE(
			pck_packer.flush() == OK,
			"Flushing the PCK should return an OK error code.");

	Error err;
	Ref<FileAccess> f = FileAccess::open(output_pck_path, FileAccess::READ, &err);
	CHECK_MESSAGE(
			err == OK,
			"The generated empty PCK file should be opened successfully.");
	CHECK_MESSAGE(
			f->get_length() >= 100,
			"The generated empty PCK file shouldn't be too small (it should have the PCK header).");
	CHECK_MESSAGE(
			f->get_length() <= 500,
			"The generated empty PCK file shouldn't be too large.");
}

TEST_CASE("[PCKPacker] Pack empty with zero alignment invalid") {
	PCKPacker pck_packer;
	const String output_pck_path = TestUtils::get_temp_path("output_empty.pck");
	ERR_PRINT_OFF;
	CHECK_MESSAGE(pck_packer.pck_start(output_pck_path, 0) != OK, "PCK with zero alignment should fail.");
	ERR_PRINT_ON;
}

TEST_CASE("[PCKPacker] Pack empty with invalid key") {
	PCKPacker pck_packer;
	const String output_pck_path = TestUtils::get_temp_path("output_empty.pck");
	ERR_PRINT_OFF;
	CHECK_MESSAGE(pck_packer.pck_start(output_pck_path, 32, "") != OK, "PCK with invalid key should fail.");
	ERR_PRINT_ON;
}

TEST_CASE("[PCKPacker] Pack a PCK file with some files and directories") {
	PCKPacker pck_packer;
	const String output_pck_path = TestUtils::get_temp_path("output_with_files.pck");
	CHECK_MESSAGE(
			pck_packer.pck_start(output_pck_path) == OK,
			"Starting a PCK file should return an OK error code.");

	const String base_dir = OS::get_singleton()->get_executable_path().get_base_dir();

	CHECK_MESSAGE(
			pck_packer.add_file("version.py", base_dir.path_join("../version.py"), "version.py") == OK,
			"Adding a file to the PCK should return an OK error code.");
	CHECK_MESSAGE(
			pck_packer.add_file("some/directories with spaces/to/create/icon.png", base_dir.path_join("../misc/logo/icon.png")) == OK,
			"Adding a file to a new subdirectory in the PCK should return an OK error code.");
	CHECK_MESSAGE(
			pck_packer.add_file("some/directories with spaces/to/create/icon.svg", base_dir.path_join("../misc/logo/icon.svg")) == OK,
			"Adding a file to an existing subdirectory in the PCK should return an OK error code.");
	CHECK_MESSAGE(
			pck_packer.add_file("some/directories with spaces/to/create/icon.png", base_dir.path_join("../misc/logo/logo.png")) == OK,
			"Overriding a non-flushed file to an existing subdirectory in the PCK should return an OK error code.");
	CHECK_MESSAGE(
			pck_packer.add_file_from_buffer("buffer/new.txt", String("Hello world!").to_utf8_buffer()) == OK,
			"Adding a file from a buffer to the PCK in a new subdirectory should return an OK error code.");
	CHECK_MESSAGE(
			pck_packer.flush() == OK,
			"Flushing the PCK should return an OK error code.");

	Error err;
	Ref<FileAccess> f = FileAccess::open(output_pck_path, FileAccess::READ, &err);
	CHECK_MESSAGE(
			err == OK,
			"The generated non-empty PCK file should be opened successfully.");
	CHECK_MESSAGE(
			f->get_length() >= 18000,
			"The generated non-empty PCK file should be large enough to actually hold the contents specified above.");
	CHECK_MESSAGE(
			f->get_length() <= 27000,
			"The generated non-empty PCK file shouldn't be too large.");
}


TEST_CASE("[PCKPacker] PackedData index shares directories and removes paths") {
	// Main::test_setup() already owns the PackedData singleton. Do not
	// replace it with a temporary object or reset unrelated pack entries.
	PackedData *packed = PackedData::get_singleton();
	REQUIRE(packed != nullptr);
	const uint32_t previous_count = packed->get_file_paths().size();
	uint8_t md5[16] = {};
	md5[0] = 0x6e;

	packed->add_path("sample.pck", "res://__pck_lookup_perf_tests__/levels/one/alpha.tscn", 0, 32, md5, nullptr, false);
	packed->add_path("sample.pck", "res://__pck_lookup_perf_tests__/levels/one/beta.tscn", 32, 16, md5, nullptr, false);
	packed->add_path("sample.pck", "res://__pck_lookup_perf_tests__/levels/two/gamma.tscn", 48, 64, md5, nullptr, false);
	CHECK(packed->has_path("res://__pck_lookup_perf_tests__/levels/one/alpha.tscn"));
	CHECK(packed->has_path("res://__pck_lookup_perf_tests__/levels/one/beta.tscn"));
	CHECK(packed->has_path("res://__pck_lookup_perf_tests__/levels/two/gamma.tscn"));
	CHECK(packed->get_file_paths().size() == previous_count + 3);

	packed->remove_path("res://__pck_lookup_perf_tests__/levels/one/alpha.tscn");
	CHECK_FALSE(packed->has_path("res://__pck_lookup_perf_tests__/levels/one/alpha.tscn"));
	CHECK(packed->has_path("res://__pck_lookup_perf_tests__/levels/one/beta.tscn"));
	CHECK(packed->has_path("res://__pck_lookup_perf_tests__/levels/two/gamma.tscn"));
	CHECK(packed->get_file_paths().size() == previous_count + 2);

	packed->remove_path("res://__pck_lookup_perf_tests__/levels/one/beta.tscn");
	packed->remove_path("res://__pck_lookup_perf_tests__/levels/two/gamma.tscn");
	CHECK(packed->get_file_paths().size() == previous_count);
}

TEST_CASE("[PCKPacker] PackedData index of many files in existing directories") {
	PackedData *packed = PackedData::get_singleton();
	REQUIRE(packed != nullptr);
	const uint32_t previous_count = packed->get_file_paths().size();
	uint8_t md5[16] = {};
	for (int i = 0; i < 512; i++) {
		String path = "res://__pck_lookup_batch_tests__/assets/shared/textures/texture_" + itos(i) + ".png";
		packed->add_path("assets.pck", path, uint64_t(i) * 64, 64, md5, nullptr, false);
	}
	CHECK(packed->get_file_paths().size() == previous_count + 512);
	CHECK(packed->has_path("res://__pck_lookup_batch_tests__/assets/shared/textures/texture_0.png"));
	CHECK(packed->has_path("res://__pck_lookup_batch_tests__/assets/shared/textures/texture_511.png"));

	for (int i = 0; i < 512; i += 2) {
		packed->remove_path("res://__pck_lookup_batch_tests__/assets/shared/textures/texture_" + itos(i) + ".png");
	}
	CHECK(packed->get_file_paths().size() == previous_count + 256);
	CHECK_FALSE(packed->has_path("res://__pck_lookup_batch_tests__/assets/shared/textures/texture_0.png"));
	CHECK(packed->has_path("res://__pck_lookup_batch_tests__/assets/shared/textures/texture_1.png"));
	for (int i = 1; i < 512; i += 2) {
		packed->remove_path("res://__pck_lookup_batch_tests__/assets/shared/textures/texture_" + itos(i) + ".png");
	}
	CHECK(packed->get_file_paths().size() == previous_count);
}


TEST_CASE("[PCKPacker] FileAccessPack bounded bulk reads and unsigned lengths") {
	const String path = TestUtils::get_temp_path("pck_bulk_read_bounds.bin");
	const uint8_t contents[] = { 11, 22, 33, 44, 55, 66, 77, 88 };
	{
		Ref<FileAccess> file = FileAccess::open(path, FileAccess::WRITE);
		REQUIRE(file.is_valid());
		CHECK(file->store_buffer(contents, sizeof(contents)));
		file->close();
	}

	PackedData::PackedFile metadata{};
	metadata.pack = path;
	metadata.offset = 0;
	metadata.size = sizeof(contents);
	metadata.bundle = false;
	metadata.encrypted = false;
	Ref<FileAccess> file(memnew(FileAccessPack("res://pck_bulk_read_bounds.bin", metadata)));
	REQUIRE(file.is_valid());
	CHECK(file->get_length() == 8);

	uint8_t dst[12] = {};
	CHECK(file->get_buffer(dst, 0) == 0);
	CHECK(file->get_position() == 0);
	CHECK_FALSE(file->eof_reached());
	CHECK(file->get_buffer(dst, 3) == 3);
	CHECK(dst[0] == 11);
	CHECK(dst[2] == 33);
	CHECK(file->get_position() == 3);

	// Must not overflow int64_t or advance the cursor by the request size.
	CHECK(file->get_buffer(dst, UINT64_MAX) == 5);
	CHECK(dst[0] == 44);
	CHECK(dst[4] == 88);
	CHECK(file->get_position() == 8);
	CHECK(file->eof_reached());
	CHECK(file->get_buffer(dst, 1) == 0);

	file->seek(0);
	CHECK_FALSE(file->eof_reached());
	CHECK(file->get_buffer(dst, 8) == 8);
	CHECK(file->get_position() == 8);
	CHECK_FALSE(file->eof_reached()); // An exact read does not overrun EOF.
	CHECK(file->get_buffer(dst, 1) == 0);
	CHECK(file->eof_reached());

	file->seek(9); // Beyond the logical packed entry.
	CHECK(file->eof_reached());
	CHECK(file->get_buffer(dst, UINT64_MAX) == 0);
	CHECK(file->get_position() == 9);
}

TEST_CASE("[PCKPacker] FileAccessPack reports physical short reads accurately") {
	const String path = TestUtils::get_temp_path("pck_truncated_bulk_read.bin");
	const uint8_t contents[] = { 0x17, 0x29, 0x3b };
	{
		Ref<FileAccess> out = FileAccess::open(path, FileAccess::WRITE);
		REQUIRE(out.is_valid());
		CHECK(out->store_buffer(contents, sizeof(contents)));
		out->close();
	}

	PackedData::PackedFile metadata{};
	metadata.pack = path;
	metadata.offset = 0;
	metadata.size = 10; // The archive index advertises more than the file has.
	metadata.bundle = false;
	metadata.encrypted = false;
	Ref<FileAccess> file(memnew(FileAccessPack("res://pck_truncated_bulk_read.bin", metadata)));
	REQUIRE(file.is_valid());
	uint8_t dst[12] = {};
	ERR_PRINT_OFF; // The physical file is intentionally shorter than its PCK metadata.
	CHECK(file->get_buffer(dst, 8) == 3);
	ERR_PRINT_ON;
	CHECK(file->get_position() == 3);
	CHECK(file->eof_reached());
	CHECK(dst[0] == 0x17);
	CHECK(dst[1] == 0x29);
	CHECK(dst[2] == 0x3b);
	CHECK(file->get_buffer(dst, 1) == 0);
}

} // namespace TestPCKPacker
