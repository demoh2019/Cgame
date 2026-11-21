/**************************************************************************/
/*  vfx_bindings.cpp                                                      */
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

#include "vfx_bindings.h"

#include "core/object/class_db.h"

static bool _is_num(const Variant &p_v) {
	return p_v.get_type() == Variant::INT || p_v.get_type() == Variant::FLOAT;
}

static double _entry_time(const Variant &p_entry) {
	if (p_entry.get_type() != Variant::DICTIONARY) {
		return 0.0;
	}
	const Dictionary d = p_entry;
	return d.has("t") && _is_num(d["t"]) ? (double)d["t"] : 0.0;
}

// ---- VFXSequence -----------------------------------------------------------

void VFXSequence::configure(const Array &p_entries, const Callable &p_spawn, const Vector3 &p_origin, const Dictionary &p_params) {
	entries = p_entries.duplicate(true);
	// Stable insertion sort by "t".
	for (int i = 1; i < entries.size(); i++) {
		const Variant item = entries[i];
		const double t = _entry_time(item);
		int j = i - 1;
		while (j >= 0 && _entry_time(entries[j]) > t) {
			entries[j + 1] = entries[j];
			j--;
		}
		entries[j + 1] = item;
	}
	spawn = p_spawn;
	origin = p_origin;
	base_params = p_params;
	time = 0.0;
	fired = 0;
	cursor = 0;
	duration = 0.0;
	for (int i = 0; i < entries.size(); i++) {
		duration = MAX(duration, _entry_time(entries[i]));
	}
}

int VFXSequence::advance(double p_dt) {
	time += MAX(p_dt, 0.0);
	int count = 0;
	while (cursor < entries.size() && _entry_time(entries[cursor]) <= time) {
		const Variant entry_v = entries[cursor];
		cursor++;
		if (entry_v.get_type() == Variant::DICTIONARY) {
			const Dictionary e = entry_v;
			Dictionary params = base_params.duplicate();
			if (e.has("params") && e["params"].get_type() == Variant::DICTIONARY) {
				params.merge((Dictionary)e["params"], true);
			}
			Vector3 offset;
			if (e.has("offset") && e["offset"].get_type() == Variant::VECTOR3) {
				offset = e["offset"];
			}
			if (spawn.is_valid()) {
				const Variant args[3] = { e.has("effect") ? String(e["effect"]) : String(), origin + offset, params };
				const Variant *argp[3] = { &args[0], &args[1], &args[2] };
				Variant ret;
				Callable::CallError err;
				spawn.callp(argp, 3, ret, err);
			}
		}
		fired++;
		count++;
	}
	return count;
}

void VFXSequence::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "entries", "spawn", "origin", "params"), &VFXSequence::configure, DEFVAL(Vector3()), DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("advance", "dt"), &VFXSequence::advance);
	ClassDB::bind_method(D_METHOD("is_finished"), &VFXSequence::is_finished);
	ClassDB::bind_method(D_METHOD("get_time"), &VFXSequence::get_time);
	ClassDB::bind_method(D_METHOD("get_duration"), &VFXSequence::get_duration);
	ClassDB::bind_method(D_METHOD("get_fired_count"), &VFXSequence::get_fired_count);
	ClassDB::bind_method(D_METHOD("get_origin"), &VFXSequence::get_origin);
}

// ---- VFXBindings -----------------------------------------------------------

void VFXBindings::register_binding(const String &p_event_type, const Dictionary &p_spec) {
	bindings[p_event_type].push_back(p_spec);
}

void VFXBindings::register_sequence(const String &p_name, const Array &p_entries) {
	sequences[p_name] = p_entries;
}

int VFXBindings::get_binding_count() const {
	int n = 0;
	for (const KeyValue<String, Array> &kv : bindings) {
		n += kv.value.size();
	}
	return n;
}

Ref<VFXSequence> VFXBindings::make_sequence(const String &p_name, const Callable &p_spawn, const Vector3 &p_origin, const Dictionary &p_params) const {
	const HashMap<String, Array>::ConstIterator it = sequences.find(p_name);
	if (!it) {
		return Ref<VFXSequence>();
	}
	Ref<VFXSequence> seq;
	seq.instantiate();
	seq->configure(it->value, p_spawn, p_origin, p_params);
	return seq;
}

Dictionary VFXBindings::map_params(const Dictionary &p_mapping, const Dictionary &p_payload) {
	Dictionary out;
	for (const Variant &key : p_mapping.get_key_list()) {
		const Variant m = p_mapping[key];
		if (m.get_type() != Variant::DICTIONARY) {
			out[key] = m;
			continue;
		}
		const Dictionary md = m;
		if (!md.has("from")) {
			out[key] = md.has("value") ? md["value"] : (md.has("default") ? md["default"] : Variant(0.0));
			continue;
		}
		const String src = md["from"];
		const Variant fallback = md.has("default") ? md["default"] : Variant(0.0);
		const Variant raw = p_payload.has(src) ? p_payload[src] : fallback;
		if (_is_num(raw)) {
			double v = (double)raw * (md.has("scale") ? (double)md["scale"] : 1.0) + (md.has("offset") ? (double)md["offset"] : 0.0);
			if (md.has("min")) {
				v = MAX(v, (double)md["min"]);
			}
			if (md.has("max")) {
				v = MIN(v, (double)md["max"]);
			}
			out[key] = v;
		} else {
			out[key] = raw;
		}
	}
	return out;
}

int VFXBindings::handle(const Dictionary &p_event, const Callable &p_spawn) {
	const String etype = p_event.has("type") ? String(p_event["type"]) : String();
	const HashMap<String, Array>::Iterator it = bindings.find(etype);
	if (!it) {
		return 0;
	}
	Dictionary payload = p_event;
	if (p_event.has("payload") && p_event["payload"].get_type() == Variant::DICTIONARY) {
		payload = p_event["payload"];
	}
	Vector3 pos;
	if (p_event.has("position") && p_event["position"].get_type() == Variant::VECTOR3) {
		pos = p_event["position"];
	} else if (payload.has("position") && payload["position"].get_type() == Variant::VECTOR3) {
		pos = payload["position"];
	}
	int started = 0;
	const Array specs = it->value;
	for (int i = 0; i < specs.size(); i++) {
		if (specs[i].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary spec = specs[i];
		const double min_interval = spec.has("min_interval") ? (double)spec["min_interval"] : 0.0;
		const String effect = spec.has("effect") ? String(spec["effect"]) : (spec.has("sequence") ? String(spec["sequence"]) : String());
		const String key = etype + "/" + effect;
		const HashMap<String, double>::ConstIterator last = last_fire.find(key);
		if (min_interval > 0.0 && last && clock - last->value < min_interval) {
			continue;
		}
		last_fire[key] = clock;
		const Dictionary mapping = spec.has("params") && spec["params"].get_type() == Variant::DICTIONARY ? (Dictionary)spec["params"] : Dictionary();
		const Dictionary params = map_params(mapping, payload);
		const Vector3 offset = spec.has("offset") && spec["offset"].get_type() == Variant::VECTOR3 ? (Vector3)spec["offset"] : Vector3();
		if (spec.has("sequence")) {
			Ref<VFXSequence> seq = make_sequence(String(spec["sequence"]), p_spawn, pos + offset, params);
			if (seq.is_valid()) {
				seq->advance(0.0);
				active.push_back(seq);
				started++;
			}
		}
		if (spec.has("effect") && p_spawn.is_valid()) {
			const Variant args[3] = { String(spec["effect"]), pos + offset, params };
			const Variant *argp[3] = { &args[0], &args[1], &args[2] };
			Variant ret;
			Callable::CallError err;
			p_spawn.callp(argp, 3, ret, err);
			started++;
		}
	}
	return started;
}

int VFXBindings::handle_cue_events(const Array &p_cue_events, const Callable &p_spawn, const Vector3 &p_position) {
	int started = 0;
	for (int i = 0; i < p_cue_events.size(); i++) {
		if (p_cue_events[i].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary cue = p_cue_events[i];
		const String kind = cue.has("event") ? String(cue["event"]) : String("executed");
		if (kind == "updated" || !cue.has("tag")) {
			continue;
		}
		const int repeats = cue.has("count") && _is_num(cue["count"]) ? CLAMP((int)cue["count"], 1, 32) : 1;
		Dictionary payload = cue.duplicate();
		payload["position"] = p_position;
		Dictionary event;
		event["type"] = kind == "stopped" ? String(cue["tag"]) + ":stopped" : String(cue["tag"]);
		event["payload"] = payload;
		event["position"] = p_position;
		for (int r = 0; r < repeats; r++) {
			started += handle(event, p_spawn);
		}
	}
	return started;
}

void VFXBindings::tick(double p_dt) {
	clock += p_dt;
	for (Ref<VFXSequence> &seq : active) {
		seq->advance(p_dt);
	}
	Vector<Ref<VFXSequence>> remaining;
	for (const Ref<VFXSequence> &seq : active) {
		if (!seq->is_finished()) {
			remaining.push_back(seq);
		}
	}
	active = remaining;
}

void VFXBindings::clear() {
	bindings.clear();
	sequences.clear();
	active.clear();
	last_fire.clear();
	clock = 0.0;
}

void VFXBindings::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_binding", "event_type", "spec"), &VFXBindings::register_binding);
	ClassDB::bind_method(D_METHOD("register_sequence", "name", "entries"), &VFXBindings::register_sequence);
	ClassDB::bind_method(D_METHOD("has_binding", "event_type"), &VFXBindings::has_binding);
	ClassDB::bind_method(D_METHOD("get_binding_count"), &VFXBindings::get_binding_count);
	ClassDB::bind_method(D_METHOD("make_sequence", "name", "spawn", "origin", "params"), &VFXBindings::make_sequence, DEFVAL(Vector3()), DEFVAL(Dictionary()));
	ClassDB::bind_static_method("VFXBindings", D_METHOD("map_params", "mapping", "payload"), &VFXBindings::map_params);
	ClassDB::bind_method(D_METHOD("handle", "event", "spawn"), &VFXBindings::handle);
	ClassDB::bind_method(D_METHOD("handle_cue_events", "cue_events", "spawn", "position"), &VFXBindings::handle_cue_events, DEFVAL(Vector3()));
	ClassDB::bind_method(D_METHOD("tick", "dt"), &VFXBindings::tick);
	ClassDB::bind_method(D_METHOD("get_active_sequence_count"), &VFXBindings::get_active_sequence_count);
	ClassDB::bind_method(D_METHOD("get_clock"), &VFXBindings::get_clock);
	ClassDB::bind_method(D_METHOD("clear"), &VFXBindings::clear);
}
