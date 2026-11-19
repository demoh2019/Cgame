/**************************************************************************/
/*  test_websocket_peer.h                                                 */
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

#include "core/io/stream_peer_tcp.h"
#include "core/io/tcp_server.h"
#include "core/os/os.h"
#include "tests/test_macros.h"

#include "modules/websocket/websocket_peer.h"

#include <functional>

namespace TestWebSocketPeer {

const IPAddress LOCALHOST("127.0.0.1");
const uint32_t SLEEP_DURATION = 1000;
const uint64_t MAX_WAIT_USEC = 2000000;

inline bool wait_for_condition(std::function<bool()> f_test) {
	if (f_test()) {
		return true;
	}
	const uint64_t time = OS::get_singleton()->get_ticks_usec();
	while ((OS::get_singleton()->get_ticks_usec() - time) < MAX_WAIT_USEC) {
		OS::get_singleton()->delay_usec(SLEEP_DURATION);
		if (f_test()) {
			return true;
		}
	}
	return false;
}

struct ScopedCleanup {
	const std::function<void()> run;

	~ScopedCleanup() {
		run();
	}
};

TEST_CASE("[WebSocketPeer] Interleaved Ping preserves fragmented message bytes") {
	Ref<TCPServer> server;
	server.instantiate();

	REQUIRE_EQ(server->listen(0, LOCALHOST), Error::OK);
	REQUIRE(server->is_listening());
	CHECK_FALSE(server->is_connection_available());

	Ref<WebSocketPeer> client(WebSocketPeer::create());
	REQUIRE(client.is_valid());

	const String url = vformat("ws://%s:%d", LOCALHOST, server->get_local_port());
	REQUIRE_EQ(client->connect_to_url(url), Error::OK);

	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return server->is_connection_available();
	}));
	Ref<StreamPeerTCP> connection = server->take_connection();
	REQUIRE(connection.is_valid());
	CHECK_EQ(client->get_connected_host(), LOCALHOST);

	Ref<WebSocketPeer> server_peer(WebSocketPeer::create());
	REQUIRE(server_peer.is_valid());

	ScopedCleanup cleanup{ [&]() {
		connection->disconnect_from_host();
		wait_for_condition([&]() {
			client->poll();
			server_peer->poll();
			return client->get_ready_state() == WebSocketPeer::STATE_CLOSED &&
					server_peer->get_ready_state() == WebSocketPeer::STATE_CLOSED;
		});
	} };

	REQUIRE_EQ(server_peer->accept_stream(connection), OK);

	REQUIRE(wait_for_condition([&]() {
		client->poll();
		server_peer->poll();
		return client->get_ready_state() == WebSocketPeer::STATE_OPEN &&
				server_peer->get_ready_state() == WebSocketPeer::STATE_OPEN;
	}));

	constexpr uint8_t frames[] = {
		0x01,
		0x01,
		'A', // Text frame, FIN clear.
		0x89,
		0x01,
		'!', // Ping frame, FIN set.
		0x80,
		0x01,
		'B', // Continuation of initial "A" Text frame, FIN set.
	};
	REQUIRE_EQ(connection->put_data(frames, sizeof(frames)), OK);

	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));

	Vector<uint8_t> packet;
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	CHECK_EQ(String::utf8(reinterpret_cast<const char *>(packet.ptr()), packet.size()), "AB");
	CHECK(client->was_string_packet());
	CHECK_EQ(client->get_available_packet_count(), 0);

	// Control frames must never contaminate a message, even when several
	// Ping/Pong frames arrive between continuation frames.
	constexpr uint8_t interleaved_control_frames[] = {
		0x01, 0x01, 'C', // Non-final text.
		0x89, 0x01, '!', // Ping carrying a payload.
		0x8A, 0x01, '?', // Pong carrying a payload.
		0x00, 0x01, 'D', // Non-final continuation.
		0x89, 0x00, // Empty Ping.
		0x80, 0x01, 'E', // Final continuation.
	};
	REQUIRE_EQ(connection->put_data(interleaved_control_frames, sizeof(interleaved_control_frames)), OK);
	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	CHECK_EQ(String::utf8(reinterpret_cast<const char *>(packet.ptr()), packet.size()), "CDE");

	// Binary frames exercise the same reassembly path, including NUL bytes.
	constexpr uint8_t interleaved_binary_frames[] = {
		0x02, 0x02, 0x00, 0xFF, // Non-final binary, 2 payload bytes.
		0x89, 0x01, 0x33, // Ping, excluded from binary payload.
		0x80, 0x02, 0x01, 0x02, // Final continuation.
	};
	REQUIRE_EQ(connection->put_data(interleaved_binary_frames, sizeof(interleaved_binary_frames)), OK);
	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	REQUIRE_EQ(packet.size(), 4);
	CHECK_EQ(packet[0], 0);
	CHECK_EQ(packet[1], 0xFF);
	CHECK_EQ(packet[2], 1);
	CHECK_EQ(packet[3], 2);

	// Control frames must not pollute binary messages either, including zero bytes.
	constexpr uint8_t binary_frames[] = {
		0x02, 0x01, 0x00, // Binary frame, FIN clear.
		0x89, 0x03, 'P', 'I', 'N', // Ping control frame.
		0x80, 0x02, 0xFF, 0x7F, // Final binary continuation.
	};
	REQUIRE_EQ(connection->put_data(binary_frames, sizeof(binary_frames)), OK);
	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	REQUIRE_EQ(packet.size(), 3);
	CHECK_EQ(packet[0], 0);
	CHECK_EQ(packet[1], 0xFF);
	CHECK_EQ(packet[2], 0x7F);
	CHECK_FALSE(client->was_string_packet());
	CHECK_EQ(client->get_available_packet_count(), 0);

	// Unsolicited Pong is also a control frame and must not be appended to text.
	constexpr uint8_t pong_frames[] = {
		0x01, 0x01, 'C',
		0x8A, 0x03, 'x', 'y', 'z',
		0x80, 0x01, 'D',
	};
	REQUIRE_EQ(connection->put_data(pong_frames, sizeof(pong_frames)), OK);
	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	CHECK_EQ(String::utf8(reinterpret_cast<const char *>(packet.ptr()), packet.size()), "CD");
	CHECK(client->was_string_packet());
	CHECK_EQ(client->get_available_packet_count(), 0);

	// Multiple Ping frames can be received while a single fragmented message is open.
	constexpr uint8_t multiple_pings[] = {
		0x01, 0x01, 'E',
		0x89, 0x01, '1',
		0x89, 0x01, '2',
		0x80, 0x01, 'F',
	};
	REQUIRE_EQ(connection->put_data(multiple_pings, sizeof(multiple_pings)), OK);
	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	CHECK_EQ(String::utf8(reinterpret_cast<const char *>(packet.ptr()), packet.size()), "EF");
	CHECK_EQ(client->get_available_packet_count(), 0);

	// An intermediate continuation frame must retain the original message,
	// even when a Ping arrives before the final continuation.
	constexpr uint8_t intermediate_continuation[] = {
		0x01, 0x01, 'G',
		0x00, 0x01, 'H',
		0x89, 0x02, 'x', 'x',
		0x80, 0x01, 'I',
	};
	REQUIRE_EQ(connection->put_data(intermediate_continuation, sizeof(intermediate_continuation)), OK);
	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	CHECK_EQ(String::utf8(reinterpret_cast<const char *>(packet.ptr()), packet.size()), "GHI");
	CHECK_EQ(client->get_available_packet_count(), 0);

	// The first fragment and Ping can be processed in a different poll() call
	// from the final continuation without producing an early packet.
	constexpr uint8_t first_fragment_and_ping[] = {
		0x01, 0x01, 'J',
		0x89, 0x01, '?',
	};
	REQUIRE_EQ(connection->put_data(first_fragment_and_ping, sizeof(first_fragment_and_ping)), OK);
	for (int i = 0; i < 5; i++) {
		client->poll();
		OS::get_singleton()->delay_usec(SLEEP_DURATION);
	}
	CHECK_EQ(client->get_available_packet_count(), 0);
	constexpr uint8_t final_continuation[] = { 0x80, 0x01, 'K' };
	REQUIRE_EQ(connection->put_data(final_continuation, sizeof(final_continuation)), OK);
	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	CHECK_EQ(String::utf8(reinterpret_cast<const char *>(packet.ptr()), packet.size()), "JK");
	CHECK_EQ(client->get_available_packet_count(), 0);

	// A control frame outside fragmentation is never delivered as a user packet.
	constexpr uint8_t ping_and_text[] = {
		0x89, 0x01, '!',
		0x81, 0x01, 'L',
	};
	REQUIRE_EQ(connection->put_data(ping_and_text, sizeof(ping_and_text)), OK);
	REQUIRE(wait_for_condition([&]() {
		client->poll();
		return client->get_available_packet_count() > 0;
	}));
	REQUIRE_EQ(client->get_packet_buffer(packet), OK);
	CHECK_EQ(String::utf8(reinterpret_cast<const char *>(packet.ptr()), packet.size()), "L");
	CHECK_EQ(client->get_available_packet_count(), 0);
}

} // namespace TestWebSocketPeer
