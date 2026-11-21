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
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "delay"), "", "get_delay");
	ClassDB::bind_method(D_METHOD("get_stats"), &AdaptiveNetworkJitterBuffer::get_stats);
}

void AdaptiveNetworkJitterBuffer::_reset_timing() {
	delay = base_delay;
	peak_jitter = 0.0;
	last_server_time = -1.0;
	last_arrival_time = -1.0;
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
		network_gap_count++;
		return delay;
	}
	const double late = MAX(0.0, arrival_span - server_span);
	const double skipped = MAX(0.0, server_span - expected_snapshot_step);
	const double extra = MIN(0.17, MAX(late, skipped));
	peak_jitter = MAX(extra, MAX(0.0, peak_jitter - arrival_span * 0.04));
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
	stats["expected_snapshot_step"] = expected_snapshot_step;
	stats["native_backend"] = true;
	return stats;
}
