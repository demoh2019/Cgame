/**************************************************************************/
/*  stream_replication.h                                                  */
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

#include "core/math/vector2i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/variant/typed_array.h"

// Replication of streaming state: delta-encoded (XOR) ready-cell bitsets over a window
// centred on the client cell, acknowledged by the server.
class StreamReplication : public RefCounted {
	GDCLASS(StreamReplication, RefCounted);

public:
	static constexpr int HEADER_BYTES = 17;

	using CellSet = HashSet<Vector2i>;

	struct ClientState {
		Vector2i position;
		bool has_position = false;
		int64_t version = 0;
		CellSet effective;
		HashMap<int64_t, CellSet> history;
		int violations = 0;
		bool flagged = false;
	};

private:
	int allowed_radius = 6;
	int max_report_radius = 8;
	int max_center_error = 2;
	int history_size = 8;
	int violation_limit = 8;
	HashMap<Variant, ClientState, HashMapHasherDefault, StringLikeVariantComparator> clients;

	ClientState &_state(const Variant &p_client);
	void _violate(ClientState &p_state);

protected:
	static void _bind_methods();

public:
	static int window_side(int p_radius);
	static int bit_index(const Vector2i &p_center, int p_radius, const Vector2i &p_cell);
	static bool in_window(const Vector2i &p_center, int p_radius, const Vector2i &p_cell);
	static int bytes_for(int p_radius);
	static PackedByteArray encode_set(const Vector2i &p_center, int p_radius, const CellSet &p_cells);
	static void decode_set(const Vector2i &p_center, int p_radius, const PackedByteArray &p_bits, CellSet &r_cells);
	static PackedByteArray encode_cells(const Vector2i &p_center, int p_radius, const Dictionary &p_cells);
	static Dictionary decode_cells(const Vector2i &p_center, int p_radius, const PackedByteArray &p_bits);
	static PackedByteArray serialize(const Dictionary &p_packet);
	static Dictionary deserialize(const PackedByteArray &p_buffer);

	void set_allowed_radius(int p_radius);
	int get_allowed_radius() const;
	void set_max_report_radius(int p_radius);
	int get_max_report_radius() const;
	void set_max_center_error(int p_error);
	int get_max_center_error() const;
	void set_history_size(int p_size);
	int get_history_size() const;
	void set_violation_limit(int p_limit);
	int get_violation_limit() const;

	void set_client_position(const Variant &p_client, const Vector2i &p_cell);
	void remove_client(const Variant &p_client);
	Dictionary apply_report(const Variant &p_client, const Dictionary &p_packet);
	int64_t ack_version(const Variant &p_client);
	Dictionary ready_set(const Variant &p_client);
	bool is_ready(const Variant &p_client, const Vector2i &p_cell);
	int violations(const Variant &p_client);
	bool is_flagged(const Variant &p_client);
	TypedArray<Vector2i> server_relevant(const Variant &p_client, const TypedArray<Vector2i> &p_cells_of_interest);
	TypedArray<Vector2i> server_missing(const Variant &p_client, const TypedArray<Vector2i> &p_cells_of_interest);
};

// Client side: tracks ready cells and builds delta reports.
class StreamReplicationClient : public RefCounted {
	GDCLASS(StreamReplicationClient, RefCounted);

	int radius = 6;
	int64_t version = 0;
	int64_t acked_version = 0;
	StreamReplication::CellSet ready;
	StreamReplication::CellSet acked;
	HashMap<int64_t, StreamReplication::CellSet> pending;
	bool force_full = false;

protected:
	static void _bind_methods();

public:
	void set_radius(int p_radius);
	int get_radius() const;
	int64_t get_version() const;
	int64_t get_acked_version() const;

	void set_ready(const Vector2i &p_cell, bool p_ready);
	void request_full();
	Dictionary build_report(const Vector2i &p_center);
	void on_ack(int64_t p_acked);
};
