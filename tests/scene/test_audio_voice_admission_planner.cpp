/**************************************************************************/
/*  test_audio_voice_admission_planner.cpp                                              */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_audio_voice_admission_planner)

#include "scene/main/audio_voice_admission_planner.h"
#include "core/math/math_funcs.h"

namespace TestAudioVoiceAdmissionPlanner {

static Dictionary voice(const String &p_name, double p_db, double p_age, int p_priority = 0) {
	Dictionary d;
	d["name"] = p_name;
	d["audibility"] = p_db;
	d["age"] = p_age;
	d["priority"] = p_priority;
	return d;
}

TEST_CASE("[AudioVoiceAdmissionPlanner] Global pressure protects combat importance") {
	Ref<AudioVoiceAdmissionPlanner> planner;
	planner.instantiate();
	Array all;
	CHECK(planner->select_victim(all, "hit", -10.0, 2) == AudioVoiceAdmissionPlanner::ROOM);
	all.push_back(voice("boss", -70.0, 1.0, 3));
	all.push_back(voice("wind", -10.0, 4.0, 0));
	all.push_back(voice("wind", -7.0, 2.0, 0));
	CHECK(planner->select_victim(all, "hit", -90.0, 2, 3, 2) == 1);
	CHECK(planner->select_victim(all, "wind", -100.0, 0, 3, 2) == AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim(all, "boss", -10.0, 3, 3, 2) == 1);
	CHECK(planner->select_victim(all, "hit", -80.0, 0, 3, 2) == AudioVoiceAdmissionPlanner::DROP_NEW);
}

TEST_CASE("[AudioVoiceAdmissionPlanner] Same-sound caps and original quietest-age semantics") {
	Ref<AudioVoiceAdmissionPlanner> planner;
	planner.instantiate();
	Array all;
	all.push_back(voice("hit", -10.0, 1.0));
	all.push_back(voice("hit", -10.0, 4.0));
	CHECK(planner->select_victim(all, "hit", -10.0, 0, 24, 2) == 1);
	CHECK(planner->select_victim(all, "other", -10.0, 0, 24, 2) == AudioVoiceAdmissionPlanner::ROOM);
	CHECK(planner->select_victim(all, "hit", -90.0, 0, 24, 2) == AudioVoiceAdmissionPlanner::DROP_NEW);
	all.clear();
	for (int i = 0; i < 24; i++) {
		all.push_back(voice(String("s") + itos(i), -10.0 - i, double(i)));
	}
	CHECK(planner->select_victim(all, "new", -10.0, 0) == 23);
	CHECK(planner->select_victim(all, "new", -80.0, 0) == AudioVoiceAdmissionPlanner::DROP_NEW);
}

TEST_CASE("[AudioVoiceAdmissionPlanner] Malformed data never stops an existing sound") {
	Ref<AudioVoiceAdmissionPlanner> planner;
	planner.instantiate();
	Array all;
	all.push_back(voice("hit", -5.0, 1.0, 1));
	CHECK(planner->select_victim(all, "", -10.0, 1, 1, 1) == AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim(all, "hit", Math::NaN, 1, 1, 1) == AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim(all, "hit", -10.0, -1, 1, 1) == AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim(all, "hit", -10.0, 4, 1, 1) == AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim(all, "hit", -10.0, 1, 0, 1) == AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim(all, "hit", -10.0, 1, 24, 0) == AudioVoiceAdmissionPlanner::DROP_NEW);
	all.push_back(voice("other", Math::INF, 0.0));
	CHECK(planner->select_victim(all, "hit", -10.0, 1) == AudioVoiceAdmissionPlanner::DROP_NEW);
	all.clear();
	all.push_back(voice("hit", -5.0, 0.0));
	all[0] = voice("hit", -5.0, 0.0, 2);
	CHECK(planner->select_victim(all, "hit", -10.0, 1, 1, 1) == AudioVoiceAdmissionPlanner::DROP_NEW);
	all.clear();
	all.push_back(voice("hit", -5.0, -1.0));
	CHECK(planner->select_victim(all, "hit", -10.0, 1) == AudioVoiceAdmissionPlanner::DROP_NEW);
}

TEST_CASE("[AudioVoiceAdmissionPlanner] Fresh equal-priority voices hold their initial attack") {
	Ref<AudioVoiceAdmissionPlanner> planner;
	planner.instantiate();
	Array voices;
	voices.push_back(voice("shot", -30.0, 0.02, 2));
	CHECK(planner->select_victim(voices, "shot", -28.0, 2, 1, 1) == 0);
	CHECK(planner->select_victim_stable(voices, "shot", -28.0, 2, 1, 1) ==
			AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim_stable(voices, "shot", -18.0, 2, 1, 1) == 0);
	CHECK(planner->select_victim_stable(voices, "kill", -90.0, 3, 1, 1) == 0);
	CHECK(planner->select_victim_stable(voices, "step", -5.0, 1, 1, 1) ==
			AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim_stable(voices, "new", -25.0, 2, 2, 1) ==
			AudioVoiceAdmissionPlanner::ROOM);
	CHECK(planner->select_victim_stable(voices, "shot", -28.0, 2, 1, 1, 0.0) ==
			planner->select_victim(voices, "shot", -28.0, 2, 1, 1));
	voices.clear();
	voices.push_back(voice("shot", -30.0, 0.12, 2));
	CHECK(planner->select_victim_stable(voices, "shot", -28.0, 2, 1, 1) == 0);
	voices.clear();
	voices.push_back(voice("shot", -30.0, 0.02, 2));
	voices.push_back(voice("shot", -27.0, 0.5, 2));
	CHECK(planner->select_victim_stable(voices, "shot", -25.0, 2, 3, 2) == 1);
	CHECK(planner->select_victim_stable(voices, "shot", -25.0, 2, 3, 2, -1.0) ==
			AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim_stable(voices, "shot", -25.0, 2, 3, 2, 6.0) ==
			AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim_stable(voices, "shot", -25.0, 2, 3, 2, Math::INF) ==
			AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim_stable(voices, "shot", -25.0, 2, 3, 2, 0.1, Math::NaN) ==
			AudioVoiceAdmissionPlanner::DROP_NEW);
	CHECK(planner->select_victim_stable(voices, "shot", -25.0, 2, 3, 2, 0.1, 61.0) ==
			AudioVoiceAdmissionPlanner::DROP_NEW);
}

} // namespace TestAudioVoiceAdmissionPlanner
