/**************************************************************************/
/*  cgame_net_conditioner.cpp                                             */
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

#include "cgame_net_conditioner.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

#include <limits>

Dictionary CgameNetConditioner::_entry_to_dictionary(const LogEntry &p_entry) {
	Dictionary d;
	d["id"] = p_entry.id;
	d["channel"] = p_entry.channel;
	d["size"] = p_entry.size;
	d["sent_at"] = p_entry.sent_at;
	d["delivered_at"] = p_entry.delivered_at;
	d["dropped"] = p_entry.dropped;
	d["reason"] = p_entry.reason;
	d["duplicated"] = p_entry.duplicated;
	d["reordered"] = p_entry.reordered;
	d["base_ms"] = p_entry.base_ms;
	d["jitter_ms"] = p_entry.jitter_ms;
	d["queue_ms"] = p_entry.queue_ms;
	d["tx_ms"] = p_entry.tx_ms;
	d["reorder_ms"] = p_entry.reorder_ms;
	return d;
}

void CgameNetConditioner::configure(const Dictionary &p_config) {
	latency_ms = MAX(0.0, double(p_config.get("latency_ms", 0.0)));
	jitter_ms = MAX(0.0, double(p_config.get("jitter_ms", 0.0)));
	loss = CLAMP(double(p_config.get("loss", 0.0)), 0.0, 1.0);
	duplicate = CLAMP(double(p_config.get("duplicate", 0.0)), 0.0, 1.0);
	reorder = CLAMP(double(p_config.get("reorder", 0.0)), 0.0, 1.0);
	bandwidth_kbps = MAX(0.0, double(p_config.get("bandwidth_kbps", 0.0)));
	max_queue_ms = MAX(1.0, double(p_config.get("max_queue_ms", 1000.0)));
	rng.seed(uint64_t(int64_t(p_config.get("seed", 1))));
	log.clear();
	pending.clear();
	link_free = 0.0;
	max_delivered = -1.0;
}

// Submits a packet at time `now` (seconds). Returns its packet id.
int64_t CgameNetConditioner::send(const Variant &p_channel, const PackedByteArray &p_bytes, double p_now) {
	int64_t id = log.size();
	LogEntry entry;
	entry.id = id;
	entry.channel = p_channel;
	entry.size = p_bytes.size();
	entry.sent_at = p_now;
	entry.base_ms = latency_ms;
	// Fixed roll order keeps the RNG stream aligned regardless of outcomes.
	double r_loss = rng.randd();
	double r_jitter = rng.random(-1.0, 1.0);
	double r_reorder = rng.randd();
	double r_dup = rng.randd();
	double r_dup_jitter = rng.random(-1.0, 1.0);
	if (r_loss < loss) {
		entry.dropped = true;
		entry.reason = "loss";
		log.push_back(entry);
		return id;
	}
	double depart = p_now;
	if (bandwidth_kbps > 0.0) {
		double backlog = MAX(0.0, link_free - p_now);
		if (backlog * 1000.0 > max_queue_ms) {
			entry.dropped = true;
			entry.reason = "bandwidth";
			log.push_back(entry);
			return id;
		}
		double tx = double(p_bytes.size()) * 8.0 / (bandwidth_kbps * 1000.0);
		depart = p_now + backlog + tx;
		link_free = depart;
		entry.queue_ms = backlog * 1000.0;
		entry.tx_ms = tx * 1000.0;
	}
	double delay_ms = MAX(0.0, latency_ms + r_jitter * jitter_ms);
	entry.jitter_ms = delay_ms - latency_ms;
	double extra_ms = 0.0;
	if (r_reorder < reorder) {
		extra_ms = latency_ms + jitter_ms + 20.0;
		entry.reordered = true;
		entry.reorder_ms = extra_ms;
	}
	double at = depart + (delay_ms + extra_ms) / 1000.0;
	entry.delivered_at = at;
	if (at < max_delivered) {
		entry.reordered = true; // Overtaken by an earlier-sent packet.
	}
	max_delivered = MAX(max_delivered, at);
	PendingPacket pkt;
	pkt.id = id;
	pkt.channel = p_channel;
	pkt.bytes = p_bytes;
	pkt.sent_at = p_now;
	pkt.delivered_at = at;
	pending.push_back(pkt);
	if (r_dup < duplicate) {
		entry.duplicated = true;
		PendingPacket dup = pkt;
		dup.delivered_at = depart + MAX(0.0, latency_ms + r_dup_jitter * jitter_ms + 1.0) / 1000.0;
		pending.push_back(dup);
	}
	log.push_back(entry);
	return id;
}

// Returns packets due by `now`, ordered by delivery time: {channel, bytes, sent_at, delivered_at, id}.
Array CgameNetConditioner::receive(double p_now) {
	Vector<PendingPacket> due;
	Vector<PendingPacket> rest;
	for (const PendingPacket &p : pending) {
		if (p.delivered_at <= p_now) {
			due.push_back(p);
		} else {
			rest.push_back(p);
		}
	}
	pending = rest;
	due.sort_custom<PendingLess>();
	Array out;
	for (const PendingPacket &p : due) {
		Dictionary d;
		d["id"] = p.id;
		d["channel"] = p.channel;
		d["bytes"] = p.bytes;
		d["sent_at"] = p.sent_at;
		d["delivered_at"] = p.delivered_at;
		out.push_back(d);
	}
	return out;
}

Dictionary CgameNetConditioner::packet(int64_t p_id) const {
	if (p_id < 0 || p_id >= log.size()) {
		return Dictionary();
	}
	return _entry_to_dictionary(log[p_id]);
}

// Log entries whose send or delivery time falls in [t0, t1], ordered by send time.
Array CgameNetConditioner::timeline(double p_t0, double p_t1) const {
	Array out;
	for (const LogEntry &e : log) {
		double s = e.sent_at;
		double dl = e.delivered_at;
		if ((s >= p_t0 && s <= p_t1) || (dl >= 0.0 && dl >= p_t0 && dl <= p_t1)) {
			out.push_back(_entry_to_dictionary(e));
		}
	}
	return out;
}

Dictionary CgameNetConditioner::stats() const {
	int64_t sent = log.size();
	int64_t delivered = 0;
	int64_t lost = 0;
	int64_t bw_drop = 0;
	int64_t dups = 0;
	int64_t reord = 0;
	Vector<double> lats;
	int64_t bytes_total = 0;
	double first_sent = std::numeric_limits<double>::infinity();
	double last_at = 0.0;
	for (const LogEntry &e : log) {
		first_sent = MIN(first_sent, e.sent_at);
		if (e.duplicated) {
			dups++;
		}
		if (e.reordered) {
			reord++;
		}
		if (e.dropped) {
			if (e.reason == "loss") {
				lost++;
			} else {
				bw_drop++;
			}
			continue;
		}
		delivered++;
		lats.push_back((e.delivered_at - e.sent_at) * 1000.0);
		bytes_total += e.size;
		last_at = MAX(last_at, e.delivered_at);
	}
	lats.sort();
	double avg = 0.0;
	double p95 = 0.0;
	if (!lats.is_empty()) {
		double sum = 0.0;
		for (double v : lats) {
			sum += v;
		}
		avg = sum / double(lats.size());
		int idx = CLAMP(int(Math::ceil(0.95 * double(lats.size()))) - 1, 0, int(lats.size()) - 1);
		p95 = lats[idx];
	}
	double span = delivered > 0 ? last_at - first_sent : 0.0;
	double thr = span > 0.0 ? double(bytes_total) / span : 0.0;
	Dictionary d;
	d["sent"] = sent;
	d["delivered"] = delivered;
	d["dropped"] = lost + bw_drop;
	d["dropped_loss"] = lost;
	d["dropped_bandwidth"] = bw_drop;
	d["duplicated"] = dups;
	d["reordered"] = reord;
	d["avg_latency_ms"] = avg;
	d["p95_latency_ms"] = p95;
	d["throughput_bps"] = thr;
	return d;
}

// Human-readable breakdown of why a packet took the time it did (or why it was dropped).
String CgameNetConditioner::delay_cause(int64_t p_packet_id) const {
	if (p_packet_id < 0 || p_packet_id >= log.size()) {
		return vformat("unknown packet %d", p_packet_id);
	}
	const LogEntry &d = log[p_packet_id];
	if (d.dropped) {
		if (d.reason == "loss") {
			return vformat("packet %d dropped by random loss (%.1f%%)", p_packet_id, loss * 100.0);
		}
		return vformat("packet %d dropped: bandwidth queue over %.0f ms at %.0f kbps", p_packet_id, max_queue_ms, bandwidth_kbps);
	}
	Vector<String> parts;
	parts.push_back(vformat("base latency %.1f ms", d.base_ms));
	if (Math::abs(d.jitter_ms) > 0.0005) {
		parts.push_back(String("jitter ") + (d.jitter_ms >= 0.0 ? "+" : "-") + String::num(Math::abs(d.jitter_ms), 1) + " ms");
	}
	if (d.queue_ms > 0.0005) {
		parts.push_back(vformat("queued %.1f ms behind bandwidth cap", d.queue_ms));
	}
	if (d.tx_ms > 0.0005) {
		parts.push_back(vformat("serialization %.1f ms", d.tx_ms));
	}
	if (d.reorder_ms > 0.0005) {
		parts.push_back(vformat("reorder hold %.1f ms", d.reorder_ms));
	}
	double total = (d.delivered_at - d.sent_at) * 1000.0;
	return vformat("packet %d total %.1f ms = %s", p_packet_id, total, String(" + ").join(parts));
}

void CgameNetConditioner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "config"), &CgameNetConditioner::configure);
	ClassDB::bind_method(D_METHOD("send", "channel", "bytes", "now"), &CgameNetConditioner::send);
	ClassDB::bind_method(D_METHOD("receive", "now"), &CgameNetConditioner::receive);
	ClassDB::bind_method(D_METHOD("packet_count"), &CgameNetConditioner::packet_count);
	ClassDB::bind_method(D_METHOD("packet", "id"), &CgameNetConditioner::packet);
	ClassDB::bind_method(D_METHOD("pending_count"), &CgameNetConditioner::pending_count);
	ClassDB::bind_method(D_METHOD("timeline", "t0", "t1"), &CgameNetConditioner::timeline);
	ClassDB::bind_method(D_METHOD("stats"), &CgameNetConditioner::stats);
	ClassDB::bind_method(D_METHOD("delay_cause", "packet_id"), &CgameNetConditioner::delay_cause);

	ClassDB::bind_method(D_METHOD("get_latency_ms"), &CgameNetConditioner::get_latency_ms);
	ClassDB::bind_method(D_METHOD("get_jitter_ms"), &CgameNetConditioner::get_jitter_ms);
	ClassDB::bind_method(D_METHOD("get_loss"), &CgameNetConditioner::get_loss);
	ClassDB::bind_method(D_METHOD("get_duplicate"), &CgameNetConditioner::get_duplicate);
	ClassDB::bind_method(D_METHOD("get_reorder"), &CgameNetConditioner::get_reorder);
	ClassDB::bind_method(D_METHOD("get_bandwidth_kbps"), &CgameNetConditioner::get_bandwidth_kbps);
	ClassDB::bind_method(D_METHOD("get_max_queue_ms"), &CgameNetConditioner::get_max_queue_ms);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "latency_ms"), "", "get_latency_ms");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "jitter_ms"), "", "get_jitter_ms");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "loss"), "", "get_loss");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "duplicate"), "", "get_duplicate");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "reorder"), "", "get_reorder");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bandwidth_kbps"), "", "get_bandwidth_kbps");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_queue_ms"), "", "get_max_queue_ms");
}
