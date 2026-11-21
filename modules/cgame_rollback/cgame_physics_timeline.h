/**************************************************************************/
/*  cgame_physics_timeline.h                                              */
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

#include "cgame_physics_core.h"

#include "core/object/ref_counted.h"
#include "core/string/ustring.h"
#include "core/templates/list.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"

// Physics timeline profiler: per-step wall-clock timings by phase (broadphase, narrowphase, solve,
// integrate), contact / pair / sleeping counters, a bounded ring buffer, an aggregated report() and a Chrome
// trace (chrome://tracing, Perfetto) export: {"traceEvents": [...]}.
//
// Attach to a CgameDeterministicPhysics with set_timeline(). Timings are wall clock and are never part of the
// simulation state, so profiling cannot affect determinism.
class CgamePhysicsTimeline : public RefCounted, public CgamePhysicsCore::StepObserver {
	GDCLASS(CgamePhysicsTimeline, RefCounted);

	struct PhaseRecord {
		String name;
		int64_t start_us = 0;
		int64_t dur_us = 0;
	};

	struct StepRecord {
		int64_t step = 0;
		int64_t start_us = 0;
		int64_t dur_us = 0;
		Vector<PhaseRecord> phases;
		int64_t contacts = 0;
		int64_t pairs = 0;
		int64_t sleeping = 0;
		int64_t bodies = 0;

		int64_t phase_us(const String &p_phase) const;
	};

	int64_t capacity = 240;

	List<StepRecord> ring;
	StepRecord current;
	bool has_current = false;
	String phase_name;
	int64_t phase_start = 0;

	static Dictionary _record_to_dictionary(const StepRecord &p_record);

protected:
	static void _bind_methods();

public:
	// CgamePhysicsCore::StepObserver
	void on_step_begin(int64_t p_step) override;
	void on_phase_begin(const char *p_phase) override;
	void on_phase_end() override;
	void on_step_end(const CgamePhysicsCore::StepStats &p_stats) override;

	void set_capacity(int64_t p_capacity) { capacity = p_capacity; }
	int64_t get_capacity() const { return capacity; }

	void clear();
	int64_t record_count() const { return ring.size(); }
	Array records() const;

	void begin_step(int64_t p_step_index);
	void begin_phase(const String &p_phase);
	void end_phase();
	void end_step(const Dictionary &p_stats);

	static int64_t phase_us(const Dictionary &p_record, const String &p_phase);
	static PackedStringArray get_phases();

	Dictionary report() const;
	String report_text() const;
	Dictionary to_trace() const;
	String export_json() const;
};
