/**************************************************************************/
/*  test_udp_server.cpp                                                   */
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

TEST_FORCE_LINK(test_udp_server)

#include "core/io/packet_peer_udp.h"
#include "core/io/udp_server.h"
#include "core/os/os.h"

#include <functional>

namespace TestUDPServer {

const int PORT = 12345;
const IPAddress LOCALHOST("127.0.0.1");
const uint32_t SLEEP_DURATION = 1000;
const uint64_t MAX_WAIT_USEC = 100000;

void wait_for_condition(std::function<bool()> f_test) {
	const uint64_t time = OS::get_singleton()->get_ticks_usec();
	while (!f_test() && (OS::get_singleton()->get_ticks_usec() - time) < MAX_WAIT_USEC) {
		OS::get_singleton()->delay_usec(SLEEP_DURATION);
	}
}

Ref<UDPServer> create_server(const IPAddress &p_address, int p_port) {
	Ref<UDPServer> server;
	server.instantiate();

	Error err = server->listen(PORT, LOCALHOST);
	REQUIRE_EQ(Error::OK, err);
	REQUIRE(server->is_listening());
	CHECK_FALSE(server->is_connection_available());
	CHECK_EQ(server->get_max_pending_connections(), 16);

	return server;
}

Ref<PacketPeerUDP> create_client(const IPAddress &p_address, int p_port) {
	Ref<PacketPeerUDP> client;
	client.instantiate();

	Error err = client->connect_to_host(LOCALHOST, PORT);
	REQUIRE_EQ(Error::OK, err);
	CHECK(client->is_bound());
	CHECK(client->is_socket_connected());

	return client;
}

Ref<PacketPeerUDP> accept_connection(Ref<UDPServer> &p_server) {
	wait_for_condition([&]() {
		return p_server->poll() != Error::OK || p_server->is_connection_available();
	});

	CHECK_EQ(p_server->poll(), Error::OK);
	REQUIRE(p_server->is_connection_available());
	Ref<PacketPeerUDP> client_from_server = p_server->take_connection();
	REQUIRE(client_from_server.is_valid());
	CHECK(client_from_server->is_bound());
	CHECK(client_from_server->is_socket_connected());

	return client_from_server;
}

TEST_CASE("[UDPServer] Instantiation") {
	Ref<UDPServer> server;
	server.instantiate();

	REQUIRE(server.is_valid());
	CHECK_EQ(false, server->is_listening());
}

TEST_CASE("[UDPServer] Accept a connection and receive/send data") {
	Ref<UDPServer> server = create_server(LOCALHOST, PORT);
	Ref<PacketPeerUDP> client = create_client(LOCALHOST, PORT);

	// Sending data from client to server.
	const String hello_world = "Hello World!";
	CHECK_EQ(client->put_var(hello_world), Error::OK);

	Variant hello_world_received;
	Ref<PacketPeerUDP> client_from_server = accept_connection(server);
	CHECK_EQ(client_from_server->get_var(hello_world_received), Error::OK);
	CHECK_EQ(String(hello_world_received), hello_world);

	// Sending data from server to client.
	const Variant pi = 3.1415;
	CHECK_EQ(client_from_server->put_var(pi), Error::OK);

	wait_for_condition([&]() {
		return client->get_available_packet_count() > 0;
	});

	CHECK_GT(client->get_available_packet_count(), 0);

	Variant pi_received;
	CHECK_EQ(client->get_var(pi_received), Error::OK);
	CHECK_EQ(pi_received, pi);

	client->close();
	server->stop();
	CHECK_FALSE(server->is_listening());
}

TEST_CASE("[UDPServer] Handle multiple clients at the same time") {
	Ref<UDPServer> server = create_server(LOCALHOST, PORT);

	Vector<Ref<PacketPeerUDP>> clients;
	for (int i = 0; i < 5; i++) {
		Ref<PacketPeerUDP> c = create_client(LOCALHOST, PORT);

		// Sending data from client to server.
		const String hello_client = itos(i);
		CHECK_EQ(c->put_var(hello_client), Error::OK);

		clients.push_back(c);
	}

	Array packets;
	for (int i = 0; i < clients.size(); i++) {
		Ref<PacketPeerUDP> cfs = accept_connection(server);

		Variant received_var;
		CHECK_EQ(cfs->get_var(received_var), Error::OK);
		CHECK_EQ(received_var.get_type(), Variant::STRING);
		packets.push_back(received_var);

		// Sending data from server to client.
		const float sent_float = 3.1415 + received_var.operator String().to_float();
		CHECK_EQ(cfs->put_var(sent_float), Error::OK);
	}

	CHECK_EQ(packets.size(), clients.size());

	packets.sort();
	for (int i = 0; i < clients.size(); i++) {
		CHECK_EQ(packets[i].operator String(), itos(i));
	}

	wait_for_condition([&]() {
		bool should_exit = true;
		for (Ref<PacketPeerUDP> &c : clients) {
			int count = c->get_available_packet_count();
			if (count < 0) {
				return true;
			}
			if (count == 0) {
				should_exit = false;
			}
		}
		return should_exit;
	});

	for (int i = 0; i < clients.size(); i++) {
		CHECK_GT(clients[i]->get_available_packet_count(), 0);

		Variant received_var;
		const float expected = 3.1415 + i;
		CHECK_EQ(clients[i]->get_var(received_var), Error::OK);
		CHECK_EQ(received_var.get_type(), Variant::FLOAT);
		CHECK_EQ(received_var.operator float(), expected);
	}

	for (Ref<PacketPeerUDP> &c : clients) {
		c->close();
	}
	server->stop();
}

TEST_CASE("[UDPServer] Should not accept new connections after stop") {
	Ref<UDPServer> server = create_server(LOCALHOST, PORT);
	Ref<PacketPeerUDP> client = create_client(LOCALHOST, PORT);

	// Sending data from client to server.
	const String hello_world = "Hello World!";
	CHECK_EQ(client->put_var(hello_world), Error::OK);

	wait_for_condition([&]() {
		return server->poll() != Error::OK || server->is_connection_available();
	});

	REQUIRE(server->is_connection_available());

	server->stop();

	CHECK_FALSE(server->is_listening());
	CHECK_FALSE(server->is_connection_available());
}

TEST_CASE("[UDPServer][Performance] Batched UDP queue framing preserves packet data on ring wrap") {
	const IPAddress source_address("127.0.0.1");
	Ref<PacketPeerUDP> receiver;
	receiver.instantiate();
	REQUIRE(receiver->bind(0, source_address, 1024) == OK);

	// Repeated enqueue/dequeue cycles force the ring read/write cursors
	// across its physical boundary without ever sending network packets.
	uint8_t payload[384] = {};
	const int sizes[] = { 0, 1, 15, 24, 31, 63, 127, 255, 383 };
	for (int iteration = 0; iteration < 90; iteration++) {
		const int size = sizes[iteration % 9];
		for (int i = 0; i < size; i++) {
			payload[i] = uint8_t((iteration * 7 + i * 13) & 255);
		}
		const uint32_t source_port = 10001 + iteration;
		REQUIRE(receiver->store_packet(source_address, source_port, payload, size) == OK);
		CHECK(receiver->get_available_packet_count() == 1);
		const uint8_t *received = nullptr;
		int received_size = -1;
		REQUIRE(receiver->get_packet(&received, received_size) == OK);
		REQUIRE(received_size == size);
		CHECK(receiver->get_packet_address() == source_address);
		CHECK(receiver->get_packet_port() == int(source_port));
		for (int i = 0; i < size; i++) {
			CHECK(received[i] == payload[i]);
		}
		CHECK(receiver->get_available_packet_count() == 0);
	}

	// Multiple frames can coexist in the queue; boundaries must remain
	// intact when the ring wraps between header and payload bytes.
	for (int packet = 0; packet < 4; packet++) {
		const int size = 24 + packet * 17;
		for (int i = 0; i < size; i++) {
			payload[i] = uint8_t(i + packet);
		}
		REQUIRE(receiver->store_packet(source_address, 22000 + packet, payload, size) == OK);
	}
	CHECK(receiver->get_available_packet_count() == 4);
	for (int packet = 0; packet < 4; packet++) {
		const uint8_t *received = nullptr;
		int received_size = -1;
		REQUIRE(receiver->get_packet(&received, received_size) == OK);
		REQUIRE(received_size == 24 + packet * 17);
		CHECK(receiver->get_packet_port() == 22000 + packet);
		for (int i = 0; i < received_size; i++) {
			CHECK(received[i] == uint8_t(i + packet));
		}
	}

	// Malformed sizes and pointer/size pairs must not alter queue state.
	ERR_PRINT_OFF;
	CHECK(receiver->store_packet(source_address, 42, payload, -1) == ERR_INVALID_PARAMETER);
	CHECK(receiver->store_packet(source_address, 42, payload, 65537) == ERR_INVALID_PARAMETER);
	CHECK(receiver->store_packet(source_address, 42, nullptr, 1) == ERR_INVALID_PARAMETER);
	ERR_PRINT_ON;
	CHECK(receiver->get_available_packet_count() == 0);
	receiver->close();
}

} // namespace TestUDPServer
