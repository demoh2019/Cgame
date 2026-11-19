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

	// Exercise other control frame combinations while a data message is open.
	// Control payloads must not leak into reassembled text or binary data.
	constexpr uint8_t empty_ping[] = {
		0x01, 0x01, 'C', // Start a fragmented text message.
		0x89, 0x00, // Ping with no payload.
		0x80, 0x01, 'D', // Final continuation frame.
	};
	constexpr uint8_t interleaved_pong[] = {
		0x01, 0x01, 'E',
		0x8A, 0x01, '!',
		0x80, 0x01, 'F',
	};
	constexpr uint8_t binary_ping[] = {
		0x02, 0x01, 'G', // Start a fragmented binary message.
		0x89, 0x01, '?',
		0x80, 0x01, 'H',
	};
	constexpr uint8_t multiple_control_frames[] = {
		0x01, 0x01, 'I',
		0x89, 0x01, '!',
		0x00, 0x01, 'J', // Non-final continuation.
		0x8A, 0x01, '?',
		0x80, 0x01, 'K',
	};
	constexpr uint8_t ping_before_data[] = {
		0x89, 0x01, '?', // Control frame without an open message.
		0x81, 0x01, 'X', // Complete text message.
	};

	struct FrameCase {
		const char *name;
		const uint8_t *data;
		size_t size;
		const char *expected;
	};
	const FrameCase cases[] = {
		{ "Empty Ping payload", empty_ping, sizeof(empty_ping), "CD" },
		{ "Pong interleaved with text", interleaved_pong, sizeof(interleaved_pong), "EF" },
		{ "Ping interleaved with binary", binary_ping, sizeof(binary_ping), "GH" },
		{ "Multiple control frames", multiple_control_frames, sizeof(multiple_control_frames), "IJK" },
		{ "Ping before complete text", ping_before_data, sizeof(ping_before_data), "X" },
	};

	for (const FrameCase &test_case : cases) {
		INFO(test_case.name);
		REQUIRE_EQ(connection->put_data(test_case.data, test_case.size), OK);
		REQUIRE(wait_for_condition([&]() {
			client->poll();
			server_peer->poll();
			return client->get_available_packet_count() > 0;
		}));
		Vector<uint8_t> received;
		REQUIRE_EQ(client->get_packet_buffer(received), OK);
		CHECK_EQ(String::utf8(reinterpret_cast<const char *>(received.ptr()), received.size()), test_case.expected);
		CHECK_EQ(client->get_available_packet_count(), 0);
	}
}

} // namespace TestWebSocketPeer
