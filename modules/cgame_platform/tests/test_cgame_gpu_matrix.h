/**************************************************************************/
/*  test_cgame_gpu_matrix.h                                               */
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

#include "../cgame_gpu_matrix_db.h"
#include "../cgame_gpu_settings_db.h"
#include "../cgame_latency_probe.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/image.h"
#include "core/io/json.h"
#include "tests/test_macros.h"
#include "tests/test_utils.h"

namespace TestCgameGpuMatrix {

static const char *H_BASE = "0000000000000000";
static const char *H_NEAR = "000000000000000f";
static const char *H_FAR = "ffffffff00000000";

static Array hashes_of(const char *p_a, const char *p_b = nullptr) {
	Array a;
	a.push_back(String(p_a));
	if (p_b != nullptr) {
		a.push_back(String(p_b));
	}
	return a;
}

static Dictionary run_entry(int p_level, double p_p50, const Array &p_hashes, int p_errors = 0) {
	Dictionary fm;
	fm["avg"] = p_p50;
	fm["p50"] = p_p50;
	fm["p95"] = p_p50 * 1.3;
	fm["p99"] = p_p50 * 1.6;
	fm["max"] = p_p50 * 2.0;
	Dictionary gpu;
	gpu["avg"] = p_p50 * 0.8;
	Dictionary r;
	r["level"] = p_level;
	r["frames"] = 300;
	r["frame_ms"] = fm;
	r["gpu_ms"] = gpu;
	r["pipeline_compiles"] = 3;
	r["checksums"] = p_hashes;
	r["errors"] = p_errors;
	return r;
}

static Dictionary make_report(const String &p_adapter, const String &p_vendor, const String &p_driver, const String &p_renderer, const Array &p_runs) {
	Dictionary sys;
	sys["adapter"] = p_adapter;
	sys["vendor"] = p_vendor;
	sys["driver"] = p_driver;
	sys["os"] = "Windows";
	sys["os_version"] = "11";
	sys["renderer"] = p_renderer;
	Dictionary rep;
	rep["schema"] = 1;
	rep["system"] = sys;
	rep["runs"] = p_runs;
	return rep;
}

static Array good_runs(const char *p_hash, double p_p50) {
	Array runs;
	for (int lv = 0; lv < 4; lv++) {
		runs.push_back(run_entry(lv, p_p50 + (double)lv * 2.0, hashes_of(p_hash, p_hash)));
	}
	return runs;
}

static Ref<CgameGPUMatrixDB> new_db() {
	Ref<CgameGPUMatrixDB> db;
	db.instantiate();
	return db;
}

static Dictionary sample(const char *p_mode, int64_t p_input, int64_t p_draw, int64_t p_pd = -1) {
	Dictionary s;
	s["mode"] = String(p_mode);
	s["input_us"] = p_input;
	s["draw_us"] = p_draw;
	s["photodiode_us"] = p_pd;
	return s;
}

TEST_CASE("[CgameGPUMatrixDB] Report schema validation") {
	const Dictionary ok = make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", good_runs(H_BASE, 5.0));
	CHECK(CgameGPUMatrixDB::validate_report(ok).size() == 0);
	CHECK(CgameGPUMatrixDB::validate_report(String("nope")).size() > 0);

	Dictionary bad_schema = ok.duplicate(true);
	bad_schema["schema"] = 9;
	CHECK(CgameGPUMatrixDB::validate_report(bad_schema).size() > 0);

	Dictionary no_sys = ok.duplicate(true);
	no_sys.erase("system");
	CHECK(CgameGPUMatrixDB::validate_report(no_sys).size() > 0);

	Dictionary bad_hash = ok.duplicate(true);
	Dictionary(Array(bad_hash["runs"])[0])["checksums"] = hashes_of("xyz");
	CHECK(CgameGPUMatrixDB::validate_report(bad_hash).size() > 0);

	Dictionary bad_level = ok.duplicate(true);
	Dictionary(Array(bad_level["runs"])[0])["level"] = 7;
	CHECK(CgameGPUMatrixDB::validate_report(bad_level).size() > 0);

	Ref<CgameGPUMatrixDB> db0 = new_db();
	CHECK_FALSE(db0->add_report(no_sys, "bad.json"));
	CHECK(db0->get_rejected().size() == 1);
	CHECK(db0->add_report(ok));
}

TEST_CASE("[CgameGPUMatrixDB] Perceptual hash") {
	CHECK(CgameGPUMatrixDB::hash_distance(H_BASE, H_NEAR) == 4);
	CHECK(CgameGPUMatrixDB::hash_distance(H_BASE, H_FAR) == 32);
	CHECK(CgameGPUMatrixDB::hash_distance(H_BASE, "abc") == -1);

	Ref<Image> grad = Image::create_empty(64, 64, false, Image::FORMAT_RGB8);
	Ref<Image> inv = Image::create_empty(64, 64, false, Image::FORMAT_RGB8);
	for (int y = 0; y < 64; y++) {
		for (int x = 0; x < 64; x++) {
			const float v = (float)x / 63.0f;
			grad->set_pixel(x, y, Color(v, v, v));
			inv->set_pixel(x, y, Color(1.0f - v, 1.0f - v, 1.0f - v));
		}
	}
	const String hg = CgameGPUMatrixDB::dhash(grad);
	CHECK(hg.length() == 16);
	CHECK(CgameGPUMatrixDB::hash_distance(hg, CgameGPUMatrixDB::dhash(grad)) == 0);
	CHECK(CgameGPUMatrixDB::hash_distance(hg, CgameGPUMatrixDB::dhash(inv)) > 40);
	Ref<Image> empty;
	empty.instantiate();
	CHECK(CgameGPUMatrixDB::dhash(empty) == "");
}

TEST_CASE("[CgameGPUMatrixDB] Matrix aggregation and regression detection") {
	Ref<CgameGPUMatrixDB> db = new_db();
	db->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", good_runs(H_BASE, 5.0)));
	db->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", good_runs(H_NEAR, 7.0)));
	db->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", good_runs(H_BASE, 6.0)));
	db->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "555.0", "vulkan", good_runs(H_FAR, 5.0)));
	db->add_report(make_report("AMD Radeon RX 7800 XT", "AMD", "24.1", "vulkan", good_runs(H_BASE, 6.0)));
	const Array cells = db->cells();
	CHECK(cells.size() == 3);
	Dictionary nv_ok;
	Dictionary nv_bad;
	for (int i = 0; i < cells.size(); i++) {
		const Dictionary c = cells[i];
		if (String(c["vendor"]) == "nvidia" && String(c["driver"]) == "560.1") {
			nv_ok = c;
		} else if (String(c["vendor"]) == "nvidia" && String(c["driver"]) == "555.0") {
			nv_bad = c;
		}
	}
	CHECK((int)nv_ok["reports"] == 3);
	CHECK(String(nv_ok["status"]) == "pass"); // Near-identical frames pass within the tolerance.
	CHECK(String(nv_ok["family"]) == "nvidia_rtx_high");
	CHECK((double)Dictionary(nv_ok["level_p50"])[0] == doctest::Approx(6.0));
	CHECK((int)nv_ok["max_level_60fps"] == 3);
	CHECK(String(nv_bad["status"]) == "fail");

	const Array regs = db->regressions();
	CHECK(regs.size() == 8); // 4 levels x 2 frames for the bad driver.
	CHECK((int)Dictionary(regs[0])["distance"] == 32);

	db->set_tolerance(40);
	db->build();
	CHECK(db->regressions().size() == 0);
	db->set_tolerance(CgameGPUMatrixDB::DEFAULT_TOLERANCE);
	db->set_reference("vulkan", 0, 0, H_FAR);
	db->build();
	CHECK(db->regressions().size() > 0);
}

TEST_CASE("[CgameGPUMatrixDB] Driver failure clustering") {
	Ref<CgameGPUMatrixDB> db2 = new_db();
	for (int i = 0; i < 3; i++) {
		db2->add_report(make_report("NVIDIA GeForce RTX 3060", "NVIDIA", "560.1", "vulkan", good_runs(H_BASE, 6.0)));
	}
	Array broken = good_runs(H_BASE, 6.0);
	Dictionary broken_run = broken[2];
	broken_run["errors"] = 4;
	db2->add_report(make_report("NVIDIA GeForce RTX 3060", "NVIDIA", "555.0", "vulkan", broken));
	db2->add_report(make_report("NVIDIA GeForce RTX 3070", "NVIDIA", "555.0", "vulkan", broken));
	Dictionary crash = make_report("Intel Arc A750", "Intel", "31.0", "d3d12", good_runs(H_BASE, 8.0));
	crash["completed"] = false;
	db2->add_report(crash);

	const Array clusters = db2->driver_failures();
	REQUIRE(clusters.size() == 2);
	Dictionary nv_cluster;
	Dictionary intel;
	for (int i = 0; i < clusters.size(); i++) {
		const Dictionary c = clusters[i];
		if (String(c["vendor"]) == "nvidia") {
			nv_cluster = c;
		} else if (String(c["vendor"]) == "intel") {
			intel = c;
		}
	}
	CHECK(String(nv_cluster["driver"]) == "555.0");
	CHECK((int)nv_cluster["fails"] == 2);
	CHECK(Array(nv_cluster["families"]).size() == 2);
	CHECK(bool(nv_cluster["driver_specific"]));
	CHECK(Dictionary(nv_cluster["reasons"]).has("errors:L2"));
	CHECK_FALSE(bool(intel["driver_specific"]));
	CHECK(Dictionary(intel["reasons"]).has("crash"));
	// Highest failure ratio first (the Intel crash is 1/1 and NVIDIA 555 is 2/2; ties sort by driver).
	CHECK(String(Dictionary(clusters[0])["driver"]) == "31.0");
}

TEST_CASE("[CgameGPUMatrixDB] Learned recommendations feed the settings database") {
	Ref<CgameGPUMatrixDB> db3 = new_db();
	Array rs3;
	for (int lv = 0; lv < 4; lv++) {
		rs3.push_back(run_entry(lv, 4.0 + (double)lv * 3.0, hashes_of(lv == 3 ? H_FAR : H_BASE)));
	}
	db3->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", rs3));
	db3->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", good_runs(H_BASE, 4.0)));
	db3->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", good_runs(H_BASE, 4.0)));
	const Dictionary learned = db3->learned_data();
	REQUIRE(learned.has("nvidia geforce rtx 4070"));
	const Dictionary entry = learned["nvidia geforce rtx 4070"];
	CHECK(Array(entry["0"]).size() == 3);
	const Array l3 = entry["3"];
	CHECK(((double)l3[0] == CgameGPUMatrixDB::BLOCKED_LEVEL_MS || (double)l3[1] == CgameGPUMatrixDB::BLOCKED_LEVEL_MS || (double)l3[2] == CgameGPUMatrixDB::BLOCKED_LEVEL_MS));

	const String path = TestUtils::get_temp_path("cgame_gpu_matrix_learned.json");
	CHECK(db3->write_learned(path));
	Dictionary rec = CgameGPUSettingsDB::recommend("NVIDIA GeForce RTX 4070", "NVIDIA", 16.6, path);
	CHECK(String(rec["source"]) == "learned");
	CHECK((int)rec["level"] == 3); // The median across reports still allows level 3 with one blocked report.

	Ref<CgameGPUMatrixDB> db4 = new_db();
	db4->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", rs3));
	db4->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", rs3));
	db4->write_learned(path);
	CHECK((int)CgameGPUSettingsDB::recommend("NVIDIA GeForce RTX 4070", "NVIDIA", 16.6, path)["level"] == 3);
	DirAccess::remove_absolute(path);
}

TEST_CASE("[CgameGPUMatrixDB] Export formats") {
	Ref<CgameGPUMatrixDB> db = new_db();
	db->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", good_runs(H_BASE, 5.0)));
	db->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "555.0", "vulkan", good_runs(H_FAR, 5.0)));
	db->add_report(make_report("NVIDIA GeForce RTX 4070", "NVIDIA", "560.1", "vulkan", good_runs(H_BASE, 7.0)));
	const String md = db->to_markdown();
	CHECK(md.contains("# GPU compatibility matrix"));
	CHECK(md.contains("| nvidia | nvidia_rtx_high | 560.1 | vulkan |"));
	CHECK(md.contains("## Rendering regressions"));
	CHECK(md.contains("(driver-specific)"));

	const String csv = db->to_csv();
	const Vector<String> lines = csv.strip_edges().split("\n");
	CHECK(lines.size() == db->cells().size() + 1);
	CHECK(lines[0].begins_with("vendor,family,driver,renderer"));
	CHECK(lines[1].split(",").size() >= 15);
	CHECK(CgameGPUMatrixDB::csv_escape("a,b") == "\"a,b\"");
	CHECK(CgameGPUMatrixDB::csv_escape("say \"hi\"") == "\"say \"\"hi\"\"\"");
	CHECK(CgameGPUMatrixDB::csv_escape("plain") == "plain");
}

TEST_CASE("[CgameLatencyProbe] Statistics and photodiode pairing") {
	Array s;
	for (int i = 0; i < 5; i++) {
		s.push_back(sample("normal", (int64_t)i * 100000, (int64_t)i * 100000 + 20000 + (int64_t)i * 1000));
	}
	for (int i = 0; i < 5; i++) {
		s.push_back(sample("framegen", 1000000 + (int64_t)i * 100000, 1000000 + (int64_t)i * 100000 + 30000));
	}
	s.push_back(sample("normal", 9000000, -1));

	const Dictionary stats = CgameLatencyProbe::summarize(s, 8.0);
	CHECK(stats.size() == 2); // Two modes reported, the incomplete sample is dropped.
	const Dictionary n = stats["normal"];
	CHECK((int)n["count"] == 5);
	CHECK((double)n["min"] == doctest::Approx(28.0));
	CHECK((double)n["p50"] == doctest::Approx(30.0));
	CHECK((double)n["max"] == doctest::Approx(32.0));
	CHECK((double)n["avg"] == doctest::Approx(30.0));
	CHECK((double)n["p95"] == doctest::Approx(31.8));
	CHECK(String(n["source"]) == "software");
	const Dictionary fg = stats["framegen"];
	CHECK((double)fg["jitter"] == doctest::Approx(0.0).epsilon(0.001));
	CHECK((double)fg["p50"] - (double)n["p50"] == doctest::Approx(8.0));

	PackedFloat64Array sorted;
	for (int i = 1; i <= 5; i++) {
		sorted.push_back((double)i);
	}
	CHECK(CgameLatencyProbe::percentile(sorted, 50.0) == doctest::Approx(3.0));
	CHECK(CgameLatencyProbe::percentile(sorted, 0.0) == doctest::Approx(1.0));
	CHECK(CgameLatencyProbe::percentile(sorted, 100.0) == doctest::Approx(5.0));
	CHECK(CgameLatencyProbe::percentile(PackedFloat64Array(), 50.0) == doctest::Approx(0.0));

	PackedInt64Array edges;
	edges.push_back(45000);
	edges.push_back(100000 + 52000);
	edges.push_back(4000000);
	CHECK(CgameLatencyProbe::pair_photodiode(s, edges, 0) == 2); // An edge far from any input stays unpaired.
	CHECK((int64_t)Dictionary(s[0])["photodiode_us"] == 45000);
	CHECK(CgameLatencyProbe::latency_ms(s[0], 8.0) == doctest::Approx(45.0));
	const Dictionary stats2 = CgameLatencyProbe::summarize(s, 8.0);
	CHECK(String(Dictionary(stats2["normal"])["source"]) == "mixed");
}

TEST_CASE("[CgameLatencyProbe] Probe records inputs, throttles and completes on draw") {
	Ref<CgameLatencyProbe> p;
	p.instantiate();
	p->set_mode("framegen");
	CHECK(p->mark_input(1000000) == 0);
	CHECK(p->mark_input(1010000) == -1); // Throttled by min_gap_ms.
	CHECK(p->is_flash_on());
	CHECK(p->mark_draw(1016000) == 1);
	CHECK(p->mark_input(1200000) == 1);
	CHECK(p->mark_draw(1210000) == 1);
	const Array samples = p->get_samples();
	REQUIRE(samples.size() == 2);
	CHECK(String(Dictionary(samples[0])["mode"]) == "framegen");
	CHECK(CgameLatencyProbe::latency_ms(samples[0], 0.0) == doctest::Approx(16.0));
	const Dictionary rep = p->report(60.0);
	CHECK(Dictionary(rep["framegen"]).has("p50"));
	CHECK((double)rep["refresh_hz"] == doctest::Approx(60.0));
	CHECK(p->estimate_display_ms(60.0) == doctest::Approx(500.0 / 60.0));
	p->set_display_offset_ms(10.0);
	CHECK(p->estimate_display_ms(60.0) == doctest::Approx(500.0 / 60.0 + 10.0));
}

} // namespace TestCgameGpuMatrix
