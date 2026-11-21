/**************************************************************************/
/*  stream_replication.cpp                                                */
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

#include "stream_replication.h"

#include "core/io/marshalls.h"
#include "core/object/class_db.h"

int StreamReplication::window_side(int p_radius) {
	return p_radius * 2 + 1;
}

int StreamReplication::bit_index(const Vector2i &p_center, int p_radius, const Vector2i &p_cell) {
	int dx = p_cell.x - p_center.x;
	int dy = p_cell.y - p_center.y;
	if (Math::abs(dx) > p_radius || Math::abs(dy) > p_radius) {
		return -1;
	}
	return (dy + p_radius) * window_side(p_radius) + (dx + p_radius);
}

bool StreamReplication::in_window(const Vector2i &p_center, int p_radius, const Vector2i &p_cell) {
	return bit_index(p_center, p_radius, p_cell) >= 0;
}

int StreamReplication::bytes_for(int p_radius) {
	int n = window_side(p_radius);
	return (n * n + 7) / 8;
}

PackedByteArray StreamReplication::encode_set(const Vector2i &p_center, int p_radius, const CellSet &p_cells) {
	PackedByteArray bits;
	bits.resize(bytes_for(p_radius));
	bits.fill(0);
	uint8_t *w = bits.ptrw();
	for (const Vector2i &cell : p_cells) {
		int i = bit_index(p_center, p_radius, cell);
		if (i >= 0) {
			w[i >> 3] = w[i >> 3] | (1 << (i & 7));
		}
	}
	return bits;
}

void StreamReplication::decode_set(const Vector2i &p_center, int p_radius, const PackedByteArray &p_bits, CellSet &r_cells) {
	int n = window_side(p_radius);
	const uint8_t *r = p_bits.ptr();
	for (int i = 0; i < n * n; i++) {
		if ((r[i >> 3] & (1 << (i & 7))) != 0) {
			r_cells.insert(Vector2i(p_center.x - p_radius + i % n, p_center.y - p_radius + i / n));
		}
	}
}

PackedByteArray StreamReplication::encode_cells(const Vector2i &p_center, int p_radius, const Dictionary &p_cells) {
	CellSet set;
	Array keys = p_cells.keys();
	for (int i = 0; i < keys.size(); i++) {
		set.insert(keys[i]);
	}
	return encode_set(p_center, p_radius, set);
}

Dictionary StreamReplication::decode_cells(const Vector2i &p_center, int p_radius, const PackedByteArray &p_bits) {
	Dictionary out;
	ERR_FAIL_COND_V(p_radius < 0 || p_bits.size() < bytes_for(p_radius), out);
	CellSet set;
	decode_set(p_center, p_radius, p_bits, set);
	for (const Vector2i &c : set) {
		out[c] = true;
	}
	return out;
}

PackedByteArray StreamReplication::serialize(const Dictionary &p_packet) {
	PackedByteArray bits = p_packet["bits"];
	Vector2i center = p_packet["center"];
	PackedByteArray buf;
	buf.resize(HEADER_BYTES);
	uint8_t *w = buf.ptrw();
	encode_uint32((uint32_t)(int64_t)p_packet["v"], w);
	encode_uint32((uint32_t)(int64_t)p_packet["base"], w + 4);
	encode_uint32((uint32_t)center.x, w + 8);
	encode_uint32((uint32_t)center.y, w + 12);
	w[16] = (uint8_t)(int64_t)p_packet["radius"];
	buf.append_array(bits);
	return buf;
}

Dictionary StreamReplication::deserialize(const PackedByteArray &p_buffer) {
	Dictionary out;
	if (p_buffer.size() < HEADER_BYTES) {
		return out;
	}
	const uint8_t *r = p_buffer.ptr();
	int radius = r[16];
	if (p_buffer.size() != HEADER_BYTES + bytes_for(radius)) {
		return out;
	}
	out["v"] = (int64_t)decode_uint32(r);
	out["base"] = (int64_t)decode_uint32(r + 4);
	out["center"] = Vector2i((int32_t)decode_uint32(r + 8), (int32_t)decode_uint32(r + 12));
	out["radius"] = radius;
	out["bits"] = p_buffer.slice(HEADER_BYTES);
	return out;
}

void StreamReplication::set_allowed_radius(int p_radius) {
	allowed_radius = p_radius;
}

int StreamReplication::get_allowed_radius() const {
	return allowed_radius;
}

void StreamReplication::set_max_report_radius(int p_radius) {
	max_report_radius = p_radius;
}

int StreamReplication::get_max_report_radius() const {
	return max_report_radius;
}

void StreamReplication::set_max_center_error(int p_error) {
	max_center_error = p_error;
}

int StreamReplication::get_max_center_error() const {
	return max_center_error;
}

void StreamReplication::set_history_size(int p_size) {
	history_size = MAX(p_size, 1);
}

int StreamReplication::get_history_size() const {
	return history_size;
}

void StreamReplication::set_violation_limit(int p_limit) {
	violation_limit = p_limit;
}

int StreamReplication::get_violation_limit() const {
	return violation_limit;
}

StreamReplication::ClientState &StreamReplication::_state(const Variant &p_client) {
	return clients[p_client];
}

void StreamReplication::_violate(ClientState &p_state) {
	p_state.violations++;
	if (p_state.violations >= violation_limit) {
		p_state.flagged = true;
	}
}

void StreamReplication::set_client_position(const Variant &p_client, const Vector2i &p_cell) {
	ClientState &s = _state(p_client);
	s.position = p_cell;
	s.has_position = true;
}

void StreamReplication::remove_client(const Variant &p_client) {
	clients.erase(p_client);
}

Dictionary StreamReplication::apply_report(const Variant &p_client, const Dictionary &p_packet) {
	ClientState &s = _state(p_client);
	Dictionary res;
	res["ok"] = false;
	res["ack"] = s.version;
	res["reason"] = "";
	res["need_full"] = false;
	res["stripped"] = 0;
	if (p_packet.is_empty() || !p_packet.has("bits")) {
		res["reason"] = "malformed";
		_violate(s);
		return res;
	}
	int radius = p_packet["radius"];
	Vector2i center = p_packet["center"];
	PackedByteArray bits = p_packet["bits"];
	int64_t ver = p_packet["v"];
	int64_t base = p_packet["base"];
	if (radius < 0 || radius > max_report_radius || bits.size() != bytes_for(radius)) {
		res["reason"] = "malformed";
		_violate(s);
		return res;
	}
	if (ver <= s.version) {
		res["reason"] = "old";
		return res;
	}
	if (!s.has_position) {
		res["reason"] = "no_position";
		return res;
	}
	if (MAX(Math::abs(center.x - s.position.x), Math::abs(center.y - s.position.y)) > max_center_error) {
		res["reason"] = "center";
		_violate(s);
		return res;
	}
	CellSet base_set;
	if (base != 0) {
		HashMap<int64_t, CellSet>::Iterator hit = s.history.find(base);
		if (!hit) {
			res["reason"] = "need_full";
			res["need_full"] = true;
			return res;
		}
		base_set = hit->value;
	}
	// raw = (base restricted to the window) XOR delta
	CellSet raw;
	for (const Vector2i &cell : base_set) {
		if (in_window(center, radius, cell)) {
			raw.insert(cell);
		}
	}
	CellSet delta;
	decode_set(center, radius, bits, delta);
	for (const Vector2i &cell : delta) {
		if (raw.has(cell)) {
			raw.erase(cell);
		} else {
			raw.insert(cell);
		}
	}
	CellSet effective;
	int stripped = 0;
	for (const Vector2i &cell : raw) {
		if (MAX(Math::abs(cell.x - s.position.x), Math::abs(cell.y - s.position.y)) > allowed_radius) {
			stripped++;
		} else {
			effective.insert(cell);
		}
	}
	s.version = ver;
	s.effective = effective;
	s.history[ver] = raw;
	while ((int)s.history.size() > history_size) {
		int64_t oldest = INT64_MAX;
		for (const KeyValue<int64_t, CellSet> &kv : s.history) {
			oldest = MIN(oldest, kv.key);
		}
		s.history.erase(oldest);
	}
	res["ok"] = true;
	res["ack"] = ver;
	res["stripped"] = stripped;
	if (stripped > 0) {
		res["reason"] = "stripped";
		_violate(s);
		res["ok"] = true;
	}
	return res;
}

int64_t StreamReplication::ack_version(const Variant &p_client) {
	return _state(p_client).version;
}

Dictionary StreamReplication::ready_set(const Variant &p_client) {
	Dictionary out;
	for (const Vector2i &c : _state(p_client).effective) {
		out[c] = true;
	}
	return out;
}

bool StreamReplication::is_ready(const Variant &p_client, const Vector2i &p_cell) {
	return _state(p_client).effective.has(p_cell);
}

int StreamReplication::violations(const Variant &p_client) {
	return _state(p_client).violations;
}

bool StreamReplication::is_flagged(const Variant &p_client) {
	return _state(p_client).flagged;
}

TypedArray<Vector2i> StreamReplication::server_relevant(const Variant &p_client, const TypedArray<Vector2i> &p_cells_of_interest) {
	ClientState &s = _state(p_client);
	TypedArray<Vector2i> out;
	for (int i = 0; i < p_cells_of_interest.size(); i++) {
		Vector2i cell = p_cells_of_interest[i];
		if (s.effective.has(cell)) {
			out.push_back(cell);
		}
	}
	return out;
}

TypedArray<Vector2i> StreamReplication::server_missing(const Variant &p_client, const TypedArray<Vector2i> &p_cells_of_interest) {
	ClientState &s = _state(p_client);
	TypedArray<Vector2i> out;
	for (int i = 0; i < p_cells_of_interest.size(); i++) {
		Vector2i cell = p_cells_of_interest[i];
		if (!s.effective.has(cell)) {
			out.push_back(cell);
		}
	}
	return out;
}

void StreamReplication::_bind_methods() {
	ClassDB::bind_static_method("StreamReplication", D_METHOD("window_side", "radius"), &StreamReplication::window_side);
	ClassDB::bind_static_method("StreamReplication", D_METHOD("bit_index", "center", "radius", "cell"), &StreamReplication::bit_index);
	ClassDB::bind_static_method("StreamReplication", D_METHOD("in_window", "center", "radius", "cell"), &StreamReplication::in_window);
	ClassDB::bind_static_method("StreamReplication", D_METHOD("bytes_for", "radius"), &StreamReplication::bytes_for);
	ClassDB::bind_static_method("StreamReplication", D_METHOD("encode_cells", "center", "radius", "cells"), &StreamReplication::encode_cells);
	ClassDB::bind_static_method("StreamReplication", D_METHOD("decode_cells", "center", "radius", "bits"), &StreamReplication::decode_cells);
	ClassDB::bind_static_method("StreamReplication", D_METHOD("serialize", "packet"), &StreamReplication::serialize);
	ClassDB::bind_static_method("StreamReplication", D_METHOD("deserialize", "buffer"), &StreamReplication::deserialize);

	ClassDB::bind_method(D_METHOD("set_allowed_radius", "radius"), &StreamReplication::set_allowed_radius);
	ClassDB::bind_method(D_METHOD("get_allowed_radius"), &StreamReplication::get_allowed_radius);
	ClassDB::bind_method(D_METHOD("set_max_report_radius", "radius"), &StreamReplication::set_max_report_radius);
	ClassDB::bind_method(D_METHOD("get_max_report_radius"), &StreamReplication::get_max_report_radius);
	ClassDB::bind_method(D_METHOD("set_max_center_error", "error"), &StreamReplication::set_max_center_error);
	ClassDB::bind_method(D_METHOD("get_max_center_error"), &StreamReplication::get_max_center_error);
	ClassDB::bind_method(D_METHOD("set_history_size", "size"), &StreamReplication::set_history_size);
	ClassDB::bind_method(D_METHOD("get_history_size"), &StreamReplication::get_history_size);
	ClassDB::bind_method(D_METHOD("set_violation_limit", "limit"), &StreamReplication::set_violation_limit);
	ClassDB::bind_method(D_METHOD("get_violation_limit"), &StreamReplication::get_violation_limit);

	ClassDB::bind_method(D_METHOD("set_client_position", "client", "cell"), &StreamReplication::set_client_position);
	ClassDB::bind_method(D_METHOD("remove_client", "client"), &StreamReplication::remove_client);
	ClassDB::bind_method(D_METHOD("apply_report", "client", "packet"), &StreamReplication::apply_report);
	ClassDB::bind_method(D_METHOD("ack_version", "client"), &StreamReplication::ack_version);
	ClassDB::bind_method(D_METHOD("ready_set", "client"), &StreamReplication::ready_set);
	ClassDB::bind_method(D_METHOD("is_ready", "client", "cell"), &StreamReplication::is_ready);
	ClassDB::bind_method(D_METHOD("violations", "client"), &StreamReplication::violations);
	ClassDB::bind_method(D_METHOD("is_flagged", "client"), &StreamReplication::is_flagged);
	ClassDB::bind_method(D_METHOD("server_relevant", "client", "cells_of_interest"), &StreamReplication::server_relevant);
	ClassDB::bind_method(D_METHOD("server_missing", "client", "cells_of_interest"), &StreamReplication::server_missing);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "allowed_radius", PROPERTY_HINT_RANGE, "0,64,1,or_greater"), "set_allowed_radius", "get_allowed_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_report_radius", PROPERTY_HINT_RANGE, "0,64,1,or_greater"), "set_max_report_radius", "get_max_report_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_center_error", PROPERTY_HINT_RANGE, "0,64,1,or_greater"), "set_max_center_error", "get_max_center_error");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "history_size", PROPERTY_HINT_RANGE, "1,256,1,or_greater"), "set_history_size", "get_history_size");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "violation_limit", PROPERTY_HINT_RANGE, "1,1000,1,or_greater"), "set_violation_limit", "get_violation_limit");

	BIND_CONSTANT(HEADER_BYTES);
}

void StreamReplicationClient::set_radius(int p_radius) {
	radius = CLAMP(p_radius, 0, 255);
}

int StreamReplicationClient::get_radius() const {
	return radius;
}

int64_t StreamReplicationClient::get_version() const {
	return version;
}

int64_t StreamReplicationClient::get_acked_version() const {
	return acked_version;
}

void StreamReplicationClient::set_ready(const Vector2i &p_cell, bool p_ready) {
	if (p_ready) {
		ready.insert(p_cell);
	} else {
		ready.erase(p_cell);
	}
}

void StreamReplicationClient::request_full() {
	force_full = true;
}

Dictionary StreamReplicationClient::build_report(const Vector2i &p_center) {
	bool full = force_full || acked_version == 0;
	StreamReplication::CellSet base_set;
	if (!full) {
		base_set = acked;
	}
	StreamReplication::CellSet snap;
	for (const Vector2i &cell : ready) {
		if (StreamReplication::in_window(p_center, radius, cell)) {
			snap.insert(cell);
		}
	}
	StreamReplication::CellSet toggled;
	for (const Vector2i &cell : snap) {
		if (!base_set.has(cell)) {
			toggled.insert(cell);
		}
	}
	for (const Vector2i &cell : base_set) {
		if (StreamReplication::in_window(p_center, radius, cell) && !snap.has(cell)) {
			toggled.insert(cell);
		}
	}
	version++;
	pending[version] = snap;
	force_full = false;
	Dictionary d;
	d["v"] = version;
	d["base"] = full ? 0 : acked_version;
	d["center"] = p_center;
	d["radius"] = radius;
	d["bits"] = StreamReplication::encode_set(p_center, radius, toggled);
	return d;
}

void StreamReplicationClient::on_ack(int64_t p_acked) {
	if (p_acked <= acked_version || !pending.has(p_acked)) {
		return;
	}
	acked = pending[p_acked];
	acked_version = p_acked;
	LocalVector<int64_t> stale;
	for (const KeyValue<int64_t, StreamReplication::CellSet> &kv : pending) {
		if (kv.key <= p_acked) {
			stale.push_back(kv.key);
		}
	}
	for (int64_t v : stale) {
		pending.erase(v);
	}
}

void StreamReplicationClient::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_radius", "radius"), &StreamReplicationClient::set_radius);
	ClassDB::bind_method(D_METHOD("get_radius"), &StreamReplicationClient::get_radius);
	ClassDB::bind_method(D_METHOD("get_version"), &StreamReplicationClient::get_version);
	ClassDB::bind_method(D_METHOD("get_acked_version"), &StreamReplicationClient::get_acked_version);
	ClassDB::bind_method(D_METHOD("set_ready", "cell", "ready"), &StreamReplicationClient::set_ready);
	ClassDB::bind_method(D_METHOD("request_full"), &StreamReplicationClient::request_full);
	ClassDB::bind_method(D_METHOD("build_report", "center"), &StreamReplicationClient::build_report);
	ClassDB::bind_method(D_METHOD("on_ack", "acked"), &StreamReplicationClient::on_ack);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "radius", PROPERTY_HINT_RANGE, "0,255,1"), "set_radius", "get_radius");
}
