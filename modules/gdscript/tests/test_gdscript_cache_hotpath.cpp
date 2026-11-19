/**************************************************************************/
/*  test_gdscript_cache_hotpath.cpp                                       */
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
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF   */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

#include "../gdscript.h"
#include "../gdscript_cache.h"

#include "core/io/file_access.h"
#include "tests/test_utils.h"

namespace TestGDScriptCacheHotpath {

static String create_script(const String &p_name) {
	const String path = TestUtils::get_temp_path(p_name);
	Ref<FileAccess> file = FileAccess::open(path, FileAccess::WRITE);
	REQUIRE(file.is_valid());
	file->store_string("extends RefCounted\nvar count: int = 123\n");
	file->close();
	return path;
}

TEST_CASE("[GDScriptCacheHotpath] Parser lookups reuse the same cached instance") {
	GDScriptLanguage::get_singleton()->init();
	const String path = create_script("gdscript_cache_hash_parser.gd");

	Error error = OK;
	const Ref<GDScriptParserRef> first = GDScriptCache::get_parser(path, GDScriptParserRef::PARSED, error);
	REQUIRE(error == OK);
	REQUIRE(first.is_valid());
	CHECK(GDScriptCache::has_parser(path));
	for (int i = 0; i < 100; i++) {
		error = OK;
		const Ref<GDScriptParserRef> again = GDScriptCache::get_parser(path, GDScriptParserRef::PARSED, error);
		CHECK(error == OK);
		CHECK(again == first);
	}

	GDScriptCache::remove_script(path);
	CHECK_FALSE(GDScriptCache::has_parser(path));
	CHECK(GDScriptCache::get_cached_script(path).is_null());
}

TEST_CASE("[GDScriptCacheHotpath] Shallow script cache and move preserve identity") {
	GDScriptLanguage::get_singleton()->init();
	const String from = create_script("gdscript_cache_hash_shallow.gd");
	const String to = TestUtils::get_temp_path("gdscript_cache_hash_renamed.gd");

	Error error = OK;
	const Ref<GDScript> first = GDScriptCache::get_shallow_script(from, error);
	REQUIRE(error == OK);
	REQUIRE(first.is_valid());
	CHECK(GDScriptCache::get_cached_script(from) == first);
	for (int i = 0; i < 100; i++) {
		error = OK;
		const Ref<GDScript> again = GDScriptCache::get_shallow_script(from, error);
		CHECK(error == OK);
		CHECK(again == first);
	}

	GDScriptCache::move_script(from, to);
	CHECK(GDScriptCache::get_cached_script(from).is_null());
	CHECK(GDScriptCache::get_cached_script(to) == first);
	GDScriptCache::remove_script(to);
	CHECK(GDScriptCache::get_cached_script(to).is_null());
}

TEST_CASE("[GDScriptCacheHotpath] Fully compiled script stays cached") {
	GDScriptLanguage::get_singleton()->init();
	const String path = create_script("gdscript_cache_hash_full.gd");

	Error error = OK;
	const Ref<GDScript> first = GDScriptCache::get_full_script(path, error);
	REQUIRE(error == OK);
	REQUIRE(first.is_valid());
	CHECK(GDScriptCache::get_cached_script(path) == first);
	for (int i = 0; i < 100; i++) {
		error = OK;
		const Ref<GDScript> again = GDScriptCache::get_full_script(path, error);
		CHECK(error == OK);
		CHECK(again == first);
	}

	GDScriptCache::remove_script(path);
	CHECK(GDScriptCache::get_cached_script(path).is_null());
}

} // namespace TestGDScriptCacheHotpath
