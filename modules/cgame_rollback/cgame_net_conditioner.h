/**************************************************************************/
/*  cgame_net_conditioner.h                                               */
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

#include "core/math/random_pcg.h"
#include "core/object/ref_counted.h"
#include "core/string/ustring.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Network condition simulator: latency, jitter, loss, duplication, reordering and a bandwidth cap (single FIFO
// link with a bounded queue), with a per-packet log and timeline.
//
// Time unit: `now` and all *_at stamps are in SECONDS; latency/jitter are in milliseconds. Deterministic: the
// same seed and the same send sequence always yield the same log.
//
// Packet model: loss roll -> bandwidth queue (serialization delay, drop when the backlog exceeds max_queue_ms)
// -> delay = latency + uniform jitter in [-jitter, +jitter] (>= 0) -> optional reorder extra delay -> optional
// duplicate copy.
class CgameNetConditioner : public RefCounted {
	GDCLASS(CgameNetConditioner, RefCounted);

	struct LogEntry {
		int64_t id = 0;
		Variant channel;
		int64_t size = 0;
		double sent_at = 0.0;
		double delivered_at = -1.0;
		bool dropped = false;
		String reason = "ok";
		bool duplicated = false;
		bool reordered = false;
		double base_ms = 0.0;
		double jitter_ms = 0.0;
		double queue_ms = 0.0;
		double tx_ms = 0.0;
		double reorder_ms = 0.0;
	};

	struct PendingPacket {
		int64_t id = 0;
		Variant channel;
		PackedByteArray bytes;
		double sent_at = 0.0;
		double delivered_at = 0.0;
	};

	struct PendingLess {
		bool operator()(const PendingPacket &p_a, const PendingPacket &p_b) const {
			if (p_a.delivered_at != p_b.delivered_at) {
				return p_a.delivered_at < p_b.delivered_at;
			}
			return p_a.id < p_b.id;
		}
	};

	double latency_ms = 0.0;
	double jitter_ms = 0.0;
	double loss = 0.0;
	double duplicate = 0.0;
	double reorder = 0.0;
	double bandwidth_kbps = 0.0; // 0 = unlimited
	double max_queue_ms = 1000.0;

	RandomPCG rng;
	Vector<LogEntry> log; // index == packet id
	Vector<PendingPacket> pending;
	double link_free = 0.0;
	double max_delivered = -1.0;

	static Dictionary _entry_to_dictionary(const LogEntry &p_entry);

protected:
	static void _bind_methods();

public:
	void configure(const Dictionary &p_config);
	int64_t send(const Variant &p_channel, const PackedByteArray &p_bytes, double p_now);
	Array receive(double p_now);
	int64_t packet_count() const { return log.size(); }
	Dictionary packet(int64_t p_id) const;
	int64_t pending_count() const { return pending.size(); }
	Array timeline(double p_t0, double p_t1) const;
	Dictionary stats() const;
	String delay_cause(int64_t p_packet_id) const;

	double get_latency_ms() const { return latency_ms; }
	double get_jitter_ms() const { return jitter_ms; }
	double get_loss() const { return loss; }
	double get_duplicate() const { return duplicate; }
	double get_reorder() const { return reorder; }
	double get_bandwidth_kbps() const { return bandwidth_kbps; }
	double get_max_queue_ms() const { return max_queue_ms; }
};
