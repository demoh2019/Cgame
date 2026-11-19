/**************************************************************************/
/*  test_translation_loader_po.cpp                                        */
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

TEST_FORCE_LINK(test_translation_loader_po)

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/translation_loader_po.h"
#include "core/string/string_builder.h"
#include "core/string/translation.h"
#include "tests/test_utils.h"

#include <string>
#include <vector>

namespace TestTranslationLoaderPO {

TEST_CASE("[TranslationLoaderPO][Performance] Plural fragments append in place with unchanged PO semantics") {
	StringBuilder po;
	po.append(R"PO(msgid ""
msgstr ""
"Language: en\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\n"

msgid "long"
msgstr ""
)PO");
	for (int i = 0; i < 2048; i++) {
		po.append("\"ab\"\n");
	}

	// Keep the ordinary one-line gettext case on the direct String path.
	po.append(R"PO(
msgid "short"
msgstr "fast"

msgctxt ""
)PO");
	for (int i = 0; i < 128; i++) {
		po.append("\"menu\"\n");
	}
	po.append(R"PO(msgid "action"
msgstr ""
)PO");
	for (int i = 0; i < 512; i++) {
		po.append("\"ok\"\n");
	}

	po.append(R"PO(
msgid ""
)PO");
	for (int i = 0; i < 512; i++) {
		po.append("\"id\"\n");
	}
	po.append("msgstr \"converted\"\n");

	po.append(R"PO(
msgid "num"
msgid_plural "nums"
msgstr[0] ""
)PO");
	for (int i = 0; i < 1024; i++) {
		po.append("\"one\"\n");
	}
	po.append("msgstr[1] \"\"\n");
	for (int i = 0; i < 1024; i++) {
		po.append("\"other\"\n");
	}

	const String path = TestUtils::get_temp_path("po_multiline_builder_perf.po");
	Ref<FileAccess> output = FileAccess::open(path, FileAccess::WRITE);
	REQUIRE(output.is_valid());
	output->store_string(po.as_string());
	output->close();

	Ref<FileAccess> input = FileAccess::open(path, FileAccess::READ);
	REQUIRE(input.is_valid());
	Error err = ERR_FILE_CORRUPT;
	const Ref<Resource> result = TranslationLoaderPO::load_translation(input, &err);
	CHECK(err == OK);
	REQUIRE(result.is_valid());
	Translation *const translation = Object::cast_to<Translation>(result.ptr());
	REQUIRE(translation != nullptr);

	CHECK(translation->get_locale() == "en");
	CHECK(String(translation->get_message("short")) == "fast");
	CHECK(String(translation->get_message("long")) == String("ab").repeat(2048));
	CHECK(String(translation->get_message(StringName(String("id").repeat(512)))) == "converted");
	CHECK(String(translation->get_message("action", StringName(String("menu").repeat(128)))) == String("ok").repeat(512));
	CHECK(String(translation->get_plural_message("num", "nums", 1)) == String("one").repeat(1024));
	CHECK(String(translation->get_plural_message("num", "nums", 2)) == String("other").repeat(1024));

	input->close();
	DirAccess::remove_file_or_error(path);
}


TEST_CASE("[TranslationLoaderPO][Performance] Binary MO catalogs decode small and large messages with shared scratch") {
	const uint32_t count = 1026;
	std::vector<std::string> originals;
	std::vector<std::string> translated;
	originals.reserve(count);
	translated.reserve(count);

	originals.emplace_back();
	translated.emplace_back("Language: en\nContent-Type: text/plain; charset=UTF-8\nPlural-Forms: nplurals=2; plural=(n != 1);\n");
	for (uint32_t i = 1; i < count - 2; i++) {
		if (i % 57 == 0) {
			// Exercise the grow-only heap fallback, including multiple sizes.
			originals.push_back("big_" + std::to_string(i) + std::string(512 + i % 111, 'x'));
			translated.push_back("large_" + std::to_string(i) + std::string(540 + i % 79, 'y'));
		} else {
			originals.push_back("key_" + std::to_string(i));
			translated.push_back("é_日本_value_" + std::to_string(i));
		}
	}
	originals.push_back(std::string("ctx") + char(4) + "menu");
	translated.push_back("Open");
	originals.emplace_back("apple\0apples", 12);
	translated.emplace_back("pomme\0pommes", 12);
	REQUIRE(originals.size() == count);
	REQUIRE(translated.size() == count);

	const uint32_t original_table = 28;
	const uint32_t translation_table = original_table + count * 8;
	const String path = TestUtils::get_temp_path("mo_stack_buffer_reuse_perf.mo");
	// Exercise both native table decoding and FileAccess endian swapping.
	for (bool big_endian : { false, true }) {
		uint32_t data_offset = translation_table + count * 8;
		Ref<FileAccess> writer = FileAccess::open(path, FileAccess::WRITE);
		REQUIRE(writer.is_valid());
		writer->set_big_endian(big_endian);
		writer->store_32(0x950412de); // MO signature in the selected byte order.
		writer->store_32(0); // Version 0.
		writer->store_32(count);
		writer->store_32(original_table);
		writer->store_32(translation_table);
		writer->store_32(0); // No hash table.
		writer->store_32(0);
		for (const std::string &value : originals) {
			writer->store_32(uint32_t(value.size()));
			writer->store_32(data_offset);
			data_offset += uint32_t(value.size()) + 1;
		}
		for (const std::string &value : translated) {
			writer->store_32(uint32_t(value.size()));
			writer->store_32(data_offset);
			data_offset += uint32_t(value.size()) + 1;
		}
		for (const std::string &value : originals) {
			REQUIRE(writer->store_buffer(reinterpret_cast<const uint8_t *>(value.data()), value.size()));
			writer->store_8(0);
		}
		for (const std::string &value : translated) {
			REQUIRE(writer->store_buffer(reinterpret_cast<const uint8_t *>(value.data()), value.size()));
			writer->store_8(0);
		}
		CHECK(writer->get_position() == data_offset);
		writer->close();

		Ref<FileAccess> input = FileAccess::open(path, FileAccess::READ);
		REQUIRE(input.is_valid());
		input->set_big_endian(big_endian);
		Error error = ERR_FILE_CORRUPT;
		const Ref<Resource> loaded = TranslationLoaderPO::load_translation(input, &error);
		REQUIRE(error == OK);
		REQUIRE(loaded.is_valid());
		const Translation *const catalog = Object::cast_to<Translation>(loaded.ptr());
		REQUIRE(catalog != nullptr);

		CHECK(catalog->get_locale() == "en");
		CHECK(catalog->get_message_count() == count - 1);
		for (uint32_t i = 1; i < count - 2; i += 19) {
			const String key = String::utf8(originals[i].data(), originals[i].size());
			const String expected = String::utf8(translated[i].data(), translated[i].size());
			CHECK(String(catalog->get_message(StringName(key))) == expected);
		}
		CHECK(String(catalog->get_message("menu", "ctx")) == "Open");
		CHECK(String(catalog->get_plural_message("apple", "apples", 1)) == "pomme");
		CHECK(String(catalog->get_plural_message("apple", "apples", 2)) == "pommes");
		input->close();
	}
	DirAccess::remove_file_or_error(path);
}

TEST_CASE("[TranslationLoaderPO] Binary MO rejects invalid table and string offsets") {
	const String path = TestUtils::get_temp_path("mo_invalid_table_offsets.mo");
	Ref<FileAccess> writer = FileAccess::open(path, FileAccess::WRITE);
	REQUIRE(writer.is_valid());
	writer->store_32(0x950412de);
	writer->store_32(0);
	writer->store_32(0x40000000); // This many entries cannot fit.
	writer->store_32(28);
	writer->store_32(36);
	writer->store_32(0);
	writer->store_32(0);
	writer->close();

	Ref<FileAccess> reader = FileAccess::open(path, FileAccess::READ);
	REQUIRE(reader.is_valid());
	Error err = OK;
	ERR_PRINT_OFF;
	Ref<Resource> result = TranslationLoaderPO::load_translation(reader, &err);
	ERR_PRINT_ON;
	CHECK(result.is_null());
	CHECK(err == ERR_FILE_CORRUPT);
	reader->close();

	// Tables fit, but the referenced string is outside the file.
	writer = FileAccess::open(path, FileAccess::WRITE);
	REQUIRE(writer.is_valid());
	writer->store_32(0x950412de);
	writer->store_32(0);
	writer->store_32(1);
	writer->store_32(28);
	writer->store_32(36);
	writer->store_32(0);
	writer->store_32(0);
	writer->store_32(1000);
	writer->store_32(44);
	writer->store_32(0);
	writer->store_32(44);
	writer->close();

	reader = FileAccess::open(path, FileAccess::READ);
	REQUIRE(reader.is_valid());
	err = OK;
	ERR_PRINT_OFF;
	result = TranslationLoaderPO::load_translation(reader, &err);
	ERR_PRINT_ON;
	CHECK(result.is_null());
	CHECK(err == ERR_FILE_CORRUPT);
	reader->close();
	DirAccess::remove_file_or_error(path);
}

} // namespace TestTranslationLoaderPO
