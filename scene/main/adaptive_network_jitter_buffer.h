/**************************************************************************/
/*  adaptive_network_jitter_buffer.h                                              */
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

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

// Presentation-only jitter buffer for server-authoritative visual proxies.
// Inspired by Unreal simulated proxy network smoothing: it tracks packet
// arrival variance but never predicts new positions or mutates physics.
class AdaptiveNetworkJitterBuffer : public RefCounted {
	GDCLASS(AdaptiveNetworkJitterBuffer, RefCounted);

	double base_delay = 0.12;
	double max_delay = 0.35;
	double expected_snapshot_step = 0.10;
	double delay = 0.12;
	double peak_jitter = 0.0;
	double last_server_time = -1.0;
	double last_arrival_time = -1.0;
	int64_t accepted_packets = 0;
	int64_t ignored_packets = 0;
	int64_t resets = 0;
	int64_t network_gap_count = 0;

	void _reset_timing();

protected:
	static void _bind_methods();

public:
	// Optional per-project snapshot cadence and buffering range. Keeps
	// default 10Hz/120ms values used by Albion After.
	bool configure(double p_base_delay, double p_max_delay, double p_expected_snapshot_step);
	void reset();
	double observe(double p_server_time, double p_local_arrival_time);
	double get_delay() const { return delay; }
	Dictionary get_stats() const;
};
