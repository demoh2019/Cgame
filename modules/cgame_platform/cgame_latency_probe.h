/**************************************************************************/
/*  cgame_latency_probe.h                                                 */
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
#include "core/variant/typed_array.h"

// Input-to-photon latency bookkeeping (normal rendering vs frame generation).
//
// The probe records one sample per discrete input and completes it when the host reports that the response frame
// was submitted. A software estimate is `(draw - input) + display_ms`; a hardware photodiode edge, when paired to
// the sample, wins over the estimate. The class does no rendering of its own: the host flips its corner rectangle
// while is_flash_on() returns true and calls mark_draw() after each presented frame.
class CgameLatencyProbe : public RefCounted {
	GDCLASS(CgameLatencyProbe, RefCounted);

public:
	static constexpr int64_t DEFAULT_MAX_GAP_US = 500000;

private:
	String mode = "normal";
	int flash_frames = 3;
	double min_gap_ms = 80.0;
	double display_offset_ms = 0.0;
	bool capture_enabled = true;
	Array samples;
	Vector<int> pending;
	int flash_left = 0;
	int64_t last_input_us = -1000000000;

protected:
	static void _bind_methods();

public:
	void set_mode(const String &p_mode) { mode = p_mode; }
	String get_mode() const { return mode; }
	void set_flash_frames(int p_frames) { flash_frames = MAX(p_frames, 1); }
	int get_flash_frames() const { return flash_frames; }
	void set_min_gap_ms(double p_ms) { min_gap_ms = p_ms; }
	double get_min_gap_ms() const { return min_gap_ms; }
	void set_display_offset_ms(double p_ms) { display_offset_ms = p_ms; }
	double get_display_offset_ms() const { return display_offset_ms; }
	void set_capture_enabled(bool p_enabled) { capture_enabled = p_enabled; }
	bool is_capture_enabled() const { return capture_enabled; }
	Array get_samples() const { return samples; }

	int mark_input(int64_t p_now_us = -1);
	int mark_draw(int64_t p_now_us = -1);
	bool is_flash_on() const { return flash_left > 0; }
	int get_pending_count() const { return pending.size(); }
	void clear();

	int import_photodiode_csv(const String &p_path, int64_t p_clock_offset_us = 0);
	Dictionary report(double p_refresh_hz = -1.0) const;
	double estimate_display_ms(double p_refresh_hz = -1.0) const;
	bool save_report(const String &p_path, double p_refresh_hz = -1.0) const;

	static double latency_ms(const Dictionary &p_sample, double p_display_ms);
	static double percentile(const PackedFloat64Array &p_sorted, double p_percent);
	static Dictionary summarize(const Array &p_samples, double p_display_ms);
	static int pair_photodiode(const Array &p_samples, const PackedInt64Array &p_edges_us, int64_t p_clock_offset_us = 0, int64_t p_max_gap_us = DEFAULT_MAX_GAP_US);
};
