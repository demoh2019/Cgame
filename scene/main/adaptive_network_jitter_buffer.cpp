/**************************************************************************/
/*  adaptive_network_jitter_buffer.cpp                                              */
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

#include "adaptive_network_jitter_buffer.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void AdaptiveNetworkJitterBuffer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "base_delay", "max_delay", "expected_snapshot_step"),
			&AdaptiveNetworkJitterBuffer::configure);
	ClassDB::bind_method(D_METHOD("reset"), &AdaptiveNetworkJitterBuffer::reset);
	ClassDB::bind_method(D_METHOD("observe", "server_time", "local_arrival_time"),
			&AdaptiveNetworkJitterBuffer::observe);
	ClassDB::bind_method(D_METHOD("get_delay"), &AdaptiveNetworkJitterBuffer::get_delay);
	ClassDB::bind_method(D_METHOD("set_recovery_guard_packets", "packets"), &AdaptiveNetworkJitterBuffer::set_recovery_guard_packets);
	ClassDB::bind_method(D_METHOD("get_recovery_guard_packets"), &AdaptiveNetworkJitterBuffer::get_recovery_guard_packets);
	ClassDB::bind_method(D_METHOD("get_recovery_hold_remaining"), &AdaptiveNetworkJitterBuffer::get_recovery_hold_remaining);
	ClassDB::bind_method(D_METHOD("get_estimated_missing_snapshots"), &AdaptiveNetworkJitterBuffer::get_estimated_missing_snapshots);
	ClassDB::bind_method(D_METHOD("get_burst_loss_events"), &AdaptiveNetworkJitterBuffer::get_burst_loss_events);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "recovery_guard_packets", PROPERTY_HINT_RANGE, "0,32,1"), "set_recovery_guard_packets", "get_recovery_guard_packets");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "delay"), "", "get_delay");
	ClassDB::bind_method(D_METHOD("get_stats"), &AdaptiveNetworkJitterBuffer::get_stats);
}

void AdaptiveNetworkJitterBuffer::_reset_timing() {
	delay = base_delay;
	peak_jitter = 0.0;
	last_server_time = -1.0;
	last_arrival_time = -1.0;
	recovery_hold_remaining = 0;
}

bool AdaptiveNetworkJitterBuffer::configure(double p_base_delay, double p_max_delay, double p_expected_snapshot_step) {
	// Prevent nonsensical network clocks and unlimited visual latency.
	if (!Math::is_finite(p_base_delay) || !Math::is_finite(p_max_delay) ||
			!Math::is_finite(p_expected_snapshot_step) ||
			p_base_delay < 0.01 || p_base_delay > 1.0 ||
			p_max_delay < p_base_delay || p_max_delay > 1.0 ||
			p_expected_snapshot_step < 0.01 || p_expected_snapshot_step > 1.0) {
		return false;
	}
	base_delay = p_base_delay;
	max_delay = p_max_delay;
	expected_snapshot_step = p_expected_snapshot_step;
	reset();
	return true;
}

void AdaptiveNetworkJitterBuffer::reset() {
	_reset_timing();
	accepted_packets = 0;
	ignored_packets = 0;
	resets = 0;
	network_gap_count = 0;
	estimated_missing_snapshots = 0;
	burst_loss_events = 0;
}

bool AdaptiveNetworkJitterBuffer::set_recovery_guard_packets(int p_packets) {
	if (p_packets < 0 || p_packets > 32) {
		return false;
	}
	recovery_guard_packets = p_packets;
	recovery_hold_remaining = 0;
	return true;
}

double AdaptiveNetworkJitterBuffer::observe(double p_server_time, double p_local_arrival_time) {
	if (!Math::is_finite(p_server_time) || !Math::is_finite(p_local_arrival_time) ||
			p_server_time < 0.0 || p_local_arrival_time < 0.0) {
		ignored_packets++;
		return delay;
	}
	if (last_server_time >= 0.0 && p_server_time <= last_server_time &&
			p_server_time >= last_server_time - 0.5) {
		// Duplicate/out-of-order frame reads are not new packet arrivals.
		ignored_packets++;
		return delay;
	}
	if (last_server_time < 0.0 || p_server_time < last_server_time - 0.5 ||
			p_local_arrival_time < last_arrival_time ||
			p_local_arrival_time - last_arrival_time > 2.0) {
		if (last_server_time >= 0.0) {
			resets++;
		}
		_reset_timing();
		last_server_time = p_server_time;
		last_arrival_time = p_local_arrival_time;
		accepted_packets++;
		return delay;
	}
	if (p_server_time <= last_server_time) {
		ignored_packets++;
		return delay;
	}

	const double server_span = p_server_time - last_server_time;
	const double arrival_span = p_local_arrival_time - last_arrival_time;
	last_server_time = p_server_time;
	last_arrival_time = p_local_arrival_time;
	accepted_packets++;

	if (server_span > 0.65) {
		// A reconnect or large packet gap should not keep stale pressure.
		peak_jitter = 0.0;
		delay = base_delay;
		recovery_hold_remaining = 0; // Large reconnect gap ends any old loss burst.
		network_gap_count++;
		return delay;
	}
	const double late = MAX(0.0, arrival_span - server_span);
	const double skipped = MAX(0.0, server_span - expected_snapshot_step);
	// Distinguish likely missing *server* snapshots from a late arrival
	// of a continuous stream. A cadence change can also look like loss,
	// hence this is an estimate, not an authoritative packet-loss count.
	const int missing = CLAMP(int(Math::floor(server_span / expected_snapshot_step + 0.5)) - 1, 0, 32);
	if (missing > 0) {
		estimated_missing_snapshots = MIN(int64_t(1000000000),
				estimated_missing_snapshots + int64_t(missing));
		burst_loss_events = MIN(int64_t(1000000000), burst_loss_events + 1);
		recovery_hold_remaining = recovery_guard_packets;
	}
	const double extra = MIN(0.17, MAX(late, skipped));
	// A loss burst may be followed by clean packets before the connection
	// has actually stabilized. Require several genuine arrivals before
	// releasing the jitter peak; duplicate renders never advance the guard.
	const bool hold = missing == 0 && recovery_hold_remaining > 0;
	const double release = hold ? 0.0 : arrival_span * 0.04;
	peak_jitter = MAX(extra, MAX(0.0, peak_jitter - release));
	if (hold) {
		--recovery_hold_remaining;
	}
	const double target = CLAMP(base_delay + peak_jitter * 1.35, base_delay, max_delay);
	if (target > delay) {
		delay = target;
	} else {
		delay = MAX(target, delay - arrival_span * 0.03);
	}
	return delay;
}

Dictionary AdaptiveNetworkJitterBuffer::get_stats() const {
	Dictionary stats;
	stats["delay"] = delay;
	stats["peak_jitter"] = peak_jitter;
	stats["accepted_packets"] = accepted_packets;
	stats["ignored_packets"] = ignored_packets;
	stats["resets"] = resets;
	stats["network_gaps"] = network_gap_count;
	stats["recovery_guard_packets"] = recovery_guard_packets;
	stats["recovery_hold_remaining"] = recovery_hold_remaining;
	stats["estimated_missing_snapshots"] = estimated_missing_snapshots;
	stats["burst_loss_events"] = burst_loss_events;
	stats["expected_snapshot_step"] = expected_snapshot_step;
	stats["native_backend"] = true;
	return stats;
}
