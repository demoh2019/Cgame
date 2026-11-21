/**************************************************************************/
/*  test_cgame_hw_adaptation.h                                            */
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

#include "../cgame_gpu_settings_db.h"
#include "../cgame_thermal_governor.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "tests/test_macros.h"
#include "tests/test_utils.h"

namespace TestCgameHwAdaptation {

static int level_of(const String &p_adapter, const String &p_vendor = "") {
	return CgameGPUSettingsDB::match_adapter(p_adapter, p_vendor)["level"];
}

static void remove_file(const String &p_path) {
	if (FileAccess::exists(p_path)) {
		DirAccess::remove_absolute(p_path);
	}
}

TEST_CASE("[CgameGPUSettingsDB] Adapter matching") {
	CHECK(level_of("Apple M3 Max") == 3);
	CHECK(level_of("Apple M1") == 2);
	CHECK(String(CgameGPUSettingsDB::match_adapter("Apple M2 Pro")["family"]) == "apple_m_pro_max");
	CHECK(level_of("NVIDIA GeForce RTX 4090") == 3);
	CHECK(level_of("NVIDIA GeForce RTX 3060") == 2);
	CHECK(level_of("NVIDIA GeForce GTX 1050 Ti") == 1);
	CHECK(level_of("AMD Radeon RX 7800 XT") == 3);
	CHECK(level_of("AMD Radeon RX 580") == 1);
	CHECK(level_of("Intel(R) Arc(TM) A750 Graphics") == 2);
	CHECK(level_of("Intel(R) Iris(R) Xe Graphics") == 1);
	CHECK(level_of("Intel(R) UHD Graphics 620") == 0);
	CHECK(level_of("Adreno (TM) 740") == 2);
	CHECK(level_of("Mali-G610") == 0);
	CHECK((double)CgameGPUSettingsDB::match_adapter("Adreno (TM) 619")["scale"] < 1.0);
	CHECK(CgameGPUSettingsDB::get_rule_count() > 20);
}

TEST_CASE("[CgameGPUSettingsDB] Unknown adapters fall back safely") {
	const Dictionary unk = CgameGPUSettingsDB::match_adapter("Totally Unknown GPU 9000");
	CHECK(String(unk["source"]) == "fallback");
	CHECK((int)unk["level"] == 1);
	CHECK(level_of("llvmpipe (LLVM 15)") == 0);
	CHECK(level_of("Mystery", "NVIDIA") == 2);
	const Dictionary feats = CgameGPUSettingsDB::features_for(3);
	CHECK(bool(feats["sdfgi"]));
	CHECK_FALSE(bool(CgameGPUSettingsDB::features_for(1)["ssao"]));
	CHECK((int)CgameGPUSettingsDB::features_for(2)["msaa"] == 2);
	CHECK((int)CgameGPUSettingsDB::features_for(99)["shadow_quality"] == CgameGPUSettingsDB::MAX_LEVEL);
}

TEST_CASE("[CgameGPUSettingsDB] Learned data overrides the static heuristic") {
	const String path = TestUtils::get_temp_path("cgame_gpu_learned.json");
	remove_file(path);
	const String adapter = "NVIDIA GeForce RTX 3060";
	CHECK((int)CgameGPUSettingsDB::recommend(adapter, "", 16.6, path)["level"] == 2);
	CHECK(CgameGPUSettingsDB::learn(adapter, 30.0, 2, path));
	CgameGPUSettingsDB::learn(adapter, 28.0, 2, path);
	CgameGPUSettingsDB::learn(adapter, 90.0, 2, path);
	Dictionary rec = CgameGPUSettingsDB::recommend(adapter, "", 16.6, path);
	CHECK(String(rec["source"]) == "learned");
	CHECK((int)rec["level"] == 1); // Slow level-2 medians push the recommendation down (median, not mean).
	CgameGPUSettingsDB::learn(adapter, 8.0, 1, path);
	CgameGPUSettingsDB::learn(adapter, 9.0, 1, path);
	CgameGPUSettingsDB::learn(adapter, 10.0, 1, path);
	rec = CgameGPUSettingsDB::recommend(adapter, "", 16.6, path);
	CHECK((int)rec["level"] == 1); // Level 1 passes, level 2 does not.
	CHECK((int)CgameGPUSettingsDB::recommend("Some Other GPU", "", 16.6, path)["level"] == 1);
	CHECK_FALSE(CgameGPUSettingsDB::learn(adapter, -1.0, 1, path));
	remove_file(path);
}

TEST_CASE("[CgameGPUSettingsDB] Fast measurements allow stepping up one level") {
	const String path = TestUtils::get_temp_path("cgame_gpu_learned_up.json");
	remove_file(path);
	const String adapter = "NVIDIA GeForce RTX 3060";
	CgameGPUSettingsDB::learn(adapter, 5.0, 2, path);
	CgameGPUSettingsDB::learn(adapter, 5.0, 2, path);
	// Level 2 runs at 5 ms (well under 70% of the target) and level 3 is untested: try level 3.
	CHECK((int)CgameGPUSettingsDB::recommend(adapter, "", 16.6, path)["level"] == 3);
	// Once level 3 was measured and is too slow, stay at 2.
	CgameGPUSettingsDB::learn(adapter, 40.0, 3, path);
	CHECK((int)CgameGPUSettingsDB::recommend(adapter, "", 16.6, path)["level"] == 2);
	remove_file(path);
}

TEST_CASE("[CgameThermalGovernor] Hysteresis") {
	Ref<CgameThermalGovernor> g;
	g.instantiate();
	g->configure(60);
	CHECK(g->fps_cap() == 60);
	double now = 0.0;
	for (int i = 0; i < 600; i++) {
		now += 0.03;
		g->sample_frame(30.0, now);
	}
	CHECK(g->quality_step() >= 2); // Sustained slow frames step quality down.
	const int stepped = g->quality_step();
	for (int i = 0; i < 60; i++) {
		now += 0.03;
		g->sample_frame(30.0, now);
	}
	CHECK(g->quality_step() >= stepped); // No recovery while still slow.

	// A brief fast burst must not recover (hysteresis).
	const int burst_start = g->quality_step();
	for (int i = 0; i < 100; i++) {
		now += 0.01;
		g->sample_frame(8.0, now);
	}
	CHECK(g->quality_step() == burst_start);
	for (int i = 0; i < 5000; i++) {
		now += 0.01;
		g->sample_frame(8.0, now);
	}
	CHECK(g->quality_step() == 0); // A long run of headroom recovers fully.
	CHECK(g->apply_to(3) == 3);

	Ref<CgameThermalGovernor> g2;
	g2.instantiate();
	for (int i = 0; i < 2000; i++) {
		now += 0.05;
		g2->sample_frame(40.0, now);
	}
	CHECK(g2->fps_cap() == 30); // Maximum throttling caps at 30 fps.
	CHECK(g2->apply_to(3) == 0);
	CHECK(g2->apply_to(0) == 0); // Quality never goes below zero.
}

TEST_CASE("[CgameThermalGovernor] Sample reports step changes") {
	Ref<CgameThermalGovernor> g;
	g.instantiate();
	g->configure(60);
	double now = 0.0;
	int changes = 0;
	for (int i = 0; i < 600; i++) {
		now += 0.03;
		if (g->sample_frame(30.0, now)) {
			changes++;
		}
	}
	CHECK(changes == g->quality_step());
	g->reset();
	CHECK(g->quality_step() == 0);
}

TEST_CASE("[CgameThermalGovernor] Battery drain") {
	Ref<CgameThermalGovernor> b;
	b.instantiate();
	CHECK(b->drain_per_hour() == doctest::Approx(-1.0));
	b->record_battery(0.0, 80.0, false);
	b->record_battery(1800.0, 75.0, false);
	b->record_battery(3600.0, 70.0, false);
	CHECK(b->drain_per_hour() == doctest::Approx(10.0).epsilon(0.001));
	CHECK(b->hours_remaining() == doctest::Approx(7.0).epsilon(0.001));
	CHECK(b->fps_cap() == 60); // A healthy battery does not cap.
	b->record_battery(3700.0, 15.0, false);
	CHECK(b->fps_cap() == 30); // A low battery caps fps.
	CHECK(b->apply_to(2) == 1); // A low battery steps quality down.
	b->record_battery(3800.0, 16.0, true);
	CHECK(b->drain_per_hour() == doctest::Approx(-1.0));
	CHECK(b->fps_cap() == 60); // Charging lifts the cap.
	CHECK(CgameThermalGovernor::read_system_battery().has("available"));
}

} // namespace TestCgameHwAdaptation
