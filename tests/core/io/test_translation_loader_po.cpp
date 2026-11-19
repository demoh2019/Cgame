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

} // namespace TestTranslationLoaderPO
