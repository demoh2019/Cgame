/**************************************************************************/
/*  test_config_file.cpp                                                  */
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

TEST_FORCE_LINK(test_config_file)

#include "core/input/input_event.h"
#include "core/io/config_file.h"

#ifdef WINDOWS_ENABLED
#include "core/os/os.h"
#endif

namespace TestConfigFile {

TEST_CASE("[ConfigFile] Parsing well-formatted files") {
	ConfigFile config_file;
	// Formatting is intentionally hand-edited to see how human-friendly the parser is.
	const Error error = config_file.parse(R"(
[player]

name = "Unnamed Player"
tagline="Waiting
for
Godot"

color =Color(   0, 0.5,1, 1) ; Inline comment
position= Vector2(
	3,
	4
)

[graphics]

antialiasing = true

; Testing comments and case-sensitivity...
antiAliasing = false
)");

	CHECK_MESSAGE(error == OK, "The configuration file should parse successfully.");
	CHECK_MESSAGE(
			String(config_file.get_value("player", "name")) == "Unnamed Player",
			"Reading `player/name` should return the expected value.");
	CHECK_MESSAGE(
			String(config_file.get_value("player", "tagline")) == "Waiting\nfor\nGodot",
			"Reading `player/tagline` should return the expected value.");
	CHECK_MESSAGE(
			Color(config_file.get_value("player", "color")).is_equal_approx(Color(0, 0.5, 1)),
			"Reading `player/color` should return the expected value.");
	CHECK_MESSAGE(
			Vector2(config_file.get_value("player", "position")).is_equal_approx(Vector2(3, 4)),
			"Reading `player/position` should return the expected value.");
	CHECK_MESSAGE(
			bool(config_file.get_value("graphics", "antialiasing")),
			"Reading `graphics/antialiasing` should return `true`.");
	CHECK_MESSAGE(
			bool(config_file.get_value("graphics", "antiAliasing")) == false,
			"Reading `graphics/antiAliasing` should return `false`.");

	// An empty ConfigFile is valid.
	const Error error_empty = config_file.parse("");
	CHECK_MESSAGE(error_empty == OK,
			"An empty configuration file should parse successfully.");
}

TEST_CASE("[ConfigFile] Parsing malformatted file") {
	ConfigFile config_file;
	ERR_PRINT_OFF;
	const Error error = config_file.parse(R"(
[player]

name = "Unnamed Player"" ; Extraneous closing quote.
tagline = "Waiting\nfor\nGodot"

color = Color(0, 0.5, 1) ; Missing 4th parameter.
position = Vector2(
	3,,
	4
) ; Extraneous comma.

[graphics]

antialiasing = true
antialiasing = false ; Duplicate key.
)");
	ERR_PRINT_ON;

	CHECK_MESSAGE(error == ERR_PARSE_ERROR,
			"The configuration file shouldn't parse successfully.");
}

TEST_CASE("[ConfigFile] Saving file") {
	ConfigFile config_file;
	config_file.set_value("player", "name", "Unnamed Player");
	config_file.set_value("player", "tagline", "Waiting\nfor\nGodot");
	config_file.set_value("player", "color", Color(0, 0.5, 1));
	config_file.set_value("player", "position", Vector2(3, 4));
	config_file.set_value("graphics", "antialiasing", true);
	config_file.set_value("graphics", "antiAliasing", false);
	config_file.set_value("quoted", String::utf8("静音"), 42);
	config_file.set_value("quoted", "a=b", 7);

#ifdef WINDOWS_ENABLED
	const String config_path = OS::get_singleton()->get_environment("TEMP").path_join("config.ini");
#else
	const String config_path = "/tmp/config.ini";
#endif

	config_file.save(config_path);

	// Expected contents of the saved ConfigFile.
	const String contents = String::utf8(R"([player]

name="Unnamed Player"
tagline="Waiting
for
Godot"
color=Color(0, 0.5, 1, 1)
position=Vector2(3, 4)

[graphics]

antialiasing=true
antiAliasing=false

[quoted]

"静音"=42
"a=b"=7
)");

	Ref<FileAccess> file = FileAccess::open(config_path, FileAccess::READ);
	CHECK_MESSAGE(file->get_as_utf8_string() == contents,
			"The saved configuration file should match the expected format.");
}

TEST_CASE("[ConfigFile] Saving pretty printed Objects") {
	ConfigFile config_file;

	Ref<InputEventKey> key;
	key.instantiate();
	key->set_keycode(Key::SPACE);

	Dictionary d_ui_accept({ { "deadzone", 0.5 }, { "events", Array({ key }) } });

	config_file.set_value("input", "ui_accept", d_ui_accept);

	const String expected = R"([input]

ui_accept={
"deadzone": 0.5,
"events": [Object(InputEventKey,
"resource_local_to_scene": false,
"resource_name": "",
"device": 16,
"window_id": 0,
"alt_pressed": false,
"shift_pressed": false,
"ctrl_pressed": false,
"meta_pressed": false,
"pressed": false,
"keycode": 32,
"physical_keycode": 0,
"key_label": 0,
"unicode": 0,
"location": 0,
"echo": false,
"script": null
)]
}
)";

	CHECK_MESSAGE(config_file.encode_to_text() == expected, "Object properties should be on new lines.");
}


TEST_CASE("[ConfigFile][Performance] Hot section and key lookups retain all semantics") {
	ConfigFile config;
	const int sections = 11;
	const int keys = 128;
	for (int section_index = 0; section_index < sections; section_index++) {
		const String section = "group_" + itos(section_index);
		for (int key_index = 0; key_index < keys; key_index++) {
			config.set_value(section, "entry_" + itos(key_index), section_index * keys + key_index);
		}
	}
	REQUIRE(config.get_sections().size() == sections);

	for (int section_index = 0; section_index < sections; section_index++) {
		const String section = "group_" + itos(section_index);
		CHECK(config.has_section(section));
		CHECK(config.get_section_keys(section).size() == keys);
		for (int key_index = 0; key_index < keys; key_index++) {
			const String key = "entry_" + itos(key_index);
			CHECK(config.has_section_key(section, key));
			CHECK(int(config.get_value(section, key)) == section_index * keys + key_index);
		}
	}

	// Lookups for nonexistent keys must not create sections or values.
	CHECK_FALSE(config.has_section_key("missing", "entry_1"));
	CHECK_FALSE(config.has_section_key("group_1", "missing"));
	CHECK(int(config.get_value("missing", "entry_1", -7)) == -7);
	CHECK(int(config.get_value("group_1", "missing", 42)) == 42);
	CHECK(config.get_sections().size() == sections);

	// Updating existing values keeps insertion order; nil removes a key.
	config.set_value("group_3", "entry_4", 1337);
	CHECK(int(config.get_value("group_3", "entry_4")) == 1337);
	config.set_value("group_3", "entry_4", Variant());
	CHECK_FALSE(config.has_section_key("group_3", "entry_4"));
	CHECK(config.get_section_keys("group_3").size() == keys - 1);
	config.set_value("group_3", "entry_4", 4);
	CHECK(int(config.get_value("group_3", "entry_4")) == 4);

	// Clearing the last key removes its parent section automatically.
	config.set_value("temporary", "only", 99);
	config.erase_section_key("temporary", "only");
	CHECK_FALSE(config.has_section("temporary"));

	config.set_value("temporary", "only", 99);
	config.set_value("temporary", "only", Variant());
	CHECK_FALSE(config.has_section("temporary"));

	config.erase_section("group_1");
	CHECK_FALSE(config.has_section("group_1"));
	CHECK(config.get_sections().size() == sections - 1);

	// Section-less keys are inserted before named sections, even if late.
	config.set_value("", "global", "ok");
	const Vector<String> section_names = config.get_sections();
	REQUIRE(section_names.size() == sections);
	CHECK(section_names[0] == "");
	CHECK(String(config.get_value("", "global")) == "ok");

	const String serialized = config.encode_to_text();
	ConfigFile restored;
	CHECK(restored.parse(serialized) == OK);
	CHECK(int(restored.get_value("group_3", "entry_4")) == 4);
	CHECK(String(restored.get_value("", "global")) == "ok");
	CHECK(restored.has_section("group_0"));
	CHECK_FALSE(restored.has_section("group_1"));
}

TEST_CASE("[ConfigFile][Performance] Chunked large save retains exact values and encoding") {
	ConfigFile config;
	config.set_value("", "global", "unsectioned");
	config.set_value("escaped]name", "bracket", 17);
	config.set_value("unicode", String::utf8("ключ"), String::utf8("значение"));
	const String payload = "The quick brown fox jumps over the lazy dog.";
	for (int index = 0; index < 2300; ++index) {
		config.set_value("bulk", "entry_" + itos(index), payload + itos(index));
	}
	// A single very large value must also be handled without splitting data.
	config.set_value("bulk", "long_value", String("x").repeat(65536));

#ifdef WINDOWS_ENABLED
	const String path = OS::get_singleton()->get_environment("TEMP").path_join("config_chunked.ini");
#else
	const String path = "/tmp/config_chunked.ini";
#endif
	REQUIRE(config.save(path) == OK);
	Ref<FileAccess> saved = FileAccess::open(path, FileAccess::READ);
	REQUIRE(saved.is_valid());
	const String bytes = saved->get_as_utf8_string();
	CHECK(bytes.begins_with("global=\"unsectioned\"\n\n[escaped\\]name]\n\nbracket=17"));
	CHECK(bytes.contains(String::utf8("ключ")));
	CHECK(bytes.contains(String::utf8("значение")));
	saved.unref();

	ConfigFile restored;
	REQUIRE(restored.load(path) == OK);
	CHECK(String(restored.get_value("", "global")) == "unsectioned");
	CHECK(int(restored.get_value("escaped]name", "bracket")) == 17);
	CHECK(String(restored.get_value("unicode", String::utf8("ключ"))) == String::utf8("значение"));
	CHECK(String(restored.get_value("bulk", "long_value")).length() == 65536);
	for (int index = 0; index < 2300; ++index) {
		CHECK(String(restored.get_value("bulk", "entry_" + itos(index))) == payload + itos(index));
	}
}

} // namespace TestConfigFile
