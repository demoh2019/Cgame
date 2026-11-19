/**************************************************************************/
/*  test_packet_peer.cpp                                                  */
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

TEST_FORCE_LINK(test_packet_peer)

#include "core/io/packet_peer.h"

namespace TestPacketPeer {

TEST_CASE("[PacketPeer][PacketPeerStream] Encode buffer max size") {
	Ref<PacketPeerStream> pps;
	pps.instantiate();

	SUBCASE("Default value") {
		CHECK_EQ(pps->get_encode_buffer_max_size(), 8 * 1024 * 1024);
	}

	SUBCASE("Max encode buffer must be at least 1024 bytes") {
		ERR_PRINT_OFF;
		pps->set_encode_buffer_max_size(42);
		ERR_PRINT_ON;

		CHECK_EQ(pps->get_encode_buffer_max_size(), 8 * 1024 * 1024);
	}

	SUBCASE("Max encode buffer cannot exceed 256 MiB") {
		ERR_PRINT_OFF;
		pps->set_encode_buffer_max_size((256 * 1024 * 1024) + 42);
		ERR_PRINT_ON;

		CHECK_EQ(pps->get_encode_buffer_max_size(), 8 * 1024 * 1024);
	}

	SUBCASE("Should be next power of two") {
		pps->set_encode_buffer_max_size(2000);

		CHECK_EQ(pps->get_encode_buffer_max_size(), 2048);
	}
}

TEST_CASE("[PacketPeer][PacketPeerStream] Read a variant from peer") {
	String godot_rules = "Godot Rules!!!";

	Ref<StreamPeerBuffer> spb;
	spb.instantiate();
	spb->put_var(godot_rules);
	spb->seek(0);

	Ref<PacketPeerStream> pps;
	pps.instantiate();
	pps->set_stream_peer(spb);

	Variant value;
	CHECK_EQ(pps->get_var(value), Error::OK);
	CHECK_EQ(String(value), godot_rules);
}

TEST_CASE("[PacketPeer][PacketPeerStream] Read a variant from peer fails") {
	Ref<PacketPeerStream> pps;
	pps.instantiate();

	Variant value;
	ERR_PRINT_OFF;
	CHECK_EQ(pps->get_var(value), Error::ERR_UNCONFIGURED);
	ERR_PRINT_ON;
}

TEST_CASE("[PacketPeer][PacketPeerStream] Put a variant to peer") {
	String godot_rules = "Godot Rules!!!";

	Ref<StreamPeerBuffer> spb;
	spb.instantiate();

	Ref<PacketPeerStream> pps;
	pps.instantiate();
	pps->set_stream_peer(spb);

	CHECK_EQ(pps->put_var(godot_rules), Error::OK);

	spb->seek(0);
	CHECK_EQ(String(spb->get_var()), godot_rules);
}

TEST_CASE("[PacketPeer][PacketPeerStream] Put a variant to peer out of memory failure") {
	String more_than_1mb = String("*").repeat(1024 + 1);

	Ref<StreamPeerBuffer> spb;
	spb.instantiate();

	Ref<PacketPeerStream> pps;
	pps.instantiate();
	pps->set_stream_peer(spb);
	pps->set_encode_buffer_max_size(1024);

	ERR_PRINT_OFF;
	CHECK_EQ(pps->put_var(more_than_1mb), Error::ERR_OUT_OF_MEMORY);
	ERR_PRINT_ON;
}

TEST_CASE("[PacketPeer][PacketPeerStream] Get packet buffer") {
	String godot_rules = "Godot Rules!!!";

	Ref<StreamPeerBuffer> spb;
	spb.instantiate();
	// First 4 bytes are the length of the string.
	CharString cs = godot_rules.ascii();
	Vector<uint8_t> buffer = { (uint8_t)(cs.length() + 1), 0, 0, 0 };
	buffer.resize_initialized(4 + cs.length() + 1);
	memcpy(buffer.ptrw() + 4, cs.get_data(), cs.length());
	spb->set_data_array(buffer);

	Ref<PacketPeerStream> pps;
	pps.instantiate();
	pps->set_stream_peer(spb);

	buffer.clear();
	CHECK_EQ(pps->get_packet_buffer(buffer), Error::OK);

	CHECK_EQ(String(reinterpret_cast<const char *>(buffer.ptr())), godot_rules);
}

TEST_CASE("[PacketPeer][PacketPeerStream] Get packet buffer from an empty peer") {
	Ref<StreamPeerBuffer> spb;
	spb.instantiate();

	Ref<PacketPeerStream> pps;
	pps.instantiate();
	pps->set_stream_peer(spb);

	Vector<uint8_t> buffer;
	ERR_PRINT_OFF;
	CHECK_EQ(pps->get_packet_buffer(buffer), Error::ERR_UNAVAILABLE);
	ERR_PRINT_ON;
	CHECK_EQ(buffer.size(), 0);
}

TEST_CASE("[PacketPeer][PacketPeerStream] Put packet buffer") {
	String godot_rules = "Godot Rules!!!";

	Ref<StreamPeerBuffer> spb;
	spb.instantiate();

	Ref<PacketPeerStream> pps;
	pps.instantiate();
	pps->set_stream_peer(spb);

	CHECK_EQ(pps->put_packet_buffer(godot_rules.to_ascii_buffer()), Error::OK);

	spb->seek(0);
	CHECK_EQ(spb->get_string(), godot_rules);
	// First 4 bytes are the length of the string.
	CharString cs = godot_rules.ascii();
	Vector<uint8_t> buffer = { (uint8_t)cs.length(), 0, 0, 0 };
	buffer.resize(4 + cs.length());
	memcpy(buffer.ptrw() + 4, cs.get_data(), cs.length());
	CHECK_EQ(spb->get_data_array(), buffer);
}

TEST_CASE("[PacketPeer][PacketPeerStream] Put packet buffer when is empty") {
	Ref<StreamPeerBuffer> spb;
	spb.instantiate();

	Ref<PacketPeerStream> pps;
	pps.instantiate();
	pps->set_stream_peer(spb);

	Vector<uint8_t> buffer;
	CHECK_EQ(pps->put_packet_buffer(buffer), Error::OK);

	CHECK_EQ(spb->get_size(), 0);
}

TEST_CASE("[PacketPeer][Performance] Bulk framed packet copies retain wire format") {
	Ref<StreamPeerBuffer> stream;
	stream.instantiate();
	Ref<PacketPeerStream> packets;
	packets.instantiate();
	packets->set_stream_peer(stream);
	packets->set_input_buffer_max_size(32768);
	packets->set_output_buffer_max_size(32768);

	const int sizes[] = { 1, 2, 3, 4, 15, 31, 32, 255, 256, 512, 1024, 4096, 16384 };
	for (int size : sizes) {
		Vector<uint8_t> payload;
		REQUIRE(payload.resize_uninitialized(size) == OK);
		uint8_t *bytes = payload.ptrw();
		for (int i = 0; i < size; i++) {
			bytes[i] = uint8_t((i * 31 + size) & 0xff);
		}

		stream->clear();
		REQUIRE(packets->put_packet_buffer(payload) == OK);
		const Vector<uint8_t> &wire = stream->get_data_array();
		REQUIRE(wire.size() == size + 4);
		CHECK(wire[0] == uint8_t(size & 0xff));
		CHECK(wire[1] == uint8_t((size >> 8) & 0xff));
		CHECK(wire[2] == uint8_t((size >> 16) & 0xff));
		CHECK(wire[3] == uint8_t((size >> 24) & 0xff));
		for (int i = 0; i < size; i++) {
			CHECK(wire[4 + i] == payload[i]);
		}

		stream->seek(0);
		Vector<uint8_t> received;
		CHECK(packets->get_packet_buffer(received) == OK);
		CHECK(received == payload);
		CHECK(packets->get_available_packet_count() == 0);
	}

	// Multiple back-to-back frames preserve boundaries and their order.
	const Vector<uint8_t> first = { 0, 1, 255, 127 };
	const Vector<uint8_t> second = { 4, 3, 2, 1, 0 };
	stream->clear();
	CHECK(packets->put_packet_buffer(first) == OK);
	CHECK(packets->put_packet_buffer(second) == OK);
	stream->seek(0);
	CHECK(packets->get_available_packet_count() == 2);
	Vector<uint8_t> received;
	CHECK(packets->get_packet_buffer(received) == OK);
	CHECK(received == first);
	CHECK(packets->get_packet_buffer(received) == OK);
	CHECK(received == second);
	CHECK(packets->get_available_packet_count() == 0);

	// Invalid pointer/length pairs must fail without invoking memcpy.
	ERR_PRINT_OFF;
	CHECK(packets->put_packet(nullptr, 5) == ERR_INVALID_PARAMETER);
	CHECK(packets->put_packet(first.ptr(), INT32_MAX) == ERR_INVALID_PARAMETER);
	ERR_PRINT_ON;
}


TEST_CASE("[PacketPeer][PacketPeerStream] Incremental packet counting survives repeated polls") {
	Ref<StreamPeerBuffer> stream;
	stream.instantiate();
	Ref<PacketPeerStream> peer;
	peer.instantiate();
	peer->set_stream_peer(stream);
	peer->set_input_buffer_max_size(16384);

	Vector<uint8_t> wire;
	for (int i = 0; i < 512; i++) {
		const uint8_t frame[] = { 1, 0, 0, 0, uint8_t(i) };
		CHECK(wire.append_array(Span<uint8_t>(frame, 5)) == OK);
	}
	stream->set_data_array(wire);
	for (int i = 0; i < 128; i++) {
		CHECK_EQ(peer->get_available_packet_count(), 512);
	}

	for (int i = 0; i < 512; i++) {
		const uint8_t *data = nullptr;
		int length = -1;
		CHECK_EQ(peer->get_packet(&data, length), OK);
		REQUIRE_EQ(length, 1);
		CHECK(data != nullptr);
		CHECK_EQ(data[0], uint8_t(i));
		CHECK_EQ(peer->get_available_packet_count(), 511 - i);
	}
	CHECK_EQ(peer->get_available_packet_count(), 0);
}

TEST_CASE("[PacketPeer][PacketPeerStream] Counting resumes across split headers and payloads") {
	Ref<StreamPeerBuffer> stream;
	stream.instantiate();
	Ref<PacketPeerStream> peer;
	peer.instantiate();
	peer->set_stream_peer(stream);
	peer->set_input_buffer_max_size(128);
	const uint8_t wire[] = { 3, 0, 0, 0, 10, 20, 30, 0, 0, 0, 0 };

	// The writer and reader share one cursor; restore the reader cursor
	// after appending each piece to simulate incremental network delivery.
	int offset = 0;
	for (int chunk : { 2, 2, 1, 2, 1, 3 }) {
		const int old_end = stream->get_size();
		stream->seek(old_end);
		REQUIRE_EQ(stream->put_data(wire + offset, chunk), OK);
		stream->seek(old_end);
		offset += chunk;
		const int expected = offset < 7 ? 0 : offset < 11 ? 1 : 2;
		CHECK_EQ(peer->get_available_packet_count(), expected);
		CHECK_EQ(peer->get_available_packet_count(), expected);
	}
	const uint8_t *data = nullptr;
	int length = -1;
	CHECK_EQ(peer->get_packet(&data, length), OK);
	REQUIRE_EQ(length, 3);
	CHECK_EQ(data[0], 10);
	CHECK_EQ(data[1], 20);
	CHECK_EQ(data[2], 30);
	CHECK_EQ(peer->get_available_packet_count(), 1);
	CHECK_EQ(peer->get_packet(&data, length), OK);
	CHECK_EQ(length, 0);
	CHECK_EQ(peer->get_available_packet_count(), 0);
}

TEST_CASE("[PacketPeer][PacketPeerStream] Switching streams drops cached parsed frames") {
	Ref<StreamPeerBuffer> first;
	first.instantiate();
	const uint8_t wire[] = { 1, 0, 0, 0, 42, 1, 0, 0, 0, 43 };
	REQUIRE_EQ(first->put_data(wire, 10), OK);
	first->seek(0);

	Ref<PacketPeerStream> packets;
	packets.instantiate();
	packets->set_stream_peer(first);
	CHECK_EQ(packets->get_available_packet_count(), 2);

	Ref<StreamPeerBuffer> replacement;
	replacement.instantiate();
	packets->set_stream_peer(replacement);
	CHECK_EQ(packets->get_available_packet_count(), 0);
	packets->set_input_buffer_max_size(1024);
	CHECK_EQ(packets->get_available_packet_count(), 0);
	replacement->put_data(wire, 5);
	replacement->seek(0);
	CHECK_EQ(packets->get_available_packet_count(), 1);
}

} // namespace TestPacketPeer
