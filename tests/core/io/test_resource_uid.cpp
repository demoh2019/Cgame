/**************************************************************************/
/*  test_resource_uid.cpp                                                 */
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

TEST_FORCE_LINK(test_resource_uid)

#include "core/io/resource_uid.h"
#include "core/io/stream_peer.h"

namespace TestResourceUID {

TEST_CASE("[ResourceUID] Must encode/decode maximum/minimum UID correctly") {
	CHECK_MESSAGE(ResourceUID::get_singleton()->id_to_text(0x7fffffffffffffff) == "uid://d4n4ub6itg400", "Maximum UID must encode correctly.");
	CHECK_MESSAGE(ResourceUID::get_singleton()->text_to_id("uid://d4n4ub6itg400") == 0x7fffffffffffffff, "Maximum UID must decode correctly.");

	CHECK_MESSAGE(ResourceUID::get_singleton()->id_to_text(0) == "uid://a", "Minimum UID must encode correctly.");
	CHECK_MESSAGE(ResourceUID::get_singleton()->text_to_id("uid://a") == 0, "Minimum UID must decode correctly.");
}

TEST_CASE("[ResourceUID] Must encode and decode invalid UIDs correctly") {
	ResourceUID *rid = ResourceUID::get_singleton();
	CHECK_MESSAGE(rid->id_to_text(-1) == "uid://<invalid>", "Invalid UID -1 must encode correctly.");
	CHECK_MESSAGE(rid->text_to_id("uid://<invalid>") == -1, "Invalid UID -1 must decode correctly.");

	CHECK_MESSAGE(rid->id_to_text(-2) == rid->id_to_text(-1), "Invalid UID -2 must encode to the same as -1.");

	CHECK_MESSAGE(rid->text_to_id("dm3rdgs30kfci") == -1, "UID without scheme must decode correctly.");
}

TEST_CASE("[ResourceUID] Must encode and decode various UIDs correctly") {
	ResourceUID *rid = ResourceUID::get_singleton();
	CHECK_MESSAGE(rid->id_to_text(1) == "uid://b", "UID 1 must encode correctly.");
	CHECK_MESSAGE(rid->text_to_id("uid://b") == 1, "UID 1 must decode correctly.");

	CHECK_MESSAGE(rid->id_to_text(8060368642360689600) == "uid://dm3rdgs30kfci", "A normal UID must encode correctly.");
	CHECK_MESSAGE(rid->text_to_id("uid://dm3rdgs30kfci") == 8060368642360689600, "A normal UID must decode correctly.");
}

TEST_CASE("[ResourceUID] Binary cache serialization preserves StreamPeerBuffer format") {
	Vector<Pair<ResourceUID::ID, String>> entries;
	entries.push_back(Pair<ResourceUID::ID, String>(0, ""));
	entries.push_back(Pair<ResourceUID::ID, String>(1, "res://levels/scene.tscn"));
	entries.push_back(Pair<ResourceUID::ID, String>(0x7fffffffffffffff, "res://assets/текстуры/файл.png"));
	entries.push_back(Pair<ResourceUID::ID, String>(-1, "res://negative-id.tres"));

	for (int i = 0; i < 1024; i++) {
		entries.push_back(Pair<ResourceUID::ID, String>(i + 1234, "res://long_folder_name/asset_" + itos(i) + ".tres"));
	}

	Ref<StreamPeerBuffer> reference;
	reference.instantiate();
	reference->put_u32(entries.size());
	for (const Pair<ResourceUID::ID, String> &entry : entries) {
		reference->put_u64(uint64_t(entry.first));
		CharString path = entry.second.utf8();
		reference->put_u32(path.length());
		reference->put_data((const uint8_t *)path.ptr(), path.length());
	}

	const Vector<uint8_t> encoded = ResourceUID::encode_binary_cache(entries);
	const Vector<uint8_t> expected = reference->get_data_array();
	REQUIRE(encoded.size() == expected.size());
	for (int i = 0; i < encoded.size(); i++) {
		CHECK(encoded[i] == expected[i]);
	}

	Vector<Pair<ResourceUID::ID, String>> empty;
	const Vector<uint8_t> empty_bytes = ResourceUID::encode_binary_cache(empty);
	CHECK(empty_bytes.size() == 4);
	for (int i = 0; i < empty_bytes.size(); i++) {
		CHECK(empty_bytes[i] == 0);
	}
}

} // namespace TestResourceUID
