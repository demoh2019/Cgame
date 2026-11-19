/**************************************************************************/
/*  gdscript_test_runner_suite.h                                          */
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

#include "../gdscript_cache.h"
#include "../gdscript_parser.h"
#include "gdscript_test_runner.h"

#include "core/io/file_access.h"
#include "core/io/resource_loader.h"
#include "tests/test_macros.h"
#include "tests/test_utils.h"

#ifdef TOOLS_ENABLED
#include "core/os/os.h"
#endif

namespace GDScriptTests {

class TestGDScriptCacheAccessor {
public:
	static bool has_shallow(String p_path) {
		return GDScriptCache::singleton->shallow_gdscript_cache.has(p_path);
	}

	static bool has_full(String p_path) {
		return GDScriptCache::singleton->full_gdscript_cache.has(p_path);
	}
};

// TODO: Handle some cases failing on release builds. See: https://github.com/godotengine/godot/pull/88452
#ifdef TOOLS_ENABLED
TEST_SUITE("[Modules][GDScript]") {
	TEST_CASE("Script compilation and runtime") {
		bool print_filenames = OS::get_singleton()->get_cmdline_args().find("--print-filenames") != nullptr;
		bool use_binary_tokens = OS::get_singleton()->get_cmdline_args().find("--use-binary-tokens") != nullptr;
		GDScriptTestRunner runner("modules/gdscript/tests/scripts", print_filenames, use_binary_tokens);
		int fail_count = runner.run_tests();
		INFO("Make sure `*.out` files have expected results.");
		REQUIRE_MESSAGE(fail_count == 0, "All GDScript tests should pass.");
	}
}
#endif // TOOLS_ENABLED

TEST_CASE("[Modules][GDScript] Load source code dynamically and run it") {
	GDScriptLanguage::get_singleton()->init();
	Ref<GDScript> gdscript = memnew(GDScript);
	gdscript->set_source_code(R"(
extends RefCounted

func _init():
	set_meta("result", 42)
)");
	// A spurious `Condition "err" is true` message is printed (despite parsing being successful and returning `OK`).
	// Silence it.
	ERR_PRINT_OFF;
	const Error error = gdscript->reload();
	ERR_PRINT_ON;
	CHECK_MESSAGE(error == OK, "The script should parse successfully.");

	// Run the script by assigning it to a reference-counted object.
	Ref<RefCounted> ref_counted = memnew(RefCounted);
	ref_counted->set_script(gdscript);
	CHECK_MESSAGE(int(ref_counted->get_meta("result")) == 42, "The script should assign object metadata successfully.");
}


TEST_CASE("[GDScriptPropertyListFastPath] exported properties preserve declaration order") {
	GDScriptLanguage::get_singleton()->init();
	Ref<GDScript> script = memnew(GDScript);
	script->set_source_code("extends RefCounted\n@export var first: int = 1\n@export var second: float = 2.0\n@export var third: String = \"ok\"\n");
	ERR_PRINT_OFF;
	const Error err = script->reload();
	ERR_PRINT_ON;
	REQUIRE_EQ(err, OK);

	Ref<RefCounted> object = memnew(RefCounted);
	object->set_script(script);
	List<PropertyInfo> properties;
	object->get_property_list(&properties);

	int pos = 0;
	int first = -1;
	int second = -1;
	int third = -1;
	for (const PropertyInfo &info : properties) {
		if (info.name == StringName("first")) { first = pos; CHECK_EQ(info.type, Variant::INT); }
		if (info.name == StringName("second")) { second = pos; CHECK_EQ(info.type, Variant::FLOAT); }
		if (info.name == StringName("third")) { third = pos; CHECK_EQ(info.type, Variant::STRING); }
		pos++;
	}
	REQUIRE(first >= 0);
	REQUIRE(second >= 0);
	REQUIRE(third >= 0);
	CHECK(first < second);
	CHECK(second < third);
}

TEST_CASE("[GDScriptPropertyListFastPath] dynamic properties follow exported properties") {
	GDScriptLanguage::get_singleton()->init();
	Ref<GDScript> script = memnew(GDScript);
	script->set_source_code(R"GD(extends RefCounted
@export var exported: int = 1

func _get_property_list() -> Array[Dictionary]:
	return [
		{"name": "dynamic_a", "type": TYPE_INT},
		{"name": "dynamic_b", "type": TYPE_STRING}
	]
)GD");
	ERR_PRINT_OFF;
	const Error err = script->reload();
	ERR_PRINT_ON;
	REQUIRE_EQ(err, OK);

	Ref<RefCounted> object = memnew(RefCounted);
	object->set_script(script);
	List<PropertyInfo> properties;
	object->get_property_list(&properties);

	int idx = 0;
	int exported = -1;
	int dynamic_a = -1;
	int dynamic_b = -1;
	for (const PropertyInfo &info : properties) {
		if (info.name == StringName("exported")) { exported = idx; }
		if (info.name == StringName("dynamic_a")) { dynamic_a = idx; CHECK_EQ(info.type, Variant::INT); }
		if (info.name == StringName("dynamic_b")) { dynamic_b = idx; CHECK_EQ(info.type, Variant::STRING); }
		idx++;
	}
	REQUIRE(exported >= 0);
	REQUIRE(dynamic_a >= 0);
	REQUIRE(dynamic_b >= 0);
	CHECK(exported < dynamic_a);
	CHECK(dynamic_a < dynamic_b);
}

TEST_CASE("[GDScriptPropertyListFastPath] repeated enumeration preserves property order") {
	GDScriptLanguage::get_singleton()->init();
	Ref<GDScript> script = memnew(GDScript);
	script->set_source_code("extends RefCounted\n@export var x: int = 1\n@export var y: int = 2\n");
	ERR_PRINT_OFF;
	const Error err = script->reload();
	ERR_PRINT_ON;
	REQUIRE_EQ(err, OK);

	Ref<RefCounted> object = memnew(RefCounted);
	object->set_script(script);
	List<PropertyInfo> original;
	object->get_property_list(&original);
	for (int i = 0; i < 64; i++) {
		List<PropertyInfo> again;
		object->get_property_list(&again);
		REQUIRE_EQ(again.size(), original.size());
		const List<PropertyInfo>::Element *lhs = original.front();
		const List<PropertyInfo>::Element *rhs = again.front();
		while (lhs != nullptr && rhs != nullptr) {
			CHECK_EQ(lhs->get().name, rhs->get().name);
			CHECK_EQ(lhs->get().type, rhs->get().type);
			lhs = lhs->next();
			rhs = rhs->next();
		}
	}
}

TEST_CASE("[GDScriptPropertyListFastPath] property type lookup reports valid and missing members") {
	GDScriptLanguage::get_singleton()->init();
	Ref<GDScript> script = memnew(GDScript);
	script->set_source_code(R"GD(extends RefCounted
@export var count: int = 7
@export var label: String = "hello"
)GD");
	ERR_PRINT_OFF;
	const Error err = script->reload();
	ERR_PRINT_ON;
	REQUIRE_EQ(err, OK);

	Ref<RefCounted> object = memnew(RefCounted);
	object->set_script(script);
	ScriptInstance *instance = object->get_script_instance();
	REQUIRE(instance != nullptr);

	bool valid = false;
	CHECK_EQ(instance->get_property_type(StringName("count"), &valid), Variant::INT);
	CHECK(valid);

	valid = false;
	CHECK_EQ(instance->get_property_type(StringName("label"), &valid), Variant::STRING);
	CHECK(valid);

	valid = true;
	CHECK_EQ(instance->get_property_type(StringName("missing_member"), &valid), Variant::NIL);
	CHECK_FALSE(valid);

	CHECK_EQ(instance->get_property_type(StringName("count"), nullptr), Variant::INT);
	CHECK_EQ(instance->get_property_type(StringName("missing_member"), nullptr), Variant::NIL);
}

TEST_CASE("[GDScriptScriptProperties] declaration order and Variant types are preserved") {
	GDScriptLanguage::get_singleton()->init();
	Ref<GDScript> script = memnew(GDScript);
	script->set_source_code("extends RefCounted\n@export var alpha: int = 3\n@export var beta: String = \"ok\"\n@export var gamma: Vector2 = Vector2(1, 2)\n");
	ERR_PRINT_OFF;
	const Error error = script->reload();
	ERR_PRINT_ON;
	REQUIRE_EQ(error, OK);

	List<PropertyInfo> properties;
	script->get_script_property_list(&properties);
	int index = 0;
	int alpha = -1, beta = -1, gamma = -1;
	for (const PropertyInfo &p : properties) {
		if (p.name == StringName("alpha")) { alpha = index; CHECK_EQ(p.type, Variant::INT); }
		if (p.name == StringName("beta")) { beta = index; CHECK_EQ(p.type, Variant::STRING); }
		if (p.name == StringName("gamma")) { gamma = index; CHECK_EQ(p.type, Variant::VECTOR2); }
		index++;
	}
	REQUIRE(alpha >= 0);
	REQUIRE(beta >= 0);
	REQUIRE(gamma >= 0);
	CHECK(alpha < beta);
	CHECK(beta < gamma);
}

TEST_CASE("[GDScriptScriptProperties] repeated enumeration preserves names, types and order") {
	GDScriptLanguage::get_singleton()->init();
	Ref<GDScript> script = memnew(GDScript);
	script->set_source_code("extends RefCounted\nvar a: int = 1\nvar b: float = 2.5\nvar c: String = \"test\"\n");
	ERR_PRINT_OFF;
	const Error error = script->reload();
	ERR_PRINT_ON;
	REQUIRE_EQ(error, OK);

	List<PropertyInfo> baseline;
	script->get_script_property_list(&baseline);
	REQUIRE(baseline.size() >= 3);
	for (int pass = 0; pass < 64; pass++) {
		List<PropertyInfo> current;
		script->get_script_property_list(&current);
		REQUIRE_EQ(current.size(), baseline.size());
		const List<PropertyInfo>::Element *lhs = baseline.front();
		const List<PropertyInfo>::Element *rhs = current.front();
		while (lhs && rhs) {
			CHECK_EQ(lhs->get().name, rhs->get().name);
			CHECK_EQ(lhs->get().type, rhs->get().type);
			lhs = lhs->next();
			rhs = rhs->next();
		}
	}
}

TEST_CASE("[Modules][GDScript] Loading keeps ResourceCache and GDScriptCache in sync") {
	GDScriptLanguage::get_singleton()->init();
	const String path = TestUtils::get_temp_path("gdscript_load_test.gd");

	{
		Ref<FileAccess> fa = FileAccess::open(path, FileAccess::ModeFlags::WRITE);
		fa->store_string("extends Node\n");
		fa->close();
	}

	CHECK(!ResourceCache::has(path));
	CHECK(!TestGDScriptCacheAccessor::has_shallow(path));
	CHECK(!TestGDScriptCacheAccessor::has_full(path));

	Ref<GDScript> loaded = ResourceLoader::load(path);

	CHECK(ResourceCache::has(path));
	CHECK(!TestGDScriptCacheAccessor::has_shallow(path));
	CHECK(TestGDScriptCacheAccessor::has_full(path));
}

TEST_CASE("[Modules][GDScript] Validate built-in API") {
	GDScriptLanguage *lang = GDScriptLanguage::get_singleton();

	// Validate methods.
	List<MethodInfo> builtin_methods;
	lang->get_public_functions(&builtin_methods);

	SUBCASE("[Modules][GDScript] Validate built-in methods") {
		for (const MethodInfo &mi : builtin_methods) {
			for (int64_t i = 0; i < mi.arguments.size(); ++i) {
				TEST_COND((mi.arguments[i].name.is_empty() || mi.arguments[i].name.begins_with("_unnamed_arg")),
						vformat("Unnamed argument in position %d of built-in method '%s'.", i, mi.name));
			}
		}
	}

	// Validate annotations.
	List<MethodInfo> builtin_annotations;
	lang->get_public_annotations(&builtin_annotations);

	SUBCASE("[Modules][GDScript] Validate built-in annotations") {
		for (const MethodInfo &ai : builtin_annotations) {
			for (int64_t i = 0; i < ai.arguments.size(); ++i) {
				TEST_COND((ai.arguments[i].name.is_empty() || ai.arguments[i].name.begins_with("_unnamed_arg")),
						vformat("Unnamed argument in position %d of built-in annotation '%s'.", i, ai.name));
			}
		}
	}
}

static void check_single_multiline_string_error(const String &p_string, int p_start_line, int p_start_column, int p_end_line, int p_end_column, const String &p_message) {
	const String source = String("var s = \"\"\"\n") + p_string + "\n\"\"\"\n";

	GDScriptParser parser;
	parser.parse(source, "", false);
	const List<GDScriptParser::ParserError> &errors = parser.get_errors();

	REQUIRE_MESSAGE(errors.size() == 1, vformat("Expected exactly one error, got %d.", errors.size()));

	const GDScriptParser::ParserError &error = errors.front()->get();

	CHECK(error.start_line == p_start_line);
	CHECK(error.start_column == p_start_column);
	CHECK(error.end_line == p_end_line);
	CHECK(error.end_column == p_end_column);
	CHECK(error.message == p_message);
}

// These can't be part of the regular parser tests because they cannot test the position information of errors.
TEST_CASE("[Modules][GDScript] Validate multi-line string error positions") {
	check_single_multiline_string_error(String::chr(0x200E), 2, 1, 2, 2, "Invisible text direction control character present in the string, escape it (\"\\u200e\") to avoid confusion.");
	check_single_multiline_string_error("\\Uzzzzzz", 2, 3, 2, 4, "Invalid hexadecimal digit in unicode escape sequence.");
	check_single_multiline_string_error("\\p", 2, 1, 2, 3, "Invalid escape in string.");
	check_single_multiline_string_error("abc\ndef\nghi\\p", 4, 4, 4, 6, "Invalid escape in string.");
	check_single_multiline_string_error("\\uD800\\uD800", 2, 11, 2, 13, "Invalid UTF-16 sequence in string, unpaired lead surrogate.");
	check_single_multiline_string_error("\\uDC00", 2, 5, 2, 7, "Invalid UTF-16 sequence in string, unpaired trail surrogate.");
	check_single_multiline_string_error("\\uD800\\u0041", 2, 5, 2, 7, "Invalid UTF-16 sequence in string, unpaired lead surrogate.");
	check_single_multiline_string_error("\\uD800\"abc", 2, 5, 2, 7, "Invalid UTF-16 sequence in string, unpaired lead surrogate");
	check_single_multiline_string_error("\\uD800x", 2, 5, 2, 7, "Invalid UTF-16 sequence in string, unpaired lead surrogate");
	check_single_multiline_string_error("\\uD800\\\n\\u0041", 2, 5, 2, 7, "Invalid UTF-16 sequence in string, unpaired lead surrogate.");
	check_single_multiline_string_error("\\uD800\\", 2, 5, 2, 7, "Invalid UTF-16 sequence in string, unpaired lead surrogate");
	check_single_multiline_string_error("\\uD800\\\nx", 2, 5, 2, 7, "Invalid UTF-16 sequence in string, unpaired lead surrogate");
}


TEST_CASE("[GDScriptSymbolFastPath] static and instance methods remain distinguishable") {
	GDScriptLanguage::get_singleton()->init();
	Ref<GDScript> script = memnew(GDScript);
	script->set_source_code("extends RefCounted\nstatic func fast_static() -> int:\n\treturn 42\nfunc normal_instance() -> int:\n\treturn 7\n");
	ERR_PRINT_OFF;
	const Error err = script->reload();
	ERR_PRINT_ON;
	REQUIRE_EQ(err, OK);
	CHECK(script->has_method(SNAME("fast_static")));
	CHECK(script->has_static_method(SNAME("fast_static")));
	CHECK(script->has_method(SNAME("normal_instance")));
	CHECK_FALSE(script->has_static_method(SNAME("normal_instance")));
	CHECK_FALSE(script->has_static_method(SNAME("nonexistent_method")));
}

TEST_CASE("[GDScriptSymbolFastPath] named constants override indexed globals") {
	GDScriptLanguage *lang = GDScriptLanguage::get_singleton();
	REQUIRE(lang != nullptr);
	lang->init();
	const StringName name = SNAME("PI");
	const Variant original = lang->get_any_global_constant(name);
	CHECK_EQ(original, Variant(Math::PI));
	lang->add_named_global_constant(name, 987.0);
	CHECK_EQ(lang->get_any_global_constant(name), Variant(987.0));
	lang->remove_named_global_constant(name);
	CHECK_EQ(lang->get_any_global_constant(name), original);
}

TEST_CASE("[GDScriptSymbolFastPath] repeated reads preserve the stable indexed constant") {
	GDScriptLanguage *lang = GDScriptLanguage::get_singleton();
	REQUIRE(lang != nullptr);
	lang->init();
	const StringName name = SNAME("TAU");
	const Variant expected = lang->get_any_global_constant(name);
	for (int i = 0; i < 256; ++i) {
		CHECK_EQ(lang->get_any_global_constant(name), expected);
	}
}

TEST_CASE("[GDScriptSymbolFastPath] missing constant returns Nil without adding it") {
	GDScriptLanguage *lang = GDScriptLanguage::get_singleton();
	REQUIRE(lang != nullptr);
	lang->init();
	const StringName missing = SNAME("__cgame_symbol_fastpath_missing_constant_20261119__");
	CHECK_FALSE(lang->has_any_global_constant(missing));
	ERR_PRINT_OFF;
	const Variant v = lang->get_any_global_constant(missing);
	ERR_PRINT_ON;
	CHECK_EQ(v.get_type(), Variant::NIL);
	CHECK_FALSE(lang->has_any_global_constant(missing));
}


#ifdef TOOLS_ENABLED
TEST_CASE("[GDScriptNamedGlobalFastPath] script reads updated named globals through the VM") {
	GDScriptLanguage *lang = GDScriptLanguage::get_singleton();
	REQUIRE(lang != nullptr);
	lang->init();

	const StringName global_name = SNAME("CgamePerfNamedGlobal");
	CHECK_FALSE(lang->get_named_globals_map().has(global_name));
	lang->add_named_global_constant(global_name, 23);

	Ref<GDScript> script = memnew(GDScript);
	script->set_source_code(R"GD(extends RefCounted
func read_global():
	return CgamePerfNamedGlobal
)GD");

	ERR_PRINT_OFF;
	const Error err = script->reload();
	ERR_PRINT_ON;
	CHECK_EQ(err, OK);

	if (err == OK) {
		Ref<RefCounted> instance = memnew(RefCounted);
		instance->set_script(script);
		for (int i = 0; i < 80; i++) {
			CHECK_EQ(instance->call("read_global"), Variant(23));
		}

		// A codegen-time constant would not see this update. This verifies
		// that the new single-probe STORE_NAMED_GLOBAL reads the current value.
		lang->add_named_global_constant(global_name, 47);
		for (int i = 0; i < 80; i++) {
			CHECK_EQ(instance->call("read_global"), Variant(47));
		}
	}
	lang->remove_named_global_constant(global_name);
	CHECK(lang->get_named_globals_map().getptr(global_name) == nullptr);
}
#endif // TOOLS_ENABLED

} // namespace GDScriptTests
