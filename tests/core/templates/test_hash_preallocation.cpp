/**************************************************************************/
/*  test_hash_preallocation.cpp                                           */
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

TEST_FORCE_LINK(test_hash_preallocation)

#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/variant/dictionary.h"

namespace TestHashPreallocation {

TEST_CASE("[HashPreallocation] Large reserved integer hash maps retain all values") {
	HashMap<int, int> map;
	map.reserve(4096);
	for (int i = 0; i < 4096; i++) {
		map.insert(i, i * 3);
	}
	REQUIRE_EQ(map.size(), 4096);
	for (int i = 0; i < 4096; i++) {
		CHECK(map.has(i));
		CHECK(map[i] == i * 3);
	}
}

TEST_CASE("[HashPreallocation] Reserving a populated map does not drop entries") {
	HashMap<int, String> map;
	for (int i = 0; i < 128; i++) {
		map.insert(i, itos(i));
	}
	map.reserve(4096);
	REQUIRE_EQ(map.size(), 128);
	for (int i = 0; i < 128; i++) {
		CHECK(map[i] == itos(i));
	}
	for (int i = 0; i < 64; i++) {
		map.erase(i);
	}
	CHECK(map.size() == 64);
	for (int i = 64; i < 128; i++) {
		CHECK(map.has(i));
	}
}

TEST_CASE("[HashPreallocation] Reserved HashSet keeps membership and uniqueness") {
	HashSet<int> set;
	set.reserve(2048);
	for (int i = 0; i < 2048; i++) {
		set.insert(i);
		set.insert(i);
	}
	REQUIRE_EQ(set.size(), 2048);
	for (int i = 0; i < 2048; i++) {
		CHECK(set.has(i));
	}
	for (int i = 0; i < 2048; i += 2) {
		set.erase(i);
	}
	CHECK(set.size() == 1024);
	for (int i = 0; i < 2048; i++) {
		CHECK(set.has(i) == (i % 2 == 1));
	}
}

TEST_CASE("[HashPreallocation] Reserved string HashSet preserves lookup") {
	HashSet<String> set(512);
	for (int i = 0; i < 512; i++) {
		set.insert(itos(i));
	}
	REQUIRE_EQ(set.size(), 512);
	for (int i = 0; i < 512; i++) {
		CHECK(set.has(itos(i)));
	}
}

TEST_CASE("[HashPreallocation] Dictionary reserved before decode preserves insertion order") {
	Dictionary dict;
	dict.reserve(512);
	for (int i = 0; i < 512; i++) {
		dict[i] = i * 7;
	}
	REQUIRE_EQ(dict.size(), 512);
	for (int i = 0; i < 512; i++) {
		CHECK_EQ(dict.get_key_at_index(i), Variant(i));
		CHECK_EQ(dict[i], Variant(i * 7));
	}
}

TEST_CASE("[HashPreallocation] Dictionary reserve on populated entries keeps data") {
	Dictionary dict;
	dict["one"] = 1;
	dict["two"] = 2;
	dict.reserve(512);
	REQUIRE_EQ(dict.size(), 2);
	CHECK_EQ(dict["one"], Variant(1));
	CHECK_EQ(dict["two"], Variant(2));
	dict["three"] = 3;
	CHECK_EQ(dict.size(), 3);
	CHECK_EQ(dict["three"], Variant(3));
}

TEST_CASE("[HashPreallocation] Empty Dictionary and map accept empty reserve") {
	Dictionary dict;
	dict.reserve(0);
	CHECK(dict.is_empty());
	HashSet<int> set;
	set.reserve(0);
	CHECK(set.is_empty());
	HashMap<int, int> map;
	map.reserve(0);
	CHECK(map.is_empty());
}

} // namespace TestHashPreallocation
