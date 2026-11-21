/**************************************************************************/
/*  audio_voice_admission_planner.cpp                                              */
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

#include "audio_voice_admission_planner.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/vector.h"

void AudioVoiceAdmissionPlanner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("select_victim", "voices", "name", "new_db",
			"new_priority", "max_voices", "same_sound_max"),
			&AudioVoiceAdmissionPlanner::select_victim, DEFVAL(24), DEFVAL(5));
}

int AudioVoiceAdmissionPlanner::select_victim(const Array &p_voices,
		const String &p_new_name, double p_new_db, int p_new_priority,
		int p_max_voices, int p_same_sound_max) const {
	if (p_new_name.is_empty() || !Math::is_finite(p_new_db) ||
			p_new_priority < 0 || p_new_priority > 3 ||
			p_max_voices < 1 || p_max_voices > 128 ||
			p_same_sound_max < 1 || p_same_sound_max > p_max_voices ||
			p_voices.size() > 128) {
		return DROP_NEW;
	}
	struct Voice {
		String name;
		double db = 0.0;
		double age = 0.0;
		int priority = 0;
	};
	Vector<Voice> voices;
	Vector<int> same_sound;
	for (int i = 0; i < p_voices.size(); i++) {
		if (p_voices[i].get_type() != Variant::DICTIONARY) {
			return DROP_NEW;
		}
		Dictionary d = p_voices[i];
		if (!d.has("name") || !d.has("audibility") || !d.has("age")) {
			return DROP_NEW;
		}
		const Variant n = d["name"], db = d["audibility"], age = d["age"];
		const Variant priority = d.get("priority", 0);
		if (n.get_type() != Variant::STRING ||
				(db.get_type() != Variant::FLOAT && db.get_type() != Variant::INT) ||
				(age.get_type() != Variant::FLOAT && age.get_type() != Variant::INT) ||
				(priority.get_type() != Variant::INT && priority.get_type() != Variant::FLOAT)) {
			return DROP_NEW;
		}
		Voice v;
		v.name = n;
		v.db = double(db);
		v.age = double(age);
		v.priority = int(priority);
		if (v.name.is_empty() || !Math::is_finite(v.db) ||
				!Math::is_finite(v.age) || v.age < 0.0 ||
				v.priority < 0 || v.priority > 3) {
			return DROP_NEW;
		}
		voices.push_back(v);
		if (v.name == p_new_name) {
			same_sound.push_back(i);
		}
	}
	if (same_sound.size() < p_same_sound_max && voices.size() < p_max_voices) {
		return ROOM;
	}
	Vector<int> candidates;
	if (same_sound.size() >= p_same_sound_max) {
		candidates = same_sound;
	} else {
		for (int i = 0; i < voices.size(); i++) {
			candidates.push_back(i);
		}
	}
	if (candidates.is_empty()) {
		return DROP_NEW;
	}
	int victim = candidates[0];
	for (const int id : candidates) {
		const Voice &a = voices[id], &b = voices[victim];
		if (a.priority < b.priority ||
				(a.priority == b.priority && (
						(Math::abs(a.db - b.db) < 0.5 && a.age > b.age) ||
						(Math::abs(a.db - b.db) >= 0.5 && a.db < b.db)))) {
			victim = id;
		}
	}
	if (p_new_priority < voices[victim].priority ||
			(p_new_priority == voices[victim].priority &&
					voices[victim].db > p_new_db + 3.0)) {
		return DROP_NEW;
	}
	return victim;
}
