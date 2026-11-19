/**************************************************************************/
/*  test_compression.cpp                                                  */
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
/* permit persons to whom the Software and associated documentation files */
/* are furnished to do so, subject to the following conditions:           */
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

TEST_FORCE_LINK(test_compression)

#include "core/io/compression.h"

#include <zlib.h>

namespace TestCompression {

struct ChunkSettingGuard {
	int saved = Compression::gzip_chunk;
	~ChunkSettingGuard() {
		Compression::gzip_chunk = saved;
	}
};

TEST_CASE("[Compression][Performance] Dynamic gzip and deflate decode exact streams") {
	ChunkSettingGuard guard;
	Compression::gzip_chunk = 257;
	const int sizes[] = { 0, 1, 15, 256, 257, 258, 16383, 16384, 16385, 65536, 131072 };
	for (Compression::Mode mode : { Compression::MODE_GZIP, Compression::MODE_DEFLATE }) {
		for (int size : sizes) {
			Vector<uint8_t> input;
			REQUIRE(input.resize_uninitialized(size) == OK);
			for (int i = 0; i < size; i++) {
				input.ptrw()[i] = uint8_t(((i * 31) ^ (i / 37)) & 255);
			}
			const int64_t limit = Compression::get_max_compressed_buffer_size(size, mode);
			REQUIRE(limit > 0);
			Vector<uint8_t> encoded;
			REQUIRE(encoded.resize_uninitialized(limit) == OK);
			const int64_t written = Compression::compress(encoded.ptrw(), input.ptr(), size, mode);
			REQUIRE(written > 0);
			REQUIRE(written <= limit);

			Vector<uint8_t> decoded;
			CHECK(Compression::decompress_dynamic(&decoded, size, encoded.ptr(), written, mode) == Z_OK);
			CHECK(decoded == input);
			CHECK(decoded.size() == size);

			if (size > 0) {
				// The one-byte over-limit sentinel distinguishes valid
				// exact-capacity streams from decompression bombs.
				ERR_PRINT_OFF;
				CHECK(Compression::decompress_dynamic(&decoded, size - 1, encoded.ptr(), written, mode) == Z_BUF_ERROR);
				ERR_PRINT_ON;
				CHECK(decoded.is_empty());
			}
			ERR_PRINT_OFF;
			CHECK(Compression::decompress_dynamic(&decoded, -1, encoded.ptr(), written - 1, mode) != Z_OK);
			ERR_PRINT_ON;
			CHECK(decoded.is_empty());
		}
	}
}

#ifdef BROTLI_ENABLED
TEST_CASE("[Compression][Performance] Brotli dynamic decompression tracks partial output correctly") {
	// Deterministic Brotli stream encoding 131072 consecutive 'A' bytes.
	const uint8_t compressed[] = {
		0x5b, 0xff, 0xff, 0x01, 0x40, 0x22, 0x28,
		0x1e, 0x0b, 0x24, 0xf7, 0x3e, 0x00,
	};
	ChunkSettingGuard guard;
	Compression::gzip_chunk = 113;
	Vector<uint8_t> decoded;
	REQUIRE(Compression::decompress_dynamic(&decoded, 131072, compressed, sizeof(compressed), Compression::MODE_BROTLI) == Z_OK);
	REQUIRE(decoded.size() == 131072);
	for (int i = 0; i < decoded.size(); i++) {
		CHECK(decoded[i] == uint8_t('A'));
	}
	ERR_PRINT_OFF;
	CHECK(Compression::decompress_dynamic(&decoded, 131071, compressed, sizeof(compressed), Compression::MODE_BROTLI) == Z_BUF_ERROR);
	ERR_PRINT_ON;
	CHECK(decoded.is_empty());
	ERR_PRINT_OFF;
	CHECK(Compression::decompress_dynamic(&decoded, -1, compressed, sizeof(compressed) - 1, Compression::MODE_BROTLI) != Z_OK);
	ERR_PRINT_ON;
	CHECK(decoded.is_empty());
}
#endif

} // namespace TestCompression
