/**************************************************************************/
/*  test_lipo.cpp                                                         */
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

TEST_FORCE_LINK(test_lipo)

#ifdef TOOLS_ENABLED

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "editor/export/lipo.h"
#include "tests/test_utils.h"

namespace TestLipO {

TEST_CASE("[LipO] Page-aligned and unaligned archive round-trip") {
	const int input_sizes[] = { 1, 1024, 4094, 4095, 4096, 4097, 8191, 8192, 8193, 12288, 16384 };

	for (int size : input_sizes) {
		PackedByteArray source;
		for (int i = 0; i < size; i++) {
			source.push_back(uint8_t((i * 37 + 11) & 0xFF));
		}
		Vector<PackedByteArray> inputs;
		inputs.push_back(source);

		Vector<Vector2i> arch_types;
		arch_types.push_back(Vector2i(7, 3));

		const String archive_path = TestUtils::get_temp_path(vformat("lipo_page_%d.bin", size));
		const String extracted_path = TestUtils::get_temp_path(vformat("lipo_extracted_%d.bin", size));

		// The input is raw test data rather than a Mach-O. The explicit CPU
		// type allows LipO to pack it using the fallback path.
		ERR_PRINT_OFF;
		const bool created = LipO::create_file(archive_path, inputs, arch_types);
		ERR_PRINT_ON;
		REQUIRE(created);

		Ref<LipO> archive;
		archive.instantiate();
		REQUIRE(archive->open_file(archive_path));
		REQUIRE(archive->get_arch_count() == 1);
		CHECK(archive->get_arch_cputype(0) == 7);
		CHECK(archive->get_arch_cpusubtype(0) == 3);
		REQUIRE(archive->extract_arch(0, extracted_path));
		archive->close();

		CHECK(FileAccess::get_file_as_bytes(extracted_path) == source);

		DirAccess::remove_file_or_error(extracted_path);
		DirAccess::remove_file_or_error(archive_path);
	}
}

} // namespace TestLipO

#endif // TOOLS_ENABLED
