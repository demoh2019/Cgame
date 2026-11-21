/**************************************************************************/
/*  cgame_physics_timeline.cpp                                            */
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

#include "cgame_physics_timeline.h"

#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/os/os.h"

static const char *const TIMELINE_PHASES[4] = { "broadphase", "narrowphase", "solve", "integrate" };

int64_t CgamePhysicsTimeline::StepRecord::phase_us(const String &p_phase) const {
	int64_t total = 0;
	for (const PhaseRecord &e : phases) {
		if (e.name == p_phase) {
			total += e.dur_us;
		}
	}
	return total;
}

Dictionary CgamePhysicsTimeline::_record_to_dictionary(const StepRecord &p_record) {
	Dictionary d;
	d["step"] = p_record.step;
	d["start_us"] = p_record.start_us;
	d["dur_us"] = p_record.dur_us;
	Array phases;
	for (const PhaseRecord &e : p_record.phases) {
		Dictionary pd;
		pd["name"] = e.name;
		pd["start_us"] = e.start_us;
		pd["dur_us"] = e.dur_us;
		phases.push_back(pd);
	}
	d["phases"] = phases;
	d["contacts"] = p_record.contacts;
	d["pairs"] = p_record.pairs;
	d["sleeping"] = p_record.sleeping;
	d["bodies"] = p_record.bodies;
	return d;
}

void CgamePhysicsTimeline::clear() {
	ring.clear();
	current = StepRecord();
	has_current = false;
}

Array CgamePhysicsTimeline::records() const {
	Array out;
	for (const StepRecord &r : ring) {
		out.push_back(_record_to_dictionary(r));
	}
	return out;
}

void CgamePhysicsTimeline::on_step_begin(int64_t p_step) {
	begin_step(p_step);
}

void CgamePhysicsTimeline::on_phase_begin(const char *p_phase) {
	begin_phase(String::utf8(p_phase));
}

void CgamePhysicsTimeline::on_phase_end() {
	end_phase();
}

void CgamePhysicsTimeline::on_step_end(const CgamePhysicsCore::StepStats &p_stats) {
	if (!has_current) {
		return;
	}
	current.contacts = p_stats.contacts;
	current.pairs = p_stats.pairs;
	current.sleeping = p_stats.sleeping;
	current.bodies = p_stats.bodies;
	current.dur_us = int64_t(OS::get_singleton()->get_ticks_usec()) - current.start_us;
	ring.push_back(current);
	while (ring.size() > MAX(capacity, int64_t(1))) {
		ring.pop_front();
	}
	current = StepRecord();
	has_current = false;
}

void CgamePhysicsTimeline::begin_step(int64_t p_step_index) {
	current = StepRecord();
	current.step = p_step_index;
	current.start_us = int64_t(OS::get_singleton()->get_ticks_usec());
	has_current = true;
}

void CgamePhysicsTimeline::begin_phase(const String &p_phase) {
	phase_name = p_phase;
	phase_start = int64_t(OS::get_singleton()->get_ticks_usec());
}

void CgamePhysicsTimeline::end_phase() {
	if (!has_current) {
		return;
	}
	int64_t now = int64_t(OS::get_singleton()->get_ticks_usec());
	PhaseRecord pr;
	pr.name = phase_name;
	pr.start_us = phase_start;
	pr.dur_us = now - phase_start;
	current.phases.push_back(pr);
}

// Script-driven end of a step; `p_stats` may carry contacts, pairs, sleeping and bodies counters.
void CgamePhysicsTimeline::end_step(const Dictionary &p_stats) {
	if (!has_current) {
		return;
	}
	CgamePhysicsCore::StepStats st;
	st.contacts = int(p_stats.get("contacts", 0));
	st.pairs = int(p_stats.get("pairs", 0));
	st.sleeping = int(p_stats.get("sleeping", 0));
	st.bodies = int(p_stats.get("bodies", 0));
	on_step_end(st);
}

// Total microseconds spent in `phase` during one recorded step.
int64_t CgamePhysicsTimeline::phase_us(const Dictionary &p_record, const String &p_phase) {
	int64_t total = 0;
	Array phases = p_record.get("phases", Array());
	for (int i = 0; i < phases.size(); i++) {
		Dictionary e = phases[i];
		if (String(e["name"]) == p_phase) {
			total += int64_t(e["dur_us"]);
		}
	}
	return total;
}

PackedStringArray CgamePhysicsTimeline::get_phases() {
	PackedStringArray out;
	for (int i = 0; i < 4; i++) {
		out.push_back(TIMELINE_PHASES[i]);
	}
	return out;
}

Dictionary CgamePhysicsTimeline::report() const {
	int64_t n = ring.size();
	Dictionary out;
	out["steps"] = n;
	out["avg_step_us"] = 0.0;
	out["max_step_us"] = 0;
	out["phases"] = Dictionary();
	out["avg_contacts"] = 0.0;
	out["max_contacts"] = 0;
	out["max_sleeping"] = 0;
	out["last"] = Dictionary();
	if (n == 0) {
		return out;
	}
	int64_t sum_step = 0;
	int64_t max_step = 0;
	int64_t sum_contacts = 0;
	int64_t max_contacts = 0;
	int64_t max_sleeping = 0;
	int64_t phase_sum[4] = { 0, 0, 0, 0 };
	int64_t phase_max[4] = { 0, 0, 0, 0 };
	for (const StepRecord &rec : ring) {
		sum_step += rec.dur_us;
		max_step = MAX(max_step, rec.dur_us);
		sum_contacts += rec.contacts;
		max_contacts = MAX(max_contacts, rec.contacts);
		max_sleeping = MAX(max_sleeping, rec.sleeping);
		for (int p = 0; p < 4; p++) {
			int64_t us = rec.phase_us(TIMELINE_PHASES[p]);
			phase_sum[p] += us;
			phase_max[p] = MAX(phase_max[p], us);
		}
	}
	Dictionary phases;
	for (int p = 0; p < 4; p++) {
		Dictionary ph;
		ph["avg_us"] = double(phase_sum[p]) / double(n);
		ph["max_us"] = phase_max[p];
		ph["total_us"] = phase_sum[p];
		phases[TIMELINE_PHASES[p]] = ph;
	}
	out["avg_step_us"] = double(sum_step) / double(n);
	out["max_step_us"] = max_step;
	out["phases"] = phases;
	out["avg_contacts"] = double(sum_contacts) / double(n);
	out["max_contacts"] = max_contacts;
	out["max_sleeping"] = max_sleeping;
	const StepRecord &last = ring.back()->get();
	Dictionary ld;
	ld["step"] = last.step;
	ld["dur_us"] = last.dur_us;
	ld["contacts"] = last.contacts;
	ld["pairs"] = last.pairs;
	ld["sleeping"] = last.sleeping;
	ld["bodies"] = last.bodies;
	out["last"] = ld;
	return out;
}

String CgamePhysicsTimeline::report_text() const {
	Dictionary r = report();
	Vector<String> lines;
	lines.push_back(vformat("physics: %d steps, avg %.1f us, max %d us, contacts avg %.1f max %d, sleeping max %d",
			int64_t(r["steps"]), double(r["avg_step_us"]), int64_t(r["max_step_us"]), double(r["avg_contacts"]),
			int64_t(r["max_contacts"]), int64_t(r["max_sleeping"])));
	Dictionary phases = r["phases"];
	for (int p = 0; p < 4; p++) {
		if (phases.has(TIMELINE_PHASES[p])) {
			Dictionary ph = phases[TIMELINE_PHASES[p]];
			lines.push_back(vformat("  %s avg %8.1f us  max %d us", String(TIMELINE_PHASES[p]).rpad(12),
					double(ph["avg_us"]), int64_t(ph["max_us"])));
		}
	}
	return String("\n").join(lines);
}

// Chrome trace object. Timestamps are microseconds relative to the oldest recorded step.
Dictionary CgamePhysicsTimeline::to_trace() const {
	Array events;
	{
		Dictionary args;
		args["name"] = "physics";
		Dictionary e;
		e["name"] = "process_name";
		e["ph"] = "M";
		e["pid"] = 1;
		e["tid"] = 1;
		e["args"] = args;
		events.push_back(e);
	}
	{
		Dictionary args;
		args["name"] = "step";
		Dictionary e;
		e["name"] = "thread_name";
		e["ph"] = "M";
		e["pid"] = 1;
		e["tid"] = 1;
		e["args"] = args;
		events.push_back(e);
	}
	Dictionary trace;
	trace["displayTimeUnit"] = "ms";
	if (ring.is_empty()) {
		trace["traceEvents"] = events;
		return trace;
	}
	int64_t origin = ring.front()->get().start_us;
	for (const StepRecord &rec : ring) {
		int64_t start = rec.start_us - origin;
		Dictionary args;
		args["contacts"] = rec.contacts;
		args["pairs"] = rec.pairs;
		args["sleeping"] = rec.sleeping;
		args["bodies"] = rec.bodies;
		Dictionary e;
		e["name"] = vformat("step %d", rec.step);
		e["cat"] = "physics";
		e["ph"] = "X";
		e["ts"] = start;
		e["dur"] = rec.dur_us;
		e["pid"] = 1;
		e["tid"] = 1;
		e["args"] = args;
		events.push_back(e);
		for (const PhaseRecord &ph : rec.phases) {
			Dictionary pe;
			pe["name"] = ph.name;
			pe["cat"] = "physics.phase";
			pe["ph"] = "X";
			pe["ts"] = ph.start_us - origin;
			pe["dur"] = ph.dur_us;
			pe["pid"] = 1;
			pe["tid"] = 1;
			events.push_back(pe);
		}
		Dictionary cargs;
		cargs["contacts"] = rec.contacts;
		cargs["sleeping"] = rec.sleeping;
		Dictionary ce;
		ce["name"] = "contacts";
		ce["ph"] = "C";
		ce["ts"] = start;
		ce["pid"] = 1;
		ce["tid"] = 1;
		ce["args"] = cargs;
		events.push_back(ce);
	}
	trace["traceEvents"] = events;
	return trace;
}

String CgamePhysicsTimeline::export_json() const {
	return JSON::stringify(to_trace());
}

void CgamePhysicsTimeline::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_capacity", "capacity"), &CgamePhysicsTimeline::set_capacity);
	ClassDB::bind_method(D_METHOD("get_capacity"), &CgamePhysicsTimeline::get_capacity);
	ClassDB::bind_method(D_METHOD("clear"), &CgamePhysicsTimeline::clear);
	ClassDB::bind_method(D_METHOD("record_count"), &CgamePhysicsTimeline::record_count);
	ClassDB::bind_method(D_METHOD("records"), &CgamePhysicsTimeline::records);
	ClassDB::bind_method(D_METHOD("begin_step", "step_index"), &CgamePhysicsTimeline::begin_step);
	ClassDB::bind_method(D_METHOD("begin_phase", "phase"), &CgamePhysicsTimeline::begin_phase);
	ClassDB::bind_method(D_METHOD("end_phase"), &CgamePhysicsTimeline::end_phase);
	ClassDB::bind_method(D_METHOD("end_step", "stats"), &CgamePhysicsTimeline::end_step);
	ClassDB::bind_static_method("CgamePhysicsTimeline", D_METHOD("phase_us", "record", "phase"), &CgamePhysicsTimeline::phase_us);
	ClassDB::bind_static_method("CgamePhysicsTimeline", D_METHOD("get_phases"), &CgamePhysicsTimeline::get_phases);
	ClassDB::bind_method(D_METHOD("report"), &CgamePhysicsTimeline::report);
	ClassDB::bind_method(D_METHOD("report_text"), &CgamePhysicsTimeline::report_text);
	ClassDB::bind_method(D_METHOD("to_trace"), &CgamePhysicsTimeline::to_trace);
	ClassDB::bind_method(D_METHOD("export_json"), &CgamePhysicsTimeline::export_json);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "capacity", PROPERTY_HINT_RANGE, "1,100000,1,or_greater"), "set_capacity", "get_capacity");
}
