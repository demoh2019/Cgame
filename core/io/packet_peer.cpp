/**************************************************************************/
/*  packet_peer.cpp                                                       */
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

#include "packet_peer.h"

#include "core/config/project_settings.h"
#include "core/io/marshalls.h"
#include "core/object/class_db.h"

#include <cstring>

/* helpers / binders */

void PacketPeer::set_encode_buffer_max_size(int p_max_size) {
	ERR_FAIL_COND_MSG(p_max_size < 1024, "Max encode buffer must be at least 1024 bytes");
	ERR_FAIL_COND_MSG(p_max_size > 256 * 1024 * 1024, "Max encode buffer cannot exceed 256 MiB");
	encode_buffer_max_size = Math::next_power_of_2((uint32_t)p_max_size);
	encode_buffer.clear();
}

int PacketPeer::get_encode_buffer_max_size() const {
	return encode_buffer_max_size;
}

Error PacketPeer::get_packet_buffer(Vector<uint8_t> &r_buffer) {
	const uint8_t *buffer;
	int buffer_size;
	RETURN_IF_ERROR(get_packet(&buffer, buffer_size));
	ERR_FAIL_COND_V(buffer_size < 0, ERR_INVALID_DATA);

	RETURN_IF_ERROR(r_buffer.resize_uninitialized(buffer_size));
	if (buffer_size == 0) {
		return OK;
	}
	ERR_FAIL_NULL_V(buffer, ERR_INVALID_DATA);

	// Copy contiguous bytes in one operation instead of a per-byte loop.
	memcpy(r_buffer.ptrw(), buffer, buffer_size);
	return OK;
}

Error PacketPeer::put_packet_buffer(const Vector<uint8_t> &p_buffer) {
	int len = p_buffer.size();
	if (len == 0) {
		return OK;
	}

	const uint8_t *r = p_buffer.ptr();
	return put_packet(&r[0], len);
}

Error PacketPeer::get_var(Variant &r_variant, bool p_allow_objects) {
	const uint8_t *buffer;
	int buffer_size;
	RETURN_IF_ERROR(get_packet(&buffer, buffer_size));

	return decode_variant(r_variant, buffer, buffer_size, nullptr, p_allow_objects);
}

Error PacketPeer::put_var(const Variant &p_packet, bool p_full_objects) {
	int len;
	Error err = encode_variant(p_packet, nullptr, len, p_full_objects); // compute len first
	if (err) {
		return err;
	}

	if (len == 0) {
		return OK;
	}

	ERR_FAIL_COND_V_MSG(len > encode_buffer_max_size, ERR_OUT_OF_MEMORY, "Failed to encode variant, encode size is bigger then encode_buffer_max_size. Consider raising it via 'set_encode_buffer_max_size'.");

	if (unlikely(encode_buffer.size() < len)) {
		// Grow once and reuse the scratch buffer across packets. Its bytes are
		// overwritten by encode_variant(), so zero-initialization and a prior
		// shrink-to-zero are unnecessary.
		RETURN_IF_ERROR(encode_buffer.resize_uninitialized(Math::next_power_of_2((uint32_t)len)));
	}

	uint8_t *w = encode_buffer.ptrw();
	err = encode_variant(p_packet, w, len, p_full_objects);
	ERR_FAIL_COND_V_MSG(err != OK, err, "Error when trying to encode Variant.");

	return put_packet(w, len);
}

Variant PacketPeer::_bnd_get_var(bool p_allow_objects) {
	Variant var;
	Error err = get_var(var, p_allow_objects);

	ERR_FAIL_COND_V(err != OK, Variant());
	return var;
}

Error PacketPeer::_put_packet(const Vector<uint8_t> &p_buffer) {
	return put_packet_buffer(p_buffer);
}

Vector<uint8_t> PacketPeer::_get_packet() {
	Vector<uint8_t> raw;
	last_get_error = get_packet_buffer(raw);
	return raw;
}

Error PacketPeer::_get_packet_error() const {
	return last_get_error;
}

void PacketPeer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_var", "allow_objects"), &PacketPeer::_bnd_get_var, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("put_var", "var", "full_objects"), &PacketPeer::put_var, DEFVAL(false));

	ClassDB::bind_method(D_METHOD("get_packet"), &PacketPeer::_get_packet);
	ClassDB::bind_method(D_METHOD("put_packet", "buffer"), &PacketPeer::_put_packet);
	ClassDB::bind_method(D_METHOD("get_packet_error"), &PacketPeer::_get_packet_error);
	ClassDB::bind_method(D_METHOD("get_available_packet_count"), &PacketPeer::get_available_packet_count);

	ClassDB::bind_method(D_METHOD("get_encode_buffer_max_size"), &PacketPeer::get_encode_buffer_max_size);
	ClassDB::bind_method(D_METHOD("set_encode_buffer_max_size", "max_size"), &PacketPeer::set_encode_buffer_max_size);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "encode_buffer_max_size"), "set_encode_buffer_max_size", "get_encode_buffer_max_size");
}

/***************/

Error PacketPeerExtension::get_packet(const uint8_t **r_buffer, int &r_buffer_size) {
	Error err;
	if (GDVIRTUAL_CALL(_get_packet, r_buffer, &r_buffer_size, err)) {
		return err;
	}
	WARN_PRINT_ONCE("PacketPeerExtension::_get_packet_native is unimplemented!");
	return FAILED;
}

Error PacketPeerExtension::put_packet(const uint8_t *p_buffer, int p_buffer_size) {
	Error err;
	if (GDVIRTUAL_CALL(_put_packet, p_buffer, p_buffer_size, err)) {
		return err;
	}
	WARN_PRINT_ONCE("PacketPeerExtension::_put_packet_native is unimplemented!");
	return FAILED;
}

void PacketPeerExtension::_bind_methods() {
	GDVIRTUAL_BIND(_get_packet, "r_buffer", "r_buffer_size");
	GDVIRTUAL_BIND(_put_packet, "buffer", "buffer_size");
	GDVIRTUAL_BIND(_get_available_packet_count);
	GDVIRTUAL_BIND(_get_max_packet_size);
}

/***************/

void PacketPeerStream::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_stream_peer", "peer"), &PacketPeerStream::set_stream_peer);
	ClassDB::bind_method(D_METHOD("get_stream_peer"), &PacketPeerStream::get_stream_peer);
	ClassDB::bind_method(D_METHOD("set_input_buffer_max_size", "max_size_bytes"), &PacketPeerStream::set_input_buffer_max_size);
	ClassDB::bind_method(D_METHOD("set_output_buffer_max_size", "max_size_bytes"), &PacketPeerStream::set_output_buffer_max_size);
	ClassDB::bind_method(D_METHOD("get_input_buffer_max_size"), &PacketPeerStream::get_input_buffer_max_size);
	ClassDB::bind_method(D_METHOD("get_output_buffer_max_size"), &PacketPeerStream::get_output_buffer_max_size);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "input_buffer_max_size"), "set_input_buffer_max_size", "get_input_buffer_max_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "output_buffer_max_size"), "set_output_buffer_max_size", "get_output_buffer_max_size");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "stream_peer", PROPERTY_HINT_RESOURCE_TYPE, StreamPeer::get_class_static(), PROPERTY_USAGE_NONE), "set_stream_peer", "get_stream_peer");
}

Error PacketPeerStream::_poll_buffer() const {
	ERR_FAIL_COND_V(peer.is_null(), ERR_UNCONFIGURED);

	const int space = ring_buffer.space_left();
	ERR_FAIL_COND_V(input_buffer.size() < space, ERR_UNAVAILABLE);
	int read = 0;
	if (space > 0) {
		RETURN_IF_ERROR(peer->get_partial_data(input_buffer.ptrw(), space, read));
	}
	if (read > 0) {
		const int written = ring_buffer.write(input_buffer.ptr(), read);
		ERR_FAIL_COND_V(written != read, ERR_BUG);
	}

	// Resume at the first unparsed byte, not at the beginning of the
	// ring buffer. Repeated polling now has O(new frames) parsing cost.
	const int available = ring_buffer.data_left();
	while (available - parsed_frame_bytes >= 4) {
		uint8_t lbuf[4];
		ring_buffer.copy(lbuf, parsed_frame_bytes, 4);
		const uint32_t length = decode_uint32(lbuf);
		const int remaining = available - parsed_frame_bytes - 4;
		if (length > uint32_t(remaining)) {
			break; // Partial payload; resume when new bytes arrive.
		}
		parsed_frame_bytes += 4 + int(length);
		complete_packet_count++;
	}
	return OK;
}

int PacketPeerStream::get_available_packet_count() const {
	_poll_buffer();
	return complete_packet_count;
}

Error PacketPeerStream::get_packet(const uint8_t **r_buffer, int &r_buffer_size) {
	ERR_FAIL_COND_V(peer.is_null(), ERR_UNCONFIGURED);
	_poll_buffer();

	ERR_FAIL_COND_V(complete_packet_count == 0, ERR_UNAVAILABLE);
	const int remaining = ring_buffer.data_left();
	ERR_FAIL_COND_V(remaining < 4, ERR_UNAVAILABLE);
	uint8_t lbuf[4];
	ring_buffer.copy(lbuf, 0, 4);
	const uint32_t len = decode_uint32(lbuf);
	// Compare unsigned to reject malformed 32-bit lengths without overflow.
	ERR_FAIL_COND_V(len > uint32_t(remaining - 4), ERR_UNAVAILABLE);
	ERR_FAIL_COND_V(len > uint32_t(input_buffer.size()), ERR_UNAVAILABLE);

	ring_buffer.read(lbuf, 4); // Discard the header.
	ring_buffer.read(input_buffer.ptrw(), int(len));
	parsed_frame_bytes -= 4 + int(len);
	complete_packet_count--;

	*r_buffer = input_buffer.ptr();
	r_buffer_size = int(len);
	return OK;
}

Error PacketPeerStream::put_packet(const uint8_t *p_buffer, int p_buffer_size) {
	ERR_FAIL_COND_V(peer.is_null(), ERR_UNCONFIGURED);
	Error err = _poll_buffer(); //won't hurt to poll here too

	if (err) {
		return err;
	}

	if (p_buffer_size == 0) {
		return OK;
	}

	ERR_FAIL_COND_V(p_buffer_size < 0, ERR_INVALID_PARAMETER);
	ERR_FAIL_NULL_V(p_buffer, ERR_INVALID_PARAMETER);
	// Avoid signed overflow in p_buffer_size + 4 for malformed lengths.
	ERR_FAIL_COND_V(output_buffer.size() < 4 || p_buffer_size > output_buffer.size() - 4, ERR_INVALID_PARAMETER);

	// Resolve writable COW storage once, then fill the prefix and payload
	// with an efficient bulk copy rather than repeated proxy lookups.
	uint8_t *dst = output_buffer.ptrw();
	encode_uint32(p_buffer_size, dst);
	memcpy(dst + 4, p_buffer, p_buffer_size);

	return peer->put_data(dst, p_buffer_size + 4);
}

int PacketPeerStream::get_max_packet_size() const {
	return output_buffer.size();
}

void PacketPeerStream::set_stream_peer(const Ref<StreamPeer> &p_peer) {
	if (p_peer.ptr() != peer.ptr()) {
		ring_buffer.clear();
		parsed_frame_bytes = 0;
		complete_packet_count = 0;
	}

	peer = p_peer;
}

Ref<StreamPeer> PacketPeerStream::get_stream_peer() const {
	return peer;
}

void PacketPeerStream::set_input_buffer_max_size(int p_max_size) {
	ERR_FAIL_COND_MSG(p_max_size < 0, "Max size of input buffer size cannot be smaller than 0.");
	// WARNING: May lose packets.
	ERR_FAIL_COND_MSG(ring_buffer.data_left(), "Buffer in use, resizing would cause loss of data.");
	ring_buffer.resize(Math::nearest_shift(Math::next_power_of_2((uint32_t)p_max_size + (uint32_t)4)) - 1);
	input_buffer.resize(Math::next_power_of_2((uint32_t)p_max_size + (uint32_t)4));
	parsed_frame_bytes = 0;
	complete_packet_count = 0;
}

int PacketPeerStream::get_input_buffer_max_size() const {
	return input_buffer.size() - 4;
}

void PacketPeerStream::set_output_buffer_max_size(int p_max_size) {
	output_buffer.resize(Math::next_power_of_2((uint32_t)p_max_size + (uint32_t)4));
}

int PacketPeerStream::get_output_buffer_max_size() const {
	return output_buffer.size() - 4;
}

PacketPeerStream::PacketPeerStream() {
	int64_t rbsize = GLOBAL_GET("network/limits/packet_peer_stream/max_buffer_po2");

	ring_buffer.resize(rbsize);
	input_buffer.resize(int64_t(1) << rbsize);
	output_buffer.resize(int64_t(1) << rbsize);
}
