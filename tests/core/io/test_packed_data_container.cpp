/**************************************************************************/
/*  test_packed_data_container.cpp                                        */
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

TEST_FORCE_LINK(test_packed_data_container)

#include "core/io/packed_data_container.h"

namespace TestPackedDataContainer {

TEST_CASE("[PackedDataContainer] Large arrays and duplicate strings round-trip") {
	Ref<PackedDataContainer> packed;
	packed.instantiate();

	const String repeated = "shared-string-value-0123456789";
	Array input;
	for (int i = 0; i < 512; i++) {
		input.push_back(repeated);
	}
	input.push_back(123456789);
	CHECK(packed->pack(input) == OK);
	CHECK(packed->size() == 513);

	bool valid = false;
	for (int i = 0; i < 512; i++) {
		CHECK(packed->getvar(i, &valid) == Variant(repeated));
		CHECK(valid);
	}
	CHECK(packed->getvar(512, &valid) == Variant(123456789));
	CHECK(valid);
}

TEST_CASE("[PackedDataContainer] Large binary data and repeated packs") {
	Ref<PackedDataContainer> packed;
	packed.instantiate();

	PackedByteArray blob;
	blob.resize(256 * 1024);
	uint8_t *bytes = blob.ptrw();
	for (int i = 0; i < blob.size(); i++) {
		bytes[i] = uint8_t(i * 37 + 11);
	}
	Array first;
	first.push_back(blob);
	first.push_back(String("trailer"));
	CHECK(packed->pack(first) == OK);
	CHECK(packed->size() == 2);

	bool valid = false;
	const Variant decoded_blob = packed->getvar(0, &valid);
	CHECK(valid);
	CHECK(decoded_blob == Variant(blob));
	CHECK(packed->getvar(1, &valid) == Variant(String("trailer")));
	CHECK(valid);

	Array replacement;
	replacement.push_back(42);
	CHECK(packed->pack(replacement) == OK);
	CHECK(packed->size() == 1);
	CHECK(packed->getvar(0, &valid) == Variant(42));
	CHECK(valid);
}

TEST_CASE("[PackedDataContainer] Large dictionary and hash-based lookups") {
	Ref<PackedDataContainer> packed;
	packed.instantiate();

	Dictionary source;
	for (int i = 0; i < 256; i++) {
		source[String("name_") + itos(i)] = i * 13;
	}
	source[-73] = "negative-integer-key";
	CHECK(packed->pack(source) == OK);
	CHECK(packed->size() == 257);

	bool valid = false;
	for (int i = 255; i >= 0; i--) {
		CHECK(packed->getvar(String("name_") + itos(i), &valid) == Variant(i * 13));
		CHECK(valid);
	}
	CHECK(packed->getvar(-73, &valid) == Variant(String("negative-integer-key")));
	CHECK(valid);
	CHECK(packed->getvar(String("definitely-missing-key-987654"), &valid) == Variant());
	CHECK_FALSE(valid);

	Dictionary smaller;
	smaller["single"] = "new-value";
	CHECK(packed->pack(smaller) == OK);
	CHECK(packed->size() == 1);
	CHECK(packed->getvar(String("single"), &valid) == Variant(String("new-value")));
	CHECK(valid);
}

} // namespace TestPackedDataContainer
