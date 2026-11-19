/**************************************************************************/
/*  test_delta_encoding.cpp                                               */
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

TEST_FORCE_LINK(test_delta_encoding)

#include "core/io/delta_encoding.h"
#include "core/templates/vector.h"

#include <cstring>
#include <utility>

namespace TestDeltaEncoding {

TEST_CASE("[DeltaEncoding] Chained patches reuse buffers and preserve contents") {
	Vector<uint8_t> current;
	CHECK(current.resize(65536) == OK);
	for (int i = 0; i < current.size(); i++) {
		current.ptrw()[i] = uint8_t(i * 17 + 41);
	}

	Vector<uint8_t> scratch;
	const uint8_t *first_destination = nullptr;
	const int sizes[] = { 65536, 65536, 65536, 131072, 98304, 32768, 65536 };
	for (int patch_idx = 0; patch_idx < 7; patch_idx++) {
		Vector<uint8_t> target;
		// The payload can grow across patches: initialize newly added bytes.
		CHECK(target.resize_initialized(sizes[patch_idx]) == OK);
		const int common = MIN(current.size(), target.size());
		if (common > 0) {
			memcpy(target.ptrw(), current.ptr(), common);
		}
		for (int i = 0; i < target.size(); i += 71) {
			target.ptrw()[i] = uint8_t(patch_idx * 23 + i / 71);
		}

		Vector<uint8_t> compressed_delta;
		CHECK(DeltaEncoding::encode_delta(current.span(), target.span(), compressed_delta, 1) == OK);
		CHECK(DeltaEncoding::decode_delta(current.span(), compressed_delta.span(), scratch) == OK);
		CHECK(scratch == target);
		if (patch_idx == 0) {
			first_destination = scratch.ptr();
		}
		if (patch_idx == 2) {
			// The destination from patch 1 is reused on patch 3, rather
			// than allocating a third full-sized decompression buffer.
			CHECK(scratch.ptr() == first_destination);
		}
		if (patch_idx == 6) {
			current = std::move(scratch);
		} else {
			std::swap(current, scratch);
		}
		CHECK(current == target);
	}
	CHECK(current.size() == 65536);
}

TEST_CASE("[DeltaEncoding] Independent patches match different prefixes") {
	Vector<uint8_t> source;
	Vector<uint8_t> changed;
	CHECK(source.resize(8192) == OK);
	CHECK(changed.resize(8192) == OK);
	for (int i = 0; i < 8192; i++) {
		source.ptrw()[i] = uint8_t(i);
		changed.ptrw()[i] = uint8_t(i ^ (i >> 4));
	}
	Vector<uint8_t> compressed;
	Vector<uint8_t> decoded;
	CHECK(DeltaEncoding::encode_delta(source.span(), changed.span(), compressed, 1) == OK);
	CHECK(DeltaEncoding::decode_delta(source.span(), compressed.span(), decoded) == OK);
	CHECK(decoded == changed);
}

} // namespace TestDeltaEncoding
