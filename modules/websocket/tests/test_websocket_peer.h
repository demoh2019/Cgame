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


	// Control frames are permitted between data fragments, but their payload
	// must never end up in the reassembled application message.
	constexpr uint8_t text_ping[] = { 0x01, 0x01, 'A', 0x89, 0x01, '!', 0x80, 0x01, 'B' };
	constexpr uint8_t text_pong[] = { 0x01, 0x01, 'C', 0x8A, 0x01, '?', 0x80, 0x01, 'D' };
	constexpr uint8_t binary_ping[] = { 0x02, 0x02, 0x00, 0xFE, 0x89, 0x01, '!', 0x80, 0x02, 0x80, 0xFF };
	constexpr uint8_t multiple_pings[] = { 0x01, 0x01, 'E', 0x89, 0x01, '!', 0x89, 0x01, '?', 0x80, 0x01, 'F' };
	constexpr uint8_t empty_ping[] = { 0x01, 0x01, 'I', 0x89, 0x00, 0x80, 0x01, 'J' };
	constexpr uint8_t ping_and_pong[] = { 0x01, 0x01, 'K', 0x8A, 0x00, 0x89, 0x01, '!', 0x80, 0x01, 'L' };
	constexpr uint8_t normal_text[] = { 0x81, 0x02, 'G', 'H' };
	constexpr uint8_t expected_ab[] = { 'A', 'B' };
	constexpr uint8_t expected_cd[] = { 'C', 'D' };
	constexpr uint8_t expected_binary[] = { 0x00, 0xFE, 0x80, 0xFF };
	constexpr uint8_t expected_ef[] = { 'E', 'F' };
	constexpr uint8_t expected_ij[] = { 'I', 'J' };
	constexpr uint8_t expected_kl[] = { 'K', 'L' };
	constexpr uint8_t expected_gh[] = { 'G', 'H' };

	struct FrameCase {
		const char *name;
		const uint8_t *frames;
		size_t frames_size;
		const uint8_t *expected;
		size_t expected_size;
		bool is_text;
	};
	const FrameCase cases[] = {
		{ "Ping inside text", text_ping, sizeof(text_ping), expected_ab, sizeof(expected_ab), true },
		{ "Pong inside text", text_pong, sizeof(text_pong), expected_cd, sizeof(expected_cd), true },
		{ "Ping inside binary", binary_ping, sizeof(binary_ping), expected_binary, sizeof(expected_binary), false },
		{ "Multiple Pings", multiple_pings, sizeof(multiple_pings), expected_ef, sizeof(expected_ef), true },
		{ "Empty Ping", empty_ping, sizeof(empty_ping), expected_ij, sizeof(expected_ij), true },
		{ "Ping and Pong", ping_and_pong, sizeof(ping_and_pong), expected_kl, sizeof(expected_kl), true },
		{ "Unfragmented text", normal_text, sizeof(normal_text), expected_gh, sizeof(expected_gh), true },
	};

	for (const FrameCase &test_case : cases) {
		INFO("Frame case: ", test_case.name);
		REQUIRE_EQ(connection->put_data(test_case.frames, test_case.frames_size), OK);
		REQUIRE(wait_for_condition([&]() {
			client->poll();
			server_peer->poll();
			return client->get_available_packet_count() > 0;
		}));

		Vector<uint8_t> packet;
		REQUIRE_EQ(client->get_packet_buffer(packet), OK);
		CHECK_EQ(packet.size(), test_case.expected_size);
		if (packet.size() == test_case.expected_size) {
			for (int i = 0; i < packet.size(); i++) {
				CHECK_EQ(packet[i], test_case.expected[i]);
			}
		}
		CHECK_EQ(client->was_string_packet(), test_case.is_text);
		CHECK_EQ(client->get_available_packet_count(), 0);
	}

}

} // namespace TestWebSocketPeer
