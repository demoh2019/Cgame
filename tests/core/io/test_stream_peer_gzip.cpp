/**************************************************************************/
/*  test_stream_peer_gzip.cpp                                             */
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

TEST_FORCE_LINK(test_stream_peer_gzip)

#include "core/io/stream_peer_gzip.h"

namespace TestStreamPeerGZIP {

const String hello = "Hello World!!!";

TEST_CASE("[StreamPeerGZIP] Initialization") {
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();
	CHECK_EQ(spgz->get_available_bytes(), 0);
}

TEST_CASE("[StreamPeerGZIP] Compress/Decompress") {
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();

	bool is_deflate = false;

	SUBCASE("GZIP") {
		is_deflate = false;
	}

	SUBCASE("DEFLATE") {
		is_deflate = true;
	}

	CHECK_EQ(spgz->start_compression(is_deflate), Error::OK);
	CHECK_EQ(spgz->put_data(hello.to_ascii_buffer().ptr(), hello.to_ascii_buffer().size()), Error::OK);
	CHECK_EQ(spgz->finish(), Error::OK);

	Vector<uint8_t> hello_compressed;
	int hello_compressed_size = spgz->get_available_bytes();
	hello_compressed.resize(hello_compressed_size);
	CHECK_EQ(spgz->get_data(hello_compressed.ptrw(), hello_compressed_size), Error::OK);

	spgz->clear();

	CHECK_EQ(spgz->start_decompression(is_deflate), Error::OK);
	CHECK_EQ(spgz->put_data(hello_compressed.ptr(), hello_compressed.size()), Error::OK);

	Vector<uint8_t> hello_decompressed;
	int hello_decompressed_size = spgz->get_available_bytes();
	hello_decompressed.resize(hello_decompressed_size);
	CHECK_EQ(spgz->get_data(hello_decompressed.ptrw(), hello_decompressed_size), Error::OK);
	CHECK_EQ(hello_decompressed, hello.to_ascii_buffer());
}

TEST_CASE("[StreamPeerGZIP] Compress/Decompress big chunks of data") { // GH-97201
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();
	CHECK_EQ(spgz->start_compression(false), Error::OK);

	Vector<uint8_t> big_data;
	big_data.resize(2500);
	// Filling it with random data because the issue is related to the size of the data when it's compress.
	// Random data results in bigger compressed data size.
	for (int i = 0; i < big_data.size(); i++) {
		big_data.write[i] = Math::random(48, 122);
	}
	CHECK_EQ(spgz->put_data(big_data.ptr(), big_data.size()), Error::OK);
	CHECK_EQ(spgz->finish(), Error::OK);

	Vector<uint8_t> big_data_compressed;
	int big_data_compressed_size = spgz->get_available_bytes();
	big_data_compressed.resize(big_data_compressed_size);
	CHECK_EQ(spgz->get_data(big_data_compressed.ptrw(), big_data_compressed_size), Error::OK);

	spgz->clear();

	CHECK_EQ(spgz->start_decompression(false), Error::OK);
	CHECK_EQ(spgz->put_data(big_data_compressed.ptr(), big_data_compressed.size()), Error::OK);

	Vector<uint8_t> big_data_decompressed;
	int big_data_decompressed_size = spgz->get_available_bytes();
	big_data_decompressed.resize(big_data_decompressed_size);
	CHECK_EQ(spgz->get_data(big_data_decompressed.ptrw(), big_data_decompressed_size), Error::OK);
	CHECK_EQ(big_data_decompressed, big_data);
}

TEST_CASE("[StreamPeerGZIP] Can't start twice") {
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();
	CHECK_EQ(spgz->start_compression(false), Error::OK);

	ERR_PRINT_OFF;
	CHECK_EQ(spgz->start_compression(false), Error::ERR_ALREADY_IN_USE);
	CHECK_EQ(spgz->start_decompression(false), Error::ERR_ALREADY_IN_USE);
	ERR_PRINT_ON;
}

TEST_CASE("[StreamPeerGZIP] Can't start with a buffer size equal or less than zero") {
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();

	ERR_PRINT_OFF;
	CHECK_EQ(spgz->start_compression(false, 0), Error::ERR_INVALID_PARAMETER);
	CHECK_EQ(spgz->start_compression(false, -1), Error::ERR_INVALID_PARAMETER);
	CHECK_EQ(spgz->start_decompression(false, 0), Error::ERR_INVALID_PARAMETER);
	CHECK_EQ(spgz->start_decompression(false, -1), Error::ERR_INVALID_PARAMETER);
	ERR_PRINT_ON;
}

TEST_CASE("[StreamPeerGZIP] Can't put/get data with a buffer size less than zero") {
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();
	CHECK_EQ(spgz->start_compression(false), Error::OK);

	ERR_PRINT_OFF;
	CHECK_EQ(spgz->put_data(hello.to_ascii_buffer().ptr(), -1), Error::ERR_INVALID_PARAMETER);

	Vector<uint8_t> hello_compressed;
	hello_compressed.resize(5);
	CHECK_EQ(spgz->get_data(hello_compressed.ptrw(), -1), Error::ERR_INVALID_PARAMETER);
	ERR_PRINT_ON;
}

TEST_CASE("[StreamPeerGZIP] Needs to be started before use") {
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();

	ERR_PRINT_OFF;
	CHECK_EQ(spgz->put_data(hello.to_ascii_buffer().ptr(), hello.to_ascii_buffer().size()), Error::ERR_UNCONFIGURED);
	ERR_PRINT_ON;
}

TEST_CASE("[StreamPeerGZIP] Can't be finished after clear or if it's decompressing") {
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();

	CHECK_EQ(spgz->start_compression(false), Error::OK);
	spgz->clear();
	ERR_PRINT_OFF;
	CHECK_EQ(spgz->finish(), Error::ERR_UNAVAILABLE);
	ERR_PRINT_ON;

	spgz->clear();
	CHECK_EQ(spgz->start_decompression(false), Error::OK);
	ERR_PRINT_OFF;
	CHECK_EQ(spgz->finish(), Error::ERR_UNAVAILABLE);
	ERR_PRINT_ON;
}

TEST_CASE("[StreamPeerGZIP] Fails to get if nothing was compress/decompress") {
	Ref<StreamPeerGZIP> spgz;
	spgz.instantiate();

	SUBCASE("Compression") {
		CHECK_EQ(spgz->start_compression(false), Error::OK);
	}

	SUBCASE("Decompression") {
		CHECK_EQ(spgz->start_decompression(false), Error::OK);
	}

	ERR_PRINT_OFF;
	Vector<uint8_t> hello_compressed;
	hello_compressed.resize(5);
	CHECK_EQ(spgz->get_data(hello_compressed.ptrw(), hello_compressed.size()), Error::ERR_UNAVAILABLE);
	ERR_PRINT_ON;
}


TEST_CASE("[StreamPeerGZIP] Megabyte input streams through bounded temporary storage") {
	bool use_deflate = false;
	int ring_size = 65535;

	SUBCASE("GZIP default ring") {
		use_deflate = false;
		ring_size = 65535;
	}
	SUBCASE("DEFLATE smaller ring") {
		use_deflate = true;
		ring_size = 16383;
	}

	// The input is much larger than the ring buffer, but compresses to a
	// small stream. The temporary zlib buffer must not scale with input size.
	Vector<uint8_t> input;
	REQUIRE(input.resize(4 * 1024 * 1024) == OK);
	uint8_t *const input_bytes = input.ptrw();
	for (int i = 0; i < input.size(); i++) {
		input_bytes[i] = uint8_t((i * 17 + (i / 4096)) & 15);
	}

	Ref<StreamPeerGZIP> compressor;
	compressor.instantiate();
	REQUIRE(compressor->start_compression(use_deflate, ring_size) == OK);
	REQUIRE(compressor->put_data(input.ptr(), input.size()) == OK);
	REQUIRE(compressor->finish() == OK);
	const int compressed_len = compressor->get_available_bytes();
	REQUIRE(compressed_len > 0);
	CHECK(compressed_len < ring_size);

	Vector<uint8_t> encoded;
	REQUIRE(encoded.resize(compressed_len) == OK);
	REQUIRE(compressor->get_data(encoded.ptrw(), encoded.size()) == OK);

	Ref<StreamPeerGZIP> decompressor;
	decompressor.instantiate();
	REQUIRE(decompressor->start_decompression(use_deflate, ring_size) == OK);
	Vector<uint8_t> decoded;
	REQUIRE(decoded.resize(input.size()) == OK);
	uint8_t *const decoded_bytes = decoded.ptrw();

	int input_pos = 0;
	int output_pos = 0;
	int iterations = 0;
	while ((input_pos < encoded.size() || decompressor->get_available_bytes() > 0) && iterations++ < 1024) {
		int sent = 0;
		if (input_pos < encoded.size()) {
			REQUIRE(decompressor->put_partial_data(encoded.ptr() + input_pos, encoded.size() - input_pos, sent) == OK);
			input_pos += sent;
		}

		int received = 0;
		if (output_pos < decoded.size()) {
			const int to_read = MIN(32768, decoded.size() - output_pos);
			REQUIRE(decompressor->get_partial_data(decoded_bytes + output_pos, to_read, received) == OK);
			output_pos += received;
		}
		if (sent == 0 && received == 0) {
			break;
		}
	}
	CHECK(iterations < 1024);
	CHECK(input_pos == encoded.size());
	CHECK(output_pos == input.size());
	CHECK(decoded == input);
}


TEST_CASE("[StreamPeerGZIP] Incompressible data finishes in bounded output chunks") {
	// zlib can buffer almost the entire incompressible input until Z_FINISH.
	// A single 1024-byte finish call is therefore insufficient.
	for (bool deflate_mode : { false, true }) {
		for (int count : { 0, 1, 511, 1024, 1536, 2048 }) {
			Vector<uint8_t> payload;
			REQUIRE(payload.resize_uninitialized(count) == OK);
			uint8_t *bytes = payload.ptrw();
			uint32_t seed = uint32_t(0xa5f7d34b + count);
			for (int i = 0; i < count; ++i) {
				seed ^= seed << 13;
				seed ^= seed >> 17;
				seed ^= seed << 5;
				bytes[i] = uint8_t(seed);
			}

			Ref<StreamPeerGZIP> compressor;
			compressor.instantiate();
			REQUIRE(compressor->start_compression(deflate_mode, 32767) == OK);
			if (count > 0) {
				REQUIRE(compressor->put_data(payload.ptr(), payload.size()) == OK);
			}
			REQUIRE(compressor->finish() == OK);
			const int compressed_len = compressor->get_available_bytes();
			REQUIRE(compressed_len > 0);
			Vector<uint8_t> encoded;
			REQUIRE(encoded.resize_uninitialized(compressed_len) == OK);
			REQUIRE(compressor->get_data(encoded.ptrw(), compressed_len) == OK);

			Ref<StreamPeerGZIP> decoder;
			decoder.instantiate();
			REQUIRE(decoder->start_decompression(deflate_mode, 32767) == OK);
			REQUIRE(decoder->put_data(encoded.ptr(), encoded.size()) == OK);
			CHECK_EQ(decoder->get_available_bytes(), count);
			Vector<uint8_t> restored;
			REQUIRE(restored.resize_uninitialized(count) == OK);
			if (count > 0) {
				REQUIRE(decoder->get_data(restored.ptrw(), count) == OK);
			}
			CHECK(restored == payload);
		}
	}
}

} // namespace TestStreamPeerGZIP
